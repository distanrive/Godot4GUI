class_name TitledGroup
extends PanelContainer
## 带标题控件组（对应 PyQt-SiliconUI 的 SiTitledWidgetGroup / SiPanelCard）。
## 顶部标题（CardTitle 语义样式）+ 下方内容容器 content，卡片外观由主题 PanelContainer 面板提供。
##
## 用法：
##   var g := TitledGroup.new()
##   g.title = "通信参数"
##   g.content.add_child(your_control)

@export var title := "标题":
	set(v):
		title = v
		if _title_label:
			_title_label.text = v

var _title_label: Label
var _content: VBoxContainer

var content: Control:
	get:
		return _content


func _init() -> void:
	# 子节点在 _init 里构建，保证 new() 之后即可访问 content（无需等进入场景树）。
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(ThemePalette.PAD_CARD_V))
	add_child(vb)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.theme_type_variation = "CardTitle"
	vb.add_child(_title_label)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	vb.add_child(_content)
