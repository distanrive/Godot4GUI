#!/usr/bin/env bash
#
# 编译 native_window 扩展（bin/native_window.windows.x86_64.dll）。
#
#   bash tools/build_native_window.sh
#
# 它把 tools/native_window/native_window.c 编成一个 GDExtension 动态库，
# 里面只有三个静态方法（hide_window / show_window / is_supported），
# 干的事是绕过引擎直接调 Win32 的 ShowWindow —— 为什么必须这么做见那个 .c 的顶部注释。
#
# 依赖：MinGW-w64 的 gcc。**必须与 Godot 官方 Windows 模板同一套工具链**
# （WinLibs POSIX 线程模型 + UCRT），否则运行时的 C 运行库可能对不上。
# 装法见 CLAUDE.md「重新编译模板的完整步骤」第 2 条；装好后脚本会自己去搜。
#
# 改完这个扩展记得：
#   1) bash tools/build_native_window.sh
#   2) godot --headless --path . --import        （刷新对 .gdextension 的扫描）
#   3) godot --headless --path . --script res://tools/self_check.gd
#      （里面有「扩展能不能加载、类与方法在不在」的探针）

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="tools/native_window/native_window.c"
OUT="bin/native_window.windows.x86_64.dll"

# ---- 找 gcc ----
if [ -n "${MINGW_GCC:-}" ]; then
	GCC="$MINGW_GCC"
else
	GCC="$(find "${LOCALAPPDATA:-$HOME/AppData/Local}/Microsoft/WinGet/Packages" \
		-name gcc.exe -path '*mingw64/bin*' 2>/dev/null | head -1 || true)"
fi
if [ -z "${GCC:-}" ] || [ ! -x "$GCC" ]; then
	echo "[ERROR] 找不到 MinGW 的 gcc.exe" >&2
	echo "        winget install BrechtSanders.WinLibs.POSIX.UCRT --source winget" >&2
	echo "        或者用 MINGW_GCC=<gcc 完整路径> bash tools/build_native_window.sh" >&2
	exit 1
fi

mkdir -p bin

# -static / -static-libgcc：把运行库链进去，产物不依赖 libgcc_s_*.dll
# （发布包里只有 exe + pck + 这一个 dll，不能是「一堆 dll」）。
# -luser32：ShowWindow / SetForegroundWindow / IsWindowVisible 都在 user32 里。
# --no-insert-timestamp：**产物是可复现的** —— 不加的话 PE 头里会写当前时间，
#   源码一个字没改、每次 build.bat 跑完 git 里都会显示「dll 被改过」。
#   这个 dll 是提交进仓库的（缺了它 Godot 每次启动会打三行 ERROR，见 CLAUDE.md），
#   所以必须让它可复现。
echo "用 $GCC 编译 $SRC -> $OUT"
"$GCC" -shared -O2 -m64 -static -static-libgcc \
	-Wl,--no-insert-timestamp \
	-o "$OUT" "$SRC" \
	-Itools/native_window \
	-luser32

ls -l "$OUT"
echo "完成。接着跑："
echo "  godot --headless --path . --import          # 刷新类名缓存，否则 TrayWindow 认不出来"
echo "  godot --path . --script res://tools/checks/tray_window.gd   # 真的隐藏/显示一次并断言"
