class_name LongPressButton
extends Button
## 长按按钮（对应 PyQt-SiliconUI 的 SiLongPressButton）。
## 需持续按住 hold_duration 秒才触发，用于防误触（启动、急停等安全操作）。
## 用 is_pressed() 轮询计时，不依赖信号时序，更可靠。

signal long_pressed                    # 长按达标后触发
signal progress_changed(ratio: float)  # 按住进度 0..1，供外部显示

@export var hold_duration := 1.0     # 需按住时长（秒）
@export var show_progress := true    # 底部绘制按压进度条

var _accum := 0.0
var _triggered := false              # 本次按住是否已触发过（防止重复触发）
var _was_pressed := false


func _process(delta: float) -> void:
	var pressed := is_pressed()

	if pressed != _was_pressed:
		_was_pressed = pressed
		queue_redraw()

	if pressed:
		if not _triggered:
			_accum += delta
			progress_changed.emit(clampf(_accum / hold_duration, 0.0, 1.0))
			if show_progress:
				queue_redraw()
			if _accum >= hold_duration:
				_triggered = true
				_accum = 0.0
				long_pressed.emit()
				queue_redraw()
	else:
		_accum = 0.0
		_triggered = false


func _draw() -> void:
	if show_progress and _was_pressed and not _triggered and hold_duration > 0.0:
		var ratio := clampf(_accum / hold_duration, 0.0, 1.0)
		var bar := Rect2(Vector2(0, size.y - 3.0), Vector2(size.x * ratio, 3.0))
		draw_rect(bar, _progress_color(), true)


## 进度条颜色：**先看当前 `theme_type_variation`，再回落 `LongPressButton`，最后才是令牌默认**。
##
## 这里必须按变体查：套了 `DangerButton` 之类的语义变体时，按钮底色是红的，
## 而进度条原来是写死按 `&"LongPressButton"` 取的（蓝色）—— 红底上的蓝条几乎看不见。
## `theme_factory.gd` 里给那几个实底变体都定义了 `progress_color`（半透明白），
## 所以红底/绿底/主色底上都能看清。
func _progress_color() -> Color:
	var variation := theme_type_variation
	if not variation.is_empty() and has_theme_color("progress_color", variation):
		return get_theme_color("progress_color", variation)
	if has_theme_color("progress_color", &"LongPressButton"):
		return get_theme_color("progress_color", &"LongPressButton")
	return Color(ThemePalette.ACCENT, 0.85)
