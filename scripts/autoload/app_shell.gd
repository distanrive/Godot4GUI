extends Node
## 应用外壳（Autoload）：窗口尺寸、系统 DPI 缩放、界面缩放记忆。
##
## 为什么需要它：模板的拉伸模式是 `disabled`（见 project.godot 的说明），
## 于是「界面在高 DPI 屏上太小」这件事必须由代码补上 —— Godot 官方对非游戏应用的
## 建议就是「disabled + 在 autoload 里把 stretch scale 设成屏幕缩放系数」。
##
## 做三件事：
##   1. **最小窗口尺寸**：拖太小会把参数栏和伪彩图挤坏，这里设 `Window.min_size`；
##   2. **界面缩放**：`content_scale_factor`。默认「跟随系统」，
##      用 `screen_get_scale()`；Windows 上它恒为 1.0（官方文档明确「仅在 Android/iOS/Web/
##      macOS/Linux Wayland 上实现」），所以回退到 `screen_get_dpi() / 96`。
##      界面里可用 `UiScaleOption` 手动选，或命令行 `--ui-scale=1.5` 覆盖。
##   3. **记忆**：窗口尺寸/是否最大化 + 缩放档位存 `user://config.cfg`，重启不丢。
##
## 这个 config 文件同时是**项目自己的参数持久化**的落点（见 docs/todo.md 的 C3）：
## 业务脚本用 `AppShell.get_config()` 拿同一个 ConfigFile 读写自己的段即可。
##
## 命令行（放在 `--` 之后）：`--ui-scale=1.5`、`--reset-window`。

signal ui_scale_changed(scale: float)

const CONFIG_PATH := "user://config.cfg"
const _SEC_UI := "ui"
const _SEC_WINDOW := "window"

## ConfigFile 实例本身就是对外接口（业务可复用它存参数），所以不藏起来。
var config := ConfigFile.new()

var _scale_setting := ThemePalette.UI_SCALE_FOLLOW_SYSTEM   # 0 = 跟随系统
var _scale_from_cli := false     # 命令行给的缩放是临时覆盖，不写回配置文件
var _restore_window := true
var _save_countdown := -1.0      # >0 表示有待落盘的改动（防抖）


func _ready() -> void:
	var cli := _parse_cli()
	config.load(CONFIG_PATH)     # 首次运行没有这个文件，返回非 OK，忽略即可

	var source := "跟随系统"
	if cli.has("ui_scale"):
		_scale_setting = cli["ui_scale"]
		_scale_from_cli = true
		source = "命令行 --ui-scale"
	elif config.has_section_key(_SEC_UI, "scale"):
		_scale_setting = float(config.get_value(_SEC_UI, "scale"))
		source = CONFIG_PATH
	if cli.has("reset_window"):
		_restore_window = false

	_apply_scale()
	var restored := false
	if _restore_window:
		restored = _restore_window_geometry()
	if not restored:
		_apply_default_window_size(_effective_scale())

	var win := get_window()
	win.size_changed.connect(_on_window_changed)
	win.close_requested.connect(_flush_now)
	set_process(true)
	# 打一行出来：「界面怎么这么大/这么小」在工控机上是最常被问的问题，
	# 有这行就能立刻区分是系统 DPI、配置文件还是命令行参数导致的。
	print("[AppShell] 界面缩放 %.2f×（来源：%s），窗口 %d×%d（逻辑 %d×%d，%s），最小 %s" % [
		_effective_scale(), source, win.size.x, win.size.y,
		int(win.size.x / _effective_scale()), int(win.size.y / _effective_scale()),
		"沿用上次" if restored else "首次运行，用默认尺寸",
		str(win.min_size)])


func _process(delta: float) -> void:
	if _save_countdown < 0.0:
		return
	_save_countdown -= delta
	if _save_countdown <= 0.0:
		_flush_now()


# ---------------------------------------------------------------- 对外接口

## 当前生效的缩放系数（已把「跟随系统」解析成具体数值）。
func get_effective_scale() -> float:
	return _effective_scale()


## 用户设定的档位：0 = 跟随系统，其余为具体倍数。
func get_ui_scale_setting() -> float:
	return _scale_setting


func is_following_system() -> bool:
	return _scale_setting <= ThemePalette.UI_SCALE_FOLLOW_SYSTEM


## 设置缩放档位（0 = 跟随系统）。会立即生效并记忆下来。
func set_ui_scale(scale: float) -> void:
	if scale > ThemePalette.UI_SCALE_FOLLOW_SYSTEM:
		scale = clampf(scale, ThemePalette.UI_SCALE_MIN, ThemePalette.UI_SCALE_MAX)
	if is_equal_approx(scale, _scale_setting):
		return
	_scale_setting = scale
	# 用户自己在界面里选过了，这次选择就是「要记住的」—— 覆盖掉命令行的临时性
	_scale_from_cli = false
	_apply_scale()
	_flush_now()


## 把自己写进 `config` 的内容落盘（业务脚本改了 `config` 之后调它一下）。
## 注意 `config` 里其它段（如 BackendLauncher 的 `[backend]`）会一起被保存，不会被覆盖掉。
func save_config() -> void:
	_flush_now()


## 设置窗口标题。**要改标题就用这个函数**，别直接写 `Window.title`，也别自己调 DisplayServer。
##
## 这里面的两步都是必需的（2026-09-22 在 Godot 4.7.2 / Windows 上实测过三种写法）：
##
## | 写法 | OS 上的标题实际变成 |
## |---|---|
## | `get_window().title = "X"` | `X (DEBUG)` —— 调试版下引擎会把后缀加回来 |
## | `DisplayServer.window_set_title("X")` 直接写在 `_ready()` 里 | `项目名 (DEBUG)` —— 被引擎的默认标题盖掉 |
## | 本函数（等一帧 + `DisplayServer`） | `X` ✅ |
##
## 「等一帧」不能省：引擎是在**窗口首帧显示时**才写那一次默认标题的，晚于 `_ready()`。
##
## 正式导出（Release）本来就没有 ` (DEBUG)` 后缀，所以这纯粹是开发期观感问题。
func set_window_title(text: String) -> void:
	await get_tree().process_frame
	DisplayServer.window_set_title(text)


## 系统/屏幕的缩放系数。
##
## 顺序：`screen_get_scale()` 优先（macOS/Wayland/移动端上是准的），
## 它没实现时（Windows 恒返回 1.0）回退到 DPI 猜测 —— 96 dpi = 100%，144 dpi = 150%。
## Godot 编辑器自己的做法也是「按分辨率/DPI 猜 + 让用户能改」，所以这里也留了手动档位。
func detect_system_scale() -> float:
	var s := DisplayServer.screen_get_scale()
	if s > 1.001:
		return clampf(s, ThemePalette.UI_SCALE_MIN, ThemePalette.UI_SCALE_MAX)
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return 1.0           # 该平台不支持查询，只能按 100% 处理
	return clampf(float(dpi) / 96.0, ThemePalette.UI_SCALE_MIN, ThemePalette.UI_SCALE_MAX)


# ---------------------------------------------------------------- 内部

func _effective_scale() -> float:
	if _scale_setting <= ThemePalette.UI_SCALE_FOLLOW_SYSTEM:
		return detect_system_scale()
	return clampf(_scale_setting, ThemePalette.UI_SCALE_MIN, ThemePalette.UI_SCALE_MAX)


func _apply_scale() -> void:
	var factor := _effective_scale()
	# 拉伸模式是 disabled：界面仍按原生像素绘制（清晰），只是整体放大 factor 倍。
	get_tree().root.content_scale_factor = factor
	_update_min_size(factor)
	ui_scale_changed.emit(factor)


func _update_min_size(factor: float) -> void:
	var win := get_window()
	if win == null:
		return
	# Window.min_size 是**物理像素**，所以要跟着缩放乘一遍，
	# 否则 150% 缩放下界面会被压进一个太小的窗口里。
	win.min_size = Vector2i(
			int(round(ThemePalette.WINDOW_MIN_W * factor)),
			int(round(ThemePalette.WINDOW_MIN_H * factor)))


## 从配置恢复窗口几何。**返回是否真的恢复过** —— 没恢复（首次运行）时调用方要补一个默认尺寸。
func _restore_window_geometry() -> bool:
	var win := get_window()
	if win == null:
		return false
	if bool(config.get_value(_SEC_WINDOW, "maximized", false)):
		win.mode = Window.MODE_MAXIMIZED
		return true
	var w := int(config.get_value(_SEC_WINDOW, "width", 0))
	var h := int(config.get_value(_SEC_WINDOW, "height", 0))
	if w > 0 and h > 0:
		win.size = Vector2i(maxi(w, win.min_size.x), maxi(h, win.min_size.y))
		return true
	return false


## 首次运行时定窗口尺寸。
##
## 为什么不能靠 `project.godot` 的 viewport 值：那个是**物理**像素、**不乘缩放系数**。
## 于是 125% 缩放下「1280×800」变成逻辑 1024×640 —— 正好等于 `WINDOW_MIN_*`，
## 窗口每次都以最小尺寸打开，看起来就是「这软件怎么一启动就这么小」。
## （实测：scale=1.25 时窗口物理 1280×800、逻辑 1024×640，就是这个原因。）
##
## 这里按**逻辑**设计尺寸（`WINDOW_DEFAULT_*`）× 缩放 换成物理，再钳进可用屏幕区域，
## 免得在小屏（或 200% 缩放）上开出一个装不下的窗口。
func _apply_default_window_size(factor: float) -> void:
	var win := get_window()
	if win == null:
		return
	var wanted := Vector2(ThemePalette.WINDOW_DEFAULT_W, ThemePalette.WINDOW_DEFAULT_H) * factor
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x > 0 and usable.size.y > 0:
		wanted.x = minf(wanted.x, float(usable.size.x))
		wanted.y = minf(wanted.y, float(usable.size.y))
	win.size = Vector2i(
			maxi(int(wanted.x), win.min_size.x),
			maxi(int(wanted.y), win.min_size.y))


func _on_window_changed() -> void:
	# 拖窗口会连续触发几十次 size_changed，防抖一下再落盘
	_save_countdown = 0.8


func _flush_now() -> void:
	_save_countdown = -1.0
	var win := get_window()
	if win == null:
		return
	# 命令行来的缩放是**临时覆盖**，不写回文件 —— 否则一次 `--ui-scale=1.5` 的试跑
	# 会在用户随后拖动窗口时被顺手记成永久设置，下次启动莫名其妙就是 1.5×。
	if not _scale_from_cli:
		config.set_value(_SEC_UI, "scale", _scale_setting)
	config.set_value(_SEC_WINDOW, "maximized", win.mode == Window.MODE_MAXIMIZED)
	if win.mode == Window.MODE_WINDOWED:
		config.set_value(_SEC_WINDOW, "width", win.size.x)
		config.set_value(_SEC_WINDOW, "height", win.size.y)
	var err := config.save(CONFIG_PATH)
	if err != OK:
		push_warning("[AppShell] 无法写入 %s（err=%d）" % [CONFIG_PATH, err])


func _notification(what: int) -> void:
	# Alt+F4 / 点关闭按钮时也要把窗口状态存下来
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_now()


func _parse_cli() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			out["ui_scale"] = arg.substr("--ui-scale=".length()).to_float()
		elif arg == "--reset-window":
			out["reset_window"] = true
	return out
