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

## 附：一条核验方法上的教训

报「泄漏」时**先做对照**：写个什么都不建的**空** `--script` 跑一遍看基线。
`ObjectDB instances were leaked at exit`、`RID allocations leaked`、
`BUG: Unreferenced static string` 这些在 headless/收尾阶段经常是**引擎自身的噪声**。

**不要只把某一行注释掉就下结论** —— 那一行如果本身是错的（属性名写错之类），
脚本会在那里提前中止，现象看起来完全像「去掉它就不泄漏了」。
（DeepScribe 报告的 `stretch_ratio` 泄漏就是这种情况：`Control` 上根本没有这个属性，
正确的是 `size_flags_stretch_ratio`；用正确属性名实测不泄漏。）
