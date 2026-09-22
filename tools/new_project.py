#!/usr/bin/env python3
"""用 Godot4GUI 模板生成一个新项目。

用法（在当前模板项目里跑）：

    python tools/new_project.py D:\\work\\MyLab --title "XX 实验台"
    python tools/new_project.py ../MyLab --name MyLab --title "XX 实验台"
    python tools/new_project.py D:\\work\\MyLab --no-gallery --no-skills

生成出来的项目**开箱可跑**：
    cd <目标目录> && pip install -r backend/requirements.txt && python backend/main.py
    再用 Godot 4.7 打开该目录按 F5 —— 点「启动采集」就能看到曲线滚动。

复用（原样拷贝）：scripts/autoload · scripts/theme · scripts/ui · scripts/util ·
                 themes/(icons, shaders) · gallery 场景
替换（本脚本写入）：scenes/app.tscn + scripts/app.gd（起始页面）· backend/main.py（服务骨架）
                    · README.md · CLAUDE.md · .gitignore · project.godot（改名）
不拷贝（模板特有的示例）：Rayleigh-Sommerfeld 衍射相关的一切
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

TEMPLATE_ROOT = Path(__file__).resolve().parent.parent
SKELETON = Path(__file__).resolve().parent / "skeleton"

# 原样复制的目录（连同里面的 .uid 一起拷，保证 .tscn 里的 uid 引用不悬空）
COPY_DIRS = [
    "scripts/autoload",
    "scripts/theme",
    "scripts/ui",
    "scripts/util",
    "themes",
]
# 原样复制的散文件（project.godot 会再按新名字改几个字段）
COPY_FILES = [
    "project.godot",
    "backend/requirements.txt",
    "docs/gdscript-only-guide.md",
    # 控件库跟着项目走，那它的回归检查也一起走：
    #   godot --headless --path . --script res://tools/checks/table_actions.gd
    "tools/checks/table_actions.gd",
]
# gallery（开发期参照手册）：--no-gallery 时不拷
GALLERY_FILES = [
    "scripts/gallery.gd",
    "scripts/gallery.gd.uid",
    "scenes/gallery.tscn",
]

# 骨架文件 -> 目标路径
SKELETON_FILES = {
    "app.gd": "scripts/app.gd",
    "app.tscn": "scenes/app.tscn",
    "backend_main.py": "backend/main.py",
    "README.md": "README.md",
    "CLAUDE.md": "CLAUDE.md",
}
SKELETON_RENAMES = {"gitignore.txt": ".gitignore"}


def die(msg: str) -> None:
    print(f"错误：{msg}", file=sys.stderr)
    raise SystemExit(1)


def render(text: str, name: str, title: str) -> str:
    """把模板占位符替换成新项目的名字。"""
    return text.replace("{{PROJECT_NAME}}", name).replace("{{PROJECT_TITLE}}", title)


def copy_tree(src: Path, dst: Path) -> int:
    if not src.is_dir():
        die(f"模板缺少目录：{src}")
    shutil.copytree(src, dst, dirs_exist_ok=True)
    return sum(1 for p in dst.rglob("*") if p.is_file())


def copy_file(src: Path, dst: Path) -> None:
    if not src.is_file():
        die(f"模板缺少文件：{src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def patch_project_godot(target: Path, name: str, title: str) -> None:
    """改工程名、窗口标题、主场景，以及 [backend] 段里的 Python 解释器路径。"""
    path = target / "project.godot"
    text = path.read_text(encoding="utf-8")

    def sub(pattern: str, repl: str, required: bool = True) -> None:
        nonlocal text
        new, n = re.subn(pattern, repl, text, count=1, flags=re.MULTILINE)
        if n == 0 and required:
            die(f"project.godot 里没找到 {pattern}，模板可能改过结构，请手动改")
        text = new

    sub(r'^config/name=".*"$', f'config/name="{name}"')
    sub(r'^config/description=".*"$', f'config/description="{title}：Godot 前端 + Python 后端"')
    sub(r'^run/main_scene=".*"$', 'run/main_scene="res://scenes/app.tscn"')
    # BackendLauncher 要靠这一行来拉起后端。默认填「跑这个脚手架的 Python」——
    # 这比去扫 PATH 靠谱得多，至少它确实装了依赖（requirements 是新项目自己装的）。
    # 生成后请确认这一行指向新项目要用的环境；换机器时也要改它。
    sub(r'^python=".*"$', 'python="%s"' % _python_for_godot(), required=False)
    path.write_text(text, encoding="utf-8", newline="\n")


def _python_for_godot() -> str:
    """当前解释器的路径，转成 Godot 项目设置里惯用的正斜杠写法。"""
    exe = Path(sys.executable)
    if exe.name.lower() == "pythonw.exe":       # 别把无窗口解释器写进去，后端要看日志
        exe = exe.with_name("python.exe")
    return exe.as_posix()


def copy_claude_skills(target: Path) -> int:
    """把模板里的 Godot 开发 skills 一起带过去（用不用 Claude Code 都无害）。"""
    src = TEMPLATE_ROOT / ".claude"
    if not src.is_dir():
        return 0
    dst = target / ".claude"
    shutil.copytree(src, dst, dirs_exist_ok=True)

    # godot-gui 这个 skill 里引用了模板特有的迁移对照表，换成新项目里真实存在的文件
    skill = dst / "skills" / "godot-gui" / "SKILL.md"
    if skill.is_file():
        text = skill.read_text(encoding="utf-8")
        text = text.replace("先读 `CLAUDE.md` 和 `docs/siliconui-godot-mapping.md`。",
                            "先读 `CLAUDE.md`，控件用法看 `scenes/gallery.tscn`。")
        text = text.replace("- 迁移对照表：`docs/siliconui-godot-mapping.md`\n", "")
        skill.write_text(text, encoding="utf-8", newline="\n")
    return sum(1 for p in dst.rglob("*") if p.is_file())


def build(target: Path, name: str, title: str, gallery: bool, skills: bool, force: bool) -> None:
    if target.exists() and any(target.iterdir()) and not force:
        die(f"目标目录非空：{target}（要覆盖请加 --force）")
    target.mkdir(parents=True, exist_ok=True)

    print(f"模板：{TEMPLATE_ROOT}")
    print(f"目标：{target}")

    copied = 0
    for rel in COPY_DIRS:
        copied += copy_tree(TEMPLATE_ROOT / rel, target / rel)
    for rel in COPY_FILES:
        copy_file(TEMPLATE_ROOT / rel, target / rel)
        copied += 1
    if gallery:
        for rel in GALLERY_FILES:
            copy_file(TEMPLATE_ROOT / rel, target / rel)
            copied += 1

    for src_name, dst_rel in SKELETON_FILES.items():
        src = SKELETON / src_name
        if not src.is_file():
            die(f"骨架缺少文件：{src}")
        dst = target / dst_rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(render(src.read_text(encoding="utf-8"), name, title),
                       encoding="utf-8", newline="\n")
        copied += 1
    for src_name, dst_rel in SKELETON_RENAMES.items():
        src = SKELETON / src_name
        if src.is_file():
            (target / dst_rel).write_text(src.read_text(encoding="utf-8"),
                                          encoding="utf-8", newline="\n")
            copied += 1
    (target / "docs").mkdir(exist_ok=True)

    patch_project_godot(target, name, title)
    if skills:
        copied += copy_claude_skills(target)

    print(f"已写入 {copied} 个文件。\n")
    print("下一步：")
    print(f"  1) cd {target}")
    print("  2) pip install -r backend/requirements.txt")
    print("  3) python backend/main.py")
    print("  4) 用 Godot 4.7 打开该目录，按 F5；点「启动采集」应看到曲线滚动")
    print()
    print("接着从这里改：")
    print("  scripts/app.gd                    —— 你的界面")
    print("  scripts/theme/theme_palette.gd    —— 配色/字号/间距（只改这一个文件）")
    print("  backend/main.py  Session.handle() —— 加你的命令")
    if gallery:
        print("  scenes/gallery.tscn               —— 控件参照手册（开发完可删）")
    print()
    print("提示：先在 Godot 里打开一次让它导入资源（生成 .godot/ 与 .uid）。")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="用 Godot4GUI 模板生成一个新项目",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例：python tools/new_project.py D:\\work\\MyLab --title \"XX 实验台\"")
    ap.add_argument("target", help="新项目的目标目录（不存在会自动创建）")
    ap.add_argument("--name", help="工程名（默认取目标目录名）")
    ap.add_argument("--title", help="界面/窗口标题（默认同 --name）")
    ap.add_argument("--no-gallery", action="store_true", help="不拷贝控件总览 gallery")
    ap.add_argument("--no-skills", action="store_true", help="不拷贝 .claude/ 开发 skills")
    ap.add_argument("--force", action="store_true", help="目标目录非空也继续（覆盖同名文件）")
    args = ap.parse_args()

    target = Path(args.target).expanduser().resolve()
    if target == TEMPLATE_ROOT or TEMPLATE_ROOT in target.parents:
        # 允许生成到模板外部；生成到模板内部会污染模板
        die(f"目标目录不能放在模板项目内部：{target}")
    name = args.name or target.name
    if not re.fullmatch(r"[A-Za-z0-9_.\-]+", name):
        die(f"工程名只允许字母/数字/下划线/点/短横线：{name}")
    title = args.title or name

    build(target, name, title,
          gallery=not args.no_gallery, skills=not args.no_skills, force=args.force)


if __name__ == "__main__":
    main()
