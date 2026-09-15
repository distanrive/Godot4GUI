# {{PROJECT_TITLE}}

Godot 4 前端 + Python 后端（WebSocket + JSON）的实验室工控软件。
由 [Godot4GUI](../Godot4GUI) 模板生成，已内置主题系统、控件库与通信骨架。

- `scenes/app.tscn` —— **主场景**：你的业务界面（现在是「命令 + 实时曲线」的最小骨架）。
- `scenes/gallery.tscn` —— 控件总览：开发期当参照手册用，看完可以删。

## 快速开始

### 1. 启动后端

```bash
pip install -r backend/requirements.txt
python backend/main.py
# 端口被占用时脚本会打印排查指引；或换端口：
#   python backend/main.py --port 9000
```

### 2. 运行前端

用 **Godot 4.7** 打开本目录，按 **F5**。点右上角「启动采集」，曲线开始滚动即链路已通。

## 接下来改哪里

| 你想做的事 | 改哪里 |
|---|---|
| 改界面布局/控件 | `scripts/app.gd`（`_build_ui()` 里全是代码建 UI 的例子） |
| 换配色/字号/间距/圆角 | `scripts/theme/theme_palette.gd`（**只改这一个文件**，全局生效） |
| 换色标（伪彩图配色） | `scripts/theme/colormaps.gd` |
| 加后端命令 | `backend/main.py` 的 `Session.handle()` 里加一个 `elif` |
| 加数据流（采集/算法） | 照 `backend/main.py` 的 `Session.sample_loop()` 写一个 async 循环 |
| 前端收消息 | `scripts/app.gd` 的 `_on_data()` 里按 `type` 分发 |
| 加自定义控件 | 在 `scripts/ui/` 里新建 `class_name` 脚本，并在 `gallery.gd` 加一节便于调试 |

## 目录结构

```
{{PROJECT_NAME}}/
├── project.godot        # 工程配置 + autoload
├── scenes/              # app.tscn（主场景）/ gallery.tscn（控件总览）
├── scripts/
│   ├── app.gd           # ← 你的业务界面
│   ├── autoload/        # NetClient（WebSocket 单例）/ ThemeManager（主题）
│   ├── theme/           # 设计令牌 + 主题工厂 + 色标
│   ├── ui/              # 可复用控件（class_name）
│   └── util/fmt.gd      # 数字格式化
├── themes/              # 图标 SVG + 伪彩着色器
├── backend/             # WebSocket 服务 + 业务计算
└── docs/                # 协议/设计文档放这里
```

## 通信协议

后端 → 前端：`sample`（采样点）/ `progress`（进度）/ `ack`（回执）/ `error`（错误）/ 你的业务消息
前端 → 后端：`hello` / `command`（`{"cmd":"...","args":{...}}`）

> 大数组走 base64：`numpy float32 → .tobytes() → base64`，前端
> `Marshalls.base64_to_raw()` + `to_float32_array()` 还原（1000 点约 5 KB）。

详细约定与踩坑清单见 `CLAUDE.md`。
