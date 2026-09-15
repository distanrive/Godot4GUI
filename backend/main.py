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
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import math
import random
import sys
import time

import numpy as np
import websockets
from websockets.exceptions import ConnectionClosed

from rayleigh_sommerfeld import Config as RSConfig, Simulation, load_params

HOST = "127.0.0.1"
DEFAULT_PORT = 8765


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
        print(f"[backend] 衍射模拟开始：N={cfg.samples} 列数={total} "
              f"λ={cfg.lamda:g}m D={cfg.diameter:g}m L={cfg.width:g}m")

        cancel = asyncio.Event()
        self.rs_cancel = cancel
        self.rs_task = asyncio.create_task(self._simulation_loop(sim, total, cancel))

    async def _simulation_loop(self, sim: Simulation, total: int, cancel: asyncio.Event) -> None:
        loop = asyncio.get_running_loop()
        started = time.perf_counter()
        vmax = 0.0
        done = 0
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
            await self.send({"type": "rs_error", "message": f"{type(exc).__name__}: {exc}"})
        finally:
            elapsed = time.perf_counter() - started
            print(f"[backend] 衍射模拟结束：{done}/{total} 列，用时 {elapsed:.1f}s")
            try:
                await self.send({
                    "type": "rs_done",
                    "columns": done,
                    "elapsed": elapsed,
                    "cancelled": cancel.is_set(),
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
            print("[backend] 收到 hello")
            return
        if kind != "command":
            return

        cmd = msg.get("cmd")
        args = msg.get("args") or {}
        if cmd == "start":
            self.streaming = True
            print("[backend] 启动采集")
        elif cmd in ("stop", "estop"):
            self.streaming = False
            print("[backend] 停止采集")
        elif cmd == "rs_start":
            await self.start_simulation(args)
        elif cmd == "rs_stop":
            await self.stop_simulation()
        elif cmd == "rs_params":
            await self.read_params(str(args.get("path", "")))
        await self.send({"type": "ack", "id": msg.get("id"), "cmd": cmd})


async def handler(websocket):
    print(f"[backend] 客户端接入 {websocket.remote_address}")
    session = Session(websocket)
    producer = asyncio.create_task(session.sample_loop())
    try:
        async for raw in websocket:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                print(f"[backend] 收到非 JSON 消息：{raw[:120]!r}")
                continue
            if isinstance(msg, dict):
                await session.handle(msg)
    except ConnectionClosed:
        print("[backend] 客户端断开")
    finally:
        producer.cancel()
        await session.stop_simulation()


async def main(host: str, port: int) -> None:
    try:
        async with websockets.serve(handler, host, port):
            print(f"[backend] 监听 ws://{host}:{port}（Ctrl+C 停止）")
            await asyncio.Future()   # 一直运行，直到 Ctrl+C
    except OSError as exc:
        # 端口被占用（Windows 常见 WinError 10048）等启动失败
        print(f"[backend] 启动失败：无法监听 ws://{host}:{port}（端口被占用）")
        print(f"        原始错误：{exc}")
        print()
        print("  排查与解决：")
        print(f"    1) 已有实例在跑 —— 找到并结束占用该端口的进程：")
        print(f"         netstat -ano | findstr :{port}     # 看最后一列 PID")
        print(f"         taskkill /F /PID <pid>            # 结束该进程")
        print(f"    2) 端口被其它程序占用 —— 换一个端口：")
        print(f"         python backend/main.py --port {port + 1}")
        print(f"    3) 刚关闭又立刻重启 —— 稍等几秒，等系统释放 TIME_WAIT 状态")
        sys.exit(1)
    print("[backend] 已停止")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Godot4GUI 后端 WebSocket 数据服务")
    ap.add_argument("--host", default=HOST, help=f"监听地址（默认 {HOST}）")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT,
                    help=f"监听端口（默认 {DEFAULT_PORT}）")
    args = ap.parse_args()
    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        print("\n[backend] 收到 Ctrl+C，正在退出…")
