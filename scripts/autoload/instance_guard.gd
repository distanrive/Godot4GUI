extends Node
## 单实例守卫（Autoload，**默认关闭**）。
##
## 模板的默认取向是**允许同时开多个前端** —— 后端每个连接一个独立 Session，
## 多前端互不干扰（见 backend_launcher.gd 与 backend/main.py 的说明）。
## 但工控台上「不小心点两下图标，开出两个一模一样的窗口」是很常见的诉求，
## 想禁掉就打开这个开关：
##
##   命令行：`--single-instance`
##   或者 project.godot 里：`[app] single_instance=true`（跟项目走，不用每次敲参数）
##
## 打开之后：第二次启动**不会**新开窗口，而是把已有那个窗口叫到最前面，然后自己退出。
##
## 实现：用一个本地 TCP 端口当锁（`LOCK_PORT`）。
##   * `TCPServer.listen()` 成功 = 我是第一个，端口就是我的锁，进程活着锁就在；
##   * 失败 = 已经有人在监听，连接过去发一个 token 请它把窗口叫到前面。
##   * **拿不到锁不等于能退出**：那个端口也可能是别的程序占着的。要收到对方的应答
##     （才是我们自己的实例）才退出，否则只提醒一句、照常运行。
##
## 踩过的坑（docs/godot-facts-verified.md §3）：`StreamPeerTCP` **必须先 `poll()`**，
## `get_status()` / `get_available_bytes()` 才会更新；不 poll 会永远停在 `STATUS_CONNECTING`，
## 单实例锁会整个失效（上游第一版就是这么坏的）。4.7 里 `poll()` 在父类 `StreamPeerSocket` 上。

const LOCK_PORT := 8766              # 后端是 8765，这里用 8766 当锁
const TOKEN := "godot4gui.show"      # 「把已有窗口叫到前面」
const REPLY := "godot4gui.here"      # 「我就是那个已有窗口」
const PROBE_TIMEOUT_SEC := 1.0       # 等应答的上限；超时就认为是别人占着端口
const PEER_TIMEOUT_SEC := 2.0        # 锁持有方等对方把 token 发过来的上限

var _enabled := false
var _server := TCPServer.new()
## 非 null 表示「我在探测已有实例」（拿不到锁的那一方）。
var _probe: StreamPeerTCP = null
var _probe_elapsed := 0.0
var _probe_sent := false
## 锁持有方这边：已接进来、还没读完 token 的连接（每个带一个超时）。
var _peers: Array = []


func _ready() -> void:
	_enabled = _parse_cli() or bool(ProjectSettings.get_setting("app/single_instance", false))
	if not _enabled:
		set_process(false)
		return
	if _server.listen(LOCK_PORT, "127.0.0.1") == OK:
		set_process(true)     # 抢到锁：我是唯一实例，留在这儿守着
		return
	# 抢不到：先问一句，确认是不是我们自己的另一个实例
	_probe = StreamPeerTCP.new()
	var err := _probe.connect_to_host("127.0.0.1", LOCK_PORT)
	if err != OK:
		_end_probe("无法连接锁端口 %d（err=%d），按多实例继续运行" % [LOCK_PORT, err])
		return
	set_process(true)


func _process(delta: float) -> void:
	if _probe != null:
		_process_probe(delta)
	else:
		_process_server(delta)


# ---------------------------------------------------------------- 探测方（第二个实例）

func _process_probe(delta: float) -> void:
	_probe_elapsed += delta
	# **必须 poll**：不 poll 的话状态永远停在 CONNECTING（见文件头）
	_probe.poll()
	match _probe.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			if not _probe_sent:
				_probe.put_data((TOKEN + "\n").to_utf8_buffer())
				_probe_sent = true
			if _probe.get_available_bytes() > 0:
				var reply := _probe.get_utf8_string(_probe.get_available_bytes())
				if reply.contains(REPLY):
					_handover()
					return
		StreamPeerTCP.STATUS_ERROR:
			_end_probe("锁端口 %d 上没有我们自己的实例（连接被拒），按多实例继续运行" % LOCK_PORT)
			return
	if _probe_elapsed > PROBE_TIMEOUT_SEC:
		_end_probe("锁端口 %d 被别的程序占着（没等到应答），按多实例继续运行" % LOCK_PORT)


## 确认已有实例在跑：请它把窗口叫到前面，然后自己退出。
func _handover() -> void:
	print("[InstanceGuard] 已有实例在运行，请它把窗口叫到前面，本次启动退出。")
	_probe.disconnect_from_host()
	_end_probe("")
	# 等一帧再退：让上面那句日志和其它 autoload 的初始化走完
	await get_tree().process_frame
	get_tree().quit()


func _end_probe(message: String) -> void:
	if not message.is_empty():
		push_warning("[InstanceGuard] %s" % message)
	_probe = null
	set_process(false)


# ---------------------------------------------------------------- 锁持有方（第一个实例）

func _process_server(delta: float) -> void:
	# 收新连接
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_peers.append({"peer": peer, "elapsed": 0.0})
	# 读 token（同样要先 poll），并清理超时的
	var keep: Array = []
	for entry in _peers:
		var peer: StreamPeerTCP = entry["peer"]
		entry["elapsed"] += delta
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0:
			var text := peer.get_utf8_string(peer.get_available_bytes())
			if text.contains(TOKEN):
				_bring_to_front()
				peer.put_data((REPLY + "\n").to_utf8_buffer())
				peer.poll()
				peer.disconnect_from_host()
				continue
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED \
				and float(entry["elapsed"]) < PEER_TIMEOUT_SEC:
			keep.append(entry)
		else:
			peer.disconnect_from_host()
	_peers = keep


## 把已有窗口叫到最前面（用户看到的就是「双击图标 = 切回原来那个窗口」）。
func _bring_to_front() -> void:
	var win := get_window()
	if win.mode == Window.MODE_MINIMIZED:
		win.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()
	print("[InstanceGuard] 收到第二个实例的请求，已把窗口叫到前面。")


# ---------------------------------------------------------------- 工具

func _parse_cli() -> bool:
	return OS.get_cmdline_user_args().has("--single-instance")


func _exit_tree() -> void:
	if _probe != null:
		_probe.disconnect_from_host()
		_probe = null
	for entry in _peers:
		(entry["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.clear()
	if _server.is_listening():
		_server.stop()
