# 替代 matplotlib 的调研与选型

> 起因：`Rayleigh-Sommerfeld-assignment1.py` 用 matplotlib 出「一张静态图」——
> 1000 个距离全算完，`pcolormesh` 画一张 Z-Y 衍射图样，`plt.show()` 结束。
> 搬进工控 GUI 后需求变了：
> **① 每算出一个距离就刷新图像；② 能交互（换配色、缩放、读数）；③ 后端别拖着绘图库跑；④ 出图观感要和原作业一致。**
>
> 本文把可选路线列全、给出取舍，并说明本项目最终怎么做的。
> 结论先放这里：**numpy 只算标量、原始数据走 WebSocket、颜色在 Godot 端用一块 canvas_item 着色器上色**——
> 零额外依赖、逐列刷新、交互免费，且默认色标与 matplotlib 逐点完全一致。

---

## 一、先把问题拆开

「替代 matplotlib」其实是三件独立的事，混在一起谈容易选错：

| 子问题 | matplotlib 的做法 | 我们的替代 |
|---|---|---|
| **算** | numpy/scipy（本来就与 matplotlib 无关） | 不变，numpy + scipy.fft |
| **着色**（标量 → 颜色） | `cmap='rainbow'` 查表 | 色标查表（GDScript `Gradient` + 着色器采样） |
| **显示** | 后端渲染成位图，`plt.show()` 弹窗 | 前端 GPU 上色，`IntensityMap` 控件 |

matplotlib 真正的价值在「**算完一次性静态出图**」。而工控 GUI 要的是「**流式 + 交互**」，
这两件事它都不是强项：它是进程内阻塞式绘图，没有增量更新接口，
每次 `draw()` 都要重走一遍 Agg/Tk 渲染管线。

---

## 二、路线 A：继续用 matplotlib（后端渲染 PNG 推给前端）

最省事的改法：后端每算一个 z，`savefig` 到内存 → PNG 字节 → base64 → WebSocket → 前端
`Image.load_png_from_buffer()`。

**为什么没选**

- 每帧要走完整渲染管线：1000×1000 的 `pcolormesh` 重绘一次约 0.1–0.3 s，
  而算一列 FFT 才 0.1 s —— **绘图成了瓶颈**，还占着 GIL。
- 传输放大：一张 1000×1000 PNG 约 200 KB ~ 1 MB，1000 帧就是几百 MB；
  同一条曲线我们只传 4 KB 的原始 float32。
- 交互全部丢失：不能换配色、不能调量程、鼠标读数无从谈起，改一次参数就得整张重画。
- 后端多一个重依赖（matplotlib + 其字体/后端资源），部署到工控机更笨重。
- GUI 里嵌 PNG 只能整体缩放，放到大屏上会糊。

> 适用场景：**报告出图、离线批处理**。保留原脚本 `Rayleigh-Sommerfeld-assignment1.py` 就是这个用途，
> 我们没有改它一行。

---

## 三、路线 B：换一个更快的 Python 绘图库（仍在后端出图）

如果一定要「后端出图」，2026 年可选的有：

| 方案 | 定位 | 对我们的适配度 |
|---|---|---|
| **Pillow / PIL** | 数组 → 位图，`Image.fromarray` + `putpalette` | 🟢 极轻，但没有坐标轴/色标条，等于自己写 matplotlib |
| **OpenCV (`cv2.applyColorMap`)** | 有 `COLORMAP_RAINBOW` 等内置色标，`numpy → 伪彩图` 一行 | 🟡 快，但拖进一个 60 MB 级的依赖，且同样没有坐标轴 |
| **pyqtgraph** | 交互式实时绘图，`setImage` 支持增量更新 | 🔴 与 PyQt 绑定 —— 本项目正是**为了摆脱 Qt**才做的，方向相反 |
| **VisPy** | GPU 加速科学可视化，百万级点实时 | 🔴 要开 OpenGL 窗口，等于再养一套渲染栈 |
| **Datashader** | 大数据栅格化（自动聚合 + 分箱） | 🟡 强在「几亿点聚合」，我们只有 100 万个格子，用不上 |
| **plotly / Bokeh / Dash** | 浏览器端交互图表 | 🔴 引入 Web 栈 + 浏览器，比 Godot 内嵌重得多 |
| **xy**（Reflex AI，2026-07 开源，Apache-2.0） | Rust 核心 + WebGL2 客户端渲染，宣称 1 亿点仍可交互，`import xy.pyplot as plt` 可平滑替换 | 🟡 新，且输出到浏览器/WebGL；要嵌进桌面 GUI 仍需一层窗口 |
| **Datoviz** | Vulkan GPU 渲染，VisPy 2.0 的预定后端 | 🟡 面向超大规模，重依赖 |
| **rsplotlib** | Rust 实现的 matplotlib 兼容 API | 🟡 同上，仍是「后端出图」范式 |

**共同问题**：它们都在解决「**怎么在 Python 里把图渲染出来**」。
可我们的前端**本来就是一个 GPU 渲染器（Godot）**，让 Python 再渲染一遍再把位图塞回去，
等于把已经在手的显卡放着不用、绕远路。**只要把「标量」传过去，颜色交给前端即可。**

---

## 四、路线 C：前端（Godot）自己画 —— 本项目采用

Godot 侧的可选做法：

| 做法 | 说明 | 评价 |
|---|---|---|
| `_draw()` + `draw_polyline` | 本项目 `TrendChart` / `MultiTrendChart` 用的方式 | 🟢 曲线够用；**画热力图是逐像素 CPU 上色，100 万格不可行** |
| `Image` + `ImageTexture` + **canvas_item 着色器** | 单通道浮点纹理存强度，色标由 GPU 查表 | 🟢✅ **本项目方案**：只传标量、只传 4 KB/列，换配色/调量程零成本 |
| `MultiMesh` / `MultiMeshInstance2D` | 大量同构图元（散点） | 🟡 适合散点，热力图用不上 |
| 引第三方 addon | 见下表 | 🟡 见下 |

**Godot 图表 addon 现状（2026）**

| Addon | 特点 | 适配度 |
|---|---|---|
| [TauPlot](https://store.godotengine.org/asset/ze2j/tau-plot/)（BSD-3，Godot ≥ 4.5） | 环形缓冲流式刷新、GPU 加速散点（MultiMesh）、多子图、hover 十字线 | 🟡 强在散点/柱状，**没有热力图**；我们已有等价的 `TrendChart`/`IntensityMap` |
| [Graph2D](https://www.gadgetgodot.com/u/ld2studio/graph2d) | 轻量折线，实时刷新 | 🟡 只有折线 |
| [Easy Charts](https://github.com/fenix-hub/godot-engine.easy-charts) | Line/Scatter/Bar/Pie/Radar，自称「受 matplotlib/plotly 启发」 | 🟡 2D 控件类，无热力图；体量比我们自己那两百行大得多 |

**为什么最终不引 addon**：本项目要的是「一张二维标量场的伪彩图 + 坐标轴 + 色标条」，
自绘 `IntensityMap` 约 300 行、零依赖、颜色/尺寸全部走主题令牌；
引 addon 反而要迁就它的数据结构与主题系统（CLAUDE.md 里「不要 per-control 打补丁」的原则）。

---

## 五、本项目的实现（可对照代码读）

```
Python 后端                                     Godot 前端
────────────                                    ────────────
numpy + scipy.fft 逐 z 算一列强度                NetClient 收到 rs_col
        │                                                │
        │  float32 小端 → base64（约 4 KB/列）             ▼
        └────────── WebSocket JSON ──────────►  IntensityMap.set_column()
                                                         │  blit 进 FORMAT_RF 图像
                                                         │  ImageTexture.update()（每帧最多一次）
                                                         ▼
                                                canvas_item 着色器查色标
                                                （themes/shaders/colormap.gdshader）
```

对应文件：

| 环节 | 文件 |
|---|---|
| 逐距离计算（原脚本算法的流式改写） | `backend/rayleigh_sommerfeld.py` |
| 协议与推送 | `backend/main.py`（`rs_begin` / `rs_col` / `rs_done`） |
| 伪彩图控件（坐标轴 + 色标条 + 悬停读数） | `scripts/ui/intensity_map.gd` |
| 上色着色器 | `themes/shaders/colormap.gdshader` |
| 色标定义（rainbow / jet / gray） | `scripts/theme/colormaps.gd` |
| 演示界面 | `scripts/main.gd` |

### 5.1 为什么用 FORMAT_RF（32 位浮点单通道）

光强动态范围极大（本例峰值 ~1e28，弱条纹 ~1e22）。若量化成 8 位，
要么大量细节被压平、要么量程一变就得整幅重新量化。
`FORMAT_RF` 原样存浮点，**显示范围只是着色器的一个 uniform**，
自动量程（`auto_range`）增长时不需要重算任何像素。

### 5.2 为什么色标也自己实现（而不是引色彩库）

matplotlib 的 `rainbow` 是**解析式**的，不是查表数据，所以可以直接复刻：

```
R(t) = clamp(|2t - 0.5|, 0, 1)
G(t) = sin(πt)
B(t) = cos(πt/2)
```

已用 matplotlib 3.11 逐点验证：**256 级 LUT 上三通道最大误差均为 0**
（`scripts/theme/colormaps.gd` 的 `sample()` 就是这三行）。
所以前端出图与作业原图配色**完全一致**，且不需要后端装 matplotlib。
想换配色只改 `Colormaps`；`jet` 走 matplotlib 的分段表，`gray` 为线性灰阶。

### 5.3 实测开销（N=1000，1000 个 z，本机 RTX 4060 + Anaconda Python 3.12）

| 项目 | 数值 |
|---|---|
| 原脚本一次性算完（N=1000） | **129.7 s**（约 0.106 s/列，两个 1000×1000 复 FFT） |
| 逐列流式（本项目） | 每列同样 0.106 s；**新增开销 ≈ 0**（base64 + JSON 约 5 KB/列） |
| 一列的网络载荷 | 1000 × float32 = 4 KB → base64 ≈ 5.4 KB |
| 全流程总载荷 | ≈ 5.4 MB（1000 列） |
| 显存/纹理 | 1000×1000 × 4 B = 4 MB，`update()` 每帧最多一次 |
| 「快速预览」预设（N=384、z 步进 4） | **1.5 s 出完整图**，足够调参数时用 |

### 5.4 踩过的坑（写下来省得再踩）

1. **canvas_item 的 `fragment()` 里 `COLOR` 已经乘过纹理**了。写成 `COLOR = colormap * COLOR`
   会把整幅图压暗（表现为「一片黑/一片红」）。正确写法是 `COLOR = vec4(c, 1.0);`。
2. 浮点纹理用 **NEAREST** 采样：既保证逐格显示（与 `pcolormesh` 的方格观感一致），
   也避开部分老 GPU/虚拟机缺少 `OES_texture_float_linear` 的问题（本项目要兼容 RDP）。
3. 数据可能是**入树前**就填好的（先 `setup()/set_column()` 再 `add_child()`），
   所以 `_ready()` 里不能无脑 `set_process(false)`，否则纹理永远不上传。
4. GDScript 的 `%` **不支持 `%e` / `%g`**（运行时报 unsupported format character），
   科学计数法得自己拼（见 `scripts/util/fmt.gd`）。

---

## 六、matplotlib API → 本项目对照

| matplotlib | 本项目 | 备注 |
|---|---|---|
| `plt.pcolormesh(Z, Y, I, cmap='rainbow')` | `IntensityMap.setup()` + `set_column()` + `colormap = "rainbow"` | 逐列追加，边算边画 |
| `plt.colorbar(label=...)` | `IntensityMap.colorbar_label`（自绘色标条） | 刻度固定标 0..1 归一化强度 |
| `ax.set_aspect('equal')` | `IntensityMap.equal_aspect = true` | 按物理尺度等比 + 居中留白 |
| `ax.set_xlabel/ylabel` | `IntensityMap.x_label` / `y_label` / `unit_suffix` | 单位自动换算（默认 m → μm） |
| `ax.set_title` | `IntensityMap.title` | |
| `imshow(..., vmin=, vmax=)` | `IntensityMap.set_display_range()` / `auto_range` | 自动量程 = 原脚本的全局归一化（在线进行） |
| `cmap='jet'` / `'gray'` | `colormap = "jet"` / `"gray"`，`Colormaps.names()` 可枚举 | 加新色标只改 `colormaps.gd` |
| 自定义 colormap | `Colormaps` 里加一条 `sample()` 分支 | |
| 鼠标读数（matplotlib 无） | `IntensityMap.cell_hovered` 信号 + 十字线 | 前端白送 |
| `plt.savefig()` | 仍需出图时用原脚本（保留未改） | 报告出图走 matplotlib 更合适 |
| 伽马/对比拉伸 | `IntensityMap.gamma` | 看弱条纹很有用 |

---

## 七、结论与后续可选项

**结论**：本项目的定位（前端有 GPU、后端只做计算、要实时与交互）下，
「numpy 算 + 传标量 + GPU 上色」严格优于「Python 端出图」。
它同时满足四条硬要求，且把 matplotlib 从**运行依赖**降级为**离线出图工具**。

**后续如果要做**：

- **导出图片**：`IntensityMap` 已经有完整的 `Image`（`FORMAT_RF`），
  加一个 `save_png()`（先在 CPU 上走一遍 `Colormaps.sample()` 生成 RGBA）即可，
  不必回到 matplotlib。
- **超多子图/等高线**：可考虑 TauPlot，但它没有热力图，仍要自己写。
- **等值线**：`marching squares` 自绘（约 100 行），或后端算好线段再传。
- **大规模点云**：换 `MultiMesh`，与本文路线不冲突。

**参考来源**

- [TauPlot - Charts & Plotting Addon](https://store.godotengine.org/asset/ze2j/tau-plot/)
- [Graph2D](https://www.gadgetgodot.com/u/ld2studio/graph2d)
- [godot-engine.easy-charts](https://github.com/fenix-hub/godot-engine.easy-charts)
- [xy: The Fastest Python Charting Library (Reflex)](https://reflex.dev/blog/xy-python-charting-library/)
- [21 Best Free and Open Source Python Visualization Packages](https://www.linuxlinks.com/best-free-python-visualization-packages/)
- [Datoviz: high-performance GPU rendering for scientific data visualization](https://github.com/jdot274/datoviz)
- [rsplotlib: Rust 实现的 matplotlib 兼容库](https://github.com/YJ-Niu/rsplotlib)
