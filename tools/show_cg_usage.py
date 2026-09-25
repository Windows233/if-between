#!/usr/bin/env python3
"""列出所有「播过 CG」的节点，看它是怎么收场的、留了多久。

用法：
    python tools/show_cg_usage.py

两个常犯的毛病（都是策划报过的）：

  **① 收 CG 时闪回原场景。** 收掉 CG 的那半秒，露出来的是**背后的场景** ——
  黑幕（`StageCurtain`，5 层）比演出层（14 层）低，所以「先收 CG 再黑屏」
  那种写法，收的时候黑还没下来。**先 `fade to black` 再 `image_hide`。**

  **② CG 一闪而过。** `_image` 的默认值凑在一起是个坑：`hold` 不写是 0、
  `hide` 不写是 true —— 合起来就是「淡入完立刻淡出」。
  要停够就写 `hold`、或 `wait_click: true`、或 `hide: false` 留着。

**判断会不会闪的口径**：CG 收掉之前，屏幕上有没有一层黑。
"""
import io
import json
import os

EVENTS = os.path.join(r"C:\Users\q3382\Documents\GameProject\if：如果之间",
                      "data", "events")

# 「会遮住画面」的指令。有它在，收 CG 的时候露出来的是黑，不是场景
BLACKEN = {"fade", "blackout"}
# 「CG 收场」
HIDE = {"image_hide"}


def main():
    for name in sorted(os.listdir(EVENTS)):
        if not name.endswith(".json"):
            continue
        data = json.load(io.open(os.path.join(EVENTS, name), encoding="utf-8"))
        for node in data.get("nodes", []):
            steps = node.get("stage", [])
            if not any(s.get("do") == "image" for s in steps):
                continue
            print("\n=== %s / %s ===" % (name[:-5], node["id"]))
            black = False
            cg_up = None
            for i, step in enumerate(steps):
                do = step.get("do", "")
                if do == "image":
                    path = os.path.basename(str(step.get("path", "")))
                    if cg_up is not None:
                        tail = "  ← 被顶掉" + ("（有黑屏挡着）" if black else "，没黑屏")
                        print("  %2d image       %s%s" % (i, path, tail))
                    else:
                        fill = step.get("fill", False)
                        hide = step.get("hide", True)
                        hold = step.get("hold", 0)
                        wait = step.get("wait_click", False)
                        # 只对「铺满的、会自己收的」图挑停留时间的毛病
                        warn = ""
                        if fill and hide and not wait and float(hold or 0) < 1.5:
                            warn = "   ← ★ 铺满的 CG 留太短，一闪而过"
                        print("  %2d image       %-22s fade=%-5s hold=%-5s hide=%-5s "
                              "fill=%-5s wait_click=%s%s"
                              % (i, path, step.get("fade"), hold, hide, fill, wait, warn))
                    cg_up = i
                elif do in HIDE:
                    mark = "" if black else "   ← ★ 没黑屏就收，会闪回原场景"
                    print("  %2d image_hide  fade=%s%s" % (i, step.get("fade"), mark))
                    cg_up = None
                elif do == "fade":
                    to = step.get("to")
                    if to == "black":
                        black = True
                        print("  %2d fade        black（%s）" % (i, step.get("time")))
                    elif to == "clear":
                        black = False
                        print("  %2d fade        clear（%s）" % (i, step.get("time")))
                elif do in ("goto", "place_player", "say", "caption", "glass", "shatter"):
                    mark = ""
                    if cg_up is not None and do == "goto" and not black:
                        mark = "   ← ★ CG 还立着就换场景"
                    print("  %2d %-12s%s" % (i, do, mark))


if __name__ == "__main__":
    main()
