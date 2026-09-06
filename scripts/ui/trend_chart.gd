class_name TrendChart
extends Control
## 实时折线图（对应 PyQt-SiliconUI 的 SiTrendChart）。
##
## 用法：
##   chart.add_point(x, y)     追加一个采样点，自动重绘
##   chart.set_points(points)  一次性设置整条曲线
##   chart.clear()             清空
##
## 内部用 PackedVector2Array 缓存，超出 max_points 时丢弃最旧的点（环形缓冲语义）。
## 用 _draw() + draw_polyline 绘制，避免引入图表 addon 依赖。
## 颜色从主题类型 "TrendChart" 读取（回退到 ThemePalette 令牌），随全局主题统一调整。

@export var line_width := 2.0

@export var max_points := 2000
@export var y_min := 0.0
@export var y_max := 100.0
@export var auto_scale := false          # true 时按数据自动缩放 Y 轴
@export var grid_columns := 8
@export var grid_rows := 4

@export var left_margin := 56.0
@export var top_margin := 8.0
@export var right_margin := 8.0
@export var bottom_margin := 8.0

var _points := PackedVector2Array()


func _ready() -> void:
	resized.connect(queue_redraw)


func add_point(x: float, y: float) -> void:
	_points.append(Vector2(x, y))
	if _points.size() > max_points:
		_points.remove_at(0)
	if auto_scale:
		_recalc_y_range()
	queue_redraw()


func set_points(points: PackedVector2Array) -> void:
	_points = points
	if auto_scale:
		_recalc_y_range()
	queue_redraw()


func clear() -> void:
	_points = PackedVector2Array()
	queue_redraw()


func _recalc_y_range() -> void:
	if _points.is_empty():
		return
	var lo := _points[0].y
	var hi := _points[0].y
	for p in _points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	if hi - lo < 1e-6:
		hi = lo + 1.0
	var pad := (hi - lo) * 0.1
	y_min = lo - pad
	y_max = hi + pad


func _get_plot_rect() -> Rect2:
	return Rect2(left_margin, top_margin,
		size.x - left_margin - right_margin,
		size.y - top_margin - bottom_margin)


## 数据坐标 -> 像素坐标。
func _to_pixel(p: Vector2, plot: Rect2, x0: float, x1: float) -> Vector2:
	var px := plot.position.x + (p.x - x0) / (x1 - x0) * plot.size.x
	var py := plot.position.y + plot.size.y - (p.y - y_min) / (y_max - y_min) * plot.size.y
	return Vector2(px, py)


func _draw() -> void:
	var plot := _get_plot_rect()

	var bg := _theme_color("background_color", ThemePalette.CHART_BG)
	var grid := _theme_color("grid_color", ThemePalette.CHART_GRID)
	var axis := _theme_color("axis_color", ThemePalette.CHART_AXIS)
	var tick := _theme_color("tick_text_color", ThemePalette.CHART_TEXT)
	var line := _theme_color("line_color", ThemePalette.CHART_LINE)

	draw_rect(Rect2(Vector2.ZERO, size), bg, true)

	# 网格 + Y 轴刻度
	for i in range(grid_rows + 1):
		var y := plot.position.y + plot.size.y * i / grid_rows
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid, 1.0)
		var t := y_max - (y_max - y_min) * i / grid_rows
		draw_string(get_theme_default_font(), Vector2(plot.position.x - 6.0, y + 4.0),
			"%.1f" % t, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, ThemePalette.FONT_XS, tick)
	for i in range(grid_columns + 1):
		var x := plot.position.x + plot.size.x * i / grid_columns
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), grid, 1.0)

	# 坐标轴
	draw_line(plot.position, Vector2(plot.position.x, plot.end.y), axis, 1.0)
	draw_line(plot.position, Vector2(plot.end.x, plot.position.y), axis, 1.0)

	if _points.size() < 2:
		return

	var x0 := _points[0].x
	var x1 := _points[_points.size() - 1].x
	if x1 - x0 < 1e-6:
		x1 = x0 + 1.0

	var pts := PackedVector2Array()
	for p in _points:
		pts.append(_to_pixel(p, plot, x0, x1))
	draw_polyline(pts, line, line_width, true)


## 从主题类型 "TrendChart" 取颜色，未定义时回退到令牌默认值。
func _theme_color(name: String, fallback: Color) -> Color:
	return get_theme_color(name, &"TrendChart") if has_theme_color(name, &"TrendChart") else fallback
