extends Node
## WebSocket 客户端单例（Autoload），负责与 Python 后端通信。
##
## 协议（JSON 文本帧，见 CLAUDE.md）：
##   后端 -> 前端：{"type": "sample"|"progress"|"ack", ...}
##   前端 -> 后端：{"type": "hello"} 或 {"type": "command", "id", "cmd", "args"}
##
## 业务脚本不要自己 new WebSocketPeer，只连接本单例的信号即可。

signal connected                       # 已连接
signal disconnected                    # 已断开
signal data_received(payload: Variant) # 收到一条解析后的 JSON 消息

@export var url: String = "ws://127.0.0.1:8765"
@export var auto_reconnect: bool = true
@export var reconnect_delay: float = 2.0

var _socket := WebSocketPeer.new()
var _reconnect_timer := 0.0
var _was_connected := false
var _msg_id := 0


var _wants_connection := false


func _ready() -> void:
	pass  # 不自动连接；由业务脚本调用 connect_to()（gallery 无需网络）


## 开始连接（并启用自动重连）。应用场景在 _ready 里调用一次即可。
func connect_to() -> void:
	_wants_connection = true
	_connect()


func _process(delta: float) -> void:
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
	_socket.close()
