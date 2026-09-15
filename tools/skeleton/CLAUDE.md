# {{PROJECT_TITLE}} — 实验室工控软件

用 **Godot 4 做前端 GUI**，**Python 做后端**（数据采集/设备控制/数值计算），两者通过本地 **WebSocket + JSON** 通信。

> 本项目由 `Godot4GUI` 模板生成：控件库、主题系统、NetClient 协议骨架都是现成的，
> 你只需要写「页面 + 协议 + 业务计算」。控件用法看 `scenes/gallery.tscn`。

## 技术栈与版本
- **Godot 4.7.x（标准版，GDScript，非 .NET）**；渲染器用 `gl_compatibility`（兼容 RDP/虚拟机/老旧 GPU）。
- **Python 3.11+**，后端依赖见 `backend/requirements.txt`。
- 通信：WebSocket，默认 `ws://127.0.0.1:8765`。
- 本地 Godot 4.7 官方英文文档（MD）：`D:\python_sourse\Godot Engine 4.7 documentation in English MD`
  （查控件 Theme Properties 用这里的 `gdd_*.md`，文件名可在 `catalog/classes.tsv` 里搜）。

## 目录结构
```
{{PROJECT_NAME}}/
├── project.godot                 # 工程配置 + ThemeManager/NetClient autoload + gl_compatibility
├── scenes/
│   ├── app.tscn                  # 主场景（挂 scripts/app.gd）—— 你的业务界面
│   └── gallery.tscn              # 控件/布局总览（开发期参照，可删）
├── scripts/
│   ├── app.gd                    # 业务页面：从这一版骨架改起
│   ├── gallery.gd                # Gallery 逻辑
│   ├── autoload/
│   │   ├── net_client.gd         # WebSocket 单例（NetClient）
│   │   └── theme_manager.gd      # 主题单例：启动时构建并应用全局主题
│   ├── theme/
│   │   ├── theme_palette.gd      # 设计令牌（颜色/圆角/字号/间距）—— 样式唯一可调来源
│   │   ├── theme_factory.gd      # 由令牌构建完整 Theme
│   │   └── colormaps.gd          # 色标定义（rainbow/jet/gray）
│   ├── ui/                       # 可复用控件（class_name，见下表）
│   └── util/fmt.gd               # 数字格式化 Fmt（GDScript 的 % 不支持 %e/%g）
├── themes/
│   ├── icons/                    # 复选/箭头/滑块等图标（SVG）
│   └── shaders/colormap.gdshader # 伪彩着色器（强度 → 色标，GPU 上色）
├── backend/
│   ├── main.py                   # WebSocket 服务骨架（命令分发 + 数据流）
│   └── requirements.txt
└── docs/                         # 你的设计/协议文档放这里
```

## 运行
1. 后端：`pip install -r backend/requirements.txt && python backend/main.py`
   （端口被占用时脚本会打印排查指引；或换端口 `python backend/main.py --port 9000`。）
2. 前端：用 Godot 4.7 打开本目录，按 **F5** 运行。点「启动采集」看到曲线滚动即链路通。

## 现成控件（`scripts/ui/`，直接 `ClassName.new()`）
| 控件 | 用途 |
|---|---|
| `TrendChart` / `MultiTrendChart` | 实时折线图（单图 / 多子图共享 X 轴） |
| `IntensityMap` | 二维标量场伪彩图（坐标轴 + 色标条 + 逐列流式追加 + 悬停读数） |
| `DataTable` | 可拖拽调列宽的数据表（`Tree` 不支持拖拽） |
| `FileDropBox` | 文件拖放框：拖入 = 输入路径，按钮调系统文件资源管理器 |
| `LongPressButton` | 长按按钮（急停/启动等防误触场景） |
| `Switch` / `PartitionIndicator` / `CircularProgressBar` | 开关 / 分段指示灯 / 环形进度 |
| `FlashLabel` | 闪烁报警标签 |
| `LabeledLineEdit` / `TitledGroup` / `ExpandWidget` / `StackedContainer` | 输入框 / 卡片分组 / 折叠 / 分页 |

其余（按钮、复选、单选、下拉、滑块、进度条、弹窗、菜单、滚动区…）用 Godot 原生控件 + 全局主题即可。

## 通信协议（JSON 文本帧）
后端 -> 前端：
- `{"type":"sample","x":...,"y":...}` — 实时采样点（喂 TrendChart）
- `{"type":"progress","value":...}` — 进度（0..100）
- `{"type":"ack","id":N,"cmd":...}` — 命令回执
- `{"type":"error","message":"..."}` — 错误上报
- 你的业务消息：`{"type":"...", ...}`，在前端 `_on_data` 里按 `type` 分发

前端 -> 后端：
- `{"type":"hello"}`
- `{"type":"command","id":N,"cmd":"...","args":{...}}` — 控制命令（start/stop/…）

> 大数组别用 JSON 数字数组：`numpy float32 → .tobytes() → base64`，前端
> `Marshalls.base64_to_raw()` + `PackedByteArray.to_float32_array()` 还原。
> 一条 1000 点曲线只占约 5 KB，比 JSON 数组小一个数量级。

## GDScript 约定
- 可复用控件用 `class_name` 声明，业务脚本里直接 `ClassName.new()`。
- 复合控件若对外暴露子节点（如 `TitledGroup.content`、`LabeledLineEdit.line_edit`），在 `_init()` 里构建子节点，保证 `new()` 之后即可访问；不要在 `_ready()` 才建。
- **数据可能在入树前就填好**（先 `setup()/set_column()` 再 `add_child()`）：控件里不要无脑 `set_process(false)`，否则待上传的帧会被一起关掉。
- UI 优先用 GDScript 代码构建（类 PyQt），复杂静态布局才手写 `.tscn`。
- 实时图表：`extends Control`，重写 `_draw()` 用 `draw_polyline`，新数据后 `queue_redraw()`。
- 二维标量场用 `IntensityMap`：数据是 `FORMAT_RF` 纹理，颜色由着色器查色标，**不要**在 CPU 上逐像素上色。
- 数字格式化用 `Fmt.num()`：**GDScript 的 `%` 不支持 `%e` / `%g`**（会运行时报 unsupported format character）。
- 网络：**只通过 `NetClient` 单例**，连它的 `connected` / `disconnected` / `data_received` 信号；不要在业务脚本里 `new WebSocketPeer`。
- 主题：由 `theme_palette.gd`（令牌）+ `theme_factory.gd`（构建）生成，`ThemeManager` 启动时应用到根窗口。
  **改样式只编辑 `theme_palette.gd`**；不要 per-control 打补丁（`theme = ...`、`add_theme_font_size_override`、`add_theme_color_override`），
  语义样式用 `theme_type_variation`。
- 可用类型变体：按钮 `AccentButton`/`DangerButton`/`SuccessButton`/`GhostButton`/`CapsuleButton`；
  标签 `PageTitle`/`SectionTitle`/`CardTitle`/`Subtitle`/`Caption`/`LogLabel`/`PathLabel`/`DropHint`/`ValueText`；
  状态 `StatusIdle`/`StatusOk`/`StatusWarn`/`StatusError`。缺层级时在 `theme_factory.gd` 的 `_add_label_variation()` 里加一个。

## 关键注意（易踩坑）
- 主题只在「Control 的父链全是 Control/Window」时才生效：中间夹一个普通 `Node`，其下的控件拿不到主题（会退回引擎默认样式）。写测试脚本包场景时尤其容易踩。
- canvas_item 着色器里 `COLOR` **已经乘过纹理采样**：写 `COLOR = vec4(c, 1.0);` 即可，再乘一次 `COLOR` 会把整幅图压暗。
- 浮点纹理用 `TEXTURE_FILTER_NEAREST`：逐格显示更像 `pcolormesh`，也避开老 GPU 缺 `OES_texture_float_linear` 的问题。
- `FileDialog.file_mode` 默认是 `FILE_MODE_SAVE_FILE`，取文件必须显式设成 `FILE_MODE_OPEN_FILE`。
- 页面边距由 `MarginContainer` 的主题默认值控制，改 `theme_palette.gd` 的 `PAGE_MARGIN` 一处即可。
- 控件「选中」有多个子状态：ItemList/Tree 要同时设 `selected`/`selected_focus`/`hovered_selected`/`hovered_selected_focus`（背景）和 `font_selected_color`/`font_hovered_selected_color`（文字），否则点击悬停时仍是白字白底。
- 闪烁/报警用 `FlashLabel`：先把文字设成报警色，再对 `modulate.a` 做透明度闪烁；**不要用 `modulate` 改颜色**（会把深色文字越乘越暗）。
- 工控安全按钮（急停/启动）用 `LongPressButton` 防误触。
- `Window` 的 `embedded_border` 用 StyleBoxFlat 覆盖会让标题栏消失，不要覆盖它。
- 后端每个命令都要回 `ack`，出错要发 `error` 消息——只 `print` 在控制台，界面上看不见。
