# 待办与交接

> 更新：2026-09-21
> **新会话从这里读起**：`CLAUDE.md`（开发约定）→ 本文（当前状态 + 待办 + 未决问题）→
> `docs/new-project-guide.md`（要用本模板起新项目时看）、
> `docs/gdscript-only-guide.md`（不要 Python 后端时看）。

---

## 0. 一分钟交接

- **项目现状**：Godot 前端 + Python 后端的工控 GUI 模板已完整可用 ——
  主题系统、自绘控件库（`scripts/ui/` 共 18 个脚本）、WebSocket 通信骨架与后端自动拉起、
  窗口/DPI 适配、一个真实数值算例（Rayleigh-Sommerfeld 衍射逐距离刷新）、
  以及「一条命令生成新项目」的脚手架。
- **最重要的三个入口**：
  - 看控件/改样式：跑 `scenes/gallery.tscn`（无需后端）
  - 看完整链路：跑 `scenes/main.tscn`（F5 即可，后端会自己起来）
  - 不用 Python 的写法：`docs/gdscript-only-guide.md`
- **改自绘控件时，用「自截图 + 放大」验收**（光跑 headless 不报错不代表画对了 —— 表格被裁、
  树线悬空这类问题 headless 一点错都不报）。做法：写个临时 `extends SceneTree` 脚本，
  `root.add_child()` 控件 → `await process_frame` 若干帧 → `root.get_texture().get_image().save_png("user://shot.png")`，
  用 `godot --path . --script res://tools/_tmp_shot.gd`（**不要加 `--headless`**，headless 没有渲染结果），
  再用 PIL 裁切放大细看。窗口高不过 800px 时内容会被截掉，可把控件单独拿出来渲染。
- **机器环境**（本机自测用）：Godot 在 `D:\Program Files\Godot_v4.7.2-stable_win64\`，
  Python 用 `C:\Users\YH\.conda\envs\normal\python.exe`（已写进 `project.godot` 的 `[backend] python`）。
  本机显示器是 **2560 宽 / Windows 缩放 125%（AppliedDPI=120）**，所以界面缩放自动值为 1.25×。
- **⚠️ 本机 headless 帧率只有约 140 fps**：`--quit-after N` 的 N 别乱写大数
  （60000 帧 ≈ 7 分钟）。自测用 `--quit-after 90~150` 看报错、`3000~4000` 跑完整链路。
- **`project.godot` 被编辑器重写过后是「极简」的**：只剩非默认项。上面那些渲染器/拉伸模式
  因为值等于引擎默认，文件里**看不到**（这是正常的，别去补写回来，编辑器保存一次又会抹掉）。
- **git 基线**：`9b3a2d9`。**工作区尚未提交** —— 2026-09-21 两批改动（第 1 节 13~22 项）
  都在工作区里，新会话接手时先 `git status` 看一眼、确认这批改动是否已经提交过。
- **未提交的改动清单**：16 个文件修改 + 9 个新文件（`app_shell.gd`、`backend_launcher.gd`、
  `column_table.gd`、`tree_table.gd`、`tree_table_item.gd`、`ui_scale_option.gd`、
  `docs/gdscript-only-guide.md`、`docs/todo.md`、以及两个关闭图标）。

---

## 1. 已完成并验证（附验证方式）

| # | 事项 | 怎么验证的 | 结果 |
|---|---|---|---|
| 1 | **数值与原作业脚本一致** | `Simulation` vs 原脚本算法逐点比对（同一参数、前 5 个 z） | **最大误差 0.0（逐位一致）** |
| 2 | **全量衍射跑通**（N=1000、1000 个距离） | 后端 + 前端实跑并截图比对 matplotlib 原图 | 117.6 s 跑完 1000 列；图样结构/配色/坐标范围与原图一致 |
| 3 | 色彩与 matplotlib 一致 | `Colormaps.rainbow` 与原版 256 级 LUT 逐点比对 | **三通道最大误差 0** |
| 4 | 前端逐列刷新 | 快速预设（N=384、z 步进 4）：97 列 | 1.5 s 出完整图，无卡顿/无报错 |
| 5 | 协议全链路 | 独立 WebSocket 客户端跑 `rs_params`/`rs_begin`/`rs_col`/`rs_done` | 全部按预期返回；`rs_stop` 可中断 |
| 6 | 拖放文件 → 参数回读 → 回填输入框 | 程序化把作业脚本 .py 交给 `FileDropBox.set_path()` | 后端用 `ast` 解析出常量（不执行文件），参数栏被正确填充 |
| 7 | `FileDropBox` 虚线外框 + 选择文件对话框 | 截图 + 打开对话框截图 | 圆角虚线框、悬停高亮、过滤器/打开模式均正确 |
| 8 | `IntensityMap` 渲染与交互 | 截图（衍射图 + gallery 演示数据） | 坐标轴、色标条、悬停十字线读数、等比 letterbox 均正常 |
| 9 | 主题全局生效 + 语义变体 | 截图逐分类检查 gallery | 样式统一 |
| 10 | 对话框标题栏统一 | 截图 `ConfirmationDialog` | 浅色标题栏 + 深色关闭图标 + 投影 |
| 11 | **脚手架** | 生成到临时目录 → `--import` → 跑主场景 → 连后端发命令 | 生成 0 错误，主场景无报错 |
| 12 | 脚手架不污染模板 | `tools/skeleton/.gdignore` + 模板 `--import`/跑场景 | 模板工程不受影响 |
| 13 | **`ColumnTable` 抽取 + `TreeTable` 新控件** | 临时 headless 自检脚本，**30 条断言全过**：列宽拖拽（含下限钳制、表体不误触）、末列填满、按行数自动高度、层级深度、展开/收起后的可见行数、点行选中、点箭头展开、折叠时自动取消隐藏行的选中、`remove()` 连带子树并清掉其中的选中项、`clear_items()`、`set_all_expanded()` | 全过；`DataTable` 公开 API 与绘制行为**不变** |
| 13b | **表格显示缺陷（你指出的，共两轮）** | 自绘控件**截图**后逐张放大比对：`--script` 里 `get_viewport().get_texture().save_png()`，再用 PIL 裁切+放大 | 见下 B4，已**肉眼确认** |
| 13c | 第一轮：① DataTable 被裁、② 三张卡片挤在一起、③ 箭头与手写的 `└` 重复 | 同上 | 都修好：高度改走 `_get_minimum_size()`；拆成 ItemList / DataTable / TreeTable 三张卡片；演示数据不再手写层级符号 |
| 13d | 第二轮：④ 树线在「最后一个子项」的子树里悬空多画一条 | 同上 | 修好。规则我写错过两次，见下面「关键决定记录」里那一条 |
| 13e | **验证用的截图脚本是临时的，已删** | —— | 自绘控件的布局问题**跑 headless 不报错也算不出来**，以后改 `TABLE_INDENT`/`TABLE_ARROW_W`/行高，建议照上面这套再截一次图 |
| 14 | **TreeTable 不泄漏内存** | 同一自检脚本发现「7 ObjectDB instances were leaked at exit」→ 改用 `Object` 显式所有权后重跑 | 泄漏归零。**踩到的坑**：`RefCounted` + 父子互引 = 引用环，引用计数永不回收；且 GDScript **不允许对象在自己的调用栈里 free 自己**（`Attempted to free a locked object`），故 `remove()` 把自己交给表去 `call_deferred("free")` |
| 15 | **后端自动拉起（端到端）** | 清空端口占用 → 直接 `godot scenes/main.tscn -- --preset=fast --autostart` | 前端自动拉起 python（pid 记录在案）→ `hello_ack` 通过 → 97 列 / 1.5 s 跑完；**退出后端口释放、python 进程数归零**（`kill_on_exit` 生效） |
| 16 | **脚手架项目也能自动拉起** | 生成新项目 → `--import` → 跑主场景 | `[app] 已连接后端。`，端口随后释放。**这条抓到一个真 bug**：骨架后端原来没有 `--log-file` 参数，argparse 会报 `unrecognized arguments` → 所有新生成项目的自动拉起都会失败（已修，并补上 `hello_ack`） |
| 17 | **界面缩放/窗口恢复（三条来源 + 回退）** | 非 headless 实跑，看 `[AppShell]` 启动行与窗口实际尺寸 | 跟随系统 → 1.25×（与本机 `AppliedDPI=0x78=120` **完全吻合**）；`--ui-scale=1.5` → 1.50× 且窗口 1536×960；`config.cfg` 写 `scale=1.0/1700×1000` → 恢复成 1700×1000；`--reset-window` → 忽略几何回到 1280×800；最小窗口随缩放 1024×640 ↔ 1280×800 |
| 18 | **渲染器换成 forward_plus** | 非 headless 实跑，看引擎首行 | `Vulkan 1.3.280 - Forward+ - Using Device #0: NVIDIA GeForce RTX 4060`。伪彩图是 canvas_item 着色器，两种渲染器下表现一致 |
| 19 | 收尾顺序修复（关窗不再误报断线） | 对比修复前后的完整运行日志 | 修复前：每次正常退出都打「与后端断开连接」并重连一次；修复后：0 次 |
| 20 | 空闲连接不会掉线（澄清一个假警报） | 手工起后端 + 前端空闲跑 70 s，统计「与后端断开连接」次数 | **0 次**。此前观察到的「20 秒断一次」是我自己并发跑多个测试实例造成的假象，不是缺陷 |
| 21 | `--log-file` 与 `hello_ack` | 后端日志实际内容 | 会话头 + 监听 + 客户端接入 + 命令全都有留档；`hello_ack` 让前端能确认端口上是自己的后端 |
| 22 | 冒烟检查（改完必跑的那套） | `--import`、`gallery --quit-after 90`、`main --quit-after 90 -- --no-backend-autostart` | 全部无 ERROR |

---

## 2. 待办

### A. 需要你拍板（阻塞后续决定）

| # | 问题 | 背景 | 我的建议 |
|---|---|---|---|
| A1 | `docs/siliconui-godot-mapping.md` 被 `.gitignore` 单独排除（且已随 `9b3a2d9` 提交），确认是**有意为之**吗？ | 该文件是 PyQt-SiliconUI（GPLv3）的迁移对照表，排除很可能是为了许可隔离；代价是团队成员拿不到它，而 `docs/new-project-guide.md` 第 10 节又提到了它 | 若有意：保持现状，指引里已注明「本地参考、未入库」；若只是不想让它进公开仓库，可改放进一个明确标注的本地目录（如 `docs/local/`） |
| A2 | 衍射演示的**默认参数**要不要改成「快速预览」？ | 现在默认 = 原作业参数（N=1000），第一次跑要等约 2 分钟才出完整图；快速预设只要 1.5 s | 演示用默认快速预设、把「原参数」留给「要出正式图」的场景；但这偏离「忠实复现作业」的初衷，故留给你定 |
| A3 | `tools/skeleton/.gdignore` 是**死文件**：它在骨架目录里存在，但 `new_project.py` 的 `SKELETON_FILES` / `SKELETON_RENAMES` 都没引用它，所以永远不会被拷进新项目 | 要么是当初写漏了，要么是后来改了复制机制忘了删 | 删掉它（模板自身的 `.godot/` 排除靠别的机制）；除非你记得它有用 |

### B. 待补验证（代码已写，但没法在无头/无交互环境里确认）

| # | 事项 | 怎么验 |
|---|---|---|
| B1 | `FileDropBox` 的**原生**对话框路径（`use_native_dialog = true`，默认值） | 真机上点「选择文件…」，确认弹出的是 Windows 资源管理器；若在 RDP/无桌面环境异常，把默认改成 `false` |
| B2 | `PopupMenu` 的主题目视确认 | 在**有窗口焦点**的交互会话里点 gallery 的「弹出菜单」按钮（自动化截图环境里弹窗因无焦点会立即隐藏，属环境限制） |
| B3 | **`forward_plus` 下伪彩图的目视确认** | 我已经确认引擎起来了（Vulkan/Forward+），但**没有亲眼比对过换渲染器前后的图像颜色**。请在真机上跑一次快速预设，确认配色与之前一致 |
| B4 | ~~`TreeTable` 的目视效果~~ | **已办**：2026-09-21 用视口截图 + 局部放大确认过（四处显示缺陷就是这一步发现的）。引导线的修法是在**隔离场景**里放同一个控件+同一份数据确认的（`└` 收口、`├` 贯穿、最后一个子项子树里无线）；gallery 里这棵树在第三张卡片，800px 窗口截不全，所以没在 gallery 里逐行肉眼过一遍 —— 同一控件同一数据，风险很低。后续若有人调 `TABLE_INDENT` / `TABLE_ARROW_W` / 行高，建议照第 0 节那套再截一次图 |
| B5 | 布局在**最大化**下的表现 | 拉伸模式已改 `disabled`，理论上最大化是「显示更多内容」；请在真机上拖动窗口确认伪彩图与参数栏的重排符合预期 |
| B6 | Windows 导出流程 | 导出 exe（需 Export Templates）+ 后端打包。重点：`backend/` 目录要**随 exe 一起拷**（`res://` 里没有 `.py`），`BackendLauncher` 会找「exe 同级 `backend/main.py`」 |
| B7 | 小窗口布局 | 最小窗口现在是 `WINDOW_MIN_W/H`（1024×640，随缩放），比它更小拖不动了。到 1024×640 时左侧参数栏会出现滚动条（功能正常，未细调）；嫌挤就调 `theme_palette.gd` 的 `SIDEBAR_W` / `WINDOW_MIN_*` |

### C. 功能补全（P1，建议优先做）

| # | 事项 | 说明 |
|---|---|---|
| C1 | `tools/smoke_test.py` | 把「`--import` + 跑两个场景 + gallery 全分类构建 + 后端协议自测 + 脚手架生成自测」固化成一条命令。**建议把第 13 项那 30 条表格断言也收进去**（那次是临时脚本、跑完删了，结论只留在第 1 节；进了 C1 才能长期回归） |
| C2 | 「配置后端…」对话框 | 现在换机器只能改 `project.godot` 的 `[backend]` 段，或业务侧调 `BackendLauncher.configure(python, script)`。可做一个 `FileDropBox` 选 python.exe / backend 脚本的对话框，写进 `user://config.cfg` |
| C3 | 参数持久化 | 演示页/业务页的输入参数存 `user://config.cfg`（`AppShell.config` 已经是统一落点，加段即可），重启不丢 |
| C4 | `IntensityMap.save_png()` | 导出当前伪彩图（含坐标轴与色标条） |

### D. 可选增强（P2）

- D1 等值线（marching squares 自绘，约 100 行）
- D2 `TrendChart` 加游标/十字线读数（目前只有 `IntensityMap` 有）
- D3 曲线/数据导出 CSV
- D4 多语言（现在界面文案是硬编码中文，可切到 Godot 的 `tr()` + 翻译资源）
- D5 `TreeTable` 加复选框列 / 图标列

---

## 3. 已知限制（不是缺陷，但要知道）

1. **默认参数下首次出图约 2 分钟**：物理本身如此（1000 个距离 × 两个 1000×1000 复 FFT）。
2. **前端被强杀时后端会变成孤儿进程**：`OS.create_process` 起的进程不随父进程结束，
   正常退出（点关闭/Alt+F4/`--quit-after`）会由 `_exit_tree` 收掉，但 `taskkill /F` 掉 Godot
   就来不及收。这是 `create_process` 的固有性质，不是 bug；要彻底避免就让后端自己跑成服务
   （`--no-backend-autostart` + 计划任务）。
3. **端口上已有后端时前端「只连不管」**：不越权去杀别人的进程，所以那个后端不会被 `kill_on_exit` 收掉。
4. **`PopupMenu` 在无窗口焦点的自动化环境里会立即隐藏**（见 B2）。
5. **等比显示时上下留白较大**：数据本身是 100 μm × 20 μm（5:1），工具条上的「等比」开关可关掉。
6. **`docs/plotting-alternatives.md` 里的第三方 addon 链接会随时间失效**，属调研快照。
7. 模板是「拷一份」而不是「依赖」：模板升级后已有新项目**不会**自动获得（见第 4 节）。

---

## 4. 关键决定记录（为什么是现在这样）

| 决定 | 理由 |
|---|---|
| 颜色在前端 GPU 上算，后端只传标量 | 后端出图会变成瓶颈（一帧 PNG 比一列 FFT 还贵）、交互全丢、依赖变重 |
| 强度数据用 `FORMAT_RF` + `NEAREST` | 光强动态范围跨 6 个数量级，量化会有色带；NEAREST 既逐格显示又避开老 GPU 的浮点线性过滤扩展问题 |
| 色标自己实现而不是引色彩库 | matplotlib 的 `rainbow` 是解析式，复刻后误差为 0，且后端不必依赖 matplotlib |
| 参数文件用 `ast` 只解析字面量、不执行 | 用户会拖入任意 .py；执行它等于任意代码执行 |
| 脚手架「拷一份」而非做成 Godot 插件/包 | 工控项目通常要长期就地改控件；插件式会让「改一个控件」变成「改公共库」 |
| 主题只允许改 `theme_palette.gd` | 否则「全局可调」会被 per-control 补丁一点点侵蚀 |
| 保留 gallery 场景 | 它同时是「控件参照手册」和「新控件试验台」 |
| 衍射演示保留 matplotlib 出图的原脚本 | 报告出图仍以 matplotlib 更合适；两套并存 |
| **渲染器换 `forward_plus`，但 Windows 驱动留在默认的 `vulkan`（不用 d3d12）** | 为后续 3D 图表留路；d3d12 虽是新工程的默认（Godot 4.6+），但对实验室老机器太新，vulkan 才是 Godot 4 长期默认、GTX 900 系起就支持的路径。`fallback_to_opengl3` 默认开，Vulkan 不可用会自动降级 |
| **不追求 D3D11** | **Godot 4 根本没有 D3D11 渲染驱动**（RenderingDevice 只有 metal/vulkan/d3d12）。唯一沾 D3D11 的是 `opengl3_angle`，但要配 `gl_compatibility`、等于放弃 forward_plus。所以「更老的 D3D 路径」不等于「换个驱动名」，只能整体退到 gl_compatibility |
| **拉伸模式 `disabled` + `content_scale_factor` 做缩放** | Godot 官方对「非游戏应用」的建议；这样最大化是「显示更多内容」而不是把界面整体放大 |
| **Windows 上缩放靠 `screen_get_dpi()/96` 猜** | `screen_get_scale()` 在 Windows 上恒返回 1.0（官方文档明确未实现），只靠它等于永远不缩放。实测本机 120 dpi ↔ 系统 125%，吻合 |
| **后端 Python 环境与脚本路径显式写进 `project.godot` 的 `[backend]` 段，不做 PATH 发现** | 工控机上多版本 Python 是常态，静默挑中一个缺 numpy/scipy 的解释器只会让后端悄无声息地起不来 |
| **拉起前先验依赖、失败时回显后端日志尾部** | 脱离进程的 stdout 没人接，不主动留证据就查不出「为什么起不来」 |
| **`BackendBus` 基类被撤销** | 一度为「本地引擎」抽象了共同接口，但那个引擎最终按需求改成只给文档（不做成品程序），于是它成了没有第二个实现的空壳。教训：抽象要等第二个实现真出现 |
| **不用 Python 后端只给文档、不做成品范例** | 需求是「指引」；把它做成可运行程序会引入一套只有演示价值的代码（且要跟着模板长期维护） |
| **表格高度走 `Control._get_minimum_size()`，不走 `custom_minimum_size.y`** | 容器取的是「自定义最小尺寸」与「`_get_minimum_size()`」的**大者**，所以调用方怎么写 `custom_minimum_size` 都不会把自动高度弄丢。之前是自己写 `custom_minimum_size.y`，被调用方一句 `custom_minimum_size = Vector2(390, 0)` 清零，表格就画到自己的矩形之外去了 |
| **树线收口规则：某层在它「最后一个子项」那一行收成 └，那个子项的子树里就**不再画这一层**的线** | 这条规则我写错过**两次**，值得记下来：<br>① 先写成「(该层祖先) 后面还有没有兄弟」—— 问错了对象，线会在每行提前收口；<br>② 再写成「一直画到该祖先子树的最后一行」—— 结果 `└─ a2` 之后，a2 的子树里还挂着一条悬空竖线（用户一眼就看出来了）。<br>正确形态是经典树线的样子：`└─ a2` 那一行就是这层的终点，它下面只有缩进空白、没有线。<br>实现见 `tree_table.gd` 的 `_guide_bottom()`：返回「贯穿 / 收成 └ / 本行不画」三态，靠「本行是从哪个兄弟分出来的、它后面还有没有兄弟」判断 |

---

## 5. 常用命令速查

```bash
# ---- 本机环境 ----
GODOT="D:\Program Files\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe"
PY="C:\Users\YH\.conda\envs\normal\python.exe"

# ---- 跑演示（后端会自动起来，不用单开终端）----
"$GODOT" --path . res://scenes/main.tscn                # 前端（或编辑器里 F5）
"$GODOT" --path . res://scenes/main.tscn -- --preset=fast --autostart   # 1.5 s 出图
"$GODOT" --path . res://scenes/gallery.tscn             # 控件总览（无需后端）

# 手动开后端 / 前端不插手
"$PY" backend/main.py                                   # 只开后端（可加 --log-file x.log）
"$GODOT" --path . res://scenes/main.tscn -- --no-backend-autostart

# 界面缩放（本机跟随系统 = 1.25×）
"$GODOT" --path . res://scenes/gallery.tscn -- --ui-scale=1.5    # 临时覆盖，不写回配置
"$GODOT" --path . res://scenes/gallery.tscn -- --reset-window    # 忽略记忆的窗口几何

# 老机器渲染器回退
"$GODOT" --rendering-method gl_compatibility --path . res://scenes/main.tscn

# ---- 自测（注意 headless 只有约 140 fps，帧数别写大）----
"$GODOT" --headless --path . --import                                   # 新建 class_name 后必跑
"$GODOT" --headless --path . --check-only --script scripts/ui/xxx.gd    # 单脚本语法
"$GODOT" --headless --path . --quit-after 90                            # 跑主场景看报错
"$GODOT" --headless --path . res://scenes/gallery.tscn --quit-after 90
"$GODOT" --headless --path . --quit-after 4000 -- --preset=fast --autostart   # 完整链路（约 28 s）

# ---- 自绘控件的目视验收（改控件/布局后强烈建议）----
# 写个临时 extends SceneTree 脚本：add_child 控件 → await 若干帧 → save_png("user://shot.png")
# 注意**不要加 --headless**（headless 没有渲染结果，存出来是空的）
"$GODOT" --path . --script res://tools/_tmp_shot.gd
# 再用 PIL 裁切+放大细看（放大倍数给大点，引导线/1px 边框这种问题要放大才看得见）
#   python -c "from PIL import Image; ..."

# ---- 起新项目 ----
"$PY" tools/new_project.py D:/work/MyLab --title "XX 实验台"

# ---- 端口被占用 / 残留进程 ----
netstat -ano | findstr :8765      # 看最后一列 PID
taskkill /F /PID <pid>
```

**改完代码的最小验收清单**：

1. `--import` 无错误；
2. 主场景 `--quit-after 90` 无 ERROR（只有 `[NetClient] 正在连接…` 属正常）；
3. `gallery` 同样无 ERROR —— **注意 gallery 的分类是懒构建的，默认只建「按钮」那一节**，
   所以这条**覆盖不到** TreeTable / IntensityMap / 弹窗那些代码。要覆盖就写个临时脚本
   逐个 `_show_section(id)` 切一遍（9 个分类），或者干脆用上面的自截图办法看一眼；
4. 涉及后端的改动：跑一次「快速预设」端到端（`--quit-after 4000`，约 28 s），
   确认「已连接后端 → 计算完成」，**并检查退出后 `netstat` 里 8765 已释放**；
5. 改了 `tools/` 的：按上面「起新项目」生成一个临时项目再走一遍 1~3
   （**新项目的自动拉起也要确认**：主场景日志里出现「已连接后端」才算过）；
6. **改了任何自绘控件 / 布局**：按「自绘控件的目视验收」截一张图放大看 ——
   headless 不报错不代表画对了（表格被裁、树线悬空这类问题它一声不响）。
