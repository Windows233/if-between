"""门卫室地图的资产生成：从 `待用资源/地图/学校/门卫室/` 提取游戏用图。

产出三张：
    art/map/gatehouse.png        背景（完整渲染）
    art/map/gatehouse_wall.png   前景层（底部矮墙 + 门柱，压在角色之上）
    art/props/gatehouse_desk.png 桌子切图（cover 遮挡物，带 alpha）

桌子的来源是一张**白底高清重绘**（约 3.57 倍），不是背景里那张做旧的原桌。
缩放系数和位置由多尺度模板匹配量得（2026-09-26），写死在下面的常量表里。
重跑匹配用 `待用资源` 目录里的原始文件，别拿这里的产物当输入。

用法：
    python tools/make_gatehouse_assets.py
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = r"C:/Users/q3382/Documents/GameProject/待用资源/地图/学校/门卫室"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 桌子：高清图 -> 背景里的缩放与落位（模板匹配实测，见提交记录）
DESK_SCALE = 0.28

# 离白多远算「物件」：>30 开始淡入，>62 全不透明。书页接近纯白（sum≈650），
# 阈值取 765-30=735 能把书页留下、把白底的柔和阴影（sum≈740+）挡在外面。
WHITE_TOLERANCE = 30

# 墙层的破窗：美术导出时「挖空」落成了**不透明纯白占位**（2026-09-26 她报的
# 「窗户黑白块」）。背景同位置是正确的灰黑夜色，把这块的近白像素改成全透明
# 就能透出正确的底。区域是量出来的破洞包围盒，别扩大到木框和石帽沿。
BROKEN_WINDOW = (1490, 2740, 1670, 2970)   # x0, y0, x1, y1
HOLE_WHITE_SUM = 640                        # RGB 和超过它算「白色占位」


def fix_broken_window(wall: Image.Image) -> Image.Image:
    a = np.asarray(wall).copy()
    x0, y0, x1, y1 = BROKEN_WINDOW
    reg = a[y0:y1, x0:x1]
    s = reg[..., :3].astype(np.int16).sum(axis=2)
    reg[..., 3] = np.where(s > HOLE_WHITE_SUM, 0, reg[..., 3])
    a[y0:y1, x0:x1] = reg
    return Image.fromarray(a, "RGBA")


def desk_alpha(tab: Image.Image) -> np.ndarray:
    t = np.asarray(tab).astype(np.int16)
    dist = 765 - t.sum(axis=2)
    alpha = np.clip((dist - WHITE_TOLERANCE) * 8, 0, 255).astype(np.uint8)
    m = alpha > 128
    lab, n = ndimage.label(m)
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    alpha[lab != (np.argsort(sizes)[::-1][0] + 1)] = 0  # 只留最大连通块
    return alpha


def main() -> int:
    full = Image.open(os.path.join(SRC, "门卫室_upscayl_4x_upscayl-standard-4x.png")).convert("RGB")
    wall = Image.open(os.path.join(SRC, "门卫室墙_upscayl_4x_upscayl-standard-4x.png")).convert("RGBA")
    tab = Image.open(os.path.join(SRC, "门卫室桌子_upscayl_4x_upscayl-standard-4x.png")).convert("RGB")

    # 背景：完整渲染直接用。桌子的旧绘仍在其中，会被 cover 精灵盖在同位置。
    full.save(os.path.join(ROOT, "art", "map", "gatehouse.png"))

    # 前景层：底部矮墙 + 门柱。与背景同尺寸，工具按 OVERLAY_Z 铺。
    # 破洞处的白色占位先清掉（见 fix_broken_window 的说明）。
    wall = fix_broken_window(wall)
    wall.save(os.path.join(ROOT, "art", "map", "gatehouse_wall.png"))

    # 桌子切图
    alpha = desk_alpha(tab)
    ys, xs = np.where(alpha > 128)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    rgb = np.asarray(tab)[y0:y1 + 1, x0:x1 + 1]
    a = alpha[y0:y1 + 1, x0:x1 + 1]
    w = int(round((x1 - x0 + 1) * DESK_SCALE))
    h = int(round((y1 - y0 + 1) * DESK_SCALE))
    desk = Image.fromarray(np.dstack([rgb, np.where(a > 160, 255, 0).astype(np.uint8)])
                           ).resize((w, h), Image.LANCZOS)
    desk.save(os.path.join(ROOT, "art", "props", "gatehouse_desk.png"))
    print(f"gatehouse_desk.png {w}x{h}")
    print("完成：art/map/gatehouse.png、art/map/gatehouse_wall.png、art/props/gatehouse_desk.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
