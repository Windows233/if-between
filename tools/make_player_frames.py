"""把主角小人的素材做成游戏里能直接用的帧。

策划给的是一张一张独立 PNG，尺寸不一样（422x729、446x733……）。
直接用有两个毛病：脚底不在一条线上（走起来像蹦），每帧的取景范围也不同。

这里只做三件事：

1. 裁掉四周的透明边；
2. 全部帧套**同一个**缩放系数 —— 各帧之间的相对大小是画师定好的，逐帧
   归一化会把「抬手的姿势」和「站直的姿势」拉成一样高；
3. 放进统一画布，**横向按脚底对齐、纵向底部对齐** —— 脚底就是角色的原点。

**不做的事：不把图缩到「游戏里显示的大小」。**
显示多大由 `scenes/player.gd` 的 `DISPLAY_HEIGHT` 配合节点 `scale` 在运行时决定。
提前压到十几像素高，画面上再放大好几倍，就是一团糊 —— 这个坑踩过一次。

用法：
    python tools/make_player_frames.py
    godot --headless --path . --import      # 必须跟着跑一次

输出：`art/player/<方向><序号>.png`
     up1..up3 / side1..side4 / down1..down4
"""
import glob
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
## 素材目录。**策划按方向分好了子目录**：
##
##   主角素材/正面/f1..f4.png
##   主角素材/侧面/侧面1..4.png
##   主角素材/背面/背面1..3.png
##
## 三个方向的文件名各叫各的（正面用 `f`，另两个用中文），所以这里
## **看目录名定方向、看文件名里的数字定序号**，不去猜前缀。
##
## 老路径 `待用资源\主角小人素材`（平铺、统一叫「正面1.png」）**2026-09-24 已经没有了** ——
## 策划重组过目录。那之后脚本指着空目录，跑起来只会说「没找到图」，
## 而画面上一点异常都没有（旧帧还在），所以坏了也不知道。
SRC_DIR = r"C:\Users\q3382\Documents\GameProject\待用资源\主角素材"
OUT_DIR = os.path.join(ROOT, "art", "player")

## 输出帧的高度（最高的那一帧缩到这个高度，其余按同一比例）。
##
## 为什么要这么高：游戏里的显示高度是 `Player.DISPLAY_HEIGHT`（现在 45），
## 1080p 全屏下每个游戏坐标 = 6 个屏幕像素，角色在屏幕上约 270 像素高。
## 帧图至少要这么多，才不至于被放大成糊的。
##
## 取 360 —— 对 45 是 8 倍余量，和上一版（显示 28 / 帧图 224）同一个尺度。
## 改 `DISPLAY_HEIGHT` 时这里跟着按同样的倍数改。
FRAME_HEIGHT = 360

## 素材里的方向名 -> 输出的方向前缀。**键就是子目录名。**
DIRS = {
    "背面": "up",
    "侧面": "side",
    "正面": "down",
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


def collect() -> dict:
    """把三个方向目录里的图收成 `{(方向, 序号): 图}`。

    **方向看目录，序号看文件名里的数字** —— 三个方向的命名不统一
    （`f1` / `侧面1` / `背面2`），按前缀猜很容易漏掉一整个方向，
    而漏掉的方向只会「沿用旧帧」，画面上看不出来。
    """
    frames = {}
    for cn, en in DIRS.items():
        folder = os.path.join(SRC_DIR, cn)
        if not os.path.isdir(folder):
            print("提醒：方向目录不在：%s" % folder)
            continue
        for path in sorted(glob.glob(os.path.join(folder, "*.png"))):
            name = os.path.splitext(os.path.basename(path))[0]
            digits = re.findall(r"\d+", name)
            if not digits:
                print("提醒：%s 的文件名里没有序号，跳过" % os.path.basename(path))
                continue
            index = int(digits[-1])
            frames[(en, index)] = trimmed(Image.open(path).convert("RGBA"))
    return frames


def main() -> int:
    frames = collect()

    if not frames:
        print("素材目录里没找到图：%s" % SRC_DIR)
        return 1

    print("收到 " + "、".join(
        "%s %d 帧" % (en, sum(1 for k in frames if k[0] == en))
        for cn, en in DIRS.items() if any(k[0] == en for k in frames)))

    # 一个系数管全部帧：帧与帧之间的相对大小保持原样
    tallest = max(img.height for img in frames.values())
    scale = FRAME_HEIGHT / float(tallest)

    scaled = {}
    for key, img in frames.items():
        width = max(1, round(img.width * scale))
        height = max(1, round(img.height * scale))
        scaled[key] = img.resize((width, height), Image.LANCZOS)

    # 画布宽度按「脚底对齐之后谁都不出界」算
    half = 1
    for img in scaled.values():
        anchor = feet_x(img)
        half = max(half, anchor, img.width - anchor)
    canvas_w = half * 2
    canvas_h = max(img.height for img in scaled.values())

    os.makedirs(OUT_DIR, exist_ok=True)
    for (direction, index), img in sorted(scaled.items()):
        canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        anchor = feet_x(img)
        # 横向：脚底对到画布中线；纵向：底部对齐
        x = canvas_w // 2 - anchor
        y = canvas_h - img.height
        canvas.paste(img, (x, y), img)
        dst = os.path.join(OUT_DIR, "%s%d.png" % (direction, index))
        canvas.save(dst)

    # 把旧的 .import 删掉，逼 Godot 重新导入。
    # 不删的话：源图换过、但已导入的那份还在缓存里，直接跑游戏用的还是旧图
    # —— 画面上不对，代码却看不出毛病。删 .import 是安全的，下次扫描会重建。
    dropped = 0
    for name in os.listdir(OUT_DIR):
        if name.endswith(".png.import"):
            os.remove(os.path.join(OUT_DIR, name))
            dropped += 1

    print("画布 %dx%d，共 %d 帧，缩放系数 %.4f"
          % (canvas_w, canvas_h, len(scaled), scale))
    if dropped:
        print("清掉 %d 个旧导入记录 —— 接着**必须**跑一次："
              "godot --headless --path . --import" % dropped)
    return 0


if __name__ == "__main__":
    sys.exit(main())
