# Godot4GUI — 实验室工控软件

用 **Godot 4 做前端 GUI**，**Python 做后端**（数据采集/设备控制），两者通过本地 **WebSocket + JSON** 通信。目标是替代 Qt/PyQt/tkinter 方案。

## 技术栈与版本
- **Godot 4.7.x（标准版，GDScript，非 .NET）**；渲染器用 `gl_compatibility`（兼容 RDP/虚拟机/老旧 GPU）。
- **Python 3.11+**，后端依赖 `websockets`（见 `backend/requirements.txt`）。
- 通信：WebSocket，默认 `ws://127.0.0.1:8765`。
- 本地文档：Godot 4.7 官方英文文档（MD）在 `D:\python_sourse\Godot Engine 4.7 documentation in English MD`。查控件 Theme Properties（主题项名）用这里的 `gdd_*.md`（如 `gdd_0633_ItemList.md`、`gdd_0767_Tree.md`、`gdd_0521_AnimationTree.md` 等）。

## 目录结构
```
Godot4GUI/
├── project.godot                 # 工程配置 + ThemeManager/NetClient autoload + gl_compatibility
├── scenes/
│   ├── gallery.tscn              # 控件/布局总览（默认主场景，挂 gallery.gd）
│   └── main.tscn                 # 最小应用 Demo（连后端，挂 main.gd）
├── scripts/
│   ├── gallery.gd                # Gallery：左侧导航 + 右侧滚动展示各分类控件
│   ├── main.gd                   # 应用 Demo：启动/停止采集 + 实时图表
│   ├── autoload/
│   │   ├── net_client.gd         # WebSocket 单例（NetClient）
│   │   └── theme_manager.gd      # 主题单例：启动时构建并应用全局主题
│   ├── theme/
│   │   ├── theme_palette.gd      # 设计令牌（颜色/圆角/字号/间距，全局唯一可调来源）
│   │   └── theme_factory.gd      # 由令牌构建完整 Theme
│   └── ui/
│       ├── trend_chart.gd         # 实时折线图 TrendChart（_draw + draw_polyline）
│       ├── multi_trend_chart.gd   # 多子图 MultiTrendChart（垂直堆叠、共享 X 轴）
│       ├── long_press_button.gd   # 长按按钮 LongPressButton（防误触）
│       ├── switch.gd              # 开关控件 Switch（Godot 无原生）
│       ├── data_table.gd          # 数据表 DataTable（可拖拽调列宽，带限位；Tree 不支持拖拽）
│       ├── circular_progress_bar.gd # 环形进度条 CircularProgressBar（_draw 圆弧）
│       ├── partition_indicator.gd   # 分段指示灯 PartitionIndicator（_draw 分段）
│       ├── flash_label.gd           # 闪烁标签 FlashLabel（报警色 + modulate.a 闪烁）
│       ├── labeled_line_edit.gd     # 带标签输入框 LabeledLineEdit
│       ├── expand_widget.gd         # 折叠展开 ExpandWidget（即时切换，无动画）
│       ├── titled_group.gd          # 带标题控件组 TitledGroup
│       └── stacked_container.gd     # 堆叠分页 StackedContainer
├── backend/
│   ├── main.py                   # Python WebSocket 后端示例
│   └── requirements.txt
├── themes/
│   └── icons/                    # 复选/箭头/滑块等图标（SVG）
└── docs/siliconui-godot-mapping.md  # PyQt-SiliconUI -> Godot 迁移对照表
```

## 运行
1. 后端：`pip install -r backend/requirements.txt && python backend/main.py`
   （端口被占用时脚本会打印排查指引；或换端口 `python backend/main.py --port 9000`。）
2. 前端：用 Godot 4.7 打开本目录，按 F5 运行。看到图表实时滚动即连通。

## 通信协议（JSON 文本帧）
后端 -> 前端：
- `{"type":"sample","x":...,"y":...}` — 实时采样点（喂给图表）
- `{"type":"progress","value":...}` — 进度（0..100）
- `{"type":"ack","id":N}` — 命令回执

前端 -> 后端：
- `{"type":"hello"}`
- `{"type":"command","id":N,"cmd":"...","args":{...}}` — 控制命令（start/estop 等）

## GDScript 约定
- 可复用控件用 `class_name` 声明（如 `TrendChart`、`LongPressButton`），业务脚本里直接 `ClassName.new()`。
- 复合控件若对外暴露子节点（如 `TitledGroup.content`、`LabeledLineEdit.line_edit`），在 `_init()` 里构建子节点，保证 `new()` 之后即可访问；不要在 `_ready()` 才建（否则 new 后、入树前访问会空引用）。
- UI 优先用 GDScript 代码构建（类 PyQt），复杂静态布局才手写 `.tscn`。
- 实时图表：`extends Control`，重写 `_draw()` 用 `draw_polyline`，新数据后 `queue_redraw()`；多子图用 `MultiTrendChart`（垂直堆叠、共享 X 轴）。
- 网络：**只通过 `NetClient` 单例**，业务脚本连接它的 `connected` / `disconnected` / `data_received` 信号；不要在业务脚本里自己 `new WebSocketPeer`。
- 后端消息是 JSON 字典，用 `type` 字段分发。
- 主题：由 `scripts/theme/theme_palette.gd`（设计令牌）+ `theme_factory.gd`（构建）生成，`ThemeManager` autoload 启动时应用到根窗口，作用于所有控件与弹窗。**改样式只编辑 `theme_palette.gd`**；不要在单个控件上 `theme = ...` 打补丁，语义样式用 `theme_type_variation`（`AccentButton`/`DangerButton`/`SuccessButton`/`GhostButton`/`CardTitle`/`Subtitle`）。

## 关键注意（易踩坑）
- `GraphEdit` / `GraphNode` 是**节点编辑器**，不是数据图表；折线图用 `_draw()`。
- 参考库 PyQt-SiliconUI 是 **GPLv3**，只借鉴交互设计，代码全部新写（见迁移表）。
- WebSocket 若卡在 connecting，改 `StreamPeerTCP`（`connect_to_host` + `get_utf8_string`）。
- 工控安全相关按钮（急停/启动）用 `LongPressButton` 防误触。
- 主题由 `ThemePalette` 令牌构建（`ThemeManager` autoload 应用），改样式只改 `scripts/theme/theme_palette.gd`；图标在 `themes/icons/*.svg`。语义按钮/标签用 `theme_type_variation`（`AccentButton`/`DangerButton`/`SuccessButton`/`GhostButton`/`CardTitle`/`Subtitle`），不要 per-control 打补丁。
- 控件「选中」有多个子状态：ItemList/Tree 要同时设 `selected`/`selected_focus`/`hovered_selected`/`hovered_selected_focus`（背景）和 `font_selected_color`/`font_hovered_selected_color`（文字），否则点击悬停时仍是白字白底。
- `Tree` 不支持拖拽调列宽（只有 `get_column_width()` 只读），要可调列宽的数据表用本项目 `DataTable`（`scripts/ui/data_table.gd`，`_draw` 自绘）。
- `DataTable` 列宽拖拽已做双向限位（下限 `TABLE_MIN_COL`，上限受其它列+末列最小宽度约束），不会拖出台面；最后一列自动填满剩余宽度。
- 闪烁/报警用 `FlashLabel`：先把文字设成报警色，再对 `modulate.a` 做透明度闪烁；不要用 `modulate` 改颜色（会把深色文字越乘越暗）。
- 页面边距由 `MarginContainer` 的主题默认值控制，改 `theme_palette.gd` 的 `PAGE_MARGIN` 一处即可统一调整整个界面到窗口边缘的距离。
- `Window` 的 `embedded_border` 用 StyleBoxFlat 覆盖会让标题栏/边框消失，不要覆盖它（对话框主体用 `AcceptDialog`/`ConfirmationDialog` 的 `panel`）。
