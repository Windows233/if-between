"""从「碰撞与交互示意图」里读出碰撞箱。

策划画的示意图就是标准答案。两种画法都支持：

**① 绿 / 青 / 白**（房间那几张）
绿色 = 实体（走不过去），青色 = 传送点，纯白 = 独立物件。

**② 红 / 蓝**（集市那张，2026-09-24）
红 = 实体，蓝 = 传送区。这一种**必须连底图一起给**，因为：
  - 红是**半透明罩在画上的**（房屋、树丛都是被罩红的），
    纯红平涂只占一小部分 —— 只能跟底图作差才认得出来；
  - 蓝更是要作差：图上本来就到处是蓝花、蓝瓦、蓝旗。

用法：
    python tools/extract_collision.py <示意图> [缩放系数] [底图]
    # ②：python tools/extract_collision.py <示意图> 0.0833333 <底图>

缩放系数 = 游戏坐标 ÷ 原图像素。比如 5552 宽的图要放进 463 宽的地图，
系数就是 1/12 ≈ 0.08333。6688 宽的集市图同样是 1/12。

输出是能直接粘进 `data/maps/*.json` 的 `walls` / 传送点矩形。

**为什么用 numpy。** 高清图有 2500 万像素，纯 Python 逐点扫要跑好几分钟；
换成 numpy 找边界的办法是几秒。算法没变，变的是「怎么找出每行的色块起止」。
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


# 绿 / 青 / 白的判定：主通道拉满，另外两通道压得很低。jpg 有压缩噪点，阈值放宽些。
def green_mask(img: Image.Image) -> np.ndarray:
    a = np.asarray(img).astype(np.int16)
    return (a[:, :, 1] > 180) & (a[:, :, 0] < 120) & (a[:, :, 2] < 120)


def cyan_mask(img: Image.Image) -> np.ndarray:
    a = np.asarray(img).astype(np.int16)
    return (a[:, :, 1] > 150) & (a[:, :, 2] > 150) & (a[:, :, 0] < 120)


def white_mask(img: Image.Image) -> np.ndarray:
    """纯白。策划拿它标**独立物件**（卧室那盏灯）。

    「纯白」是严格判的（三个通道都在 245 以上）：石墙的高光、窗户里的云
    都到不了这个数，所以不会误伤。实测卧室图上只有左下角那一块。
    """
    a = np.asarray(img).astype(np.int16)
    return (a[:, :, 0] > 245) & (a[:, :, 1] > 245) & (a[:, :, 2] > 245)


## 红 / 蓝那套的阈值。量过的数就写在这儿，别在别处再抄一份。
##
## 「红」看的是 `(R − B)` 相对底图涨了多少：底图那块本来是什么颜色都不影响，
## 只认「被罩红了」。实测被罩红的建筑/树丛在 100 以上，广场地面在 0 附近，
## 取 60 中间偏安全。
##
## 「蓝」看的是 `(B − R)` 相对底图涨了多少。叠在地毯上的那块是 +91，
## 叠在石阶上的是 +38 —— 取 25。**不能再低**：图上的蓝花蓝瓦本来就有
## 一大片 B−R 为正的地方，底图一作差才压得住。
RED_TINT = 60
BLUE_TINT = 25
## 作差和开运算都缩小了做。全分辨率上一次开运算要几分钟，
## 而这层色块本来就是大块，缩小 8 倍不影响边界（误差半个格子 ≈ 0.7 游戏像素）。
DOWNSCALE = 8


def _tint_score(img: Image.Image, base: Image.Image, s: int, blue: bool) -> np.ndarray:
    """缩小 `s` 倍之后，逐点的「变红了多少 / 变蓝了多少」。"""
    a = np.asarray(base.resize((base.width // s, base.height // s), Image.BOX)).astype(np.int32)
    d = np.asarray(img.resize((img.width // s, img.height // s), Image.BOX)).astype(np.int32)
    if blue:
        return (d[:, :, 2] - d[:, :, 0]) - (a[:, :, 2] - a[:, :, 0])
    return (d[:, :, 0] - d[:, :, 2]) - (a[:, :, 0] - a[:, :, 2])


## 合并容差。**这一步是缩小的那层上的像素**，1 格 = `DOWNSCALE` 个原图像素
## = 0.67 个游戏像素。3 就是允许边界抖 2 个游戏像素。
##
## 别拿原图尺度的 2 来套：缩完再放大的图，边界是「8 像素一格」的台阶，
## 相邻两行能差 8 —— 用 2 当容差的结果是一块墙被切成几十条 2 像素的碎条
##（2026-09-24 集市那张图实测过）。
TINT_MERGE_TOL = 6


def red_wall_rects(img: Image.Image, base: Image.Image, k: float,
                   s: int = DOWNSCALE, thr: int = RED_TINT) -> list:
    """被罩红的地方 → 游戏坐标的实体矩形。

    **全程在缩小那层做完再换算**，不回原图。原图 2500 万像素上做逐行合并
    既慢，又会因为边界台阶切出一堆碎条（见 `TINT_MERGE_TOL`）。
    """
    score = _tint_score(img, base, s, blue=False)
    # 闭运算 5×5（≈3.3 游戏像素）：把叶边、屋顶那些碎口填平，块数能少一半。
    # 只填凹口，不往外撑 —— 所以不会吃掉广场。
    m = ndimage.binary_closing(score > thr, np.ones((5, 5), bool))
    rects = runs_to_rects(mask_runs(m), tol=TINT_MERGE_TOL)
    f = s * k
    out = [[round(x * f), round(y * f), max(1, round(w * f)), max(1, round(h * f))]
           for x, y, w, h in rects]
    return drop_slivers(out)


def blue_portal_rects(img: Image.Image, base: Image.Image, k: float,
                      s: int = DOWNSCALE, thr: int = BLUE_TINT) -> list:
    """被罩蓝的地方 → 游戏坐标的传送区。

    **用连通域的外框，不用逐行合并。** 传送区是一块一块独立的色斑，
    外框正是要的东西；逐行合并会在一块斑中间断开的地方裂成两条
    （左上那处实测裂成了 [20,78,40,7] + [19,85,41,6]）。
    """
    score = _tint_score(img, base, s, blue=True)
    m = ndimage.binary_opening(score > thr, np.ones((3, 3), bool))
    m = ndimage.binary_closing(m, np.ones((5, 5), bool))
    lab, n = ndimage.label(m)
    f = s * k
    out = []
    for sl in ndimage.find_objects(lab):
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        w, h = x1 - x0, y1 - y0
        # 小于 200 格（≈ 10×10 游戏像素）的多半是蓝花、蓝瓦的残留。
        # **别再提高了**：大房子门口那块（蓝垫子 30×11 格）本来就是最小的一个，
        # 门槛抬到 400 就把它滤没了（2026-09-24 第一次跑就是这么丢的）。
        if w * h < 200:
            continue
        out.append([round(x0 * f), round(y0 * f), max(1, round(w * f)), max(1, round(h * f))])
    out.sort(key=lambda r: (r[1], r[0]))
    return out




def close_holes(mask: np.ndarray, size: int = 5) -> np.ndarray:
    """把 1~2 像素的小洞和小凹口填掉。

    **为什么必须做**：图是 jpg 压过的，色块边缘会有一两像素的杂色行。
    这些洞会让「逐行合并」把一个完整的大块切成好几条 ——
    委托屋那张图正好没有，卧室这张右侧一列 96×60 的墙被切成了 9 条
    1 像素高的薄片，其中还有 1×1 的。

    闭运算 = 先膨胀再腐蚀，只填凹口和洞，**不会把边界整体撑大**。
    """
    return ndimage.binary_closing(mask, structure=np.ones((size, size), bool))


def mask_runs(mask: np.ndarray) -> list:
    """每行里「是色块」的那些连续段，返回 `[[(起, 止), ...], ...]`。

    用前后像素的差找边界，一行的几十次比较就出结果，不用逐点问。
    """
    rows = []
    for y in range(mask.shape[0]):
        row = mask[y]
        starts = np.flatnonzero(~row[:-1] & row[1:]) + 1
        ends = np.flatnonzero(row[:-1] & ~row[1:])
        if row[0]:
            starts = np.concatenate(([0], starts))
        if row[-1]:
            ends = np.concatenate((ends, [len(row) - 1]))
        rows.append([(int(a), int(b)) for a, b in zip(starts, ends)])
    return rows


def runs_to_rects(rows, tol=2):
    """把逐行的横条纵向合并成矩形。

    只有起止都差不多（容 tol 像素）才算同一条，抗锯齿造成的一两像素抖动
    不该把一块墙切成十条。
    """
    rects = []
    active = []  # [x0, x1, y_start]
    for y, runs in enumerate(rows):
        still = []
        used = [False] * len(runs)
        for a in active:
            matched = False
            for i, (x0, x1) in enumerate(runs):
                if used[i]:
                    continue
                if abs(x0 - a[0]) <= tol and abs(x1 - a[1]) <= tol:
                    a[0], a[1] = min(a[0], x0), max(a[1], x1)
                    still.append(a)
                    used[i] = True
                    matched = True
                    break
            if not matched:
                rects.append((a[0], a[2], a[1] - a[0] + 1, y - a[2]))
        for i, (x0, x1) in enumerate(runs):
            if not used[i]:
                still.append([x0, x1, y])
        active = still

    for a in active:
        rects.append((a[0], a[2], a[1] - a[0] + 1, len(rows) - a[2]))

    # 太细的条多半是抗锯齿的毛边，丢掉
    return [r for r in rects if r[2] > 2 and r[3] > 2]


def scale_rects(rects, k):
    out = []
    for x, y, w, h in rects:
        out.append([round(x * k), round(y * k), max(1, round(w * k)), max(1, round(h * k))])
    return out


## 手工调整。**键是照抄示意图得到的原值，值是最终要写进去的值。**
##
## 按**示意图文件名里的关键字**分组：每张图的家具不一样，混在一起的话，
## 提取别的图时会不停地报「没匹配上」。
##
## 为什么需要：示意图上那块绿画的是**家具本体**（策划的说法：「我画的
## 范围是整个书桌」），而挡路的实体只该盖住家具落在地面上的那一圈。
## 书桌那张图连桌面上的地球仪、油灯、书都算进去了 —— 照抄的话家具上方
## 那团**空气**也成了实体，人就永远走不到桌子跟前，「站桌后只露上半身」
## 这个效果根本摆不出来。
##
## 写在这里而不是只手改 JSON：**只改 JSON 的话，下次重跑提取就退回去了**，
## 而且退回去之后画面看着「能用」，没人会发现。
## 详细推导见开发纪要第三十二节。
OVERRIDES = {
    "委托店": {
        # 书桌：从「整个书桌」（含桌面摆件）缩到桌体落在地面的那段。
        (185, 121, 77, 32): [185, 139, 77, 10],
    },
}


def overrides_for(path: str) -> dict:
    """按文件名挑这一张图的手工调整。挑不到就当没有。"""
    name = os.path.basename(path)
    for key, table in OVERRIDES.items():
        if key in name:
            return table
    return {}


## 传送区的手工修正。**和 OVERRIDES 同一套规矩**：键是照抄提取出来的原值，
## 值是最终要写进去的。
##
## 为什么需要：传送区是照着蓝块提的，而蓝块往往**紧贴着墙底**
## （台阶的上面一段、门洞正下方那一块垫子）。脚底方块 16 像素高**而且只往上伸**，
## 所以紧贴墙底那一段**一行都站不住** —— 玩家走上去踩不到，
## 手感就是「这扇门坏了」（这条坑见技能里的「门区深度」）。
##
## 集市那张实测（那是 557×314 的图，坐标是游戏单位）：
##
##   左上台阶     蓝块 [19, 77, 41, 15]，能站的行从 y=93 才开始 → 往下铺到 92
##   大房子门口   蓝块 [233, 109, 20, 7]，能站的行从 y=124 才开始 → 往下铺到 124
##   底部地毯     蓝块 [255, 273, 47, 13]，框里 273..285 都站得住 → 不用动
##   右下角       蓝块 [510, 268, 27, 10]，框里 268..277 都站得住 → 不用动
##
## 往下铺多少不是拍的：「站得住」是拿游戏自己那套量具量出来的
##（`tests/probe_portal_depth.gd`），铺完还要 ≥ 4 行才放过。
PORTAL_FIXES = {
    "4106E682225371396997B04A22BABF01": {
        (19, 77, 41, 15): [19, 92, 41, 14],
        (233, 109, 20, 7): [233, 124, 20, 12],
        # 底部地毯（南门）：两处要修。
        #   ① 蓝块最右边 2 像素压在墙上了（画的时候蓝叠过了红边）——收到 x=300；
        #   ② **往下铺到碰撞边界**（策划 2026-09-24 要的）：地毯下面还有一块
        #      45×24 的凹口（左右两边是 y 281..296 的墙，底边实体从 y=297 起
        #      横铺整排）。那一整块都是死胡同，把触发区一直铺到底 ——
        #      站进这个凹口任意一处都算「站在南门上」，不用去够某一行。
        (255, 273, 47, 13): [255, 273, 45, 25],
    },
}


def apply_portal_fixes(rects, path: str):
    name = os.path.basename(path)
    table = {}
    for key, sub in PORTAL_FIXES.items():
        if key in name:
            table = sub
    if not table:
        return rects
    out = []
    hit = set()
    for r in rects:
        key = tuple(r)
        if key in table:
            hit.add(key)
            out.append(list(table[key]))
        else:
            out.append(r)
    for key in table:
        if key not in hit:
            print("提醒：传送区修正 %s 没匹配上 —— 示意图改过了？" % (list(key),))
    return out


def apply_overrides(rects, table: dict):
    out = []
    hit = set()
    for r in rects:
        key = tuple(r)
        if key in table:
            hit.add(key)
            out.append(list(table[key]))
        else:
            out.append(r)
    for key in table:
        if key not in hit:
            print("提醒：手工调整 %s 没匹配上任何一块 —— 示意图改过了？" % (list(key),))
    return out


def drop_slivers(rects, min_side: int = 2):
    """丢掉连 2 个**游戏像素**都不到的条。

    注意传进来的矩形**已经换算成游戏坐标了** —— 这里不要再乘系数。

    那是色块边缘的抗锯齿，不是墙。留着的话地图数据里会多一堆
    `[129, 354, 290, 1]` 这样的薄片，看数据的人得逐个猜它们是什么。
    """
    return [r for r in rects if r[2] >= min_side and r[3] >= min_side]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    k = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
    base = sys.argv[3] if len(sys.argv) > 3 else ""

    img = Image.open(path).convert("RGB")
    print("图 %s  尺寸 %s  缩放 %s" % (path, img.size, k))
    print("地图 size 取 [%d, %d]" % (round(img.size[0] * k), round(img.size[1] * k)))

    table = overrides_for(path)
    if base:
        # 红 / 蓝那套（集市）。见文件头：这一种必须跟底图作差。
        print("按底图作差：%s" % base)
        art = Image.open(base).convert("RGB")
        if art.size != img.size:
            print("！底图和示意图尺寸不一样（%s vs %s），作差会错位"
                  % (art.size, img.size))
            return 1
        walls = apply_overrides(red_wall_rects(img, art, k), table)
        portals = apply_portal_fixes(blue_portal_rects(img, art, k), path)
        whites = []
    else:
        green = close_holes(green_mask(img))
        walls = apply_overrides(
            drop_slivers(scale_rects(runs_to_rects(mask_runs(green)), k)), table)
        portals = apply_portal_fixes(
            drop_slivers(scale_rects(runs_to_rects(mask_runs(cyan_mask(img))), k)), path)
        # 纯白 = 策划单独标出来的**独立物件**（卧室那盏灯）。它不进 walls，
        # 而是要切出来单独摆 —— 但位置得有个准数，所以顺手报一下。
        whites = scale_rects(runs_to_rects(mask_runs(close_holes(white_mask(img)))), k)
        whites = [r for r in whites if r[2] * r[3] >= 4]

    print("\n# 实体 %d 块" % len(walls))
    print('"walls": [')
    for r in walls:
        print("    [%d, %d, %d, %d]," % tuple(r))
    print("]")

    print("\n# 传送点 %d 块" % len(portals))
    for r in portals:
        print("  [%d, %d, %d, %d]" % tuple(r))

    if whites:
        print("\n# 纯白（独立物件）%d 块" % len(whites))
        for r in whites:
            print("  [%d, %d, %d, %d]" % tuple(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
