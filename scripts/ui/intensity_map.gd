class_name IntensityMap
extends Control
## 伪彩强度图：把二维标量场（本项目的用途 = Rayleigh-Sommerfeld 衍射的 Z-Y 光强分布）
## 画成带坐标轴与色标条的彩色图，并可**逐列追加**数据边算边显示。
##
## 为什么自己写：Godot 没有原生热力图；而 matplotlib 只能在 Python 端出 PNG，
## 交互（缩放/换配色/读数）全都没有。这里把「标量 → 颜色」交给一块 canvas_item 着色器
## （`themes/shaders/colormap.gdshader`），于是换配色、调显示范围都只是改 uniform，
## 不用重算、不用重新上传数据。详见 `docs/plotting-alternatives.md`。
##
## 用法：
##   var m := IntensityMap.new()
##   m.setup(1000, 1000)                 # 1000 列（z）× 1000 行（y）
##   m.set_z_range(0.1e-6, 100e-6)
##   m.set_y_range(-50e-6, 50e-6)
##   m.set_column(i, values)             # 每算出一个 z 就追加一列
##
## 颜色与尺寸全部走主题类型 "IntensityMap"（回退到 ThemePalette 令牌）。

## 鼠标悬停在图上时给出该点的读数，便于定量看条纹。
signal cell_hovered(z: float, y: float, value: float)
## 画布被重置（`setup()` / `clear()`）时发出：此时显示范围已回到「自动」，
## 界面上那个「自动量程」开关要跟着拨回「开」。
signal range_reset

@export var colormap := Colormaps.DEFAULT:
	set(v):
		colormap = v
		if _material != null:
			_material.set_shader_parameter("colormap", Colormaps.texture(v))
			queue_redraw()

@export var title := ""
@export var x_label := "Z"
@export var y_label := "Y"
@export var colorbar_label := "归一化光强"

## true = 按物理尺度等比显示（和原 matplotlib 的 set_aspect('equal') 一致）。
@export var equal_aspect := true:
	set(v):
		equal_aspect = v
		_relayout()

@export var show_colorbar := true:
	set(v):
		show_colorbar = v
		_relayout()

## true = 显示范围随数据最大值自动增长（等价于原脚本最后做的「全局归一化」，只是在线进行）。
## 关掉它就是「冻结当前显示范围」，便于把两幅图放在同一量程下对比。
@export var auto_range := true

@export var gamma := 1.0:
	set(v):
		gamma = v
		if _material != null:
			_material.set_shader_parameter("gamma", v)

## 显示范围（原始强度单位）。
var display_range := Vector2(0.0, 1.0)
## 坐标范围（单位：米）；画刻度时乘 unit_scale 换成显示单位。
var z_range := Vector2(0.0, 1.0)
var y_range := Vector2(0.0, 1.0)
## 显示单位换算：0.1e-6 m × 1e6 = 0.1 μm。
@export var unit_scale := 1e6
@export var unit_suffix := "μm"

var _image: Image
var _texture: ImageTexture
var _view: TextureRect
var _overlay: Control
var _material: ShaderMaterial
var _cols := 0
var _rows := 0
var _dirty := false
var _hover_cell := Vector2i(-1, -1)
var _hover_valid := false


func _init() -> void:
	# 子节点在 _init 里构建，保证 new() 之后即可访问（与项目其它复合控件一致）。
	_material = ShaderMaterial.new()
	_material.shader = load("res://themes/shaders/colormap.gdshader")
	_material.set_shader_parameter("colormap", Colormaps.texture(colormap))
	_material.set_shader_parameter("vmin", 0.0)
	_material.set_shader_parameter("vmax", 1.0)
	_material.set_shader_parameter("gamma", gamma)

	_view = TextureRect.new()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 强度图逐格显示，不要糊
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.material = _material
	_view.visible = false
	add_child(_view)

	# 叠加层：图像是子节点（画在父节点之后），十字光标只能再叠一层才看得见。
	# 注意：绘制必须发生在「正在绘制的那个 CanvasItem」上，所以把 _overlay 传回去；
	# 直接在本脚本里 draw_* 会画到 IntensityMap 上并报 “Drawing is only allowed inside _draw()”。
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay.bind(_overlay))
	add_child(_overlay)


func _ready() -> void:
	custom_minimum_size = custom_minimum_size.max(Vector2(240, 180))
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_relayout)
	mouse_exited.connect(_on_mouse_exited)
	# 注意别写成 set_process(false)：数据可能是入树前就填好的（先 setup/set_column 再 add_child），
	# 那样会把待上传的帧一起关掉，画面永远是空的。
	set_process(_dirty)
	_relayout()


func _process(_delta: float) -> void:
	if not _dirty or _texture == null:
		set_process(false)
		return
	_texture.update(_image)   # 每帧最多上传一次，行数据再密也不会打爆显存带宽
	_dirty = false
	set_process(false)


# ---------- 数据 ----------

## 分配画布：cols = z 方向列数，rows = y 方向行数。重复调用同尺寸则只清空数据。
func setup(cols: int, rows: int) -> void:
	cols = maxi(cols, 1)
	rows = maxi(rows, 1)
	if _image != null and _cols == cols and _rows == rows:
		clear()
		return
	_cols = cols
	_rows = rows
	# FORMAT_RF：单通道 32 位浮点，原样存光强（不量化），着色器负责上色
	_image = Image.create_empty(cols, rows, false, Image.FORMAT_RF)
	_image.fill(Color(0, 0, 0, 1))
	_texture = ImageTexture.create_from_image(_image)
	_view.texture = _texture
	_view.visible = true
	_reset_range()
	_dirty = true
	set_process(true)
	_relayout()
	queue_redraw()


## 追加一列（第 index 个 z 的整条 y 剖面，原始强度值）。
func set_column(index: int, values: PackedFloat32Array) -> void:
	if _image == null or index < 0 or index >= _cols:
		return
	var row := PackedFloat32Array()
	row.resize(_rows)
	var n := mini(values.size(), _rows)
	var peak := 0.0
	for i in n:
		var v := values[i]
		if not is_finite(v):
			v = 0.0
		row[i] = v
		peak = maxf(peak, v)
	_image.blit_rect(
			Image.create_from_data(1, _rows, false, Image.FORMAT_RF, row.to_byte_array()),
			Rect2i(0, 0, 1, _rows), Vector2i(index, 0))

	if auto_range and peak > display_range.y:
		display_range.y = peak
		_apply_range()
	_dirty = true
	set_process(true)


## 追加一列（base64 编码的 float32 小端字节，后端逐 z 推送用的就是这种格式：
## 比 JSON 数字数组小一半、解析也快）。
func set_column_b64(index: int, b64: String) -> void:
	if b64.is_empty():
		return
	var bytes := Marshalls.base64_to_raw(b64)
	if bytes.is_empty():
		return
	set_column(index, bytes.to_float32_array())


## 清空数据（保留画布尺寸）。显示范围一并回到「自动」—— 空画布配一个冻结的旧量程
## 只会让接下来画出来的东西颜色全错（这也是为什么必须顺手复位 `auto_range`）。
func clear() -> void:
	if _image == null:
		return
	_image.fill(Color(0, 0, 0, 1))
	_reset_range()
	_dirty = true
	set_process(true)
	queue_redraw()


## 复位显示范围并回到自动量程。**必须同时复位 `auto_range`**：
## 只把 display_range 清零而留着 auto_range=false 的话，vmax 会落到 1e-30，
## 所有像素都落到色标最底部 —— 表现就是「整幅图全黑」。界面上有「自动量程」开关之后，
## 这条路径是用户能主动走到的，所以这里把两件事绑在一起做。
func _reset_range() -> void:
	display_range = Vector2(0.0, 0.0)
	auto_range = true
	_apply_range()
	range_reset.emit()


func has_data() -> bool:
	return _image != null and display_range.y > 0.0


func set_z_range(from: float, to: float) -> void:
	z_range = Vector2(from, to)
	queue_redraw()


func set_y_range(from: float, to: float) -> void:
	y_range = Vector2(from, to)
	_relayout()
	queue_redraw()


## 手动指定显示范围（关掉自动量程，用作「增益/曝光」调节）。
func set_display_range(lo: float, hi: float) -> void:
	auto_range = false
	display_range = Vector2(lo, maxf(hi, lo + 1e-12))
	_apply_range()


func get_display_range() -> Vector2:
	return display_range


## 把显示上限抬到 value（只在自动量程打开、且 value 确实更大时生效）。
##
## 后端每条 `rs_col` 都带着 `vmax`（该 z 处**整行**的峰值，不只是显示窗口内的），
## 用它比前端自己按列再累积一份峰值更可信 —— 两套实现一旦漂移（例如中止后重新开始），
## 画面颜色就会和数据对不上。
func set_peak(value: float) -> void:
	if not auto_range or not is_finite(value) or value <= display_range.y:
		return
	display_range.y = value
	_apply_range()


## 当前显示范围的峰值（原始强度单位）。
func get_peak() -> float:
	return display_range.y


func _apply_range() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("vmin", display_range.x)
	# 空数据时给一个极小的非零量程，避免除零；此时所有像素都会落到色标底部
	_material.set_shader_parameter("vmax", maxf(display_range.y, 1e-30))
	queue_redraw()


# ---------- 布局 ----------

func _relayout() -> void:
	if _view == null or _overlay == null:
		return
	var plot := _plot_rect()
	_view.position = plot.position
	_view.size = plot.size
	_overlay.position = plot.position
	_overlay.size = plot.size
	queue_redraw()


## 绘图区（扣掉四周刻度/标题/色标；equal_aspect 时按物理尺度等比居中）。
func _plot_rect() -> Rect2:
	var right := ThemePalette.IMAP_MARGIN_RIGHT
	if show_colorbar:
		# 色标条本身 + 右侧刻度数字 / 竖排标题的宽度（否则标签会贴到窗口外被裁掉）
		var tail := ThemePalette.IMAP_COLORBAR_TICK_W
		if not colorbar_label.is_empty():
			tail = maxf(tail, ThemePalette.IMAP_COLORBAR_LABEL_OFFSET + ThemePalette.FONT_SM * 1.4)
		right += ThemePalette.IMAP_COLORBAR_GAP + ThemePalette.IMAP_COLORBAR_W + tail
	var avail := Rect2(
			ThemePalette.IMAP_MARGIN_LEFT,
			ThemePalette.IMAP_MARGIN_TOP,
			maxf(size.x - ThemePalette.IMAP_MARGIN_LEFT - right, 1.0),
			maxf(size.y - ThemePalette.IMAP_MARGIN_TOP - ThemePalette.IMAP_MARGIN_BOTTOM, 1.0))
	if not equal_aspect:
		return avail
	var zs := absf(z_range.y - z_range.x)
	var ys := absf(y_range.y - y_range.x)
	if zs <= 0.0 or ys <= 0.0:
		return avail
	var want := zs / ys
	var have := avail.size.x / avail.size.y
	if have > want:
		var w := avail.size.y * want
		return Rect2(avail.position + Vector2((avail.size.x - w) * 0.5, 0.0), Vector2(w, avail.size.y))
	var h := avail.size.x / want
	return Rect2(avail.position + Vector2(0.0, (avail.size.y - h) * 0.5), Vector2(avail.size.x, h))


func _colorbar_rect(plot: Rect2) -> Rect2:
	return Rect2(plot.end.x + ThemePalette.IMAP_COLORBAR_GAP, plot.position.y,
			ThemePalette.IMAP_COLORBAR_W, plot.size.y)


# ---------- 交互 ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_update_hover(event.position)


func _on_mouse_exited() -> void:
	if _hover_valid:
		_hover_valid = false
		_hover_cell = Vector2i(-1, -1)
		_overlay.queue_redraw()


func _update_hover(pos: Vector2) -> void:
	if _image == null or _cols <= 0 or _rows <= 0:
		return
	var plot := _plot_rect()
	if not plot.has_point(pos):
		_on_mouse_exited()
		return
	var u := clampf((pos.x - plot.position.x) / maxf(plot.size.x, 1.0), 0.0, 0.999999)
	var v := clampf((pos.y - plot.position.y) / maxf(plot.size.y, 1.0), 0.0, 0.999999)
	var cell := Vector2i(int(u * _cols), int(v * _rows))
	if _hover_valid and cell == _hover_cell:
		return
	_hover_cell = cell
	_hover_valid = true
	_overlay.queue_redraw()
	cell_hovered.emit(_cell_z(cell.x), _cell_y(cell.y), get_value(cell.x, cell.y))


## 取某个格子的原始强度值。
func get_value(col: int, row: int) -> float:
	if _image == null or col < 0 or col >= _cols or row < 0 or row >= _rows:
		return 0.0
	return _image.get_pixel(col, row).r


## 第 i 列对应的 z（米）。
func _cell_z(i: int) -> float:
	if _cols <= 1:
		return z_range.x
	return lerpf(z_range.x, z_range.y, float(i) / float(_cols - 1))


## 第 i 行对应的 y（米）。
func _cell_y(i: int) -> float:
	if _rows <= 1:
		return y_range.x
	return lerpf(y_range.x, y_range.y, float(i) / float(_rows - 1))


# ---------- 绘制 ----------

func _theme_color(name: StringName, fallback: Color) -> Color:
	return get_theme_color(name, &"IntensityMap") if has_theme_color(name, &"IntensityMap") else fallback


func _theme_font_size(name: StringName, fallback: int) -> int:
	return get_theme_font_size(name, &"IntensityMap") if has_theme_font_size(name, &"IntensityMap") else fallback


func _draw() -> void:
	var font := get_theme_default_font()
	var plot := _plot_rect()
	var bg := _theme_color(&"background_color", ThemePalette.CHART_BG)
	var axis := _theme_color(&"axis_color", ThemePalette.CHART_AXIS)
	var tick := _theme_color(&"tick_text_color", ThemePalette.CHART_TEXT)
	var title_col := _theme_color(&"title_color", ThemePalette.TEXT)
	var fs_tick := _theme_font_size(&"tick_font_size", ThemePalette.FONT_XS)
	var fs_label := _theme_font_size(&"label_font_size", ThemePalette.FONT_SM)
	var fs_title := _theme_font_size(&"title_font_size", ThemePalette.FONT_MD)

	draw_rect(Rect2(Vector2.ZERO, size), bg, true)

	# Y 轴刻度（左侧）+ 水平短刻度线
	for t in _nice_ticks(y_range.x, y_range.y, ThemePalette.IMAP_AXIS_TICKS):
		var py := _value_to_py(t, plot)
		draw_line(Vector2(plot.position.x - 4.0, py), Vector2(plot.position.x, py), axis, 1.0)
		draw_string(font, Vector2(0.0, py + fs_tick * 0.35), _fmt(t * unit_scale),
				HORIZONTAL_ALIGNMENT_RIGHT, ThemePalette.IMAP_MARGIN_LEFT - 8.0, fs_tick, tick)

	# X 轴刻度（底部）
	for t in _nice_ticks(z_range.x, z_range.y, ThemePalette.IMAP_AXIS_TICKS):
		var px := _value_to_px(t, plot)
		draw_line(Vector2(px, plot.end.y), Vector2(px, plot.end.y + 4.0), axis, 1.0)
		draw_string(font, Vector2(px - 28.0, plot.end.y + 5.0 + fs_tick),
				_fmt(t * unit_scale), HORIZONTAL_ALIGNMENT_CENTER, 56.0, fs_tick, tick)

	# 坐标轴标签（没有单位后缀时就只显示名字，不留空括号）
	var x_axis := x_label if unit_suffix.is_empty() else "%s (%s)" % [x_label, unit_suffix]
	var y_axis := y_label if unit_suffix.is_empty() else "%s (%s)" % [y_label, unit_suffix]
	draw_string(font, Vector2(plot.position.x, plot.end.y + 5.0 + fs_tick * 2.0 + 8.0),
			x_axis, HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, fs_label, tick)
	draw_set_transform(Vector2(2.0, plot.position.y + plot.size.y * 0.5), -PI * 0.5, Vector2.ONE)
	draw_string(font, Vector2(-plot.size.y * 0.5, 0.0), y_axis,
			HORIZONTAL_ALIGNMENT_CENTER, plot.size.y, fs_label, tick)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 绘图区外框
	draw_rect(plot, axis, false, 1.0)

	if not title.is_empty():
		draw_string(font, Vector2(plot.position.x, plot.position.y - 8.0), title,
				HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, fs_title, title_col)

	if show_colorbar:
		_draw_colorbar(_colorbar_rect(plot), font, fs_tick, fs_label, tick, axis)


## 色标条：横向铺开色标、纵向自上而下由大到小。
## 刻度固定标 0..1（= 归一化强度），和原 matplotlib 出图的 colorbar 语义一致；
## 原始量程（display_range）另行显示在界面上，不混进色标里。
func _draw_colorbar(bar: Rect2, font: Font, fs_tick: int, fs_label: int,
		tick: Color, axis: Color) -> void:
	var bands := maxi(ThemePalette.IMAP_COLORBAR_BANDS, 2)
	for i in bands:
		var t := 1.0 - float(i) / float(bands - 1)
		var y := bar.position.y + bar.size.y * float(i) / float(bands)
		var h := bar.size.y / float(bands) + 1.0
		draw_rect(Rect2(bar.position.x, y, bar.size.x, h), Colormaps.sample(colormap, t), true)
	draw_rect(bar, axis, false, 1.0)

	for i in 5:
		var t := float(i) / 4.0
		var py := bar.position.y + bar.size.y * (1.0 - t)
		draw_line(Vector2(bar.end.x, py), Vector2(bar.end.x + 4.0, py), axis, 1.0)
		draw_string(font, Vector2(bar.end.x + 6.0, py + fs_tick * 0.35),
				"%.2f" % t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_tick, tick)

	draw_set_transform(Vector2(bar.end.x + ThemePalette.IMAP_COLORBAR_LABEL_OFFSET,
			bar.position.y + bar.size.y * 0.5), -PI * 0.5, Vector2.ONE)
	draw_string(font, Vector2(-bar.size.y * 0.5, 0.0), colorbar_label,
			HORIZONTAL_ALIGNMENT_CENTER, bar.size.y, fs_label, tick)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 悬停十字线 + 读数（画在叠加层 target 上：图像是子节点，只有再叠一层才盖得住）。
func _draw_overlay(target: CanvasItem) -> void:
	if not _hover_valid or target == null:
		return
	var rect := Rect2(Vector2.ZERO, target.size)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var font := get_theme_default_font()
	var fs := _theme_font_size(&"tick_font_size", ThemePalette.FONT_XS)
	var col := _theme_color(&"hover_color", ThemePalette.ACCENT)
	var text_col := _theme_color(&"hover_text_color", ThemePalette.TEXT_ON_ACCENT)

	var cx := rect.size.x * (float(_hover_cell.x) + 0.5) / float(maxi(_cols, 1))
	var cy := rect.size.y * (float(_hover_cell.y) + 0.5) / float(maxi(_rows, 1))
	target.draw_line(Vector2(cx, 0.0), Vector2(cx, rect.size.y), Color(col, 0.7), 1.0)
	target.draw_line(Vector2(0.0, cy), Vector2(rect.size.x, cy), Color(col, 0.7), 1.0)

	var txt := "Z %s | Y %s | I %s" % [
		_fmt(_cell_z(_hover_cell.x) * unit_scale),
		_fmt(_cell_y(_hover_cell.y) * unit_scale),
		Fmt.num(get_value(_hover_cell.x, _hover_cell.y), 4),
	]
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var box := Rect2(ThemePalette.IMAP_READOUT_PAD, ThemePalette.IMAP_READOUT_PAD,
			w + fs * 1.2, fs * 1.9)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	sb.set_corner_radius_all(ThemePalette.RADIUS_SM)
	target.draw_style_box(sb, box)
	target.draw_string(font, Vector2(box.position.x + fs * 0.6, box.position.y + box.size.y * 0.72),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, text_col)


func _value_to_px(v: float, plot: Rect2) -> float:
	var span := z_range.y - z_range.x
	if absf(span) < 1e-15:
		return plot.position.x
	return plot.position.x + (v - z_range.x) / span * plot.size.x


func _value_to_py(v: float, plot: Rect2) -> float:
	var span := y_range.y - y_range.x
	if absf(span) < 1e-15:
		return plot.position.y
	# y 向上为正，和原图一致
	return plot.end.y - (v - y_range.x) / span * plot.size.y


## 刻度值格式化（GDScript 没有 %g/%e，统一走 Fmt）。
static func _fmt(v: float) -> String:
	return Fmt.num(v, 3)


## 取「好看」的刻度值（1/2/5×10ⁿ 步长），避免出现 0.3333 这种刻度。
static func _nice_ticks(lo: float, hi: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not is_finite(lo) or not is_finite(hi) or hi <= lo:
		out.append(lo)
		return out
	var raw := (hi - lo) / float(maxi(count, 1))
	var mag := pow(10.0, floor(log(raw) / log(10.0)))
	var norm := raw / mag
	var step := mag
	if norm > 1.5 and norm <= 3.5:
		step = mag * 2.0
	elif norm > 3.5 and norm <= 7.5:
		step = mag * 5.0
	elif norm > 7.5:
		step = mag * 10.0
	var v: float = ceilf(lo / step) * step
	var guard := 0
	while v <= hi + step * 1.0e-6 and guard < 64:
		out.append(v)
		v += step
		guard += 1
	return out
