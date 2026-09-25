"""生成占位美术：一块带描边的抽象色块，中间写上它叫什么。

美术没到的资源先拿这个顶着，至少玩的时候一眼看得出「这是什么东西」。
真图到位后，把对应的 png 覆盖掉即可，数据和代码一行都不用改。

用法：
    python tools/make_placeholders.py

缺什么就往 `PLACEHOLDERS` 里加一行。
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
]

FONT_SIZE = 22
TEXT_COLOR = (238, 238, 238)
EDGE_COLOR = (16, 18, 24)
EDGE_WIDTH = 4

# (输出路径, 显示的文字, 尺寸, 底色)
PLACEHOLDERS = [
    # --- 角色立绘 ---
    ("art/portrait/a.png", "A\n修留声机的少年", (256, 256), "#6f8f7a"),
    ("art/portrait/passerby.png", "路人", (256, 256), "#6f6f7a"),
    # --- 场景背景。第一章只有委托屋、集市、商店、城邦地图四处 ---
    ("art/map/shop.png", "商店", (320, 180), "#3a3346"),
    # 已经有真图，别再生成覆盖：`protagonist/*`、`elder`、`mysterious`、
    # `cat_photo`、`pendant`、`desk_shop`、`market`、`overworld`。
    # 后面的章节（死巷/蚀界/校区）美术没到再说，到时往这张表里加一行就行。
]


def _font() -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, FONT_SIZE)
    return ImageFont.load_default()


def make_block(text: str, size: tuple, color: str) -> Image.Image:
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 场景背景要铺满整个画面，字太小站在上面看不清
    font = ImageFont.truetype(_font_path(), 34 if min(size) <= 200 else FONT_SIZE) \
        if _font_path() else ImageFont.load_default()

    x0, y0 = EDGE_WIDTH, EDGE_WIDTH
    x1, y1 = size[0] - EDGE_WIDTH - 1, size[1] - EDGE_WIDTH - 1
    draw.rectangle([x0, y0, x1, y1], fill=color, outline=EDGE_COLOR, width=EDGE_WIDTH)

    lines = text.split("\n")
    line_height = 40 if min(size) <= 200 else FONT_SIZE + 6
    top = (size[1] - line_height * len(lines)) / 2
    for index, line in enumerate(lines):
        box = draw.textbbox((0, 0), line, font=font)
        width = box[2] - box[0]
        left = (size[0] - width) / 2 - box[0]
        draw.text((left, top + index * line_height - box[1]), line,
                  font=font, fill=TEXT_COLOR)
    return img


def _font_path() -> str:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return path
    return ""


def main() -> None:
    for rel, text, size, color in PLACEHOLDERS:
        out = os.path.join(ROOT, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        make_block(text, size, color).save(out)
        print("占位 ->", rel)


if __name__ == "__main__":
    main()
