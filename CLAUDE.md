# Godot4GUI — 实验室工控软件

用 **Godot 4 做前端 GUI**，**Python 做后端**（数据采集/设备控制/数值计算），两者通过本地 **WebSocket + JSON** 通信。目标是替代 Qt/PyQt/tkinter 方案。

## 技术栈与版本
- **Godot 4.7.x（标准版，GDScript，非 .NET）**；渲染器用 `forward_plus`，为后续 3D 图表留路。
  **Windows 上的驱动用默认的 `vulkan`**（不是 d3d12）—— Godot 4.6 起新建工程会默认给 d3d12，
  但那太新，实验室机器以 `vulkan` 更稳（GTX 900 系起就支持，且是 Godot 4 长期默认的路径）。
  想要 d3d12 就显式加 `rendering/rendering_device/driver.windows="d3d12"`，不写即 vulkan。
- **Godot 4 没有 D3D11 渲染驱动**：RenderingDevice 的驱动只有 `metal`/`vulkan`/`d3d12`，
  gl_compatibility 侧只有 `opengl3`/`opengl3_es`/`opengl3_angle`。
  如果目标机器需要「更老的 D3D 路径」，唯一沾 D3D11 的是 **`opengl3_angle`**
  （ANGLE 把 GL ES 3.0 翻译到 D3D11），但它必须配合 `gl_compatibility` 渲染器，等于放弃 forward_plus。
  另：Vulkan/D3D12 都不可用时，`rendering/rendering_device/fallback_to_opengl3`（默认开）会自动降级。
- **`project.godot` 里能看到什么、看不到什么**：Godot 默认的 `rendering_method` 就是 `forward_plus`、
  `stretch_mode` 就是 `disabled`、`rendering_method.mobile` 就是 `mobile`、驱动就是 `vulkan`，
  所以这些**等于默认值的项不会写在文件里**（写上去、被编辑器保存一次也会被抹掉）。
  **用编辑器打开过工程后，`project.godot` 会被重写成「只留非默认项 + 抹掉所有注释」** ——
  所以不要把「为什么这么设」只写在 project.godot 的注释里（会被抹掉），要写进本文档。
- **Python 3.11+**，后端依赖 `websockets` + `numpy` + `scipy`（见 `backend/requirements.txt`）。
- 通信：WebSocket，默认 `ws://127.0.0.1:8765`。
- 本地文档：Godot 4.7 官方英文文档（MD）在 `D:\python_sourse\Godot Engine 4.7 documentation in English MD`。查控件 Theme Properties（主题项名）用这里的 `gdd_*.md`（如 `gdd_0633_ItemList.md`、`gdd_0767_Tree.md`、`gdd_0650_MarginContainer.md`）。
- 本机可用于自测的 Godot：`D:\Program Files\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe`
  （`--headless --check-only --script <路径>` 查语法；`--headless <场景> --quit-after N` 查运行期报错；
  新建脚本后先跑一次 `--headless --import` 刷新 `class_name` 全局缓存）。
- 本机 Python：`C:\Users\YH\.conda\envs\normal\python.exe`（含 numpy/scipy/matplotlib）。

## 目录结构
```
Godot4GUI/
├── project.godot                 # 工程配置 + autoload + [backend] 段（渲染器 forward_plus + vulkan，见「技术栈」）
├── scenes/
│   ├── main.tscn                 # 应用 Demo（默认主场景，挂 main.gd）：Rayleigh-Sommerfeld 衍射模拟
│   └── gallery.tscn              # 控件/布局总览，挂 gallery.gd
├── scripts/
│   ├── gallery.gd                # Gallery：左侧导航 + 右侧滚动展示各分类控件
│   ├── main.gd                   # 衍射模拟前端：参数栏 + FileDropBox + IntensityMap + 日志
│   ├── autoload/
│   │   ├── net_client.gd         # WebSocket 单例（NetClient）
│   │   ├── theme_manager.gd      # 主题单例：启动时构建并应用全局主题
│   │   ├── app_shell.gd          # 窗口最小尺寸 / DPI 界面缩放 / user://config.cfg（AppShell）
│   │   └── backend_launcher.gd   # 后端连不上就自动拉起后端进程（BackendLauncher）
│   ├── theme/
│   │   ├── theme_palette.gd      # 设计令牌（颜色/圆角/字号/间距，全局唯一可调来源）
│   │   ├── theme_factory.gd      # 由令牌构建完整 Theme
│   │   └── colormaps.gd          # 色标定义（rainbow/jet/gray）+ Gradient/Texture 缓存
│   ├── ui/
│   │   ├── trend_chart.gd         # 实时折线图 TrendChart（_draw + draw_polyline）
│   │   ├── multi_trend_chart.gd   # 多子图 MultiTrendChart（垂直堆叠、共享 X 轴）
│   │   ├── intensity_map.gd       # 伪彩强度图 IntensityMap（坐标轴+色标条+逐列流式追加）
│   │   ├── file_drop_box.gd       # 文件拖放框 FileDropBox（圆角虚线框 + 系统文件对话框）
│   │   ├── long_press_button.gd   # 长按按钮 LongPressButton（防误触）
│   │   ├── switch.gd              # 开关控件 Switch（Godot 无原生）
│   │   ├── column_table.gd        # 表格基类 ColumnTable（列宽拖拽机制，DataTable/TreeTable 共用）
│   │   ├── data_table.gd          # 数据表 DataTable（可拖拽调列宽；Tree 不支持拖拽）
│   │   ├── tree_table.gd          # 树状表格 TreeTable（层级 + 列宽拖拽 + 行选中）
│   │   ├── tree_table_item.gd     # 树表行对象 TreeTableItem（显式所有权，见「关键注意」）
│   │   ├── ui_scale_option.gd     # 界面缩放选择器 UiScaleOption（跟随系统/100%~200%）
│   │   ├── circular_progress_bar.gd # 环形进度条 CircularProgressBar（_draw 圆弧）
│   │   ├── partition_indicator.gd   # 分段指示灯 PartitionIndicator（_draw 分段）
│   │   ├── flash_label.gd           # 闪烁标签 FlashLabel（报警色 + modulate.a 闪烁）
│   │   ├── labeled_line_edit.gd     # 带标签输入框 LabeledLineEdit
│   │   ├── expand_widget.gd         # 折叠展开 ExpandWidget（即时切换，无动画）
│   │   ├── titled_group.gd          # 带标题控件组 TitledGroup
│   │   └── stacked_container.gd     # 堆叠分页 StackedContainer
│   └── util/fmt.gd               # 数字格式化 Fmt（GDScript 的 % 不支持 %e/%g）
├── themes/
│   ├── icons/                    # 复选/箭头/滑块/关闭等图标（SVG）
│   └── shaders/colormap.gdshader # 伪彩着色器：强度纹理 → 色标（GPU 上色）
├── backend/
│   ├── main.py                   # WebSocket 后端：协议分发 + 衍射流式推送 + --log-file
│   ├── rayleigh_sommerfeld.py    # Rayleigh-Sommerfeld 计算（逐列流式，作业脚本的改写版）
│   └── requirements.txt
├── tools/
│   ├── new_project.py            # 脚手架：以本模板生成新项目（生成即可 F5 跑通）
│   ├── checks/                   # 常驻回归检查（headless 一条命令跑，失败返回非零退出码）
│   └── skeleton/                 # 新项目的起始页面/后端骨架/README/CLAUDE 模板（含 .gdignore）
└── docs/
    ├── new-project-guide.md        # 【起新项目看这篇】完整开发指引
    ├── gdscript-only-guide.md      # 不用 Python 后端（纯 GDScript）时的写法、线程与性能红线
    ├── godot-facts-verified.md     # Godot 4.7 实测事实与坑（每条标注核验状态）
    ├── todo.md                     # 当前状态、待办、未决问题与关键决定记录
    ├── siliconui-godot-mapping.md  # PyQt-SiliconUI -> Godot 迁移对照表
    └── plotting-alternatives.md    # 替代 matplotlib 的调研、选型与踩坑
```

> 接手开发前先读 `docs/todo.md`：里面有已完成项的验证方式、待你拍板的问题、
> 以及「改完代码的最小验收清单」。

## 运行
1. 后端依赖装一次：`pip install -r backend/requirements.txt`
2. 前端：用 Godot 4.7 打开本目录，按 F5 运行（默认主场景 = 衍射演示）。看到图像逐列刷新即连通。
   **不用自己开后端** —— `BackendLauncher` 会按 `project.godot` 的 `[backend]` 段自动拉起它。
   只逛控件：运行 `scenes/gallery.tscn`（无需后端）。
   手动开后端也可以：`python backend/main.py [--port 9000] [--log-file x.log]`，此时给前端加 `--no-backend-autostart`。
3. 命令行自测：`godot scenes/main.tscn -- --preset=fast --autostart`
   （`--preset=fast` 用快速参数，`--autostart` 连上后端就开算；
   另有 `--no-backend-autostart`、`--ui-scale=1.5`、`--python=<路径>`、`--backend-script=<路径>`。）
4. 用本模板起新项目：`python tools/new_project.py <目标目录> --title "..."`，
   生成后必须能 `--import` + 跑主场景无报错（改 `tools/` 后请照 `docs/new-project-guide.md` 末尾自测一遍）。

## 通信协议（JSON 文本帧）
后端 -> 前端：
- `{"type":"rs_begin","columns":N,"rows":M,"z0","z1","y0","y1","params":{...}}` — 开始一次计算（声明画布与坐标范围）
- `{"type":"rs_col","i":k,"z":...,"vmax":...,"data":"<base64 float32 小端>"}` — 第 k 个距离的强度剖面（逐列刷新）
- `{"type":"rs_done","columns":N,"elapsed":s,"cancelled":bool}` — 计算结束
- `{"type":"rs_params","ok":bool,"params":{...}}` — 参数文件回读结果（.py 只解析字面量常量，不执行）
- `{"type":"rs_error","message":"..."}` — 计算报错
- `{"type":"sample","x":...,"y":...}` — 通用示例采样点（喂 TrendChart）
- `{"type":"progress","value":...}` — 进度（0..100）
- `{"type":"ack","id":N,"cmd":...}` — 命令回执
- `{"type":"hello_ack","server":"godot4gui-backend","version":"..."}` — 对 `hello` 的应答，
  前端据此确认端口上跑的确实是本后端（而不是别的程序占着这个端口）

前端 -> 后端：
- `{"type":"hello"}`
- `{"type":"command","id":N,"cmd":"...","args":{...}}` — `rs_start` / `rs_stop` / `rs_params` / `start` / `stop` / `estop`

## GDScript 约定
- 可复用控件用 `class_name` 声明（如 `TrendChart`、`FileDropBox`），业务脚本里直接 `ClassName.new()`。
- 复合控件若对外暴露子节点（如 `TitledGroup.content`、`LabeledLineEdit.line_edit`），在 `_init()` 里构建子节点，保证 `new()` 之后即可访问；不要在 `_ready()` 才建（否则 new 后、入树前访问会空引用）。
- **数据可能在入树前就填好**（先 `setup()/set_column()` 再 `add_child()`）：控件里不要无脑 `set_process(false)`，否则待上传的帧会被一起关掉（`IntensityMap._ready()` 里踩过）。
- UI 优先用 GDScript 代码构建（类 PyQt），复杂静态布局才手写 `.tscn`。
- 实时图表：`extends Control`，重写 `_draw()` 用 `draw_polyline`，新数据后 `queue_redraw()`；多子图用 `MultiTrendChart`。
- 二维标量场（热力图/伪彩图）用 `IntensityMap`：数据是 `FORMAT_RF` 纹理，颜色由 `themes/shaders/colormap.gdshader` 查色标，**不要**在 CPU 上逐像素上色。
- 二维表格：平表用 `DataTable`，**层级/可展开的用 `TreeTable`**（Godot 原生 `Tree` 不支持拖拽调列宽，样式也不走本项目主题）。两者都继承 `ColumnTable`（列宽拖拽 + 行内按钮机制在那里）。
  改宽度用 `set_min_width()`（或设 `custom_minimum_size.x`）；**高度由内容自动上报，不要去写 `custom_minimum_size.y`** ——
  那是「至少这么高」，写 0 会把自动高度覆盖掉，控件随即在自己的矩形之外画表格（表现为表格被裁、行溢到卡片外面，踩过）。
  层级关系由 `TreeTable` 自己画（缩进 + 引导线 + 展开箭头），**单元格文本里不要手写 `└`/`├`**，否则和引导线重复。
- **表格行内按钮**（「开始 / 暂停 / 删除」这类按行操作）用 `set_row_actions(uid, 列号, 规格数组)`（树表是 `set_item_actions(item, 列号, 规格数组)`）。
  规格每项 `{"text", "action", "variation", "tooltip", "disabled"}`；按钮是**真实 `Button` 节点**，
  主题变体/禁用态/tooltip 都照常生效，点是发 `cell_action_pressed(uid, index, action)` 信号。
  几个必须知道的点：
  - **用 `Cell*` 变体**（`CellButton` / `CellSuccessButton` / `CellDangerButton` / `CellAccentButton`）：普通的 32px 高，塞进 30px 的行里会顶到分隔线，`Cell*` 是 26px。
  - 按钮所在列**要留够宽度**（三个按钮约 140px 起）；放最后一列最省事（自动填满剩余宽度），别的列拖宽了会把它挤到溢出。
  - 行用**整数 uid** 标识（树表是 `item.uid`），所以「行被删掉」不会让按钮引用悬空；`TreeTable.get_item_by_uid(uid)` 换回行对象。
  - **换了行数据要重新配一次按钮**（按钮只认 uid，不会跟着数据走）；`DataTable` 的行号就是 uid，`set_rows()` 后行号含义变了。
  - 收起的行按钮自动隐藏、展开后回来；行 `remove()` / `clear_items()` 会把按钮一起回收。
  - 点按钮**不会**顺带选中该行（按钮自己消费了事件）；想要「点按钮也选中行」就在信号处理里自己调 `select()`。
  - 按钮是真的节点：几百行 × 每行几个按钮开销可观，行数很多时建议只给当前页/可见行配。
- 数字格式化用 `Fmt.num()` / `Fmt.sci()`：**GDScript 的 `%` 不支持 `%e` / `%g`**（会运行时报 unsupported format character）。
- 网络：**只通过 `NetClient` 单例**，业务脚本连接它的 `connected` / `disconnected` / `data_received` / `connecting` 信号；不要在业务脚本里自己 `new WebSocketPeer`。
  注意 `disconnected` 只在**曾经连上过**之后断线时才发；「后端从头到尾没起来」要靠 `connecting` 感知（`BackendLauncher` 就是这么做的）。
- **后端进程生命周期交给 `BackendLauncher`**：它读 `project.godot` 的 `[backend]` 段（`python` / `script` / `autostart` / `kill_on_exit`），
  连不上就自动拉起，失败时把后端日志尾部摆给用户看。**不要**在业务脚本里自己 `OS.create_process`；
  也**不要**改成「扫 PATH 找 python」——工控机上多版本 Python 是常态，静默挑错解释器只会让后端悄无声息地起不来。
- **界面缩放/窗口尺寸交给 `AppShell`**：`content_scale_factor` + `Window.min_size` + `user://config.cfg` 记忆。
  界面里给用户一个 `UiScaleOption.new()` 即可。不要把窗口尺寸/缩放写死在业务脚本里。
  **首次运行的窗口尺寸不要依赖 `project.godot` 的 `display/window/size/viewport_*`** ——
  那个值是**物理**像素、不乘缩放系数，125% 缩放下「1280×800」实际是逻辑 1024×640，
  正好等于最小尺寸，窗口就会每次都以最小尺寸打开。`AppShell` 按逻辑设计尺寸
  （`WINDOW_DEFAULT_*`）× 缩放换算，并钳进可用屏幕，不要在自己的脚本里再设一遍。
- 业务脚本要存自己的配置，用 `AppShell.config`（同一个 `user://config.cfg`，分自己的段），改完调 `AppShell.save_config()`。
- 后端消息是 JSON 字典，用 `type` 字段分发。
- 主题：由 `scripts/theme/theme_palette.gd`（设计令牌）+ `theme_factory.gd`（构建）生成，`ThemeManager` autoload 启动时应用到根窗口，作用于所有控件与弹窗。**改样式只编辑 `theme_palette.gd`**；不要在单个控件上 `theme = ...` 打补丁，也不要用 `add_theme_font_size_override` / `add_theme_color_override` 改常规样式，语义样式用 `theme_type_variation`。
- 可用的类型变体：按钮 `AccentButton`/`DangerButton`/`SuccessButton`/`GhostButton`/`CapsuleButton`，
  以及它们给表格单元格用的紧凑版 `CellButton`/`CellAccentButton`/`CellSuccessButton`/`CellDangerButton`；标签 `PageTitle`/`SectionTitle`/`CardTitle`/`Subtitle`/`Caption`/`LogLabel`/`PathLabel`/`DropHint`/`ValueText`；状态 `StatusIdle`/`StatusOk`/`StatusWarn`/`StatusError`。缺层级时在 `theme_factory.gd` 的 `_add_label_variation()` 里加一个，不要在业务脚本里就地打补丁。
- **按钮变体怎么选**（语义是按「视觉权重」分的，不是按颜色好看）：

  | 变体 | 长什么样 | 什么场合用 |
  |---|---|---|
  | `AccentButton` | 主色实底白字 | **主操作**，一屏最多一个（开始/保存/执行） |
  | `DangerButton` | 红色实底 | 有破坏性或安全相关的操作（急停/删除/停止） |
  | `SuccessButton` | 绿色实底 | 确认执行（下发参数/启动） |
  | `GhostButton` | **无底色无边框、只有文字**，悬停才浮出浅底 | 卡片/工具栏里的**次要操作**（回读参数、打开日志目录）。名字里的「幽灵」说的是它没有底板，不是权限或状态 |
  | `CapsuleButton` | 全圆角 + 描边 | 标签式**选择**（筛选/快捷选项），语义上不是「执行」 |
  | `Cell*Button` | 同上各自的样子，但内边距收紧（44×26 而非 48×32） | **只在表格单元格里用**（行内按钮）。四个紧凑变体由 `_add_button_variation()` 连同普通版一起生成，改内边距只需动 `theme_palette.gd` 的 `PAD_CELL_BUTTON_*` |

- 色标（colormap）只改 `scripts/theme/colormaps.gd`；默认 `rainbow` 与 matplotlib 的 `cmap='rainbow'` 逐点完全一致（`R=clamp(|2t-0.5|)`, `G=sin(πt)`, `B=cos(πt/2)`），别改这三行除非要换观感。
- 完全没有 Python 后端的项目怎么写（纯 GDScript、线程纪律、性能红线、留「缝」以便日后升级）：见 **`docs/gdscript-only-guide.md`**。

## 关键注意（易踩坑）
- `GraphEdit` / `GraphNode` 是**节点编辑器**，不是数据图表；折线图用 `_draw()`，热力图用 `IntensityMap`。
- 参考库 PyQt-SiliconUI 是 **GPLv3**，只借鉴交互设计，代码全部新写（见迁移表）。
- WebSocket 若卡在 connecting，改 `StreamPeerTCP`（`connect_to_host` + `get_utf8_string`）。
- 工控安全相关按钮（急停/启动）用 `LongPressButton` 防误触。
- 控件「选中」有多个子状态：ItemList/Tree 要同时设 `selected`/`selected_focus`/`hovered_selected`/`hovered_selected_focus`（背景）和 `font_selected_color`/`font_hovered_selected_color`（文字），否则点击悬停时仍是白字白底。
- `Tree` 不支持拖拽调列宽（只有 `get_column_width()` 只读），要可调列宽的数据表用本项目 `DataTable`。
- 闪烁/报警用 `FlashLabel`：先把文字设成报警色，再对 `modulate.a` 做透明度闪烁；不要用 `modulate` 改颜色（会把深色文字越乘越暗）。
- 页面边距由 `MarginContainer` 的主题默认值控制，改 `theme_palette.gd` 的 `PAGE_MARGIN` 一处即可统一调整。
- **窗口标题要用 `AppShell.set_window_title()`**，别直接写 `get_window().title`。
  开发期用编辑器那套二进制跑工程时，标题会带个 ` (DEBUG)` 后缀，看着像没编译完；要去掉它必须两步都对
  （2026-09-22 在 Godot 4.7.2 / Windows 上实测）：

  | 写法 | OS 上的标题实际变成 |
  |---|---|
  | `get_window().title = "X"` | `X (DEBUG)` ← `Window.title` 的 setter 会让引擎把后缀加回来 |
  | `DisplayServer.window_set_title("X")` 直接写在 `_ready()` 里 | `项目名 (DEBUG)` ← 被引擎的默认标题盖掉 |
  | `AppShell.set_window_title("X")`（等一帧 + `DisplayServer`） | `X` ✅ |

  「等一帧」不能省：引擎是在**窗口首帧显示时**才写那一次默认标题的，晚于 `_ready()`。
  正式导出（Export → Release）本来就没有这个后缀，所以这纯粹是开发期观感问题。
- **headless / 退出时报的「泄漏」未必是你的代码漏了**：`ObjectDB instances were leaked at exit`、
  `RID allocations of type ... leaked at exit`、`BUG: Unreferenced static string` 这些在收尾阶段
  经常是**引擎自身的噪声**（场景/脚本中途报错、`--quit-after` 到大帧数时都出现过）。
  判据是**做对照**：写个什么都不建的**空** `--script` 跑一遍，基线干净了再去怀疑自己的代码。
  **不要只把某一行注释掉就断定是它** —— 那行如果本身是错的（属性名写错之类）脚本会提前中止，
  看起来就像「去掉它就不泄漏」。（上游 DeepScribe 报回来的 `stretch_ratio` 泄漏就是这么来的：
  `Control` 上根本没有 `stretch_ratio` 这个属性，正确的是 `size_flags_stretch_ratio`；
  我用正确属性名实测 **4 个实例、有/无对照都不泄漏**，所以这条没法写进模板当结论。）
- `Window` 的 `embedded_border`（内嵌对话框的标题栏）**可以**覆盖，但要保留引擎默认的边距：`content_margin_top = 28`（标题栏高度）、`expand_margin_* = 32`（投影留白），只换颜色。边距给小了标题文字会被裁掉 —— 这才是「覆盖后标题栏消失」的真正原因（见 `theme_factory.gd` 的 `embed`）。改成浅色标题栏后必须同时换 `close`/`close_pressed` 图标：引擎默认是白叉，浅底上看不见（已换成 `themes/icons/close*.svg`）。
- **canvas_item 着色器里 `COLOR` 已经乘过纹理采样**：写 `COLOR = vec4(c, 1.0);` 即可，再乘一次 `COLOR` 会把整幅图压暗。
- 浮点纹理（`FORMAT_RF`）用 `TEXTURE_FILTER_NEAREST`：逐格显示更像 `pcolormesh`，也避开老 GPU 缺 `OES_texture_float_linear` 的问题。
- **主题只在「Control 的父链全是 Control/Window」时才生效**：中间夹一个普通 `Node`，其下的控件就拿不到主题（`get_theme_constant` 会返回引擎默认值）。写测试脚本包场景时尤其容易踩。
- 拖放/文件对话框：`FileDialog.file_mode` 默认是 `FILE_MODE_SAVE_FILE`，取文件必须显式设成 `FILE_MODE_OPEN_FILE`。
- **长文本 `Label` 的最小宽度 = 整串文字的宽度**：放进 `HBoxContainer`/`GridContainer` 会把容器最小宽度顶大，
  窗口装不下就横向溢出（右边的按钮被切掉）。实测一段 46 字中文的 `Label` 最小宽度 **672px**。
  三种解法都有效（实测）：`clip_text = true` → 1px、`text_overrun_behavior = OVERRUN_TRIM_ELLIPSIS` → 1px、
  `autowrap_mode != OFF` **且**给 `custom_minimum_size.x` → 该宽度。
  （`clip_text` 或 `overrun != NO_TRIMMING` 时引擎直接返回 `Size2(1, 高度)`，所以它们**能**压小最小宽度。）
- **`StreamPeerTCP` 必须先 `poll()`，`get_status()` / `get_available_bytes()` 才会更新**
  （4.7 里 `poll()` 在父类 **`StreamPeerSocket`** 上，找文档容易找错类）。不 poll 会永远停在
  `STATUS_CONNECTING`，而且很难看出原因 —— 用 TCP 端口做单实例锁时就踩过。
- **更多 Godot 4.7 实测事实**（编码名只认 `gb2312`/`gb18030`、`to_multibyte_char_buffer()` 带结尾 NUL、
  `PopupMenu` 分隔线占下标、`get_theme_color()` 没有默认值重载、`.bat` 的三条硬约束……）：
  见 **`docs/godot-facts-verified.md`**（每条都标了「已验 / 待验 / 已修正」）。
- **GDScript 的 lambda 按值捕获局部变量**：在 `connect(func(...): ...)` 里给外层的**局部**变量赋值，
  只改到 lambda 自己那份副本，外面看到的还是原值（写信号回调测试时踩过：`var got := []; ...connect(func(...): got = [...]);`
  结果 `got` 永远是空的）。两种正确写法：把结果放到**成员变量**里（`_clicked = [...]`，走 `self` 能写回去），
  或者对捕获到的 `Array`/`Dictionary` 做**原地修改**（`got.append(x)` —— 引用类型，拷贝的是引用）。
- **`IntensityMap.setup()` / `clear()` 会把 `auto_range` 一并复位成 `true`**（内部走 `_reset_range()`），并发出 `range_reset` 信号。
  这不是随手写的：只清 `display_range` 而留着 `auto_range = false`，`vmax` 会落到 `1e-30`，**整幅图全黑**。
  界面上有「自动量程」开关之后这条路径用户能主动走到，所以两件事必须绑在一起做。要冻结量程用 `auto_range = false`，别去动 `display_range`。
- **`TreeTableItem` 是显式所有权对象（`extends Object`，不是 `RefCounted`）**：父行持有子行、子行持有父行会形成**引用环**，
  而 GDScript 用引用计数（非追踪 GC），环上的对象永远不回收 —— 表格反复重建就会稳定泄漏。
  约定同 Godot 原生 `TreeItem`：**行由 `TreeTable` 拥有，调用方不要自己 `free()`**；删一行用 `item.remove()`，
  之后该引用就失效了；`clear_items()` 会释放整棵树。
- **GDScript 不允许一个对象在「自己的调用栈里」释放自己**（引擎会判定 `Object` 处于 locked 状态而拒绝，
  报 `Attempted to free a locked object`）。所以 `TreeTableItem.remove()` 把自己交给 `TreeTable._release_item_tree()`
  去释放，其中**只有正在执行 `remove()` 的那一行**用 `call_deferred("free")` 推迟到空闲时，子树立即释放。
  自己写「节点/对象自删」逻辑时记住这条。
- **`OS.create_process()` 起的进程不会随 Godot 退出而结束**（引擎文档明确写了）。要么在 `_exit_tree()` 里
  `OS.kill(pid)`（`BackendLauncher` 的做法），要么就明确接受它会变成孤儿进程。
  另外 `OS.kill()` 之前**必须**先 `OS.is_process_running(pid)` —— pid 可能早已失效并被系统回收复用，
  拿着旧 pid 去 kill 会杀到不相干的进程。
- **前端拉起的后端，其 stdout 没人接**（脱离进程、无控制台）。所以 `backend/main.py` 支持 `--log-file`，
  把日志 tee 到文件里；`BackendLauncher` 靠读这个文件的尾部来告诉用户「后端为什么没起来」。
  自己写脱离进程时也要留这么一手，否则出错时一点线索都没有。
- **收尾顺序：先让 `NetClient.begin_shutdown()`，再关后端进程**。反过来的话后端一死 TCP 就断，
  `NetClient` 的 `poll()` 会把这次**主动收尾**读成「后端崩了」—— 弹一句「与后端断开连接」的告警还要重连一次，
  用户每次正常关窗都看到，就会去追一个不存在的故障。autoload 的 `_exit_tree` 顺序不保证，不能靠「我比它后跑」。
- **拉伸模式是 `disabled`，界面缩放走 `content_scale_factor`**（非游戏应用的官方推荐做法）。
  于是「最大化」= 显示更多内容，而不是把界面整体放大。要加缩放档位用 `AppShell.set_ui_scale()` / `UiScaleOption`。
  别改回 `canvas_items` —— 那会让工控机上的大屏把界面糊成一片。
- **`DisplayServer.screen_get_scale()` 在 Windows 上恒返回 1.0**（官方文档：只在 Android/iOS/Web/macOS/Linux-Wayland 上实现）。
  所以 `AppShell.detect_system_scale()` 会回退到 `screen_get_dpi() / 96`（96 dpi = 100%）——
  这在 Windows 上是可用的。别只依赖 `screen_get_scale()`，那等于永远不缩放。
- **`Switch` 没有 `BaseButton` 那套 API**：它是自绘的 `Control`。要「改状态但不触发回调」用
  `set_pressed_no_signal()`（名字对齐引擎的 `BaseButton`），别用 `set_pressed()` —— 后者会 emit `toggled`，容易打环。
- **演示页的「z 步进」是「× dx」的倍数**（dx = L/N，与原作业脚本一致），不是一个绝对长度。
  界面上必须把换算结果实时显示出来（`main.gd` 的 `_update_step_hint()`），否则光看数字没人知道它意味着多少 μm。
  另外算 z 序列长度要用 **`ceil((z_max-z_min)/dx) + 1`** 对齐 numpy 的 `arange(z_min, z_max+dx, dx)`；
  用 `floor` 会差一个元素（实测 N=384 时差 1 列，画布就对不上了）。
