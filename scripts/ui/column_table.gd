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
##
## ## 内建滚动（表头固定）
##
## 默认**不开**：内容有多高就报多高，行为与「没有滚动这回事」的年代完全一致。
## 要长列表滚动就显式给一个上限：
##   `set_max_visible_rows(8)` —— 最多显示 8 行，再多就由控件自己出滚动条
##   `set_max_height(320.0)`   —— 直接限制控件总高（表头 + 表体）
## 两者都设时取更小的那个；传 0 取消该项。
##
## 与「套一层 `ScrollContainer`」的区别在于**表头钉住不动**：那种写法会把表头一起滚走。
##
## 三条不变量（改这个文件时别破坏）：
##   1. 没 opt-in 时 `_get_minimum_size().y == get_required_height()`、`_scroll == 0`、
##      `clip_contents == false`，渲染路径与从前逐像素一致；
##   2. **滚动绝不调 `update_minimum_size()`** —— 那会让容器每滚一格就重排一次；
##   3. `_scroll` 只由 `set_scroll()` 写，且 `_layout_rows()` 返回的仍是**未减偏移的内容坐标**，
##      内容坐标 → 控件坐标的换算**全表只有 `_place_action_cell()` 一处**。

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

# ---- 内建滚动 ----
var _scroll := 0.0                  # 表体滚动偏移（px，>= 0；表头不参与）
var _scrollbar_active := false      # 内容是否已超出上限（决定滚动条显隐与末列留宽）
var _vbar: VScrollBar = null
var _bar_w := ThemePalette.SCROLLBAR_W   # 右侧给滚动条留的宽度（实测值，可能比令牌宽）
var _max_visible_rows := 0          # 0 = 不限
var _max_height := 0.0              # 0 = 不限


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	_ensure_vbar()
	# 入树瞬间补一次：**`resized` 可能在 `_ready()` 之前就已经发生过**（用 `--script` 起的
	# 测试场景里必然如此：容器排完版才轮到 ready 通知），那一次没人在听，
	# 于是行内按钮会停在 (0,0) 且不可见 —— 直到下一次 resize 才归位。
	_on_resized()


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
		# 最后一列填满剩余宽度（至少留 TABLE_MIN_COL），避免被其它列挤到溢出台面。
		# 滚动生效时先把滚动条占的宽度扣掉，否则末列的文字会被压在滚动条底下。
		var used := 0.0
		for k in range(_widths.size() - 1):
			used += _widths[k]
		var avail := size.x - (_bar_w if _scrollbar_active else 0.0)
		return maxf(avail - used, ThemePalette.TABLE_MIN_COL)
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
## 内容高度的上报口。**没 opt-in 时就是 `get_required_height()` 原文** ——
## `minf(x, INF) == x`，所以「没上滚动」的那条路与从前逐位一致（这是整套改动的底线）。
func _get_minimum_size() -> Vector2:
	return Vector2(0.0, minf(get_required_height(), _limit_height()))


## 列数 / 列宽 / 行数变化后的统一入口：**重算最小尺寸、更新滚动条、重摆单元格按钮、重绘**。
##
## 调用方**不要**再去补其中任何一件 —— 漏掉一件就是一个 bug。这里原来少了 `queue_redraw()`，
## 于是「拖拽列宽」那条路自己写了 `queue_redraw()` 却没重摆按钮，结果拖动分隔线时
## 表头跟着走、行内按钮钉在原地不动（DeepScribe 报回来的就是这个）。
func _on_columns_changed() -> void:
	update_minimum_size()
	_update_scrollbar()
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
	# 控件尺寸变了：滚动条要重新摆位、「内容是否超出上限」也可能变了，
	# 然后才是「最后一列宽度变了 ⇒ 按钮的 x 要跟着走」。
	# **仍然不调 `update_minimum_size()`** —— 尺寸是高度契约的输出，不是输入（见文件头第 2 条）。
	_layout_scrollbar()
	_update_scrollbar()
	_on_widths_changed()


# ---------------------------------------------------------------- 内建滚动

## 最多显示几行（超出就出滚动条）。传 0 / 负数取消。表头不计入行数。
func set_max_visible_rows(rows: int) -> void:
	_max_visible_rows = maxi(rows, 0)
	update_minimum_size()
	_update_scrollbar()
	queue_redraw()


func get_max_visible_rows() -> int:
	return _max_visible_rows


## 直接限制控件总高（含表头）。传 0 / 负数取消。
func set_max_height(px: float) -> void:
	_max_height = maxf(px, 0.0)
	update_minimum_size()
	_update_scrollbar()
	queue_redraw()


func get_max_height() -> float:
	return _max_height


## 当前是否真的在滚动（= 内容超出了上限）。
func is_scrollable() -> bool:
	return _scrollbar_active


func get_scroll() -> float:
	return _scroll


## 设置滚动偏移（会被钳到 `[0, _max_scroll()]`）。这是**唯一**写 `_scroll` 的地方。
func set_scroll(value: float) -> void:
	var v := clampf(value, 0.0, _max_scroll())
	if is_equal_approx(v, _scroll):
		return
	_scroll = v
	if _vbar != null and is_instance_valid(_vbar):
		# 用 no_signal 版本：否则会把这次设置再回灌进 _on_vbar_changed()，转一圈
		_vbar.set_value_no_signal(v)
	_relayout_actions()          # 按钮的 y 跟着偏移走
	_on_scrolled()
	queue_redraw()


func scroll_by(delta: float) -> void:
	set_scroll(_scroll + delta)


## 把某一行滚进视野（程序化选中一行时用，免得「选中了却看不见」）。
func ensure_row_visible(uid: int) -> void:
	for row in _layout_rows():
		if int(row["uid"]) != uid:
			continue
		var top := float(row["top"]) - ThemePalette.TABLE_HEADER_H
		var bottom := top + float(row["height"])
		if top < _scroll:
			set_scroll(top)
		elif bottom > _scroll + _body_view_h():
			set_scroll(bottom - _body_view_h())
		return


## 内部滚动条（只读用途，主要给回归检查脚本断言用）。
func get_scroll_bar() -> VScrollBar:
	return _ensure_vbar()


## 高度上限；未 opt-in 时返回 `INF`（于是 `minf(内容高, INF) == 内容高`）。
func _limit_height() -> float:
	var limit := INF
	if _max_visible_rows > 0:
		limit = ThemePalette.TABLE_HEADER_H + ThemePalette.TABLE_ROW_H * float(_max_visible_rows)
	if _max_height > 0.0:
		limit = minf(limit, _max_height)
	return limit


## 表体可视高度（不含表头）。
func _body_view_h() -> float:
	return maxf(size.y - ThemePalette.TABLE_HEADER_H, 0.0)


func _max_scroll() -> float:
	if not _scrollbar_active:
		return 0.0
	return maxf(get_required_height() - ThemePalette.TABLE_HEADER_H - _body_view_h(), 0.0)


## 需不需要滚动条。**只看「内容 vs 上限」，刻意不看 `size`** ——
## 否则「滚动条出现 ⇒ 末列变窄 ⇒ size 变 ⇒ 又要重算」会绕成一个回环，
## 而且首帧 `size.y == 0` 时还会误判成「装不下」闪一下滚动条。
func _needs_scroll() -> bool:
	var limit := _limit_height()
	return is_finite(limit) and get_required_height() > limit + 0.5


func _ensure_vbar() -> VScrollBar:
	if _vbar != null and is_instance_valid(_vbar):
		return _vbar
	_vbar = VScrollBar.new()
	_vbar.visible = false
	_vbar.step = ThemePalette.TABLE_ROW_H
	_vbar.custom_step = ThemePalette.TABLE_ROW_H     # 一次滚一行，和逐行的心智模型对齐
	_vbar.value_changed.connect(_on_vbar_changed)
	add_child(_vbar)
	_layout_scrollbar()
	return _vbar


## 只摆位置（resize 走这条，不做显隐决策）。
func _layout_scrollbar() -> void:
	if _vbar == null or not is_instance_valid(_vbar):
		return
	# 预留宽度以**实测**最小宽度为准：主题给的样式盒比令牌宽的话，
	# 只按令牌预留会让末列内容压在滚动条底下。恒取两者的大者。
	_bar_w = maxf(ThemePalette.SCROLLBAR_W, _vbar.get_combined_minimum_size().x)
	_vbar.position = Vector2(size.x - _bar_w, ThemePalette.TABLE_HEADER_H)
	_vbar.size = Vector2(_bar_w, _body_view_h())


## 显隐 + 配 Range + 钳制偏移。**不调 `update_minimum_size()`**（见文件头第 2 条）。
func _update_scrollbar() -> void:
	var want := _needs_scroll()
	var changed := want != _scrollbar_active
	_scrollbar_active = want
	# 裁剪只在滚动生效时打开：没 opt-in 时保持和从前一样（哪怕按钮溢出台面也不裁）
	clip_contents = want

	var bar := _ensure_vbar()
	if bar == null:
		return
	bar.visible = want
	var body_content := maxf(get_required_height() - ThemePalette.TABLE_HEADER_H, 0.0)
	bar.max_value = body_content
	bar.page = minf(_body_view_h(), body_content)
	set_scroll(_scroll)          # 内容变短 / 窗口变大后偏移可能越界，钳一下
	if changed:
		# 滚动条的出现会改变末列宽度 ⇒ 按钮的 x 要重摆、画面要重画
		_on_widths_changed()


func _on_vbar_changed(value: float) -> void:
	set_scroll(value)


## 滚动发生后的钩子（子类可覆写，例如清理悬停高亮）。
func _on_scrolled() -> void:
	pass


## 本帧需要绘制的行区间 `[x, y)`。未启用滚动时恒为 `[0, n)` ——
## 这正是「没 opt-in 就和从前逐像素一致」的来源。
## 末尾多画一行是有意的：让最后一行下沿的接缝也画出来，多出来的部分交给 `clip_contents` 裁掉。
func _visible_row_range(row_h: float, n: int) -> Vector2i:
	if not _scrollbar_active or row_h <= 0.0:
		return Vector2i(0, n)
	var first := clampi(int(floor(_scroll / row_h)), 0, n)
	var last := clampi(int(ceil((_scroll + _body_view_h()) / row_h)) + 1, first, n)
	return Vector2i(first, last)


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


## 子类覆写：当前**未被折叠**的行，每项 `{"uid": int, "top": float, "height": float}`。
##
## `top` 是**内容坐标**：`TABLE_HEADER_H + 行序 × TABLE_ROW_H`，**不扣滚动偏移**。
## 换算成控件坐标只在 `_place_action_cell()` 里做一次（见文件头第 3 条）——
## 这个契约是刻意保持不变的，下游项目可能覆写了本函数，改签名会静默破坏它们。
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
	# 内容坐标 → 控件坐标：**全表只有这一处减滚动偏移**（`_layout_rows()` 的契约保持不变）
	var y := top - _scroll
	# 已经滚到表体带之外的行：把按钮藏起来。
	# 顶部那条尤其要注意 —— 不藏的话它会画到表头上面去（裁剪矩形是整个控件，
	# 表头就在矩形里面，裁不掉）。
	if _scrollbar_active and (y < ThemePalette.TABLE_HEADER_H - 0.5 or y >= size.y):
		box.hide()
		return
	# 先取到最小尺寸，才知道要往上挪多少才能垂直居中
	box.reset_size()
	var col := int(cell["col"])
	var left := 0.0 if col <= 0 else _sep_x(col - 1)
	box.position = Vector2(left + ThemePalette.TABLE_PAD,
			y + (height - box.size.y) * 0.5)
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
	# 滚轮：只有「表体」区域响应，且只在滚动生效时。
	# （`ScrollBar` 自己不消费滚轮事件，只有 `ScrollContainer` 会 —— 所以这里不会双重滚动。）
	if _scrollbar_active and event is InputEventMouseButton and event.pressed \
			and event.position.y > ThemePalette.TABLE_HEADER_H:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_by(-ThemePalette.TABLE_ROW_H)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_by(ThemePalette.TABLE_ROW_H)
			accept_event()
			return

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
