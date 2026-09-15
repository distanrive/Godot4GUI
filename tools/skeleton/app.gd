extends Control
## 起始页面：**你的业务界面从这里写起**。
##
## 这一版是「最小能跑通」的骨架，已经接好了整条链路：
##     连接后端 → 发 start/stop 命令 → 收 sample 采样点画折线 → 状态与日志
## 直接 F5（配合 `python backend/main.py`）就能看到曲线滚动，
## 说明「Godot 前端 ⇄ Python 后端」是通的，接下来把示例替换成你的业务即可。
##
## 写界面时记住两条（详见 CLAUDE.md）：
##   1) 样式只走主题：字号/颜色用 theme_type_variation，别 add_theme_*_override；
##   2) 网络只走 NetClient 单例：连它的 connected / disconnected / data_received 信号。

var chart: TrendChart
var status_label: Label
var log_label: Label
var start_button: Button
var stop_button: Button


func _ready() -> void:
	_build_ui()
	NetClient.connected.connect(_on_connected)
	NetClient.disconnected.connect(_on_disconnected)
	NetClient.data_received.connect(_on_data)
	NetClient.connect_to()
	_update_buttons(false)


# ---------------------------------------------------------------- 界面

func _build_ui() -> void:
	# 页面边距由主题里 MarginContainer 的默认值给出：
	# 改 scripts/theme/theme_palette.gd 的 PAGE_MARGIN 一处，全局统一生效。
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_sidebar())

	chart = TrendChart.new()
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.custom_minimum_size = Vector2(0, ThemePalette.PANEL_MIN_H)
	chart.y_min = 0.0
	chart.y_max = 100.0
	body.add_child(chart)

	log_label = Label.new()
	log_label.text = "就绪。点「启动采集」看曲线滚动。"
	log_label.theme_type_variation = "LogLabel"
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(log_label)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "{{PROJECT_TITLE}}"
	title.theme_type_variation = "PageTitle"
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	start_button = _button("启动采集", "AccentButton", func(): NetClient.send_command("start"))
	stop_button = _button("停止", "", func(): NetClient.send_command("stop"))
	header.add_child(start_button)
	header.add_child(stop_button)

	status_label = Label.new()
	status_label.text = "未连接后端"
	status_label.theme_type_variation = "StatusIdle"
	header.add_child(status_label)
	return header


## 左侧参数栏：换成你项目的输入控件即可
## （LabeledLineEdit / SpinBox / OptionButton / Switch / FileDropBox …，都在 scripts/ui/）。
func _build_sidebar() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(ThemePalette.SIDEBAR_W, 0)

	var group := TitledGroup.new()
	group.title = "示例参数"
	side.add_child(group)

	var channel := LabeledLineEdit.new()
	channel.label_text = "通道名"
	channel.text = "CH1"
	group.content.add_child(channel)

	var note := Label.new()
	note.text = "控件用法见 scenes/gallery.tscn（左边导航按分类看一遍就够了）。"
	note.theme_type_variation = "Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group.content.add_child(note)
	return side


func _button(text: String, variation: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = variation
	b.pressed.connect(handler)
	return b


# ---------------------------------------------------------------- 网络

func _on_connected() -> void:
	status_label.text = "已连接"
	status_label.theme_type_variation = "StatusOk"
	NetClient.send_json({"type": "hello"})
	_log("已连接后端。")


func _on_disconnected() -> void:
	status_label.text = "未连接"
	status_label.theme_type_variation = "StatusError"
	_update_buttons(false)
	_log("与后端断开（后端没启动？先跑 python backend/main.py）。")


func _on_data(payload: Variant) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		return
	# 后端消息一律用 type 字段分发（协议见 CLAUDE.md）
	match str(payload.get("type", "")):
		"sample":
			chart.add_point(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)))
		"progress":
			_log("进度 %d%%" % int(payload.get("value", 0.0)))
		"ack":
			var cmd := str(payload.get("cmd", ""))
			_update_buttons(cmd == "start")
			_log("后端已确认：%s" % cmd)


func _update_buttons(running: bool) -> void:
	if start_button == null:
		return
	start_button.disabled = running
	stop_button.disabled = not running


func _log(msg: String) -> void:
	log_label.text = msg
	print("[app] " + msg)
