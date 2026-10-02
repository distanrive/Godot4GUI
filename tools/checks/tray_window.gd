extends SceneTree
## 原生窗口扩展（把主窗口从任务栏上真的藏起来）的回归检查。
##
##   godot --path . --script res://tools/checks/tray_window.gd
##   期望：输出 [check] PASS，退出码 0
##
## **必须用窗口模式跑**（别加 `--headless`）：headless 下没有窗口系统，
## `window_get_native_handle()` 返回 0，整项会被跳过 —— 那样还不如不跑。
##
## 为什么值得钉住：这份扩展干的事**在 Godot 里没有替代品**
## （主窗口的 `hide()` 必然失败、它恒定带 `WS_EX_APPWINDOW`），
## 而「.dll 缺失 / ABI 对不上」的表现是**静默降级成最小化** —— 不报错，只是功能没了。
## 所以这里必须真的隐藏一次、再断言窗口系统确认它确实不可见了。
##
## 用**临时窗口**验，**不动主窗口**：否则跑个自检把用户的窗口藏起来、还没有托盘图标能叫回来。

var _fails := 0


func _initialize() -> void:
	if not ClassDB.class_exists(&"NativeWindow"):
		_report("NativeWindow 类已注册", false,
				"没注册 —— bin/native_window.windows.x86_64.dll 编了吗？"
				+ "跑 bash tools/build_native_window.sh，再 --import 一次")
		_finish()
		return

	var names := PackedStringArray()
	for m in ClassDB.class_get_method_list(&"NativeWindow", true):
		names.append(str(m["name"]))
	var missing := PackedStringArray()
	for want in ["hide_window", "show_window", "is_supported", "is_window_visible"]:
		if not names.has(want):
			missing.append(want)
	_report("扩展的方法齐全", missing.is_empty(), str(names))
	_report("TrayWindow 封装认得它", TrayWindow.available())
	if _fails > 0:
		_finish()
		return

	if DisplayServer.get_name() == "headless":
		_report("隐藏 / 显示（headless 下没有窗口系统，跳过）", true)
		_finish()
		return

	var probe := Window.new()
	probe.title = "tray_window check"
	probe.size = Vector2i(240, 160)
	root.add_child(probe)
	await process_frame
	await process_frame

	var hwnd := DisplayServer.window_get_native_handle(
			DisplayServer.WINDOW_HANDLE, probe.get_window_id())
	if hwnd == 0:
		_report("取得到窗口句柄", false, "window_get_native_handle 返回 0")
		probe.queue_free()
		_finish()
		return

	var was_visible := bool(ClassDB.class_call_static(&"NativeWindow", &"is_window_visible", hwnd))
	ClassDB.class_call_static(&"NativeWindow", &"hide_window", hwnd)
	await process_frame
	var now_visible := bool(ClassDB.class_call_static(&"NativeWindow", &"is_window_visible", hwnd))
	ClassDB.class_call_static(&"NativeWindow", &"show_window", hwnd)
	await process_frame
	var back_visible := bool(ClassDB.class_call_static(&"NativeWindow", &"is_window_visible", hwnd))

	_report("hide_window 真的把窗口藏起来了（IsWindowVisible 变假）",
			was_visible and not now_visible,
			"调用前 %s，调用后 %s" % [was_visible, now_visible])
	_report("show_window 能把它叫回来", back_visible, "恢复后 %s" % back_visible)

	probe.queue_free()
	await process_frame
	_finish()


func _report(what: String, ok: bool, detail := "") -> void:
	var suffix := "" if detail.is_empty() else "  —— %s" % detail
	if ok:
		print("  [ok]   %s%s" % [what, suffix])
	else:
		_fails += 1
		print("  [FAIL] %s%s" % [what, suffix])


func _finish() -> void:
	print("[check] %s" % ("PASS" if _fails == 0 else "FAIL（%d 项）" % _fails))
	quit(_fails)
