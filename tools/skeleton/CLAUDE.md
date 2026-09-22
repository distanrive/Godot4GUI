# {{PROJECT_TITLE}} — 实验室工控软件

用 **Godot 4 做前端 GUI**，**Python 做后端**（数据采集/设备控制/数值计算），两者通过本地 **WebSocket + JSON** 通信。

> 本项目由 `Godot4GUI` 模板生成：控件库、主题系统、NetClient 协议骨架都是现成的，
> 你只需要写「页面 + 协议 + 业务计算」。控件用法看 `scenes/gallery.tscn`。

## 技术栈与版本
- **Godot 4.7.x（标准版，GDScript，非 .NET）**；渲染器用 `forward_plus` + Windows 上的默认驱动 `vulkan`，
  给 3D 图表留路。老机器/RDP 上启动即崩或黑屏时回退 `gl_compatibility`
  （`--rendering-method gl_compatibility`，或项目设置 Rendering → Renderer → Rendering Method）。
  注：**Godot 4 没有 D3D11 渲染驱动**（只有 vulkan / d3d12 / metal / opengl3 系）。
  想要更老的 D3D 路径只能用 `opengl3_angle`（ANGLE 翻译到 D3D11），且必须配 `gl_compatibility`。
- **Python 3.11+**，后端依赖见 `backend/requirements.txt`。
- 通信：WebSocket，默认 `ws://127.0.0.1:8765`。
- 本地 Godot 4.7 官方英文文档（MD）：`D:\python_sourse\Godot Engine 4.7 documentation in English MD`
  （查控件 Theme Properties 用这里的 `gdd_*.md`，文件名可在 `catalog/classes.tsv` 里搜）。

## 目录结构
```
{{PROJECT_NAME}}/
├── project.godot                 # 工程配置 + autoload + [backend] 段（渲染器 forward_plus + vulkan）
├── scenes/
│   ├── app.tscn                  # 主场景（挂 scripts/app.gd）—— 你的业务界面
│   └── gallery.tscn              # 控件/布局总览（开发期参照，可删）
├── scripts/
│   ├── app.gd                    # 业务页面：从这一版骨架改起
│   ├── gallery.gd                # Gallery 逻辑
│   ├── autoload/
│   │   ├── net_client.gd         # WebSocket 单例（NetClient）
│   │   ├── theme_manager.gd      # 主题单例：启动时构建并应用全局主题
│   │   ├── app_shell.gd          # 窗口最小尺寸 / DPI 界面缩放 / user://config.cfg（AppShell）
│   │   └── backend_launcher.gd   # 后端连不上就自动拉起后端进程（BackendLauncher）
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
└── docs/
    ├── gdscript-only-guide.md    # 不用 Python 后端时的写法、线程纪律与性能红线
    └── ...                       # 你的设计/协议文档放这里
```

## 运行
1. 后端依赖装一次：`pip install -r backend/requirements.txt`
2. 前端：用 Godot 4.7 打开本目录，按 **F5** 运行。点「启动采集」看到曲线滚动即链路通。

   **不用自己开后端**：`BackendLauncher` 发现连不上就会按 `project.godot` 的 `[backend]` 段
   把 `backend/main.py` 拉起来（`python` 那一行是生成时就填好的本机解释器路径）。
   想手动开后端并让前端别插手：`python backend/main.py` + 启动参数 `--no-backend-autostart`。

## 现成控件（`scripts/ui/`，直接 `ClassName.new()`）
| 控件 | 用途 |
|---|---|
| `TrendChart` / `MultiTrendChart` | 实时折线图（单图 / 多子图共享 X 轴） |
| `IntensityMap` | 二维标量场伪彩图（坐标轴 + 色标条 + 逐列流式追加 + 悬停读数） |
| `DataTable` | 可拖拽调列宽的数据表（`Tree` 不支持拖拽）+ 行内按钮 |
| `TreeTable` | 树状表格：层级展开/收起 + 可拖拽调列宽 + 行选中 + 行内按钮（`TreeTableItem` 是行对象） |
| `ColumnTable` | 上两者的公共基类（列宽拖拽 + 单元格按钮机制）；换宽度用 `set_min_width()`，高度由内容自动上报（别去写 `custom_minimum_size.y`，会覆盖掉自动高度） |

行内按钮（「开始 / 暂停 / 删除」这类按行操作）用 `set_row_actions(uid, 列, 规格数组)`
（树表 `set_item_actions(item, 列, 规格数组)`），发 `cell_action_pressed(uid, index, action)`。
要点：用 `Cell*` 系列变体（普通按钮 32px 高，塞进 30px 的行里会顶到分隔线）；
按钮列要留够宽度（三个约 140px）；**换了行数据要重新配一次**（按钮只认 uid）；
收起的行按钮自动隐藏、删行自动回收；点按钮不会顺带选中该行。
| `FileDropBox` | 文件拖放框：拖入 = 输入路径，按钮调系统文件资源管理器 |
| `LongPressButton` | 长按按钮（急停/启动等防误触场景） |
| `Switch` / `PartitionIndicator` / `CircularProgressBar` | 开关 / 分段指示灯 / 环形进度 |
| `FlashLabel` | 闪烁报警标签 |
| `LabeledLineEdit` / `TitledGroup` / `ExpandWidget` / `StackedContainer` | 输入框 / 卡片分组 / 折叠 / 分页 |
| `UiScaleOption` | 界面缩放选择器（跟随系统 / 100%~200%），放进工具栏即可 |

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
- 网络：**只通过 `NetClient` 单例**，连它的 `connected` / `disconnected` / `data_received` / `connecting` 信号；不要在业务脚本里 `new WebSocketPeer`。
  注意 `disconnected` 只在**曾经连上过**之后断线时才发；「后端从头到尾没起来」要靠 `connecting` 感知。
- **后端进程生命周期交给 `BackendLauncher`**：它读 `project.godot` 的 `[backend]` 段
  （`python` / `script` / `autostart` / `kill_on_exit`），连不上就自动拉起，失败时把后端日志尾部摆给用户看。
  不要在业务脚本里自己 `OS.create_process`，也**不要**改成「扫 PATH 找 python」——
  工控机上多版本 Python 是常态，静默挑错解释器只会让后端悄无声息地起不来。
  换机器时改 `[backend] python`，或写到 `user://config.cfg` 的 `[backend]` 段（不动仓库）。
- **界面缩放/窗口尺寸交给 `AppShell`**（`content_scale_factor` + `Window.min_size` + `user://config.cfg` 记忆）；
  要给用户留缩放档位就放一个 `UiScaleOption.new()`。业务脚本自己的配置也用
  `AppShell.config`（同一个文件，分自己的段），改完调 `AppShell.save_config()`。
- 主题：由 `theme_palette.gd`（令牌）+ `theme_factory.gd`（构建）生成，`ThemeManager` 启动时应用到根窗口。
  **改样式只编辑 `theme_palette.gd`**；不要 per-control 打补丁（`theme = ...`、`add_theme_font_size_override`、`add_theme_color_override`），
  语义样式用 `theme_type_variation`。
- 可用类型变体：按钮 `AccentButton`/`DangerButton`/`SuccessButton`/`GhostButton`/`CapsuleButton`
  以及表格单元格用的紧凑版 `CellButton`/`CellAccentButton`/`CellSuccessButton`/`CellDangerButton`；
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
- `Window` 的 `embedded_border`（内嵌对话框标题栏）已在本模板里换成了浅色，改它时要保留引擎默认边距（`content_margin_top = 28`、`expand_margin_* = 32`），并配套换 `close`/`close_pressed` 图标——引擎默认是白叉，浅底上看不见。
- 后端每个命令都要回 `ack`，出错要发 `error` 消息——只 `print` 在控制台，界面上看不见。
- **`OS.create_process()` 起的进程不会随 Godot 退出而结束**：要么在 `_exit_tree()` 里 `OS.kill(pid)`
  （`BackendLauncher` 就是这么做的），要么明确接受它变成孤儿进程。`OS.kill()` 之前必须先
  `OS.is_process_running(pid)` —— pid 可能失效并被系统回收复用，拿旧 pid 去 kill 会杀到不相干的进程。
- **收尾顺序：先 `NetClient.begin_shutdown()`，再关后端进程**。反过来的话后端一死 TCP 就断，
  `NetClient` 会把这次主动收尾读成「后端崩了」，弹告警还要重连。autoload 的 `_exit_tree` 顺序不保证。
- **拉伸模式是 `disabled`**，界面缩放走 `AppShell` 的 `content_scale_factor`：
  最大化时是「显示更多内容」而不是整体放大。别改回 `canvas_items`。
  另外 `DisplayServer.screen_get_scale()` 在 Windows 上恒返回 1.0，
  要缩放得回退到 `screen_get_dpi() / 96`。
- **`Switch` 是自绘 Control，没有 `BaseButton` 那套 API**：要「改状态但不触发回调」用
  `set_pressed_no_signal()`，用 `set_pressed()` 会 emit `toggled`，容易打环。
- **`TreeTableItem` 是显式所有权对象**（`extends Object`）：行由 `TreeTable` 拥有，调用方不要自己
  `free()`；删一行用 `item.remove()`，之后该引用就失效了。用 `RefCounted` 会让父子互相持有引用形成
  **引用环**，而 GDScript 用引用计数（非追踪 GC），环上的对象永远不回收。
- **GDScript 不允许对象在「自己的调用栈里」释放自己**（会报 `Attempted to free a locked object`）。
  自删逻辑要交给外部持有者，必要时 `call_deferred("free")` 推迟到空闲时。
- **窗口标题用 `AppShell.set_window_title()`**，别写 `get_window().title`：调试版下 `Window.title`
  会被引擎加上 ` (DEBUG)` 后缀，而 `DisplayServer.window_set_title()` 写在 `_ready()` 里又会被
  引擎的默认标题盖掉 —— 必须「等一帧 + 用 DisplayServer」两步都对。导出后本来就没这后缀。
- **headless / 退出时报的「泄漏」未必是你的代码漏的**（`ObjectDB instances were leaked`、
  `RID allocations leaked`、`BUG: Unreferenced static string` 常常是引擎收尾噪声）。
  判据是**做对照**：跑一个什么都不建的**空** `--script` 看基线干不干净。
  别只把某一行注释掉就断定是它 —— 那行本身写错的话脚本会提前中止，看着就像「去掉它就好了」。
- `IntensityMap.setup()` / `clear()` 会把 `auto_range` 一并复位（内部 `_reset_range()`）：
  只清 `display_range` 而留着 `auto_range = false`，`vmax` 会落到 `1e-30` → **整幅图全黑**。
  要冻结量程用 `auto_range = false`，别去动 `display_range`。
