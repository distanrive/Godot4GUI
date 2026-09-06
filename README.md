# Godot4GUI — 实验室工控软件

用 **Godot 4 做前端 GUI** + **Python 做后端**（数据采集 / 设备控制），两者通过本地 **WebSocket + JSON** 通信，目标是替代 Qt / PyQt / tkinter 方案。

项目内置一套**可复用、全局可调**的 Godot 4 控件库，并提供两个入口场景：

- `scenes/gallery.tscn` —— 控件 / 布局总览（默认主场景），左侧导航、右侧分类展示所有控件。
- `scenes/main.tscn` —— 最小应用 Demo：连后端，启动 / 停止采集 + 实时折线图。

## 特性

- **主题系统**：设计令牌 `scripts/theme/theme_palette.gd` → 主题工厂 `theme_factory.gd` → `ThemeManager` 启动时应用到根窗口。**改样式只编辑 `theme_palette.gd` 一个文件**，全局生效（含弹窗、菜单、tooltip）。
- **语义化样式**：`theme_type_variation` 提供 `AccentButton` / `DangerButton` / `SuccessButton` / `GhostButton` / `CapsuleButton` / `CardTitle` / `Subtitle`。
- **自绘控件库**（零图表 addon 依赖，全部 `_draw()` 自绘）：

| 控件 | class_name | 说明 |
|---|---|---|
| 实时折线图 | `TrendChart` | 环形缓冲 + `draw_polyline`，自动/手动 Y 轴 |
| 多子图折线图 | `MultiTrendChart` | 垂直堆叠、共享 X 轴、各自独立 Y 轴 |
| 数据表 | `DataTable` | 可拖拽调列宽（带双向限位），`Tree` 不支持拖拽 |
| 长按按钮 | `LongPressButton` | 防误触（急停 / 启动） |
| 开关 | `Switch` | Godot 无原生开关，`_draw` 自绘 |
| 环形进度条 | `CircularProgressBar` | `_draw` 圆弧 + 中心百分比 |
| 分段指示灯 | `PartitionIndicator` | 连续量离散成多段 |
| 闪烁标签 | `FlashLabel` | 报警色 + `modulate.a` 透明度闪烁 |
| 带标签输入框 | `LabeledLineEdit` | 标签 + 输入框组合 |
| 折叠展开 | `ExpandWidget` | 即时展开 / 收起 |
| 带标题控件组 | `TitledGroup` | 标题 + 内容卡片 |
| 堆叠分页 | `StackedContainer` | 多页切换 |

- **WebSocket 前后端通信**：JSON 文本帧，命令 / 采样 / 进度 / 回执。
- 渲染器用 `gl_compatibility`，兼容 RDP / 虚拟机 / 老旧 GPU。

## 技术栈与版本

- Godot 4.7.x（标准版，GDScript，非 .NET）
- Python 3.11+，后端依赖 `websockets>=12.0`（`backend/requirements.txt`）
- 通信：WebSocket，默认 `ws://127.0.0.1:8765`

## 快速开始

### 1. 启动后端

```bash
pip install -r backend/requirements.txt
python backend/main.py
# 端口被占用时：脚本会打印排查指引；或换端口：
#   python backend/main.py --port 9000
```

### 2. 运行前端

用 **Godot 4.7** 打开本目录，按 **F5** 运行。看到 `main.tscn` 里图表实时滚动即连通。

> 只逛控件不看后端：直接运行默认主场景 `gallery.tscn`（无需启动 Python 后端）。

## 目录结构

```
Godot4GUI/
├── project.godot                 # 工程配置 + autoload + gl_compatibility
├── scenes/
│   ├── gallery.tscn              # 控件总览（默认主场景）
│   └── main.tscn                 # 最小应用 Demo（连后端）
├── scripts/
│   ├── gallery.gd                # Gallery 逻辑
│   ├── main.gd                   # Demo 逻辑
│   ├── autoload/
│   │   ├── net_client.gd         # WebSocket 单例（NetClient）
│   │   └── theme_manager.gd      # 主题单例（启动时应用全局主题）
│   ├── theme/
│   │   ├── theme_palette.gd      # 设计令牌（颜色/圆角/字号/间距，唯一可调来源）
│   │   └── theme_factory.gd      # 由令牌构建 Theme
│   └── ui/                       # 可复用控件（class_name，见上表）
├── backend/
│   ├── main.py                   # Python WebSocket 后端示例
│   └── requirements.txt
└── themes/icons/                 # 复选/箭头/滑块等 SVG 图标
```

## 通信协议（JSON 文本帧）

后端 → 前端：

- `{"type":"sample","x":...,"y":...}` — 实时采样点
- `{"type":"progress","value":...}` — 进度（0..100）
- `{"type":"ack","id":N,"cmd":...}` — 命令回执

前端 → 后端：

- `{"type":"hello"}`
- `{"type":"command","id":N,"cmd":"...","args":{...}}` — 控制命令（start / stop / estop）

## 自定义样式

所有颜色、圆角、字号、间距集中定义在 `scripts/theme/theme_palette.gd`（设计令牌），
`ThemeManager` 启动时据此构建并应用全局主题。**改样式只改这一个文件**，不要 per-control 打补丁。

## License

MIT协议

本项目的交互设计参考了 [PyQt-SiliconUI](https://github.com/)（**GPLv3**），但只借鉴交互设计、代码全部新写，不构成 GPL 传染。
