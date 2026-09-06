extends Node
## 全局主题单例（Autoload）。
##
## 启动时由 ThemePalette + ThemeFactory 构建完整主题，应用到根窗口，
## 使整棵树（含弹窗、PopupMenu、Tooltip）都使用统一样式。
## 样式调整请改 scripts/theme/theme_palette.gd，不要在本文件里改值。


func _ready() -> void:
	_apply()


## 构建并应用主题（也可在运行时切换/刷新时再次调用）。
func _apply() -> void:
	var t := ThemeFactory.build()
	get_tree().root.theme = t
