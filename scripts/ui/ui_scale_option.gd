class_name UiScaleOption
extends OptionButton
## 界面缩放选择器：跟随系统 / 100% / 125% / 150% / 175% / 200%。
## 选中即调用 `AppShell.set_ui_scale()` —— 立即生效，并记到 `user://config.cfg`，重启不丢。
##
## 用法（放进任意工具栏/侧栏即可）：
##   var scale := UiScaleOption.new()
##   header.add_child(scale)
##
## 为什么需要手动档位：Windows 上 `DisplayServer.screen_get_scale()` 恒返回 1.0，
## 自动缩放只能靠 `screen_get_dpi() / 96` 猜（见 `AppShell.detect_system_scale()`），
## 猜到的值在个别显示器/远程桌面上未必合意，得让用户能改。

const _CUSTOM_TEXT := "自定义"


func _init() -> void:
	# 选项在 _init 里就建好：业务代码 new() 之后可能马上设置 selected / 读 item_count
	add_item("跟随系统")
	for s in ThemePalette.UI_SCALE_STEPS:
		add_item("%d%%" % int(round(s * 100.0)))
	add_item(_CUSTOM_TEXT)
	set_item_disabled(item_count - 1, true)      # 没有自定义值时这一项是灰的
	tooltip_text = "界面缩放：跟随系统按屏幕 DPI 自动定；选具体档位会记到 user://config.cfg。"


func _ready() -> void:
	_sync()
	item_selected.connect(_on_item_selected)
	AppShell.ui_scale_changed.connect(_on_scale_changed)


## 把当前档位同步到控件上（`select()` 不会反过来触发 item_selected，所以不会打环）。
func _sync() -> void:
	var setting := AppShell.get_ui_scale_setting()
	set_item_text(0, "跟随系统（%.2f×）" % AppShell.detect_system_scale())

	var custom := item_count - 1
	var index := 0
	var matched := AppShell.is_following_system()
	for i in ThemePalette.UI_SCALE_STEPS.size():
		if is_equal_approx(float(ThemePalette.UI_SCALE_STEPS[i]), setting):
			index = i + 1
			matched = true
			break
	if not matched and setting > 0.0:
		set_item_text(custom, "自定义（%.2f×）" % setting)
		set_item_disabled(custom, false)
		index = custom
	select(index)


func _on_item_selected(index: int) -> void:
	var custom := item_count - 1
	if index == 0:
		AppShell.set_ui_scale(ThemePalette.UI_SCALE_FOLLOW_SYSTEM)
	elif index == custom:
		return          # 「自定义」是显示用的，不可选（已是 disabled，这里兜底）
	else:
		AppShell.set_ui_scale(float(ThemePalette.UI_SCALE_STEPS[index - 1]))


func _on_scale_changed(_factor: float) -> void:
	_sync()
