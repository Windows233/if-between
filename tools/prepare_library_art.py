"""Prepare the supplied library layers; write map data through MapEditModel separately."""

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


MAP_SIZE = (467, 374)
SHELVES = [
    ("shelf_a", (113, 108, 152, 191), (117, 173, 30, 14)),
    ("shelf_b", (316, 108, 354, 191), (321, 171, 30, 15)),
    ("shelf_c", (113, 200, 152, 282), (118, 261, 29, 14)),
    ("shelf_d", (316, 200, 354, 282), (321, 261, 30, 16)),
    ("shelf_nw", (115, 45, 214, 104), (119, 88, 91, 10)),
    ("shelf_ne", (252, 45, 379, 104), (257, 88, 117, 10)),
    ("shelf_w", (48, 104, 78, 269), (50, 118, 23, 147)),
    ("shelf_e", (389, 78, 421, 269), (390, 100, 24, 164)),
    ("shelf_sw", (103, 281, 185, 326), (107, 304, 75, 7)),
    ("shelf_se", (282, 281, 365, 326), (287, 304, 74, 7)),
]
DETAILS = [
    ("library_altar", [(217, 104), (217, 87), (220, 87), (220, 79),
                       (227, 79), (229, 84), (237, 78), (246, 81),
                       (250, 90), (250, 107), (217, 107)], (217, 100, 32, 7)),
    ("library_plant", [(52, 267), (58, 263), (66, 268), (67, 264),
                       (76, 264), (78, 273), (85, 275), (85, 298),
                       (81, 298), (81, 305), (55, 305), (55, 296),
                       (51, 292), (51, 280), (54, 278)], (51, 289, 33, 16)),
    ("library_reading_desk", [(376, 285), (376, 266), (380, 264),
                              (395, 264), (399, 260), (406, 263),
                              (411, 267), (415, 267), (415, 293),
                              (412, 293), (412, 307), (404, 307),
                              (401, 303), (392, 303), (392, 307),
                              (385, 307), (385, 295), (380, 295),
                              (380, 286)], (378, 287, 37, 18)),
]


def pixel_box(bounds, size):
    return tuple(round(value * size[index % 2] / MAP_SIZE[index % 2])
                 for index, value in enumerate(bounds))


def save_piece(image, bounds, actor_id, collision, output):
    box = pixel_box(bounds, image.size)
    piece = image.crop(box)
    tight = piece.getbbox()
    if tight is None:
        raise ValueError(f"Empty cutout: {actor_id}")
    piece = piece.crop(tight)
    origin = (box[0] + tight[0], box[1] + tight[1])
    rect = [origin[0] * MAP_SIZE[0] / image.width,
            origin[1] * MAP_SIZE[1] / image.height,
            piece.width * MAP_SIZE[0] / image.width,
            piece.height * MAP_SIZE[1] / image.height]
    piece.save(output / f"library_{actor_id}_cover.png")
    return {"id": actor_id, "rect": rect,
            "sprite": f"res://art/props/library_{actor_id}_cover.png",
            "collision_world": list(collision)}


def prepare(source, project):
    background = Image.open(source / "图书馆1_upscayl_4x_upscayl-standard-4x.png").convert("RGBA")
    shelves = Image.open(source / "书柜_upscayl_4x_upscayl-standard-4x.png").convert("RGBA")
    foreground = Image.open(source / "底墙_upscayl_4x_upscayl-standard-4x.png").convert("RGBA")
    furniture = Image.open(source / "墙_upscayl_4x_upscayl-standard-4x.png").convert("RGBA")
    output = project / "art/props"
    review = project / ".godot/library_review"
    review.mkdir(parents=True, exist_ok=True)
    background.convert("RGB").save(project / "art/map/library.png")
    items = [save_piece(shelves, bounds, actor_id, collision, output)
             for actor_id, bounds, collision in SHELVES]
    for actor_id, polygon, collision in DETAILS:
        mask = Image.new("L", furniture.size)
        points = [(round(x * furniture.width / MAP_SIZE[0]),
                   round(y * furniture.height / MAP_SIZE[1])) for x, y in polygon]
        ImageDraw.Draw(mask).polygon(points, fill=255)
        layer = furniture.copy()
        layer.putalpha(ImageChops.multiply(mask, furniture.getchannel("A")))
        bounds = (min(x for x, _ in polygon), min(y for _, y in polygon),
                  max(x for x, _ in polygon) + 1, max(y for _, y in polygon) + 1)
        items.append(save_piece(layer, bounds, actor_id, collision, output))
    for left, top, right, bottom in [(103, 281, 185, 310), (282, 281, 365, 310)]:
        foreground.paste((0, 0, 0, 0), pixel_box((left, top, right, bottom), foreground.size))
    foreground.save(project / "art/map/library_wall.png")
    payload = {"actors": items, "walls": [
        [0, 0, 467, 34], [0, 34, 50, 316], [437, 34, 30, 316],
        [32, 34, 405, 66], [414, 100, 23, 204],
        [32, 311, 173, 39], [263, 311, 174, 39],
        [189, 284, 16, 66], [263, 284, 16, 66], [0, 350, 467, 24]],
        "spawn": [233, 296]}
    manifest = review / "layout.json"
    manifest.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    canvas = background.convert("RGB").resize((934, 748))
    draw = ImageDraw.Draw(canvas, "RGBA")
    for wall in payload["walls"]:
        left, top, width, height = wall
        draw.rectangle((left * 2, top * 2, (left + width) * 2, (top + height) * 2),
                       fill=(255, 40, 40, 75), outline=(255, 70, 70, 230))
    for item in items:
        left, top, width, height = item["collision_world"]
        draw.rectangle((left * 2, top * 2, (left + width) * 2, (top + height) * 2),
                       fill=(255, 140, 0, 95), outline=(255, 210, 0, 255))
        left, top, width, height = item["rect"]
        draw.rectangle((left * 2, top * 2, (left + width) * 2, (top + height) * 2),
                       outline=(30, 255, 130, 220))
        draw.text((left * 2, top * 2 - 12), item["id"], fill="white")
    canvas.save(review / "collision_review.png")
    columns = 5
    sheet = Image.new("RGB", (columns * 280, math.ceil(len(items) / columns) * 260), "#454545")
    draw = ImageDraw.Draw(sheet)
    for index, item in enumerate(items):
        cutout = Image.open(output / Path(item["sprite"]).name)
        cutout.thumbnail((264, 230))
        offset = ((index % columns) * 280 + 8, (index // columns) * 260 + 22)
        sheet.paste(cutout, offset, cutout)
        draw.text((offset[0], offset[1] - 17), item["id"], fill="white")
    sheet.save(review / "cutouts.png")
    print(f"Prepared {len(items)} cutouts; editor input: {manifest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    arguments = parser.parse_args()
    prepare(arguments.source, arguments.project)
