class_name TreeTable
extends ColumnTable
## 树状表格（可展开的层级数据 + 可拖拽调列宽）。
##
## 为什么不直接用 Godot 的 `Tree`：`Tree` **不支持拖拽调列宽**
## （`get_column_width()` 只读），而工控界面里列宽随数据长短变化是刚需；
## 另外自绘能让配色/行高完全走本项目的主题令牌。列宽机制直接继承自 `ColumnTable`，
## 与 `DataTable` 共用同一套拖拽实现。
##
## 用法：
##   var t := TreeTable.new()
##   t.set_columns(["设备 / 通道", "状态", "数值"], [220.0, 90.0, 90.0])
##   var dev := t.create_item()
##   dev.set_cells(["设备 A", "在线", "—"]).set_expanded(true)
##   var ch := t.create_item(dev)
##   ch.set_cells(["  └ 通道 1", "正常", "10.0 V"])
##   t.item_selected.connect(func(it): print(it.get_cells()))
##
## 放在 `ScrollContainer` 里即可滚动：高度按「表头 + 可见行数 × 行高」自动上报，
## 不需要调用方手算（要改宽度用 `set_min_width()`）。
##
## 层级关系由控件自己画（缩进 + 引导线 + 展开箭头），**单元格文本里不要再手写
## `└`/`├` 之类的符号** —— 那会和引导线重复，看起来有两个层级标记。
##
## 颜色/图标从主题类型 "TreeTable" 读取（回退到 ThemePalette 令牌）。

## 选中某一行（点击或 `select()` 触发）。
signal item_selected(item: TreeTableItem)
## 双击某一行（业务上通常 =「打开/编辑这一项」）。
signal item_activated(item: TreeTableItem)
## 某一行被展开/收起。
signal item_toggled(item: TreeTableItem, expanded: bool)

var _root: TreeTableItem = null
var _selected: TreeTableItem = null
var _hovered: TreeTableItem = null
var _visible: Array[TreeTableItem] = []
var _last_click_ms := 0
var _last_click_item: TreeTableItem = null


func _init() -> void:
	# 一个不可见的根：所有顶层行都是它的子行，于是「深度/可见性/递归遍历」只有一套写法
	# （与 Godot 原生 Tree 的隐藏根节点是同一个思路）。
	_root = TreeTableItem.new(self, null)
	_root._expanded = true


func _ready() -> void:
	super._ready()
	mouse_exited.connect(_on_mouse_exited)


func _notification(what: int) -> void:
	# 行是显式所有权（见 TreeTableItem 的说明），表消失时要自己把它们释放掉
	if what == NOTIFICATION_PREDELETE and _root != null:
		var doomed := _root._children.duplicate()
		_root._children.clear()
		_selected = null
		_hovered = null
		for item in doomed:
			_release_item_tree(item)
		_root.free()
		_root = null


# ---------- 数据 ----------

## 建一行。`parent` 为空时建在顶层。
## 挂载/深度维护都在 `TreeTableItem.add_child_item()` 里，建行与后续插行是同一条路径。
func create_item(parent: TreeTableItem = null) -> TreeTableItem:
	var host := parent if parent != null else _root
	return host.add_child_item(TreeTableItem.new(self, host))


func get_root() -> TreeTableItem:
	return _root


## 清空所有行并释放（保留列定义）。重建整张表时用它，别自己 free 行。
func clear_items() -> void:
	var doomed := _root._children.duplicate()
	_root._children.clear()
	# 必须先断开选中/悬停引用，再释放 —— 它们可能指向将被释放的行
	_selected = null
	_hovered = null
	for item in doomed:
		_release_item_tree(item)
	_rebuild_visible()
	item_selected.emit(null)


## 当前选中的行（可能为 null）。
func get_selected() -> TreeTableItem:
	return _selected


## 选中一行；传 null 取消选中。不可选中的行会被忽略。
func select(item: TreeTableItem) -> void:
	if item != null and not item.is_selectable():
		return
	if _selected == item:
		return
	_selected = item
	queue_redraw()
	item_selected.emit(item)


## 可见行数（= 屏幕上真正画出来的行数）。
func get_visible_count() -> int:
	return _visible.size()


## 全部展开 / 全部收起。
func set_all_expanded(expanded: bool) -> void:
	_set_all_expanded(_root, expanded)
	_rebuild_visible()
	item_toggled.emit(null, expanded)


func _set_all_expanded(item: TreeTableItem, expanded: bool) -> void:
	# 直接改 _expanded 而不是走 set_expanded()：后者每行都会触发一次重算，
	# 几千行时会退化成 O(n²)。这里统一改完，最后只重算一次。
	for c in item._children:
		if c.get_child_count() > 0:
			c._expanded = expanded
		_set_all_expanded(c, expanded)


# ---------- 布局（ColumnTable 钩子） ----------

func get_required_height() -> float:
	return ThemePalette.TABLE_HEADER_H + ThemePalette.TABLE_ROW_H * _visible.size()


func _theme_type() -> StringName:
	return &"TreeTable"


# ---------- 内部 ----------

## 行结构 / 内容变化后的统一入口（`TreeTableItem` 会调它）。
func _item_changed() -> void:
	_rebuild_visible()


## 展开状态变了：可见行集合和高度都要重算，并广播信号。
func _item_expansion_changed(item: TreeTableItem) -> void:
	_rebuild_visible()
	item_toggled.emit(item, item.is_expanded())


## 某一行（及其子树）即将被释放：先把它从选中/悬停里摘干净，避免留下悬空引用。
## 必须在真正 free 之前调用 —— 之后任何比较都成了访问已释放对象。
func _item_removed(item: TreeTableItem) -> void:
	if _selected != null and _is_under(_selected, item):
		_selected = null
		item_selected.emit(null)
	if _hovered != null and _is_under(_hovered, item):
		_hovered = null
	_rebuild_visible()


## 释放一棵行子树。`locked` 是「此刻正在执行自己的方法、因而被引擎锁住」的那一行
## （从 `TreeTableItem.remove()` 过来的就是它）：它的 `free()` 必须 `call_deferred`，
## 否则会撞上 Object 的 locked 检查。其余行都立即释放。
##
## 先把整棵子树的内部链接清空、再统一释放：这样中途不存在「半挂不挂」的状态，
## 表里的 `_visible` / `_selected` 也不会指向已经在释放队列里的行。
func _release_item_tree(item: TreeTableItem, locked: TreeTableItem = null) -> void:
	var stack: Array[TreeTableItem] = [item]
	var doomed: Array[TreeTableItem] = []
	while not stack.is_empty():
		var node: TreeTableItem = stack.pop_back()
		for c in node._children:
			stack.append(c)
		node._children.clear()
		node._table = null
		node._parent = null
		doomed.append(node)
	for node in doomed:
		if node == locked:
			node.call_deferred("free")
		else:
			node.free()


## candidate 是 ancestor 自己或它的后代吗？（只在两者都还活着时调用）
func _is_under(candidate: TreeTableItem, ancestor: TreeTableItem) -> bool:
	var p := candidate
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


## 深度优先收集所有「祖先都展开」的行（不含隐藏的根）。
func _rebuild_visible() -> void:
	_visible.clear()
	_collect(_root)
	# 选中行被折叠隐藏了就取消选中，否则会出现「高亮在看不见的地方」
	if _selected != null and not _visible.has(_selected):
		_selected = null
		item_selected.emit(null)
	if _hovered != null and not _visible.has(_hovered):
		_hovered = null
	# 可见行数变了 → 高度也变了，让容器重新问一次最小尺寸
	update_minimum_size()
	queue_redraw()


## 缩进层级 `level` 那根竖线在本行画多长。返回值：
##   `row_h`   → 贯穿整行（本行是 ├ 的一支，线要继续往下走到兄弟那里）
##   `row_h/2` → 画到行中线就收，和横线接成 └（本行是该层的最后一个子项）
##   `-1`      → 本行**不画**这一层的线
##
## 第三种是容易被漏掉的一种：某层在它的最后一个子项那一行收成 └ 之后，
## **那个子项自己的子树里就不该再有这一层的线了**（只有缩进的空白）。
## 经典树线就是这么画的：
##     ├─ a1
##     │   ├─ x
##     │   └─ y
##     └─ a2      ← 第一层在这行收口
##         ├─ p   ← 注意 p/q 左边没有第一层的竖线
##         └─ q
## 早期版本按「一直画到子树最后一行」来写，结果 a2 子树里多出一条悬空竖线。
func _guide_bottom(item: TreeTableItem, level: int, row_h: float) -> float:
	# 这一层的竖线属于「深度 level+1」的那个祖先；本行相对于它是深度 level+2 的那个子项
	# （也就是「本行是从哪个兄弟分出来的」）。
	var branch := item
	while branch != null and branch.get_depth() > level + 2:
		branch = branch.get_parent()
	if branch == null or branch.get_depth() != level + 2:
		return -1.0
	var owner := branch.get_parent()
	if owner == null:
		return -1.0
	if branch.get_index() < owner.get_child_count() - 1:
		return row_h                                  # 后面还有兄弟 → 贯穿
	if branch == item:
		return row_h * 0.5                            # 本行就是该层最后一个子项 → 收成 └
	return -1.0                                       # 本行在「最后一个子项」的子树里 → 不画


func _collect(item: TreeTableItem) -> void:
	for c in item._children:
		_visible.append(c)
		if c.is_expanded():
			_collect(c)


## 命中第几行（-1 = 没命中行）。
func _row_at(pos: Vector2) -> int:
	if _visible.is_empty():
		return -1
	var i := int(floor((pos.y - ThemePalette.TABLE_HEADER_H) / ThemePalette.TABLE_ROW_H))
	return i if i >= 0 and i < _visible.size() else -1


## 点击点是否落在某行的「展开箭头」上（只有真的有子行才算）。
func _hits_arrow(item: TreeTableItem, x: float) -> bool:
	if item.get_child_count() == 0:
		return false
	var left := ThemePalette.TABLE_PAD + float(_indent_level(item)) * ThemePalette.TABLE_INDENT
	return x >= left and x <= left + ThemePalette.TABLE_ARROW_W


## 顶层行缩进为 0（根的深度是 0，顶层行是 1）。
func _indent_level(item: TreeTableItem) -> int:
	return maxi(item.get_depth() - 1, 0)


func _on_body_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := _row_at(event.position)
		var item := _visible[i] if i >= 0 else null
		if item != _hovered:
			_hovered = item
			queue_redraw()
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	var idx := _row_at(event.position)
	if idx < 0:
		select(null)
		accept_event()
		return
	var item := _visible[idx]
	if _hits_arrow(item, event.position.x):
		item.toggle_expanded()
		accept_event()
		return
	if item.is_selectable():
		select(item)
	# 双击 = 激活（用「同一行 + 间隔 < 400ms」判定，省掉一条 OS 级的双击事件处理）
	var now := Time.get_ticks_msec()
	if item == _last_click_item and now - _last_click_ms < 400:
		item_activated.emit(item)
		_last_click_item = null
	else:
		_last_click_ms = now
		_last_click_item = item
	accept_event()


func _on_mouse_exited() -> void:
	if _hovered != null:
		_hovered = null
		queue_redraw()


# ---------- 绘制 ----------

func _draw() -> void:
	if _titles.is_empty():
		return
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()

	var header_h := ThemePalette.TABLE_HEADER_H
	var row_h := ThemePalette.TABLE_ROW_H
	var pad := ThemePalette.TABLE_PAD
	var cell_bg := _theme_color(&"cell_bg_color", ThemePalette.SURFACE)
	var header_bg := _theme_color(&"header_bg_color", ThemePalette.SURFACE_ALT)
	var grid := _theme_color(&"grid_color", ThemePalette.BORDER)
	var text := _theme_color(&"text_color", ThemePalette.TEXT)
	var header_text := _theme_color(&"header_text_color", ThemePalette.TEXT)
	var selected_bg := _theme_color(&"selected_bg_color", ThemePalette.ACCENT_SOFT)
	var hover_bg := _theme_color(&"hover_bg_color", ThemePalette.SURFACE_ALT)
	var guide := _theme_color(&"guide_color", ThemePalette.BORDER_STRONG)

	draw_rect(Rect2(0, header_h, size.x, size.y - header_h), cell_bg, true)
	draw_rect(Rect2(0, 0, size.x, header_h), header_bg, true)

	var arrow_open := _theme_icon(&"arrow_expanded", "arrow_down.svg")
	var arrow_closed := _theme_icon(&"arrow_collapsed", "arrow_right.svg")

	# ---- 行 ----
	var y := header_h
	for item in _visible:
		var is_sel := item == _selected
		if is_sel:
			draw_rect(Rect2(0, y, size.x, row_h), selected_bg, true)
		elif item == _hovered:
			draw_rect(Rect2(0, y, size.x, row_h), hover_bg, true)

		# 层级引导线：每一层画一段竖线，再横着拐进本行（各层的长度规则见 _guide_bottom 的说明）
		var depth := _indent_level(item)
		var mid_y := y + row_h * 0.5
		for level in depth:
			var length := _guide_bottom(item, level, row_h)
			if length < 0.0:
				continue
			var gx := pad + float(level) * ThemePalette.TABLE_INDENT + ThemePalette.TABLE_ARROW_W * 0.5
			draw_line(Vector2(gx, y), Vector2(gx, y + length), guide, 1.0)
		if depth > 0:
			var gx2 := pad + float(depth - 1) * ThemePalette.TABLE_INDENT \
					+ ThemePalette.TABLE_ARROW_W * 0.5
			draw_line(Vector2(gx2, mid_y), Vector2(gx2 + ThemePalette.TABLE_INDENT, mid_y), guide, 1.0)

		# 第 0 列：缩进 + 展开箭头 + 文本
		var indent := float(depth) * ThemePalette.TABLE_INDENT
		var name_x := pad + indent + ThemePalette.TABLE_ARROW_W
		if item.get_child_count() > 0:
			var tex := arrow_open if item.is_expanded() else arrow_closed
			if tex != null:
				var icon_size := tex.get_size()
				draw_texture_rect(tex, Rect2(
						pad + indent + (ThemePalette.TABLE_ARROW_W - icon_size.x) * 0.5,
						y + (row_h - icon_size.y) * 0.5, icon_size.x, icon_size.y), false)
		var baseline := y + row_h * 0.5 + fs * 0.35
		draw_string(font, Vector2(name_x, baseline), _cell_text(item, 0),
				HORIZONTAL_ALIGNMENT_LEFT,
				maxf(_col_w(0) - name_x - pad, 0.0), fs, text)

		# 其余列
		var cx := _col_w(0)
		for c in range(1, _titles.size()):
			draw_string(font, Vector2(cx + pad, baseline), _cell_text(item, c),
					HORIZONTAL_ALIGNMENT_LEFT, _col_w(c) - pad * 2.0, fs, text)
			cx += _col_w(c)
		y += row_h

	# ---- 列分隔线（画在行之上，避免被选中底色盖掉） ----
	for i in range(_titles.size()):
		var sx := _sep_x(i)
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), grid, 1.0)
		draw_string(font, Vector2(sx - _col_w(i) + pad, header_h / 2.0 + fs * 0.35), _titles[i],
				HORIZONTAL_ALIGNMENT_LEFT, _col_w(i) - pad * 2.0, fs, header_text)

	# 表头下沿 + 底边线
	draw_line(Vector2(0, header_h), Vector2(size.x, header_h), grid, 1.0)
	draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)


func _cell_text(item: TreeTableItem, col: int) -> String:
	var cells := item.get_cells()
	return cells[col] if col >= 0 and col < cells.size() else ""


## 从主题类型 "TreeTable" 取图标，未定义时回退到 themes/icons 里的同名文件。
func _theme_icon(name: StringName, fallback_file: String) -> Texture2D:
	var t := _theme_type()
	if has_theme_icon(name, t):
		return get_theme_icon(name, t)
	return load("res://themes/icons/" + fallback_file) as Texture2D
