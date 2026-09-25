#!/usr/bin/env python3
"""给策划的 demo：一条命令出 exe（可选带 zip）。

**为什么要有这个脚本。** 打包前有两处只该在开发机上存在的东西必须摘掉：
`[autoload]` 里的 `MCPRuntimeProbe` 和整个 `[editor_plugins]` 节（godot_mcp）。
以前是手改 `project.godot`，改完导出、再手动还原 —— 忘还原的话下次开编辑器
gdmcp 就是坏的。这种「记得做某件事」的约定迟早会破，交给脚本。

流程：备份 project.godot -> 写精简版 -> 导出 -> **无论成败都还原**
      -> 包内自检（`tools/check_pack.gd`）-> 报告产物。

**为什么要自检。** 2026-09-24：临时角色在编辑器里好好的，打包之后一个都不出来 ——
包里 `DirAccess.get_files_at()` 给出的是 `down1.png.import`，不是 `down1.png`。
编辑器里这两种名字都在，所以这个问题**只在包里出现**，跑测试、开编辑器都抓不到。
自检不过就带着非零退出码收场，免得把一个跑不动的包发出去。

用法（在项目根或任意位置都行）：

    python tools/export_demo.py              # 导出到 ../if-demo-build/
    python tools/export_demo.py --zip        # 顺手压成 _demo.zip
    python tools/export_demo.py --no-check   # 跳过包内自检
    python tools/export_demo.py -o D:/某个目录/IF如果之间.exe

Godot 可执行文件按这个顺序找：`--godot` 参数、环境变量 `GODOT_EXE`、
下面 `GODOT_CANDIDATES` 里第一个存在的。换机器时改那份候选表。
"""

import argparse
import os
import shutil
import subprocess
import sys

# 项目根 = 本文件所在目录的上一级
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 换机器时改这里
GODOT_CANDIDATES = [
    r"C:\Games\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    r"C:\Program Files\Godot\godot.exe",
]

PRESET = "Windows Desktop"
DEFAULT_OUT = os.path.join(PROJECT, "..", "if-demo-build", "IF如果之间.exe")

# 打包时要摘掉的 autoload。键名，不是 uid。
DEV_AUTOLOADS = ["MCPRuntimeProbe"]
# 整个节都要摘掉的。`[editor_plugins]` 里那条 enabled 指着 addons/godot_mcp。
DEV_SECTIONS = ["editor_plugins"]

# 包内自检脚本。**走绝对路径加载，tools/ 不进包也照样能跑。**
PACK_CHECK = os.path.join(PROJECT, "tools", "check_pack.gd")


def find_godot(explicit=None):
    if explicit:
        if os.path.isfile(explicit):
            return explicit
        sys.exit("找不到 Godot：" + explicit)
    env = os.environ.get("GODOT_EXE")
    if env and os.path.isfile(env):
        return env
    for path in GODOT_CANDIDATES:
        if os.path.isfile(path):
            return path
    found = shutil.which("godot")
    if found:
        return found
    sys.exit("找不到 Godot 可执行文件。用 --godot 指定，或把路径填进 GODOT_CANDIDATES。")


def strip_dev_only(text):
    """摘掉开发专用配置，返回新的 project.godot 内容。

    按节扫，不按行号 —— 行号会因为别处的改动而漂。
    """
    keep = []
    skipping = False
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            # 进入新节。整节要摘的就从这里开始跳
            skipping = stripped[1:-1] in DEV_SECTIONS
            if skipping:
                continue
        if skipping:
            continue
        if any(stripped.startswith(name + "=") for name in DEV_AUTOLOADS):
            continue
        keep.append(line)

    # 摘完之后 `[autoload]` 可能空了。空节留着不好看，也容易让人以为掉了东西
    out = []
    index = 0
    while index < len(keep):
        line = keep[index]
        if line.strip() == "[autoload]":
            nxt = index + 1
            while nxt < len(keep) and keep[nxt].strip() == "":
                nxt += 1
            if nxt >= len(keep) or keep[nxt].lstrip().startswith("["):
                index = nxt
                continue
        out.append(line)
        index += 1
    return "".join(out)


def run_pack_check(godot, out_path):
    """把刚导出的 exe 当 pck 挂上，验一遍包里的资源认不认得出来。

    返回 True 表示过了，False 表示包有问题。脚本本身不进包，从绝对路径加载。
    """
    if not os.path.isfile(PACK_CHECK):
        print("提醒：找不到 %s，跳过包内自检" % PACK_CHECK)
        return True

    print("--- 包内自检 ---")
    result = subprocess.run(
        [godot, "--headless", "--main-pack", out_path, "--script", PACK_CHECK],
        cwd=PROJECT,
    )
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description="导出给策划的 demo")
    parser.add_argument("-o", "--out", default=None, help="导出的 exe 路径")
    parser.add_argument("--godot", default=None, help="Godot 可执行文件路径")
    parser.add_argument("--zip", action="store_true", help="导完顺手压成 zip")
    parser.add_argument("--no-check", action="store_true", help="跳过包内自检")
    parser.add_argument("--dry-run", action="store_true",
                        help="只打印摘完之后 project.godot 长什么样，不导出")
    args = parser.parse_args()

    godot = find_godot(args.godot)
    out_path = os.path.abspath(args.out or DEFAULT_OUT)
    out_dir = os.path.dirname(out_path)
    config = os.path.join(PROJECT, "project.godot")

    print("Godot   : " + godot)
    print("项目    : " + PROJECT)
    print("产物    : " + out_path)

    if not os.path.isfile(config):
        sys.exit("找不到 project.godot：" + config)
    # 导出目标目录必须先存在，否则 Godot 会报「给定的导出路径不存在」
    os.makedirs(out_dir, exist_ok=True)

    with open(config, "r", encoding="utf-8") as handle:
        original = handle.read()

    stripped = strip_dev_only(original)
    if stripped == original:
        print("提醒：project.godot 里没找到要摘的东西，确认一下 DEV_AUTOLOADS / DEV_SECTIONS")
    else:
        removed = len(original) - len(stripped)
        print("已摘掉开发专用配置（%d 字符）" % removed)

    if args.dry_run:
        print("--- 摘完之后的 project.godot ---")
        sys.stdout.write(stripped)
        return 0

    result = None
    try:
        with open(config, "w", encoding="utf-8", newline="") as handle:
            handle.write(stripped)
        result = subprocess.run(
            [godot, "--headless", "--path", PROJECT,
             "--export-release", PRESET, out_path],
            cwd=PROJECT,
        )
    finally:
        # 还原是硬要求：不还原的话下次开编辑器 gdmcp 就是坏的
        with open(config, "w", encoding="utf-8", newline="") as handle:
            handle.write(original)
        print("project.godot 已还原")

    if result is None or result.returncode != 0:
        sys.exit("导出失败，退出码 %s" % (result.returncode if result else "?"))
    if not os.path.isfile(out_path):
        sys.exit("导出命令没报错，但产物不在：" + out_path)

    size = os.path.getsize(out_path)
    print("导出成功：%.1f MB" % (size / 1024.0 / 1024.0))

    if not args.no_check and not run_pack_check(godot, out_path):
        sys.exit("包内自检没过 —— 包里有些资源认不出来，这个包别发出去")

    if args.zip:
        zip_base = os.path.splitext(out_path)[0] + "_demo"
        archive = shutil.make_archive(zip_base, "zip", out_dir,
                                      os.path.basename(out_path))
        print("已打包：%s（%.1f MB）"
              % (archive, os.path.getsize(archive) / 1024.0 / 1024.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
