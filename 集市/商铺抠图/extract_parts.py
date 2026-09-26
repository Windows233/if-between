# -*- coding: utf-8 -*-
"""从三张商铺素材图中抠出每个组成部分,导出透明 PNG + 位置 JSON + 对照图。"""
import numpy as np, cv2, json, os
from PIL import Image, ImageDraw, ImageFont

SRC_DIR = r"D:\游戏制作\地图\集市\商铺"
OUT_DIR = r"D:\游戏制作\地图\集市\商铺\抠图"
os.makedirs(OUT_DIR, exist_ok=True)

FONT = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 28)

# 每张图的连通域 -> 部件名映射;粘连块用切分指令处理
# split: ('col', cut) 表示该连通域在局部坐标 cut 列处左右分开; ('row', cut) 上下分开
SHEETS = {
    "IMG_3992": {
        "outdir": "IMG_3992_书店铺",
        "items": [
            {"blob": 1, "name": "完整商铺"},
            {"blob": 2, "name": "紫色顶棚", "split": ("col", 950), "side": "left"},
            {"blob": 2, "name": "书架",     "split": ("col", 950), "side": "right"},
            {"blob": 3, "name": "花桶"},
            {"blob": 4, "name": "旗帜旗杆"},
            {"blob": 5, "name": "茶壶",     "split": ("row", 298), "side": "top"},
            {"blob": 5, "name": "价目牌",   "split": ("row", 298), "side": "bottom"},
            {"blob": 6, "name": "星盘柜"},
            {"blob": 7, "name": "书桌"},
            {"blob": 8, "name": "小凳"},
        ],
    },
    "IMG_3993": {
        "outdir": "IMG_3993_药剂铺",
        "items": [
            {"blob": 1, "name": "完整商铺"},
            {"blob": 2, "name": "药材架"},
            {"blob": 3, "name": "药剂架"},
            {"blob": 4, "name": "药剂架提灯"},
            {"blob": 5, "name": "坩埚花桶"},
            {"blob": 6, "name": "价目牌"},
            {"blob": 7, "name": "小桌"},
            {"blob": 8, "name": "细杆"},
        ],
    },
    "IMG_3994": {
        "outdir": "IMG_3994_武器铺",
        "items": [
            {"blob": 1, "name": "完整商铺"},
            {"blob": 2, "name": "盾牌展桌"},
            {"blob": 3, "name": "剑架"},
            {"blob": 4, "name": "花桶组合"},
            {"blob": 5, "name": "武器工作台"},
            {"blob": 6, "name": "木桶组合"},
        ],
    },
}

def checker(w, h, s=32):
    t = np.zeros((h, w, 3), np.uint8)
    for yy in range(0, h, s):
        for xx in range(0, w, s):
            c = 200 if ((xx // s + yy // s) % 2 == 0) else 255
            t[yy:yy + s, xx:xx + s] = c
    return t

def save_png(path, rgba):
    im = Image.fromarray(rgba)
    im.save(path)  # PIL 写盘,避免 cv2 中文路径问题

def collage(item_tiles, out_path, title):
    """部件对照表:棋盘格背景 + 名称 + 尺寸"""
    pad, label_h, cw = 24, 56, 560
    tiles = []
    for name, rgba, (rx, ry) in item_tiles:
        h, w = rgba.shape[:2]
        scale = min(1.0, cw / max(w, h))
        nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
        a = rgba[:, :, 3:4].astype(np.float32) / 255
        bg = checker(nw, nh)
        comp = (rgba[:, :, :3] * a + bg * (1 - a)).astype(np.uint8)
        comp = cv2.resize(comp, (nw, nh), interpolation=cv2.INTER_AREA)
        tiles.append((name, comp, (rx, ry), (w, h)))
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    cell_h = max(t[1].shape[0] for t in tiles) + label_h + pad * 2
    W = cols * (cw + pad) + pad
    H = rows * cell_h + pad + 80
    sheet = np.full((H, W, 3), 34, np.uint8)
    for i, (name, comp, pos, wh) in enumerate(tiles):
        r, c = divmod(i, cols)
        x0 = pad + c * (cw + pad) + (cw - comp.shape[1]) // 2
        y0 = pad + 80 + r * cell_h
        sheet[y0:y0 + comp.shape[0], x0:x0 + comp.shape[1]] = comp
        pil = Image.fromarray(sheet)
        d = ImageDraw.Draw(pil)
        d.text((pad + c * (cw + pad) + 4, y0 + comp.shape[0] + 6),
               "%s  %dx%d" % (name, wh[0], wh[1]), font=FONT, fill=(230, 230, 230))
        d.text((pad + c * (cw + pad) + 4, y0 + comp.shape[0] + 40),
               "位置(%d,%d)" % pos, font=FONT, fill=(150, 150, 150))
        sheet = np.array(pil)
    pil = Image.fromarray(sheet)
    d = ImageDraw.Draw(pil)
    big = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 44)
    d.text((pad, 14), title, font=big, fill=(240, 240, 240))
    pil.save(out_path)

report = []
for src_name, cfg in SHEETS.items():
    im = Image.open(os.path.join(SRC_DIR, src_name + ".PNG")).convert("RGBA")
    arr = np.array(im)
    full_mask = (arr[:, :, 3] > 10)
    nlab, labels, stats, cent = cv2.connectedComponentsWithStats(full_mask.astype(np.uint8), 8)

    outdir = os.path.join(OUT_DIR, cfg["outdir"])
    os.makedirs(outdir, exist_ok=True)
    item_tiles, meta, covered = [], [], np.zeros_like(full_mask)

    for idx, item in enumerate(cfg["items"], 1):
        b = item["blob"]
        x, y, w, h, area = stats[b]
        m = (labels[y:y + h, x:x + w] == b)
        if "split" in item:
            axis, cut = item["split"]
            if axis == "col":
                keep = (np.arange(w) < cut) if item["side"] == "left" else (np.arange(w) >= cut)
                m = m & keep[None, :]
            else:
                keep = (np.arange(h) < cut) if item["side"] == "top" else (np.arange(h) >= cut)
                m = m & keep[:, None]
        if not m.any():
            report.append("!! %s %s 空掩码" % (src_name, item["name"]))
            continue
        ys, xs = np.where(m)
        cy0, cy1, cx0, cx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        sub = arr[y + cy0:y + cy1, x + cx0:x + cx1].copy()
        sub[~m[cy0:cy1, cx0:cx1]] = 0
        covered[y:y + h, x:x + w] |= m
        fname = "%02d_%s.png" % (idx, item["name"])
        save_png(os.path.join(outdir, fname), sub)
        gx, gy = x + cx0, y + cy0  # 源图全局坐标
        meta.append({"file": fname, "name": item["name"],
                     "x": int(gx), "y": int(gy), "w": int(cx1 - cx0), "h": int(cy1 - cy0),
                     "pixels": int(m.sum())})
        item_tiles.append((item["name"], sub, (gx, gy)))

    # 校验:所有部件掩码之并 == 原图前景 (无丢失/无重复)
    lost = int(full_mask.sum() - covered.sum())
    report.append("%s: %d 个部件, 像素覆盖差值=%d %s" %
                  (src_name, len(meta), lost, "OK" if lost == 0 else "有丢失!"))
    with open(os.path.join(outdir, "_部件位置.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)

    # 对照图缩略导出(限制总宽)
    tiles_small = []
    for name, rgba, pos in item_tiles:
        hh, ww = rgba.shape[:2]
        s = min(1.0, 560 / max(hh, ww))
        small = cv2.resize(rgba, (max(1, int(ww * s)), max(1, int(hh * s))), interpolation=cv2.INTER_AREA) if s < 1 else rgba
        tiles_small.append((name, small, pos))
    collage(tiles_small, os.path.join(OUT_DIR, "对照图_%s.png" % cfg["outdir"]),
            "%s 部件对照表(共 %d 件)" % (cfg["outdir"], len(item_tiles)))

print("\n".join(report))
