"""切出**背景插画上没有的**物件贴图。

地图是整张画好的俯视图，桌子、床、货架、猫窝都画在上面了。
所以正常情况下**什么都不用切** —— 背景就是一切，`data/maps/*.json` 里的
`actors` 只负责「这块地方能交互」，画面交给插画。

只有两种东西需要单独一张图：

  1. **不在背景图里的独立素材。** 委托屋那张书桌是策划单独给的
     `书桌_无地毯.png`，背景图上那个位置是空的，不贴就看不见。
  2. **要从背景里单个拎出来的。** 卧室门口那盏提灯，策划要求它
     「始终遮盖主角图层」—— 背景层永远在角色底下，所以得单独一份、
     放到角色上面去（`Actor.over`）。

**别的都不要切。** 从插画上原样切一块再贴回原位是重复画两遍：
轻则白费，重则把站在旁边的人切成一条 —— 切图的 `rect` 比人宽的时候，
贴图会盖住角色（开发纪要 36 就是这么发现的）。

用法：
    python tools/slice_props.py

切完自己看一眼 `art/props/`，位置不对就调下面的框。
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## 独立书桌的源图。跟 `make_player_frames.py` 一样写成绝对路径 ——
## 策划给的素材放在项目外的「待用资源」里，切片脚本得能找到它。
## 换机器时改这一行。
SRC_DESK = r"C:\Users\q3382\Documents\GameProject\待用资源\地图\书桌_无地毯.png"

# (源图, 裁切框 left,top,right,bottom, 输出文件名)
#
# `rect`（在 `data/maps/*.json` 里）一律按「裁切框 ÷12」写，贴图和背景严丝合缝。
CUTS = [
    # --- 委托屋那张书桌：独立素材，背景图上没有它 ---
    # 源图四周有透明边，框按不透明内容定，切出来就是桌子本体。
    (SRC_DESK, (345, 223, 1377, 797), "desk.png"),
    # --- 卧室门口那盏提灯：从背景上拎出来，放到角色上面去 ---
    # 框 = `rect [117,292,13,28]` × 12。策划在碰撞示意图上用**纯白**标了它的位置。
    ("art/map/bedroom.png", (1404, 3504, 1560, 3840), "room_lamp.png"),
]


def main() -> None:
    out_dir = os.path.join(ROOT, "art", "props")
    os.makedirs(out_dir, exist_ok=True)
    cache = {}

    for rel, box, name in CUTS:
        # 项目外的绝对路径（独立物件的源图）直接用，其余按相对项目根解析
        src = rel if os.path.isabs(rel) else os.path.join(ROOT, rel.replace("/", os.sep))
        if src not in cache:
            cache[src] = Image.open(src)
        shot = cache[src].crop(box)
        dst = os.path.join(out_dir, name)
        shot.save(dst)
        print("切出 %-22s %s -> %s" % (name, box, shot.size))

    # 把切过的图的 .import 删掉，逼 Godot 重新导入。
    # 不删的话：源图换了、缓存里还是旧的那份，画面上不对而代码看不出毛病
    # （24 节踩过）。删 .import 是安全的，下次扫描会重建。
    dropped = 0
    for _rel, _box, name in CUTS:
        stale = os.path.join(out_dir, name + ".import")
        if os.path.exists(stale):
            os.remove(stale)
            dropped += 1
    if dropped:
        print("清掉 %d 个旧导入记录 —— 接着**必须**跑一次："
              "godot --headless --path . --import" % dropped)


if __name__ == "__main__":
    main()
