class_name ThemePalette
extends RefCounted
## 设计令牌（Design Tokens）——全项目样式唯一可调来源。
##
## 所有颜色、圆角、字号、间距都在这里集中定义；`ThemeFactory` 据此构建全局主题，
## 自定义控件（TrendChart / Switch / LongPressButton）也从此读取默认颜色。
## 想统一调整样式时，只改这个文件即可全局生效，无需触碰任何控件脚本。

# ---------- 中性色 ----------
const BG := Color(0.957, 0.961, 0.969)            # 应用背景          #f4f5f7
const SURFACE := Color(1.0, 1.0, 1.0)             # 卡片/输入底色     #ffffff
const SURFACE_ALT := Color(0.929, 0.937, 0.949)   # 悬停底色          #edf0f2
const BORDER := Color(0.847, 0.867, 0.898)        # 常规边框          #d8dde5
const BORDER_STRONG := Color(0.761, 0.788, 0.827) # 强边框/按下       #c2c9d3

# ---------- 文字 ----------
const TEXT := Color(0.122, 0.153, 0.200)          # 主文字            #1f2733
const TEXT_SEC := Color(0.333, 0.376, 0.431)      # 次要文字          #55606e
const TEXT_DIS := Color(0.596, 0.631, 0.675)      # 禁用文字          #98a1ac
const TEXT_ON_ACCENT := Color(1.0, 1.0, 1.0)      # 强调底上的文字     #ffffff

# ---------- 强调 / 主色 ----------
const ACCENT := Color(0.290, 0.565, 0.850)        # 主色              #4a90d9
const ACCENT_HOVER := Color(0.243, 0.486, 0.745)
const ACCENT_PRESS := Color(0.204, 0.408, 0.627)
const ACCENT_SOFT := Color(0.882, 0.933, 0.973)   # 选中浅底          #e1eef8
const ACCENT_SOFT_HOVER := Color(0.827, 0.902, 0.961)

# ---------- 语义色 ----------
const SUCCESS := Color(0.184, 0.627, 0.435)       # 成功 / 开关开     #2fa06f
const SUCCESS_HOVER := Color(0.157, 0.533, 0.369)
const SUCCESS_PRESS := Color(0.133, 0.447, 0.310)
const SUCCESS_SOFT := Color(0.906, 0.965, 0.933)

const DANGER := Color(0.839, 0.271, 0.271)        # 危险 / 急停       #d64545
const DANGER_HOVER := Color(0.729, 0.220, 0.220)
const DANGER_PRESS := Color(0.604, 0.180, 0.180)
const DANGER_SOFT := Color(0.988, 0.929, 0.929)

const WARNING := Color(0.851, 0.541, 0.122)       # 警告              #d98a1f
const WARNING_SOFT := Color(0.992, 0.949, 0.882)

# ---------- 图表 ----------
const CHART_LINE := ACCENT
const CHART_BG := SURFACE
const CHART_GRID := Color(0.906, 0.914, 0.929)
const CHART_AXIS := BORDER_STRONG
const CHART_TEXT := TEXT_SEC
const CHART_SERIES := [ACCENT, SUCCESS, WARNING, DANGER]   # 多子图默认曲线配色（循环取用）

# ---------- 色标（colormap） ----------
# 伪彩图默认色标名；可选名见 scripts/theme/colormaps.gd（rainbow / jet / gray）。
# "rainbow" 与 matplotlib 的 cmap='rainbow' 完全一致。
const CMAP_DEFAULT := "rainbow"

# ---------- 伪彩强度图（IntensityMap） ----------
const IMAP_MARGIN_LEFT := 58.0     # 左侧留给 Y 刻度
const IMAP_MARGIN_RIGHT := 12.0    # 右侧（不含色标）
const IMAP_MARGIN_TOP := 26.0      # 顶部留给标题
const IMAP_MARGIN_BOTTOM := 40.0   # 底部留给 X 刻度 + 轴标签
const IMAP_COLORBAR_W := 16.0      # 色标条宽度
const IMAP_COLORBAR_GAP := 34.0    # 色标条与绘图区的间距（放刻度数字）
const IMAP_COLORBAR_LABEL_OFFSET := 46.0   # 色标文字（竖排）距色标条右缘
const IMAP_COLORBAR_TICK_W := 34.0         # 色标右侧刻度数字需要的宽度
const IMAP_COLORBAR_BANDS := 128   # 色标条分段数（越大越平滑）
const IMAP_AXIS_TICKS := 5         # 每个轴大致刻度数
const IMAP_READOUT_PAD := 8.0      # 悬停读数气泡的内边距

# ---------- 文件拖放框（FileDropBox） ----------
const DROPBOX_MIN_H := 108.0       # 未指定时的最小高度
const DROPBOX_BORDER_W := 2.0      # 虚线粗细
const DROPBOX_DASH := 7.0          # 虚线段长
const DROPBOX_GAP := 5.0           # 虚线间隙

# ---------- 圆角 ----------
const RADIUS_SM := 4
const RADIUS_MD := 6
const RADIUS_LG := 8
const RADIUS_PILL := 999       # 胶囊形（引擎会把圆角钳到半高，得到药丸/胶囊外观）

# ---------- 字号 ----------
const FONT_XS := 11
const FONT_SM := 12
const FONT_MD := 14          # 全局默认正文字号
const FONT_LG := 16
const FONT_XL := 20
const FONT_XXL := 24

# ---------- 间距 / 留白（StyleBox content margin） ----------
const PAD_BUTTON_H := 10.0
const PAD_BUTTON_V := 6.0
const PAD_INPUT_H := 8.0
const PAD_INPUT_V := 5.0
const PAD_PANEL := 12.0
const PAD_POPUP := 6.0
const PAD_CARD_V := 10.0        # 卡片内标题与内容的垂直间距（TitledGroup/RowCard）

# ---------- 数据表尺寸（ColumnTable / DataTable / TreeTable） ----------
const TABLE_HEADER_H := 30.0
const TABLE_ROW_H := 26.0
const TABLE_PAD := 8.0          # 单元格左右留白
const TABLE_MIN_COL := 40.0     # 列最小宽度
const TABLE_INDENT := 16.0      # 树表每层缩进（TreeTable）
const TABLE_ARROW_W := 16.0     # 树表展开箭头占位宽度（TreeTable）

# ---------- 主题常量（theme constants，均为 int） ----------
const SEP_BOX := 8            # HBox/VBox 子项间距
const SEP_GRID := 8           # Grid 间距
const PAGE_MARGIN := 16       # 页面边距（整个界面到窗口边缘的距离）
const SEP_SEPARATOR := 4      # 分隔线留白

# ---------- 页面级布局（业务界面用，改这里即可统一缩放） ----------
const SIDEBAR_W := 320.0        # 左侧参数栏宽度
const PANEL_MIN_H := 220.0      # 主显示区最小高度
const TOOLBAR_MIN_H := 28.0     # 工具行最小高度

# ---------- 窗口（AppShell autoload） ----------
# 用户能把窗口拖到的最小尺寸。低于这个值布局会开始互相挤压（参数栏出现滚动条、
# 伪彩图被压扁），所以交给 AppShell 在启动时设成窗口的 min_size。
const WINDOW_MIN_W := 1024.0
const WINDOW_MIN_H := 640.0

# ---------- 界面缩放（AppShell / UiScaleOption） ----------
# 可选缩放档位；0.0 这一档是「跟随系统 DPI」的哨兵值（见 app_shell.gd 的 detect_dpi_scale）。
const UI_SCALE_FOLLOW_SYSTEM := 0.0
const UI_SCALE_STEPS := [1.0, 1.25, 1.5, 1.75, 2.0]
const UI_SCALE_MIN := 0.75
const UI_SCALE_MAX := 3.0
