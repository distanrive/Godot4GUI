class_name FlashLabel
extends Label
## 闪烁标签（对应 PyQt-SiliconUI 的 SiFlashLabel）。
## start() 后把文字设为 flash_color，并按 interval 在「亮/暗」之间切换透明度实现闪烁。
## 只改 modulate.a 的透明度，不改颜色本身，因此报警色保持纯正、不会被乘暗。
##
## 用法：
##   var f := FlashLabel.new()
##   f.text = "报警"
##   f.flash_color = ThemePalette.DANGER
##   f.start()      # 开始闪烁
##   f.stop()       # 停止并恢复普通文字色

@export var interval := 0.5
@export var flash_color := ThemePalette.DANGER
@export var min_alpha := 0.0        # 闪烁时的最低透明度（0 = 完全熄灭；>0 为柔和脉冲）

@export var flashing := false:
	set(v):
		flashing = v
		if not v:
			_acc = 0.0
			_on = true
			modulate.a = 1.0

var _acc := 0.0
var _on := true          # 当前处于「亮」相


func _process(delta: float) -> void:
	if not flashing:
		return
	_acc += delta
	if _acc >= interval:
		_acc = 0.0
		_on = not _on
		modulate.a = 1.0 if _on else min_alpha


func start() -> void:
	add_theme_color_override("font_color", flash_color)
	flashing = true


func stop() -> void:
	flashing = false
	remove_theme_color_override("font_color")
