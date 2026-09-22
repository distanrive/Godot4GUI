# 用 Godot4GUI 模板起一个新项目 —— 完整指引

> 本文面向「已有 Godot4GUI，要开一个新工控项目」的场景。
> 目标：**半小时内跑通一条自己的链路**（界面 → 命令 → 后端计算 → 数据回传 → 界面刷新），
> 而不是从零搭主题、控件、WebSocket。
>
> 配套工具：`tools/new_project.py`（脚手架，已实测：生成即能 F5 跑通）。

---

## 0. 三十秒版

```bash
# 在模板项目根目录（Godot4GUI/）里执行
python tools/new_project.py D:\work\MyLab --title "XX 实验台"

cd /d D:\work\MyLab
pip install -r backend/requirements.txt
# 用 Godot 4.7 打开 D:\work\MyLab，按 F5
# 点右上角「启动采集」→ 曲线开始滚动 = 整条链路已通
```

**只开一个终端就行**：前端发现连不上后端，会按 `project.godot` 的 `[backend]` 段自己把它拉起来
（标题栏会显示「正在连接后端…」→「已连接后端（本次自动拉起，pid=…）」）。
想把后端开在另一个终端也可以：`python backend/main.py`，再给前端加 `--no-backend-autostart`。

生成时 `[backend] python=` 已经填成**跑这个脚手架的那个解释器**（比扫 PATH 靠谱）；
换机器时改那一行。

然后照第 4 节改 `scripts/app.gd` 和 `backend/main.py` 即可。

---

## 1. 模板里有什么、你的项目继承什么

模板项目 `Godot4GUI` 分四层，**前两层可以 100% 继承，后两层是你的活**：

| 层 | 内容 | 新项目怎么处理 |
|---|---|---|
| **样式层** | `scripts/theme/theme_palette.gd`（设计令牌）→ `theme_factory.gd`（构建 Theme）→ `ThemeManager` autoload 应用 | **原样继承**，只改 `theme_palette.gd` 里的值 |
| **外壳层** | `app_shell.gd`（窗口最小尺寸 / DPI 缩放 / `user://config.cfg` 记忆）、`ui_scale_option.gd` | **原样继承**；界面里放一个 `UiScaleOption.new()` 就把缩放交给用户 |
| **通信层** | `net_client.gd`（WebSocket 单例、自动重连、JSON 分发）+ `backend_launcher.gd`（连不上就自动拉起后端进程） | **原样继承**，只改协议内容与 `project.godot` 的 `[backend]` 段 |
| **控件层** | `scripts/ui/` 全部 `class_name` 控件 + `themes/`（图标、伪彩着色器） | 直接用；缺什么按第 7 节加 |
| **业务层** | `scenes/app.tscn` + `scripts/app.gd`（页面）、`backend/main.py`（服务） | **你自己写**（脚手架给的是可跑的骨架） |

**不需要 Python 后端**时，外壳层/样式层/控件层照样 100% 继承，只把通信层与业务层的后端部分去掉；
写法和取舍见 `docs/gdscript-only-guide.md`。

数据流长这样，改代码前先记住这张图：

```
   ┌─────────────── Godot 前端 ───────────────┐        ┌──── Python 后端 ────┐
   │ app.gd（页面）                            │        │ main.py             │
   │   │ 用户点按钮                            │        │  Session.handle()   │
   │   ▼                                       │        │    ▲ 收命令          │
   │ NetClient.send_command("xxx", {...})  ────┼── WS ──┼────┘                │
   │   ▲                                       │        │  Session.xxx_loop() │
   │   │ data_received 信号（按 type 分发）      │        │    │ 采集/计算        │
   │ app.gd 更新控件（图表/表格/指示灯…）         │◄── WS ─┼────┘ self.send(...) │
   └───────────────────────────────────────────┘        └─────────────────────┘
```

---

## 2. 脚手架做了什么（`tools/new_project.py`）

```bash
python tools/new_project.py <目标目录> [--name 工程名] [--title 界面标题]
                                       [--no-gallery] [--no-skills] [--force]
```

- `--name` 默认取目标目录名，写入 `project.godot` 的 `config/name`（也是窗口标题）；
- `--title` 显示在界面上（`app.gd` 的标题 + README/CLAUDE 文档）；
- `--no-gallery` 不拷控件总览场景（省 1 个文件，但开发期少了个参照手册，不建议）；
- `--force` 目标目录非空时也继续（覆盖同名文件）。

**原样复制**：`scripts/autoload/`、`scripts/theme/`、`scripts/ui/`、`scripts/util/`、
`themes/`（图标 + 着色器）、`project.godot`（改名后，`[backend] python=` 会改写成本机跑脚手架的那个解释器）、
`backend/requirements.txt`、`scenes/gallery.tscn` + `scripts/gallery.gd`、
`docs/gdscript-only-guide.md`（不需要后端时看这篇）、
`tools/checks/table_actions.gd`（表格行内按钮的回归检查，改表格后跑一下）；
`.claude/skills/`（可选，Claude Code 的开发规范）。

**替换成本项目的骨架**：

| 生成的文件 | 内容 |
|---|---|
| `scenes/app.tscn` + `scripts/app.gd` | 起始页面：标题栏（标题/启动/停止/连接状态）+ 参数侧栏 + 实时折线图 + 日志行 |
| `backend/main.py` | WebSocket 服务骨架：`Session` 类、命令分发、示例数据流、端口占用排查提示 |
| `README.md` / `CLAUDE.md` | 新项目的说明与**开发约定**（约定部分建议保留，见第 7 节） |
| `.gitignore` | Godot/Python/IDE 的忽略规则 |

**不拷贝**（模板特有）：Rayleigh-Sommerfeld 衍射相关的一切（`backend/rayleigh_sommerfeld.py`、
衍射演示的 `main.gd`）、`docs/plotting-alternatives.md`（那篇调研是通用知识，需要就自己拷）。

> 生成后第一次用 Godot 打开时，引擎会导入资源并生成 `.godot/`、`.gd.uid`，属正常现象。
> 用命令行验证项目是否干净：
> ```bash
> godot --headless --path <目标目录> --import                     # 导入 + 刷新类名缓存
> godot --headless --path <目标目录> --quit-after 60              # 跑主场景，看有无报错
> godot --headless --path <目标目录> res://scenes/gallery.tscn --quit-after 60
> ```

---

## 3. 不用脚手架：手工搭建清单

想自己控制每一行的话，按下表拷/改（顺序即依赖顺序）：

1. **拷目录**：`scripts/autoload/`、`scripts/theme/`、`scripts/ui/`、`scripts/util/`、`themes/`
   （连同 `.gd.uid` 一起拷，避免 `.tscn` 里的 uid 引用悬空）。
2. **拷 `project.godot`**，改三处：
   - `config/name="你的工程名"`
   - `config/description="..."`
   - `run/main_scene="res://scenes/app.tscn"`
   并确认 `[autoload]` 四行都在、顺序不要颠倒（`AppShell` 要在 `BackendLauncher` 之前，
   因为后者读前者的配置）：
   ```ini
   [autoload]
   ThemeManager="*res://scripts/autoload/theme_manager.gd"
   NetClient="*res://scripts/autoload/net_client.gd"
   AppShell="*res://scripts/autoload/app_shell.gd"
   BackendLauncher="*res://scripts/autoload/backend_launcher.gd"
   ```
   再补一段**后端启动配置**（`BackendLauncher` 靠它拉起后端，不做 PATH 发现）：
   ```ini
   [backend]
   python="C:/path/to/python.exe"      # 必须显式写；换机器时改这里
   script="res://backend/main.py"
   autostart=true
   kill_on_exit=true
   ```
   渲染器：不用写。Godot 默认就是 `forward_plus` + Windows 上的 `vulkan`（正是我们要的），
   写了也会在编辑器保存时被当成默认值抹掉。
3. **建一个主场景**：`scenes/app.tscn` = 一个 `Control`（锚点铺满）+ 挂 `scripts/app.gd`。
4. **建后端**：`backend/{main.py, requirements.txt}`。
   **别删 `--host` / `--port` / `--log-file` 三个参数** —— 自动拉起时会传它们，
   少了任何一个，argparse 会以 `unrecognized arguments` 直接退出。
5. **拷 `scenes/gallery.tscn` + `scripts/gallery.gd`**（强烈建议）：它是控件参照手册，
   也是新控件的调试台。

---

## 4. 新项目的第一小时：改这四个地方

### 4.1 改界面 —— `scripts/app.gd`

脚手架给的 `_build_ui()` 就是范例（代码建 UI，类 PyQt）。照着改：

```gdscript
func _build_ui() -> void:
	var margin := MarginContainer.new()                      # 页面边距来自主题 PAGE_MARGIN
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)       # 间距可以就地调
	margin.add_child(root)

	var title := Label.new()
	title.text = "激光功率监测"
	title.theme_type_variation = "PageTitle"                 # ← 字号/颜色走主题变体
	root.add_child(title)

	var group := TitledGroup.new()                           # 带标题的卡片
	group.title = "参数"
	root.add_child(group)

	var field := LabeledLineEdit.new()
	field.label_text = "采样率"
	field.text = "1000"
	group.content.add_child(field)

	var chart := TrendChart.new()                            # 实时折线
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.y_min = 0.0
	chart.y_max = 100.0
	root.add_child(chart)
```

控件清单见 `CLAUDE.md`，用法看 `scenes/gallery.tscn`（左边导航按「按钮 / 输入框 / 图表 / …」分类）。

### 4.2 加命令 —— `backend/main.py`

```python
elif cmd == "measure":                       # ← 加在 Session.handle() 的 if/elif 链里
    await self._measure(args)                # 干完活别忘了 log 与错误上报
```

```python
async def _measure(self, args: dict) -> None:
    duration = float(args.get("seconds", 5))
    try:
        for i in range(int(duration * 10)):
            value = read_power_meter()                   # 你的设备/算法
            await self.send({"type": "power", "t": i * 0.1, "v": value})
            await self.send_progress(100.0 * (i + 1) / (duration * 10))
            await asyncio.sleep(0.1)
        await self.send({"type": "result", "message": "测量完成"})
    except Exception as exc:
        await self.send_error(f"测量失败：{exc}")
```

> **阻塞调用要丢线程池**：`await loop.run_in_executor(None, read_serial_blocking, port)`。
> 直接在 `async def` 里写阻塞 IO 会把整个后端（含其它客户端的数据流）卡住。

### 4.3 收数据 —— `scripts/app.gd` 的 `_on_data`

```gdscript
match str(payload.get("type", "")):
	"power":                                    # 后端推来的业务消息
		chart.add_point(float(payload.get("t", 0.0)), float(payload.get("v", 0.0)))
	"result":
		_log(str(payload.get("message", "")))
	"progress":
		progress_bar.value = float(payload.get("value", 0.0))
	"error":                                    # 一定要处理，别让报错石沉大海
		_log("后端报错：" + str(payload.get("message", "")))
```

### 4.4 改样式 —— `scripts/theme/theme_palette.gd`

```gdscript
const ACCENT := Color(0.29, 0.565, 0.85)      # 主色：整站按钮/选中/曲线都跟着变
const FONT_MD := 14                            # 默认正文字号
const PAGE_MARGIN := 16                        # 界面到窗口边缘的距离
const RADIUS_SM := 4                           # 圆角
const SEP_BOX := 8                             # 控件间距
```

改完这一处，按钮、输入框、表格、弹窗、tooltip **全部**跟着变（因为 `ThemeManager` 把构建好的
Theme 挂到了根窗口）。**不要在业务脚本里 `add_theme_font_size_override`**，否则「全局可调」就断了。

---

## 5. 协议设计指引

模板已经定好骨架，照着扩就行：

| 方向 | 消息 | 用途 |
|---|---|---|
| 后端→前端 | `{"type":"sample","x","y"}` | 采样点（TrendChart） |
| | `{"type":"progress","value":0..100}` | 进度条 |
| | `{"type":"ack","id","cmd"}` | 命令回执（前端据此改按钮状态） |
| | `{"type":"error","message"}` | 错误上报（**别只 print 在控制台**） |
| 前端→后端 | `{"type":"hello"}` | 握手 |
| | `{"type":"command","id","cmd","args"}` | 所有控制命令 |

自己加消息时守三条：

1. **一律用 `type` 字段分发**（前后端都 `match`/`if` 一下，别靠字段猜测）。
2. **每条命令都要回 `ack`**（哪怕只是 `{"cmd":"start"}`），前端要拿它更新 UI 状态。
3. **大数组走 base64，别用 JSON 数字数组**：

```python
# 后端
import base64
import numpy as np
payload = base64.b64encode(np.ascontiguousarray(row, dtype=np.float32).tobytes()).decode("ascii")
await self.send({"type": "waveform", "n": row.size, "data": payload})
```

```gdscript
# 前端
var raw := Marshalls.base64_to_raw(str(payload.get("data", "")))
var values := raw.to_float32_array()
```

> 一条 1000 点曲线：base64 约 5.4 KB；写成 JSON 数字数组要 10 KB 以上，解析还慢一个数量级。
> 需要二维图（热力图/伪彩图）用 `IntensityMap`：**逐列追加**，每条消息一列，边算边画。

**长任务要可中断**：后端用 `asyncio.Event` 做取消标志，命令循环里每步检查一次：

```python
async def _measure(self, args):
    cancel = asyncio.Event()
    self._cancel = cancel                     # 让 stop 命令能拿到
    for i in range(steps):
        if cancel.is_set():
            break
        ...                                    # 干活 + 推送
    await self.send({"type": "done", "cancelled": cancel.is_set()})

async def handle(self, msg):
    ...
    elif cmd == "stop":
        if self._cancel: self._cancel.set()    # 只置位，不杀协程
```

CPU 密集的步骤（FFT、大矩阵）要 `await loop.run_in_executor(...)`，
这样事件循环才有机会处理 `stop` 命令 —— 否则界面点「停止」要等这一步算完才响应。

---

## 6. 验证与调试流程

### 6.1 Godot 侧

```bash
GODOT="D:\Program Files\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe"

# 1) 新建了 class_name 脚本后，先刷新全局类名缓存（否则会报 Identifier not declared）
"$GODOT" --headless --path <项目> --import

# 2) 单脚本语法检查
"$GODOT" --headless --path <项目> --check-only --script scripts/app.gd

# 3) 跑主场景 N 帧后退出，看运行期报错（_draw / 信号 / 空引用都会在这里暴露）
"$GODOT" --headless --path <项目> --quit-after 60

# 4) 指定场景跑
"$GODOT" --headless --path <项目> res://scenes/gallery.tscn --quit-after 60
```

> 注意：`--check-only` 解析不了 autoload 里的 `NetClient`（那要跑起来才有），
> 报 `Identifier not found: NetClient` 是正常的 —— 用第 3 条跑场景才准。
>
> 想给场景传参调试，用 `--` 之后的用户参数：
> ```bash
> "$GODOT" --path <项目> res://scenes/app.tscn -- --autostart
> ```
> ```gdscript
> for arg in OS.get_cmdline_user_args():
>     if arg == "--autostart": _autostart = true
> ```

### 6.2 后端侧（不开前端也能测）

写个一次性客户端脚本，直接验协议（比开 GUI 快得多）：

```python
import asyncio, json, websockets

async def main():
    async with websockets.connect("ws://127.0.0.1:8765") as ws:
        await ws.send(json.dumps({"type": "hello"}))
        await ws.send(json.dumps({"type": "command", "id": 1, "cmd": "measure",
                                  "args": {"seconds": 2}}))
        while True:
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=10))
            print(msg.get("type"), str(msg)[:100])
            if msg.get("type") == "result":
                break

asyncio.run(main())
```

### 6.3 把 gallery 当控件试验台

加新控件（或调样式）时，先在 `scripts/gallery.gd` 对应分类里加一段——
能立刻看到效果、且不影响业务页面；确认满意再往 `app.gd` 里用。

---

## 7. 加一个新控件（什么时候加、怎么加）

**先别急着写**：Godot 原生 `Button/LineEdit/SpinBox/OptionButton/CheckBox/HSlider/ProgressBar/
Tree/ItemList/TabContainer/SplitContainer/PopupMenu` + 全局主题，已经覆盖 80% 的工控界面。
只有下面三种情况才自绘：

1. 原生没有（开关 `Switch`、环形进度、分段指示灯、闪烁标签）；
2. 原生有的能力不够（`Tree` 不支持拖拽调列宽 → `DataTable`；图表 → `TrendChart`/`IntensityMap`；
   文件拖放 → `FileDropBox`）；
3. 交互形态特殊（长按防误触 `LongPressButton`）。

加的时候守四条约定（模板里的控件都这么写）：

```gdscript
class_name MyGauge                     # 1) 全局唯一的 class_name
extends Control

@export var value := 0.0:
	set(v):
		value = v
		queue_redraw()                 # 2) 数据变了就重绘

func _init() -> void:                  # 3) 复合控件的子节点在 _init 里建
	add_child(_label)                  #    （保证 new() 之后就能访问，不用等入树）

func _theme_color(name: StringName, fallback: Color) -> Color:   # 4) 颜色走主题类型
	return get_theme_color(name, &"MyGauge") if has_theme_color(name, &"MyGauge") else fallback
```

然后在 `theme_factory.gd` 的 `_custom_types()` 里注册颜色/字号：

```gdscript
t.set_color("track_color", "MyGauge", ThemePalette.SURFACE_ALT)
t.set_color("value_color", "MyGauge", ThemePalette.ACCENT)
t.set_font_size("label_font_size", "MyGauge", ThemePalette.FONT_SM)
```

最后在 `gallery.gd` 里加一节（方便以后所有人查用法），并在 `CLAUDE.md` 的控件表里补一行。

---

## 8. 上线/部署注意

- **渲染器**：`forward_plus` + Windows 上的默认驱动 `vulkan`，给 3D 图表留路，实验室机器 GTX 900 系起即可。
  （Godot 4.6 起新建工程在 Windows 上会给 `d3d12`，本项目刻意不用 —— 对老机器太新；
  要 d3d12 就显式写 `rendering/rendering_device/driver.windows="d3d12"`，不写即 vulkan。
  **Godot 4 没有 D3D11 驱动**，想走更老的 D3D 路径只能用 `opengl3_angle` + `gl_compatibility`。）
  若目标机器是 RDP / 虚拟机 / 老 Intel 核显且**启动即崩或黑屏**，回退 `gl_compatibility`：
  命令行 `--rendering-method gl_compatibility`（临时验证），或项目设置 Rendering → Renderer 改（永久）。
  Vulkan 不可用时引擎会按 `fallback_to_opengl3`（默认开）自动降级。
- **后端不用手动开**：`BackendLauncher` 会按 `project.godot` 的 `[backend]` 段自动拉起。
  换机器时改这一段里的 `python`（绝对路径）与 `script`；也可以在 `user://config.cfg` 的
  `[backend]` 段覆盖（不动仓库）。**刻意不做 PATH 自动发现** —— 工控机多版本 Python 是常态，
  静默挑错解释器只会让后端悄无声息地起不来。
- **后端跑成后台服务**（不想让前端管进程时）：`pythonw backend/main.py` 可无窗口运行，
  要开机自启就做个计划任务；前端加 `--no-backend-autostart`。端口被占用时脚本会打印排查指引
  （`netstat -ano | findstr :8765` + `taskkill`）。
- **后端日志**：`--log-file <路径>` 会把 print 同时写进文件（前端自动拉起时就是这么传的，
  因为它读不到脱离进程的 stdout）。失败时 `BackendLauncher` 会把日志尾部摆到界面上。
  要更正式就自己接 `logging`。
- **打包前端**：Godot 导出 Windows 可执行文件（需要 Export Templates）。
  导出后 `res://` 变成只读包：别把运行期要写的数据放进 `res://`，用 `user://`；
  后端脚本 `res://backend/main.py` 在导出包里**不存在**（`.py` 不进 pck），
  要把 `backend/` 目录**随 exe 一起拷过去** —— `BackendLauncher` 会依次找
  `res://backend/main.py`（开发期）和「exe 同级的 `backend/main.py`」（部署期）。
- **后端不在同一台机器**：改 `NetClient.url`（`scripts/autoload/net_client.gd` 的 `@export`），
  并在后端 `--host 0.0.0.0` 监听。注意这是**明文 ws**，跨机务必只在内网用。
  （`BackendLauncher` 的 host/port 是从 `NetClient.url` 解析的，不用两处改。）
- **断线重连**：`NetClient` 已内建（`auto_reconnect`，默认 2s 一次）。业务侧只要按
  `connected`/`disconnected` 信号更新状态灯即可，不用自己写重连。
- **窗口与高 DPI**：拉伸模式是 `disabled` + `AppShell` 按 DPI 设 `content_scale_factor`，
  所以最大化时是「显示更多内容」而不是整体放大。要给用户留缩放档位就放一个
  `UiScaleOption.new()`；它会记进 `user://config.cfg`。

---

## 9. 踩坑速查（新项目最容易撞的）

| 现象 | 原因 / 解法 |
|---|---|
| 整个界面是引擎默认灰样式 | 主题没生效。**Control 的父链里不能夹普通 `Node`**（比如测试脚本包了一层 Node），Autoload 名称/路径对不对、`ThemeManager` 有没有在 `_ready` 里 `get_tree().root.theme = t` |
| `Identifier not found: NetClient` | 在 `--check-only` 单脚本模式下 autoload 不加载，正常；跑场景验证 |
| `Identifier "Xxx" not declared` | 新建的 `class_name` 还没进缓存，跑一次 `--import` |
| 自定义着色器「没生效」 | canvas_item 里 `COLOR` **已经乘过纹理采样**：写 `COLOR = vec4(c, 1.0);`，别写 `* COLOR` |
| 伪彩图一片糊/有条带 | 浮点纹理用 `TEXTURE_FILTER_NEAREST`；老 GPU 缺 `OES_texture_float_linear` |
| 控件里数据填了却不显示 | 控件的 `_ready()` 里别无脑 `set_process(false)`（数据可能是入树前填的） |
| 中文/科学计数法格式报错 | GDScript 的 `%` **不支持 `%e`/`%g`**，用 `Fmt.num()` / `Fmt.sci()` |
| 文件对话框选不了文件 | `FileDialog.file_mode` 默认是 `FILE_MODE_SAVE_FILE`，要显式设 `FILE_MODE_OPEN_FILE` |
| 报警文字越看越暗 | 别用 `modulate` 改颜色，用 `FlashLabel` 或 `font_color`（modulate 是相乘） |
| 表格拖不动列宽 | Godot 的 `Tree` 不支持，用本项目 `DataTable`；要层级就用 `TreeTable` |
| 伪彩图整幅全黑 | 只清了显示范围没复位 `auto_range`（`vmax` 落到 `1e-30`）。用 `_reset_range()` 一次性复位两件事 |
| 关窗时弹「与后端断开连接」 | 收尾顺序反了：先 `NetClient.begin_shutdown()` 再杀后端进程，否则后端一死被读成「崩了」 |
| 退出后残留 python 进程 | `OS.create_process` 起的进程不随 Godot 退出；要么 `_exit_tree` 里 `OS.kill(pid)`，要么接受它 |
| 高 DPI 屏上字太小 / 最大化后界面被放大 | 拉伸模式应为 `disabled`，缩放走 `AppShell` 的 `content_scale_factor`（`screen_get_scale()` 在 Windows 上恒为 1.0，要回退到 `screen_get_dpi()/96`） |
| 画面卡顿/界面假死 | 后端在事件循环里写了阻塞调用，丢 `run_in_executor` |
| 端口被占用 | `python backend/main.py --port 9001`，或 `taskkill` 掉旧进程 |

---

## 10. 什么时候**不**用这个模板

- 要做 3D 可视化/仿真界面 → 用 Godot 但别用这套 2D 控件，主题系统仍可复用
  （渲染器已是 `forward_plus`，3D 可直接上手）；
- 要 Web/远程访问 → 这套是**本地 WebSocket + 桌面窗口**，不适合浏览器交付；
- 纯离线数据分析 → 直接用 Python（matplotlib/pyqtgraph 都行），不必上前后端；
- **不需要 Python 后端**（纯界面/IO/轻计算，想交付单个 exe）→ **模板照用，只是把后端去掉**：
  删 `backend/`、`[backend]` 段和 `NetClient`/`BackendLauncher`，保留主题与控件库；
  写法、线程纪律、性能红线和「以后想加后端怎么留缝」见 **`docs/gdscript-only-guide.md`**；
- 团队已有 Qt 资产且不打算换 → 迁移成本主要在控件重写，先看 `docs/siliconui-godot-mapping.md`
  的对照表评估工作量（该文件在模板仓库中被 .gitignore 排除，属本地参考）。

---

## 附：模板维护者备忘

- 模板自身升级（新增控件/令牌）后，新项目**不会**自动获得——脚手架是「拷一份」，不是「依赖」。
  想同步：把新控件文件拷进新项目，并同步 `theme_factory.gd` / `theme_palette.gd` 的对应片段。
- 改模板的 `scripts/ui/`、`scripts/theme/` 时请顺手更新 `tools/skeleton/CLAUDE.md` 的控件表，
  否则新项目拿到的文档会落后。
- 脚手架自测（改完 `tools/` 必跑一遍）：
  ```bash
  python tools/new_project.py D:\tmp\scaffold_check --title "自测"
  godot --headless --path D:\tmp\scaffold_check --import
  godot --headless --path D:\tmp\scaffold_check --quit-after 60
  ```
  主场景跑完**不应有任何 ERROR**（只有 `[NetClient] 正在连接…` 属正常）。
