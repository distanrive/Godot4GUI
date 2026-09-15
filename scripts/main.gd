extends Control
## 衍射模拟前端（把原来的「正弦采样 + 折线图」演示换成 Rayleigh-Sommerfeld 衍射）。
##
## 流程：
##   左侧填参数（或用 FileDropBox 拖入 `.py` / `.json` 参数文件自动填）→ 点「开始计算」
##   → 后端每算出一个 z 就推一列光强 → `IntensityMap` 逐列追加、实时刷新伪彩图。
##
## 后端脚本：`backend/rayleigh_sommerfeld.py`（作业脚本 `Rayleigh-Sommerfeld-assignment1.py`
## 的流式改写版，物理与数值一致）；协议见 CLAUDE.md 与 `docs/plotting-alternatives.md`。
##
## 单位约定：界面上一律用 μm，发给后端时换算成 m。
## 样式：不在本文件里写死颜色/字号，全部用 ThemePalette 令牌与语义变体。

const UM := 1.0e-6          # 微米 → 米

var _map: IntensityMap
var _progress: ProgressBar
var _status: Label
var _running_label: FlashLabel
var _log_label: Label
var _range_label: Label
var _hover_label: Label

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
var _stop_button: Button
var _params_button: Button

var _running := false
var _params_path := ""
var _autostart := false     # --autostart：连上后端就自动开算（自测/演示用）


func _ready() -> void:
	_build_ui()
	# 可选命令行参数（放在 `--` 之后），便于脚本化演示与自测：
	#   godot res://scenes/main.tscn -- --preset=fast --autostart
	for arg in OS.get_cmdline_user_args():
		if arg == "--preset=fast":
			_apply_preset("fast")
		elif arg == "--autostart":
			_autostart = true
	NetClient.connected.connect(_on_connected)
	NetClient.disconnected.connect(_on_disconnected)
	NetClient.data_received.connect(_on_data)
	NetClient.connect_to()
	_update_buttons()


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
	_stop_button = _make_button("停止", "", _on_stop_pressed)
	header.add_child(_start_button)
	header.add_child(_stop_button)

	_status = Label.new()
	_status.text = "未连接后端"
	_status.theme_type_variation = "StatusIdle"
	header.add_child(_status)
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
	_f_stride = _add_field(grid, "z 步进", "1", "")
	_f_ym = _add_field(grid, "显示窗口 ±y", "10", "μm")

	var note := Label.new()
	note.text = "dx = L/N 同时是 z 的步长（与原作业一致）。N 越大越精细、也越慢。"
	note.theme_type_variation = "Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	params.content.add_child(note)

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

	_range_label = Label.new()
	_range_label.text = "量程 —"
	_range_label.theme_type_variation = "Subtitle"
	bottom.add_child(_range_label)
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

	bar.add_child(_make_button("重置量程", "GhostButton", func():
		_map.auto_range = true
		_map.display_range = Vector2(0.0, 0.0)
		_map.clear()
		_update_range_label()))

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
	field.label_width = 104.0
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

## 读一个输入框里的数字（读不出来就用 last 并提示，不静默改成 0）。
func _num(field: LabeledLineEdit, fallback: float) -> float:
	var text := field.text.strip_edges()
	if not text.is_valid_float():
		_log("「%s」不是数字（%s），沿用上一次的值 %s" % [field.label_text, text, Fmt.num(fallback, 6)])
		return fallback
	return text.to_float()


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
	_log("已读入参数：%s" % ", ".join(applied))


func _apply_preset(which: String) -> void:
	if which == "fast":
		_f_samples.text = "384"
		_f_stride.text = "4"
		_f_z1.text = "100"
		_log("已套用「快速预览」：N=384、z 步进 4（约十几秒出图）。")
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


# ---------------------------------------------------------------- 运行

func _on_start_pressed() -> void:
	var params := _collect_params()
	var columns := int(ceil((params["z_max"] - params["z_min"]) / params["z_stride"]
			/ (params["width"] / float(params["samples"])))) + 1
	_map.clear()
	_progress.value = 0.0
	_running = true
	_update_buttons()
	_log("开始计算：N=%d，约 %d 个距离，每算出一个就刷新一次图像。" % [params["samples"], columns])
	NetClient.send_command("rs_start", params)


func _on_stop_pressed() -> void:
	NetClient.send_command("rs_stop")
	_log("已请求停止。")


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
	_stop_button.disabled = not _running
	_running_label.visible = _running
	if _running:
		_running_label.start()
	else:
		_running_label.stop()


func _set_status(text: String, variation: String) -> void:
	_status.text = text
	_status.theme_type_variation = variation


func _log(msg: String) -> void:
	if _log_label != null:
		_log_label.text = msg
	print("[diffraction] " + msg)


func _update_range_label() -> void:
	if _range_label == null or _map == null:
		return
	var peak := _map.get_peak()
	_range_label.text = "量程 %s" % ("—" if peak <= 0.0 else Fmt.num(peak, 4))


# ---------------------------------------------------------------- 网络

func _on_connected() -> void:
	_set_status("已连接后端", "StatusOk")
	NetClient.send_json({"type": "hello"})
	_log("已连接后端，可以开始计算。")
	if _autostart:
		_autostart = false
		_on_start_pressed()


func _on_disconnected() -> void:
	_set_status("未连接后端", "StatusError")
	_running = false
	_update_buttons()
	_log("与后端断开连接（后端未启动？先跑 python backend/main.py）。")


func _on_data(payload: Variant) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		return
	match str(payload.get("type", "")):
		"rs_begin":
			_on_begin(payload)
		"rs_col":
			_map.set_column_b64(int(payload.get("i", -1)), str(payload.get("data", "")))
			_update_range_label()
		"rs_params":
			_on_params(payload)
		"rs_done":
			_on_done(payload)
		"rs_error":
			_running = false
			_update_buttons()
			_log("后端报错：%s" % str(payload.get("message", "")))
		"progress":
			_progress.value = float(payload.get("value", 0.0))
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
	_map.setup(columns, rows)
	_map.set_z_range(float(payload.get("z0", 0.0)), float(payload.get("z1", 1.0)))
	_map.set_y_range(float(payload.get("y0", -1.0)), float(payload.get("y1", 1.0)))
	_update_range_label()
	_log("画布 %d 列（z）× %d 行（y），开始逐距离刷新。" % [columns, rows])


func _on_params(payload: Dictionary) -> void:
	if bool(payload.get("ok", false)):
		_apply_params(payload.get("params", {}))
	else:
		_log("读取参数文件失败：%s" % str(payload.get("message", "")))


func _on_done(payload: Dictionary) -> void:
	_running = false
	_update_buttons()
	if bool(payload.get("cancelled", false)):
		_log("已停止：算了 %d 个距离，用时 %.1f s。" % [
			int(payload.get("columns", 0)), float(payload.get("elapsed", 0.0))])
	else:
		_progress.value = 100.0
		_log("计算完成：%d 个距离，用时 %.1f s。" % [
			int(payload.get("columns", 0)), float(payload.get("elapsed", 0.0))])


func _on_cell_hovered(z: float, y: float, value: float) -> void:
	_hover_label.text = "z %s｜y %s μm｜I %s" % [Fmt.num(z / UM, 4), Fmt.num(y / UM, 4), Fmt.num(value, 4)]
