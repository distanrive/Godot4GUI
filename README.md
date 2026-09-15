# Godot4GUI — 实验室工控软件

用 **Godot 4 做前端 GUI** + **Python 做后端**（数据采集 / 设备控制 / 数值计算），两者通过本地 **WebSocket + JSON** 通信，目标是替代 Qt / PyQt / tkinter 方案。

项目内置一套**可复用、全局可调**的 Godot 4 控件库，并提供两个入口场景：

- `scenes/main.tscn` —— **应用 Demo（默认主场景）**：Rayleigh-Sommerfeld 衍射模拟，
  每算出一个距离就刷新一次伪彩图，支持换配色 / 伽马 / 等比显示 / 鼠标读数。
- `scenes/gallery.tscn` —— 控件 / 布局总览：左侧导航、右侧分类展示所有控件（无需后端）。

## 特性

- **主题系统**：设计令牌 `scripts/theme/theme_palette.gd` → 主题工厂 `theme_factory.gd` → `ThemeManager` 启动时应用到根窗口。**改样式只编辑 `theme_palette.gd` 一个文件**，全局生效（含弹窗、菜单、tooltip）。
- **语义化样式**：`theme_type_variation` 提供按钮 `AccentButton` / `DangerButton` / `SuccessButton` / `GhostButton` / `CapsuleButton`，
  标签 `PageTitle` / `SectionTitle` / `CardTitle` / `Subtitle` / `Caption` / `LogLabel` / `PathLabel` / `DropHint`，
  状态 `StatusIdle` / `StatusOk` / `StatusWarn` / `StatusError`。**不要 per-control 改字号/颜色**，否则「全局可调」就断了。
- **自绘控件库**（零图表 addon 依赖，全部 `_draw()` / 着色器自绘）：

| 控件 | class_name | 说明 |
|---|---|---|
| 实时折线图 | `TrendChart` | 环形缓冲 + `draw_polyline`，自动/手动 Y 轴 |
| 多子图折线图 | `MultiTrendChart` | 垂直堆叠、共享 X 轴、各自独立 Y 轴 |
| 伪彩强度图 | `IntensityMap` | 热力图：坐标轴 + 色标条 + 悬停读数；逐列流式追加，可换配色/伽马/量程 |
| 数据表 | `DataTable` | 可拖拽调列宽（带双向限位），`Tree` 不支持拖拽 |
| 文件拖放框 | `FileDropBox` | 圆角虚线外框；拖入文件 = 输入路径，中间按钮调系统文件资源管理器 |
| 长按按钮 | `LongPressButton` | 防误触（急停 / 启动） |
| 开关 | `Switch` | Godot 无原生开关，`_draw` 自绘 |
| 环形进度条 | `CircularProgressBar` | `_draw` 圆弧 + 中心百分比 |
| 分段指示灯 | `PartitionIndicator` | 连续量离散成多段 |
| 闪烁标签 | `FlashLabel` | 报警色 + `modulate.a` 透明度闪烁 |
| 带标签输入框 | `LabeledLineEdit` | 标签 + 输入框组合 |
| 折叠展开 | `ExpandWidget` | 即时展开 / 收起 |
| 带标题控件组 | `TitledGroup` | 标题 + 内容卡片 |
| 堆叠分页 | `StackedContainer` | 多页切换 |

- **WebSocket 前后端通信**：JSON 文本帧，命令 / 采样 / 进度 / 回执 / 逐列图像数据。
- **色标（colormap）内置**：`rainbow`（与 matplotlib `cmap='rainbow'` **逐点完全一致**）/ `jet` / `gray`，
  定义在 `scripts/theme/colormaps.gd`，由 `themes/shaders/colormap.gdshader` 在 GPU 上查表上色。
- 渲染器用 `gl_compatibility`，兼容 RDP / 虚拟机 / 老旧 GPU。

## 技术栈与版本

- Godot 4.7.x（标准版，GDScript，非 .NET）
- Python 3.11+，后端依赖见 `backend/requirements.txt`（`websockets` + `numpy` + `scipy`）
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

用 **Godot 4.7** 打开本目录，按 **F5** 运行（默认主场景 = 衍射演示）。
左侧填参数（或把参数文件拖进 `FileDropBox` 自动回读）→ 点「开始计算」→ 图像逐列刷新。

> 只逛控件不看后端：把主场景切成 `scenes/gallery.tscn`（或按 F6 运行该场景），无需启动 Python。

命令行自测（可选，参数放在 `--` 之后）：

```bash
godot scenes/main.tscn -- --preset=fast --autostart   # 快速预设 + 连上后端就开算
```

### 衍射演示小抄

| 预设 | 参数 | 耗时 |
|---|---|---|
| 原参数（默认） | N=1000，z 从 0.1 μm 到 100 μm 步长 dx，共 1000 个距离 | ≈ 130 s |
| 快速预览 | N=384，z 步进 4 | ≈ 2 s |

> 原作业脚本 `Rayleigh-Sommerfeld-assignment1.py` 保持原样未改，
> 流式改写版是 `backend/rayleigh_sommerfeld.py`（物理与数值逐位一致，已做等价性验证）。

## 目录结构

```
Godot4GUI/
├── project.godot                 # 工程配置 + autoload + gl_compatibility
├── scenes/
│   ├── main.tscn                 # 应用 Demo（衍射模拟，默认主场景）
│   └── gallery.tscn              # 控件总览
├── scripts/
│   ├── main.gd                   # 衍射前端：参数栏 + 强度图 + 日志
│   ├── gallery.gd                # Gallery 逻辑
│   ├── autoload/
│   │   ├── net_client.gd         # WebSocket 单例（NetClient）
│   │   └── theme_manager.gd      # 主题单例（启动时应用全局主题）
│   ├── theme/
│   │   ├── theme_palette.gd      # 设计令牌（颜色/圆角/字号/间距，唯一可调来源）
│   │   ├── theme_factory.gd      # 由令牌构建 Theme
│   │   └── colormaps.gd          # 色标定义（rainbow/jet/gray）
│   ├── ui/                       # 可复用控件（class_name，见上表）
│   └── util/fmt.gd               # 数字格式化（GDScript 无 %e/%g）
├── themes/
│   ├── icons/                    # 复选/箭头/滑块等 SVG 图标
│   └── shaders/colormap.gdshader # 伪彩着色器（强度 → 色标）
├── backend/
│   ├── main.py                   # WebSocket 服务（协议分发）
│   ├── rayleigh_sommerfeld.py    # 衍射计算（逐列流式）
│   └── requirements.txt
├── tools/
│   ├── new_project.py            # 脚手架：用本模板生成新项目
│   └── skeleton/                 # 新项目的起始页面/后端骨架/文档模板
└── docs/
    ├── new-project-guide.md       # 【起新项目看这篇】完整开发指引
    ├── siliconui-godot-mapping.md # PyQt-SiliconUI → Godot 迁移对照表
    └── plotting-alternatives.md   # 替代 matplotlib 的调研与选型
```

## 用本模板起一个新项目

```bash
python tools/new_project.py D:\work\MyLab --title "XX 实验台"
```

生成即开箱可跑（起始页面 + 后端骨架 + 主题/控件/通信全继承），
完整步骤、协议设计、加控件、调试与踩坑见 **[docs/new-project-guide.md](docs/new-project-guide.md)**。

## 通信协议（JSON 文本帧）

后端 → 前端：

- `{"type":"rs_begin","columns":N,"rows":M,"z0","z1","y0","y1","params":{...}}` — 开始一次计算，声明画布尺寸与坐标范围
- `{"type":"rs_col","i":k,"z":...,"vmax":...,"data":"<base64 float32>"}` — **第 k 个距离的强度剖面**（逐列刷新）
- `{"type":"rs_done","columns":N,"elapsed":s,"cancelled":bool}` — 计算结束
- `{"type":"rs_params","ok":true,"params":{...}}` — 参数文件回读结果
- `{"type":"rs_error","message":"..."}` — 计算报错
- `{"type":"sample","x":...,"y":...}` — 通用示例采样点（`TrendChart` 演示用）
- `{"type":"progress","value":...}` — 进度（0..100）
- `{"type":"ack","id":N,"cmd":...}` — 命令回执

前端 → 后端：

- `{"type":"hello"}`
- `{"type":"command","id":N,"cmd":"...","args":{...}}`
  - `rs_start`（args = 仿真参数）/ `rs_stop` / `rs_params`（args = `{"path": ...}`）
  - `start` / `stop` / `estop`（通用示例数据流）

## 自定义样式

所有颜色、圆角、字号、间距集中定义在 `scripts/theme/theme_palette.gd`（设计令牌），
`ThemeManager` 启动时据此构建并应用全局主题。**改样式只改这一个文件**，不要 per-control 打补丁。

色标只改 `scripts/theme/colormaps.gd`；新增配色在 `names()` 与 `sample()` 里各加一行即可。

## License

MIT协议

本项目的交互设计参考了 [PyQt-SiliconUI](https://github.com/)（**GPLv3**），但只借鉴交互设计、代码全部新写，不构成 GPL 传染。
