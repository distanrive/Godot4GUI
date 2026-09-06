class_name LabeledLineEdit
extends HBoxContainer
## 带标签输入框（对应 PyQt-SiliconUI 的 SiLabeledLineEdit）。
## 左侧固定宽度标签 + 右侧可伸缩 LineEdit，组合复用而非 per-control 样式。
##
## 用法：
##   var e := LabeledLineEdit.new()
##   e.label_text = "名称"
##   e.line_edit.text = "默认值"
##   e.text                  # 快捷读写右侧输入框文本

@export var label_text := "标签":
	set(v):
		label_text = v
		if _label:
			_label.text = v

@export var label_width := 64.0:
	set(v):
		label_width = v
		if _label:
			_label.custom_minimum_size.x = v

var _label: Label
var line_edit: LineEdit

## 快捷读写右侧输入框文本（line_edit 尚未构建时读返回空串、写被忽略）。
var text: String:
	get:
		return line_edit.text if line_edit else ""
	set(v):
		if line_edit:
			line_edit.text = v


func _init() -> void:
	# 子节点在 _init 里构建，保证 new() 之后即可访问 line_edit（无需等进入场景树）。
	_label = Label.new()
	_label.text = label_text
	_label.custom_minimum_size = Vector2(label_width, 0)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	line_edit = LineEdit.new()
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(line_edit)
