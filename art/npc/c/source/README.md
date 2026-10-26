# C 绘制源表

- `c_redraw_sheet_20261026.png`：内置 imagegen 生成的透明原始表，5列×3行。上到下为正面、背面、左侧面；每行第1列为站姿，第2—5列为四步态。
- `sheet_regions.json`：审核后的实际透明轮廓范围；生成图留白不完全等宽，不能简单按总宽除5硬切。
- `prompt.txt`：实际生成提示词。身份取自已有 C 小人，风格与头身取自主角三个方向。
- 导出工具：`tools/build_c_sprites.py`，只切帧、等比缩放与对齐，输出15张258×360透明帧。旧脚本 `make_npc_frames.py` 负责其他 NPC，不负责重建 C。
- 运行时使用上一级目录中的 `idle_down/up/side.png` 及 `down/up/side1..4.png`；本源目录不直接作为人物动画目录。

完整交接见 `docs/C重绘与NPC尺寸统一_20261026.md` 与 `art/catalogs/c_redraw_20261026.json`。
