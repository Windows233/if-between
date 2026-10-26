# C 主角同款侧走源稿

2026-10-26。用户要求动作跟主角一致，替代偏僵硬的八相位v2。

- `hero_pose_guide.png`：由主角实际side1—4拼成的2×2动作模板；主角第1/3帧相同。
- `c_identity_reference.png`：5acd727中的C侧面站姿，用于保留身份。
- `initial_sheet.png`：内置imagegen首次生成结果。
- `c_hero_side_sheet.png`：内置imagegen定向缩短围巾后的实际导出源稿。
- `01_generate.txt`、`02_scarf_fit.txt`：两次实际提示词。
- `regions.json`：源稿中的收脚、迈步A、迈步B范围；生成稿第三格不用，直接复用第一格，如主角一样第1/3帧一致。

执行`tools/build_c_sprites.py`只切片、等比缩放与脚底/头部中心对齐，不绘制动作。输出side1—4及idle_side，258×360，4帧/8FPS；第1/3/站姿相同，右向镜像。根目录多余side5—8退出，历史源稿保留。正背面与NPC统一45高度沿用。
