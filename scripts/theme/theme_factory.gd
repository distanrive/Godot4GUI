class_name ThemeFactory
extends RefCounted
## 由 ThemePalette 设计令牌构建完整 Theme。
##
## 主题在运行时由 ThemeManager autoload 调用 `build()` 后应用到根窗口，
## 因此这里与 ThemePalette 是唯二的样式来源，业务脚本不要 per-control 打补丁。

const _TRANSPARENT := Color(0, 0, 0, 0)


## 构建全局主题（样式统一，颜色/字号/圆角全部来自 ThemePalette）。
static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = ThemePalette.FONT_MD
	_colors(t)
	_styleboxes(t)
	_icons(t)
	_constants(t)
	_custom_types(t)
	_type_variations(t)
	return t


# ---------- 颜色 ----------

static func _colors(t: Theme) -> void:
	_set_text_colors(t, "Label", ThemePalette.TEXT)
	_set_text_colors(t, "RichTextLabel", ThemePalette.TEXT)

	# 按钮系（Button / CheckBox / OptionButton 等继承 Button）
	t.set_color("font_color", "Button", ThemePalette.TEXT)
	t.set_color("font_hover_color", "Button", ThemePalette.TEXT)
	t.set_color("font_pressed_color", "Button", ThemePalette.TEXT)
	t.set_color("font_focus_color", "Button", ThemePalette.TEXT)
	t.set_color("font_hover_pressed_color", "Button", ThemePalette.TEXT)
	t.set_color("font_disabled_color", "Button", ThemePalette.TEXT_DIS)

	t.set_color("font_color", "CheckBox", ThemePalette.TEXT)
	t.set_color("font_hover_color", "CheckBox", ThemePalette.TEXT)
	t.set_color("font_pressed_color", "CheckBox", ThemePalette.TEXT)
	t.set_color("font_focus_color", "CheckBox", ThemePalette.TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", ThemePalette.TEXT)
	t.set_color("font_disabled_color", "CheckBox", ThemePalette.TEXT_DIS)

	t.set_color("font_color", "OptionButton", ThemePalette.TEXT)
	t.set_color("font_hover_color", "OptionButton", ThemePalette.TEXT)
	t.set_color("font_pressed_color", "OptionButton", ThemePalette.TEXT)
	t.set_color("font_focus_color", "OptionButton", ThemePalette.TEXT)
	t.set_color("font_hover_pressed_color", "OptionButton", ThemePalette.TEXT)
	t.set_color("font_disabled_color", "OptionButton", ThemePalette.TEXT_DIS)

	# 输入框
	t.set_color("font_color", "LineEdit", ThemePalette.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", ThemePalette.TEXT_SEC)
	t.set_color("font_selected_color", "LineEdit", ThemePalette.TEXT_ON_ACCENT)
	t.set_color("caret_color", "LineEdit", ThemePalette.ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ThemePalette.ACCENT, 0.35))

	t.set_color("font_color", "SpinBox", ThemePalette.TEXT)

	# 进度条（百分比文字）
	t.set_color("font_color", "ProgressBar", ThemePalette.TEXT)

	# 弹出菜单
	t.set_color("font_color", "PopupMenu", ThemePalette.TEXT)
	t.set_color("font_hover_color", "PopupMenu", ThemePalette.TEXT)
	t.set_color("font_disabled_color", "PopupMenu", ThemePalette.TEXT_DIS)
	t.set_color("font_accelerator_color", "PopupMenu", ThemePalette.TEXT_SEC)

	# 表格与列表（选中态文字保持深色，背景用浅色）
	t.set_color("font_color", "ItemList", ThemePalette.TEXT)
	t.set_color("font_hovered_color", "ItemList", ThemePalette.TEXT)
	t.set_color("font_selected_color", "ItemList", ThemePalette.TEXT)
	t.set_color("font_hovered_selected_color", "ItemList", ThemePalette.TEXT)
	t.set_color("guide_color", "ItemList", Color(ThemePalette.ACCENT, 0.25))

	t.set_color("font_color", "Tree", ThemePalette.TEXT)
	t.set_color("font_hovered_color", "Tree", ThemePalette.TEXT)
	t.set_color("font_selected_color", "Tree", ThemePalette.TEXT)
	t.set_color("font_hovered_selected_color", "Tree", ThemePalette.TEXT)
	t.set_color("title_button_color", "Tree", ThemePalette.TEXT)
	t.set_color("guide_color", "Tree", Color(ThemePalette.ACCENT, 0.25))
	t.set_color("relationship_line_color", "Tree", Color(ThemePalette.BORDER_STRONG, 0.8))

	# Tab 页
	for typ in ["TabBar", "TabContainer"]:
		t.set_color("font_color", typ, ThemePalette.TEXT)
		t.set_color("font_unselected_color", typ, ThemePalette.TEXT_SEC)
		t.set_color("font_hovered_color", typ, ThemePalette.TEXT)
		t.set_color("font_selected_color", typ, ThemePalette.TEXT)
		t.set_color("font_disabled_color", typ, ThemePalette.TEXT_DIS)

	# 工具提示
	t.set_color("font_color", "TooltipLabel", ThemePalette.TEXT)


# ---------- StyleBox ----------

static func _styleboxes(t: Theme) -> void:
	# 中性按钮
	var btn := _sb(ThemePalette.SURFACE, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var btn_hover := _sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER_STRONG, ThemePalette.RADIUS_SM, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var btn_pressed := _sb(ThemePalette.ACCENT_SOFT, ThemePalette.ACCENT, ThemePalette.RADIUS_SM, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var btn_hover_pressed := _sb(ThemePalette.ACCENT_SOFT_HOVER, ThemePalette.ACCENT, ThemePalette.RADIUS_SM, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var btn_disabled := _sb(ThemePalette.SURFACE, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var btn_focus := _outline(ThemePalette.ACCENT, ThemePalette.RADIUS_SM)

	_apply_button_styles(t, "Button", btn, btn_hover, btn_pressed, btn_disabled, btn_focus)
	t.set_stylebox("hover_pressed", "Button", btn_hover_pressed)

	# 输入框
	t.set_stylebox("normal", "LineEdit", _sb(ThemePalette.SURFACE, ThemePalette.BORDER,
			ThemePalette.RADIUS_SM, 1, ThemePalette.PAD_INPUT_H, ThemePalette.PAD_INPUT_V))
	t.set_stylebox("focus", "LineEdit", _sb(ThemePalette.SURFACE, ThemePalette.ACCENT,
			ThemePalette.RADIUS_SM, 1, ThemePalette.PAD_INPUT_H, ThemePalette.PAD_INPUT_V))

	# 数值框
	t.set_stylebox("normal", "SpinBox", _sb(ThemePalette.SURFACE, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1))
	t.set_stylebox("updown", "SpinBox", _sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1))

	# 进度条
	t.set_stylebox("background", "ProgressBar", _sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER,
			ThemePalette.RADIUS_SM, 1))
	t.set_stylebox("fill", "ProgressBar", _sb(ThemePalette.ACCENT, _TRANSPARENT, ThemePalette.RADIUS_SM, 0))

	# 面板 / 卡片
	t.set_stylebox("panel", "PanelContainer", _sb(ThemePalette.SURFACE, ThemePalette.BORDER,
			ThemePalette.RADIUS_MD, 1, ThemePalette.PAD_PANEL, ThemePalette.PAD_PANEL))
	# 滚动区域不画底，露出应用背景
	var scroll_panel := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", scroll_panel)
	t.set_stylebox("panel", "ItemList", _sb(ThemePalette.SURFACE, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1))
	t.set_stylebox("panel", "Tree", _sb(ThemePalette.SURFACE, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1))

	# 弹出菜单
	t.set_stylebox("panel", "PopupMenu", _sb(ThemePalette.SURFACE, ThemePalette.BORDER,
			ThemePalette.RADIUS_MD, 1, ThemePalette.PAD_POPUP, ThemePalette.PAD_POPUP))
	t.set_stylebox("hover", "PopupMenu", _sb(ThemePalette.ACCENT_SOFT, _TRANSPARENT,
			ThemePalette.RADIUS_SM, 0, ThemePalette.PAD_POPUP, 3.0))

	# 对话框
	var dialog := _sb(ThemePalette.SURFACE, ThemePalette.BORDER, ThemePalette.RADIUS_MD, 1,
			ThemePalette.PAD_PANEL, ThemePalette.PAD_PANEL)
	t.set_stylebox("panel", "AcceptDialog", dialog)
	t.set_stylebox("panel", "ConfirmationDialog", dialog)

	# 内嵌窗口（对话框 / FileDialog）的标题栏：默认是深灰，跟浅色主题不搭。
	# 换色时**必须保留默认的内容边距**（content_margin_top = 28 是标题栏高度、
	# expand_margin = 32 是投影留白）：边距给小了标题文字会被裁掉——
	# 这就是「覆盖 embedded_border 之后标题栏消失」的真正原因，不是不能覆盖。
	var embed := StyleBoxFlat.new()
	embed.bg_color = ThemePalette.SURFACE_ALT
	embed.border_color = ThemePalette.BORDER
	embed.set_border_width_all(1)
	embed.set_corner_radius_all(ThemePalette.RADIUS_MD)
	embed.expand_margin_left = 32.0
	embed.expand_margin_top = 32.0
	embed.expand_margin_right = 32.0
	embed.expand_margin_bottom = 32.0
	embed.content_margin_left = 10.0
	embed.content_margin_top = 28.0
	embed.content_margin_right = 10.0
	embed.content_margin_bottom = 8.0
	# 保留一点投影，否则对话框和浅色背景贴在一起分不出层次
	embed.shadow_color = Color(0.0, 0.0, 0.0, 0.16)
	embed.shadow_size = 10
	t.set_stylebox("embedded_border", "Window", embed)
	t.set_stylebox("embedded_unfocused_border", "Window", embed)
	t.set_color("title_color", "Window", ThemePalette.TEXT)
	t.set_color("title_outline_modulate", "Window", _TRANSPARENT)
	t.set_font_size("title_font_size", "Window", ThemePalette.FONT_MD)
	# 关闭按钮：引擎默认是「白色叉」，浅色标题栏上会看不见，必须换成深色图标
	t.set_icon("close", "Window", _icon("close.svg"))
	t.set_icon("close_pressed", "Window", _icon("close_pressed.svg"))

	# 列表 / 树选中背景
	var selected := _sb(ThemePalette.ACCENT_SOFT, _TRANSPARENT, ThemePalette.RADIUS_SM, 0)
	for typ in ["ItemList", "Tree"]:
		t.set_stylebox("selected", typ, selected)
		t.set_stylebox("selected_focus", typ, selected)
		t.set_stylebox("hovered_selected", typ, _sb(ThemePalette.ACCENT_SOFT_HOVER, _TRANSPARENT, ThemePalette.RADIUS_SM, 0))
		t.set_stylebox("hovered_selected_focus", typ, _sb(ThemePalette.ACCENT_SOFT_HOVER, _TRANSPARENT, ThemePalette.RADIUS_SM, 0))
	t.set_stylebox("focus", "Tree", _outline(ThemePalette.ACCENT, ThemePalette.RADIUS_SM))
	t.set_stylebox("focus", "ItemList", _outline(ThemePalette.ACCENT, ThemePalette.RADIUS_SM))

	# 树表头（列分隔线靠表头边框体现）
	t.set_stylebox("title_button_normal", "Tree", _sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER,
			ThemePalette.RADIUS_SM, 1, ThemePalette.PAD_INPUT_H, 4.0))
	t.set_stylebox("title_button_hover", "Tree", _sb(ThemePalette.ACCENT_SOFT, ThemePalette.BORDER,
			ThemePalette.RADIUS_SM, 1, ThemePalette.PAD_INPUT_H, 4.0))
	t.set_stylebox("title_button_pressed", "Tree", _sb(ThemePalette.ACCENT_SOFT_HOVER, ThemePalette.ACCENT,
			ThemePalette.RADIUS_SM, 1, ThemePalette.PAD_INPUT_H, 4.0))

	# 滚动条：轨道 + 滑块（ScrollBar 的 grabber 是 StyleBox，非图标）
	t.set_stylebox("scroll", "ScrollBar", _sb(ThemePalette.SURFACE_ALT, _TRANSPARENT, ThemePalette.RADIUS_SM, 0))
	t.set_stylebox("scroll_focus", "ScrollBar", _sb(ThemePalette.SURFACE_ALT, _TRANSPARENT, ThemePalette.RADIUS_SM, 0))
	t.set_stylebox("grabber", "ScrollBar", _sb(ThemePalette.BORDER_STRONG, _TRANSPARENT, ThemePalette.RADIUS_SM, 0))
	t.set_stylebox("grabber_highlight", "ScrollBar", _sb(Color(0.62, 0.66, 0.71), _TRANSPARENT, ThemePalette.RADIUS_SM, 0))
	t.set_stylebox("grabber_pressed", "ScrollBar", _sb(ThemePalette.ACCENT, _TRANSPARENT, ThemePalette.RADIUS_SM, 0))

	# 滑块：轨道（明显灰色，四周留白使杆变细）+ 可交互区
	t.set_stylebox("slider", "Slider", _sb(Color(0.64, 0.68, 0.73), _TRANSPARENT, ThemePalette.RADIUS_SM, 0, 6.0, 6.0))
	t.set_stylebox("grabber_area", "Slider", StyleBoxEmpty.new())
	t.set_stylebox("grabber_area_highlight", "Slider", StyleBoxEmpty.new())

	# 分割容器：常显分割条 + 可见分隔条背景
	t.set_stylebox("split_bar_background", "SplitContainer", _sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER, 0, 0))

	# Tab 页
	var tab_selected := _sb(ThemePalette.SURFACE, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1)
	var tab_unselected := _sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1)
	var tab_hovered := _sb(ThemePalette.ACCENT_SOFT, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1)
	for typ in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", typ, tab_selected)
		t.set_stylebox("tab_unselected", typ, tab_unselected)
		t.set_stylebox("tab_hovered", typ, tab_hovered)
		t.set_stylebox("tab_disabled", typ, _sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER, ThemePalette.RADIUS_SM, 1))
	t.set_stylebox("tab_focus", "TabBar", _outline(ThemePalette.ACCENT, ThemePalette.RADIUS_SM))
	t.set_stylebox("tab_focus", "TabContainer", _outline(ThemePalette.ACCENT, ThemePalette.RADIUS_SM))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# 工具提示
	t.set_stylebox("panel", "TooltipPanel", _sb(ThemePalette.SURFACE, ThemePalette.BORDER_STRONG,
			ThemePalette.RADIUS_SM, 1, ThemePalette.PAD_INPUT_H, ThemePalette.PAD_INPUT_V))

	# 分隔线
	t.set_stylebox("separator", "Separator", _sb(ThemePalette.BORDER, _TRANSPARENT, 0, 0))


# ---------- 图标 ----------

static func _icons(t: Theme) -> void:
	var check_on := _icon("check_checked.svg")
	var check_off := _icon("check_unchecked.svg")
	var radio_on := _icon("radio_checked.svg")
	var radio_off := _icon("radio_unchecked.svg")
	var arrow_down := _icon("arrow_down.svg")
	var arrow_up := _icon("arrow_up.svg")
	var arrow_right := _icon("arrow_right.svg")
	var grabber := _icon("grabber.svg")
	var splitter := _icon("splitter_grabber.svg")
	var dot := _icon("dot.svg")
	var empty := _icon("empty.svg")

	t.set_icon("checked", "CheckBox", check_on)
	t.set_icon("unchecked", "CheckBox", check_off)
	t.set_icon("radio_checked", "CheckBox", radio_on)
	t.set_icon("radio_unchecked", "CheckBox", radio_off)

	t.set_icon("arrow", "OptionButton", arrow_down)

	t.set_icon("up", "SpinBox", arrow_up)
	t.set_icon("down", "SpinBox", arrow_down)

	t.set_icon("grabber", "Slider", grabber)
	t.set_icon("grabber_highlight", "Slider", grabber)
	t.set_icon("grabber", "SplitContainer", splitter)

	t.set_icon("arrow", "Tree", arrow_down)
	t.set_icon("arrow_collapsed", "Tree", arrow_right)

	# 树状表格的展开箭头（自绘控件不认 Tree 的图标，得在自己的类型名下再注册一次）
	t.set_icon("arrow_expanded", "TreeTable", arrow_down)
	t.set_icon("arrow_collapsed", "TreeTable", arrow_right)

	# 弹出菜单：仅当前选项用圆点标记，其余不显示任何标记
	t.set_icon("checked", "PopupMenu", dot)
	t.set_icon("radio_checked", "PopupMenu", dot)
	t.set_icon("unchecked", "PopupMenu", empty)
	t.set_icon("radio_unchecked", "PopupMenu", empty)


# ---------- 常量 ----------

static func _constants(t: Theme) -> void:
	t.set_constant("separation", "BoxContainer", ThemePalette.SEP_BOX)
	t.set_constant("h_separation", "GridContainer", ThemePalette.SEP_GRID)
	t.set_constant("v_separation", "GridContainer", ThemePalette.SEP_GRID)
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		t.set_constant(m, "MarginContainer", ThemePalette.PAGE_MARGIN)
	t.set_constant("separation", "Separator", ThemePalette.SEP_SEPARATOR)

	# 图标与文字间距（CheckBox/Radio 继承 Button）
	t.set_constant("h_separation", "Button", 6)

	t.set_constant("h_separation", "ItemList", 6)
	t.set_constant("v_separation", "ItemList", 2)
	t.set_constant("icon_margin", "ItemList", 6)
	t.set_constant("line_separation", "ItemList", 2)

	t.set_constant("h_separation", "Tree", 6)
	t.set_constant("v_separation", "Tree", 2)
	t.set_constant("button_margin", "Tree", 4)

	t.set_constant("h_separation", "TabBar", 4)

	# 分割容器：不自动隐藏分割条
	t.set_constant("autohide", "SplitContainer", 0)


# ---------- 自定义控件类型 ----------

static func _custom_types(t: Theme) -> void:
	t.set_color("line_color", "TrendChart", ThemePalette.CHART_LINE)
	t.set_color("background_color", "TrendChart", ThemePalette.CHART_BG)
	t.set_color("grid_color", "TrendChart", ThemePalette.CHART_GRID)
	t.set_color("axis_color", "TrendChart", ThemePalette.CHART_AXIS)
	t.set_color("tick_text_color", "TrendChart", ThemePalette.CHART_TEXT)

	t.set_color("on_color", "Switch", ThemePalette.SUCCESS)
	t.set_color("off_color", "Switch", ThemePalette.BORDER_STRONG)
	t.set_color("knob_color", "Switch", ThemePalette.SURFACE)

	t.set_color("progress_color", "LongPressButton", Color(ThemePalette.ACCENT, 0.85))
	# 实底语义变体上的长按按钮：底色是红的/绿的/主色，进度条用半透明白才看得见
	# （原来进度条写死按 LongPressButton 取蓝色，套了 DangerButton 就几乎看不见了）
	for typ in ["AccentButton", "DangerButton", "SuccessButton", "CellAccentButton",
			"CellSuccessButton", "CellDangerButton"]:
		t.set_color("progress_color", typ, Color(1.0, 1.0, 1.0, 0.55))

	# 数据表（DataTable）
	t.set_color("header_bg_color", "DataTable", ThemePalette.SURFACE_ALT)
	t.set_color("cell_bg_color", "DataTable", ThemePalette.SURFACE)
	t.set_color("grid_color", "DataTable", ThemePalette.BORDER)
	t.set_color("header_text_color", "DataTable", ThemePalette.TEXT)
	t.set_color("text_color", "DataTable", ThemePalette.TEXT)

	# 树状表格（TreeTable）：比 DataTable 多「选中底色 / 悬停底色 / 层级引导线」
	t.set_color("header_bg_color", "TreeTable", ThemePalette.SURFACE_ALT)
	t.set_color("cell_bg_color", "TreeTable", ThemePalette.SURFACE)
	t.set_color("grid_color", "TreeTable", ThemePalette.BORDER)
	t.set_color("header_text_color", "TreeTable", ThemePalette.TEXT)
	t.set_color("text_color", "TreeTable", ThemePalette.TEXT)
	t.set_color("selected_bg_color", "TreeTable", ThemePalette.ACCENT_SOFT)
	t.set_color("hover_bg_color", "TreeTable", ThemePalette.SURFACE_ALT)
	t.set_color("guide_color", "TreeTable", ThemePalette.BORDER_STRONG)

	# 环形进度条（CircularProgressBar）
	t.set_color("track_color", "CircularProgressBar", ThemePalette.SURFACE_ALT)
	t.set_color("progress_color", "CircularProgressBar", ThemePalette.ACCENT)
	t.set_color("text_color", "CircularProgressBar", ThemePalette.TEXT)

	# 多子图（MultiTrendChart）
	t.set_color("background_color", "MultiTrendChart", ThemePalette.CHART_BG)
	t.set_color("grid_color", "MultiTrendChart", ThemePalette.CHART_GRID)
	t.set_color("axis_color", "MultiTrendChart", ThemePalette.CHART_AXIS)
	t.set_color("tick_text_color", "MultiTrendChart", ThemePalette.CHART_TEXT)

	# 分段指示灯（PartitionIndicator）
	t.set_color("on_color", "PartitionIndicator", ThemePalette.ACCENT)
	t.set_color("off_color", "PartitionIndicator", ThemePalette.SURFACE_ALT)
	t.set_color("border_color", "PartitionIndicator", ThemePalette.BORDER)

	# 伪彩强度图（IntensityMap）
	t.set_color("background_color", "IntensityMap", ThemePalette.CHART_BG)
	t.set_color("axis_color", "IntensityMap", ThemePalette.CHART_AXIS)
	t.set_color("tick_text_color", "IntensityMap", ThemePalette.CHART_TEXT)
	t.set_color("title_color", "IntensityMap", ThemePalette.TEXT)
	t.set_color("hover_color", "IntensityMap", ThemePalette.ACCENT)
	t.set_color("hover_text_color", "IntensityMap", ThemePalette.TEXT_ON_ACCENT)
	t.set_font_size("tick_font_size", "IntensityMap", ThemePalette.FONT_XS)
	t.set_font_size("label_font_size", "IntensityMap", ThemePalette.FONT_SM)
	t.set_font_size("title_font_size", "IntensityMap", ThemePalette.FONT_MD)

	# 文件拖放框（FileDropBox）
	t.set_color("bg_color", "FileDropBox", ThemePalette.SURFACE)
	t.set_color("bg_hover_color", "FileDropBox", ThemePalette.SURFACE_ALT)
	t.set_color("bg_drop_color", "FileDropBox", ThemePalette.ACCENT_SOFT)
	t.set_color("border_color", "FileDropBox", ThemePalette.BORDER_STRONG)
	t.set_color("border_hover_color", "FileDropBox", ThemePalette.ACCENT)
	t.set_color("border_drop_color", "FileDropBox", ThemePalette.ACCENT)


# ---------- 类型变体（语义化样式） ----------

static func _type_variations(t: Theme) -> void:
	# 语义按钮，以及它们的「单元格紧凑版」（`Cell` 前缀）。
	# 两者只差内边距，所以用同一段代码生成 —— 普通按钮实测 32px 高，
	# 塞进 30px 的表格行里会顶到分隔线，`Cell*` 那几个是 26px。
	var semantic := [
		["AccentButton", ThemePalette.ACCENT, ThemePalette.ACCENT_HOVER, ThemePalette.ACCENT_PRESS],
		["DangerButton", ThemePalette.DANGER, ThemePalette.DANGER_HOVER, ThemePalette.DANGER_PRESS],
		["SuccessButton", ThemePalette.SUCCESS, ThemePalette.SUCCESS_HOVER, ThemePalette.SUCCESS_PRESS],
	]
	for spec in semantic:
		_add_button_variation(t, spec[0], spec[1], spec[2], spec[3], ThemePalette.TEXT_ON_ACCENT)
		_add_button_variation(t, "Cell" + spec[0], spec[1], spec[2], spec[3],
				ThemePalette.TEXT_ON_ACCENT,
				ThemePalette.PAD_CELL_BUTTON_H, ThemePalette.PAD_CELL_BUTTON_V)
	# 幽灵按钮（透明底 + 主色文字）
	_add_ghost_variation(t)
	# 胶囊按钮（全圆角、带描边）
	_add_capsule_variation(t)
	# 单元格按钮（表格行内用的中性紧凑按钮）
	_add_cell_button_variation(t)

	# 标签变体：字号/颜色只在这里定义，业务脚本不要 add_theme_font_size_override
	# （否则「全局可调」就断了），需要新层级时在这里加一个变体即可。
	_add_label_variation(t, "PageTitle", ThemePalette.TEXT, ThemePalette.FONT_XXL)
	_add_label_variation(t, "SectionTitle", ThemePalette.TEXT, ThemePalette.FONT_XL)
	_add_label_variation(t, "CardTitle", ThemePalette.ACCENT, ThemePalette.FONT_LG)
	_add_label_variation(t, "Subtitle", ThemePalette.TEXT_SEC, ThemePalette.FONT_SM)
	_add_label_variation(t, "Caption", ThemePalette.TEXT_SEC, ThemePalette.FONT_XS)
	_add_label_variation(t, "DropHint", ThemePalette.TEXT_SEC, ThemePalette.FONT_SM)
	# 路径用等宽感的小字：一眼能看出「这是个文件路径」而不是正文
	_add_label_variation(t, "PathLabel", ThemePalette.TEXT_SEC, ThemePalette.FONT_XS)
	_add_label_variation(t, "LogLabel", ThemePalette.TEXT_SEC, ThemePalette.FONT_SM)

	# 状态标签：用文字色表达状态，**不要用 modulate 染深色文字**（会越乘越暗、读不清）
	_add_label_variation(t, "StatusIdle", ThemePalette.TEXT_SEC, ThemePalette.FONT_MD)
	_add_label_variation(t, "StatusOk", ThemePalette.SUCCESS, ThemePalette.FONT_MD)
	_add_label_variation(t, "StatusWarn", ThemePalette.WARNING, ThemePalette.FONT_MD)
	_add_label_variation(t, "StatusError", ThemePalette.DANGER, ThemePalette.FONT_MD)
	_add_label_variation(t, "ValueText", ThemePalette.TEXT, ThemePalette.FONT_MD)


static func _add_label_variation(t: Theme, type_name: String, color: Color, size: int) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_color("font_color", type_name, color)
	t.set_font_size("font_size", type_name, size)


# ---------- 工具 ----------

## 设置 Label/RichTextLabel 的 default_color / font_color。
static func _set_text_colors(t: Theme, typ: String, c: Color) -> void:
	if typ == "Label":
		t.set_color("font_color", typ, c)
	else:
		t.set_color("default_color", typ, c)


## 构建一个 StyleBoxFlat。
static func _sb(bg: Color, border: Color, radius: int, bw: int,
		pad_h := 0.0, pad_v := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	if bw > 0:
		sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_right = pad_h
	sb.content_margin_bottom = pad_v
	return sb


## 焦点描边：只画边框（draw_center=false），叠加在 base 之上不遮挡背景。
static func _outline(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	return sb


static func _apply_button_styles(t: Theme, typ: String,
		normal: StyleBox, hover: StyleBox, pressed: StyleBox,
		disabled: StyleBox, focus: StyleBox) -> void:
	t.set_stylebox("normal", typ, normal)
	t.set_stylebox("hover", typ, hover)
	t.set_stylebox("pressed", typ, pressed)
	t.set_stylebox("disabled", typ, disabled)
	t.set_stylebox("focus", typ, focus)


static func _add_button_variation(t: Theme, type_name: String,
		bg: Color, bg_hover: Color, bg_pressed: Color, text: Color,
		pad_h := ThemePalette.PAD_BUTTON_H, pad_v := ThemePalette.PAD_BUTTON_V) -> void:
	t.set_type_variation(type_name, "Button")
	t.set_color("font_color", type_name, text)
	t.set_color("font_hover_color", type_name, text)
	t.set_color("font_pressed_color", type_name, text)
	t.set_color("font_focus_color", type_name, text)
	t.set_color("font_hover_pressed_color", type_name, text)
	t.set_color("font_disabled_color", type_name, Color(text, 0.6))

	var normal := _sb(bg, _TRANSPARENT, ThemePalette.RADIUS_SM, 0, pad_h, pad_v)
	var hover := _sb(bg_hover, _TRANSPARENT, ThemePalette.RADIUS_SM, 0, pad_h, pad_v)
	var pressed := _sb(bg_pressed, _TRANSPARENT, ThemePalette.RADIUS_SM, 0, pad_h, pad_v)
	var disabled := _sb(Color(bg, 0.4), _TRANSPARENT, ThemePalette.RADIUS_SM, 0, pad_h, pad_v)
	_apply_button_styles(t, type_name, normal, hover, pressed, disabled,
			_outline(bg, ThemePalette.RADIUS_SM))
	t.set_stylebox("hover_pressed", type_name, pressed)


static func _add_capsule_variation(t: Theme) -> void:
	t.set_type_variation("CapsuleButton", "Button")
	t.set_color("font_color", "CapsuleButton", ThemePalette.TEXT)
	t.set_color("font_hover_color", "CapsuleButton", ThemePalette.TEXT)
	t.set_color("font_pressed_color", "CapsuleButton", ThemePalette.TEXT)
	t.set_color("font_focus_color", "CapsuleButton", ThemePalette.TEXT)
	t.set_color("font_hover_pressed_color", "CapsuleButton", ThemePalette.TEXT)
	t.set_color("font_disabled_color", "CapsuleButton", ThemePalette.TEXT_DIS)

	var r := ThemePalette.RADIUS_PILL
	var normal := _sb(ThemePalette.SURFACE, ThemePalette.BORDER, r, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var hover := _sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER_STRONG, r, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var pressed := _sb(ThemePalette.ACCENT_SOFT, ThemePalette.ACCENT, r, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var disabled := _sb(ThemePalette.SURFACE, ThemePalette.BORDER, r, 1,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	_apply_button_styles(t, "CapsuleButton", normal, hover, pressed, disabled,
			_outline(ThemePalette.ACCENT, r))
	t.set_stylebox("hover_pressed", "CapsuleButton",
			_sb(ThemePalette.ACCENT_SOFT_HOVER, ThemePalette.ACCENT, r, 1,
				ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V))


## 单元格按钮（`CellButton`）：给 `DataTable` / `TreeTable` 的行内按钮用。
##
## 它是 `Button` 的变体，所以**颜色全部继承普通按钮**（深浅、悬停、按下、禁用都一样），
## 这里只把内边距收窄 —— 普通按钮实测 32px 高，塞进表格行里会顶到分隔线。
## 需要语义色（红的删除、绿的开始）时**不要**用它，直接用 `DangerButton`/`SuccessButton`
## 那些变体（它们略高一点，行高 30 也放得下）。
static func _add_cell_button_variation(t: Theme) -> void:
	t.set_type_variation("CellButton", "Button")
	var ph := ThemePalette.PAD_CELL_BUTTON_H
	var pv := ThemePalette.PAD_CELL_BUTTON_V
	var r := ThemePalette.RADIUS_SM
	_apply_button_styles(t, "CellButton",
			_sb(ThemePalette.SURFACE, ThemePalette.BORDER, r, 1, ph, pv),
			_sb(ThemePalette.SURFACE_ALT, ThemePalette.BORDER_STRONG, r, 1, ph, pv),
			_sb(ThemePalette.ACCENT_SOFT, ThemePalette.ACCENT, r, 1, ph, pv),
			_sb(ThemePalette.SURFACE, ThemePalette.BORDER, r, 1, ph, pv),
			_outline(ThemePalette.ACCENT, r))
	t.set_stylebox("hover_pressed", "CellButton",
			_sb(ThemePalette.ACCENT_SOFT_HOVER, ThemePalette.ACCENT, r, 1, ph, pv))


static func _add_ghost_variation(t: Theme) -> void:
	t.set_type_variation("GhostButton", "Button")
	t.set_color("font_color", "GhostButton", ThemePalette.ACCENT)
	t.set_color("font_hover_color", "GhostButton", ThemePalette.ACCENT_HOVER)
	t.set_color("font_pressed_color", "GhostButton", ThemePalette.ACCENT_PRESS)
	t.set_color("font_focus_color", "GhostButton", ThemePalette.ACCENT)
	t.set_color("font_hover_pressed_color", "GhostButton", ThemePalette.ACCENT_PRESS)
	t.set_color("font_disabled_color", "GhostButton", ThemePalette.TEXT_DIS)

	var empty := _sb(_TRANSPARENT, _TRANSPARENT, ThemePalette.RADIUS_SM, 0,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	var hover := _sb(ThemePalette.ACCENT_SOFT, _TRANSPARENT, ThemePalette.RADIUS_SM, 0,
			ThemePalette.PAD_BUTTON_H, ThemePalette.PAD_BUTTON_V)
	_apply_button_styles(t, "GhostButton", empty, hover, hover, empty,
			_outline(ThemePalette.ACCENT, ThemePalette.RADIUS_SM))
	t.set_stylebox("hover_pressed", "GhostButton", hover)


static func _icon(name: String) -> Texture2D:
	return load("res://themes/icons/" + name) as Texture2D
