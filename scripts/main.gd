extends Control
## 衍射模拟前端（把原来的「正弦采样 + 折线图」演示换成 Rayleigh-Sommerfeld 衍射）。
##
## 流程：
##   左侧填参数（或用 FileDropBox 拖入 `.py` / `.json` 参数文件自动填）→ 点「开始计算」
##   → 后端每算出一个 z 就推一列光强 → `IntensityMap` 逐列追加、实时刷新伪彩图。
##
## 后端不启动时由 `BackendLauncher` 自动拉起（见 scripts/autoload/backend_launcher.gd）。
## 不需要 Python 后端的项目该怎么写，见 docs/gdscript-only-guide.md。
##
## 单位约定：界面上一律用 μm，发给后端时换算成 m。
## 样式：不在本文件里写死颜色/字号，全部用 ThemePalette 令牌与语义变体。

const UM := 1.0e-6          # 微米 → 米

var _map: IntensityMap
var _progress: ProgressBar
var _status: Label
var _running_label: FlashLabel
var _log_label: Label
var _count_label: Label
var _hover_label: Label
var _step_hint: Label
var _backend_button: Button

var _f_lambda: LabeledLineEdit
var _f_diameter: LabeledLineEdit
var _f_width: LabeledLineEdit
var _f_samples: LabeledLineEdit
var _f_z0: LabeledLineEdit
var _f_z1: LabeledLineEdit
var _f_stride: LabeledLineEdit
var _f_ym: LabeledLineEdit
var _drop: FileDropBox

var _start_button: Button
var _abort_button: Button
var _params_button: Button

var _running := false
var _params_path := ""
var _autostart := false       # --autostart：连上后端就自动开算（自测/演示用）
var _total_columns := 0       # 本次计算的总列数（来自 rs_begin）
var _received := 0            # 已收到的列数
var _last_error := ""         # 上一次的错误信息（rs_error 之后 rs_done 仍会到达，不能被它盖掉）


func _ready() -> void:
	# 先解析命令行，但**不要**在这里就套用预设 ——
	# `_apply_preset()` 要往输入框里写值，而输入框是 `_build_ui()` 才建出来的。
	var fast_preset := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--preset=fast":
			fast_preset = true
		elif arg == "--autostart":
			_autostart = true

	_build_ui()
	if fast_preset:
		_apply_preset("fast")

	# 后端进程生命周期：连不上就自动拉起（见 scripts/autoload/backend_launcher.gd）
	BackendLauncher.status_changed.connect(_on_backend_status)
	BackendLauncher.launch_failed.connect(_on_backend_failed)
	_set_status(BackendLauncher.status_text(), BackendLauncher.status_level())

	NetClient.connected.connect(_on_connected)
	NetClient.disconnected.connect(_on_disconnected)
	NetClient.data_received.connect(_on_data)
	NetClient.connect_to()
	_update_buttons()
	_update_step_hint()


# ---------------------------------------------------------------- 界面

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_sidebar())
	body.add_child(_build_stage())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Rayleigh-Sommerfeld 衍射模拟"
	title.theme_type_variation = "PageTitle"
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# 运行控制放在标题栏：主操作恒定可见，左侧参数栏就能整屏放下（不必滚动）
	_start_button = _make_button("开始计算", "AccentButton", _on_start_pressed)
	_abort_button = _make_button("中止", "", _on_abort_pressed)
	_abort_button.tooltip_text = "中止本次计算。\n不支持暂停/续算：再次「开始计算」会从第一个距离重新算。"
	header.add_child(_start_button)
	header.add_child(_abort_button)

	# 后端没连上时的救急按钮（平时隐藏）
	_backend_button = _make_button("启动后端", "GhostButton", func():
		BackendLauncher.ensure_running(true))
	_backend_button.visible = false
	header.add_child(_backend_button)

	_status = Label.new()
	_status.text = "未连接后端"
	_status.theme_type_variation = "StatusIdle"
	header.add_child(_status)

	header.add_child(UiScaleOption.new())
	return header


## 左侧参数栏（窄，可滚动，窗口小的时候不会把控件挤没）。
func _build_sidebar() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(ThemePalette.SIDEBAR_W, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 12)
	scroll.add_child(vb)

	# ---- 仿真参数 ----
	var params := TitledGroup.new()
	params.title = "仿真参数"
	vb.add_child(params)
	var grid := VBoxContainer.new()
	params.content.add_child(grid)

	_f_lambda = _add_field(grid, "波长 λ", "0.5", "μm")
	_f_diameter = _add_field(grid, "小孔直径 D", "10", "μm")
	_f_width = _add_field(grid, "模拟区域 L", "100", "μm")
	_f_samples = _add_field(grid, "采样点数 N", "1000", "")
	_f_z0 = _add_field(grid, "z 起点", "0.1", "μm")
	_f_z1 = _add_field(grid, "z 终点", "100", "μm")
	# 「z 步进」的实际含义是「乘以 dx」——光看数字看不出来，所以下面配一行实时换算提示
	_f_stride = _add_field(grid, "z 步进（× dx）", "1", "")
	_f_ym = _add_field(grid, "显示窗口 ±y", "10", "μm")

	# 实时换算提示：dx = L/N 随参数变，所以「步进 1 到底是多少 μm」必须当场算给用户看
	_step_hint = Label.new()
	_step_hint.theme_type_variation = "Caption"
	_step_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	params.content.add_child(_step_hint)
	for field in [_f_width, _f_samples, _f_z0, _f_z1, _f_stride]:
		field.line_edit.text_changed.connect(func(_t: String): _update_step_hint())

	# ---- 参数文件（拖放框） ----
	var file_group := TitledGroup.new()
	file_group.title = "参数文件"
	vb.add_child(file_group)

	_drop = FileDropBox.new()
	_drop.hint_text = "拖入参数文件，或"
	_drop.filters = PackedStringArray([
		"*.json ; JSON 参数文件",
		"*.py ; Python 脚本（读其中的常量）",
		"* ; 所有文件",
	])
	_drop.path_changed.connect(_on_params_file_changed)
	file_group.content.add_child(_drop)

	var file_note := Label.new()
	file_note.text = "支持作业脚本本身：只解析其中的 lamda / D / L / N / ym 常量，不执行该文件。"
	file_note.theme_type_variation = "Caption"
	file_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	file_group.content.add_child(file_note)

	_params_button = _make_button("回读参数文件", "GhostButton", _on_read_params_pressed)
	file_group.content.add_child(_params_button)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 6)
	preset_row.add_child(_make_button("原参数", "CapsuleButton", func(): _apply_preset("full")))
	preset_row.add_child(_make_button("快速预览", "CapsuleButton", func(): _apply_preset("fast")))
	file_group.content.add_child(preset_row)

	return scroll


## 右侧主显示区：工具条 + 强度图 + 进度 + 日志。
func _build_stage() -> Control:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)

	_map = IntensityMap.new()
	_map.title = "Z-Y 平面衍射图样（Rayleigh-Sommerfeld）"
	_map.x_label = "Z"
	_map.y_label = "Y"
	_map.colorbar_label = "归一化光强"
	_map.custom_minimum_size = Vector2(0, ThemePalette.PANEL_MIN_H)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.cell_hovered.connect(_on_cell_hovered)

	vb.add_child(_build_toolbar())   # 先建工具条（它会读 _map 的当前配色）
	vb.add_child(_map)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)

	_running_label = FlashLabel.new()
	_running_label.text = "计算中"
	_running_label.flash_color = ThemePalette.WARNING
	_running_label.visible = false
	bottom.add_child(_running_label)

	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.custom_minimum_size = Vector2(0, 0)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_progress)

	# 进度读数用「已算几个距离」表达 —— 比一个裸的百分比更能对上「逐个距离刷新」的心智模型
	_count_label = Label.new()
	_count_label.text = "已算 0 / 0 个距离"
	_count_label.theme_type_variation = "Subtitle"
	bottom.add_child(_count_label)
	vb.add_child(bottom)

	_log_label = Label.new()
	_log_label.text = "就绪。左侧填参数或拖入参数文件，然后点「开始计算」。"
	_log_label.theme_type_variation = "LogLabel"
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_log_label)
	return vb


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.custom_minimum_size = Vector2(0, ThemePalette.TOOLBAR_MIN_H)

	var cmap_label := Label.new()
	cmap_label.text = "配色"
	cmap_label.theme_type_variation = "Subtitle"
	bar.add_child(cmap_label)

	var cmap := OptionButton.new()
	for name in Colormaps.names():
		cmap.add_item(name)
	cmap.selected = maxi(Colormaps.names().find(_map.colormap), 0)
	cmap.item_selected.connect(func(i: int):
		_map.colormap = Colormaps.names()[i]
		_log("配色切换为 %s" % _map.colormap))
	bar.add_child(cmap)

	var gamma_label := Label.new()
	gamma_label.text = "伽马"
	gamma_label.theme_type_variation = "Subtitle"
	bar.add_child(gamma_label)

	var gamma := HSlider.new()
	gamma.min_value = 0.2
	gamma.max_value = 3.0
	gamma.step = 0.05
	gamma.value = 1.0
	gamma.custom_minimum_size = Vector2(120, 0)
	gamma.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gamma.value_changed.connect(func(v: float):
		_map.gamma = v
		gamma.tooltip_text = "伽马 %.2f（>1 提亮暗部条纹）" % v)
	gamma.tooltip_text = "伽马 1.00（>1 提亮暗部条纹）"
	bar.add_child(gamma)

	var aspect_label := Label.new()
	aspect_label.text = "等比"
	aspect_label.theme_type_variation = "Subtitle"
	bar.add_child(aspect_label)

	var aspect := Switch.new()
	aspect.button_pressed = _map.equal_aspect
	aspect.toggled.connect(func(on: bool): _map.equal_aspect = on)
	bar.add_child(aspect)

	# 显示范围：开 = 随数据最大值自动增长；关 = 冻结当前范围，便于前后对比。
	# （原来是「重置量程」按钮，点下去会连已算出的图像一起清空 —— 那是破坏性的，
	#   而且「重置量程」到底重设到多少也没说清。现在语义就是一个开关。）
	var range_label := Label.new()
	range_label.text = "自动量程"
	range_label.theme_type_variation = "Subtitle"
	bar.add_child(range_label)

	var auto_range := Switch.new()
	auto_range.button_pressed = _map.auto_range
	auto_range.tooltip_text = "开：显示范围随数据最大值增长（只增不减）。\n关：冻结当前显示范围，方便和目标图对比。"
	auto_range.toggled.connect(func(on: bool):
		_map.auto_range = on
		_log("自动量程：%s" % ("开（继续随数据增长）" if on else "关（冻结当前显示范围）")))
	bar.add_child(auto_range)
	# 开始一次新计算时 IntensityMap 会把量程复位成自动（见 setup()），开关要跟着回到「开」
	_map.range_reset.connect(func(): auto_range.set_pressed_no_signal(true))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# 悬停读数放在工具条右端：既能定量读条纹，又不会把状态日志冲掉
	_hover_label = Label.new()
	_hover_label.text = "把鼠标移到图上可读数"
	_hover_label.theme_type_variation = "Subtitle"
	bar.add_child(_hover_label)
	return bar


## 参数栏里的一行：标签 + 输入框（+ 单位）。
func _add_field(parent: Control, label: String, value: String, unit: String) -> LabeledLineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var field := LabeledLineEdit.new()
	field.label_text = label
	field.label_width = 132.0
	field.line_edit.text = value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	if not unit.is_empty():
		var u := Label.new()
		u.text = unit
		u.theme_type_variation = "Subtitle"
		row.add_child(u)
	parent.add_child(row)
	return field


func _make_button(text: String, variation: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = variation
	b.pressed.connect(handler)
	return b


# ---------------------------------------------------------------- 参数

## 读一个输入框里的数字。读不出来就沿用 fallback，并把输入框改回实际生效的值 ——
## 否则「日志说沿用了旧值，输入框里还留着那个非法值」，用户会一直以为自己填对了。
func _num(field: LabeledLineEdit, fallback: float) -> float:
	var text := field.text.strip_edges()
	if not text.is_valid_float():
		_log("「%s」不是数字（%s），沿用上一次的值 %s" % [field.label_text, text, Fmt.num(fallback, 6)])
		field.text = Fmt.num(fallback, 6)
		return fallback
	return text.to_float()


## 把「z 步进 = 几个 dx」换算成看得懂的实际步距，并给出总距离数。
func _update_step_hint() -> void:
	if _step_hint == null or _f_width == null:
		return
	var width := _num_silent(_f_width, 100.0)
	var samples := maxi(int(round(_num_silent(_f_samples, 1000.0))), 1)
	var dx := width / float(samples)
	var z0 := _num_silent(_f_z0, 0.1)
	var z1 := _num_silent(_f_z1, 100.0)
	var stride := maxi(int(round(_num_silent(_f_stride, 1.0))), 1)
	if z1 < z0:
		var t := z0
		z0 = z1
		z1 = t
	# 与后端 Config.z_values 同一套算法：arange(z0, z1 + dx, dx)[::stride]
	var full := int(ceil((z1 - z0) / dx)) + 1
	var columns := int(ceil(float(full) / float(stride)))
	_step_hint.text = "dx = L/N = %s μm ｜ 实际 Δz = %s μm ｜ 共 %s 个距离" % [
		Fmt.num(dx, 4), Fmt.num(dx * stride, 4), Fmt.num(columns, 4)]


## 读数字但**不写日志**（给实时提示用：每敲一个键都写日志会把日志刷爆）。
func _num_silent(field: LabeledLineEdit, fallback: float) -> float:
	var text := field.text.strip_edges()
	return text.to_float() if text.is_valid_float() else fallback


func _collect_params() -> Dictionary:
	return {
		"lamda": _num(_f_lambda, 0.5) * UM,
		"diameter": _num(_f_diameter, 10.0) * UM,
		"width": _num(_f_width, 100.0) * UM,
		"samples": int(round(_num(_f_samples, 1000.0))),
		"z_min": _num(_f_z0, 0.1) * UM,
		"z_max": _num(_f_z1, 100.0) * UM,
		"z_stride": maxi(int(round(_num(_f_stride, 1.0))), 1),
		"y_window": _num(_f_ym, 10.0) * UM,
	}


## 把参数字典（通常是后端回读的）写回输入框；单位统一显示成 μm。
func _apply_params(data: Dictionary) -> void:
	var fields := {
		"lamda": [_f_lambda, 1.0 / UM],
		"diameter": [_f_diameter, 1.0 / UM],
		"width": [_f_width, 1.0 / UM],
		"samples": [_f_samples, 1.0],
		"z_min": [_f_z0, 1.0 / UM],
		"z_max": [_f_z1, 1.0 / UM],
		"z_stride": [_f_stride, 1.0],
		"y_window": [_f_ym, 1.0 / UM],
	}
	var applied := PackedStringArray()
	for key in fields:
		if not data.has(key):
			continue
		var spec: Array = fields[key]
		var field: LabeledLineEdit = spec[0]
		var scale: float = spec[1]
		var v := float(data[key]) * scale
		field.text = Fmt.num(v, 6)
		applied.append(key)
	_update_step_hint()
	_log("已读入参数：%s" % ", ".join(applied))


func _apply_preset(which: String) -> void:
	if which == "fast":
		_f_samples.text = "384"
		_f_stride.text = "4"
		_f_z1.text = "100"
		_log("已套用「快速预览」：N=384、z 步进 4（约几秒出图）。")
	else:
		_f_lambda.text = "0.5"
		_f_diameter.text = "10"
		_f_width.text = "100"
		_f_samples.text = "1000"
		_f_z0.text = "0.1"
		_f_z1.text = "100"
		_f_stride.text = "1"
		_f_ym.text = "10"
		_log("已恢复作业原始参数（N=1000、1000 个 z，约 2 分钟算完）。")
	_update_step_hint()


# ---------------------------------------------------------------- 运行

func _on_start_pressed() -> void:
	var params := _collect_params()
	_map.clear()                 # 新一次计算 = 新画布；量程随之回到「自动」（见 IntensityMap.setup）
	_progress.value = 0.0
	_total_columns = 0
	_received = 0
	_last_error = ""
	_update_count_label()
	_running = true
	_update_buttons()
	_log("开始计算：N=%d，共 %s 个距离，每算出一个就刷新一次图像。" % [
		params["samples"], Fmt.num(_estimate_columns(params), 4)])
	NetClient.send_command("rs_start", params)


## 前端预估的列数（仅用于日志；真正的画布尺寸以 `rs_begin` 为准）。
func _estimate_columns(params: Dictionary) -> int:
	var dx: float = params["width"] / float(maxi(int(params["samples"]), 1))
	var full := int(ceil((params["z_max"] - params["z_min"]) / dx)) + 1
	return int(ceil(float(full) / float(maxi(int(params["z_stride"]), 1))))


func _on_abort_pressed() -> void:
	NetClient.send_command("rs_stop")
	_log("已请求中止。不支持续算：再次「开始计算」会从第一个距离重算。")


func _on_read_params_pressed() -> void:
	if _params_path.is_empty():
		_log("还没有选参数文件：把 .py / .json 拖到左上角的拖放框里，或用「选择文件…」按钮。")
		return
	NetClient.send_command("rs_params", {"path": _params_path})


func _on_params_file_changed(path: String) -> void:
	_params_path = path
	_log("参数文件：%s" % path)
	NetClient.send_command("rs_params", {"path": path})


func _update_buttons() -> void:
	if _start_button == null:
		return
	_start_button.disabled = _running
	_abort_button.disabled = not _running
	_running_label.visible = _running
	if _running:
		_running_label.start()
	else:
		_running_label.stop()


func _set_status(text: String, variation: String) -> void:
	_status.text = text
	_status.theme_type_variation = _variation_for_level(variation)


## BackendLauncher 用的是 "idle/ok/warn/error"，这里换成主题里的 Status* 变体名。
func _variation_for_level(level: String) -> String:
	match level:
		"ok":
			return "StatusOk"
		"warn":
			return "StatusWarn"
		"error":
			return "StatusError"
		_:
			return "StatusIdle"


func _log(msg: String) -> void:
	if _log_label != null:
		_log_label.text = msg
	print("[diffraction] " + msg)


## 底部读数：只讲「算了几个距离」，不再混进光强峰值
## （那个值和色标条的 0..1 刻度是两套语义，摆在一起只会让人看不懂）。
func _update_count_label() -> void:
	if _count_label == null:
		return
	if _total_columns <= 0:
		_count_label.text = "已算 %d / — 个距离" % _received
	else:
		_count_label.text = "已算 %d / %d 个距离" % [_received, _total_columns]


# ---------------------------------------------------------------- 网络

func _on_connected() -> void:
	_set_status("已连接后端", "ok")
	NetClient.send_json({"type": "hello"})
	_log("已连接后端，可以开始计算。")
	if _autostart:
		_autostart = false
		_on_start_pressed()


func _on_disconnected() -> void:
	_set_status("未连接后端", "error")
	_running = false
	_update_buttons()
	_log("与后端断开连接（后端已退出？见「后端启动失败」提示）。")


## 后端进程状态（由 BackendLauncher 发来）：已连上 / 正在拉起 / 起不来。
func _on_backend_status(text: String, level: String) -> void:
	_set_status(text, level)
	_backend_button.visible = (level == "error")
	if level == "error":
		_log(text)


func _on_backend_failed(reason: String) -> void:
	_log("后端没起来：%s\n  可以点标题栏的「启动后端」重试，或在 project.godot 的 [backend] 段"
			% reason)


func _on_data(payload: Variant) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		return
	match str(payload.get("type", "")):
		"rs_begin":
			_on_begin(payload)
		"rs_col":
			_on_column(payload)
		"rs_params":
			_on_params(payload)
		"rs_done":
			_on_done(payload)
		"rs_error":
			_last_error = str(payload.get("message", ""))
			_running = false
			_update_buttons()
			_update_count_label()
			_log("后端报错：%s" % _last_error)
		"progress":
			_progress.value = float(payload.get("value", 0.0))
		"hello_ack":
			pass
		"ack":
			pass
		"sample":
			pass


func _on_begin(payload: Dictionary) -> void:
	var columns := int(payload.get("columns", 0))
	var rows := int(payload.get("rows", 0))
	if columns <= 0 or rows <= 0:
		_log("后端给的画布尺寸不合法：%d × %d" % [columns, rows])
		return
	_total_columns = columns
	_received = 0
	_map.setup(columns, rows)
	_map.set_z_range(float(payload.get("z0", 0.0)), float(payload.get("z1", 1.0)))
	_map.set_y_range(float(payload.get("y0", -1.0)), float(payload.get("y1", 1.0)))
	_update_count_label()
	_log("画布 %d 列（z）× %d 行（y），开始逐距离刷新。" % [columns, rows])


func _on_column(payload: Dictionary) -> void:
	var index := int(payload.get("i", -1))
	_map.set_column_b64(index, str(payload.get("data", "")))
	if index >= 0:
		_received = maxi(_received, index + 1)
	_update_count_label()
	# 量程以**后端算出的全局最大值**为准（`vmax` 是整行的峰值，不只是显示窗口内的），
	# 前端自己也有一份按列累积的峰值，只在后端没给 vmax 时才回退到它。
	if _map.auto_range:
		var vmax := float(payload.get("vmax", 0.0))
		if vmax > 0.0:
			_map.set_peak(vmax)


func _on_params(payload: Dictionary) -> void:
	if bool(payload.get("ok", false)):
		_apply_params(payload.get("params", {}))
	else:
		_log("读取参数文件失败：%s" % str(payload.get("message", "")))


func _on_done(payload: Dictionary) -> void:
	_running = false
	_update_buttons()
	_update_count_label()
	var columns := int(payload.get("columns", 0))
	var elapsed := float(payload.get("elapsed", 0.0))
	if bool(payload.get("error", false)) or not _last_error.is_empty():
		# 出错时后端也会发 rs_done（前端要靠它收尾），但那不是「算完了」——
		# 别让这条消息把 rs_error 的报错覆盖成一句「计算完成」。
		_log("计算已中断（出错）：已算 %d / %d 个距离。%s" % [columns, _total_columns, _last_error])
		return
	if bool(payload.get("cancelled", false)):
		_log("已中止：算了 %d / %d 个距离，用时 %.1f s。" % [columns, _total_columns, elapsed])
	else:
		_progress.value = 100.0
		_log("计算完成：%d 个距离，用时 %.1f s。" % [columns, elapsed])


func _on_cell_hovered(z: float, y: float, value: float) -> void:
	_hover_label.text = "z %s｜y %s μm｜I %s" % [Fmt.num(z / UM, 4), Fmt.num(y / UM, 4), Fmt.num(value, 4)]
