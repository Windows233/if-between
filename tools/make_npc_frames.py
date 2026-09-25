"""把 NPC 素材做成游戏里能直接用的帧图。

道理跟主角那套（`make_player_frames.py`）完全一样，只是 NPC 的素材更简单。
三件事：

1. 裁掉四周的透明边；
2. 同一批帧套**同一个**缩放系数 —— 帧与帧之间的相对大小是画师定好的；
3. 放进统一画布，**横向按脚底对齐、纵向底部对齐**。

**跟主角脚本的差别**（所以没有硬合并成一份）：

- 主角四个方向，NPC 现在只有**正面和背面**，策划给的素材就这两面；
- NPC 的文件名是 `<角色><朝向><序号>`，而且**第 1 帧不带数字**：
  `老奶正.png` 是第 1 帧、`老奶正2.png` 是第 2 帧；
- 一个脚本管所有 NPC，映射写在下面 `NPCS` 里。

用法：

    python tools/make_npc_frames.py
    godot --headless --path . --import      # 必须跟着跑一次

输出：`art/npc/<id>/<方向><序号>.png`，比如 `art/npc/elder/down1..4.png` 和 `up1.png`。

> `trimmed()` / `feet_x()` 是从 `make_player_frames.py` 抄过来的，逻辑一模一样。
> **改其中一份就要改另一份** —— 两边做的是同一件事，跑偏了会让主角和 NPC 的
> 脚底对齐规则悄悄分家。真到第三次抄的时候，就该抽成一个公共模块了。
"""
import glob
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = r"C:\Users\q3382\Documents\GameProject\待用资源\npc素材"
OUT_ROOT = os.path.join(ROOT, "art", "npc")

## 输出帧的高度。和主角取同一个值 —— 两边在游戏里的显示高度都是 45，
## 帧图尺度不一致的话，其中一边会被放大成糊的。
FRAME_HEIGHT = 360

## 要生成哪些 NPC：**输出目录名 -> 素材里的文件名前缀**。
##
## 加一个新 NPC：把素材丢进 `SRC_DIR`，命名照 `<前缀><朝向><序号>.png`，
## 然后在这儿加一行。没列进来的素材不会被碰（那个目录里还堆着别的东西）。
NPCS = {
    "elder": "老奶",
    # A（2026-09-24）：只有「侧面站着」和「蹲着」两个姿势，**没有走路动画** ——
    # 剧情里让他走那一下是「一边平移一边淡出」，不切走路帧。
    "a": "a",
    # 神秘人 B（2026-09-24）：也是静止的 —— 正面 + 背面各一张，
    # 只在第二遍集市那一幕站着说话，然后淡出。
    "b": "神秘",
}

## 文件名里那个朝向/姿势字 -> 输出名。
##
## 这东西本来是「方向」（正面 / 背面）。A 来了之后多两个**不是方向**的：
## `side` 是侧面站着、`crouch` 是蹲着。**帧目录和动画名的机制是一样的**
##（`art/npc/<id>/<名字><序号>.png` -> `idle_<名字>`），所以不再单独开一套，
## 只是心里要清楚：`crouch` 不是一个朝向，是一个姿势。
##
## 匹配是「前缀」匹配，所以**别加一个能被别人包含进来的短名**
##（加了个「侧」的话，「侧面」的图会被它先截走）。
DIR_NAMES = {
    "正": "down",
    "背": "up",
    "侧面": "side",
    "下蹲": "crouch",
}


def trimmed(img):
    """裁掉四周的透明边。"""
    box = img.getbbox()
    return img.crop(box) if box else img


def feet_x(img):
    """底部那条不透明像素的水平中心。

    按**脚**对齐比按包围盒中心稳：抬手或侧身的姿势包围盒会偏，
    照包围盒居中会让角色在走路时左右滑动。
    """
    width, height = img.size
    band = max(1, int(height * 0.06))
    alpha = img.getchannel("A").load()
    columns = []
    for y in range(height - band, height):
        for x in range(width):
            if alpha[x, y] > 16:
                columns.append(x)
    if not columns:
        return width // 2
    return (min(columns) + max(columns)) // 2


def collect(prefix: str) -> dict:
    """收一个 NPC 的帧，键是 `(方向, 序号)`。

    文件名形如 `<prefix><朝向><序号>.png`，**序号可以没有**（那就是第 1 帧）。
    朝向字必须认识，认不出来的直接跳过 —— 宁可少一帧让人看见，
    也别猜错方向把背面当正面。
    """
    frames = {}
    for path in sorted(glob.glob(os.path.join(SRC_DIR, "*.png"))):
        name = os.path.splitext(os.path.basename(path))[0]
        if not name.startswith(prefix):
            continue
        rest = name[len(prefix):]
        direction = None
        for cn, en in DIR_NAMES.items():
            if rest.startswith(cn):
                direction = en
                rest = rest[len(cn):]
                break
        if direction is None:
            print("提醒：%s 的朝向字不认识，跳过（认识的只有 %s）"
                  % (os.path.basename(path), "、".join(DIR_NAMES)))
            continue
        index = int(rest) if rest.isdigit() else 1
        frames[(direction, index)] = trimmed(Image.open(path).convert("RGBA"))
    return frames


def build(npc_id: str, prefix: str) -> int:
    frames = collect(prefix)
    if not frames:
        print("%s：素材目录里没找到以「%s」开头的图（%s）" % (npc_id, prefix, SRC_DIR))
        return 0

    # 一个系数管这个 NPC 的全部帧
    tallest = max(img.height for img in frames.values())
    scale = FRAME_HEIGHT / float(tallest)

    scaled = {}
    for key, img in frames.items():
        width = max(1, round(img.width * scale))
        height = max(1, round(img.height * scale))
        scaled[key] = img.resize((width, height), Image.LANCZOS)

    # 画布宽度按「脚底对齐之后谁都不出界」算，同一个 NPC 的所有帧共用
    half = 1
    for img in scaled.values():
        anchor = feet_x(img)
        half = max(half, anchor, img.width - anchor)
    canvas_w = half * 2
    canvas_h = max(img.height for img in scaled.values())

    out_dir = os.path.join(OUT_ROOT, npc_id)
    os.makedirs(out_dir, exist_ok=True)
    for (direction, index), img in sorted(scaled.items()):
        canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        anchor = feet_x(img)
        x = canvas_w // 2 - anchor
        y = canvas_h - img.height
        canvas.paste(img, (x, y), img)
        canvas.save(os.path.join(out_dir, "%s%d.png" % (direction, index)))

    # 旧帧先清掉：换了素材、某个方向少了一帧的话，多出来的旧图会留在目录里，
    # 被 `_scan_frames` 扫到就会去播一张早该消失的图。
    for name in os.listdir(out_dir):
        if name.endswith(".png.import"):
            os.remove(os.path.join(out_dir, name))
        elif name.endswith(".png"):
            stem = name[:-4]
            keep = any("%s%d" % (d, i) == stem for (d, i) in scaled)
            if not keep:
                os.remove(os.path.join(out_dir, name))
                print("  清掉多余的旧帧 %s" % name)

    counts = {}
    for (direction, _index) in scaled:
        counts[direction] = counts.get(direction, 0) + 1
    print("%s：画布 %dx%d，%s，缩放 %.4f  ->  art/npc/%s/"
          % (npc_id, canvas_w, canvas_h,
             "、".join("%s %d 帧" % (d, n) for d, n in sorted(counts.items())),
             scale, npc_id))
    return len(scaled)


def main() -> int:
    total = 0
    for npc_id, prefix in NPCS.items():
        total += build(npc_id, prefix)
    if total == 0:
        print("一个 NPC 的帧都没生成出来。")
        return 1
    print("共 %d 帧。接着**必须**跑一次：godot --headless --path . --import" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
