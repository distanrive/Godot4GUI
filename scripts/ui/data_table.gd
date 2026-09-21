class_name DataTable
extends ColumnTable
## 可拖拽调列宽的数据表（Godot 的 Tree 不支持拖拽调列宽，这里用 _draw 自绘实现）。
##
## 用法：
##   var t := DataTable.new()
##   t.set_columns(["参数", "数值", "单位"], [180.0, 120.0, 90.0])
##   t.set_rows([["设备", "—", "—"], ["通道 1", "10.0", "V"]])
##
## 拖动表头相邻列之间的分隔线即可调整列宽（最小 40px）；最后一列自动填满剩余宽度。
## 列宽机制在基类 `ColumnTable` 里（`TreeTable` 复用同一套）；本类只负责把二维数组画出来。
##
## 高度由内容自动上报（见基类 `ColumnTable._get_minimum_size()`），调用方不必再手算
## 「表头 + 行数 × 行高」；要改宽度用 `set_min_width()`（或设 `custom_minimum_size.x`）。
##
## 颜色从主题类型 "DataTable" 读取（回退到 ThemePalette 令牌），尺寸走 ThemePalette 令牌，
## 因此随全局主题统一调整，也支持 per-control 主题覆盖。

var _rows: Array = []    # 每行是 Array（String 或可 str() 的值）


func set_rows(rows: Array) -> void:
	_rows = rows
	_on_columns_changed()
	queue_redraw()


func get_rows() -> Array:
	return _rows


## 内容需要的高度：表头 + 每行 TABLE_ROW_H。
func get_required_height() -> float:
	return ThemePalette.TABLE_HEADER_H + ThemePalette.TABLE_ROW_H * _rows.size()


func _theme_type() -> StringName:
	return &"DataTable"


func _draw() -> void:
	if _titles.is_empty():
		return
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()

	var header_h := ThemePalette.TABLE_HEADER_H
	var row_h := ThemePalette.TABLE_ROW_H
	var pad := ThemePalette.TABLE_PAD
	var cell_bg := _theme_color(&"cell_bg_color", ThemePalette.SURFACE)
	var header_bg := _theme_color(&"header_bg_color", ThemePalette.SURFACE_ALT)
	var grid := _theme_color(&"grid_color", ThemePalette.BORDER)
	var text := _theme_color(&"text_color", ThemePalette.TEXT)
	var header_text := _theme_color(&"header_text_color", ThemePalette.TEXT)

	# 表体底色
	draw_rect(Rect2(0, header_h, size.x, size.y - header_h), cell_bg, true)
	# 表头底色
	draw_rect(Rect2(0, 0, size.x, header_h), header_bg, true)

	# 列分隔线（贯穿整表）+ 表头文字
	for i in range(_titles.size()):
		var w := _col_w(i)
		var sx := _sep_x(i)
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), grid, 1.0)
		draw_string(font, Vector2(sx - w + pad, header_h / 2.0 + fs * 0.35), _titles[i],
				HORIZONTAL_ALIGNMENT_LEFT, w - pad * 2.0, fs, header_text)

	# 表体行
	var y := header_h
	for r in _rows.size():
		draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)
		var row: Array = _rows[r]
		var cx := 0.0
		for c in _titles.size():
			var cell := str(row[c]) if c < row.size() else ""
			draw_string(font, Vector2(cx + pad, y + row_h / 2.0 + fs * 0.35), cell,
					HORIZONTAL_ALIGNMENT_LEFT, _col_w(c) - pad * 2.0, fs, text)
			cx += _col_w(c)
		y += row_h

	# 底边线
	draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)
