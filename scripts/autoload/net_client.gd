extends Node
## WebSocket 客户端单例（Autoload），负责与 Python 后端通信。
##
## 协议（JSON 文本帧，见 CLAUDE.md）：
##   后端 -> 前端：{"type": "sample"|"progress"|"ack", ...}
##   前端 -> 后端：{"type": "hello"} 或 {"type": "command", "id", "cmd", "args"}
##
## 业务脚本不要自己 new WebSocketPeer，只连接本单例的信号即可。
##
## 注意 `disconnected` 的语义：它只在**曾经连上过**之后断线时才发。
## 「后端从头到尾没起来」这种情况不会触发它（`_was_connected` 一直是 false）——
## 需要感知这种情况请用 `connecting`（BackendLauncher 就是靠它在宽限期后拉起后端）。

signal connecting                      # 业务层表达了「我要连」的意图（connect_to() 时发一次）
signal connected                       # 已连接
signal disconnected                    # 曾经的连接断开了
signal data_received(payload: Variant) # 收到一条解析后的 JSON 消息

@export var url: String = "ws://127.0.0.1:8765"
@export var auto_reconnect: bool = true
@export var reconnect_delay: float = 2.0

var _socket := WebSocketPeer.new()
var _reconnect_timer := 0.0
var _was_connected := false
var _msg_id := 0
var _shutting_down := false


var _wants_connection := false


func _ready() -> void:
	pass  # 不自动连接；由业务脚本调用 connect_to()（gallery 无需网络）


## 开始连接（并启用自动重连）。应用场景在 _ready 里调用一次即可。
func connect_to() -> void:
	_wants_connection = true
	# 已经连着/正在连时再 connect_to_url() 只会报错，直接忽略（业务里重复调用是常见的）
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CONNECTING:
		return
	_connect()
	connecting.emit()


## 当前是否连着（业务层发命令前判断用）。
func is_open() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


## 业务层是否表达过「我要连接」。BackendLauncher 据此决定要不要拉起后端 ——
## gallery 这类不联网的场景从不调用 connect_to()，也就不会被拉起后端。
func wants_connection() -> bool:
	return _wants_connection


## 进入「静默退出」：不再 poll、不再广播 connected/disconnected。
##
## 收尾时**必须先调它、再关后端进程**。否则顺序会变成：后端进程一死，TCP 断开，
## 下一次 `poll()` 把这次**主动收尾**读成「后端崩了」—— 于是弹一句「与后端断开连接」
## 的告警，还要去重连一次。用户每次正常关窗都看到这句，就会去追一个不存在的故障。
func begin_shutdown() -> void:
	_shutting_down = true


func _process(delta: float) -> void:
	if _shutting_down:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_connected:
				_was_connected = true
				connected.emit()
			_drain_packets()
		WebSocketPeer.STATE_CLOSED:
			if _was_connected:
				_was_connected = false
				disconnected.emit()
			if _wants_connection and auto_reconnect:
				_reconnect_timer -= delta
				if _reconnect_timer <= 0.0:
					_connect()


func _connect() -> void:
	var err := _socket.connect_to_url(url)
	if err != OK:
		push_warning("[NetClient] 无法连接 %s（err=%d），%.1fs 后重试" % [url, err, reconnect_delay])
		_reconnect_timer = reconnect_delay
	else:
		print("[NetClient] 正在连接 %s" % url)


func _drain_packets() -> void:
	while _socket.get_available_packet_count() > 0:
		var text := _socket.get_packet().get_string_from_utf8()
		var payload = JSON.parse_string(text)
		if payload == null:
			push_warning("[NetClient] 收到非 JSON 消息：%s" % text)
			continue
		data_received.emit(payload)


## 发送原始文本帧。
func send_text(text: String) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("[NetClient] 未连接，丢弃消息")
		return
	_socket.send_text(text)


## 发送任意 JSON 序列化的数据。
func send_json(data: Variant) -> void:
	send_text(JSON.stringify(data))


## 发送一条命令，返回递增的 msg_id（对应后端的 ack.id）。
func send_command(cmd: String, args: Dictionary = {}) -> int:
	_msg_id += 1
	send_json({"type": "command", "id": _msg_id, "cmd": cmd, "args": args})
	return _msg_id


func _exit_tree() -> void:
	# 先立旗子再 close()：否则这一帧的 poll() 会把「我自己关的」读成「后端断了」，
	# 业务层弹一句「与后端断开连接」，BackendLauncher 还会据此再拉起一个后端进程 ——
	# 而此刻程序正在退出，那个新进程就没人收了。
	_shutting_down = true
	_socket.close()
