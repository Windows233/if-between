"""导出 imagegen 已绘制的 C 帧表，只做切帧、等比缩放和脚底对齐。

不绘制或仿造运动帧。主源表负责正背步态和站姿，侧走采用修正的八相位源表。
所有输出258×360，与主角相同。每个朝向内共享缩放系数，避免逐帧变大变小。
"""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art/npc/c/source/c_redraw_sheet_20261026.png'
REGIONS = ROOT / 'art/npc/c/source/sheet_regions.json'
OUT = ROOT / 'art/npc/c'
FRAME_SIZE = (258, 360)
VISIBLE_HEIGHT = 348


def build():
    sheet = Image.open(SOURCE).convert('RGBA')
    regions = json.loads(REGIONS.read_text(encoding='utf-8'))
    result = []
    for row, direction in enumerate(('down', 'up', 'side')):
        parts = []
        for entry in regions:
            if entry['row'] != row:
                continue
            # 坐标来自透明轮廓审查，留三像素以保留原始半透明边缘。
            x0, y0, x1, y1 = entry['cell']
            part = sheet.crop((max(0,x0-3),y0,min(sheet.width,x1+3),y1))
            alpha = part.getchannel('A')
            box = alpha.point(lambda value:255 if value >= 128 else 0).getbbox()
            parts.append((entry['col'], part, box))
        factor = VISIBLE_HEIGHT / max(box[3]-box[1] for _,_,box in parts)
        for col, part, box in parts:
            if direction == 'side' and col > 0:
                # 旧源表的侧走没有交替步态，禁止再次导出覆盖修正版。
                continue
            # 以头部中心固定水平锚点；步态允许手、外套和脚自然摆动。
            head_bottom = round(box[1]+(box[3]-box[1])*.41)
            head_box = part.crop((0,box[1],part.width,head_bottom)).getchannel('A').point(lambda value:255 if value >=128 else 0).getbbox()
            head_x = (head_box[0]+head_box[2])/2
            scaled = part.resize((round(part.width*factor),round(part.height*factor)), Image.Resampling.NEAREST)
            at_x = round(FRAME_SIZE[0]/2-head_x*factor)
            at_y = round(FRAME_SIZE[1]-box[3]*factor)
            frame = Image.new('RGBA', FRAME_SIZE)
            frame.alpha_composite(scaled,(at_x,at_y))
            name = f'idle_{direction}.png' if col == 0 else f'{direction}{col}.png'
            frame.save(OUT/name)
            result.append({'path':f'art/npc/c/{name}','source_row':row,'source_column':col,'scale':factor,'size':list(FRAME_SIZE),'alpha_bbox':list(frame.getchannel('A').point(lambda v:255 if v>=128 else 0).getbbox())})
    result.extend(build_side_walk())
    return result


def build_side_walk():
    """八阶段侧走：共同缩放/地面基线，保留足部真实抬落，不逐帧拉伸。"""
    source_dir = OUT / 'source/side_walk_v2'
    sheet = Image.open(source_dir/'side_walk8.png').convert('RGBA')
    entries = json.loads((source_dir/'regions.json').read_text(encoding='utf-8'))
    parts=[]
    for entry in entries:
        x0,y0,x1,y1=entry['cell']
        part=sheet.crop((max(0,x0-3),y0,min(sheet.width,x1+3),y1))
        box=part.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        parts.append((entry,part,box))
    factor=VISIBLE_HEIGHT/max(box[3]-box[1] for _,_,box in parts)
    baselines={row:max(box[3] for e,_,box in parts if e['row']==row) for row in [0,1]}
    result=[]
    for entry,part,box in parts:
        head_bottom=round(box[1]+(box[3]-box[1])*.41)
        head_box=part.crop((0,box[1],part.width,head_bottom)).getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        head_x=(head_box[0]+head_box[2])/2
        scaled=part.resize((round(part.width*factor),round(part.height*factor)),Image.Resampling.NEAREST)
        at_x=round(FRAME_SIZE[0]/2-head_x*factor)
        at_y=round(FRAME_SIZE[1]-baselines[entry['row']]*factor)
        frame=Image.new('RGBA',FRAME_SIZE)
        frame.alpha_composite(scaled,(at_x,at_y))
        name=f"side{entry['frame']}.png"
        frame.save(OUT/name)
        result.append({'path':f'art/npc/c/{name}','phase':entry['phase'],'source':str(source_dir.relative_to(ROOT)).replace('\\','/'),'source_cell':entry['cell'],'scale':factor,'size':list(FRAME_SIZE),'alpha_bbox':list(frame.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox())})
    return result


if __name__ == '__main__':
    frames = build()
    print(json.dumps(frames,ensure_ascii=False,indent=2))
