class_name FileDropBox
extends Control
## 文件拖放框：**虚线外框** + 中间一个「选择文件…」按钮。
##
## 交互（两条路径等价，都是「输入一个路径」）：
##   1. 从系统资源管理器把文件拖进来 —— 落点即路径，触发 `path_changed`；
##   2. 点中间按钮（或点框内空白处）—— 调起系统文件资源管理器选文件。
##
## 拖拽悬停时边框与底色会高亮，松开即写入路径，因此不需要额外的确认步骤。
##
## 用法：
##   var box := FileDropBox.new()
##   box.hint_text = "拖入参数文件（.json / .py）"
##   box.filters = PackedStringArray(["*.json ; JSON 参数文件", "*.py ; Python 脚本"])
##   box.path_changed.connect(func(p): print("选中 ", p))
##   add_child(box)
##
## 颜色/虚线/圆角全部走主题类型 "FileDropBox"（回退到 ThemePalette 令牌），
## 想统一改样式只改 `scripts/theme/theme_palette.gd`。

## 路径变化（拖放或选择文件后触发）。
signal path_changed(path: String)

@export var hint_text := "把文件拖到这里，或" :
	set(v):
		hint_text = v
		if _hint != null:
			_hint.text = v

@export var button_text := "选择文件…" :
	set(v):
		button_text = v
		if _button != null:
			_button.text = v

@export var dialog_title := "选择文件"

## FileDialog 过滤器，格式见 Godot 文档：「*.png ; PNG 图片」。
@export var filters := PackedStringArray(["* ; 所有文件"])

## true = 调起系统（Windows 资源管理器）原生对话框；false = 用 Godot 内置对话框（跟随全局主题）。
@export var use_native_dialog := true

## 拖入多个文件时只取第一个（本控件表达的是「一个路径」）。
@export var path := "" :
	set(v):
		path = v
		_refresh()

var _hint: Label
var _button: Button
var _clear_button: Button
var _path_label: Label
var _dialog: FileDialog

var _hovered := false
var _drag_over := false
var _last_drop_msec := -100000


func _init() -> void:
	# 子节点在 _init 里构建，保证 new() 之后即可访问（与 TitledGroup / LabeledLineEdit 一致）。
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vb)

	_hint = Label.new()
	_hint.text = hint_text
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.theme_type_variation = "DropHint"
	vb.add_child(_hint)

	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)

	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(buttons)

	_button = Button.new()
	_button.text = button_text
	_button.theme_type_variation = "AccentButton"
	_button.pressed.connect(open_dialog)
	buttons.add_child(_button)

	_clear_button = Button.new()
	_clear_button.text = "清除"
	_clear_button.theme_type_variation = "GhostButton"
	_clear_button.tooltip_text = "清空已选路径"
	_clear_button.visible = false
	_clear_button.pressed.connect(func(): set_path(""))
	buttons.add_child(_clear_button)

	_path_label = Label.new()
	_path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_path_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_label.theme_type_variation = "PathLabel"
	vb.add_child(_path_label)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = maxf(custom_minimum_size.y, ThemePalette.DROPBOX_MIN_H)
	resized.connect(queue_redraw)
	mouse_entered.connect(func(): _set_hovered(true))
	mouse_exited.connect(func(): _set_hovered(false))
	tooltip_text = "拖入文件，或点击选择文件"
	_refresh()

	# 兜底通道：部分平台/嵌入窗口下，系统文件拖放只会发 Window.files_dropped（不带落点），
	# 这里在「鼠标正好在本框内」时接住，保证拖放一定可用（GUI 通道已处理时会被去重）。
	var win := get_window()
	if win != null and not win.files_dropped.is_connected(_on_window_files_dropped):
		win.files_dropped.connect(_on_window_files_dropped)


## 写入路径并通知（拖放/选择文件/业务代码都应走这里）。
func set_path(p: String, notify := true) -> void:
	if p == path:
		_refresh()
		return
	path = p
	if notify:
		path_changed.emit(path)


func clear() -> void:
	set_path("")


## 调起文件对话框：默认走系统资源管理器（use_native_dialog = true）。
func open_dialog() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.title = dialog_title
		_dialog.filters = filters
		_dialog.file_selected.connect(func(p: String): set_path(p))
		add_child(_dialog)
	else:
		_dialog.title = dialog_title
		_dialog.filters = filters
	_dialog.use_native_dialog = use_native_dialog
	_dialog.current_dir = _start_dir()
	_dialog.popup_centered_ratio(0.55)   # 原生对话框忽略尺寸参数


## 接住 OS 拖放（Window.files_dropped 兜底通道 / 业务代码主动调用）。
## 返回是否被接受。
func accept_dropped_files(files: PackedStringArray) -> bool:
	if files.is_empty():
		return false
	_last_drop_msec = Time.get_ticks_msec()
	set_path(files[0])
	return true


func _start_dir() -> String:
	if not path.is_empty():
		var d := path.get_base_dir()
		if DirAccess.dir_exists_absolute(d):
			return d
	return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)


func _refresh() -> void:
	if _path_label == null:
		return
	_path_label.text = path if not path.is_empty() else "（尚未选择文件）"
	_path_label.tooltip_text = path
	if _clear_button != null:
		_clear_button.visible = not path.is_empty()
	queue_redraw()


func _set_hovered(v: bool) -> void:
	if _hovered == v:
		return
	_hovered = v
	queue_redraw()


func _set_drag_over(v: bool) -> void:
	if _drag_over == v:
		return
	_drag_over = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# 点框内空白处 = 点按钮（按钮自身会先吃掉自己的点击，不会重复触发）。
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		open_dialog()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_drag_over(false)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var ok := not extract_files(data).is_empty()
	_set_drag_over(ok and Rect2(Vector2.ZERO, size).has_point(at_position))
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_set_drag_over(false)
	var files := extract_files(data)
	if files.is_empty():
		return
	_last_drop_msec = Time.get_ticks_msec()
	set_path(files[0])


func _on_window_files_dropped(files: PackedStringArray) -> void:
	if Time.get_ticks_msec() - _last_drop_msec < 300:
		return   # GUI 拖放通道已经处理过，避免同一份文件被写入两次
	if not get_global_rect().has_point(get_global_mouse_position()):
		return   # 界面上有多个拖放框时，只接住鼠标所在的那一个
	accept_dropped_files(files)


## 从拖放数据里取出文件路径列表，兼容多种来源（PackedStringArray / Array / String / 字典）。
static func extract_files(data: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if data is PackedStringArray:
		out = data
	elif data is Array:
		for f in data:
			out.append(str(f))
	elif data is String:
		out.append(data)
	elif data is Dictionary:
		var files: Variant = data.get("files", null)
		if files is PackedStringArray:
			out = files
		elif files is Array:
			for f in files:
				out.append(str(f))
	return out


# ---------- 绘制 ----------

func _theme_color(name: StringName, fallback: Color) -> Color:
	return get_theme_color(name, &"FileDropBox") if has_theme_color(name, &"FileDropBox") else fallback


func _draw() -> void:
	var dragging := _drag_over

	var bg := _theme_color(&"bg_color", ThemePalette.SURFACE)
	var border := _theme_color(&"border_color", ThemePalette.BORDER_STRONG)
	if dragging:
		bg = _theme_color(&"bg_drop_color", ThemePalette.ACCENT_SOFT_HOVER)
		border = _theme_color(&"border_drop_color", ThemePalette.ACCENT)
	elif _hovered:
		bg = _theme_color(&"bg_hover_color", ThemePalette.SURFACE_ALT)
		border = _theme_color(&"border_hover_color", ThemePalette.ACCENT)

	# 半像素内缩，避免描边被控件边界裁掉一半
	var rect := Rect2(Vector2.ONE * ThemePalette.DROPBOX_BORDER_W * 0.5,
			size - Vector2.ONE * ThemePalette.DROPBOX_BORDER_W)
	var radius := float(ThemePalette.RADIUS_LG)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, rect)

	_draw_dashed_round_rect(rect, radius, border,
			ThemePalette.DROPBOX_BORDER_W,
			ThemePalette.DROPBOX_DASH, ThemePalette.DROPBOX_GAP)


## 画「圆角虚线矩形」：沿圆角矩形周长走一圈，按 dash/gap 交替落笔。
func _draw_dashed_round_rect(rect: Rect2, radius: float, color: Color,
		width: float, dash: float, gap: float) -> void:
	var pts := round_rect_perimeter(rect, radius)
	var on := true
	var left := dash
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.0001:
			continue
		var t := 0.0
		while t < seg:
			var step := minf(left, seg - t)
			if on and step > 0.0001:
				draw_line(a.lerp(b, t / seg), a.lerp(b, (t + step) / seg), color, width, true)
			t += step
			left -= step
			if left <= 0.0001:
				on = not on
				left = dash if on else gap


## 圆角矩形的周长采样点（顺时针，首尾闭合），供虚线描边使用。
static func round_rect_perimeter(rect: Rect2, radius: float, arc_steps := 5) -> PackedVector2Array:
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var p := rect.position
	var e := rect.end
	var pts := PackedVector2Array()
	if r <= 0.5:
		pts.append(p)
		pts.append(Vector2(e.x, p.y))
		pts.append(e)
		pts.append(Vector2(p.x, e.y))
		pts.append(p)
		return pts

	pts.append(Vector2(p.x + r, p.y))
	pts.append(Vector2(e.x - r, p.y))
	_append_arc(pts, Vector2(e.x - r, p.y + r), r, -PI * 0.5, 0.0, arc_steps)
	pts.append(Vector2(e.x, e.y - r))
	_append_arc(pts, Vector2(e.x - r, e.y - r), r, 0.0, PI * 0.5, arc_steps)
	pts.append(Vector2(p.x + r, e.y))
	_append_arc(pts, Vector2(p.x + r, e.y - r), r, PI * 0.5, PI, arc_steps)
	pts.append(Vector2(p.x, p.y + r))
	_append_arc(pts, Vector2(p.x + r, p.y + r), r, PI, PI * 1.5, arc_steps)
	pts.append(pts[0])
	return pts


static func _append_arc(pts: PackedVector2Array, center: Vector2, radius: float,
		from: float, to: float, steps: int) -> void:
	for i in range(steps + 1):
		var a := lerpf(from, to, float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
