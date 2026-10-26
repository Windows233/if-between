# 首次入馆至 End7：权威回读索引

本索引服务于程序清单的分段实现与复核。它只提供回读入口，不产生新剧情要求，也不替代任务清单。

## 需求来源与优先级

- **唯一需求权威**：`C:/Users/q3382/Documents/GameProject/待用资源/团队交付包_第二章后半章/程序任务_首次入馆至End7.txt`。每次开始一组任务、恢复被打断的工作、或检查实装时，按下表回读相关 `P` 项、`L` 节点及第五、六节；不要只依赖旧会话摘要。
- `剧情后半章.stage.md`、`.stage.yaml` 与同名 JSON 是同源结构稿/数据快照，用于快速定位 cue、原句、挂接和 `requires_work`，不覆盖程序任务清单。若与任务清单冲突，以任务清单为准。
- `文档自检.json`只记录源包结构检查结果，不证明游戏实现、运行时可达性或通关。
- 项目文档仅用于查找编辑接口、工具和验证流程；按下面映射定点回读，不能据此增加或改写需求。

## 按工作包回读

| 工作包 | 开工及复核时回读 | 项目内配套入口 | 代码/测试定位 |
| --- | --- | --- | --- |
| P1 童话书 | P1；L03、L13；第五、六节 | `docs/工程约定.md` 第五节改动索引；`docs/IF机制.md`（剧情节点状态） | `data/events/ch2_library_shelf.json`；`tests/test_library_after.gd` |
| P2 血迹 | P2；L02、L12；第五、六节 | `docs/工程约定.md` 第五节；`docs/IF机制.md`（地图状态与个人回溯） | `data/events/ch2_library_blood.json`；`data/maps/library.json`；`tests/test_library_after.gd` |
| P3 猫与媒介 | P3；L04—L11、L16—L17；第五、六节 | `docs/IF机制.md`；`docs/工程约定.md` 中背包选择、演出指令及读档补演条目 | `data/events/ch2_library_cat.json`；`core/stage_step.gd`；`scenes/cutscene.gd`；`scenes/map_view.gd`；`tests/test_library_after.gd` |
| P4 主动隐蔽 | P4；L20、L22—L28；第五、六节 | `docs/IF机制.md`；`docs/工程约定.md` 的场景交互/追逐实现索引 | `scenes/ch2_escape_session.gd`；`data/events/ch2_library_cat.json`；`tests/test_ch2_escape.gd` |
| P5 窗边脱离 | P5；L28—L32；第五、六节 | `docs/地图编辑器-操作说明.md`（交互区/碰撞与地图数据保存）；`docs/工程约定.md` 中剧情挂接、演出指令及换图条目 | `data/events/ch2_library_cat.json`；`data/events/ch2_classroom_window.json`；`data/maps/classroom.json`；`tests/test_ch2_escape.gd` |
| P6 夜市与 End7 | P6；L33—L40；第五、六节 | `docs/IF机制.md`；`docs/工程约定.md` 的库存、幂等奖励、结局与存档条目 | `data/events/ch2_market_b_end.json`；`data/maps/market_night.json`；`scenes/cutscene.gd`；`core/stage_step.gd`；`tests/test_library_after.gd` |
| P7 跨流程收口 | P7；第五、六节及所有受影响工作包的相关 L 节点 | `docs/交接须知.md` 第四节验证命令；`docs/工程约定.md` 中存读档、演出/画面和烟测索引；地图更动读 `docs/地图编辑器-操作说明.md` | `tests/test_library_after.gd`；`tests/test_ch2_escape.gd`；`tests/run_tests.gd`；受影响事件/地图 |

## 执行规程

1. 开始或恢复某个 P 项前，先核对该 P 行所列需求段及节点的原文、位置/挂接、触发、演出和出口；跨到新工作包时重新回读对应行。
2. 修改现有节点中段演出时，同时回读第五节存档规则，检查 `story_step` 对已有存档的影响；奖励、扣物和状态标记对照第五节逐项核验。
3. 改地图时回读清单对应 L 节点与验收项，按 `docs/地图编辑器-操作说明.md` 用地图编辑器保存；若因必要情况直接改 JSON，至少执行 `python tools/check_data.py`。
4. 实装复核从任务清单第六节逐条打勾，并区分静态、自动测试、真窗口、人工连续通关证据。没有的证据明确标记缺失；不得将结构检查或单测结果写成整章通关。
5. 文档索引只负责找到当前需求段。源任务清单内容或路径变化后，以清单当前内容为准并更新此表；不复制整份清单，避免形成第二份需求真源。

## 当前会话记录

本次使用的任务清单路径见上。工作区基线从 `main` 的 `ae1a7bd` 开始；文档结构自检记录的 `4976/4976` 是该快照基线，不是本次修改后的结果。当前工作进度以 `docs/进行中.md` 与实时 Git 状态为准。
