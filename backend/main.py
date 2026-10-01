"""Godot4GUI 后端：WebSocket 数据服务。

与前端 NetClient（GDScript Autoload）通过 JSON 文本帧通信，提供两路数据：

1. **Rayleigh-Sommerfeld 衍射模拟**（主力演示，见 `backend/rayleigh_sommerfeld.py`）
   前端发 `rs_start` 指定参数，后端**每算出一个距离就推一列数据**（`rs_col`），
   前端边收边画，逐个 z 刷新伪彩图；`rs_stop` 可随时中断。
   另外提供 `rs_params`：把参数文件（.json 或 .py，例如作业脚本本身）拖进前端后，
   后端只解析其中的字面量常量、不执行文件，回读成参数字典。

2. **通用示例数据流**（`start` / `stop`）——正弦+噪声采样点，用于 TrendChart 演示。

启动：
    pip install -r requirements.txt
    python backend/main.py                # 默认 127.0.0.1:8765
    python backend/main.py --port 9000    # 换端口（端口被占用时）
    python backend/main.py --log-file x.log   # 同时把日志写进文件

多客户端与生命周期：**每个前端连接是一个独立 Session**，所以多个前端可以同时连着，
互不干扰（各自跑各自的模拟）。后端会向所有客户端广播 `{"type":"clients","count":N}`。
加了 `--exit-with-last-client`（前端自动拉起时会传）后，最后一个客户端断开再等
`--linger-sec` 秒仍无人连接，后端就自己退出 —— 这样「前端 A 退出」不会连带把
「前端 B 正在用的后端」杀掉，也兜住了前端被强杀时的孤儿进程。

也可以由前端自动拉起（见 `scripts/autoload/backend_launcher.gd` 与 project.godot 的
`[backend]` 段）。那种情况下本进程是**脱离进程**、stdout 没人接，所以前端会传
`--log-file` —— 「后端起不来」时前端唯一能拿到的线索就是它。
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import datetime
import json
import math
import os
import random
import sys
import time

import numpy as np
import websockets
from websockets.exceptions import ConnectionClosed

from rayleigh_sommerfeld import Config as RSConfig, Simulation, load_params

HOST = "127.0.0.1"
DEFAULT_PORT = 8765
SERVER_NAME = "godot4gui-backend"
BACKEND_VERSION = "1.2"
MAX_LOG_BYTES = 2 * 1024 * 1024     # 日志超过这个大小就轮转一次，避免长期运行无限膨胀
DEFAULT_LINGER_SEC = 5.0            # 最后一个客户端断开后，等这么久还没人来就连自己一起收掉

_log_handle = None

# ---- 客户端与生命周期 ----
# 每个前端连接是一个独立的 Session（互不共享状态），所以「多个前端同时开着」本身是安全的。
# 真正需要管的是**进程归属**：前端 A 退出时不该把前端 B 正在用的后端一起带走。
# 于是这里做两件事：
#   1. 广播在线客户端数 —— 前端据此决定「我是不是最后一个，能不能收进程」；
#   2. 可选地「最后一个客户端走后再等一会儿就自己退出」—— 这条兜住前端被强杀
#      （`taskkill /F`，来不及跑 `_exit_tree`）的情况，否则后端会变成孤儿进程占着端口。
_clients: "set[Session]" = set()
_had_client = False
_exit_with_last_client = False
_linger_sec = DEFAULT_LINGER_SEC
# 「一个客户端都没等到」的兜底时长。前端拉起后端后可能在它监听之前就退出了
# （用户开了就关、启动失败、被强杀），那种情况下后端**永远不会**收到
# 「最后一个客户端断开」，光靠 linger 是收不掉的 —— 会变成孤儿进程占着端口。
# 给足前端连接的时间（前端自己的等待上限是 25s），超了就当没人要这个后端。
DEFAULT_NO_CLIENT_TIMEOUT_SEC = 60.0
_no_client_timeout = DEFAULT_NO_CLIENT_TIMEOUT_SEC
_linger_task: "asyncio.Task | None" = None
_shutdown: "asyncio.Event | None" = None


# ---------------------------------------------------------------- 日志

def log(message: str = "") -> None:
    """打印，并在 `--log-file` 生效时同时追加到文件。

    前端用 `OS.create_process` 拉起后端时，后端是脱离进程：stdout 没有终端接收，
    「后端起不来」时前端拿不到任何线索。所以这层 tee 不是锦上添花 ——
    `BackendLauncher` 失败时读到的那段日志尾巴就来自它。
    """
    print(message, flush=True)
    if _log_handle is not None:
        try:
            _log_handle.write(message + "\n")
            _log_handle.flush()
        except OSError:
            pass        # 日志写不进去不该影响后端干活


def open_log_file(path: str) -> None:
    """打开日志文件（追加）。文件过大时先轮转，防止长期运行把磁盘写满。"""
    global _log_handle
    if not path:
        return
    try:
        parent = os.path.dirname(os.path.abspath(path))
        if parent:
            os.makedirs(parent, exist_ok=True)
        if os.path.isfile(path) and os.path.getsize(path) > MAX_LOG_BYTES:
            os.replace(path, path + ".old")
        _log_handle = open(path, "a", encoding="utf-8", buffering=1)
    except OSError as exc:
        print(f"[backend] 无法写入日志文件 {path}：{exc}", file=sys.stderr)


def close_log_file() -> None:
    global _log_handle
    if _log_handle is not None:
        try:
            _log_handle.close()
        except OSError:
            pass
        _log_handle = None


class Session:
    """一个前端连接的会话状态（数据流开关 + 正在跑的衍射模拟）。"""

    def __init__(self, websocket):
        self.ws = websocket
        self.streaming = False        # 通用示例数据流开关
        self.x = 0.0
        self.rs_task: asyncio.Task | None = None
        self.rs_cancel: asyncio.Event | None = None

    # ---- 发送 ----
    async def send(self, payload: dict) -> None:
        await self.ws.send(json.dumps(payload, ensure_ascii=False))

    # ---- 通用示例数据流 ----
    async def sample_loop(self) -> None:
        """模拟一路传感器：正弦 + 噪声，映射到 0..100（喂 TrendChart）。"""
        while True:
            if self.streaming:
                y = 50.0 + 40.0 * math.sin(self.x / 20.0) + random.uniform(-3.0, 3.0)
                await self.send({"type": "sample", "x": round(self.x, 1), "y": round(y, 3)})
                self.x += 1.0
            await asyncio.sleep(0.05)

    # ---- Rayleigh-Sommerfeld 衍射模拟 ----
    async def stop_simulation(self) -> None:
        if self.rs_task is None:
            return
        if self.rs_cancel is not None:
            self.rs_cancel.set()
        try:
            await self.rs_task
        except asyncio.CancelledError:
            pass
        self.rs_task = None
        self.rs_cancel = None

    async def start_simulation(self, params: dict) -> None:
        await self.stop_simulation()

        cfg = RSConfig.from_dict(params)
        sim = Simulation(cfg)
        total = sim.columns
        await self.send({
            "type": "rs_begin",
            "columns": total,
            "rows": sim.rows,
            "z0": float(sim.z_values[0]),
            "z1": float(sim.z_values[-1]),
            "y0": float(sim.y_values[0]),
            "y1": float(sim.y_values[-1]),
            "params": cfg.as_dict(),
        })
        log(f"[backend] 衍射模拟开始：N={cfg.samples} 列数={total} "
              f"λ={cfg.lamda:g}m D={cfg.diameter:g}m L={cfg.width:g}m")

        cancel = asyncio.Event()
        self.rs_cancel = cancel
        self.rs_task = asyncio.create_task(self._simulation_loop(sim, total, cancel))

    async def _simulation_loop(self, sim: Simulation, total: int, cancel: asyncio.Event) -> None:
        loop = asyncio.get_running_loop()
        started = time.perf_counter()
        vmax = 0.0
        done = 0
        failed = False
        try:
            for index in range(total):
                if cancel.is_set():
                    break
                # FFT 是 CPU 密集的，丢到线程池里跑（numpy 在 FFT 期间会释放 GIL），
                # 既不阻塞事件循环，也让 rs_stop 能在两列之间及时生效。
                z, row, peak = await loop.run_in_executor(None, sim.column, index)
                vmax = max(vmax, peak)
                payload = base64.b64encode(
                    np.ascontiguousarray(row, dtype=np.float32).tobytes()).decode("ascii")
                await self.send({
                    "type": "rs_col",
                    "i": index,
                    "z": z,
                    "vmax": vmax,          # 目前为止的全局最大值（前端据此在线归一化）
                    "data": payload,       # float32 小端字节的 base64
                })
                await self.send({"type": "progress", "value": 100.0 * (index + 1) / total})
                done = index + 1
        except ConnectionClosed:
            pass   # 前端已断开，没人可通知了，安静收尾
        except Exception as exc:                      # noqa: BLE001 —— 报给前端而不是静默失败
            failed = True
            log(f"[backend] 衍射模拟出错：{type(exc).__name__}: {exc}")
            await self.send({"type": "rs_error", "message": f"{type(exc).__name__}: {exc}"})
        finally:
            elapsed = time.perf_counter() - started
            log(f"[backend] 衍射模拟结束：{done}/{total} 列，用时 {elapsed:.1f}s")
            try:
                await self.send({
                    "type": "rs_done",
                    "columns": done,
                    "elapsed": elapsed,
                    "cancelled": cancel.is_set(),
                    # 出错时也要发 rs_done（前端要借此收尾），但必须带上 error，
                    # 否则前端会把这个「结束」当成「算完了」而把错误信息覆盖掉。
                    "error": failed,
                })
            except (ConnectionClosed, RuntimeError, asyncio.CancelledError):
                pass   # 前端已断开 / 正在收尾，收尾消息送不出去属正常

    # ---- 参数文件回读 ----
    async def read_params(self, path: str) -> None:
        try:
            params = await asyncio.to_thread(load_params, path)
            await self.send({"type": "rs_params", "ok": True, "params": params})
        except Exception as exc:                      # noqa: BLE001
            await self.send({"type": "rs_params", "ok": False,
                             "path": path, "message": f"{type(exc).__name__}: {exc}"})

    # ---- 命令分发 ----
    async def handle(self, msg: dict) -> None:
        kind = msg.get("type")
        if kind == "hello":
            # 回一条 hello_ack：前端据此确认「这个端口上跑的就是我们的后端」，
            # 而不是撞上了别的程序占着同一个端口（见 backend_launcher.gd 的 _verified）。
            log("[backend] 收到 hello")
            await self.send({"type": "hello_ack", "server": SERVER_NAME,
                             "version": BACKEND_VERSION, "clients": len(_clients)})
            return
        if kind != "command":
            return

        cmd = msg.get("cmd")
        args = msg.get("args") or {}
        if cmd == "start":
            self.streaming = True
            log("[backend] 启动采集")
        elif cmd in ("stop", "estop"):
            self.streaming = False
            log("[backend] 停止采集")
        elif cmd == "rs_start":
            await self.start_simulation(args)
        elif cmd == "rs_stop":
            await self.stop_simulation()
        elif cmd == "rs_params":
            await self.read_params(str(args.get("path", "")))
        await self.send({"type": "ack", "id": msg.get("id"), "cmd": cmd})


async def broadcast(payload: dict) -> None:
    """把一条消息发给所有在线客户端（断开的跳过，不影响别人）。

    目前只用来广播在线客户端数 —— 前端靠它判断「我退出时能不能把后端进程一起收掉」。
    """
    for session in list(_clients):
        try:
            await session.send(payload)
        except (ConnectionClosed, RuntimeError):
            pass        # 正好断了：它自己的 finally 会做清理


async def _client_count_changed() -> None:
    await broadcast({"type": "clients", "count": len(_clients)})


def _schedule_linger_exit() -> None:
    """最后一个客户端走了：起一个「宽限期」计时，到期还没人来就自己退出。

    这条**不是可选的美化**：前端被 `taskkill /F` 掉时 `_exit_tree` 根本没机会跑，
    没有它后端就会一直占着端口当孤儿进程（模板的已知限制之一）。
    """
    global _linger_task
    if not _exit_with_last_client:
        return
    if _linger_task is not None and not _linger_task.done():
        return
    _linger_task = asyncio.create_task(_linger_then_exit())


async def _linger_then_exit() -> None:
    log(f"[backend] 最后一个客户端已断开，{_linger_sec:g} 秒内没人连进来就退出")
    try:
        await asyncio.sleep(_linger_sec)
    except asyncio.CancelledError:
        return
    if _clients:
        return
    log("[backend] 空闲超时，后端退出（下次前端启动时会自动拉起）")
    if _shutdown is not None:
        _shutdown.set()


def _cancel_linger() -> None:
    global _linger_task
    if _linger_task is not None and not _linger_task.done():
        _linger_task.cancel()
    _linger_task = None


async def _watch_for_first_client() -> None:
    """`--exit-with-last-client` 的配套兜底：等这么久还没人来，就当没人要，自己退。

    没有它的话，「前端把后端拉起来、还没连上就被关掉/强杀」会让后端**永远**留着
    （`_schedule_linger_exit()` 只有在「有过客户端、又都走了」时才会被调到）。
    """
    try:
        await asyncio.sleep(_no_client_timeout)
    except asyncio.CancelledError:
        return
    if _had_client or _clients:
        return
    log(f"[backend] 启动后 {_no_client_timeout:g} 秒内没有客户端连进来，退出")
    if _shutdown is not None:
        _shutdown.set()


async def handler(websocket):
    global _had_client
    log(f"[backend] 客户端接入 {websocket.remote_address}")
    session = Session(websocket)
    _clients.add(session)
    _had_client = True
    _cancel_linger()                 # 宽限期内有人连进来了，取消退出
    producer = asyncio.create_task(session.sample_loop())
    await _client_count_changed()
    try:
        async for raw in websocket:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                log(f"[backend] 收到非 JSON 消息：{raw[:120]!r}")
                continue
            if isinstance(msg, dict):
                await session.handle(msg)
    except ConnectionClosed:
        log("[backend] 客户端断开")
    finally:
        producer.cancel()
        await session.stop_simulation()
        _clients.discard(session)
        await _client_count_changed()
        if not _clients:
            _schedule_linger_exit()


async def main(host: str, port: int) -> None:
    global _shutdown
    _shutdown = asyncio.Event()
    try:
        async with websockets.serve(handler, host, port):
            log(f"[backend] 监听 ws://{host}:{port}（Ctrl+C 停止）"
                  + ("，最后一个客户端断开后自动退出" if _exit_with_last_client else ""))
            if _exit_with_last_client:
                asyncio.create_task(_watch_for_first_client())
            # 默认一直运行到 Ctrl+C；开了 --exit-with-last-client 时，
            # 空闲超时（或一个客户端都没等到）会 set() 这个事件，于是这里返回、
            # serve 关闭、进程退出。
            await _shutdown.wait()
    except OSError as exc:
        # 端口被占用（Windows 常见 WinError 10048）等启动失败
        log(f"[backend] 启动失败：无法监听 ws://{host}:{port}（端口被占用）")
        log(f"        原始错误：{exc}")
        log()
        log("  排查与解决：")
        log(f"    1) 已有实例在跑 —— 找到并结束占用该端口的进程：")
        log(f"         netstat -ano | findstr :{port}     # 看最后一列 PID")
        log(f"         taskkill /F /PID <pid>            # 结束该进程")
        log(f"    2) 端口被其它程序占用 —— 换一个端口：")
        log(f"         python backend/main.py --port {port + 1}")
        log(f"    3) 刚关闭又立刻重启 —— 稍等几秒，等系统释放 TIME_WAIT 状态")
        sys.exit(1)
    log("[backend] 已停止")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Godot4GUI 后端 WebSocket 数据服务")
    ap.add_argument("--host", default=HOST, help=f"监听地址（默认 {HOST}）")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT,
                    help=f"监听端口（默认 {DEFAULT_PORT}）")
    ap.add_argument("--log-file", default="", metavar="PATH",
                    help="把日志同时写进这个文件（前端自动拉起时会传，便于排查启动失败）")
    ap.add_argument("--exit-with-last-client", action="store_true",
                    help="最后一个客户端断开后再等 --linger-sec 秒就退出（前端自动拉起时会传）。"
                         "手动直跑时不加这个参数，行为与从前一致：一直运行到 Ctrl+C")
    ap.add_argument("--linger-sec", type=float, default=DEFAULT_LINGER_SEC,
                    help=f"配合 --exit-with-last-client 的宽限秒数（默认 {DEFAULT_LINGER_SEC:g}）")
    ap.add_argument("--no-client-timeout", type=float, default=DEFAULT_NO_CLIENT_TIMEOUT_SEC,
                    help="配合 --exit-with-last-client：启动后这么久还没有任何客户端连接就退出"
                         f"（默认 {DEFAULT_NO_CLIENT_TIMEOUT_SEC:g}s），兜住「前端把后端起起来、"
                         "还没连上就被关掉」留下的孤儿进程")
    args = ap.parse_args()

    # 这里是模块级代码（不在函数里），直接赋值即写到模块全局，不需要 global 声明。
    _exit_with_last_client = args.exit_with_last_client
    _linger_sec = max(args.linger_sec, 0.0)
    _no_client_timeout = max(args.no_client_timeout, 0.0)

    open_log_file(args.log_file)
    if args.log_file:
        log(f"\n===== {datetime.datetime.now():%Y-%m-%d %H:%M:%S} "
            f"backend v{BACKEND_VERSION} 启动（pid={os.getpid()}）=====")
    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        log("\n[backend] 收到 Ctrl+C，正在退出…")
    finally:
        close_log_file()
