class_name ColumnTable
extends Control
## 可拖拽调列宽的表格基类 —— `DataTable`（平表）与 `TreeTable`（树表）共用。
##
## 为什么自己写：Godot 的 `Tree` **不支持拖拽调列宽**（`get_column_width()` 只读），
## 所以本项目的表格一律 `_draw()` 自绘。而「列宽拖拽」这段逻辑跟表里放什么数据无关，
## 于是抽到基类里：子类只需要实现 `_draw()`。
##
## 子类要做三件事：
##   1. 覆写 `_theme_type()` 返回自己的主题类型名（`&"DataTable"` / `&"TreeTable"`）；
##   2. 覆写 `_draw()`，用 `_col_w()` / `_sep_x()` / `_theme_color()` 画内容；
##   3. 覆写 `get_required_height()` 报告内容需要的高度（基类默认只有表头高）。
##
## **高度由内容决定，不需要调用方手算**：「表头 + 行数 × 行高」交给
## `_get_minimum_size()` 报给容器，容器会自己腾地方。所以调用方只要管宽度
## （`set_min_width()`，或者直接设 `custom_minimum_size.x`）；
## **不要去写 `custom_minimum_size.y`** —— 那是「至少这么高」，写 0 会覆盖掉自动高度，
## 控件就会在自己的矩形之外画内容（表现出来就是表格被裁掉、行溢到卡片外面）。
##
## 列宽规则：拖动表头相邻列之间的分隔线调列宽（最小 `TABLE_MIN_COL`）；
## **最后一列自动填满剩余宽度**，不参与拖拽。颜色从 `_theme_type()` 的类型读取
## （回退到 ThemePalette 令牌），因此随全局主题统一调整。

const _HIT := 6.0        # 分隔线命中范围（px）

var _titles: PackedStringArray = []
var _widths: PackedFloat32Array = []

var _drag_col := -1       # 正在拖拽的分隔线左侧列索引
var _drag_start_x := 0.0
var _drag_start_w := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


## 设置列标题与初始列宽（宽度个数应与标题个数一致；最后一列宽度会被忽略、自动填满）。
func set_columns(titles: PackedStringArray, widths: PackedFloat32Array) -> void:
	_titles = titles
	_widths = widths
	_on_columns_changed()
	queue_redraw()


func get_columns() -> PackedStringArray:
	return _titles


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


## 内容需要的高度（子类覆写；基类只算表头）。
func get_required_height() -> float:
	return ThemePalette.TABLE_HEADER_H


## 设置表格宽度。高度不用管：它由 `get_required_height()` 自动报给容器。
func set_min_width(width: float) -> void:
	var ms := custom_minimum_size
	ms.x = width
	custom_minimum_size = ms


## 内容高度的上报口。走 `_get_minimum_size()` 而不是去写 `custom_minimum_size.y`，
## 是因为容器取的是「两者的大者」：调用方随便设 `custom_minimum_size`（哪怕是 0）
## 都不会把自动高度弄丢。**别改成自己写 custom_minimum_size.y** ——
## 之前就是这么写的，结果调用方一句 `custom_minimum_size = Vector2(390, 0)`
## 就把高度清零了，控件随即在自己的矩形之外画表格（表现为表格被裁掉）。
func _get_minimum_size() -> Vector2:
	return Vector2(0.0, get_required_height())


## 列数 / 列宽 / 行数变化后的统一入口：让容器重新问一次最小尺寸。
## 子类可覆写做更多事（记得调 super）。
func _on_columns_changed() -> void:
	update_minimum_size()


## 从主题类型 `_theme_type()` 取颜色，未定义时回退到令牌默认值。
func _theme_color(name: StringName, fallback: Color) -> Color:
	var t := _theme_type()
	return get_theme_color(name, t) if has_theme_color(name, t) else fallback


## 本表使用的主题类型名（子类覆写）。
func _theme_type() -> StringName:
	return &"ColumnTable"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# 只有表头那一行才能起拖；表体的点击留给子类自己处理（见 TreeTable）
			if event.position.y <= ThemePalette.TABLE_HEADER_H:
				_drag_col = _hit_sep(event.position.x)
				if _drag_col >= 0:
					_drag_start_x = event.position.x
					_drag_start_w = _widths[_drag_col]
					accept_event()
					return
		elif _drag_col >= 0:
			_drag_col = -1
			accept_event()
			return
		_on_body_input(event)
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
	else:
		_on_body_input(event)


## 表体（表头以下）的输入钩子，供子类做行选择/展开等。默认忽略。
func _on_body_input(_event: InputEvent) -> void:
	pass
