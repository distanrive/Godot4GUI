class_name LogView
extends PanelContainer
## 滚动日志视图 —— 工控界面里「一直在刷新的那一栏日志」。
##
## 为什么要有它：模板里原来没有日志控件，业务侧常见写法是一个 `Label` 反复 `text = msg`，
## 于是**只能看见最后一条**；出问题时想往回翻，前面全没了。
## 下游 DeepScribe 为此自己拼了一套（`RichTextLabel` + 面板 + 行数上限 + 清空），
## 这里把它收进模板并补上主题与 API。
##
## 用法：
##   var log := LogView.new()
##   log.custom_minimum_size = Vector2(0, 160)
##   add_child(log)
##   log.append("设备已连接", "ok")
##   log.append("温度读数 41.8 ℃ 超限", "warn", "通道 2")   # 第三参是来源标签
##   log.clear()
##
## 几个刻意的设计：
##   * **日志文本会自动转义 BBCode**（`[` → `[lb]`），所以把任意数据丢进来都不会
##     被当成标记解析；要自己写富文本请用 `get_rich_text().append_text()`。
##   * **行数有上限**（`max_lines`），超出后成块裁掉最旧的再重建，避免长时间运行把内存吃满。
##   * **自动跟随是「贴底才跟」**：用户往上翻看历史时，新来的日志不会把他拽回底部。
##   * 文本可选中复制（`selection_enabled`），排查问题时很需要。
##
## 颜色来自主题类型 `LogView`（`info_color` / `ok_color` / `warn_color` / `error_color` /
## `system_color` / `time_color` / `source_color`），未定义时回退到 ThemePalette 令牌。

## 行数上限（超出后按 TRIM_CHUNK 成块裁剪）。
@export var max_lines := 2000:
	set(v):
		max_lines = maxi(v, 16)
		_trim()

## 是否在每行前面加 `HH:MM:SS` 时间戳。
@export var show_timestamp := true

## 是否自动滚到最新一行（用户往上翻时自动暂停跟随，回到底部后恢复）。
@export var follow := true

## 一次裁掉多少行 —— 每加一行就重建整段 BBCode 会很卡，所以攒够一批再重建。
const TRIM_CHUNK := 500

var _log: RichTextLabel
## 每条 `[时间戳, level, source, 纯文本]`；裁剪时靠它重建，`get_lines()` 也用它。
var _entries: Array = []


func _init() -> void:
	# 子节点在 `_init()` 里建：保证 `new()` 之后（还没进场景树）就能 append ——
	# 数据可能是入树前就填好的，等到 `_ready()` 建子节点就晚了。
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.scroll_following = follow
	_log.selection_enabled = true      # 排查时要把日志选中复制出来
	_log.focus_mode = Control.FOCUS_CLICK
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_log)


# ---------------------------------------------------------------- 对外接口

## 追加一行。`level` 取 `info` / `ok` / `warn` / `error` / `system`（未知值按 `info` 处理）；
## `source` 是可选来源标签（设备名 / 通道名 / 文件名），会加粗显示在最前面。
func append(text: String, level := "info", source := "") -> void:
	if _log == null:
		return
	var at_bottom := _is_at_bottom()
	var stamp := Time.get_time_string_from_system() if show_timestamp else ""
	_entries.append([stamp, level, source, text])
	_emit_line(stamp, level, source, text)
	_trim()
	# 「贴底才跟随」：用户正在往回翻历史时不要把他拽到底部。
	# 这里改的是**下一次**追加时引擎的行为，所以放在 append_text 之后设也生效。
	_log.scroll_following = follow and at_bottom


## 清空全部日志。
func clear() -> void:
	_entries.clear()
	if _log != null:
		_log.clear()


## 当前保留的行数。
func line_count() -> int:
	return _entries.size()


## 全部日志行的纯文本（不含 BBCode 标记）。
func get_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _entries:
		out.append(str(entry[3]))
	return out


## 全部日志拼成一段文本 —— 直接写文件/贴给人看用。
func get_text() -> String:
	return "\n".join(get_lines())


## 把当前日志写进文件（排查时让用户把文件发过来，比截屏靠谱）。
func save_to_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(get_text() + "\n")
	f.close()
	return OK


## 底层的 RichTextLabel —— 要自己追加富文本时用它（注意绕过了这里的转义与裁剪）。
func get_rich_text() -> RichTextLabel:
	return _log


# ---------------------------------------------------------------- 内部

## 追加一行到 RichTextLabel（BBCode 形式）。
func _emit_line(stamp: String, level: String, source: String, text: String) -> void:
	var parts := PackedStringArray()
	if not stamp.is_empty():
		parts.append("[color=#%s]%s[/color]" % [_color_html(&"time_color", ThemePalette.TEXT_DIS), stamp])
	if not source.is_empty():
		parts.append("[color=#%s][b]%s[/b][/color]"
				% [_color_html(&"source_color", ThemePalette.ACCENT), _escape(source)])
	parts.append("[color=#%s]%s[/color]" % [_level_color_html(level), _escape(text)])
	_log.append_text(" ".join(parts) + "\n")


## 超出上限时成块裁掉最旧的，并重建整段内容。
func _trim() -> void:
	if _entries.size() <= max_lines or _log == null:
		return
	# 一次裁到「max_lines - TRIM_CHUNK」左右，这样接下来 TRIM_CHUNK 次追加都不用重建。
	# 钳进 [max_lines/2, max_lines] 是为了兼容「max_lines 比 TRIM_CHUNK 还小」的配置 ——
	# 直接写 max_lines - TRIM_CHUNK 会在那种情况下算出负数，把日志一次清空（踩过）。
	var keep := clampi(max_lines - TRIM_CHUNK, maxi(max_lines / 2, 1), max_lines)
	_entries = _entries.slice(maxi(_entries.size() - keep, 0))
	_rebuild()


func _rebuild() -> void:
	_log.clear()
	for entry in _entries:
		_emit_line(str(entry[0]), str(entry[1]), str(entry[2]), str(entry[3]))


## 当前是否停在最底部（判断「该不该继续跟随」用）。
func _is_at_bottom() -> bool:
	if _log == null:
		return true
	var bar := _log.get_v_scroll_bar()
	return bar.value + bar.page >= bar.max_value - 1.0


func _level_color_html(level: String) -> String:
	var name := StringName(level + "_color")
	if has_theme_color(name, &"LogView"):
		return get_theme_color(name, &"LogView").to_html(false)
	match level:
		"ok":
			return ThemePalette.SUCCESS.to_html(false)
		"warn":
			return ThemePalette.WARNING.to_html(false)
		"error":
			return ThemePalette.DANGER.to_html(false)
		"system":
			return ThemePalette.ACCENT.to_html(false)
		_:
			return ThemePalette.TEXT_SEC.to_html(false)


func _color_html(name: StringName, fallback: Color) -> String:
	var c: Color = get_theme_color(name, &"LogView") if has_theme_color(name, &"LogView") else fallback
	return c.to_html(false)


## BBCode 转义：日志里出现 `[` 的概率不低（路径、数组、单位），
## 不转义的话 RichTextLabel 会把它当标记解析，整行显示就乱了。
func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
