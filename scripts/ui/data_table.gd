class_name DataTable
extends Control
## 可拖拽调列宽的数据表（Godot 的 Tree 不支持拖拽调列宽，这里用 _draw 自绘实现）。
##
## 用法：
##   var t := DataTable.new()
##   t.set_columns(["参数", "数值", "单位"], [180.0, 120.0, 90.0])
##   t.set_rows([["设备", "—", "—"], ["通道 1", "10.0", "V"]])
##
## 拖动表头相邻列之间的分隔线即可调整列宽（最小 40px）；最后一列自动填满剩余宽度。
## 颜色从主题类型 "DataTable" 读取（回退到 ThemePalette 令牌），尺寸走 ThemePalette 令牌，
## 因此随全局主题统一调整，也支持 per-control 主题覆盖。

const _HIT := 6.0        # 分隔线命中范围（px）

var _titles: PackedStringArray = []
var _widths: PackedFloat32Array = []
var _rows: Array = []    # 每行是 Array（String 或可 str() 的值）

var _drag_col := -1       # 正在拖拽的分隔线左侧列索引
var _drag_start_x := 0.0
var _drag_start_w := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func set_columns(titles: PackedStringArray, widths: PackedFloat32Array) -> void:
	_titles = titles
	_widths = widths
	queue_redraw()


func set_rows(rows: Array) -> void:
	_rows = rows
	queue_redraw()


## 列 i 的实际绘制宽度（最后一列自动填满剩余宽度）。
func _col_w(i: int) -> float:
	if _widths.is_empty():
		return 0.0
	if i == _widths.size() - 1:
		# 最后一列填满剩余宽度（至少留 TABLE_MIN_COL），避免被其它列挤到溢出台面
		var used := 0.0
		for k in range(_widths.size() - 1):
			used += _widths[k]
		return maxf(size.x - used, ThemePalette.TABLE_MIN_COL)
	return _widths[i]


## 第 i 条分隔线（列 i 的右边界）的 x 坐标。
func _sep_x(i: int) -> float:
	var x := 0.0
	for k in range(i + 1):
		x += _col_w(k)
	return x


## 返回命中的分隔线左侧列索引，未命中返回 -1（最后一列不参与拖拽）。
func _hit_sep(mx: float) -> int:
	var best := -1
	var best_d := _HIT
	for i in range(_widths.size() - 1):
		var d := absf(_sep_x(i) - mx)
		if d < best_d:
			best_d = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y <= ThemePalette.TABLE_HEADER_H:
				_drag_col = _hit_sep(event.position.x)
				if _drag_col >= 0:
					_drag_start_x = event.position.x
					_drag_start_w = _widths[_drag_col]
					accept_event()
		elif _drag_col >= 0:
			_drag_col = -1
			accept_event()
	elif event is InputEventMouseMotion and _drag_col >= 0:
		# 拖拽列宽上下限：≥ TABLE_MIN_COL，且不能把其它列挤到连最后一列都放不下
		var other := 0.0
		for k in range(_widths.size() - 1):
			if k != _drag_col:
				other += _widths[k]
		var lo := ThemePalette.TABLE_MIN_COL
		var hi := maxf(size.x - other - ThemePalette.TABLE_MIN_COL, lo)
		_widths[_drag_col] = clampf(_drag_start_w + (event.position.x - _drag_start_x), lo, hi)
		queue_redraw()
		accept_event()


func _draw() -> void:
	if _titles.is_empty():
		return
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()

	var header_h := ThemePalette.TABLE_HEADER_H
	var row_h := ThemePalette.TABLE_ROW_H
	var pad := ThemePalette.TABLE_PAD
	var cell_bg := _theme_color("cell_bg_color", ThemePalette.SURFACE)
	var header_bg := _theme_color("header_bg_color", ThemePalette.SURFACE_ALT)
	var grid := _theme_color("grid_color", ThemePalette.BORDER)
	var text := _theme_color("text_color", ThemePalette.TEXT)
	var header_text := _theme_color("header_text_color", ThemePalette.TEXT)

	# 表体底色
	draw_rect(Rect2(0, header_h, size.x, size.y - header_h), cell_bg, true)
	# 表头底色
	draw_rect(Rect2(0, 0, size.x, header_h), header_bg, true)

	# 列分隔线（贯穿整表）+ 表头文字
	for i in range(_titles.size()):
		var w := _col_w(i)
		var sx := _sep_x(i)
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), grid, 1.0)
		draw_string(font, Vector2(sx - w + pad, header_h / 2.0 + fs * 0.35), _titles[i],
			HORIZONTAL_ALIGNMENT_LEFT, w - pad * 2.0, fs, header_text)

	# 表体行
	var y := header_h
	for r in _rows.size():
		draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)
		var row: Array = _rows[r]
		var cx := 0.0
		for c in _titles.size():
			var cell := str(row[c]) if c < row.size() else ""
			draw_string(font, Vector2(cx + pad, y + row_h / 2.0 + fs * 0.35), cell,
				HORIZONTAL_ALIGNMENT_LEFT, _col_w(c) - pad * 2.0, fs, text)
			cx += _col_w(c)
		y += row_h

	# 底边线
	draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)


## 从主题类型 "DataTable" 取颜色，未定义时回退到令牌默认值。
func _theme_color(name: String, fallback: Color) -> Color:
	return get_theme_color(name, &"DataTable") if has_theme_color(name, &"DataTable") else fallback
