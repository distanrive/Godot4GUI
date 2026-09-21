class_name TreeTableItem
extends Object
## `TreeTable` 的一行（可带子行）。用法与 Godot 原生 `TreeItem` 类似：
##
##   var dev := table.create_item()                  # 顶层行
##   var ch := table.create_item(dev)                # 子行
##   ch.set_cells(["通道 1", "正常", "10.0"])        # 链式调用
##   dev.set_expanded(true)
##
## **生命周期**（与原生 `TreeItem` 同一套约定，务必记住）：
##   * 行由 `TreeTable` 拥有，调用方**不要**自己 `free()`；
##   * 要删一行用 `remove()`，它会把自己和整棵子树从表里摘掉并释放 —— 之后这个引用就失效了，
##     不要再访问（与 `TreeItem.free()` 的注意事项完全一致）；
##   * 整张表被释放时，所有行会跟着释放。
##
## 为什么不继承 `RefCounted`：父子互相持有引用会形成**引用环**，而 GDScript 用的是引用计数
## （非追踪 GC），环上的对象永远不会被回收。表格反复重建（例如每秒刷新一次设备列表）
## 就会稳定泄漏。改成显式所有权后，生命周期与原生 `TreeItem` 一致，也没有环。
##
## 单元格文本一律是 `String`：本项目表格不做内嵌控件，保持自绘的简单与一致。

var _table: Node = null                  # 所属 TreeTable（用 Node 类型：避免与 TreeTable 循环引用）
var _parent: TreeTableItem = null
var _children: Array[TreeTableItem] = []
var _cells: PackedStringArray = []
var _expanded := false
var _selectable := true
var _metadata: Variant = null
var _depth := 0


func _init(table: Node = null, parent: TreeTableItem = null) -> void:
	_table = table
	_parent = parent


# ---------- 文本 ----------

## 设置第 col 列的文本（列数不足时自动补空）。
func set_text(col: int, text: String) -> TreeTableItem:
	if col < 0:
		return self
	if col >= _cells.size():
		_cells.resize(col + 1)
	_cells[col] = text
	_invalidate()
	return self


func get_text(col: int) -> String:
	return _cells[col] if col >= 0 and col < _cells.size() else ""


## 一次性设置整行文本（比逐列 set_text 少几次重绘）。
func set_cells(values: PackedStringArray) -> TreeTableItem:
	_cells = values
	_invalidate()
	return self


func get_cells() -> PackedStringArray:
	return _cells


# ---------- 挂载的业务数据 ----------

## 挂任意业务对象（设备句柄/配置字典…）。表格只负责显示，不解释它。
func set_metadata(value: Variant) -> TreeTableItem:
	_metadata = value
	return self


func get_metadata() -> Variant:
	return _metadata


# ---------- 结构 ----------

## 追加一个子行（一般直接用 `table.create_item(parent)`，很少需要手调它）。
func add_child_item(item: TreeTableItem) -> TreeTableItem:
	if item == null:
		return null
	item._parent = self
	item._rebind(_table, _depth + 1)
	_children.append(item)
	_invalidate()
	return item


func get_parent() -> TreeTableItem:
	return _parent


## 子行列表（副本；要改结构请用 `add_child_item()` / `remove()`）。
func get_children() -> Array[TreeTableItem]:
	return _children.duplicate()


func get_child_count() -> int:
	return _children.size()


func get_child(index: int) -> TreeTableItem:
	return _children[index] if index >= 0 and index < _children.size() else null


## 自己是第几个兄弟（-1 = 已经不在表里）。
func get_index() -> int:
	return _parent._children.find(self) if _parent != null else -1


## 把自己和整棵子树从表里摘掉并释放。**调用后本引用失效**（同 `TreeItem.free()`）。
##
## 释放动作交给表来做（`_release_item_tree`）：GDScript 不允许一个对象在**自己的调用栈里**
## 释放自己（引擎会判定 Object 处于 locked 状态而拒绝），所以「本行自己」的 free 由表推迟到
## 空闲时执行，子树则立即释放。
func remove() -> void:
	var table := _table
	if _parent != null:
		_parent._children.erase(self)
		_parent = null
	# 先让表忘掉这一行，再释放 —— 否则表里会留下指向已释放对象的选中/悬停引用
	if table != null and table.has_method("_item_removed"):
		table._item_removed(self)
	if table != null and table.has_method("_release_item_tree"):
		table._release_item_tree(self, self)
	else:
		# 已经不属于任何表：没人能替我们释放，只能推迟到当前调用栈结束之后
		_table = null
		_parent = null
		call_deferred("free")


func get_depth() -> int:
	return _depth


func get_table() -> Node:
	return _table


## 本行是否处于「所有祖先都展开」的状态（= 会不会出现在屏幕上）。
func is_visible_in_tree() -> bool:
	var p := _parent
	while p != null:
		if p._parent != null and not p._expanded:   # _parent 为空的隐藏根恒展开
			return false
		p = p._parent
	return _table != null


# ---------- 展开 / 选中 ----------

func set_expanded(expanded: bool) -> TreeTableItem:
	if _expanded == expanded:
		return self
	_expanded = expanded
	if _table != null and _table.has_method("_item_expansion_changed"):
		_table._item_expansion_changed(self)
	return self


func is_expanded() -> bool:
	return _expanded


func toggle_expanded() -> TreeTableItem:
	return set_expanded(not _expanded)


func set_selectable(selectable: bool) -> TreeTableItem:
	_selectable = selectable
	return self


func is_selectable() -> bool:
	return _selectable


## 选中本行（等价于 `table.select(item)`）。
func select() -> TreeTableItem:
	if _table != null and _table.has_method("select"):
		_table.select(self)
	return self


# ---------- 内部 ----------

## 重新挂到某张表 / 某个深度，并连带整棵子树（父行被插到别的表下时会用到）。
func _rebind(table: Node, depth: int) -> void:
	_table = table
	_depth = depth
	for c in _children:
		c._rebind(table, depth + 1)


## 行内容变了 → 让表重算可见行并重绘。
func _invalidate() -> void:
	if _table != null and _table.has_method("_item_changed"):
		_table._item_changed()
