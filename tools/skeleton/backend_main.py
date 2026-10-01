"""{{PROJECT_TITLE}} —— WebSocket 后端骨架。

与 Godot 前端（`scripts/autoload/net_client.gd` 单例 NetClient）通过 JSON 文本帧通信。
本文件是可运行的**最小骨架**：前端点「启动采集」后按 50ms 周期推正弦采样点，
把「前端命令 → 后端处理 → 后端推数据 → 前端刷新」这条链路先跑通。

启动：
    pip install -r requirements.txt
    python backend/main.py                 # 默认 127.0.0.1:8765
    python backend/main.py --port 9000     # 换端口（端口被占用时）
    python backend/main.py --log-file x.log   # 同时把日志写进文件

通常**不用手动启动**：前端连不上时会由 `BackendLauncher` 自动拉起本文件
（它读 project.godot 的 `[backend]` 段，并传 `--host/--port/--log-file/--exit-with-last-client`）。
所以下面这几个参数**不要删**，删了自动拉起就会失败（argparse 会报 unrecognized arguments）。

多客户端与生命周期：**每个前端连接是一个独立 Session**，多个前端可以同时开着、互不干扰；
后端向所有客户端广播 `{"type":"clients","count":N}`。带 `--exit-with-last-client` 启动时
（前端自动拉起就是这么传的），最后一个客户端断开再等 `--linger-sec` 秒无人连接就自己退出 ——
这样「前端 A 退出」不会连带杀掉「前端 B 正在用的后端」；`--no-client-timeout` 再兜一层
「前端把后端起起来、还没连上就被关掉」的孤儿进程。

往这里加你的业务，只有两个动作：
    1) **加命令**：在 `Session.handle()` 的 `elif` 链里加分支（见 `_example_command`）；
    2) **加数据流**：照 `Session.sample_loop()` 写一个 async 循环，
       用 `await self.send({...})` 推消息即可；CPU 密集的活儿丢
       `loop.run_in_executor(None, blocking_fn, args)`，别卡住事件循环。
"""

from __future__ import annotations

import argparse
import asyncio
import datetime
import json
import math
import os
import random
import sys
import time

import websockets
from websockets.exceptions import ConnectionClosed

HOST = "127.0.0.1"
DEFAULT_PORT = 8765
SERVER_NAME = "{{PROJECT_NAME}}-backend"
BACKEND_VERSION = "1.1"
MAX_LOG_BYTES = 2 * 1024 * 1024
DEFAULT_LINGER_SEC = 5.0            # 最后一个客户端断开后，等这么久还没人来就连自己一起收掉
DEFAULT_NO_CLIENT_TIMEOUT_SEC = 60.0  # 启动后这么久一个客户端都没来，就当没人要，自己退

_log_handle = None

# ---- 客户端与生命周期 ----
# **每个前端连接是一个独立的 Session**，所以多个前端可以同时开着、互不共享状态。
# 这里管的是**进程归属**：前端 A 退出时不该把前端 B 正在用的后端一起带走。
#   1. 广播在线客户端数 —— 前端据此决定「我是不是最后一个，能不能收进程」；
#   2. 「最后一个客户端走后再等一会儿就自己退出」+「等不到客户端也自己退出」——
#      兜住前端被强杀（`taskkill /F`，来不及跑 `_exit_tree`）或「开一半就没了」的情况，
#      否则后代会变成孤儿进程一直占着端口。
_clients: "set[Session]" = set()
_had_client = False
_exit_with_last_client = False
_linger_sec = DEFAULT_LINGER_SEC
_no_client_timeout = DEFAULT_NO_CLIENT_TIMEOUT_SEC
_linger_task: "asyncio.Task | None" = None
_shutdown: "asyncio.Event | None" = None


# ---------------------------------------------------------------- 日志

def log(message: str = "") -> None:
    """打印，并在 `--log-file` 生效时同时追加到文件。

    前端用 `OS.create_process` 拉起后端时，本进程是**脱离进程**：stdout 没有终端接收，
    「起不来」时前端拿不到任何线索，只能靠读这个日志文件的尾部来告诉用户原因。
    所以 `--log-file` 不是可选项，别删。
    """
    print(message, flush=True)
    if _log_handle is not None:
        try:
            _log_handle.write(message + "\n")
            _log_handle.flush()
        except OSError:
            pass        # 日志写不进去不该影响后端干活


def open_log_file(path: str) -> None:
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
    """一个前端连接的会话：数据流开关 + 命令分发。"""

    def __init__(self, websocket):
        self.ws = websocket
        self.streaming = False     # 示例数据流开关（由 start/stop 命令控制）
        self.x = 0.0

    # ---------- 发送 ----------

    async def send(self, payload: dict) -> None:
        """统一出口：所有后端 -> 前端的消息都从这里发，便于加日志/限流。"""
        await self.ws.send(json.dumps(payload, ensure_ascii=False))

    async def send_progress(self, value: float) -> None:
        """进度（0..100）：前端 ProgressBar 直接吃这个。"""
        await self.send({"type": "progress", "value": round(float(value), 2)})

    async def send_error(self, message: str) -> None:
        """出错要发给前端（别只 print 在控制台，界面上看不见）。"""
        await self.send({"type": "error", "message": message})

    # ---------- 数据流 ----------

    async def sample_loop(self) -> None:
        """示例数据流：正弦 + 噪声，映射到 0..100 喂给前端 TrendChart。

        换成你自己的采集循环即可（串口/PLC/相机/算法…）。
        注意：这里在事件循环里跑，**不要**写阻塞调用；
        真要阻塞（读串口、跑 FFT），用 `await loop.run_in_executor(None, fn, *args)`。
        """
        while True:
            if self.streaming:
                y = 50.0 + 40.0 * math.sin(self.x / 20.0) + random.uniform(-3.0, 3.0)
                await self.send({
                    "type": "sample",
                    "x": round(self.x, 1),
                    "y": round(y, 3),
                })
                self.x += 1.0
            await asyncio.sleep(0.05)

    async def _example_command(self, args: dict) -> None:
        """示例命令：演示「收参数 → 干活 → 回报进度」的写法，可整段删掉。"""
        count = int(args.get("count", 5))
        for i in range(count):
            await self.send_progress(100.0 * (i + 1) / count)
            await asyncio.sleep(0.2)
        await self.send({"type": "result", "message": f"示例命令完成，共 {count} 步"})

    # ---------- 命令分发 ----------

    async def handle(self, msg: dict) -> None:
        kind = msg.get("type")
        if kind == "hello":
            # 回一条 hello_ack：前端据此确认「这个端口上跑的确实是我们的后端」，
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
        elif cmd == "example":                      # ← 你的命令加在这里
            await self._example_command(args)
        else:
            log(f"[backend] 未知命令：{cmd}")

        # 每条命令都回执，前端据此更新按钮状态
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
    """最后一个客户端走了：起一个「宽限期」计时，到期还没人来就自己退出。"""
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
    """兜底：等这么久还没人来，就当没人要，自己退。

    没有它的话，「前端把后端起起来、还没连上就被关掉/强杀」会让后端**永远**留着 ——
    `_schedule_linger_exit()` 只有在「有过客户端、又都走了」时才会被调到。
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
            if not isinstance(msg, dict):
                continue
            try:
                await session.handle(msg)
            except Exception as exc:                # noqa: BLE001 —— 报给前端而不是闷掉
                log(f"[backend] 处理命令出错：{type(exc).__name__}: {exc}")
                await session.send_error(f"{type(exc).__name__}: {exc}")
    except ConnectionClosed:
        log("[backend] 客户端断开")
    finally:
        producer.cancel()
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
    ap = argparse.ArgumentParser(description="{{PROJECT_TITLE}} 后端 WebSocket 数据服务")
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
                         f"（默认 {DEFAULT_NO_CLIENT_TIMEOUT_SEC:g}s）")
    args = ap.parse_args()

    # 模块级代码（不在函数里），直接赋值即写到模块全局。
    _exit_with_last_client = args.exit_with_last_client
    _linger_sec = max(args.linger_sec, 0.0)
    _no_client_timeout = max(args.no_client_timeout, 0.0)

    open_log_file(args.log_file)
    if args.log_file:
        log(f"\n===== {datetime.datetime.now():%Y-%m-%d %H:%M:%S} "
            f"backend v{BACKEND_VERSION} 启动（pid={os.getpid()}）=====")
    started = time.perf_counter()
    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        log(f"\n[backend] 收到 Ctrl+C，正在退出…（已运行 {time.perf_counter() - started:.1f}s）")
    finally:
        close_log_file()
