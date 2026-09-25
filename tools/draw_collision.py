"""把地图数据里的碰撞箱画在背景图上，用来核对。

碰撞是看不见的：数据写错了，画面上完全看不出来，只有玩到那儿才发现
「怎么走不过去」。这个脚本把 `walls` 涂成半透明红、`portals` 涂成青，
叠在背景图上面输出一张对照图，肉眼一比就知道对不对。

用法：
    python tools/draw_collision.py desk_shop
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "docs", "screenshots")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    map_id = sys.argv[1]
    path = os.path.join(ROOT, "data", "maps", "%s.json" % map_id)
    data = json.load(open(path, encoding="utf-8"))
    size = data["size"]

    bg_rel = data.get("background", "")
    if bg_rel:
        bg = Image.open(os.path.join(ROOT, bg_rel.replace("res://", "").replace("/", os.sep)))
        bg = bg.convert("RGBA").resize((size[0], size[1]))
    else:
        bg = Image.new("RGBA", (size[0], size[1]), (30, 32, 40, 255))

    # 放大四倍再看，不然小图看不出边界差一两像素
    k = 4
    bg = bg.resize((size[0] * k, size[1] * k), Image.NEAREST)

    # **独立贴图的家具也要贴上去。** 书桌这种东西不画在背景图里，
    # 只画背景的话那块地方是一片空地板 —— 对照图上就看不出
    # 碰撞箱和家具本体差了多远，而这正是要核对的东西。
    for actor in data.get("actors", []):
        sprite = actor.get("sprite", "")
        if not sprite:
            continue
        p = os.path.join(ROOT, sprite.replace("res://", "").replace("/", os.sep))
        if not os.path.isfile(p):
            print("提醒：%s 的贴图找不到（%s）" % (actor.get("id"), sprite))
            continue
        rx, ry, rw, rh = actor["rect"]
        shot = Image.open(p).convert("RGBA").resize((rw * k, rh * k), Image.LANCZOS)
        bg.alpha_composite(shot, (rx * k, ry * k))

    layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def box(rect, fill, outline):
        x, y, w, h = rect
        d.rectangle([x * k, y * k, (x + w) * k - 1, (y + h) * k - 1],
                    fill=fill, outline=outline, width=1)

    def outline(rect, colour):
        x, y, w, h = rect
        d.rectangle([x * k, y * k, (x + w) * k - 1, (y + h) * k - 1],
                    outline=colour, width=2)

    for wall in data.get("walls", []):
        box(wall, (255, 40, 40, 110), (255, 60, 60, 230))
    for portal in data.get("portals", []):
        box(portal["rect"], (0, 220, 255, 110), (0, 240, 255, 230))
    for actor in data.get("actors", []):
        box(actor["rect"], (60, 255, 60, 70), (80, 255, 80, 200))
        # 够得着的范围（写了才有）：橙色框。它只影响「点不点得到」，不挡路。
        if "reach" in actor:
            outline(actor["reach"], (255, 180, 40, 240))

    out = Image.alpha_composite(bg, layer).convert("RGB")
    os.makedirs(OUT_DIR, exist_ok=True)
    dst = os.path.join(OUT_DIR, "collision_%s.png" % map_id)
    out.save(dst)
    print("红=实体  青=传送点  绿=物件本体  橙=够得着的范围")
    print("写出", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
