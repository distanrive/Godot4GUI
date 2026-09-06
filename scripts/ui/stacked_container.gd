class_name StackedContainer
extends Control
## 堆叠/分页容器（对应 PyQt-SiliconUI 的 SiStackedContainer）。
## 多个子页面叠加，同一时刻只显示其一，用于「上一步/下一步」或多视图切换。
## Godot 无原生堆叠容器，这里手动切换各页 visible。
##
## 用法：
##   var s := StackedContainer.new()
##   s.add_page(page_a)          # 依次加入页面（第一页默认可见）
##   s.add_page(page_b)
##   s.set_page_index(1)         # 显示第 2 页

signal page_changed(index: int)

var _pages: Array[Control] = []
var current_index := 0


func add_page(page: Control) -> void:
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = _pages.is_empty()   # 第一页默认可见
	add_child(page)
	_pages.append(page)
	_refit()


func set_page_index(i: int) -> void:
	if _pages.is_empty():
		return
	current_index = clampi(i, 0, _pages.size() - 1)
	for k in range(_pages.size()):
		_pages[k].visible = k == current_index
	page_changed.emit(current_index)


func next_page() -> void:
	set_page_index(current_index + 1)


func prev_page() -> void:
	set_page_index(current_index - 1)


## 最小尺寸取各页最大者，保证切页时容器尺寸稳定。
func _refit() -> void:
	var m := Vector2.ZERO
	for p in _pages:
		m = m.max(p.get_combined_minimum_size())
	custom_minimum_size = m
