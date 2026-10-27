# 第二章互动缺口与图书馆素材接入

这份说明绑定当前工程的真实地图、actor和事件，给程序作为接入清单。对应结构稿是同目录的 `ch2_interaction_and_assets_20261027.stage.yaml`；当前标为 `draft`，因为镜子/教学楼公告栏仍需在地图编辑器落点保存。

## 这段发生在哪里

| 场景 | 工程文件 | 本次使用的真实对象 | 当前情况 |
| --- | --- | --- | --- |
| 教室 | `data/maps/classroom.json`，384×307，`art/map/classroom.png` | `diary_desk` `[260,137,38,26]` | 窗户actor已按用户要求从地图编辑器删除；镜子、教学楼公告栏actor缺失 |
| 操场 | `data/maps/school_yard.json`，316×211，`art/map/school_yard.png` | `flagpole` `[106,39,28,62]`，`swing` `[194,38,56,38]` | 旗杆事件存在；秋千需解决底图C与独立C争用，救援小游戏加难 |
| 校门 | `data/maps/school_gate.json`，421×281，`art/map/school_gate.png` | `notice_board` `[123,220,42,31]` | 这是校门通知栏；若要教学楼公告栏，需要新actor，不要复用错位置 |
| 图书馆 | `data/maps/library.json`，467×374，`art/map/library_no_cat.png` + `library_wall.png` | `escape_shelf_barrier` `[201,215,64,28]` | 已有最终横放静态图和状态碰撞；缺一次性倒塌序列播放 |

视口是 320×180，镜头沿用现有夹边跟随逻辑。书架动画应在 `escape_shelf_barrier` 的地图坐标播放，不做缩放或镜头推拉；`library_wall.png` 的前景遮挡继续保留。

## 触发与演出表

| 节点 | 触发/地图对象 | 玩家看到和操作 | 程序接入 |
| --- | --- | --- | --- |
| `diary_pages` | 教室 `diary_desk` → `ch2_diary` | 日记第1、2、3页分别显示；每页确认后收图，第三页后才奖励 | 将当前整张 `ch2_diary_written.png` 拆成三次 `image`；保留 `diary_reward` 的一次性状态 |
| `flagpole` | 操场 `flagpole` → `ch2_flagpole` | 读到外套袖口猫毛 | 复用现有事件；确认actor action仍绑定 `check` |
| `swing_rescue` | 操场 `swing` → `ch2_swing` | 三段连续稳定输入；窗口外按键计错，累计3次失败；失败重试，成功才救出C | 秋千交互期间屏蔽普通C互动；底图C和独立C只保留一个可见表现 |
| `c_to_teaching_gate` | 救援成功后的流程 | C在教学楼门口问话；对白后C成为静止NPC，玩家手动进教学楼 | 去掉去二楼/自动移动出口，保存 `c_static_teaching_gate` |
| `notice_and_mirror` | 教室新 `teaching_notice` / `mirror` actor | 公告栏显示三条规则；镜子显示一次性镜面反馈 | 用地图编辑器新增并保存两个actor，再绑定事件；校门 `notice_board` 继续独立存在 |
| `library_shelf_fall` | `ch2_library_cat.crowbar_used` | “对了！书架”后播放6.zip十帧倒塌，完成后C咳嗽对白；碰撞只在完成后开启 | 选择一张联系图，裁帧或做AtlasTexture；给 `map_view` 一次性播放和完成回调。读档直接使用 `library_shelf_fallen.png` |
| `chase_nonfatal` | 日记路线 `chase_prepare` | Q/E追逐失败或被追上不死亡，清理追逐状态后由C救场 | 把当前 `chase_caught` 的死亡CG/End5出口替换为 `caught_rescued` 分支 |
| `library_caught_dialogue` | 被追上后进入图书馆 | C说“看来有人在这里出事，我们得小心一点了”，随后停在入口 | `library_enter` 按结果分流，C不自动跟随 |
| `library_success_os` | 两次QTE成功后进入图书馆 | 只出现主角OS：“他怎么能到得这么快，而且，他怎么知道我在这里” | 成功分支不要生成C救场对白 |
| `window_asset` | 教室待重新放置的窗户对象 | 用户窗户图保留为候选资源，夜景背板与窗框分层，暂不触发原抛币流程 | `classroom_window` 已按用户要求删除；`ch2_classroom_window` 事件和 `art/props/classroom_window_frame.png` 保留，等待重新放置并校准位置 |

## 书架动画的状态时序

1. `crowbar_used` 先播放主角两句对白。
2. “对了！书架”之后触发 `escape_shelf_barrier` 的十帧动画。动画未完成前不要写 `shelf_fallen=true`，也不要开启最终碰撞，避免主角提前撞上横放书架。
3. 动画完成回调设置 `ch2/library/shelf_fallen=true`，切换 `library_shelf_fallen.png`，开启 `scenes/library_visuals.gd` 的局部碰撞。
4. 播放C的咳嗽和“看来这场游戏要尽早结束了”，再进入现有 `escape_prepare` → `escape_library_run`。
5. 读档、重进图书馆或失败重试时不重新播动画，直接显示最终静态帧和碰撞。

6.zip 的第二张 `7349C296-2590-4506-8DB2-95822699D3AA.PNG` 是无编号的 1983×793、5×2 十帧联系图，已复制为 `res://art/props/library_shelf_fall_sheet.png` 并接入 `map_actor_animation`。第一张 `40BD3CCD-321F-4886-B02F-CBC34B3E2257.PNG` 带有底部 1–10 标签，不进游戏。窗户附件与 `res://art/props/classroom_window_frame.png` 实质相同，继续复用现有 actor，不新增第二扇窗。

## 接入与结束状态

- 日记：第三页确认后设置 `ch2/diary_read=true`，回访不重复奖励。
- 救援：成功后设置 `ch2/rescued_c=true`；失败只重试小游戏，不死亡。
- C门口：对白后设置 `ch2/c_static_teaching_gate=true`，C不跟随、不自动走位、不挡教学楼入口。
- 书架：倒塌动画完成后设置 `ch2/library/shelf_fallen=true`；最终贴图和局部碰撞由 `library_visuals.gd` 复原。
- 追逐：被追上设置 `caught_rescued=true` 并走图书馆C对白；成功路线不设置该状态，只走单句OS。
- 窗户：`classroom_window` 已从地图删除；保留 `ch2_classroom_window` 事件、状态和资源，重新放置后再恢复绑定。

## 当前缺口与验收

1. 选定 6.zip A/B 其中一张，裁出十帧，确认倒塌方向、透明边缘和帧号均不会显示在游戏中。
2. 验证书架动画完成前可正常触发对白，完成后主角路线被横架阻挡；读档直接是最终状态。
3. 在地图编辑器新增镜子和教学楼公告栏，保存后检查交互范围、可站位置和遮挡层。
4. 秋千救援测试成功、三次错误失败、暂停/重试、读档四条路径，并确认不会同时出现两个C。
5. 追逐测试两次QTE成功、任一失败、被追上三条路径：失败不进End5；被追上能在图书馆看到C对白；全成功只出现OS。
6. 窗户重新放置后再跑 `python tools/check_data.py`、相关Godot回归和真窗口烟测；当前不应假设 `classroom_window` 存在。
