extends SceneTree
## 表格「行内按钮」的回归检查（headless，不需要窗口、不需要后端）。
##
##   godot --headless --path . --script res://tools/checks/table_actions.gd
##   期望：输出 [check] PASS，退出码 0
##
## 为什么专门有这个脚本：行内按钮的 x 是**算出来的**（`_place_action_cell()` 用列宽定位），
## 所以任何「改变了列宽/行结构却没重摆按钮」的地方都会让它留在原地。
## 这类问题**跑场景不会报错、断言不写清楚也看不出来** —— 上游 DeepScribe 就报回来一个：
## 拖拽列宽时表头跟着走、按钮钉在原地（原因是拖拽分支只 `queue_redraw()`，没重摆按钮）。
## 本脚本用合成的 `InputEventMouseButton` + `InputEventMouseMotion` 打进 `_gui_input()`
## 来钉住这条路径。
##
## 注意：判断按钮位置**不能用 `button.position`** —— 按钮是 HBoxContainer 的子节点，
## 在 HBox 里恒为第 0 个（x 永远是 0）；被移动的是那个 HBox，所以要用它的 `global_position`。

var _fails := 0
## 信号回调要写回的结果放**成员变量**：GDScript 的 lambda 是按值捕获局部变量的，
## 在 lambda 里给外层局部变量赋值只改到它自己那份副本（踩过）。
var _clicked: Array = []


func _initialize() -> void:
	await _check_drag_relayouts_buttons()
	_check_tree_actions()
	await _check_data_table_actions()
	print("[check] %s" % ("PASS" if _fails == 0 else "FAIL（%d 项）" % _fails))
	quit(_fails)


## 拖拽列宽 → 按钮必须跟着走（回归：这条曾经是坏的）
func _check_drag_relayouts_buttons() -> void:
	var table := DataTable.new()
	table.set_columns(PackedStringArray(["名称", "数值", "操作"]),
			PackedFloat32Array([120.0, 100.0, 200.0]))
	table.set_rows([["A", "1", ""], ["B", "2", ""]])
	table.set_min_width(420.0)
	root.add_child(table)
	await process_frame

	# 按钮放在**最后一列**（最常用的摆法）：它的 x = 前面各列宽度之和，
	# 而最后一列的宽度是「剩余宽度」，所以拖任何一条分隔线都会挪到它
	table.set_row_actions(0, 2, [{"text": "开始", "action": "start"}])
	await process_frame
	var box := table.get_action_button(0, 0).get_parent() as Control
	var box_x0 := box.global_position.x
	var sep_x0 := table._sep_x(0)

	_press(table, Vector2(sep_x0, 10.0))
	_move(table, Vector2(sep_x0 + 60.0, 10.0))
	await process_frame

	var sep_moved := table._sep_x(0) - sep_x0
	var box_moved := box.global_position.x - box_x0
	_eq(sep_moved, 60.0, 1.0, "拖拽后分隔线位移 60px")
	_eq(box_moved, 60.0, 1.0, "行内按钮跟着列宽一起位移（拖拽分支有没有重摆按钮）")
	table.free()


## 展开/收起、删行、点按钮回传
func _check_tree_actions() -> void:
	var tree := TreeTable.new()
	tree.set_columns(PackedStringArray(["名称", "操作"]),
			PackedFloat32Array([260.0, 200.0]))
	tree.set_min_width(460.0)
	root.add_child(tree)

	var dev := tree.create_item()
	dev.set_cells(PackedStringArray(["设备 A", ""]))
	var ch1 := tree.create_item(dev)
	ch1.set_cells(PackedStringArray(["通道 1", ""]))
	var ch2 := tree.create_item(dev)
	ch2.set_cells(PackedStringArray(["通道 2", ""]))

	tree.set_item_actions(dev, 1, _specs())
	tree.set_item_actions(ch1, 1, _specs())
	tree.set_item_actions(ch2, 1, _specs())
	_eq(_visible_boxes(tree), 1.0, 1e-4, "设备收起时只有设备行的按钮可见（子行跟着隐藏）")
	dev.set_expanded(true)
	_eq(_visible_boxes(tree), 3.0, 1e-4, "展开后三行按钮都回来")
	_ok(_box_of(tree, dev.uid).global_position.y < _box_of(tree, ch1.uid).global_position.y,
			"按钮纵向位置跟着行序（设备行在上）")

	tree.cell_action_pressed.connect(func(uid: int, index: int, action: String):
		_clicked = [uid, index, action])
	tree.get_action_button(ch1.uid, 2).pressed.emit()
	_ok(not _clicked.is_empty(), "点按钮会发 cell_action_pressed 信号")
	if _clicked.size() == 3:
		_eq(float(_clicked[0]), float(ch1.uid), 1e-4, "回传的行 uid 正确")
		_eq(float(_clicked[1]), 2.0, 1e-4, "回传的按钮序号正确")
		_ok(str(_clicked[2]) == "delete", "回传的 action 正确（%s）" % str(_clicked[2]))

	# uid 要在 remove() **之前**取：删了之后这个引用就失效了（行由表拥有）
	var ch2_uid := ch2.uid
	ch2.remove()
	_eq(_visible_boxes(tree), 2.0, 1e-4, "删行后其按钮立刻不可见")
	_ok(tree.get_action_button(ch2_uid, 0) == null, "已删行的按钮查不到了")
	tree.free()


func _check_data_table_actions() -> void:
	var table := DataTable.new()
	table.set_columns(PackedStringArray(["名称", "操作"]),
			PackedFloat32Array([200.0, 220.0]))
	table.set_min_width(460.0)
	root.add_child(table)
	_set_rows(table, 5)
	_eq(_boxes(table).size(), 5.0, 1e-4, "5 行各配一组按钮")
	_set_rows(table, 2)
	await process_frame                      # 回收用的是 queue_free，帧末才真删
	_eq(_boxes(table).size(), 2.0, 1e-4, "行数变少后多出来的按钮被回收")
	table.clear_all_actions()
	await process_frame
	_eq(_boxes(table).size(), 0.0, 1e-4, "clear_all_actions() 全部回收")
	table.free()


# ---------- 工具 ----------

func _set_rows(table: DataTable, n: int) -> void:
	var rows: Array = []
	for i in n:
		rows.append(["行 %d" % (i + 1), ""])
	table.set_rows(rows)
	for i in n:
		table.set_row_actions(i, 1, _specs())


func _specs() -> Array:
	return [
		{"text": "开始", "action": "start"},
		{"text": "暂停", "action": "pause"},
		{"text": "删除", "action": "delete"},
	]


func _boxes(t: Node) -> Array:
	var out: Array = []
	for c in t.get_children():
		if c is HBoxContainer:
			out.append(c)
	return out


func _visible_boxes(t: Node) -> float:
	var n := 0
	for b in _boxes(t):
		if (b as Control).visible:
			n += 1
	return float(n)


func _box_of(tree: TreeTable, uid: int) -> Control:
	return tree.get_action_button(uid, 0).get_parent() as Control


func _press(c: Control, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	c._gui_input(e)


func _move(c: Control, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	c._gui_input(e)


func _eq(got: float, want: float, tol: float, what: String) -> void:
	if absf(got - want) <= tol:
		print("  [ok]   %s" % what)
	else:
		_fails += 1
		print("  [FAIL] %s：期望 %s，实际 %s" % [what, want, got])


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  [ok]   %s" % what)
	else:
		_fails += 1
		print("  [FAIL] %s" % what)
