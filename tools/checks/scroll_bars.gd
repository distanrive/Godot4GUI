extends SceneTree
## 滚动条 / 表格内建滚动 / LogView 的回归检查（headless，不需要窗口、不需要后端）。
##
##   godot --headless --path . --script res://tools/checks/scroll_bars.gd
##   期望：输出 [check] PASS，退出码 0
##
## 为什么要有它：
##  1. **滚动条的粗细完全由主题样式盒的最小尺寸决定**。这里曾经等价于 0
##     （`_sb()` 的 pad 默认 0），实测 `VScrollBar.get_combined_minimum_size()` 就是 `(0, 0)` ——
##     轨道和滑块都画不出来，整个界面的滚动条都成了抓不住的细痕。
##     这是一条**改了主题就会悄悄复发**的缺陷（画面照样不报错），所以钉在断言里。
##  2. 表格内建滚动动了四条线（绘制、命中测试、行内按钮、最小尺寸契约），
##     其中「滚动不能触发最小尺寸重算」和「没 opt-in 时高度必须等于内容高」两条
##     是**向后兼容的底线**，只能靠断言守住。
##  3. `TreeTable._row_at()` 在加了滚动偏移之后，表头那一小段会被算成「点了某一行」——
##     这个 bug 不会报错、只会让点表头时莫名选中/展开某行，属于最难查的那类。

const HEADER_H := 30.0     # = ThemePalette.TABLE_HEADER_H
const ROW_H := 30.0        # = ThemePalette.TABLE_ROW_H

var _fails := 0


func _initialize() -> void:
	# 主题要显式建一次：`--script` 跑的是自己的 SceneTree，autoload 那套不一定在。
	root.theme = ThemeFactory.build()

	await _check_scrollbar_theme()
	await _check_table_scroll_api()
	await _check_button_follows_scroll()
	await _check_tree_row_hit()
	await _check_opt_out_restores()
	_check_log_view()

	print("[check] %s" % ("PASS" if _fails == 0 else "FAIL（%d 项）" % _fails))
	quit(_fails)


# ---------------------------------------------------------------- 主题

func _check_scrollbar_theme() -> void:
	var bar := VScrollBar.new()
	root.add_child(bar)
	await process_frame

	var w := bar.get_combined_minimum_size().x
	# 这一条就是当年那个 0px 缺陷的钉子：0 宽 = 抓不住、看不见
	_ge(w, 1.0, "VScrollBar 有实际宽度（%.1fpx；0 就是那个「滚动条消失」的缺陷）" % w)
	_ge(w, ThemePalette.SCROLLBAR_W - 0.01,
			"VScrollBar 宽度不低于 SCROLLBAR_W 令牌（样式盒 content_margin 没被改回 0）")
	# 横向同理：HScrollBar 走的是同一套样式盒
	var hbar := HScrollBar.new()
	root.add_child(hbar)
	await process_frame
	_ge(hbar.get_combined_minimum_size().y, ThemePalette.SCROLLBAR_W - 0.01,
			"HScrollBar 高度不低于 SCROLLBAR_W（两个方向共用同一条令牌）")
	bar.free()
	hbar.free()


# ---------------------------------------------------------------- 表格滚动

func _check_table_scroll_api() -> void:
	var table := _make_table(20)
	var full := HEADER_H + ROW_H * 20.0

	# 没 opt-in：与加滚动之前完全一致
	_eq(table.get_combined_minimum_size().y, full, 0.01,
			"没 opt-in 时高度 = 表头 + 20 行（向后兼容的底线）")
	_ok(not table.is_scrollable(), "没 opt-in 时不出滚动条")
	_ok(not table.clip_contents, "没 opt-in 时不裁剪（保持从前的绘制行为）")

	# opt-in
	table.set_max_visible_rows(10)
	await process_frame
	_eq(table.get_combined_minimum_size().y, HEADER_H + ROW_H * 10.0, 0.01,
			"set_max_visible_rows(10) 后高度 = 表头 + 10 行")
	_ok(table.is_scrollable(), "内容超出上限 → 滚动生效")
	_ok(table.get_scroll_bar().visible, "滚动条可见")
	_ok(table.clip_contents, "滚动生效时开启裁剪（挡住溢出表体的内容）")
	_eq(table.get_scroll_bar().position.y, HEADER_H, 0.01, "滚动条从表头下沿开始（表头不被它盖住）")

	# 高度上限：总高直接受限
	var table2 := _make_table(20)
	table2.set_max_height(210.0)
	await process_frame
	_eq(table2.get_combined_minimum_size().y, 210.0, 0.01, "set_max_height() 直接限制总高")
	table2.free()

	# 内容装得下就不出滚动条
	var table3 := _make_table(2)
	table3.set_max_visible_rows(10)
	await process_frame
	_eq(table3.get_combined_minimum_size().y, HEADER_H + ROW_H * 2.0, 0.01,
			"内容没超出上限时不加高、也不出滚动条")
	_ok(not table3.is_scrollable(), "没超出上限 → is_scrollable() 为 false")
	table3.free()

	# **滚动绝不能触发最小尺寸重算**（否则容器每滚一格就重排一次）
	var before := table.get_combined_minimum_size().y
	table.set_scroll(ROW_H * 3.0)
	await process_frame
	_eq(table.get_combined_minimum_size().y, before, 0.01, "滚动不改变最小尺寸（不触发容器重排）")
	_eq(table.get_scroll(), ROW_H * 3.0, 0.01, "set_scroll() 生效")

	# 末列要给滚动条让出宽度，否则文字压在滚动条底下
	var w_scroll := table._col_w(2)
	table.set_max_visible_rows(0)
	await process_frame
	var w_plain := table._col_w(2)
	_eq(w_plain - w_scroll, table._bar_w, 0.01,
			"滚动生效时末列宽度让出滚动条的位置（让出 %.1fpx）" % table._bar_w)
	table.free()


func _check_button_follows_scroll() -> void:
	var table := _make_table(20)
	table.set_max_visible_rows(10)
	await process_frame
	for i in 20:
		table.set_row_actions(i, 2, [{"text": "开始", "action": "start"}])
	await process_frame

	# 第 5 行在滚动前后都落在表体里，所以它的按钮位置可以直接比较
	var box := table.get_action_button(5, 0).get_parent() as Control
	var y0 := box.global_position.y
	table.set_scroll(ROW_H * 2.0)
	await process_frame
	_eq(y0 - box.global_position.y, ROW_H * 2.0, 0.5, "滚动后行内按钮跟着上移（位移 = 滚动量）")

	# 滚出表体的行：按钮要藏起来（不藏的话它会画到表头上面去）
	table.set_scroll(0.0)
	await process_frame
	var first := table.get_action_button(0, 0).get_parent() as Control
	_ok(first.visible, "滚回顶部后第一行的按钮可见")
	table.set_scroll(ROW_H * 5.0)
	await process_frame
	_ok(not first.visible, "滚出表体带的行，按钮被藏起来（否则会压到表头上）")
	_ok(table.get_action_button(0, 0) != null, "只是藏起来，没有被回收（滚回来还要用）")
	table.set_scroll(0.0)
	await process_frame
	_ok(first.visible, "滚回来后按钮恢复可见")
	table.free()


func _check_tree_row_hit() -> void:
	var tree := TreeTable.new()
	tree.set_columns(PackedStringArray(["名称", "操作"]), PackedFloat32Array([260.0, 200.0]))
	tree.set_min_width(460.0)
	root.add_child(tree)
	for i in 12:
		tree.create_item().set_cells(PackedStringArray(["节点 %d" % (i + 1), ""]))
	await process_frame

	tree.set_max_visible_rows(5)
	await process_frame
	_ok(tree.is_scrollable(), "树表 12 行 / 上限 5 行 → 滚动生效")

	tree.set_scroll(ROW_H * 2.0)
	await process_frame
	_eq(float(tree._row_at(Vector2(10.0, HEADER_H + 5.0))), 2.0, 1e-4,
			"滚动后命中的是第 2 行（第 0/1 行已滚出视野）")
	_ok(tree._row_at(Vector2(10.0, HEADER_H - 2.0)) == -1,
			"表头带不算「点到了某一行」（加滚动偏移后最容易踩的一条）")
	_ok(tree._row_at(Vector2(10.0, 2.0)) == -1, "表头正中间也不算行")

	tree.set_scroll(0.0)
	await process_frame
	_eq(float(tree._row_at(Vector2(10.0, HEADER_H + 5.0))), 0.0, 1e-4, "滚回顶部后命中的是第 0 行")
	tree.free()


func _check_opt_out_restores() -> void:
	var table := _make_table(20)
	table.set_max_visible_rows(8)
	await process_frame
	_ok(table.is_scrollable(), "先开滚动")
	table.set_scroll(ROW_H * 3.0)
	await process_frame
	table.set_max_visible_rows(0)
	await process_frame
	_ok(not table.is_scrollable(), "取消上限后滚动失效")
	_eq(table.get_scroll(), 0.0, 0.01, "取消上限后偏移归零")
	_ok(not table.get_scroll_bar().visible, "取消上限后滚动条隐藏")
	_eq(table.get_combined_minimum_size().y, HEADER_H + ROW_H * 20.0, 0.01,
			"取消上限后高度回到内容高（整条路可逆）")
	table.free()


# ---------------------------------------------------------------- LogView

func _check_log_view() -> void:
	var log := LogView.new()
	root.add_child(log)

	log.append("第一条")
	log.append("第二条", "warn")
	log.append("带方括号的 [D:/data/run[3]] 不该被当成 BBCode")
	_eq(float(log.line_count()), 3.0, 1e-4, "append() 后行数正确")
	_ok(log.get_lines()[2] == "带方括号的 [D:/data/run[3]] 不该被当成 BBCode",
			"方括号原样保留（转义过了）")

	log.clear()
	_eq(float(log.line_count()), 0.0, 1e-4, "clear() 后行数归零")

	# 上限裁剪：max_lines 比 TRIM_CHUNK 小的时候曾经会把日志一次清空
	log.max_lines = 100
	for i in 500:
		log.append("批量 %d" % i)
	var n := log.line_count()
	_ok(n <= 100, "超过 max_lines 后行数被裁到上限内（现在 %d）" % n)
	_ok(n > 0, "裁剪不会把日志一次清空（max_lines < TRIM_CHUNK 的边界）")
	_ok(log.get_lines()[n - 1] == "批量 499", "裁掉的是最旧的，最后一行仍是最新那条")
	log.free()


# ---------------------------------------------------------------- 工具

func _make_table(rows: int) -> DataTable:
	var table := DataTable.new()
	table.set_columns(PackedStringArray(["名称", "数值", "操作"]),
			PackedFloat32Array([120.0, 100.0, 200.0]))
	table.set_min_width(420.0)
	root.add_child(table)
	var data: Array = []
	for i in rows:
		data.append(["行 %d" % (i + 1), "%d" % i, ""])
	table.set_rows(data)
	return table


func _eq(got: float, want: float, tol: float, what: String) -> void:
	if absf(got - want) <= tol:
		print("  [ok]   %s" % what)
	else:
		_fails += 1
		print("  [FAIL] %s：期望 %s，实际 %s" % [what, want, got])


func _ge(got: float, want: float, what: String) -> void:
	if got >= want - 1e-6:
		print("  [ok]   %s" % what)
	else:
		_fails += 1
		print("  [FAIL] %s：期望 >= %s，实际 %s" % [what, want, got])


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  [ok]   %s" % what)
	else:
		_fails += 1
		print("  [FAIL] %s" % what)
