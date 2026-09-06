class_name ExpandWidget
extends VBoxContainer
## 折叠展开控件（对应 PyQt-SiliconUI 的 SiHExpandWidget / SiVExpandWidget）。
## 顶部是可点击标题栏（带展开/收起箭头），下方是内容容器 content，
## 点击标题栏即时切换展开/收起（无动画，避免逐帧布局带来的卡顿）。
##
## 用法：
##   var ex := ExpandWidget.new()
##   ex.title = "参数设置"
##   ex.content.add_child(your_control)
##   ex.set_expanded(false)

signal toggled(expanded: bool)

@export var title := "分组":
	set(v):
		title = v
		if _header:
			_header.text = v

@export var expanded := true   # 初始展开状态（在 _ready 中应用）

var _header: Button
var _content: VBoxContainer
var _arrow_down: Texture2D
var _arrow_right: Texture2D

var content: Control:
	get:
		return _content


func _init() -> void:
	# 子节点在 _init 里构建，保证 new() 之后即可访问 content（无需等进入场景树）。
	_arrow_down = load("res://themes/icons/arrow_down.svg")
	_arrow_right = load("res://themes/icons/arrow_right.svg")

	_header = Button.new()
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.text = title
	_header.icon = _arrow_down
	_header.pressed.connect(_on_header_pressed)
	add_child(_header)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)


func _ready() -> void:
	_apply(expanded)


## 程序化切换展开状态（即时生效）。
func set_expanded(v: bool) -> void:
	if v == expanded:
		return
	expanded = v
	_apply(v)
	toggled.emit(v)


func _on_header_pressed() -> void:
	set_expanded(not expanded)


## 即时展开/收起：只切换可见性与箭头（visible=false 的控件不参与容器布局）。
func _apply(v: bool) -> void:
	if _content == null:
		return
	_header.icon = _arrow_down if v else _arrow_right
	_content.visible = v
