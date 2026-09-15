# Godot4GUI — 实验室工控软件

用 **Godot 4 做前端 GUI**，**Python 做后端**（数据采集/设备控制/数值计算），两者通过本地 **WebSocket + JSON** 通信。目标是替代 Qt/PyQt/tkinter 方案。

## 技术栈与版本
- **Godot 4.7.x（标准版，GDScript，非 .NET）**；渲染器用 `gl_compatibility`（兼容 RDP/虚拟机/老旧 GPU）。
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
├── project.godot                 # 工程配置 + ThemeManager/NetClient autoload + gl_compatibility
├── scenes/
│   ├── main.tscn                 # 应用 Demo（默认主场景，挂 main.gd）：Rayleigh-Sommerfeld 衍射模拟
│   └── gallery.tscn              # 控件/布局总览，挂 gallery.gd
├── scripts/
│   ├── gallery.gd                # Gallery：左侧导航 + 右侧滚动展示各分类控件
│   ├── main.gd                   # 衍射模拟前端：参数栏 + FileDropBox + IntensityMap + 日志
│   ├── autoload/
│   │   ├── net_client.gd         # WebSocket 单例（NetClient）
│   │   └── theme_manager.gd      # 主题单例：启动时构建并应用全局主题
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
│   │   ├── data_table.gd          # 数据表 DataTable（可拖拽调列宽；Tree 不支持拖拽）
│   │   ├── circular_progress_bar.gd # 环形进度条 CircularProgressBar（_draw 圆弧）
│   │   ├── partition_indicator.gd   # 分段指示灯 PartitionIndicator（_draw 分段）
│   │   ├── flash_label.gd           # 闪烁标签 FlashLabel（报警色 + modulate.a 闪烁）
│   │   ├── labeled_line_edit.gd     # 带标签输入框 LabeledLineEdit
│   │   ├── expand_widget.gd         # 折叠展开 ExpandWidget（即时切换，无动画）
│   │   ├── titled_group.gd          # 带标题控件组 TitledGroup
│   │   └── stacked_container.gd     # 堆叠分页 StackedContainer
│   └── util/fmt.gd               # 数字格式化 Fmt（GDScript 的 % 不支持 %e/%g）
├── themes/
│   ├── icons/                    # 复选/箭头/滑块等图标（SVG）
│   └── shaders/colormap.gdshader # 伪彩着色器：强度纹理 → 色标（GPU 上色）
├── backend/
│   ├── main.py                   # WebSocket 后端：协议分发 + 衍射流式推送
│   ├── rayleigh_sommerfeld.py    # Rayleigh-Sommerfeld 计算（逐列流式，作业脚本的改写版）
│   └── requirements.txt
├── tools/
│   ├── new_project.py            # 脚手架：以本模板生成新项目（生成即可 F5 跑通）
│   └── skeleton/                 # 新项目的起始页面/后端骨架/README/CLAUDE 模板（含 .gdignore）
└── docs/
    ├── new-project-guide.md        # 【起新项目看这篇】完整开发指引
    ├── siliconui-godot-mapping.md  # PyQt-SiliconUI -> Godot 迁移对照表
    └── plotting-alternatives.md    # 替代 matplotlib 的调研、选型与踩坑
```

## 运行
1. 后端：`pip install -r backend/requirements.txt && python backend/main.py`
   （端口被占用时脚本会打印排查指引；或换端口 `python backend/main.py --port 9000`。）
2. 前端：用 Godot 4.7 打开本目录，按 F5 运行（默认主场景 = 衍射演示）。看到图像逐列刷新即连通。
   只逛控件：运行 `scenes/gallery.tscn`（无需后端）。
3. 命令行自测：`godot scenes/main.tscn -- --preset=fast --autostart`
   （`--preset=fast` 用快速参数，`--autostart` 连上后端就开算。）
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
- 数字格式化用 `Fmt.num()` / `Fmt.sci()`：**GDScript 的 `%` 不支持 `%e` / `%g`**（会运行时报 unsupported format character）。
- 网络：**只通过 `NetClient` 单例**，业务脚本连接它的 `connected` / `disconnected` / `data_received` 信号；不要在业务脚本里自己 `new WebSocketPeer`。
- 后端消息是 JSON 字典，用 `type` 字段分发。
- 主题：由 `scripts/theme/theme_palette.gd`（设计令牌）+ `theme_factory.gd`（构建）生成，`ThemeManager` autoload 启动时应用到根窗口，作用于所有控件与弹窗。**改样式只编辑 `theme_palette.gd`**；不要在单个控件上 `theme = ...` 打补丁，也不要用 `add_theme_font_size_override` / `add_theme_color_override` 改常规样式，语义样式用 `theme_type_variation`。
- 可用的类型变体：按钮 `AccentButton`/`DangerButton`/`SuccessButton`/`GhostButton`/`CapsuleButton`；标签 `PageTitle`/`SectionTitle`/`CardTitle`/`Subtitle`/`Caption`/`LogLabel`/`PathLabel`/`DropHint`/`ValueText`；状态 `StatusIdle`/`StatusOk`/`StatusWarn`/`StatusError`。缺层级时在 `theme_factory.gd` 的 `_add_label_variation()` 里加一个，不要在业务脚本里就地打补丁。
- 色标（colormap）只改 `scripts/theme/colormaps.gd`；默认 `rainbow` 与 matplotlib 的 `cmap='rainbow'` 逐点完全一致（`R=clamp(|2t-0.5|)`, `G=sin(πt)`, `B=cos(πt/2)`），别改这三行除非要换观感。

## 关键注意（易踩坑）
- `GraphEdit` / `GraphNode` 是**节点编辑器**，不是数据图表；折线图用 `_draw()`，热力图用 `IntensityMap`。
- 参考库 PyQt-SiliconUI 是 **GPLv3**，只借鉴交互设计，代码全部新写（见迁移表）。
- WebSocket 若卡在 connecting，改 `StreamPeerTCP`（`connect_to_host` + `get_utf8_string`）。
- 工控安全相关按钮（急停/启动）用 `LongPressButton` 防误触。
- 控件「选中」有多个子状态：ItemList/Tree 要同时设 `selected`/`selected_focus`/`hovered_selected`/`hovered_selected_focus`（背景）和 `font_selected_color`/`font_hovered_selected_color`（文字），否则点击悬停时仍是白字白底。
- `Tree` 不支持拖拽调列宽（只有 `get_column_width()` 只读），要可调列宽的数据表用本项目 `DataTable`。
- 闪烁/报警用 `FlashLabel`：先把文字设成报警色，再对 `modulate.a` 做透明度闪烁；不要用 `modulate` 改颜色（会把深色文字越乘越暗）。
- 页面边距由 `MarginContainer` 的主题默认值控制，改 `theme_palette.gd` 的 `PAGE_MARGIN` 一处即可统一调整。
- `Window` 的 `embedded_border` 用 StyleBoxFlat 覆盖会让标题栏/边框消失，不要覆盖它（对话框主体用 `AcceptDialog`/`ConfirmationDialog` 的 `panel`）。
- **canvas_item 着色器里 `COLOR` 已经乘过纹理采样**：写 `COLOR = vec4(c, 1.0);` 即可，再乘一次 `COLOR` 会把整幅图压暗。
- 浮点纹理（`FORMAT_RF`）用 `TEXTURE_FILTER_NEAREST`：逐格显示更像 `pcolormesh`，也避开老 GPU 缺 `OES_texture_float_linear` 的问题。
- **主题只在「Control 的父链全是 Control/Window」时才生效**：中间夹一个普通 `Node`，其下的控件就拿不到主题（`get_theme_constant` 会返回引擎默认值）。写测试脚本包场景时尤其容易踩。
- 拖放/文件对话框：`FileDialog.file_mode` 默认是 `FILE_MODE_SAVE_FILE`，取文件必须显式设成 `FILE_MODE_OPEN_FILE`。
