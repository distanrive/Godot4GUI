class_name CircularProgressBar
extends Control
## 环形进度条（对应 PyQt-SiliconUI 的 SiCircularProgressBar）。
## Godot 无原生环形进度，这里用 _draw 画底环 + 进度圆弧，中心显示百分比。
## 颜色从主题类型 "CircularProgressBar" 读取（回退到 ThemePalette 令牌），随全局主题统一调整。
##
## 用法：
##   var c := CircularProgressBar.new()
##   c.value = 0.65            # 0..1
##   c.show_text = true        # 中心显示百分比

@export_range(0.0, 1.0, 0.01) var value := 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

@export var show_text := true
@export var ring_width := 6.0
@export var start_angle_deg := -90.0   # 起始角度（度，0=右侧，顺时针为正）；-90 从顶部开始


func _ready() -> void:
	custom_minimum_size = Vector2(80, 80)
	resized.connect(queue_redraw)


func _draw() -> void:
	var track := _theme_color("track_color", ThemePalette.SURFACE_ALT)
	var progress := _theme_color("progress_color", ThemePalette.ACCENT)
	var text_col := _theme_color("text_color", ThemePalette.TEXT)

	var center := size / 2.0
	var radius := maxf(minf(size.x, size.y) / 2.0 - ring_width / 2.0 - 1.0, 1.0)
	var start := deg_to_rad(start_angle_deg)

	# 底环
	draw_arc(center, radius, 0.0, TAU, 64, track, ring_width, true)
	# 进度圆弧
	if value > 0.0:
		draw_arc(center, radius, start, start + TAU * value, 64, progress, ring_width, true)

	# 中心百分比文字
	if show_text:
		var font := get_theme_default_font()
		var fs := get_theme_default_font_size() + 4
		var txt := "%d%%" % int(round(value * 100.0))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		draw_string(font, Vector2(center.x - w / 2.0, center.y + fs * 0.35),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, text_col)


## 从主题类型 "CircularProgressBar" 取颜色，未定义时回退到令牌默认值。
func _theme_color(name: String, fallback: Color) -> Color:
	return get_theme_color(name, &"CircularProgressBar") if has_theme_color(name, &"CircularProgressBar") else fallback
