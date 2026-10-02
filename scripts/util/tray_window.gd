class_name TrayWindow
extends RefCounted
## 「关窗后从任务栏上消失、只留托盘图标」—— **Godot 自己做不到**，这个类包住那份原生扩展。
##
## 为什么非要原生代码（三条都是引擎源码里的事实，不是猜的）：
##   1. `Window::set_visible()` 对**没有父节点**的窗口直接
##      `ERR_FAIL_NULL_MSG(get_parent(), "Can't change visibility of main window.")`
##      —— 主窗口就是 `get_tree().root`，没有父节点，所以 `hide()` 必然失败；
##   2. `DisplayServer` 没有任何 hide 类接口，最接近的只有 `window_set_mode(MINIMIZED)`；
##   3. Windows 后端给主窗口**恒定**加 `WS_EX_APPWINDOW`（= 必须出现在任务栏）。
## 于是只能拿 `DisplayServer.window_get_native_handle()` 的 HWND 绕过引擎调 `ShowWindow`。
## 完整的证据链与踩坑见 `tools/native_window/native_window.c` 顶部的长注释。
##
## 用法（一般是配合 `StatusIndicator` 托盘图标）：
## [codeblock]
## if TrayWindow.available():
##     TrayWindow.hide()        # 关窗时藏起来
## ...
## TrayWindow.restore()         # 点托盘图标时叫回来
## [/codeblock]
##
## 三件容易忘的事：
##   * **隐藏期间会把 `Engine.max_fps` 压到 10**（`_HIDDEN_MAX_FPS`）：Godot 并不知道窗口没了，
##     照常按 60fps 渲染，一个待在托盘里待机一整天的程序没必要一直烤 GPU。
##     恢复时自动还原。计时器 / 协程 / 网络轮询走的是真实时间，不受影响。
##   * **`available()` 可能返回 false**（没编出那个 dll、或不在 Windows 上）。
##     调用点必须判返回值并**退回「最小化到任务栏」**，别假设一定能藏 ——
##     否则用户点关闭会以为程序退出了，其实它只是看不见。
##   * 全程走 `ClassDB.class_call_static()` 的**动态**调用，不在脚本里直接写类名：
##     那样 .dll 一缺失就是**整个脚本编译不过**，连降级的机会都没有。

## 藏起来之后把帧率压到多少。不压到 1 是因为托盘菜单也是 Godot 画的，
## 1fps 下右键托盘图标要等一秒才弹出来。
const _HIDDEN_MAX_FPS := 10

## 窗口当前是不是被我们藏起来的（`restore()` 据此决定要不要动）。
static var _hidden := false

## 藏起来之前的帧率上限，恢复时要还回去。
static var _max_fps_before := 0


## 这份扩展在当前平台上能不能用（类注册了、dll 也加载了）。
##
## 每次查询都要过一次 `ClassDB`，但这只发生在「关窗 / 点托盘」这种一次性动作上，
## 不存在性能问题；换来的是**缺 dll 时功能优雅降级**而不是脚本编译失败。
static func available() -> bool:
	return ClassDB.class_exists(&"NativeWindow") \
			and bool(ClassDB.class_call_static(&"NativeWindow", &"is_supported"))


## 把主窗口从任务栏和 Alt+Tab 上藏起来。**返回 false 表示没藏成**，调用方要退回最小化。
static func hide() -> bool:
	if _hidden or not available():
		return false
	var hwnd := _handle()
	if hwnd == 0:
		return false
	ClassDB.class_call_static(&"NativeWindow", &"hide_window", hwnd)
	_hidden = true
	_max_fps_before = Engine.max_fps
	Engine.max_fps = _HIDDEN_MAX_FPS
	return true


## 把窗口叫回来（并置于最前，免得它出现在别的窗口底下、用户以为没反应）。
## 没藏着的时候返回 false。
static func restore() -> bool:
	if not _hidden:
		return false
	var hwnd := _handle()
	if hwnd == 0:
		return false
	ClassDB.class_call_static(&"NativeWindow", &"show_window", hwnd)
	_hidden = false
	# **先还原帧率再返回**：让紧接着那一帧就按正常帧率画出来，
	# 否则用户点完托盘图标会先看到一下卡顿感。
	Engine.max_fps = _max_fps_before
	return true


static func is_hidden() -> bool:
	return _hidden


static func _handle() -> int:
	return DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
