class_name ColumnTable
extends Control
## 可拖拽调列宽的表格基类 —— `DataTable`（平表）与 `TreeTable`（树表）共用。
##
## 为什么自己写：Godot 的 `Tree` **不支持拖拽调列宽**（`get_column_width()` 只读），
## 所以本项目的表格一律 `_draw()` 自绘。而「列宽拖拽」这段逻辑跟表里放什么数据无关，
## 于是抽到基类里：子类只需要实现 `_draw()`。
##
## 子类要做三件事：
##   1. 覆写 `_theme_type()` 返回自己的主题类型名（`&"DataTable"` / `&"TreeTable"`）；
##   2. 覆写 `_draw()`，用 `_col_w()` / `_sep_x()` / `_theme_color()` 画内容；
##   3. 覆写 `get_required_height()` 报告内容需要的高度（基类默认只有表头高），
##      并覆写 `_layout_rows()` / `_all_row_uids()` —— 单元格按钮靠它们定位（见下）。
##
## **高度由内容决定，不需要调用方手算**：「表头 + 行数 × 行高」交给
## `_get_minimum_size()` 报给容器，容器会自己腾地方。所以调用方只要管宽度
## （`set_min_width()`，或者直接设 `custom_minimum_size.x`）；
## **不要去写 `custom_minimum_size.y`** —— 那是「至少这么高」，写 0 会覆盖掉自动高度，
## 控件就会在自己的矩形之外画内容（表现出来就是表格被裁掉、行溢到卡片外面）。
##
## ## 单元格按钮（行内操作）
##
## `set_row_actions()` 能把**真实的 `Button` 节点**放进某一行的某一列（一行可放多个，
## 比如「开始 / 暂停 / 删除」）。按钮是这个表格的子节点，所以会跟着表格一起滚、
## 一起释放；主题变体也照常生效（用 `CellButton` / `CellSuccessButton` /
## `CellDangerButton` 这些紧凑变体，普通按钮 32px 高、塞进 30px 的行里会顶到分隔线）。
##
## 行用 **整数 uid** 标识（不是对象引用），这样「行被删掉」和「按钮节点还在」这两件事
## 不会互相悬空：uid 只用于查表，某行不存在了就把它的按钮回收掉。
##
## 注意几点：
##   * 按钮所在的列**要留够宽度**（三个按钮约 140px 起）。放在最后一列最省事
##     （最后一列会自动填满剩余宽度）；拖动别的列把它挤窄了，按钮会溢出到相邻列。
##   * 点按钮**不会**顺带选中该行（按钮自己消费掉了事件）。想要「点按钮也选中行」，
##     在 `cell_action_pressed` 的处理里自己调 `select()`。
##   * 按钮是真的节点：几百行 × 每行几个按钮会有可观的开销。行数很多时建议只给
##     当前页/可见行配按钮。
##
## 列宽规则：拖动表头相邻列之间的分隔线调列宽（最小 `TABLE_MIN_COL`）；
## **最后一列自动填满剩余宽度**，不参与拖拽。颜色从 `_theme_type()` 的类型读取
## （回退到 ThemePalette 令牌），因此随全局主题统一调整。

## 单元格按钮被点击：`uid` 是行标识（见 `set_row_actions`），`index` 是该行第几个按钮，
## `action` 是按钮的 `action` 字段（没写就是按钮文字）。
signal cell_action_pressed(uid: int, index: int, action: String)

const _HIT := 6.0        # 分隔线命中范围（px）

var _titles: PackedStringArray = []
var _widths: PackedFloat32Array = []

var _drag_col := -1       # 正在拖拽的分隔线左侧列索引
var _drag_start_x := 0.0
var _drag_start_w := 0.0

## uid -> {"col": int, "box": HBoxContainer}
var _action_cells := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)


## 设置列标题与初始列宽（宽度个数应与标题个数一致；最后一列宽度会被忽略、自动填满）。
func set_columns(titles: PackedStringArray, widths: PackedFloat32Array) -> void:
	_titles = titles
	_widths = widths
	_on_columns_changed()
	queue_redraw()


func get_columns() -> PackedStringArray:
	return _titles


## 列 i 的实际绘制宽度（最后一列自动填满剩余宽度）。
func _col_w(i: int) -> float:
	if _widths.is_empty():
		return 0.0
	if i == _widths.size() - 1:
		# 最后一列填满剩余宽度（至少留 TABLE_MIN_COL），避免被其它列挤到溢出台面
		var used := 0.0
		for k in range(_widths.size() - 1):
			used += _widths[k]
		return maxf(size.x - used, ThemePalette.TABLE_MIN_COL)
	return _widths[i]


## 第 i 条分隔线（列 i 的右边界）的 x 坐标。
func _sep_x(i: int) -> float:
	var x := 0.0
	for k in range(i + 1):
		x += _col_w(k)
	return x


## 返回命中的分隔线左侧列索引，未命中返回 -1（最后一列不参与拖拽）。
func _hit_sep(mx: float) -> int:
	var best := -1
	var best_d := _HIT
	for i in range(_widths.size() - 1):
		var d := absf(_sep_x(i) - mx)
		if d < best_d:
			best_d = d
			best = i
	return best


## 内容需要的高度（子类覆写；基类只算表头）。
func get_required_height() -> float:
	return ThemePalette.TABLE_HEADER_H


## 设置表格宽度。高度不用管：它由 `get_required_height()` 自动报给容器。
func set_min_width(width: float) -> void:
	var ms := custom_minimum_size
	ms.x = width
	custom_minimum_size = ms


## 内容高度的上报口。走 `_get_minimum_size()` 而不是去写 `custom_minimum_size.y`，
## 是因为容器取的是「两者的大者」：调用方随便设 `custom_minimum_size`（哪怕是 0）
## 都不会把自动高度弄丢。**别改成自己写 custom_minimum_size.y** ——
## 之前就是这么写的，结果调用方一句 `custom_minimum_size = Vector2(390, 0)`
## 就把高度清零了，控件随即在自己的矩形之外画表格（表现为表格被裁掉）。
func _get_minimum_size() -> Vector2:
	return Vector2(0.0, get_required_height())


## 列数 / 列宽 / 行数变化后的统一入口：**重算最小尺寸、重摆单元格按钮、重绘**，三件一起做。
##
## 调用方**不要**再去补其中任何一件 —— 漏掉一件就是一个 bug。这里原来少了 `queue_redraw()`，
## 于是「拖拽列宽」那条路自己写了 `queue_redraw()` 却没重摆按钮，结果拖动分隔线时
## 表头跟着走、行内按钮钉在原地不动（DeepScribe 报回来的就是这个）。
func _on_columns_changed() -> void:
	update_minimum_size()
	_on_widths_changed()


## 只是列宽变了（拖拽过程中，或控件被 resize）：按钮的 x 与画面都要更新。
##
## 刻意**不调 `update_minimum_size()`**：拖拽时每秒会来上百个 motion 事件，
## 每次都让容器重算一遍最小尺寸纯属白费（行高不会因为拖列宽而变）。
## 「列宽也可能影响最小尺寸」的那种场景走 `_on_columns_changed()`。
func _on_widths_changed() -> void:
	_relayout_actions()
	queue_redraw()


func _on_resized() -> void:
	_on_widths_changed()         # 窗口尺寸变了 ⇒ 最后一列宽度跟着变 ⇒ 按钮的 x 要跟着走


# ---------------------------------------------------------------- 单元格按钮

## 给 `uid` 这一行的第 `col` 列放按钮。`specs` 每项是一个字典：
##   `{"text": "开始",               # 必填，按钮文字
##     "action": "start",           # 可选，随信号回传的标识；默认取 text
##     "variation": "CellButton",   # 可选，主题变体；默认 CellButton（紧凑中性）
##     "tooltip": "启动这一路",      # 可选
##     "disabled": false}`          # 可选
## 传空数组 = 清掉这一行已有的按钮。
##
## **行数据换了之后要重新调一次**（按钮不会自动跟着行数据走，它们只认 uid）。
func set_row_actions(uid: int, col: int, specs: Array) -> void:
	_remove_action_cell(uid)
	if specs.is_empty():
		return

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", int(ThemePalette.TABLE_ACTION_SEP))
	# 按钮之间的空隙让点击落回表格本身（否则整行都点不动、选不中）
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var index := 0
	for spec in specs:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var button := Button.new()
		button.text = str(spec.get("text", ""))
		var variation := str(spec.get("variation", "CellButton"))
		if not variation.is_empty():
			button.theme_type_variation = variation
		button.tooltip_text = str(spec.get("tooltip", ""))
		button.disabled = bool(spec.get("disabled", false))
		var action := str(spec.get("action", button.text))
		button.pressed.connect(_on_action_pressed.bind(uid, index, action))
		box.add_child(button)
		index += 1

	_action_cells[uid] = {"col": col, "box": box}
	_relayout_actions()


## 取回某个按钮，便于事后改文字/禁用（例如「运行中」时把「开始」置灰）。
func get_action_button(uid: int, index: int) -> Button:
	if not _action_cells.has(uid):
		return null
	var box: Node = _action_cells[uid]["box"]
	if not is_instance_valid(box) or index < 0 or index >= box.get_child_count():
		return null
	return box.get_child(index) as Button


## 清掉某一行的按钮。
func clear_row_actions(uid: int) -> void:
	_remove_action_cell(uid)


## 清掉所有行的按钮（换整张表的数据时用）。
func clear_all_actions() -> void:
	for uid in _action_cells.keys():
		_remove_action_cell(uid)


## 子类覆写：当前**可见**的行，每项 `{"uid": int, "top": float, "height": float}`
## （`top` 含表头偏移，用控件自身坐标）。基类据此摆放按钮。
func _layout_rows() -> Array:
	return []


## 子类覆写：当前**存在**的所有行 uid（**含被折叠/隐藏的**）。
## 基类靠它区分「这一行只是暂时收起来了（按钮藏起来留着）」和
## 「这一行已经没了（按钮连同节点一起回收）」。
func _all_row_uids() -> Array:
	return []


func _on_action_pressed(uid: int, index: int, action: String) -> void:
	cell_action_pressed.emit(uid, index, action)


## 把按钮摆到对应单元格里；顺带做显隐与回收。
func _relayout_actions() -> void:
	if _action_cells.is_empty():
		return

	var valid := {}
	for uid in _all_row_uids():
		valid[uid] = true

	var seen := {}
	for row in _layout_rows():
		var uid: int = row["uid"]
		seen[uid] = true
		if _action_cells.has(uid):
			_place_action_cell(uid, float(row["top"]), float(row["height"]))

	for uid in _action_cells.keys():
		if seen.has(uid):
			continue
		if valid.has(uid):
			# 行还在、只是被折叠/隐藏了：留着节点，先藏起来
			var hidden_box: Node = _action_cells[uid]["box"]
			if is_instance_valid(hidden_box):
				(hidden_box as Control).visible = false
		else:
			# 行已经没了：回收
			_remove_action_cell(uid)


func _place_action_cell(uid: int, top: float, height: float) -> void:
	var cell: Dictionary = _action_cells[uid]
	var box: Control = cell["box"]
	if not is_instance_valid(box):
		return
	# 先取到最小尺寸，才知道要往上挪多少才能垂直居中
	box.reset_size()
	var col := int(cell["col"])
	var left := 0.0 if col <= 0 else _sep_x(col - 1)
	box.position = Vector2(left + ThemePalette.TABLE_PAD,
			top + (height - box.size.y) * 0.5)
	box.visible = true


func _remove_action_cell(uid: int) -> void:
	if not _action_cells.has(uid):
		return
	var box: Node = _action_cells[uid]["box"]
	if is_instance_valid(box):
		(box as Control).hide()      # 立刻不可见：queue_free 要到帧末才真删，中间这一帧别让它还画着
		# 用 queue_free 而不是 free：可能是「点了按钮 → 回调里重建行 → 走到这里」，
		# 那个正在发 pressed 信号的按钮还在自己的调用栈上，立即释放会被引擎拒绝。
		box.queue_free()
	_action_cells.erase(uid)


## 从主题类型 `_theme_type()` 取颜色，未定义时回退到令牌默认值。
func _theme_color(name: StringName, fallback: Color) -> Color:
	var t := _theme_type()
	return get_theme_color(name, t) if has_theme_color(name, t) else fallback


## 本表使用的主题类型名（子类覆写）。
func _theme_type() -> StringName:
	return &"ColumnTable"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# 只有表头那一行才能起拖；表体的点击留给子类自己处理（见 TreeTable）
			if event.position.y <= ThemePalette.TABLE_HEADER_H:
				_drag_col = _hit_sep(event.position.x)
				if _drag_col >= 0:
					_drag_start_x = event.position.x
					_drag_start_w = _widths[_drag_col]
					accept_event()
					return
		elif _drag_col >= 0:
			_drag_col = -1
			accept_event()
			return
		_on_body_input(event)
	elif event is InputEventMouseMotion and _drag_col >= 0:
		# 拖拽列宽上下限：≥ TABLE_MIN_COL，且不能把其它列挤到连最后一列都放不下
		var other := 0.0
		for k in range(_widths.size() - 1):
			if k != _drag_col:
				other += _widths[k]
		var lo := ThemePalette.TABLE_MIN_COL
		var hi := maxf(size.x - other - ThemePalette.TABLE_MIN_COL, lo)
		_widths[_drag_col] = clampf(_drag_start_w + (event.position.x - _drag_start_x), lo, hi)
		# 列宽变了 ⇒ 按钮该在的位置也变了（最后一列的宽度是「剩余宽度」，所以拖任何一条
		# 分隔线都会挪到它），所以这里不能只 queue_redraw()。
		_on_widths_changed()
		accept_event()
	else:
		_on_body_input(event)


## 表体（表头以下）的输入钩子，供子类做行选择/展开等。默认忽略。
func _on_body_input(_event: InputEvent) -> void:
	pass
