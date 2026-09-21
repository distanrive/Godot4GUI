extends Node
## 后端进程启动器（Autoload）：连不上后端时自动把它拉起来。
##
## 为什么需要它：模板原本要用户先开一个终端跑 `python backend/main.py`，
## 再回 Godot 按 F5。工控机上这是双份操作、还容易忘。现在前端自己管这件事。
##
## **刻意不做 PATH 自动发现**：工控机上装好几个 Python 是常态，
## 悄悄挑中一个缺 numpy/scipy 的解释器，只会让后端静默起不来、还查不出原因。
## 所以 Python 解释器与后端脚本路径必须**显式配置**，来源按优先级：
##   1. 命令行 `--python=<绝对路径>` / `--backend-script=<路径>`（自测用）
##   2. `user://config.cfg` 的 `[backend]` 段（用 `configure()` 写，不动仓库）
##   3. `project.godot` 的 `[backend]` 段（跟项目走，见 project.godot 里的说明）
## 三处都没有 → **不启动**，只报「后端未配置」。
##
## 拉起前会先在后台线程里验一遍依赖（`python -c "import websockets, numpy, scipy"`）：
## 依赖缺了就直接把 Python 的报错原文摆给用户看，而不是让后端悄悄死掉。
##
## 进程归属：只对自己 `create_process` 起来的进程负责 —— 端口上已经有别的后端时
## 只连不管（不越权去杀别人的进程），自己起的则在退出时按 `backend/kill_on_exit` 收掉
## （`OS.create_process` 起的进程**不会**随 Godot 退出而结束，不收就是孤儿进程）。
##
## 命令行（放在 `--` 之后）：`--no-backend-autostart`。

signal status_changed(text: String, level: String)
signal launch_failed(reason: String)

enum State { IDLE, GRACE, PROBING, WAITING, RUNNING, FAILED }

const GRACE_SEC := 2.0            # 先等一会儿：也许后端只是启动慢，不必急着再拉一个
const LAUNCH_TIMEOUT_SEC := 25.0  # 拉起来之后等它监听端口的上限（import numpy/scipy 要几秒）
const MAX_ATTEMPTS := 2           # 自动重试上限，避免后端反复崩时变成拉起风暴
const LOG_TAIL_LINES := 12

var _enabled := true
var _state: State = State.IDLE
var _timer := 0.0
var _attempts := 0

var _python := ""
var _script := ""
var _kill_on_exit := true
var _host := "127.0.0.1"
var _port := 8765
var _log_path := ""

var _owned_pid := 0
var _verified := false            # 是否收到过 hello_ack（确认端口上确实是我们这个后端）
var _status := "未连接后端"
var _level := "idle"
var _shutting_down := false

var _probe_thread: Thread = null
var _probe_exit := 0
var _probe_output := ""


func _ready() -> void:
	var cli := _parse_cli()
	if cli.has("disabled"):
		_enabled = false
		_set_status("未连接后端（自动启动已关闭）", "idle")
		return
	if cli.has("python"):
		_python = cli["python"]
	if cli.has("script"):
		_script = cli["script"]

	NetClient.connecting.connect(_on_connecting)
	NetClient.connected.connect(_on_connected)
	NetClient.disconnected.connect(_on_disconnected)
	NetClient.data_received.connect(_on_data)
	set_process(true)


func _process(delta: float) -> void:
	match _state:
		State.GRACE:
			_timer -= delta
			if _timer <= 0.0:
				_begin_launch()
		State.PROBING:
			if _probe_thread != null and not _probe_thread.is_alive():
				_probe_thread.wait_to_finish()
				_probe_thread = null
				_on_probe_finished()
		State.WAITING:
			if NetClient.is_open():
				_set_running()
			else:
				_timer -= delta
				if _timer <= 0.0:
					_fail("等了 %d 秒仍未连上" % int(LAUNCH_TIMEOUT_SEC))
		_:
			set_process(false)


# ---------------------------------------------------------------- 对外接口

func status_text() -> String:
	return _status


## "idle" | "ok" | "warn" | "error" —— 对应主题里的 StatusIdle / StatusOk / StatusWarn / StatusError
func status_level() -> String:
	return _level


func is_configured() -> bool:
	_resolve_config()
	return not _python.is_empty() and not _script.is_empty()


## 实际会用的解释器路径（界面上显示给用户看）。
func python_path() -> String:
	_resolve_config()
	return _python


## 实际会用的后端脚本路径（已把 res:// 解析成绝对路径）。
func script_path() -> String:
	_resolve_config()
	return _script


## 本次会话是否由我们拉起了后端（是的话退出时会收掉）。
func owned_pid() -> int:
	return _owned_pid


## 请求确保后端在跑。`force=true` 时忽略重试上限（用户手动点「启动后端」用）。
func ensure_running(force := false) -> void:
	if not _enabled or _shutting_down:
		return
	if force:
		_attempts = 0
	if NetClient.is_open():
		_set_running()
		return
	if _state == State.GRACE or _state == State.PROBING or _state == State.WAITING:
		return
	_set_status("正在连接后端…", "idle")
	_state = State.GRACE
	_timer = GRACE_SEC
	set_process(true)


## 记下后端配置（写 `user://config.cfg`，不动仓库）。传空串表示清掉这一项。
func configure(python: String, script: String) -> void:
	AppShell.config.set_value("backend", "python", python)
	AppShell.config.set_value("backend", "script", script)
	AppShell.save_config()
	_python = ""
	_script = ""
	_attempts = 0
	_set_status("后端配置已保存", "idle")


## 收掉自己拉起的后端进程（端口随之释放）。
func stop_owned() -> void:
	if _owned_pid == 0:
		return
	if OS.is_process_running(_owned_pid):
		OS.kill(_owned_pid)
	_owned_pid = 0
	_set_status("已停止后端进程", "idle")


# ---------------------------------------------------------------- NetClient 事件

func _on_connecting() -> void:
	if _state == State.IDLE:
		ensure_running()


func _on_connected() -> void:
	if _state != State.RUNNING:
		_set_running()


func _on_disconnected() -> void:
	# 原本连着的后端断了（被关掉/崩了）：再走一遍拉起流程；`_attempts` 会拦住拉起风暴。
	#
	# **不要在这里清 `_owned_pid`**：连接断了不等于我们拉起的那个进程没了。
	# 清了它就等于放弃所有权 —— 退出时 `_exit_tree` 见 pid 为 0 就不去收，
	# 那个进程会一直占着端口变成孤儿。判断进程死没死交给 `OS.is_process_running()`。
	ensure_running()


func _on_data(payload: Variant) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		return
	if str(payload.get("type", "")) == "hello_ack":
		_verified = true
		_refresh_running_status()


# ---------------------------------------------------------------- 启动流程

func _begin_launch() -> void:
	if NetClient.is_open():
		_set_running()
		return
	# 已经拉起过、进程还活着：只是还没监听上，继续等，别再起一个
	if _owned_pid != 0 and OS.is_process_running(_owned_pid):
		_state = State.WAITING
		_timer = LAUNCH_TIMEOUT_SEC
		set_process(true)
		return
	if _attempts >= MAX_ATTEMPTS:
		_fail("已尝试 %d 次仍失败，不再自动重试（可手动点「启动后端」）" % _attempts)
		return

	_resolve_config()
	if _python.is_empty() or _script.is_empty():
		_fail("后端未配置：请填 project.godot 的 [backend] 段（python / script），"
				+ "或由业务代码调 BackendLauncher.configure(python, script) 写进 user://config.cfg")
		return
	if not FileAccess.file_exists(_python):
		_fail("找不到 Python 解释器：%s" % _python)
		return
	if not FileAccess.file_exists(_script):
		_fail("找不到后端脚本：%s" % _script)
		return

	# 验依赖：这一趟要启动 Python 并 import numpy/scipy（1~2 秒），
	# 必须离开主线程，否则窗口在这期间会「无响应」。
	_set_status("正在检查 Python 环境（%s）…" % _python.get_file(), "idle")
	_state = State.PROBING
	_probe_thread = Thread.new()
	_probe_thread.start(_probe_worker.bind(_python))


## 在后台线程里跑（只写两个成员变量，主线程 join 之后再读）。
func _probe_worker(python: String) -> void:
	var output: Array = []
	_probe_exit = OS.execute(python, ["-c", "import websockets, numpy, scipy"], output, true)
	_probe_output = "\n".join(output)


func _on_probe_finished() -> void:
	if _probe_exit != 0:
		_fail("Python 环境不可用（%s）：%s" % [_python, _probe_output.strip_edges()])
		return
	_spawn()


func _spawn() -> void:
	_attempts += 1
	_ensure_log_dir()
	var args := PackedStringArray([
		_script, "--host", _host, "--port", str(_port), "--log-file", _log_path])
	var pid := OS.create_process(_python, args)
	if pid <= 0:
		_fail("无法创建进程：%s（err=%d）" % [_python, pid])
		return
	_owned_pid = pid
	_state = State.WAITING
	_timer = LAUNCH_TIMEOUT_SEC
	_set_status("已拉起后端（pid=%d），等待就绪…" % pid, "idle")
	set_process(true)


func _set_running() -> void:
	_state = State.RUNNING
	_attempts = 0
	set_process(false)
	_refresh_running_status()


func _refresh_running_status() -> void:
	var who := "外部已在运行" if _owned_pid == 0 else "本次自动拉起，pid=%d" % _owned_pid
	if _verified:
		who += "，已确认是 Godot4GUI 后端"
	elif _owned_pid != 0:
		who += "，尚未收到 hello_ack"
	_set_status("已连接后端（%s）" % who, "ok")


func _fail(reason: String) -> void:
	_state = State.FAILED
	set_process(false)
	var detail := reason + _log_tail()
	_set_status("后端启动失败：%s" % reason, "error")
	push_warning("[BackendLauncher] %s" % detail)
	launch_failed.emit(detail)


# ---------------------------------------------------------------- 配置与工具

## 按 CLI > user://config.cfg > project.godot 的顺序解析出解释器与脚本路径。
func _resolve_config() -> void:
	if _python.is_empty():
		_python = str(AppShell.config.get_value("backend", "python", ""))
	if _python.is_empty():
		_python = str(ProjectSettings.get_setting("backend/python", ""))

	if _script.is_empty():
		_script = str(AppShell.config.get_value("backend", "script", ""))
	if _script.is_empty():
		_script = str(ProjectSettings.get_setting("backend/script", ""))

	_script = _resolve_script_path(_script)
	_kill_on_exit = bool(ProjectSettings.get_setting("backend/kill_on_exit", true))
	_parse_endpoint()
	_log_path = ProjectSettings.globalize_path("user://logs/backend.log")


## `res://backend/main.py` → 绝对路径；导出后 res:// 是只读包、里面没有 .py，
## 这时退回到「可执行文件旁边的 backend/ 目录」（部署时把 backend/ 一起拷过去）。
func _resolve_script_path(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://"):
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			return abs_path
		var beside_exe := OS.get_executable_path().get_base_dir().path_join(
				path.trim_prefix("res://"))
		if FileAccess.file_exists(beside_exe):
			return beside_exe
		return abs_path
	return path


## 从 NetClient.url 解析主机与端口 —— 保持「连接地址只有一处真相」。
func _parse_endpoint() -> void:
	var url := NetClient.url
	var rest := url.substr(url.find("://") + 3) if url.contains("://") else url
	rest = rest.split("/")[0]
	var parts := rest.split(":")
	_host = parts[0] if parts.size() > 0 and not parts[0].is_empty() else "127.0.0.1"
	_port = int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 8765


func _ensure_log_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_log_path.get_base_dir())


## 后端日志的尾部若干行。后端是脱离进程，崩了前端拿不到任何 stdout，
## 所以它把 print 同时写进 --log-file，失败时这里读回来给用户看。
func _log_tail() -> String:
	if _log_path.is_empty() or not FileAccess.file_exists(_log_path):
		return ""
	var lines := FileAccess.get_file_as_string(_log_path).strip_edges().split("\n")
	if lines.size() == 1 and lines[0].is_empty():
		return ""
	var from := maxi(lines.size() - LOG_TAIL_LINES, 0)
	return "\n  后端日志尾部（%s）：\n    %s" % [_log_path, "\n    ".join(lines.slice(from))]


func _set_status(text: String, level: String) -> void:
	_status = text
	_level = level
	status_changed.emit(text, level)


func _parse_cli() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-backend-autostart":
			out["disabled"] = true
		elif arg.begins_with("--python="):
			out["python"] = arg.substr("--python=".length())
		elif arg.begins_with("--backend-script="):
			out["script"] = arg.substr("--backend-script=".length())
	return out


func _exit_tree() -> void:
	_shutting_down = true
	if _probe_thread != null and _probe_thread.is_started():
		_probe_thread.wait_to_finish()
	# 先让 NetClient 闭嘴，再收后端进程。反过来的话，后端进程一死 TCP 就断，
	# NetClient 的 poll() 会把这次主动收尾读成「后端崩了」，弹告警还要重连。
	# autoload 的 _exit_tree 顺序不保证（谁先谁后取决于引擎），所以不能靠「我比它后跑」。
	NetClient.begin_shutdown()
	# 自己拉起的进程要自己收：create_process 起的进程不会随 Godot 退出而结束。
	# `is_process_running()` 这一问不能省 —— pid 可能早已失效，而 `OS.kill()` 拿到
	# 一个被系统回收复用的 pid 会杀掉不相干的进程。
	if _kill_on_exit and _owned_pid != 0 and OS.is_process_running(_owned_pid):
		OS.kill(_owned_pid)
