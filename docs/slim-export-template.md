# 精简导出模板：实测记录与配方

> 官方 Windows 导出模板 **104 MB**，自编精简后可到 **33 MB 上下**。
> 这份文档记录 2026-09-23 在**本机**实际跑出来的数字、两条路线的对照、
> 以及**对本模板致命/安全的开关清单** —— 不是转述别人的配方。
>
> 相关：`docs/godot-facts-verified.md`（Godot 事实与坑）、
> `docs/gdscript-only-guide.md` §5（「一个 exe」的交付体积现实）。

---

## 0. 首要原则：**模板按项目指定，不要共用一份**

**不同项目用到的引擎功能不一样，所以模板本来就不该是同一份。**
正确做法是用导出预设里的选项把模板**绑到项目上**（Windows 平台已核实，
见 `gdd_1257_EditorExportPlatformWindows.md`）：

```ini
; export_presets.cfg
custom_template/release="D:/godot-build/out/<你的项目>_template_release.exe"
custom_template/debug="D:/godot-build/out/<你的项目>_template_debug.exe"
```

文档原文：*"Path to the custom export template. **If left empty, default template is used.**"*

- 于是 `%APPDATA%\Godot\export_templates\<版本>\windows_release_x86_64.exe` 那份**只是兜底默认**，
  预设留空时才用它。**不需要为了导 A 项目去把全局模板改成 B 项目的样子** —— 那样既容易忘，
  也会连带影响别的项目。
- 举例：wlt_login/ReUSTCNet 是纯 GDScript、只用 `HTTPRequest`，所以它那份模板**关掉 websocket 是对的**；
  而本项目 `scripts/autoload/net_client.gd:23` 是 `var _socket := WebSocketPeer.new()`，
  它自己那份模板就该带上 `module_websocket_enabled=yes`。**两者互不相干，各编各的。**
- 要注意的只有一种情况：**预设留空（用全局默认）而全局那份恰好是给别的项目编的精简版** ——
  这时会出「导出后某个类不存在」的问题，而且**只在导出后暴露**（编辑器里按 F5 用的是编辑器本体，
  与模板无关）。所以：**要么给预设指一份自己的模板，要么确认全局那份是官方原版。**
- 想快速确认一份模板里有没有某个类：见 §6 的「探针法」。

---

## 1. 结论先说：三个投递口，等价但不相同

编译永远由 **SCons 选项**驱动，「告诉编译器打包什么」有三个投递口：

| 投递口 | 形态 | 能开 | 能关 | 能裁**类** | 跟版本走 |
|---|---|---|---|---|---|
| 命令行参数 | 一串 `module_xxx_enabled=no` | ✅ | ✅ | ❌ | 手工 |
| `custom.py` | Python 文件，放**源码根目录** | ✅ | ✅ | ❌ | 手工 |
| `.gdbuild` | JSON，`build_profile=<路径>` | 机制上能 | ✅ | ✅ | ✅ 编辑器同版本生成 |

**`.gdbuild` 的应用时机很重要**（`SConstruct:647-658`）：

```python
if "disabled_build_options" in ft:
    for c in ft["disabled_build_options"]:
        env[c] = dbo[c]        # 无条件覆盖，且在命令行解析之后
```

→ **profile 提到的键会盖掉命令行**。名字虽叫 `disabled_*`，机制上能把任意选项设成任意值
（但编辑器生成的只写 `false`）。所以「想开某个模块又同时用 profile」时，
**要么保证 profile 里不写它，要么改 profile**。

---

## 2. 实测数字（同一台机器 / 同一个 4.7.2 源码）

源码树：`D:\godot-build\godot`（`git describe` = `4.7.2-stable`；
二进制 banner 的 revision `ed1daf0bf` 与官方一致 ⇒ 同一次源码）。

| 模板 | 体积 | 跑真实 app（同一个 `wlt_login.pck`，headless 240 帧） |
|---|---|---|
| 官方 | **104.2 MB** | — |
| 命令行（`tools/build_template.sh` 那套） | **34.0 MB** | 0 ERROR，**1 WARNING** |
| `.gdbuild` 驱动（本次实测） | **32.8 MB** | **0 ERROR，0 WARNING** |

两条额外结论：

1. **profile 版小 1.2 MB 的来源**：profile 里补了 `disable_navigation_2d/3d`、
   `disable_physics_2d/3d`、`disable_xr` 这几个**核心**开关；命令行那套只关了对应的**模块**
   （`module_godot_physics_2d_enabled=no` 之类），core 侧还留着。
2. **顺手修掉一个隐性毛病**：只关物理*模块*时，运行时找不到物理实现会
   **退回 dummy server 并打警告** ——
   `WARNING: Falling back to dummy PhysicsServer2D; ... If this is intended, set the
   physics/2d/physics_engine project setting to Dummy.`
   用 `disable_physics_2d`（core 开关）才是真正编掉，警告与那条死路径一起消失。

编译耗时：`-j20`、`lto=full`、`optimize=size_extra`，**3 分 34 秒**。

---

## 3. 两个杠杆：选项 vs 类

### 3.1 `disabled_build_options`（模块 / 特性开关）

就是 SCons 选项，`env[c] = value` 直接生效。收益：**这是大头**（3D、音频、导航、XR、
各种图片编解码、物理引擎……）。

### 3.2 `disabled_classes`（类级裁剪）——profile 独有的能力

机制（本机源码核实）：

- `SConstruct:653` 把列表读进 `env.disabled_classes`；
- 它被写进生成的头文件 **`core/disabled_classes.gen.h`**，由 `core/object/class_db.h` 引入；
- `class_db.h` 里的 `GD_IS_CLASS_ENABLED(m_class)` 是个编译期 trait，
  被裁掉的类其 `ClassDB::register_class<T>()` 直接**编译掉**，
  再靠链接器的 section GC 把整份实现丢掉 ⇒ 真省体积。

**实测确认这个杠杆从没被用过**：命令行那套编完后，`core/disabled_classes.gen.h`
的内容**只有 `#pragma once`**（我这份手写的 profile 也没给类列表，所以仍是空的）。

**但类列表不该手写**：它靠「扫工程的场景与脚本，反推用到的类」，
官方明列了盲区 —— 运行时**动态构造**的 GDScript、**表达式**里的用法、GDExtension、
运行时加载的外部 pck，以及「某些边角情况」。**漏一个类 = 运行时才炸**，
所以必须靠编辑器生成 + 导出后冒烟测。

生成方式（**只有 GUI，没有 CLI** —— 我查过编辑器 `--help` 没有相关选项）：

1. Godot 4.7.2 打开工程；
2. 菜单 **项目 → 工具 → Engine Compilation Configuration Editor**
   （源码位置：`editor/editor_node.cpp:8970` 注册的命令，实现在
   `editor/settings/editor_build_profile.cpp`）；
3. 点 **Detect from Project** → **Save As** 存成 `.gdbuild`（建议放进工程并纳入版本控制）；
4. 编译时 `build_profile=<该文件>`。

这个编辑器功能**不是新的**（4.3/4.4 就有），而且有历史 bug，用前心里有数：
`Load` 在 4.3/4.4 stable 点了没反应（[#104586](https://github.com/godotengine/godot/issues/104586)）；
`Detect from Project` 在 4.5dev3–4.5beta4 整体失效（[#109236](https://github.com/godotengine/godot/issues/109236)，
4.4.1 stable 正常）。4.7.2 上未见相关问题。

---

## 4. 本项目的开关清单（照着抄，别照抄别人的）

### 4.1 **必须保留**（关掉就出问题，都是踩过或核实过的）

| 保留 | 关掉的后果 |
|---|---|
| **`module_websocket_enabled=yes`** | **NetClient 废掉**（`WebSocketPeer` 类不存在，autoload 启动即报错）。**本项目必须开** |
| `module_svg_enabled=yes` | `themes/icons/*.svg` 全失效 |
| `module_webp_enabled=yes` | **所有贴图运行时加载失败**：Godot 的「无损」纹理导入（`compress/mode=0`）内部用 WebP 存 `.ctex`。官方「可关模块」清单里**故意没有它**（全文档搜不到 `module_webp`），别自己加 |
| `module_text_server_adv_enabled=yes` | 界面全是中文，要靠 adv 做排版；官方警告配 `text_server_fb_enabled=yes` 才不至于没文本系统，但 fb 对 CJK 没把握 |
| `module_freetype_enabled=yes`、`module_glslang_enabled=yes`、`module_gdscript_enabled=yes` | 字体渲染、运行时着色器编译、脚本 |
| `opengl3`（驱动） | Vulkan 不可用时（RDP/虚拟机/老核显）的兜底 |
| `mbedtls`（若用 HTTPRequest 的 TLS） | 跨机 `https` 请求失败 |
| `module_jpg/bmp/tga/hdr_enabled`（**视项目**） | 用户自带的 JPG/BMP/TGA/HDR 贴图加载失败。**PNG 是 core，不受影响**；本项目只用 SVG 图标，可以关 |

### 4.2 **绝对不要开**的开关

- **`disable_advanced_gui=yes`** —— 官方文档明说它会关掉这些类，而本模板用了一大批：
  **`OptionButton`（`UiScaleOption` 就是继承它的！还有 main.gd 的配色下拉）**、
  `FileDialog`（FileDropBox 的原生对话框）、`ConfirmationDialog`/`AcceptDialog`（gallery 弹窗）、
  `PopupMenu`、`RichTextLabel`、`SpinBox`、`SplitContainer`、`GraphEdit`、`Tree`。
- **`vulkan=no`** —— forward_plus 没了，等于放弃「后续 3D 图表」那条路。
- **`disable_3d=yes`** —— 同上（本项目渲染器选 forward_plus 就是为了留 3D 的路）。
  纯 2D 项目可以关，能省约 15%。

### 4.3 对本项目**可以关**的（需要时再核实）

3D 物理/导航/XR/音频/纹理编解码等（`astcenc` `basis_universal` `bcdec` `cvtt` `etcpak`
`betsy` `ktx` `dds` `fbx` `gltf` `csg` `gridmap` `vhacd` `meshoptimizer` `lightmapper_rd`
`raycast` `xatlas_unwrap` `msdfgen` `visual_shader` `jolt_physics` `godot_physics_3d`
`godot_physics_2d` `navigation_2d` `navigation_3d` `openxr` `webxr` `mobile_vr`
`ogg` `vorbis` `mp3` `theora` `interactive_music` `enet` `webrtc` `upnp` `jsonrpc`
`multiplayer` `noise` `camera` `mono` `regex` `zip` `objectdb_profiler`），
另加 core 开关 `disable_navigation_2d/3d`、`disable_physics_2d/3d`、`disable_xr`、
`d3d12=no`、`winrt=no`、`accesskit=no`。

> `d3d12=no` 的理由：本项目用 Vulkan（forward_plus），而编 D3D12 驱动需要额外的
> DirectX 12 SDK 依赖；关掉既省事又省体积。

---

## 5. 复现步骤（本机工具链）

```bash
# 工具链（一次性）
pip install scons
winget install BrechtSanders.WinLibs.POSIX.UCRT --version 14.2.0-12.0.0-r2 --source winget
#   ↑ 不需要 Visual Studio —— Godot 官方 Windows 二进制本来就是 MinGW 编的
#   ↑ --source winget 必须加（msstore 源证书有问题）

# 定位 gcc（winget 装的路径带随机后缀，用 find）
GCC=$(find /c/Users/YH/AppData/Local/Microsoft/WinGet/Packages -maxdepth 5 -iname gcc.exe | head -1)
export PATH="$(dirname "$GCC"):$PATH"
SCONS="C:/Users/YH/.conda/envs/normal/Scripts/scons.exe"

cd /d/godot-build/godot          # 源码树（4.7.2-stable）

# 先干跑验证 profile 被吃到（几秒，不占 CPU）：
"$SCONS" -n platform=windows target=template_release tools=no arch=x86_64 use_mingw=yes \
    production=yes optimize=size_extra lto=full \
    build_profile=D:/path/to/project.gdbuild | head -3
#   期望第一行: Using feature build profile: "D:/path/to/project.gdbuild"

# 真编（-j20 约 3.5 分钟）：
"$SCONS" -j20 platform=windows target=template_release tools=no arch=x86_64 use_mingw=yes \
    production=yes optimize=size_extra lto=full d3d12=no winrt=no accesskit=no \
    build_profile=D:/path/to/project.gdbuild
#   产物: bin/godot.windows.template_release.x86_64.exe
```

把产物接到项目上（**推荐**，见 §0）：

```ini
; 项目里的 export_presets.cfg
custom_template/release="D:/godot-build/out/<项目>_template_release.exe"
custom_template/debug="D:/godot-build/out/<项目>_template_debug.exe"
```

**不要**为了导某个项目去把 `%APPDATA%\...\export_templates\` 里那份全局模板改掉 ——
那是所有项目共用的兜底默认，改了会连带影响别人（而且很容易忘）。
只有当预设**留空**、又确实需要临时用全局那份时，才按下面备份/替换：

```
%APPDATA%\Godot\export_templates\4.7.2.stable\
    windows_release_x86_64.exe           ← 被替换的那份
    windows_release_x86_64.official.bak   ← 官方原件备份，别删
```

> 两个细节：① **release 和 debug 是两份模板**（`windows_debug_x86_64.exe` 官方 103 MB），
> 只填 release 的话 Debug 导出还是 100+ MB；② 模板目录名必须与编辑器版本一致（`version.txt`）。

---

## 6. 怎么验证一份模板能不能用（探针法）

导出模板的 `.exe` **本身就是一个 Godot 运行时**，虽然不接受 `--path`（那是 dev/tool 特性），
但它会把**自己所在目录**当 `res://` 跑。于是：

1. 建一个探针目录，放一个最小 `project.godot` + `main.tscn` + `main.gd`；
2. `main.gd` 里 `ClassDB.class_exists("WebSocketPeer")` 之类逐个检查，`print` 出来然后 `quit()`；
3. 把待测模板 `cp` 成 `<任意名>.exe` 放进该目录；
4. `./xxx.exe --headless` → 读输出。

实测样例（同一份 4.7.2 源码）：

```
官方 104 MB 模板 : 类总数=969  缺失=(无)
纯 GDScript 精简模板: 类总数=536  缺失=WebSocketPeer, Node3D, MeshInstance3D, RegEx, ZIPReader
```

**注意两个坑**（我踩过）：

- 用 **`grep` 扫二进制猜类在不在是没用的** —— Godot 把编辑器 UI 字符串与
  `StringName` 都压缩/编码了，扫不到不代表没有（`Node3D` 扫到 2 处 vs 46 处只能算「相对差异」）。
  要结论就用探针法问 `ClassDB`。
- 冒烟测**不能靠 `--script`**：release 导出模板不执行 `--script`。
  用 `--headless --quit-after N` 跑 **导出后的 exe**，再 grep 引擎级错误
  （`SCRIPT ERROR` / `ERROR:`）—— 这也是 wlt_login 的 `build.bat` 的做法。
  它能抓到「导出日志里完全看不出来」的问题（例如所有贴图加载失败）。

---

## 7. 还没验证的

- **`disabled_classes` 到底能再省多少**：未知（§3.2 的杠杆从未启用）。
  拿到编辑器 detect 出来的 profile 后，按 §5 编一次、按 §6 冒烟测，就能得到实测数字。
- **两份模板在同项目上的帧率/启动时间差异**：没测（理论上关掉的功能不影响 UI 路径）。
- **在线生成器（[godot-build-options-generator](https://godot-build-options-generator.github.io)）
  是否支持 4.7**：**确认不了** —— 本环境 WebFetch 对任何域名都失败（Claude Code 自己的
  域名校验走不通，与代理无关）。而且搜到的真实 `custom.py` 例子里出现过 **Godot 3 时代的
  选项名**（`module_navigation_enabled`，4.x 已拆成 `module_navigation_2d/3d_enabled`），
  名字不对时 SCons **静默忽略**。所以用它的话，产物必须拿 `scons --help` 逐个核对
  （本机有源码树，跑这个命令就是权威清单）。
