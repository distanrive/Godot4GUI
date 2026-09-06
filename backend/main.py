"""Godot4GUI 后端示例：WebSocket 数据服务。

与前端 NetClient（GDScript Autoload）通过 JSON 文本帧通信。
前端发 start/stop 命令控制数据流开关，后端按 50ms 周期推送正弦+噪声采样。

启动：
    pip install -r requirements.txt
    python backend/main.py                # 默认 127.0.0.1:8765
    python backend/main.py --port 9000    # 换端口（端口被占用时）
"""

import argparse
import asyncio
import json
import math
import random
import sys

import websockets

HOST = "127.0.0.1"
DEFAULT_PORT = 8765


async def handler(websocket):
    print(f"[backend] 客户端接入 {websocket.remote_address}")
    streaming = False   # 数据流开关，由 start/stop 命令控制
    x = 0.0

    async def send_loop():
        nonlocal x
        while True:
            if streaming:
                # 模拟一路传感器：正弦 + 噪声，映射到 0..100
                y = 50.0 + 40.0 * math.sin(x / 20.0) + random.uniform(-3.0, 3.0)
                await websocket.send(json.dumps({
                    "type": "sample",
                    "x": round(x, 1),
                    "y": round(y, 3),
                }))
                x += 1.0
            await asyncio.sleep(0.05)

    producer = asyncio.create_task(send_loop())
    try:
        async for raw in websocket:
            msg = json.loads(raw)
            if msg.get("type") == "command":
                cmd = msg.get("cmd")
                if cmd == "start":
                    streaming = True
                    print("[backend] 启动采集")
                elif cmd in ("stop", "estop"):
                    streaming = False
                    print("[backend] 停止采集")
                await websocket.send(json.dumps({
                    "type": "ack", "id": msg.get("id"), "cmd": cmd,
                }))
            elif msg.get("type") == "hello":
                print("[backend] 收到 hello")
    except websockets.ConnectionClosed:
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
    ap = argparse.ArgumentParser(description="Godot4GUI 后端 WebSocket 数据服务")
    ap.add_argument("--host", default=HOST, help=f"监听地址（默认 {HOST}）")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT,
                    help=f"监听端口（默认 {DEFAULT_PORT}）")
    args = ap.parse_args()
    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        print("\n[backend] 收到 Ctrl+C，正在退出…")
