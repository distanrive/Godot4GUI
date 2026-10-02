# Godot 4.7 实测事实与坑（核验过的）

> 这份文件收「**踩过一次、写在文档里能省下一个人半天**」的 Godot 4.7 事实。
> 大部分来自下游项目（DeepScribe / wlt_login）回流，但**每条都标了核验状态** ——
> 没核验过的宁可标出来，也不当成结论往下传（有过一次教训：某条报告的最小复现里
> 属性名是错的、根本跑不起来，看着却很像「去掉它就好了」）。
>
> 环境：Godot 4.7.2 stable / Windows 11。核验方式见每条的「怎么验的」。

标记含义：**[已验]** = 我在本机对着引擎/文档实测过；**[待验]** = 只有报告来源，我还没验；
**[已修正]** = 报告里的说法不准确，下面是订正后的版本。

---

## 一、控件与布局

### 1. `Label` 的最小宽度 = 整串文字的宽度 **[已修正]**

长文本（长选项名、路径、整句状态）放进 `HBoxContainer` / `GridContainer` 会把容器的
**最小宽度**顶大；窗口装不下就横向溢出，右边的按钮被切掉。

实测（一段 46 字的中文，`Label` 自身的 `get_combined_minimum_size().x`）：

| 设置 | 最小宽度 |
|---|---|
| 什么都不设 | **672** |
| `clip_text = true` | **1** |
| `text_overrun_behavior = OVERRUN_TRIM_ELLIPSIS` | **1** |
| `autowrap_mode != OFF` + `custom_minimum_size.x = 120` | **120** |

> **订正**：上游报告说「`clip_text = true` 不能减小最小宽度，只有 autowrap 能」——
> 前半句不对。Godot 4.7 里 `Label::get_minimum_size()` 在 `clip` **或**
> `overrun_behavior != NO_TRIMMING` 时直接返回 `Size2(1, 高度)`，所以**三种办法都有效**：
> - 想截断显示（`…`）：`clip_text = true` 或 `text_overrun_behavior = OVERRUN_TRIM_ELLIPSIS`
> - 想完整显示但允许换行：`autowrap_mode != OFF` **并且**给一个 `custom_minimum_size.x`
>   （只开 autowrap 不给宽度，最小宽度还是按最长的词算）
>
> 本项目 `gallery.gd` 的路径标签用的就是 `OVERRUN_TRIM_ELLIPSIS`。

**怎么验的**：`--script` 建 Label 逐个设，打印 `get_combined_minimum_size().x`。

### 1b. 滚动条的粗细**完全由样式盒的最小尺寸决定**，给 0 就没有滚动条 **[已验]**

`ScrollBar` 的 `scroll` / `grabber` 样式盒的 `content_margin` 决定条宽（= 左右 margin 之和）。
自定义主题里写成 `pad = 0` 的样式盒，实测：

```
VScrollBar.get_combined_minimum_size() == (0, 0)
ScrollContainer 内部滚动条宽度 == (0.0, 300.0)      # 可见 = true，但宽 0
```

也就是说**滚动条存在、只是宽 0**：轨道和滑块都画不出来，屏幕上只剩贴着右缘的一条淡痕，
抓不住也点不中。最阴的是它**不报任何错**（跑 headless、跑场景都干干净净），
只有截图放大才看得出来。

本项目据此刻了 `ThemePalette.SCROLLBAR_W`（12px）并把这条钉进 `tools/checks/scroll_bars.gd`。

**顺带一条**：自定义 `Theme` 里**没定义的项会回落到引擎默认主题**，
所以默认滚动条两端的上下箭头按钮会冒出来（默认主题定义了 `increment`/`decrement`）。
本项目把它们设成全透明的 `themes/icons/empty.svg` 压掉。

**怎么验的**：`--script` 建 `VScrollBar`，打印 `get_combined_minimum_size()`；
再开真窗口 `root.get_texture().get_image().save_png()` 截图放大看。

---

### 1c. `resized` 信号可能在 `_ready()` **之前**就已经发生过 **[已验]**

容器（`VBoxContainer` 等）**排完版**才轮到 ready 通知传播，于是：

```gdscript
func _ready() -> void:
    resized.connect(_on_resized)     # ← 这一行挂上时，那次 resize 已经过去了
```

实测打印顺序：先 `resized size=(520, 210)`，**之后**才是 `_ready`。
后果是「依赖 resize 才摆好的东西一直不对，直到下一次 resize 才归位」——
本项目的行内按钮就这么踩过：停在 `(0,0)` 且不可见。

**解法**：在 `_ready()` 末尾补一次 `_on_resized()`（幂等的话最省事）。

**怎么验的**：`--script` 里给 `resized` 挂一个打印、再在 `_ready` 里挂一个，看谁先来。

---

### 1d. `clip_contents` 会裁剪**自己的绘制 + 子节点**，但裁剪矩形是**整个控件** **[已验（文档 + 实测）]**

`gdd_0542_CanvasItem.md` / `gdd_0963_Control.md` 原文：clips "CanvasItem based children"，
且被裁掉的子节点**连输入一起收不到**（本项目截图确认：表体外溢的行确实被切掉了）。

**但它裁不掉「控件内部的某一条带」**：矩形裁剪的边界是控件自身矩形，
而自绘表格的表头就在这个矩形**里面** —— 所以「往上滚时压进表头带的那半行」裁不掉。

**解法（本项目的做法）**：**表头最后画**，用表头底色盖住那半行。只是把 `draw_*` 换个顺序，
`_scroll == 0` 时结果与从前逐像素一致。

另外别把 `clip_contents` 和 `CanvasItem.clip_children` 搞混：后者是**alpha 遮罩**那一套
（文档里「不能嵌套」的警告说的是它），矩形裁剪可以正常嵌套。

---

### 1e. `GridContainer` 的余量分配**不看 `size_flags_stretch_ratio`** **[已验（源码 + 实测）]**

`GridContainer::_update_grid()` 对可扩展列就是一句
`remaining_space.width / col_expanded.size()` —— **平均分**，
你把 `size_flags_stretch_ratio` 设成 1:2:3 也一点用没有。
想按比例分宽度得用 `HBoxContainer`（它认 ratio）。

更反直觉的是**挤不下时会「钉死」某一列**：它先假定均分，如果某一列的固有最小宽度
大于「剩余空间 ÷ 可扩展列数」，那一列就被移出可扩展集合、按**它的最小值**固定下来，
剩下的宽度**全给另一列**。

实测（两列网格、可用宽 1268、缝 12）：左列最小 400，右列最小 814
（= 网络卡 402 + 缝 12 + 运行状态卡 400）→ 814 > 1256/2 = 628，
于是右列被钉死在 814，左列拿走剩下的 **442**。三张卡变成 442｜402｜400 ——
左列反而最宽，跟想要的「三列大致等宽」正好相反。

**解法**：想让某一列是固定宽度、其余全给另一边，就**别给那一列的单元格设 `SIZE_EXPAND`**
（不设 EXPAND 的列按最小值走，余量全归可扩展列）。本模板据此拿到 400｜422｜422。

**怎么验的**：`--script` 里建网格 → 打印 `get_combined_minimum_size()` 与各子节点的 `size`，
改一个标志位再打一次对照。

---

### 1f. `popup_on_parent()` 要的是**全局坐标**，不是父控件的局部坐标 **[已验]**

给表格加行级右键菜单时最容易想当然的一条：把 `PopupMenu` 挂成某个 `Control` 的子节点，
就以为 `popup_on_parent(Rect2(控件内局部坐标, Vector2.ZERO))` 是相对那个控件定位的。
**不是。**

官方文档原话（`Window.popup_on_parent`）：

> Popups the Window with a position shifted by parent **Window's** position.
> If the Window is embedded, has the same effect as `popup()`.

而 `popup()` 的说明写着 "rect must be in global coordinates"（单窗口模式下 = 相对
**主窗口左上角**）。两句合起来：**嵌入子窗口时 `popup_on_parent` 就是 `popup`，
坐标按主窗口算** —— 「父亲是 Control」和「坐标相对谁」是两回事，这是最容易搞混的地方。

实测（宿主控件放在 220px 占位 + 16px 页边距之后，模拟「左边有侧边栏」；
控件内点击位置 `(320, 75)`）：

| 传什么 | 菜单实际落在 | 偏差 |
|---|---|---|
| `Rect2(Vector2(320, 75), Vector2.ZERO)` | `(320, 75)` | **向左偏 244px**（= 宿主控件的全局 x） |
| `Rect2(host.get_global_position() + Vector2(320, 75), Vector2.ZERO)` | `(564, 99)` | **0, 0** |

症状就是「菜单弹出来离鼠标偏出去一大截」，且偏差**恰好等于那个控件的全局 x**
—— 贴着原点摆的控件会碰巧通过，所以写复现时**宿主必须有非零偏移**。

写法上有个好处：嵌入式弹窗的「主窗口左上角」正好等于 `Control.get_global_position()`
的原点，而非嵌入模式下 `popup_on_parent` 又会补上父窗口的位置，
所以 `host.get_global_position() + 控件内坐标` 这一种写法**两种模式都对**。

**顺带一条**：嵌入弹窗会被引擎**自动收进视口**，靠边时不用自己 clamp ——
请求 `(1590, 1190)` 实际落在 `(1516, 996)`，右下边缘恰好贴住 1600×1200 视口。

**怎么验的**：`--script` 建一个带非零全局偏移的 `Control`，把 `PopupMenu` 挂上去，
按上面两种写法各弹一次，打印 `menu.position` 与期望位置的差。

---

### 2. 窗口尺寸：拉伸模式 `disabled` 时 `viewport_*` 是**物理**像素 **[已验]**

`project.godot` 的 `display/window/size/viewport_width/height` **不乘** `content_scale_factor`。
所以 125% 缩放的机器上写「1280×800」，实际拿到的是**逻辑 1024×640** ——
如果它正好等于 `AppShell` 的 `WINDOW_MIN_*`，窗口就会**每次都以最小尺寸打开**。

实测（`content_scale_factor = 1.25`）：窗口物理 1280×800 → 逻辑 1024×640（= 最小尺寸）。

**已修**：`AppShell._apply_default_window_size()` 用**逻辑**设计尺寸
（`ThemePalette.WINDOW_DEFAULT_W/H`）× 缩放换算成物理，再钳进 `screen_get_usable_rect()`。
修完实测：物理 1600×1000 = 逻辑 1280×800 ✔

**怎么验的**：删掉 `user://config.cfg` 后起一次真窗口，读 `[AppShell]` 那行启动日志
（它会把物理/逻辑尺寸都打出来）。

---

## 二、网络

### 3. `StreamPeerTCP` 必须先 `poll()`，状态才会更新 **[已验]**

**注意 4.7 里 `poll()` 不在 `StreamPeerTCP` 上，而在它的父类 `StreamPeerSocket` 上**
（找文档时容易找错类）。文档原文：

> `Error poll()` —— Polls the socket, **updating its state**. See `get_status()`.

不 poll 的话 `get_status()` / `get_available_bytes()` 永远停在旧值
（连接请求会一直显示 `STATUS_CONNECTING`），而且很难看出原因。
「用 TCP 端口当单实例锁」这种写法第一版就是这么整个失效的。

**怎么验的**：对没人监听的端口 `connect_to_host()`，不 poll → 状态一直是 CONNECTING；
poll 一次 → 立刻变成 ERROR。

### 4. `WebSocketPeer` 的心跳/关闭语义

本项目自己的经验（`NetClient`）：`disconnected` 只在**曾经连上过**之后断线时才发；
「后端从头到尾没起来」不会触发它。要感知这种情况得自己记「我发起过连接」
（模板里是 `connecting` 信号，`BackendLauncher` 就靠它在宽限期后拉起后端）。

---

## 三、字符串与编码（Windows 中文环境尤其要看）

### 5. `String.to_multibyte_char_buffer()` **会带一个结尾 NUL** **[已验]**

```
"中文A".to_multibyte_char_buffer() → 6 字节（GBK 的 中文=4 + A=1 + **NUL=1**）
"中文A".to_utf8_buffer()           → 7 字节
```

拼表单 / 命令行 / 二进制协议时，每个串尾部会多一个 `%00`。
要**精确**的字节就用 `to_utf8_buffer()` 或自己 `trim` 掉末尾的 0。

**怎么验的**：`--script` 里 `print(buf.size())` 与 `buf[buf.size()-1]`。

### 6. Windows 上 `get_string_from_multibyte_char()` **只认 `gb2312` / `gb18030`** **[已验]**

| 编码名 | 结果 |
|---|---|
| `"gb2312"` | ✅ 能解 |
| `"gb18030"` | ✅ 能解 |
| `"936"` | ❌ 返回空串 |
| `"GBK"` | ❌ 返回空串 |
| `"cp936"` | ❌ 返回空串 |

传不认的名字时**返回空串并打一行** `ERROR: Conversion failed: Unknown encoding`
—— 不看日志就会以为「文件是空的」。

**怎么验的**：同一段 UTF-8 字节喂 5 个编码名，打印结果长度。

### 7. 判断「是不是 UTF-8」要**做字节结构校验**，别数替换字符 **[已验（旁证）]**

GBK 几乎接受任意字节对。把 UTF-8 字节喂给 GBK 解码，**通常一个 `U+FFFD` 都没有**、
只是全是错字 —— 所以「decode 后没有替换字符」完全不能证明它是 UTF-8。

实测：UTF-8 的「中文测试」用 gb2312 解出来是「涓枃娴嬭瘯」（10 个合法汉字，0 个替换字符）。

正确做法是按 UTF-8 的结构（首字节前导 1 的个数 + 后续字节 `10xxxxxx`）逐段校验。

---

## 四、杂项（写打包脚本 / 加密 / 托盘时会撞）

### 8. `OS.execute` 没有 `working_directory` 参数 **[待验]**

要用别的工作目录，只能自己在命令行里 `cd`（Windows 上是 `cmd /c "cd /d X && ..."`）
或改用 `OS.create_process` 前先切当前目录。

### 9. `Crypto.encrypt()` 要的是 `CryptoKey` **[待验]**

那是**非对称**那套，喂裸对称密钥编不过。对称加密得用 `AESContext`，
且 CBC 要自己补 PKCS#7 padding（补到 16 字节整数倍）。

### 10. `OS.get_unique_id()` 官方说不稳定、**不要用于安全用途** **[待验]**

别拿它当密钥材料或设备指纹的唯一定据。

### 11. 导出后的 release 构建**不会执行 `--script`** **[待验]**

别把开发期自检工具打进去（打了也调不起来）。

### 12. 托盘用 `StatusIndicator` 节点（4.3+） **[待验]**

Godot 3.x 的 `status_indicator_add_button` 在 4.x **不存在**；`StatusIndicator.menu` 是 `NodePath`。

### 13. `PopupMenu` 的**分隔线也占下标** **[已验（官方文档原文）]**

> `void add_separator(label: String = "", id: int = -1)` —— Adds a separator between items.
> **Separators also occupy an index**, which you can set by using the `id` parameter.

所以「第 3 项」这种按下标的写法会因为中间插了分隔线而错位；要按 `id` 操作，
用 `get_item_index(id)` 反查下标。

### 14. 关闭行为自管 **[待验]**

`get_tree().auto_accept_quit = false` + 在 `NOTIFICATION_WM_CLOSE_REQUEST` 里自己处理；
`Window.hide()` 可以隐藏主窗口而进程继续跑（托盘应用的常见做法）。

### 15. `get_theme_color()` / `get_theme_constant()` **没有带默认值的重载** **[已验（官方文档）]**

> `Color get_theme_color(name: StringName, theme_type: StringName = &"") const`

只有两个参数，**没有**「取不到就给个默认色」的版本。所以本项目所有自绘控件都写成：

```gdscript
func _theme_color(name: StringName, fallback: Color) -> Color:
    return get_theme_color(name, t) if has_theme_color(name, t) else fallback
```

顺带一个有用的细节（同一份文档里写着）：`theme_type` 省略时会用控件的
**`theme_type_variation`**、否则用类名 —— 这正是 `LongPressButton` 能「跟着语义变体取色」的依据。

---

### 16. `OS.create_process` 的子进程**确实**不随 Godot 退出而结束；但 `_console.exe` 有 wrapper 层 **[已验]**

先记一条被验证的官方说法（`gdd_1387_OS.md` 原文）：
> Creates a new process that runs independently of Godot. **It will not terminate when Godot terminates.**

实测属实 —— 用**非 console 版**二进制 `Godot_v4.7.2-stable_win64.exe`：
`taskkill /F` 强杀 Godot 之后，它 `create_process` 拉起的 python 后端**仍然活着**
（而且这时另一个 WebSocket 客户端还连着，后端按自己的 linger 逻辑把局面收干净）。

**但测试进程归属时有个坑**：`Godot_..._console.exe` 在需要控制台时会把自己**重新拉起一层**
（于是「后端 python 的父进程」有时候就是那个 wrapper、有时候是它的子进程）。
实测过一次「杀掉 wrapper 之后它的子孙也一起没了」的现象（像是控制台被关掉、附着在上面的进程收到
CTRL_CLOSE_EVENT）。

**教训**：写进程生命周期的自动化测试时，**认准真正的 Godot 进程**（= 后端 python 的父进程），
或者干脆用非 console 版二进制 —— 否则「杀谁」这件事本身就有歧义，得出的结论会互相打架
（本项目在这上面绕了三圈：先用 console 版得出「Godot 会带走子进程」，换非 console 版才发现不是）。

---

### 16b. `brotli=no` 会让**所有内置字体加载失败**（编译期开关的隐性依赖） **[已验]**

Godot 的内置字体**全是 WOFF2**：`thirdparty/fonts/` 下的 `Inter_Regular/Inter_Bold`
（默认 UI 字体）与 `DroidSansFallback`（**中文兜底字体**），
而 WOFF2 解压靠 FreeType + brotli（`modules/text_server_adv/SCsub` 里的
`FT_CONFIG_OPTION_USE_BROTLI`）。

关掉 `brotli` 之后两种字体都解不出来，文字**静默退化成 Windows 系统字体**：
英文与数字变衬线体（Times 那一路）、中文变宋体式的细笔画，界面整体「字变小了、变淡了」，
而**日志里一行错都不报**。这一项只占 **0.3 MB**，不值得省。

**症状与 `module_webp_enabled=no` 是同一类**（贴图导入内部用 WebP 存 `.ctex`，
关掉后所有贴图加载失败）。教训：**「看着用不到」的第三方库可能是引擎内部的依赖**
（编码器/解码器这类尤其危险），砍之前先在真机上跑一遍、并且**用眼睛看**。

**怎么验的**：同一台机器、同一个窗口、同一块区域，用两种模板各导一次 exe、截图逐像素比 ——
衬线体 vs 黑体一眼就能分出来。

---

## 五、Windows `.bat` 打包脚本的三条硬约束 **[待验，报告来源]**

写过的都撞过（报告者说三条全撞了）：

1. **必须纯 ASCII + CRLF**。非 ASCII + 代码页 65001 会让 cmd 逐行读字节的偏移算错、
   **注释被当成命令执行**；GBK + `chcp 936` 能解析，但**每次调完 Godot 之后的中文 echo 都变乱码**
   （Godot 启动时会把控制台代码页改成 UTF-8）。
2. **`if ... ( ... )` 块里的 `echo` 不能有未转义的 `)`** —— 会提前闭合块，
   后面的文字被当命令执行（报 `not was unexpected at this time`）。
3. **`call` 用全路径**：某些环境（比如从 Git Bash 启动的 cmd）会设
   `NoDefaultCurrentDirectoryInExePath=1`，裸文件名直接找不到。

---

## 六、窗口与托盘（Windows）

### 17. `Window.hide()` 对**主窗口必然失败**，任务栏按钮也去不掉 **[已验（源码 + 实测）]**

```
ERROR: Can't change visibility of main window.
   at: set_visible (scene/main/window.cpp:1017)
```

`Window::set_visible()` 里第一件事就是
`ERR_FAIL_NULL_MSG(get_parent(), "Can't change visibility of main window.")` ——
主窗口就是 `get_tree().root`，**没有父节点**，所以这一句必然命中。另外三条证据：

- `DisplayServer` 根本没有 hide 类接口，最接近的只有 `window_set_mode(MINIMIZED)`；
- Windows 后端 `_get_window_style()` 给主窗口**恒定**加 `WS_EX_APPWINDOW` ——
  那正是「必须出现在任务栏」的标志；只有窗口带外部父 HWND（编辑器内嵌游戏那条路）时才跳过；
- `WINDOW_FLAG_POPUP` 明确拒绝主窗口（`Main window can't be popup.`）。

**所以「关窗后只剩托盘图标、任务栏不留按钮」用纯 GDScript 做不到**，
只能拿 `DisplayServer.window_get_native_handle(WINDOW_HANDLE)` 的 HWND
绕过引擎调 Win32 的 `ShowWindow(hwnd, SW_HIDE)`。本模板为此带了一份极小的 GDExtension
（`tools/native_window/`），GDScript 侧封装见 `scripts/util/tray_window.gd`。

**一个被它坑到的写法**：`win.hide()` 之后读 `win.visible` 判断成没成功。
`hide()` 每一次都失败，于是**每一次**都会走进「隐藏失败」分支、打一条
「当前平台无法隐藏窗口」的警告 —— 那条警告看着像偶发故障，其实描述的是必然结果。

### 18. `render_target_update_mode` 只注册在 `SubViewport` 上 **[已验（源码 + 实测）]**

`UpdateMode` 枚举**声明**在 `viewport.h`，很容易以为根窗口也能用 —— 但
`ADD_PROPERTY("render_target_update_mode", ...)` 和 `BIND_ENUM_CONSTANT(UPDATE_*)`
都写在 `SubViewport::_bind_methods()` 里（`scene/main/viewport.cpp`）。

后果：`Viewport.UPDATE_DISABLED` **连解析都过不去**
（`Parse Error: Cannot find member "UPDATE_DISABLED" in base "Viewport"`），
写成整数去 `set()` 则是运行时报错。

**「藏起来之后别一直渲染」怎么办**：用 `Engine.max_fps` 把主循环憋住。
本模板压到 10 —— 不压到 1 是因为托盘菜单也是 Godot 画的，1fps 下要等一秒才弹出来。
计时器 / 协程 / 网络轮询走的是真实时间，不受影响。

---

## 七、GDExtension（写原生扩展时）

本模板带了一份**手写的 C 扩展**（`tools/native_window/`，约 300 行，**不依赖 godot-cpp**）——
只包两个函数，为一个 `ShowWindow` 拉一整套 C++ 绑定（几百 MB 仓库 + 一次长编译）不划算。
下面几条都是写它的时候撞出来的。

### 19. `GDExtensionPropertyInfo.class_name` **不能给 NULL** **[已验（崩溃复现）]**

头文件里它是个 `GDExtensionStringNamePtr`，看着「没有类」就该填 NULL ——
但 Godot 侧的 `PropertyInfo(const GDExtensionPropertyInfo &)` 是**无条件解引用**的：

```cpp
class_name = *reinterpret_cast<const StringName *>(pinfo.class_name);
```

给 NULL 就是一次空指针解引用，表现为**加载扩展时整个进程 signal 11 崩溃**，
而且崩在 Godot 自己的代码里、**堆栈没有符号**（`-- END OF C++ BACKTRACE --` 之后是空的），
极难定位。正确做法是传一个**空的 StringName**。`hint_string` 同理（要空的 `String`，不是 NULL）。

### 20. `.gdextension` 不被扫到就**静默不加载** **[已验]**

Godot 运行期是从 `.godot/extension_list.cfg` 读扩展清单的，而那个文件由
**编辑器扫描工程时**生成。往工程里新放一个 `.gdextension` 之后如果不跑一次 `--import`
（或开一次编辑器），`ClassDB.class_exists("YourClass")` 永远是 false，
而且**一句报错都没有**。新增带 `class_name` 的脚本同理（表现为 `Identifier not declared`）。

反过来，**清单在、dll 不在**时每次启动会打三行 ERROR
（`GDExtension dynamic library not found`）—— 功能会优雅降级，但控制台一直是脏的。
所以本模板把那个 58 KB 的 `bin/*.dll` **提交进仓库**。

### 21. `ClassDB.class_call_static()` 是「缺 dll 也不炸」的关键 **[已验]**

```gdscript
# ✗ dll 一缺失，**整个脚本编译不过**，连降级的机会都没有
NativeWindow.hide_window(hwnd)

# ✓ 类不在时 class_exists 返回 false，可以优雅退回「最小化到任务栏」
if ClassDB.class_exists(&"NativeWindow"):
    ClassDB.class_call_static(&"NativeWindow", &"hide_window", hwnd)
```

业务脚本里**一律用动态写法**。一次关窗查一次 ClassDB，性能上完全无所谓。

---

## 附：一条核验方法上的教训

报「泄漏」时**先做对照**：写个什么都不建的**空** `--script` 跑一遍看基线。
`ObjectDB instances were leaked at exit`、`RID allocations leaked`、
`BUG: Unreferenced static string` 这些在 headless/收尾阶段经常是**引擎自身的噪声**。

**不要只把某一行注释掉就下结论** —— 那一行如果本身是错的（属性名写错之类），
脚本会在那里提前中止，现象看起来完全像「去掉它就不泄漏了」。
（DeepScribe 报告的 `stretch_ratio` 泄漏就是这种情况：`Control` 上根本没有这个属性，
正确的是 `size_flags_stretch_ratio`；用正确属性名实测不泄漏。）
