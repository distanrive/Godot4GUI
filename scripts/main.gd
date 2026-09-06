extends Control
## 主场景：极简可用的工控界面。
## 只保留「看得到效果」的控件：
##   启动采集 / 停止 —— 真正控制后端数据流（图表开始/停止滚动）
##   Y 轴上限滑条 —— 调整图表纵轴范围
## 已移除之前的摆设控件：使能复选框、采样点数数字框、急停长按按钮。

var chart: TrendChart
var status_label: Label
var log_label: Label
var y_slider: HSlider
var y_label: Label


func _ready() -> void:
	_build_ui()
	NetClient.connected.connect(_on_connected)
	NetClient.disconnected.connect(_on_disconnected)
	NetClient.data_received.connect(_on_data)
	NetClient.connect_to()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "Lab Control GUI — Godot 前端"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# 连接状态
	status_label = Label.new()
	status_label.text = "未连接"
	status_label.modulate = ThemePalette.DANGER
	vbox.add_child(status_label)

	# 控制行：启动 / 停止 / Y 轴范围
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	vbox.add_child(controls)

	var start_btn := Button.new()
	start_btn.text = "启动采集"
	start_btn.theme_type_variation = "AccentButton"
	start_btn.pressed.connect(func(): NetClient.send_command("start"))
	controls.add_child(start_btn)

	var stop_btn := Button.new()
	stop_btn.text = "停止"
	stop_btn.pressed.connect(func(): NetClient.send_command("stop"))
	controls.add_child(stop_btn)

	y_label = Label.new()
	y_label.text = "Y 轴上限：100"
	controls.add_child(y_label)

	y_slider = HSlider.new()
	y_slider.min_value = 1.0
	y_slider.max_value = 200.0
	y_slider.value = 100.0
	y_slider.custom_minimum_size = Vector2(160, 0)
	y_slider.value_changed.connect(_on_y_scale_changed)
	controls.add_child(y_slider)

	# 实时图表（占据剩余空间）
	chart = TrendChart.new()
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.y_min = 0.0
	chart.y_max = 100.0
	vbox.add_child(chart)

	# 日志（事件反馈）
	log_label = Label.new()
	log_label.text = "日志：就绪"
	log_label.add_theme_font_size_override("font_size", 13)
	log_label.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(log_label)


func _log(msg: String) -> void:
	log_label.text = "日志：" + msg
	print("[main] " + msg)


func _on_y_scale_changed(v: float) -> void:
	y_label.text = "Y 轴上限：%d" % int(v)
	if chart:
		chart.y_max = v
		chart.queue_redraw()


func _on_connected() -> void:
	status_label.text = "已连接"
	status_label.modulate = ThemePalette.SUCCESS
	NetClient.send_json({"type": "hello"})
	_log("已连接后端")


func _on_disconnected() -> void:
	status_label.text = "未连接"
	status_label.modulate = ThemePalette.DANGER
	_log("连接断开")


func _on_data(payload: Variant) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		return
	match payload.get("type", ""):
		"sample":
			chart.add_point(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)))
		"ack":
			var cmd := str(payload.get("cmd", ""))
			if cmd == "start":
				_log("已启动采集")
			elif cmd in ["stop", "estop"]:
				_log("已停止采集")
			else:
				_log("命令已确认（%s）" % cmd)
