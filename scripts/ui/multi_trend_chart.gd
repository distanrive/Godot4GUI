class_name MultiTrendChart
extends Control
## 多子图实时折线图：垂直堆叠 N 个子图，共享 X 轴（时间），每个子图独立 Y 轴与曲线。
## 对应 SiTrendChart 的「多子图」扩展（如 TauPlot 的多子图能力），零依赖 _draw 自绘。
## 颜色从主题类型 "MultiTrendChart" 读取（回退到 ThemePalette 令牌），曲线色由每个子图指定。
##
## 用法：
##   var c := MultiTrendChart.new()
##   var t := c.add_plot("温度", 0.0, 100.0)                 # 返回子图索引
##   var p := c.add_plot("压力", 0.0, 10.0, ThemePalette.SUCCESS)
##   c.add_point(t, 0.0, 42.0)
##   c.add_point(p, 0.0, 3.2)

@export var line_width := 2.0
@export var max_points := 2000
@export var grid_columns := 8
@export var grid_rows := 3          # 每个子图水平网格线数
@export var left_margin := 56.0
@export var top_margin := 8.0
@export var right_margin := 8.0
@export var bottom_margin := 8.0

var _plots: Array = []   # 每个元素：Dictionary{title, points, y_min, y_max, color}


func _ready() -> void:
	resized.connect(queue_redraw)


## 新增一个子图，返回索引；color 不传时按 CHART_SERIES 循环取默认色。
func add_plot(title: String, y_min: float, y_max: float, color := Color.TRANSPARENT) -> int:
	if color == Color.TRANSPARENT:
		var series := ThemePalette.CHART_SERIES
		color = series[_plots.size() % series.size()]
	_plots.append({
		"title": title,
		"points": PackedVector2Array(),
		"y_min": y_min,
		"y_max": y_max,
		"color": color,
	})
	queue_redraw()
	return _plots.size() - 1


func add_point(plot: int, x: float, y: float) -> void:
	if plot < 0 or plot >= _plots.size():
		return
	var pts: PackedVector2Array = _plots[plot]["points"]
	pts.append(Vector2(x, y))
	if pts.size() > max_points:
		pts.remove_at(0)
	_plots[plot]["points"] = pts
	queue_redraw()


func set_points(plot: int, points: PackedVector2Array) -> void:
	if plot < 0 or plot >= _plots.size():
		return
	_plots[plot]["points"] = points
	queue_redraw()


func clear_all() -> void:
	for p in _plots:
		p["points"] = PackedVector2Array()
	queue_redraw()


func get_plot_count() -> int:
	return _plots.size()


## 所有子图共享的 X 范围（取各子图数据的最早/最晚 x，保证对齐）。
func _x_range() -> Vector2:
	var x0 := INF
	var x1 := -INF
	var found := false
	for p in _plots:
		var pts: PackedVector2Array = p["points"]
		if pts.size() > 0:
			found = true
			x0 = minf(x0, pts[0].x)
			x1 = maxf(x1, pts[pts.size() - 1].x)
	if not found:
		return Vector2(0.0, 1.0)
	if x1 - x0 < 1e-6:
		x1 = x0 + 1.0
	return Vector2(x0, x1)


func _draw() -> void:
	if _plots.is_empty():
		return
	var bg := _theme_color("background_color", ThemePalette.CHART_BG)
	var grid := _theme_color("grid_color", ThemePalette.CHART_GRID)
	var axis := _theme_color("axis_color", ThemePalette.CHART_AXIS)
	var tick := _theme_color("tick_text_color", ThemePalette.CHART_TEXT)

	draw_rect(Rect2(Vector2.ZERO, size), bg, true)

	var xr := _x_range()
	var plot_w := size.x - left_margin - right_margin
	var total_h := size.y - top_margin - bottom_margin
	var plot_h := total_h / _plots.size()

	# 左侧 Y 轴 + 底部共享 X 轴
	draw_line(Vector2(left_margin, top_margin), Vector2(left_margin, size.y - bottom_margin), axis, 1.0)
	draw_line(Vector2(left_margin, size.y - bottom_margin), Vector2(size.x - right_margin, size.y - bottom_margin), axis, 1.0)

	for i in range(_plots.size()):
		var rect := Rect2(left_margin, top_margin + i * plot_h, plot_w, plot_h)
		_draw_plot(rect, _plots[i], xr, grid, tick)


## 绘制单个子图：网格 + Y 刻度 + 标题 + 曲线。
func _draw_plot(rect: Rect2, p: Dictionary, xr: Vector2, grid: Color, tick: Color) -> void:
	var y_min: float = p["y_min"]
	var y_max: float = p["y_max"]
	if y_max - y_min < 1e-6:
		y_max = y_min + 1.0

	# 水平网格 + Y 刻度
	for r in range(grid_rows + 1):
		var fy := rect.position.y + rect.size.y * r / grid_rows
		draw_line(Vector2(rect.position.x, fy), Vector2(rect.end.x, fy), grid, 1.0)
		var v := y_max - (y_max - y_min) * r / grid_rows
		draw_string(get_theme_default_font(), Vector2(rect.position.x - 6.0, fy + 4.0),
			"%.1f" % v, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, ThemePalette.FONT_XS, tick)
	# 垂直网格
	for c in range(grid_columns + 1):
		var fx := rect.position.x + rect.size.x * c / grid_columns
		draw_line(Vector2(fx, rect.position.y), Vector2(fx, rect.end.y), grid, 1.0)

	# 子图标题（左上角，用曲线色标识对应关系）
	draw_string(get_theme_default_font(), Vector2(rect.position.x + 4.0, rect.position.y + 14.0),
		str(p["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, ThemePalette.FONT_SM, p["color"])

	# 曲线
	var points: PackedVector2Array = p["points"]
	if points.size() < 2:
		return
	var pts := PackedVector2Array()
	for pt in points:
		var px := rect.position.x + (pt.x - xr.x) / (xr.y - xr.x) * rect.size.x
		var py := rect.position.y + rect.size.y - (pt.y - y_min) / (y_max - y_min) * rect.size.y
		pts.append(Vector2(px, py))
	draw_polyline(pts, p["color"], line_width, true)


## 从主题类型 "MultiTrendChart" 取颜色，未定义时回退到令牌默认值。
func _theme_color(name: String, fallback: Color) -> Color:
	return get_theme_color(name, &"MultiTrendChart") if has_theme_color(name, &"MultiTrendChart") else fallback
