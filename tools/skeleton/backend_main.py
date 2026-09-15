"""{{PROJECT_TITLE}} —— WebSocket 后端骨架。

与 Godot 前端（`scripts/autoload/net_client.gd` 单例 NetClient）通过 JSON 文本帧通信。
本文件是可运行的**最小骨架**：前端点「启动采集」后按 50ms 周期推正弦采样点，
把「前端命令 → 后端处理 → 后端推数据 → 前端刷新」这条链路先跑通。

启动：
    pip install -r requirements.txt
    python backend/main.py                 # 默认 127.0.0.1:8765
    python backend/main.py --port 9000     # 换端口（端口被占用时）

往这里加你的业务，只有两个动作：
    1) **加命令**：在 `Session.handle()` 的 `elif` 链里加分支（见 `_example_command`）；
    2) **加数据流**：照 `Session.sample_loop()` 写一个 async 循环，
       用 `await self.send({...})` 推消息即可；CPU 密集的活儿丢
       `loop.run_in_executor(None, blocking_fn, args)`，别卡住事件循环。
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import random
import sys
import time

import websockets
from websockets.exceptions import ConnectionClosed

HOST = "127.0.0.1"
DEFAULT_PORT = 8765


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
        elif cmd == "example":                      # ← 你的命令加在这里
            await self._example_command(args)
        else:
            print(f"[backend] 未知命令：{cmd}")

        # 每条命令都回执，前端据此更新按钮状态
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
            if not isinstance(msg, dict):
                continue
            try:
                await session.handle(msg)
            except Exception as exc:                # noqa: BLE001 —— 报给前端而不是闷掉
                print(f"[backend] 处理命令出错：{type(exc).__name__}: {exc}")
                await session.send_error(f"{type(exc).__name__}: {exc}")
    except ConnectionClosed:
        print("[backend] 客户端断开")
    finally:
        producer.cancel()


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
    ap = argparse.ArgumentParser(description="{{PROJECT_TITLE}} 后端 WebSocket 数据服务")
    ap.add_argument("--host", default=HOST, help=f"监听地址（默认 {HOST}）")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT,
                    help=f"监听端口（默认 {DEFAULT_PORT}）")
    args = ap.parse_args()
    started = time.perf_counter()
    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        print(f"\n[backend] 收到 Ctrl+C，正在退出…（已运行 {time.perf_counter() - started:.1f}s）")
