class_name Switch
extends Control
## 简单开关控件（对应 PyQt-SiliconUI 的 SiSwitch）。
## Godot 没有原生 Switch，这里用 _draw 画胶囊 + 圆钮，点击切换。
## 状态存 button_pressed，切换时发 toggled(on) 信号。
## 颜色从主题类型 "Switch" 读取（回退到 ThemePalette 令牌），随全局主题统一调整。

signal toggled(on: bool)

var button_pressed := false

## 禁用：置灰 + 不吃点击。
## `Control` 没有 `disabled`（那是 `BaseButton` 的），而本控件是自绘的，
## 所以这里自己补一个 —— 否则任何「条件不满足时置灰」的场景都只能在业务层自己挡点击。
var disabled := false:
	set(v):
		disabled = v
		mouse_default_cursor_shape = Control.CURSOR_ARROW if v else Control.CURSOR_POINTING_HAND
		# 用 modulate.a 做置灰（**不是** 用 modulate 改颜色 —— 那会把颜色乘暗、越乘越糊）。
		# 与 FlashLabel 的做法一致：透明度闪烁/变暗是 modulate.a 的正当用法。
		modulate.a = 0.45 if v else 1.0
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(48, 26)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_pressed(v: bool) -> void:
	button_pressed = v
	toggled.emit(v)
	queue_redraw()


## 只改状态、不发 `toggled`。名字与 `BaseButton.set_pressed_no_signal()` 对齐 ——
## 业务代码要在「状态被外部改了、但不想触发自己的回调」时用它（否则会打环）。
func set_pressed_no_signal(v: bool) -> void:
	if button_pressed == v:
		return
	button_pressed = v
	queue_redraw()


func is_pressed() -> bool:
	return button_pressed


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return          # 禁用时不吃点击（置灰只是外观，行为也要挡住）
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		set_pressed(not button_pressed)
		accept_event()


func _draw() -> void:
	var on := _theme_color("on_color", ThemePalette.SUCCESS)
	var off := _theme_color("off_color", ThemePalette.BORDER_STRONG)
	var knob := _theme_color("knob_color", ThemePalette.SURFACE)

	# 胶囊轨道
	var sb := StyleBoxFlat.new()
	sb.bg_color = on if button_pressed else off
	sb.set_corner_radius_all(size.y / 2.0)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))

	# 圆钮
	var h := size.y
	var knob_r := h / 2.0 - 3.0
	var cx := size.x - h / 2.0 if button_pressed else h / 2.0
	draw_circle(Vector2(cx, h / 2.0), knob_r, knob)


## 从主题类型 "Switch" 取颜色，未定义时回退到令牌默认值。
func _theme_color(name: String, fallback: Color) -> Color:
	return get_theme_color(name, &"Switch") if has_theme_color(name, &"Switch") else fallback
