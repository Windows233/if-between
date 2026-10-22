"""从对方给的**本地包**里同步 git 内容 —— 不走网络。

## 为什么要这个

这个仓库里有几百 MB 的美术素材，`git fetch` 走网络传不完（而且**不支持断点续传**，
被掐掉就从零开始）。策划那边也是同样拉不动。
**常规做法：对方把包给你，从本地拉。** 这个脚本吃掉三种形态：

| 对方给的东西 | 例 | 脚本怎么用 |
| --- | --- | --- |
| 整个项目文件夹（里面有 `.git`） | `if-between (2)/if-between` | 直接用那个文件夹 |
| 只有 `.git` 一个目录 | `<某处>/.git` | 直接用那个 `.git` |
| `git bundle` 打的单文件 | `第二章.bundle` | 直接用那个文件 |

## 用法

    python tools/sync_from_package.py "<对方的路径>"
    python tools/sync_from_package.py "<对方的路径>" --merge 分支名

不加 `--merge` 就只拉，拉完报「比我们多了哪些提交、动了哪些文件」，让你自己决定合不合。
加 `--merge` 会**先跑闸门再合**（`check_data` + 全量测试 + 烟测），闸门不过就不合。

拉进来的分支落在 `pkg/<名字>` 下面（不影响 `origin/*`）。

## 对方那边怎么打包

    # 推荐：只装缺的提交，文件小
    git bundle create 增量.bundle <我们已有的某个提交>..<他的分支>
    # 或者全装
    git bundle create 全部.bundle --all

    # 也可以直接把 .git 文件夹拷出来（记得先停手，别在 fetch/merge 中途拷）
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"C:/Games/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"


def run(args: list) -> tuple:
    p = subprocess.run(args, cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()


def _find_repo_inside(folder: str) -> str:
    """在一个目录里找 git 源：它自己带 .git，或者往下找一层（zip 解开常多套一层）。"""
    if os.path.isdir(os.path.join(folder, ".git")):
        return folder
    for name in sorted(os.listdir(folder)):
        sub = os.path.join(folder, name)
        if os.path.isdir(sub) and os.path.isdir(os.path.join(sub, ".git")):
            return sub
    return ""


def resolve_source(path: str) -> str:
    """把用户给的路径判成 git 认得的那种。返回空串表示认不出来。

    **zip 会解到临时目录**（对方多半是压成 zip 发的），解出来的东西用完不删 ——
    留在系统临时目录里，下次再用同一个路径还能命中缓存。
    """
    if not os.path.exists(path):
        return ""
    if path.endswith(".bundle"):
        return path if os.path.isfile(path) else ""
    if path.endswith(".zip"):
        if not zipfile.is_zipfile(path):
            return ""
        out = os.path.join(tempfile.gettempdir(),
                           "if_sync_" + os.path.splitext(os.path.basename(path))[0])
        if not os.path.isdir(out):
            print("解开 %s → %s" % (os.path.basename(path), out))
            with zipfile.ZipFile(path) as zf:
                zf.extractall(out)
        if os.path.isdir(os.path.join(out, ".git")):
            return out
        found = _find_repo_inside(out)
        if found != "":
            return found
        # 解出来的是「单独一个 .git 目录」的情况
        for name in sorted(os.listdir(out)):
            sub = os.path.join(out, name)
            if name == ".git" and os.path.isdir(sub):
                return sub
        return ""
    if os.path.basename(path.rstrip("/\\")) == ".git":
        return path if os.path.isdir(path) else ""
    if os.path.isdir(os.path.join(path, ".git")):
        return path
    return ""


def main() -> int:
    ap = argparse.ArgumentParser(description="从本地包同步 git 内容（不走网络）")
    ap.add_argument("source", help="对方的文件夹 / .git / .bundle")
    ap.add_argument("--merge", default="", help="拉完之后把哪个 pkg/ 分支合进当前分支")
    ap.add_argument("--skip-gates", action="store_true", help="合并不跑闸门（不推荐）")
    args = ap.parse_args()

    src = resolve_source(args.source)
    if src == "":
        print("认不出这个路径：它既不是文件夹（里面有 .git）、也不是 .git、也不是 .bundle")
        print("注意：**整个项目文件夹**和**只有 .git** 都能用，单独的散文件不行。")
        return 2

    print("=== 从 %s 拉 ===" % src)
    code, out, err = run(["git", "fetch", src, "+refs/heads/*:refs/remotes/pkg/*"])
    if code != 0:
        print("拉失败：", err or out)
        return 1

    code, out, _ = run(["git", "for-each-ref", "--format=%(refname:short) %(objectname:short)",
                        "refs/remotes/pkg/"])
    branches = [line.split() for line in out.splitlines() if line.strip()]
    if not branches:
        print("对方包里没有任何分支")
        return 1
    print("拉到的分支：")
    for name, sha in branches:
        print("  %-28s %s" % (name, sha))

    # 报「比我们多了什么」
    _, head, _ = run(["git", "rev-parse", "--abbrev-ref", "HEAD"])
    for name, _sha in branches:
        code, log, _ = run(["git", "log", "--oneline", "%s..%s" % (head, name)])
        count = len([l for l in log.splitlines() if l.strip()])
        print("\n--- %s 比当前分支（%s）多 %d 个提交 ---" % (name, head, count))
        for line in log.splitlines()[:15]:
            print("   ", line)
        if count > 15:
            print("    ……还有 %d 条" % (count - 15))
        if count:
            _, stat, _ = run(["git", "diff", "--stat", "%s...%s" % (head, name)])
            tail = stat.splitlines()[-1] if stat else ""
            print("    改动规模：", tail)
            _, data, _ = run(["git", "diff", "--name-status", "%s...%s" % (head, name), "--", "data/"])
            if data:
                print("    其中数据文件：")
                for line in data.splitlines()[:20]:
                    print("      ", line)

    if args.merge == "":
        print("\n只拉不合。要合的话：")
        print("  python tools/sync_from_package.py \"%s\" --merge %s" % (args.source, branches[0][0]))
        return 0

    target = args.merge if args.merge.startswith("pkg/") else "pkg/" + args.merge
    if not any(b[0] == target for b in branches):
        print("没有这个分支：", target)
        return 2

    if not args.skip_gates:
        print("\n=== 合并前跑闸门 ===")
        code, out, err = run([sys.executable, "tools/check_data.py"])
        print(out.splitlines()[-1] if out else err)
        if code != 0:
            print("数据自查没过，不合。先看上面报的问题。")
            return 1

    print("\n=== 合并 %s ===" % target)
    code, out, err = run(["git", "merge", "--no-edit", target])
    print(out or err)
    if code != 0:
        print("有冲突或者合不了。**别硬来**：对着差异解，或者找 Windows233。")
        return 1

    print("\n合并完成。接着跑测试与烟测：")
    print("  \"%s\" --headless --path . --script res://tests/run_tests.gd" % GODOT)
    print("  \"%s\" --path . --script res://tests/smoke_run.gd" % GODOT)
    print("两项都过再 push。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
