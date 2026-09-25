#!/usr/bin/env python3
"""把一个剧情文件的节点链打出来，看接得通不通。

用法：
    python tools/show_story_chain.py ch2_meet_a
    python tools/show_story_chain.py            # 列一下有哪些

**它不是测试的替代品。** 测试验的是「这一条指令对不对」，
这个看的是「整条链走不走得通」。

接错下游（出口绕回自己那一圈、或者接去一个不该去的节点）**测试照样全绿** ——
2026-09-25 那次「没改按确定出不去，卡在 IF 框」就是这么来的：
`tutorial_miss` 的 `next` 指回了 `tutorial_choose`，数据上完全合法。

打出来的东西：每个节点的出口（`next` / `ending`）、它自带的选项、
以及它上面挂的三类"暗门"：`talk`（走过去说话）、`if_panel` 的 `wrong`、
`choices` 的 `next`。**链路里任何一个 id 打不出对应节点，就是断了。**
"""
import io
import json
import os
import sys

EVENTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "data", "events")


def exits_of(node):
    """这个节点所有的出口：`(从哪儿来的, 去哪儿)`。"""
    out = []
    # **`next_when` 优先**：条件满足就走它，否则才用 `next`
    when = node.get("next_when")
    if isinstance(when, dict) and when.get("next"):
        out.append(("next_when（满足时）", when["next"]))
    if node.get("next"):
        out.append(("next", node["next"]))
    for choice in node.get("choices", []):
        if choice.get("next"):
            label = choice.get("label", choice.get("id", "?"))
            out.append(("选项「%s」" % label, choice["next"]))
    for step in node.get("stage", []):
        if step.get("talk"):
            # **`talk` 指的是另一个剧情文件**（走过去触发的那一段），不在本文件里，
            # 所以下面检查时会「找不到」—— 那是正常的，别当断链。
            out.append(("走过去说话（别的剧情）", step["talk"]))
        if step.get("do") == "if_panel":
            if step.get("wrong"):
                out.append(("IF 框没改对", step["wrong"]))
            if step.get("solve"):
                out.append(("IF 框改对了", "(本节点的 next)"))
    return out


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else ""
    if not name:
        print("有哪些剧情：")
        for f in sorted(os.listdir(EVENTS)):
            if f.endswith(".json"):
                print("  " + f[:-5])
        return 0

    path = os.path.join(EVENTS, name + ".json")
    if not os.path.exists(path):
        print("没有这个剧情：%s" % path)
        return 1

    data = json.load(io.open(path, encoding="utf-8"))
    nodes = {n["id"]: n for n in data.get("nodes", [])}
    entry = data.get("entry", "")
    print("=== %s（入口 %s，%d 个节点）===" % (name, entry, len(nodes)))

    # 从入口能走到哪儿
    seen = set()
    queue = [entry] if entry in nodes else []
    while queue:
        here = queue.pop()
        if here in seen:
            continue
        seen.add(here)
        for _why, target in exits_of(nodes[here]):
            if target in nodes and target not in seen:
                queue.append(target)

    for nid, node in nodes.items():
        mark = " " if nid in seen else "?"
        ending = (" [结局 %s]" % node["ending"]) if node.get("ending") else ""
        print("\n%s %-18s%s" % (mark, nid, ending))
        if nid not in seen:
            print("      （从入口走不到 —— 靠 `talk` 之类挂上去的？）")
        for why, target in exits_of(node):
            if target.startswith("("):
                print("      %-16s → %s" % (why, target))
                continue
            if target in nodes:
                ok = "✓"
            elif "别的剧情" in why:
                ok = "（在另一个文件里，正常）"
            else:
                ok = "✗ 没有这个节点！"
            print("      %-16s → %-18s %s" % (why, target, ok))

    print("\n（`?` = 从入口走不到。真走不到的要在数据里找找是不是漏接了）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
