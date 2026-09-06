class_name PartitionIndicator
extends Control
## 分段指示灯（对应 PyQt-SiliconUI 的 SiLinearPartitionIndicator）。
## 横向一排等宽的圆角分段，前 active_count 段点亮、其余熄灭，
## 用于把连续量（压力/液位/进度）离散成多段显示。
## 颜色从主题类型 "PartitionIndicator" 读取（回退到 ThemePalette 令牌），随全局主题统一调整。
##
## 用法：
##   var p := PartitionIndicator.new()
##   p.segment_count = 10
##   p.set_active(5)             # 点亮前 5 段

@export var segment_count := 10:
	set(v):
		segment_count = maxi(1, v)
		queue_redraw()

@export var active_count := 0:
	set(v):
		active_count = v
		queue_redraw()

@export var gap := 3.0          # 段间距
@export var corner := 3         # 段圆角
@export var show_border := true


func _ready() -> void:
	custom_minimum_size = Vector2(120, 18)
	resized.connect(queue_redraw)


func set_active(n: int) -> void:
	active_count = n


func _draw() -> void:
	if segment_count <= 0:
		return
	var on := _theme_color("on_color", ThemePalette.ACCENT)
	var off := _theme_color("off_color", ThemePalette.SURFACE_ALT)
	var border := _theme_color("border_color", ThemePalette.BORDER)

	var n := clampi(active_count, 0, segment_count)
	var total_gap := gap * (segment_count - 1)
	var seg_w := (size.x - total_gap) / segment_count
	for i in range(segment_count):
		var x := i * (seg_w + gap)
		var sb := StyleBoxFlat.new()
		sb.bg_color = on if i < n else off
		sb.set_corner_radius_all(corner)
		if show_border:
			sb.border_color = border
			sb.set_border_width_all(1)
		draw_style_box(sb, Rect2(x, 0.0, seg_w, size.y))


## 从主题类型 "PartitionIndicator" 取颜色，未定义时回退到令牌默认值。
func _theme_color(name: String, fallback: Color) -> Color:
	return get_theme_color(name, &"PartitionIndicator") if has_theme_color(name, &"PartitionIndicator") else fallback
