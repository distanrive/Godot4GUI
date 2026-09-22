extends Control
## 控件与布局展示（Gallery），对应 PyQt-SiliconUI 的 examples/Gallery。
## 左侧导航切换分类，右侧滚动展示该分类下的控件。
## 每个控件用 _card() 卡片 + 标题标注，方便复制到业务里复用。
## 图表与进度条由 _process 本地驱动，无需后端即可演示。

var _content: VBoxContainer          # 右侧滚动内容容器（承载所有 section）
var _sections: Dictionary = {}       # id -> 已构建的 section 容器（切分类不销毁，状态保留）
var _section_box: VBoxContainer      # 当前正在构建的 section 容器（构建期间非 null）
var _chart: TrendChart               # 图表展示实例（首次构建图表分类后持续存在）
var _multi: MultiTrendChart           # 多子图展示实例
var _map: IntensityMap                # 伪彩强度图展示实例
var _progress: ProgressBar            # 进度条展示实例
var _chart_t := 0.0                  # 图表本地演示数据相位
var _multi_t := 0.0                  # 多子图本地演示数据相位
var _sample_acc := 0.0               # 采样节流累计


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	# 图表演示：50ms 一个点，模拟后端采样节奏
	_sample_acc += delta
	if _sample_acc >= 0.05:
		_sample_acc = 0.0
		if _chart != null:
			_chart_t += 0.05
			_chart.add_point(_chart_t, 50.0 + 40.0 * sin(_chart_t * 2.0))
		if _multi != null:
			_multi_t += 0.05
			_multi.add_point(0, _multi_t, 50.0 + 30.0 * sin(_multi_t * 1.5))
			_multi.add_point(1, _multi_t, 5.0 + 2.0 * sin(_multi_t * 0.8))
			_multi.add_point(2, _multi_t, 20.0 + 15.0 * sin(_multi_t * 2.5))
	# 进度条演示：循环递增
	if _progress != null:
		_progress.value = fmod(_progress.value + delta * 15.0, 100.0)


func _build() -> void:
	# 页面边距：由 MarginContainer 使用主题默认 PAGE_MARGIN（见 theme_palette.gd）
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var root := HBoxContainer.new()
	margin.add_child(root)

	# 左侧导航（宽度要放得下底部的「界面缩放」下拉，否则选项文字会被截断）
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(180, 0)
	nav.add_theme_constant_override("separation", 4)
	root.add_child(nav)

	var nav_title := Label.new()
	nav_title.text = "控件分类"
	nav_title.theme_type_variation = "SectionTitle"
	nav.add_child(nav_title)

	var sections := [
		["按钮", "buttons"],
		["文本与标签", "labels"],
		["输入框", "inputs"],
		["选择", "selection"],
		["滑块与进度", "sliders"],
		["容器与布局", "containers"],
		["表格与列表", "tables"],
		["图表", "chart"],
		["弹窗与菜单", "dialogs"],
	]
	for s in sections:
		var b := Button.new()
		b.text = s[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_show_section.bind(s[1]))
		nav.add_child(b)

	# 界面缩放（AppShell + UiScaleOption）：模板的拉伸模式是 disabled，
	# 所以「高 DPI 屏上字太小」要靠这里调，选完记到 user://config.cfg。
	var nav_spacer := Control.new()
	nav_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_spacer)
	var scale_label := Label.new()
	scale_label.text = "界面缩放"
	scale_label.theme_type_variation = "Subtitle"
	nav.add_child(scale_label)
	nav.add_child(UiScaleOption.new())

	# 右侧滚动内容
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	scroll.add_child(_content)

	_show_section("buttons")


func _show_section(id: String) -> void:
	# 每个分类只构建一次，切走时仅隐藏而不销毁，因此滑块值、表格列宽、
	# 开关/折叠状态等运行时改动在下次切回时都会保留。
	if not _sections.has(id):
		_section_box = VBoxContainer.new()
		_section_box.add_theme_constant_override("separation", 16)
		_sections[id] = _section_box
		_content.add_child(_section_box)
		match id:
			"buttons": _section_buttons()
			"labels": _section_labels()
			"inputs": _section_inputs()
			"selection": _section_selection()
			"sliders": _section_sliders()
			"containers": _section_containers()
			"tables": _section_tables()
			"chart": _section_chart()
			"dialogs": _section_dialogs()
		_section_box = null

	# 只显示当前分类，隐藏其它
	for key in _sections:
		_sections[key].visible = (key == id)


# ---------- 工具 ----------

func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "SectionTitle"   # 字号走主题变体，全局可调
	return l


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Caption"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## 让控件保持固定宽度、左对齐（不占满整行）。
func _sized(ctrl: Control, w: float) -> Control:
	var ms := ctrl.custom_minimum_size
	ms.x = w
	ctrl.custom_minimum_size = ms
	ctrl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return ctrl


## 把某个控件装进带标题的卡片里，方便区分每个控件是干什么的。
func _card(title: String, content: Control) -> Control:
	var p := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = "CardTitle"
	vb.add_child(t)
	vb.add_child(content)
	p.add_child(vb)
	return p


## 造一份「先聚焦后发散 + 干涉条纹」的假数据喂给 IntensityMap，
## 让伪彩图在没有后端时也能看出效果（真实用法见 scripts/main.gd 的衍射演示）。
func _fill_demo_map(map: IntensityMap, cols: int, rows: int) -> void:
	map.setup(cols, rows)
	map.unit_scale = 1.0        # 演示数据是任意单位，不做 m → μm 换算
	map.unit_suffix = ""
	map.set_z_range(0.0, 8.0)
	map.set_y_range(-1.0, 1.0)
	for c in cols:
		var z := float(c) / float(cols - 1)
		var w := 0.02 + absf(z - 0.42) * 0.55          # 束宽：先收后放
		var col := PackedFloat32Array()
		col.resize(rows)
		for r in rows:
			var y := (float(r) / float(rows - 1) - 0.5) * 2.0
			var v := exp(-(y * y) / (2.0 * w * w))
			v *= 1.0 + 0.35 * cos(y * 26.0 * (1.0 - z))   # 干涉条纹
			col[r] = maxf(v, 0.0)
		map.set_column(c, col)


## 堆叠分页演示用页面：居中文本的占位页。
func _make_page(text: String) -> Control:
	var p := Control.new()
	p.custom_minimum_size = Vector2(0, 120)
	var l := Label.new()
	l.text = text
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


# ---------- 各分类 ----------

func _section_buttons() -> void:
	_section_box.add_child(_header("按钮 Button"))
	_section_box.add_child(_caption("pressed 信号在松开时触发；toggle_mode 可做开关；flat 为扁平样式。"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var b1 := Button.new()
	b1.text = "普通按钮"
	row.add_child(b1)

	var b2 := Button.new()
	b2.text = "扁平按钮"
	b2.flat = true
	row.add_child(b2)

	var b3 := Button.new()
	b3.text = "切换按钮"
	b3.toggle_mode = true
	row.add_child(b3)

	var b4 := Button.new()
	b4.text = "禁用按钮"
	b4.disabled = true
	row.add_child(b4)

	var lp := LongPressButton.new()
	lp.text = "长按 1s（防误触）"
	lp.hold_duration = 1.0
	lp.long_pressed.connect(func(): print("[gallery] 长按触发"))
	row.add_child(lp)

	# 长按按钮 + 语义变体：按住时的进度条颜色会跟着变体走（红底上用半透明白，
	# 不然原来是写死的主色蓝、红底上几乎看不见）
	var lp_danger := LongPressButton.new()
	lp_danger.text = "长按急停（危险变体）"
	lp_danger.hold_duration = 1.0
	lp_danger.theme_type_variation = "DangerButton"
	lp_danger.long_pressed.connect(func(): print("[gallery] 长按急停触发"))
	row.add_child(lp_danger)

	_section_box.add_child(_card("按钮类型", row))

	# 语义化按钮：通过 theme_type_variation 复用统一样式
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)

	var ab := Button.new()
	ab.text = "主操作"
	ab.theme_type_variation = "AccentButton"
	row2.add_child(ab)

	var db := Button.new()
	db.text = "危险 / 急停"
	db.theme_type_variation = "DangerButton"
	row2.add_child(db)

	var sb := Button.new()
	sb.text = "成功"
	sb.theme_type_variation = "SuccessButton"
	row2.add_child(sb)

	var gb := Button.new()
	gb.text = "幽灵按钮（无底色）"
	gb.theme_type_variation = "GhostButton"
	row2.add_child(gb)

	_section_box.add_child(_card("语义按钮（类型变体）", row2))
	_section_box.add_child(_caption(
		"设 theme_type_variation 即可获得统一样式。五个变体各自的用途："
		+ " AccentButton = 一屏一个的主操作（开始/保存）；"
		+ " DangerButton = 有破坏性或安全相关的操作（急停/删除）；"
		+ " SuccessButton = 确认执行；"
		+ " GhostButton = **次要操作**（回读参数、打开日志目录这类）；"
		+ " CapsuleButton = 标签式筛选/快捷选项，不是「执行」而是「选择」。"
		+ "\n「幽灵」指的是**没有底色和边框、只有文字**，悬停时才浮出一层浅底 —— "
		+ "所以它不跟主操作抢视觉焦点，适合放在卡片和工具栏里。它不是权限、也不是状态。"))

	# 胶囊按钮：全圆角 + 描边（类型变体 CapsuleButton）
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	for t in ["胶囊 A", "胶囊 B", "胶囊 C"]:
		var cb := Button.new()
		cb.text = t
		cb.theme_type_variation = "CapsuleButton"
		row3.add_child(cb)
	_section_box.add_child(_card("胶囊按钮（CapsuleButton）", row3))
	_section_box.add_child(_caption("CapsuleButton 为全圆角带描边按钮，适合做标签/筛选；改 theme_palette.gd 的 RADIUS_PILL 可统一调整圆角。"))


func _section_labels() -> void:
	_section_box.add_child(_header("文本与标签 Label"))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)

	var l1 := Label.new()
	l1.text = "普通标签"

	var l2 := Label.new()
	l2.text = "大字号标签"
	l2.add_theme_font_size_override("font_size", 24)

	# 彩色标签：覆盖 font_color（modulate 会把深色文字越乘越暗，看不到颜色）
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 10)
	var color_pairs := [
		["主色标签", ThemePalette.ACCENT],
		["成功标签", ThemePalette.SUCCESS],
		["危险标签", ThemePalette.DANGER],
		["警告标签", ThemePalette.WARNING],
	]
	for c in color_pairs:
		var cl := Label.new()
		cl.text = c[0]
		cl.add_theme_color_override("font_color", c[1])
		color_row.add_child(cl)

	var l4 := Label.new()
	l4.text = "自动换行：这是一段足够长的演示文字，用于展示 autowrap 自动换行效果。请观察它在限定宽度内如何折行显示，从而验证自动换行功能是否正常，以及换行后各行的间距与可读性。"
	l4.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l4.custom_minimum_size = Vector2(180, 0)

	# 链接标签：RichTextLabel 的 [url] 标签 + meta_clicked
	var links := RichTextLabel.new()
	links.bbcode_enabled = true
	links.fit_content = true
	links.selection_enabled = true
	links.text = "链接示例：[url=https://docs.godotengine.org/]Godot 官方文档[/url]    [url=OPEN_LOG_DIR]打开日志文件夹[/url]"
	links.meta_clicked.connect(_on_link_clicked)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.text = "[b]加粗[/b]  [i]斜体[/i]  [color=#ff5555]红色[/color]  [color=#55aaff]蓝色[/color]"

	var t1 := Label.new()
	t1.text = "卡片标题"
	t1.theme_type_variation = "CardTitle"

	var t2 := Label.new()
	t2.text = "次要说明文字"
	t2.theme_type_variation = "Subtitle"

	vb.add_child(l1)
	vb.add_child(l2)
	vb.add_child(color_row)
	vb.add_child(l4)
	vb.add_child(links)
	vb.add_child(rt)

	# 闪烁标签：start() 后按 interval 在正常色/报警色之间交替
	var flash := FlashLabel.new()
	flash.text = "闪烁报警标签"
	flash.flash_color = ThemePalette.DANGER
	flash.start()
	vb.add_child(flash)

	vb.add_child(t1)
	vb.add_child(t2)
	_section_box.add_child(_card("标签类型", vb))
	_section_box.add_child(_caption(
		"彩色标签：一次性场合可用 add_theme_color_override 就地改色（上面那排）；"
		+ "有语义的固定状态请用类型变体 StatusOk / StatusWarn / StatusError（改一处全局生效）。"
		+ " 链接用 RichTextLabel 的 [url] 标签 + meta_clicked 信号。"))


## 链接标签点击回调：网页 URL 直接打开，本地路径（OPEN_LOG_DIR）打开日志目录。
func _on_link_clicked(meta: Variant) -> void:
	var m := str(meta)
	if m == "OPEN_LOG_DIR":
		var dir := ProjectSettings.globalize_path("user://logs")
		DirAccess.make_dir_recursive_absolute(dir)
		OS.shell_open(dir)
	else:
		OS.shell_open(m)


func _section_inputs() -> void:
	_section_box.add_child(_header("输入框 Input"))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)

	var e1 := LineEdit.new()
	e1.placeholder_text = "普通输入框（placeholder）"
	vb.add_child(_sized(e1, 240))

	var e2 := LineEdit.new()
	e2.text = "密码模式"
	e2.secret = true
	vb.add_child(_sized(e2, 240))

	var sp := SpinBox.new()
	sp.min_value = 0
	sp.max_value = 100
	sp.value = 50
	vb.add_child(_sized(sp, 120))

	var le := LabeledLineEdit.new()
	le.label_text = "设备名称"
	le.line_edit.text = "通道 1"
	vb.add_child(_sized(le, 260))

	_section_box.add_child(_card("LineEdit / SpinBox / 带标签输入框（固定宽度）", vb))

	# 文件拖放框：拖入即输入路径，中间按钮调系统文件资源管理器
	var drop := FileDropBox.new()
	drop.hint_text = "把文件拖到这里，或"
	drop.filters = PackedStringArray(["*.json ; JSON 文件", "*.py ; Python 脚本", "* ; 所有文件"])
	var drop_out := Label.new()
	drop_out.theme_type_variation = "PathLabel"
	drop_out.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	drop_out.text = "path_changed → （尚未选择）"
	drop.path_changed.connect(func(p: String): drop_out.text = "path_changed → " + p)
	var drop_box := VBoxContainer.new()
	drop_box.add_theme_constant_override("separation", 6)
	drop_box.add_child(drop)
	drop_box.add_child(drop_out)
	_section_box.add_child(_card("文件拖放框 FileDropBox（虚线外框 + 选择文件按钮）", drop_box))
	_section_box.add_child(_caption(
		"拖放框把「拖入文件」和「点按钮选文件」统一成同一个结果：一个路径（path_changed 信号）。"
		+ " use_native_dialog = true 时调起系统资源管理器，false 时用 Godot 内置对话框（跟随全局主题）。"))


func _section_selection() -> void:
	_section_box.add_child(_header("选择 Selection"))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)

	var cb := CheckBox.new()
	cb.text = "复选框"

	# 单选：同一 ButtonGroup 内互斥
	var bg := ButtonGroup.new()
	var r1 := CheckBox.new()
	r1.text = "单选 A"
	r1.button_group = bg
	r1.button_pressed = true
	var r2 := CheckBox.new()
	r2.text = "单选 B"
	r2.button_group = bg

	var opt := OptionButton.new()
	opt.add_item("选项一")
	opt.add_item("选项二")
	opt.add_item("选项三")

	var sw := Switch.new()
	sw.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sw_label := Label.new()
	sw_label.text = "开关：关"
	sw.toggled.connect(func(on: bool): sw_label.text = "开关：开" if on else "开关：关")

	# 禁用态：置灰 + 不吃点击（Control 没有 disabled，Switch 是自绘的，所以自己补了一个）
	var sw_off := Switch.new()
	sw_off.button_pressed = true
	sw_off.disabled = true
	sw_off.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sw_off_label := Label.new()
	sw_off_label.text = "禁用（置灰、点不动）"
	sw_off_label.theme_type_variation = "Subtitle"

	vb.add_child(cb)
	vb.add_child(r1)
	vb.add_child(r2)
	vb.add_child(_sized(opt, 150))
	vb.add_child(sw)
	vb.add_child(sw_label)
	vb.add_child(sw_off)
	vb.add_child(sw_off_label)
	_section_box.add_child(_card("复选 / 单选 / 下拉 / 开关（下拉固定宽度）", vb))


func _section_sliders() -> void:
	_section_box.add_child(_header("滑块与进度 Sliders & Progress"))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var hs := HSlider.new()
	hs.min_value = 0
	hs.max_value = 100
	hs.value = 30
	vb.add_child(_sized(hs, 240))

	var vs := VSlider.new()
	vs.min_value = 0
	vs.max_value = 100
	vs.value = 70
	vs.custom_minimum_size = Vector2(0, 120)
	vs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(vs)

	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.value = 40
	vb.add_child(_sized(_progress, 240))

	# 环形进度条
	var circ := CircularProgressBar.new()
	circ.value = 0.65
	circ.custom_minimum_size = Vector2(96, 96)
	circ.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(circ)

	# 分段指示灯
	var part := PartitionIndicator.new()
	part.segment_count = 10
	part.set_active(6)
	vb.add_child(_sized(part, 240))

	_section_box.add_child(_card("HSlider / VSlider / ProgressBar / 环形进度 / 分段指示", vb))
	_section_box.add_child(_caption("进度条由 _process 循环递增；环形进度与分段指示为 P1 自定义控件（_draw 自绘）。"))


func _section_containers() -> void:
	_section_box.add_child(_header("容器与布局 Containers"))

	var panel := PanelContainer.new()
	var pl := Label.new()
	pl.text = "PanelContainer 面板"
	pl.custom_minimum_size = Vector2(220, 60)
	panel.add_child(pl)
	_section_box.add_child(_card("PanelContainer（面板）", panel))

	var hv := HBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	for i in range(4):
		var b := Button.new()
		b.text = "H 布局 %d" % (i + 1)
		hv.add_child(b)
	_section_box.add_child(_card("HBoxContainer（水平）", hv))

	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 4)
	for i in range(3):
		var b := Button.new()
		b.text = "V 布局 %d" % (i + 1)
		vv.add_child(b)
	_section_box.add_child(_card("VBoxContainer（垂直）", vv))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for i in range(6):
		var b := Button.new()
		b.text = "网格 %d" % (i + 1)
		grid.add_child(b)
	_section_box.add_child(_card("GridContainer（2 列网格）", grid))

	var split := HSplitContainer.new()
	split.custom_minimum_size = Vector2(0, 100)
	var sl := Label.new()
	sl.text = "左（拖分割线）"
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sr := Label.new()
	sr.text = "右"
	sr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(sl)
	split.add_child(sr)
	_section_box.add_child(_card("HSplitContainer（可拖拽分割）", split))

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var flow_texts := [
		"流式 1", "流式 2", "较长的流式按钮 3", "流式 4", "流式 5",
		"更长一点的流式按钮 6", "流式 7", "流式 8", "流式按钮 9",
		"非常长的流式按钮 10", "流式 11", "流式 12", "流式按钮 13",
		"流式 14", "流式 15", "流式按钮 16", "流式 17", "流式 18",
		"较长流式按钮 19", "流式 20", "流式 21", "流式按钮 22",
	]
	for t in flow_texts:
		var b := Button.new()
		b.text = t
		flow.add_child(b)
	_section_box.add_child(_card("HFlowContainer（自动换行流式）", flow))

	# 折叠展开（ExpandWidget）
	var expand := ExpandWidget.new()
	expand.title = "折叠展开（点击标题切换）"
	var a := Label.new()
	a.text = "展开后可见的内容 A"
	var b := Label.new()
	b.text = "展开后可见的内容 B"
	expand.content.add_child(a)
	expand.content.add_child(b)
	_section_box.add_child(_card("ExpandWidget（折叠展开）", expand))

	# 带标题控件组（TitledGroup）
	var tg := TitledGroup.new()
	tg.title = "通信参数"
	var le1 := LabeledLineEdit.new()
	le1.label_text = "地址"
	le1.line_edit.text = "127.0.0.1"
	var le2 := LabeledLineEdit.new()
	le2.label_text = "端口"
	le2.line_edit.text = "8765"
	tg.content.add_child(le1)
	tg.content.add_child(le2)
	_section_box.add_child(_card("TitledGroup（带标题控件组）", tg))

	# 堆叠分页（StackedContainer）
	var stack := StackedContainer.new()
	stack.custom_minimum_size = Vector2(0, 120)
	stack.add_page(_make_page("第 1 页：总览"))
	stack.add_page(_make_page("第 2 页：详情"))
	stack.add_page(_make_page("第 3 页：设置"))
	var stack_nav := HBoxContainer.new()
	stack_nav.add_theme_constant_override("separation", 8)
	var prev := Button.new()
	prev.text = "上一页"
	prev.pressed.connect(func(): stack.prev_page())
	var next := Button.new()
	next.text = "下一页"
	next.pressed.connect(func(): stack.next_page())
	var page_tip := Label.new()
	page_tip.theme_type_variation = "Subtitle"
	stack.page_changed.connect(func(i: int): page_tip.text = "当前第 %d 页" % (i + 1))
	stack_nav.add_child(prev)
	stack_nav.add_child(next)
	stack_nav.add_child(page_tip)
	var stack_box := VBoxContainer.new()
	stack_box.add_theme_constant_override("separation", 8)
	stack_box.add_child(stack)
	stack_box.add_child(stack_nav)
	_section_box.add_child(_card("StackedContainer（堆叠分页）", stack_box))

	# 行卡片（RowCard）：PanelContainer + HBox，标题在左、内容在右
	var rowcard := PanelContainer.new()
	var rch := HBoxContainer.new()
	rch.add_theme_constant_override("separation", 12)
	var rc_title := Label.new()
	rc_title.text = "运行状态"
	rc_title.theme_type_variation = "CardTitle"
	var rc_value := Label.new()
	rc_value.text = "正常"
	rc_value.theme_type_variation = "StatusOk"   # 语义状态色，别用 modulate 染深色文字
	rch.add_child(rc_title)
	rch.add_child(rc_value)
	rowcard.add_child(rch)
	_section_box.add_child(_card("RowCard（行卡片，PanelContainer + HBox）", rowcard))


func _section_tables() -> void:
	_section_box.add_child(_header("表格与列表 Table / List"))

	# ---- ItemList（原生控件，固定高、内容多了自己出滚动条）----
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(280, 172)
	list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for i in range(6):
		list.add_item("列表项 %d" % (i + 1))
	_section_box.add_child(_card("ItemList（Godot 原生列表）", list))
	_section_box.add_child(_caption(
		"ItemList 是原生控件，样式走全局主题；高度给多少显示多少，超出的部分自己出滚动条。"))

	# ---- DataTable（自绘，可拖拽调列宽，末列带行内按钮）----
	var table := DataTable.new()
	table.set_columns(
		PackedStringArray(["通道", "数值", "单位", "操作"]),
		PackedFloat32Array([110.0, 90.0, 70.0, 150.0]))
	var rows: Array = []
	for i in range(5):
		rows.append(["通道 %d" % (i + 1), "%.1f" % (i * 1.5 + 10.0),
				"V" if i % 2 == 0 else "mA", ""])       # 操作列不放文字，由按钮占位
	table.set_rows(rows)
	# 只给宽度；高度由控件按行数自动上报，不要去设 custom_minimum_size.y。
	# 宽度要给够：操作列是最后一列（自动填满剩余宽度），三个按钮约需 140px。
	table.set_min_width(540.0)
	table.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var table_out := Label.new()
	table_out.theme_type_variation = "PathLabel"
	table_out.text = "cell_action_pressed → （点一下行内按钮）"
	table.cell_action_pressed.connect(func(uid: int, index: int, action: String):
		table_out.text = "cell_action_pressed → 第 %d 行（uid=%d）的「%s」" % [uid + 1, uid, action])
	for i in rows.size():
		table.set_row_actions(i, 3, _demo_actions())

	# 参数变了要重新配一次按钮（按钮只认 uid，不会自动跟着行数据走）——
	# 这里演示用：点「重设数据」后行数变了，按钮得重配。
	var rebuild := Button.new()
	rebuild.text = "重设数据（3 行）"
	rebuild.theme_type_variation = "CapsuleButton"
	rebuild.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rebuild.pressed.connect(func():
		var new_rows: Array = []
		for i in range(3):
			new_rows.append(["重设 %d" % (i + 1), "%.1f" % (i * 3.0), "A", ""])
		table.clear_all_actions()
		table.set_rows(new_rows)
		for i in new_rows.size():
			table.set_row_actions(i, 3, _demo_actions())
		table_out.text = "行数据换了，按钮已重新配置")

	var table_box := VBoxContainer.new()
	table_box.add_theme_constant_override("separation", 8)
	table_box.add_child(table)
	table_box.add_child(rebuild)
	table_box.add_child(table_out)
	_section_box.add_child(_card("DataTable（可拖拽调列宽 + 行内按钮）", table_box))
	_section_box.add_child(_caption(
		"DataTable 为自绘数据表：拖动表头分隔线调列宽，最后一列自动填满剩余宽度；"
		+ "Godot 的 Tree 做不到这一点。高度按行数自动上报，调用方只管宽度。"
		+ " 末列的「开始/暂停/删除」是 `set_row_actions()` 放进去的**真实 Button**，"
		+ "所以主题变体（CellSuccessButton 等）与禁用态都照常生效。"))

	_add_tree_table_section()


## 演示用的行内按钮规格（开始 / 暂停 / 删除）。
## 用 `Cell*` 变体：普通按钮 32px 高，塞进 30px 的行里会顶到分隔线。
func _demo_actions() -> Array:
	return [
		{"text": "开始", "action": "start", "variation": "CellSuccessButton",
			"tooltip": "启动这一路"},
		{"text": "暂停", "action": "pause", "variation": "CellButton",
			"tooltip": "暂停采集（可恢复）"},
		{"text": "删除", "action": "delete", "variation": "CellDangerButton",
			"tooltip": "删除这一项（不可撤销）"},
	]


## 树状表格演示：三层「设备 → 通道 → 测量项」，另配展开/收起与选中读数的按钮。
func _add_tree_table_section() -> void:
	var tree := TreeTable.new()
	# 单位并进「数值」列，把最后一列让给操作按钮
	tree.set_columns(
		PackedStringArray(["设备 / 通道 / 测量项", "状态", "数值", "操作"]),
		PackedFloat32Array([210.0, 70.0, 90.0, 150.0]))
	tree.set_min_width(540.0)

	# 三层数据：层级**不要**写进文本里（不要手写 └ / ├），
	# 缩进与引导线由 TreeTable 自己画，文本里再写一遍就是重复的层级标记。
	var specs := [
		["温控台 A", "在线", [
			["通道 1", "正常", [["热电偶", "25.4", "℃"], ["设定值", "25.0", "℃"]]],
			["通道 2", "报警", [["热电偶", "41.8", "℃"], ["设定值", "25.0", "℃"]]],
		]],
		["电源 B", "在线", [
			["输出 1", "正常", [["电压", "12.00", "V"], ["电流", "0.85", "A"]]],
		]],
		["泵组 C", "离线", []],
	]
	for spec in specs:
		var dev := tree.create_item()
		dev.set_cells(PackedStringArray([spec[0], spec[1], "—", ""])).set_expanded(true)
		dev.set_metadata({"kind": "device", "name": spec[0]})
		# 设备行给「开始/暂停/删除」
		tree.set_item_actions(dev, 3, _demo_actions())
		for chan_spec in spec[2]:
			var chan := tree.create_item(dev)
			chan.set_cells(PackedStringArray([chan_spec[0], chan_spec[1], "—", ""]))
			chan.set_metadata({"kind": "channel", "name": chan_spec[0]})
			# 展开到第三层，好把「多级引导线」和「最后一个子项收成 └」都演示出来
			chan.set_expanded(not chan_spec[2].is_empty())
			# 通道行只给「暂停/删除」——演示「不同行可以配不同的按钮」与禁用态：
			# 报警中的通道不允许删（真实的工控里这条很常见）
			var alarming: bool = chan_spec[1] == "报警"
			tree.set_item_actions(chan, 3, [
				{"text": "暂停", "action": "pause", "variation": "CellButton"},
				{"text": "删除", "action": "delete", "variation": "CellDangerButton",
					"disabled": alarming,
					"tooltip": "报警中的通道不允许删除" if alarming else "删除这一路（不可撤销）"},
			])
			for point_spec in chan_spec[2]:
				var point := tree.create_item(chan)
				# 数值带上单位（单位列已让给操作列）
				point.set_cells(PackedStringArray([point_spec[0], "",
						"%s %s" % [point_spec[1], point_spec[2]], ""]))
				point.set_metadata({"kind": "point", "name": point_spec[0]})
				# 叶子（测量项）不给按钮：行内按钮是「按行配」的，不是每行都有

	var readout := Label.new()
	readout.theme_type_variation = "PathLabel"
	readout.text = "item_selected → （点一行看看）"
	tree.item_selected.connect(func(item: TreeTableItem):
		readout.text = "item_selected → " if item != null else "item_selected → (null)"
		if item != null:
			readout.text += "『%s』 %s" % [item.get_cells()[0], str(item.get_metadata())])
	tree.item_activated.connect(func(item: TreeTableItem):
		readout.text = "item_activated（双击）→ 『%s』" % item.get_cells()[0])
	# 行内按钮：拿 uid 换回行对象，再取它的业务数据
	tree.cell_action_pressed.connect(func(uid: int, index: int, action: String):
		var item := tree.get_item_by_uid(uid)
		var name := item.get_cells()[0] if item != null else "（行已删除）"
		readout.text = "cell_action_pressed → 对『%s』执行 %s" % [name, action])

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var expand := Button.new()
	expand.text = "全部展开"
	expand.theme_type_variation = "CapsuleButton"
	expand.pressed.connect(func(): tree.set_all_expanded(true))
	var collapse := Button.new()
	collapse.text = "全部收起"
	collapse.theme_type_variation = "CapsuleButton"
	collapse.pressed.connect(func(): tree.set_all_expanded(false))
	var drop := Button.new()
	drop.text = "删掉选中行"
	drop.theme_type_variation = "GhostButton"
	drop.pressed.connect(func():
		var sel := tree.get_selected()
		if sel != null:
			readout.text = "已删除『%s』" % sel.get_cells()[0]
			sel.remove())
	buttons.add_child(expand)
	buttons.add_child(collapse)
	buttons.add_child(drop)

	# 放在 ScrollContainer 里：TreeTable 会把自己的最小高度同步成「表头 + 可见行数 × 行高」，
	# 所以行数超出这个框时由外层滚动，不需要控件内部再做滚动。
	var scroll := ScrollContainer.new()
	# 给够高度，让展开到第三层（12 行 × 30px 行高 + 表头）时整棵树都看得见，不用滚
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.add_child(tree)
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(scroll)
	box.add_child(buttons)
	box.add_child(readout)
	_section_box.add_child(_card("TreeTable（树状表格：层级 + 可拖拽调列宽 + 行内按钮）", box))
	_section_box.add_child(_caption(
		"TreeTable 解决 Godot 原生 Tree 的两个短板：列宽不能拖（get_column_width 只读）"
		+ "、样式不走本项目主题。层级用 create_item(parent) 建，点箭头展开/收起，"
		+ "双击一行发 item_activated。要滚动就把它放进 ScrollContainer —— 控件会自己算最小高度。"
		+ "\n末列的按钮用 `set_item_actions(item, 列号, 规格数组)` 配：设备行是「开始/暂停/删除」，"
		+ "通道行只有「暂停/删除」（通道 2 在报警，它的「删除」是**禁用**的），"
		+ "叶子测量项**没有**按钮 —— 行内按钮是按行配的、不必每行都有。"
		+ "收起的行按钮会自动隐藏、展开后回来；行被 remove() 掉则连按钮一起回收。"))


func _section_chart() -> void:
	_section_box.add_child(_header("图表 TrendChart"))
	_chart = TrendChart.new()
	_chart.custom_minimum_size = Vector2(0, 300)
	_chart.y_min = 0.0
	_chart.y_max = 100.0
	_section_box.add_child(_card("实时折线图（本地正弦演示）", _chart))
	_section_box.add_child(_caption("数据由 _process 本地生成；接入后端时把 add_point 换成 NetClient 的 sample 消息。"))

	# 多子图：共享 X 轴，每个子图独立 Y 轴与曲线
	_multi = MultiTrendChart.new()
	_multi.custom_minimum_size = Vector2(0, 360)
	_multi.add_plot("温度 ℃", 0.0, 100.0)
	_multi.add_plot("压力 MPa", 0.0, 10.0)
	_multi.add_plot("流量 L/min", 0.0, 40.0)
	_section_box.add_child(_card("多子图 MultiTrendChart（共享 X 轴）", _multi))
	_section_box.add_child(_caption("MultiTrendChart 垂直堆叠多个子图，共享时间轴、各自独立 Y 轴与曲线配色。"))

	# 伪彩强度图（IntensityMap）：本地造一份「聚焦 + 干涉条纹」的假数据
	_map = IntensityMap.new()
	_map.title = "伪彩强度图（本地演示数据）"
	_map.x_label = "Z"
	_map.y_label = "Y"
	_map.colorbar_label = "归一化强度"
	_map.custom_minimum_size = Vector2(0, 300)
	_fill_demo_map(_map, 160, 90)
	_section_box.add_child(_card("伪彩强度图 IntensityMap（可换配色 / 逐列追加）", _map))

	var cmap_row := HBoxContainer.new()
	cmap_row.add_theme_constant_override("separation", 8)
	for name in Colormaps.names():
		var b := Button.new()
		b.text = name
		b.theme_type_variation = "CapsuleButton"
		b.pressed.connect(func():
			_map.colormap = name
			_map.queue_redraw())
		cmap_row.add_child(b)
	_section_box.add_child(_card("切换配色（Colormaps.names()）", cmap_row))
	_section_box.add_child(_caption(
		"IntensityMap 把「标量 → 颜色」交给一块 canvas_item 着色器（themes/shaders/colormap.gdshader），"
		+ "所以换配色、调显示范围、调伽马都只是改 uniform；数据用 FORMAT_RF 逐列追加，可以边算边画。"
		+ " 默认色标 rainbow 与 matplotlib 的 cmap='rainbow' 完全一致（见 docs/plotting-alternatives.md）。"))


func _section_dialogs() -> void:
	_section_box.add_child(_header("弹窗与菜单 Dialog / Menu"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var b1 := Button.new()
	b1.text = "消息框"
	b1.pressed.connect(func():
		var d := AcceptDialog.new()
		d.title = "提示"
		d.dialog_text = "这是一条消息"
		add_child(d)
		d.popup_centered())

	var b2 := Button.new()
	b2.text = "确认框"
	b2.pressed.connect(func():
		var d := ConfirmationDialog.new()
		d.title = "确认"
		d.dialog_text = "确定继续吗？"
		add_child(d)
		d.popup_centered())

	var b3 := Button.new()
	b3.text = "弹出菜单"
	b3.pressed.connect(func():
		var m := PopupMenu.new()
		m.add_item("菜单项 A")
		m.add_item("菜单项 B")
		m.add_separator()
		m.add_item("退出")
		add_child(m)
		m.popup_centered())

	row.add_child(b1)
	row.add_child(b2)
	row.add_child(b3)
	_section_box.add_child(_card("AcceptDialog / ConfirmationDialog / PopupMenu", row))
