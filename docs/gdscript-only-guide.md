# 不用 Python 后端：纯 GDScript 方案指引

> 这份文档回答一个问题：**什么时候可以不要 `backend/`，直接在 GDScript 里把事做完；
> 什么时候不该；以及真要做的时候，代码该怎么摆。**
>
> 模板默认是「Godot 前端 + Python 后端」。但一个工控小工具如果只需要读个配置文件、
> 显示几个数值、算点加减乘除，多养一个 Python 进程纯属负担：多一份环境依赖、
> 多一个要打包的东西、多一处会起不来的地方。本文就是给这类项目指路。

---

## 0. 三十秒判断

| 你的计算是什么样 | 结论 |
|---|---|
| 界面逻辑、文件读写、串口/TCP 收发、状态机、定时器 | **纯 GDScript**，不要后端 |
| 几百到几万个点的四则运算 / 简单三角函数 / 查找表 | **纯 GDScript**，见 §3 的实测数字 |
| FFT、卷积、矩阵分解、样条插值、统计检验、微分方程求解 | **要 Python**（numpy/scipy 就是干这个的） |
| 每帧要处理一张图像（逐像素） | **纯 GDScript，但必须走 `Image`/着色器**，见 §3 |
| 计算要跑几分钟、还要能中途取消 | **要 Python**（放到独立进程，UI 才不会被拖住） |
| 要复用已有的 Python 代码/设备 SDK | **要 Python** |
| 想让最终交付只有一个 exe、不装 Python | **纯 GDScript** 是最省事的路（**注意 exe 体积**，见 §5 末条） |

一句话：**算得少就近算，算得多就分家。** 分不分家的判据是「计算量级」和「有没有现成库」，
不是「架构好不好看」。

> 这张表不是纸上推演：`docs/todo.md` 里那些「已完成并验证」的项，大部分就是按这条路
> 做出来的（界面/布局/控件/配置全在 GDScript 里，只有 FFT 那步交给 Python）。
> 唯一的坑是交付体积，见 §5 最后一条。
> 想直接看「纯 GDScript 程序长什么样」：`scenes/gallery.tscn` 本身就是一个 ——
> 它从来不需要后端。

---

## 1. 决定不分家之后：先把「缝」留出来

真正会让你后悔的，不是当初没写后端，而是**把数据入口散落在十个地方**。
将来要接后端时，你得满项目找发送点。

所以即使纯 GDScript，也请照模板的样子留一道缝：

```
界面（按钮/输入框）            ← 只负责收集参数、显示结果
      ↓  send_command("xxx", args)
业务逻辑（本地函数 / 本地引擎）  ← 唯一一处「数据从哪来」的地方
      ↓  _on_data({"type": ..., ...})
界面更新
```

具体做法（模板里就是这个形状，可以照抄 `scripts/main.gd`）：

- **所有「发出请求」都走一个方法**，别在按钮的回调里直接调计算函数：

  ```gdscript
  func _on_start_pressed() -> void:
      var params := _collect_params()
      _send("rs_start", params)          # ← 只有这一处知道「数据从哪来」
  ```

- **所有「收到数据」都走一个分发函数**，用 `type` 字段分派：

  ```gdscript
  func _on_data(payload: Variant) -> void:
      match str(payload.get("type", "")):
          "rs_begin": _on_begin(payload)
          "rs_col":   _on_column(payload)
          "rs_done":  _on_done(payload)
  ```

- 这两处收敛好之后，**把本地实现换成 `NetClient` 就只是改这两个函数体**，
  界面代码一行不用动。这就是为什么这个模板把网络层做成 `NetClient` 单例：
  它是那道缝，不是负担。

> 约定：即使全是本地算，也**建议沿用「发命令 + 回消息」的形态**（带 `type` 字段的字典）。
> 将来接后端时，消息格式不用重新设计，直接就是协议。

---

## 2. 重计算放哪：线程纪律

GDScript 是跑在主线程上的。一个 200 ms 的循环就会让界面卡 200 ms —— 按钮点不动、
进度条不走、窗口被系统标记「无响应」。

**规则：主线程只碰 UI，重活放 `Thread` 或 `WorkerThreadPool`。**

```
主线程                          后台线程
------                          --------
收集参数、置 UI 为「计算中」  →   start()
_process() 里取结果            ←  只往队列里塞结果（加锁）
更新控件 / emit 信号                绝不碰任何节点、信号、场景树
```

最小骨架（这是文档里的示例，不是仓库里的现成程序）：

```gdscript
var _mutex := Mutex.new()
var _queue: Array = []          # 线程产出 → 主线程消费
var _thread: Thread = null


func _start(params: Dictionary) -> void:
	_thread = Thread.new()
	_thread.start(_worker.bind(params))
	set_process(true)           # 开始取结果


## 在后台线程里跑。**这里不要碰任何节点** —— GDScript 跨线程操作场景树是未定义行为。
func _worker(params: Dictionary) -> void:
	for i in params["count"]:
		var value := _heavy_step(i)          # 纯计算，不碰 UI
		_mutex.lock()
		_queue.append({"i": i, "value": value})
		_mutex.unlock()


func _process(_delta: float) -> void:
	var batch: Array = []
	_mutex.lock()
	if not _queue.is_empty():
		batch = _queue
		_queue = []
	_mutex.unlock()
	for entry in batch:
		_some_label.text = "已算 %d" % entry["i"]     # 回到主线程才更新 UI
		_emit_progress(entry)


func _stop() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()      # 必须收尾，否则引擎报「Thread 未正确结束」
	_thread = null
	set_process(false)


func _exit_tree() -> void:
	_stop()                           # 退出场景时也要收，别让它悬着
```

几个真会踩的点：

- **`Thread` 必须在对象被释放前 `wait_to_finish()`**（`_exit_tree()` 里补一刀），
  否则退出时报 `A Thread object is being destroyed without its completion having been realized`。
- **判断线程状态用对方法**：`is_alive()` 是「还在跑」，`is_started()` 是「start 过且尚未
  join」。想跳过阻塞式 join 前先看 `is_alive()`。
- **想省事就用 `WorkerThreadPool.add_group_task()`**：它把线程池和任务切分都包好了，
  适合「把一个大数组切成 N 段并行算」这种规整场景，比手搓 `Thread` 少一半代码。
- **多核只在真的独立时才有用**：GDScript 段之间共享全局状态（autoload、静态变量），
  并行任务里读写它们同样要加锁。

---

## 3. 性能红线（附本机实测数字）

GDScript 比 C++/numpy 慢一到两个数量级。但**慢的是「每单位计算」，不是「每帧能做的事」**——
只要你避开下面几条红线，纯 GDScript 能撑住相当多的界面场景。

本机（Godot 4.7 headless，同一台机器）实测：

| 操作 | 实测 |
|---|---|
| 一次「多项式 + `cos` + 分支」的标量求值 | **约 0.36 µs** |
| 7 469 次这样的求值（97 列 × 77 行） | **约 3 ms** |
| 201 000 次这样的求值（1000 列 × 201 行） | **约 71 ms** |

也就是说：**几十万次简单标量运算，GDScript 是几十毫秒的量级** —— 做界面内的即时预览
完全够用。参考坐标：要在同一台机器上做「1000 个距离 × 两个 1000×1000 复 FFT」，
Python 版 `backend/rayleigh_sommerfeld.py` 要 **117 秒**。这不是「GDScript 比 numpy 快」——
两者的**计算量级完全不同**，这个对比恰恰说明本文的核心判据：
**先看计算量级和要不要 FFT/线性代数，再谈用哪种语言。**

### 红线一：绝不要逐像素循环

```gdscript
# ✗ 这么写，一张 1000×1000 的图要循环一百万次，界面直接卡死
for y in 1000:
	for x in 1000:
		img.set_pixel(x, y, _color_for(data[x][y]))
```

正确的两条路：
1. **上 GPU**：把标量数据当纹理传给着色器，让它在 GPU 上并行上色。
   本项目就是这么做的 —— 见 `scripts/ui/intensity_map.gd` +
   `themes/shaders/colormap.gdshader`：CPU 只负责把数据写进 `Image`，
   「标量 → 颜色」全在着色器里，所以换配色/调伽马只是改一个 uniform。
2. **用引擎的批量接口**：`Image.fill_rect()`、`Image.blit_rect()`、
   `Image.create_from_data()` 这类整块操作是 C++ 实现的，比逐个 `set_pixel()` 快几个数量级。

### 红线二：用 Packed* 数组，不要用 Array

```gdscript
var a := PackedFloat32Array()     # ✓ 连续内存，C++ 侧批量读写
var b: Array = []                 # ✗ 每个元素都是装箱的 Variant
```

`PackedFloat32Array` / `PackedVector2Array` / `PackedByteArray` 传给 `Image`、
`draw_polyline`、网络序列化时都是零拷贝或近似零拷贝；`Array` 则要逐个拆箱。
数字量上千之后差距很明显。

### 红线三：别在每帧的路径上分配

`_process()` 里 `Array`/`Dictionary`/`String` 的创建都是分配。每帧拼字符串、
每帧 `new` 一个容器，积少成多会稳定掉帧。规律是「**算好一次、缓存起来**」——
`IntensityMap` 里 `_dirty` + 「每帧最多上传一次纹理」就是这个思路。

### 红线四：科学计算库是没有的

GDScript **没有** Bessel 函数、FFT、矩阵运算、插值、统计分布、稀疏求解……
标准库只有基础数学。你可以手写（比如用 Abramowitz & Stegun 的多项式近似凑一个
Bessel 出来），但准确度、可维护性、可验证性都要自己扛 —— 写论文/出报告级别的数值
更不该这么干。

**这是「该用 Python」最硬的信号**：一旦你要实现的是一本数值分析教材里的东西，
就去用 numpy/scipy，别在 GDScript 里重新发明它。

---

## 4. 该升级到 Python 后端的时候

出现下面任何一条，就是分家的时候（按模板加 `backend/`，界面不动）：

- 计算时间到了**秒级以上**，或者需要**中途取消/暂停**；
- 需要 numpy / scipy / pandas / matplotlib / 设备厂商的 Python SDK；
- 计算过程要**独立于界面存活**（关掉界面继续跑、或由定时任务拉起）；
- 已经有现成的 Python 代码要复用；
- 需要在**多台机器**上共享同一份计算结果。

迁移步骤（因为 §1 的缝已经留好了，所以很快）：

1. `python tools/new_project.py` 或直接照 `backend/main.py` 建一个后端，实现同样的
   `type` 消息；
2. 把界面里 `_send()` 的实现从「调本地函数」换成 `NetClient.send_command(...)`；
3. 把「本地算完直接改界面」换成「收到 `data_received` 再改界面」；
4. 把重计算的 `Thread` 代码整段搬到 Python 侧。

**界面层不用改**，这正是 §1 那些约定的价值。

---

## 5. 用本模板做纯 GDScript 项目时的取舍

- **可以直接删掉的东西**：`backend/` 整个目录、`project.godot` 的 `[backend]` 段、
  `NetClient` / `BackendLauncher` 两个 autoload，以及 `scripts/main.gd` 里的网络部分。
- **建议保留的东西**：主题系统（`theme_palette.gd` + `theme_factory.gd`）、`scripts/ui/`
  的全部控件、`AppShell`（窗口尺寸 + DPI 缩放 + `user://config.cfg` 记忆）、
  `scenes/gallery.tscn`（控件参照手册）。这些跟后端毫无关系。
- **纯 GDScript 项目的部署优势**：导出一个 exe 就完事，工控机上不用装 Python、
  不用配虚拟环境、不会遇到「服务器上 numpy 版本不对」这类问题。
  这是它最实际的收益。
- **但先掂量一下这个 exe 的体积**：用官方编辑器直接导出，**上 100 MB 是常态**
  （实测约 104 MB）—— 里面塞了 3D、音频、导航、XR、各种图片编解码、联机等等整个引擎。
  这是「要不要用 Godot 替代 Qt/tkinter」这个决策里最现实的反对意见，所以先看分发方式：
  内网 U 盘拷几台机器通常无所谓；要发几十台、或走网络分发，就得考虑下面这条。
  想要合理体积**必须自己编一份精简引擎模板**：关掉用不到的模块 + `disable_3d=yes`
  `optimize=size_extra lto=full`，实测 **104 MB → 34 MB**（压缩包 28 → 9 MB），
  20 核编译约 4 分钟。两个坑：**`module_webp` 绝不能关**（Godot 的纹理导入内部用 WebP
  存 `.ctex`，关了所有贴图都会加载失败），`svg` / `text_server_adv` / `freetype` / `glslang`
  也必须留（图标、中文排版、字体渲染、着色器编译），另外留 `opengl3` 兜底 RDP/虚拟机。
  工具链：`pip install scons` + `winget install BrechtSanders.WinLibs.POSIX.UCRT`
  （**不需要 Visual Studio** —— Godot 官方 Windows 二进制本来就是 MinGW 编的）。
- **一条经验**：本模板的 `scenes/gallery.tscn` 从来不需要后端就能跑 ——
  它就是一个「纯前端 GDScript 程序」的现成例子，可以从它开始改。
