# 剧情1.2：已确认双QTE与C门口接应

状态：ready_for_implementation。演出说明与结构稿同源。

school_gate near_classroom至library from_school_gate已绑定；仅表示需求齐备，追逐控制器仍requires_work。
不等待走廊成图可先用开发入口联调本段；正式主线仍依赖日记/组队/决策币前置。

坐标：地图逻辑坐标、脚底；逻辑视口320×180。

## 实际场景：school_gate

地图：data/maps/school_gate.json；背景：art/map/school_gate.png；逻辑大小：[421, 281]。
雕像阻直线，走南侧；C不烘焙在底图，接应须独立小人。
实际视口320×180；player_scale=0.5；相机按地图标尺，不能当底图全景。

### chase_prepare｜选对图书馆，从教学楼门外开始

触发：{"type": "state", "condition": {"all": [{"var": "diary_read", "op": "eq", "value": true}, {"var": "teamed", "op": "eq", "value": true}, {"var": "coin_count", "op": "ge", "value": 1}]}}；控制：cutscene；重复：guarded。
人物：主角near_classroom=[62,114]脚底朝下；黑雾猫在后方追近；C尚未露面。

- **chase_gate** [staging] 从教室经教学楼出口切到school_gate near_classroom，跳过未制作走廊穿行演出（finished）
  参数：{"operation": "goto", "map": "school_gate", "spawn": "near_classroom"}
  原生对应：`[{"do": "fade", "to": "black", "time": 0.2}, {"do": "goto", "map": "school_gate", "spawn": "near_classroom"}, {"do": "fade", "to": "clear", "time": 0.2}]`
- **chase_instructions** [staging] 先读无倒计时玩法说明，再确认开跑（confirm）
  参数：{"text": "向右跑到图书馆。出现字母时，在圆圈收完前按下它。"}
  原生对应：`[{"do": "caption", "lines": [{"text": "向右跑到图书馆。出现字母时，在圆圈收完前按下它。"}]}]`
- **chase_init** [staging] 保存追逐前完整快照，初始化两点、黑雾与镜头；不覆盖手动存档（immediate）
  参数：{"operation": "session_start", "spawn": [62, 114], "control": "WASD/方向键可控，关闭普通调查/传送/鼠标自动走；保留暂停", "camera": "当前基准×1.05；短震2–3屏幕像素", "checkpoint": "追逐前背包/flag/时间/镜头/输入/音乐完整保存"}
  待接入：新增追逐会话控制器；重试和读档重建该会话，不保留半圈/慢动作或已开放图书馆。
- **chase_flags_reset** [staging] 仅重置本次会话结果；不清主线背包/已获日记（immediate）
  参数：{"changes": [{"var": "q1_ok", "op": "set", "value": false}, {"var": "q2_ok", "op": "set", "value": false}, {"var": "arrived", "op": "set", "value": false}], "native_node_set": {"session/q1_ok": false, "session/q2_ok": false, "session/arrived": false}}
  待接入：按本cue的准确时刻拆原生节点set；不能提前在整段入口赠物或开图书馆。

出口：{"type": "next", "next": "run_q1"}
接入：选对图书馆的主线出口触发；开发入口可直接进此节点，但不能跳过正式前置校验。缺币的旧存档走迁移/回C补交，不能当新版正常坏结局。

### run_q1｜玩家跑动与第1处Q闪避

触发：{"type": "flow"}；控制：minigame；重复：guarded。
人物：主角由玩家移动；黑雾在后，成功后拉开追逐差距；C不在该点。

- **qte1** [source] 首次跨x=145，猫逼近，显示Q与收缩外圈；成功才继续（interaction_result）
  参数：{"requirement_status": "planned", "input": "Q", "result_var": "q1_ok", "trigger": {"x": 145, "policy": "可走Y全覆盖，按前进进度一次触发；不能绕过，Q2须Q1成功"}, "time_limit_real_seconds": 1.4, "slow_scale": 0.2, "telegraph_real_seconds": 0.3, "prompt_screen": [160, 58], "ring_radius": [28, 16], "success": "窗口内新按正确键即成功，约0.2秒侧身/短闪避，猫停顿后退，拉开距离；恢复跑动", "wrong": "错键红闪，不续时，不立刻判死；可补按正确键", "failure": "超时无正确按下，结果false一次", "pause": "ESC/失焦暂停真实计时；恢复剩余时间，不补算；菜单输入不判键", "input_edge": "不计提示前按住或键盘重复；环和UI不跟镜头抖", "camera": "基准×1.15短推近；退出复原，不能改角色大小", "collision": "闪避落点必须WalkGrid可走；无安全点用原地侧身＋猫后退，不穿墙"}
  待接入：新增圈式QTE/真实时间计时/顺序触发；旧IF或rescue面板不能直接冒称已支持；跑动阶段不加隐藏血量/体力/秒杀计时。

出口：{"type": "branch", "cases": [{"condition": {"var": "q1_ok", "op": "eq", "value": true}, "next": "run_q2"}], "default": "chase_caught"}
接入：依cue分拆原生节点，set在准确时刻执行。

### run_q2｜玩家跑动与第2处E闪避

触发：{"type": "flow"}；控制：minigame；重复：guarded。
人物：主角由玩家移动；黑雾在后，成功后拉开追逐差距；C不在该点。

- **qte2** [source] 首次跨x=286，猫逼近，显示E与收缩外圈；成功才继续（interaction_result）
  参数：{"requirement_status": "planned", "input": "E", "result_var": "q2_ok", "trigger": {"x": 286, "policy": "可走Y全覆盖，按前进进度一次触发；不能绕过，Q2须Q1成功"}, "time_limit_real_seconds": 1.2, "slow_scale": 0.2, "telegraph_real_seconds": 0.3, "prompt_screen": [160, 58], "ring_radius": [28, 16], "success": "窗口内新按正确键即成功，约0.2秒侧身/短闪避，猫停顿后退，拉开距离；恢复跑动", "wrong": "错键红闪，不续时，不立刻判死；可补按正确键", "failure": "超时无正确按下，结果false一次", "pause": "ESC/失焦暂停真实计时；恢复剩余时间，不补算；菜单输入不判键", "input_edge": "不计提示前按住或键盘重复；环和UI不跟镜头抖", "camera": "基准×1.15短推近；退出复原，不能改角色大小", "collision": "闪避落点必须WalkGrid可走；无安全点用原地侧身＋猫后退，不穿墙"}
  待接入：新增圈式QTE/真实时间计时/顺序触发；旧IF或rescue面板不能直接冒称已支持；跑动阶段不加隐藏血量/体力/秒杀计时。

出口：{"type": "branch", "cases": [{"condition": {"var": "q2_ok", "op": "eq", "value": true}, "next": "arrive"}], "default": "chase_caught"}
接入：依cue分拆原生节点，set在准确时刻执行。

### arrive｜两次成功后，玩家继续跑到图书馆门前

触发：{"type": "flow"}；控制：minigame；重复：guarded。
人物：主角继承当前脚底位置；C仅在本节点说明的地图出现；不假设跨地图自动跟随。

- **reach_library** [staging] 双QTE成功不自动传送；玩家沿南侧通路到门前终点（interaction_result）
  参数：{"requirement_status": "planned", "result_var": "arrived", "goal_rect": [338, 148, 30, 30], "approach": [353, 164], "door": [353, 150], "control": "仍可跑动；未到门不触发C；不增第三QTE或强制失败", "source_portal": [341, 76, 24, 78]}
  待接入：追逐控制器接终点区并禁止提前触发to_library；到门口后接管短演出，必要位移只沿已查安全段。

出口：{"type": "branch", "cases": [{"condition": {"var": "arrived", "op": "eq", "value": true}, "next": "c_door_cover"}], "default": "chase_caught"}
接入：依cue分拆原生节点，set在准确时刻执行。

### c_door_cover｜C在门口接应，玩家胜利有效

触发：{"type": "flow"}；控制：cutscene；重复：guarded。
人物：C脚底365,164侧向主角；主角停在353,164；仅单个C，暂未泄露决策币定位。

- **qte_cleanup_success** [staging] 停止QTE与追逐声，恢复时间和镜头后再播台词；不让慢动作拖慢对白（immediate）
  参数：{"operation": "cleanup", "restore": "进场时间倍率、镜头zoom/offset、输入与音频，删除圈与旧定时器；保留短接应期间普通移动锁"}
  待接入：全部出口共用清理，先执行再接C，避免后续图书馆残留慢动作；接应无新惩罚。
- **c_at_door** [staging] school_gate只创建一个C，小人脚底[365, 164]，面向主角；复用方向帧；不播放不存在的伸手动作（finished）
  参数：{"operation": "show", "position": {"space": "map", "at": [365, 164], "anchor": "feet"}, "facing": "left"}
  原生对应：`[{"do": "npc", "id": "c", "sprite": "res://art/npc/c", "at": [365, 164], "pose": "side"}]`
- **c_watch_out** [source] 台词：小心！（confirm）
  精确台词：小心！
  原生对应：`[{"do": "say", "lines": [{"text": "小心！", "speaker": "C", "side": "right", "portrait": "c/neutral"}]}]`
- **c_cover_action** [staging] C面向黑雾，主角保持门前站姿，黑雾退开或淡出；不夺走已完成闪避的结果（finished）
  参数：{"operation": "cover", "c_position": [365, 164], "hero_position": [353, 164], "fallback": "用C侧面站姿＋黑雾后退/淡出表现掩护，不等挥刀动作帧"}
  待接入：清理追逐黑雾前做0.2–0.35秒后退/淡出；C没有独立攻击动画，不虚构一刀必杀或解释其能力。
- **c_check_injury** [source] 台词：你没受伤吧（confirm）
  精确台词：你没受伤吧
  原生对应：`[{"do": "say", "lines": [{"text": "你没受伤吧", "speaker": "C", "side": "right", "portrait": "c/neutral"}]}]`
- **hero_to_library** [source] 台词：.....没有，我们快去图书馆吧（confirm）
  精确台词：.....没有，我们快去图书馆吧
  原生对应：`[{"do": "say", "lines": [{"text": ".....没有，我们快去图书馆吧", "speaker": "我", "side": "left", "portrait": "protagonist/quiet"}]}]`
- **hero_c_speed** [source] 心声：他怎么能到得这么快，而且，他怎么知道我在这里（confirm）
  精确台词：他怎么能到得这么快，而且，他怎么知道我在这里
  原生对应：`[{"do": "say", "lines": [{"text": "（心声）他怎么能到得这么快，而且，他怎么知道我在这里", "speaker": "我", "side": "left", "portrait": "protagonist/quiet"}]}]`

出口：{"type": "next", "next": "library_enter"}
接入：保留P513–516关键台词；“小心”只接应，不追加不可赢陷阱、固定乱码或失去成功。强制组队正常流程必有决策币，未持币失败分支不放进新版正常主线。

### chase_caught｜QTE超时被追上，进入End5

触发：{"type": "flow"}；控制：cutscene；重复：guarded。
人物：主角继承当前脚底位置；C仅在本节点说明的地图出现；不假设跨地图自动跟随。

- **chase_cleanup_fail** [staging] 超时先清理慢动作、镜头、输入监听、临时声音和环；锁定到一次失败出口（immediate）
  参数：{"operation": "cleanup", "remove": "黑雾/环/定时器，临时输入释放；停止重复判定", "retry": "回near_classroom，两QTE从零，恢复追逐前背包与flag；没有成功开放图书馆"}
  待接入：共用清理函数覆盖失败、成功、重试、读档、切图、标题；读档中途重建检查点，不续半个QTE。
- **caught_image** [staging] 显示校园被黑雾追上CG；缺图首版用当前校门背景与黑雾定格（confirm）
  参数：{"operation": "show", "asset": "failure_cg", "layout": "屏幕中央，保持比例；玩家确认后撤图，不压住下句对话"}
  待接入：school_gate背景＋黑雾接近定格，标临时，不用梦境卧室CG
- **caught_black** [staging] 确认失败画面后淡黑（finished）
  参数：{"operation": "fade", "to": "black", "time": 0.3}
  原生对应：`[{"do": "fade", "to": "black", "time": 0.3}]`
- **caught_title** [source] 台词：end 5 不可违的铁律（confirm）
  精确台词：end 5 不可违的铁律
  原生对应：`[{"do": "say", "lines": [{"text": "end 5 不可违的铁律"}]}]`
- **caught_end_text** [source] 台词：死亡可是人生的必修课，你只是超前学习了而已（confirm）
  精确台词：死亡可是人生的必修课，你只是超前学习了而已
  原生对应：`[{"do": "say", "lines": [{"text": "死亡可是人生的必修课，你只是超前学习了而已"}]}]`

出口：{"type": "end", "ending_id": "end4_iron", "ending_number": 5, "handoff": "按现有结局框架进入结局；提供从追逐前检查点重试/回标题，重试不是保存失败状态。两QTE成功后不能进入本出口。"}
接入：依cue分拆原生节点，set在准确时刻执行。

## 实际场景：library

地图：data/maps/library.json；背景：art/map/library.png；逻辑大小：[467, 374]。
中央猫/黑红雾已烘焙在底图，不能把它冒称独立可动猫；入口C用独立人物，前景墙另有library_wall遮挡。
实际视口320×180；player_scale=1；相机按地图标尺，不能当底图全景。

### library_enter｜成功后开放并进入图书馆

触发：{"type": "flow"}；控制：cutscene；重复：guarded。
人物：主角from_school_gate=[233,296]；C=[251,296]，面朝室内/主角，站在入口侧边不堵门。

- **arrive_flags** [staging] 两QTE+到门+接应完成才写成功与开放；不在救C节点写（immediate）
  参数：{"changes": [{"var": "chase_clear", "op": "set", "value": true}, {"var": "library_open", "op": "set", "value": true}], "native_node_set": {"ch2/chase1_clear": true, "ch2/library_open": true}}
  待接入：按本cue的准确时刻拆原生节点set；不能提前在整段入口赠物或开图书馆。
- **entry_door_open** [source] 开门一次，不与猫叫抢同一原生SFX播放器（immediate）
  参数：{"operation": "play", "bus": "sfx", "asset": "door_open", "loop": false}
  原生对应：`[{"do": "play_sound", "path": "res://audio/sfx/door_open.wav"}]`
- **library_goto** [source] 主角进入图书馆现有入口，旧地图C随切图清理（finished）
  参数：{"operation": "goto", "map": "library", "spawn": "from_school_gate"}
  原生对应：`[{"do": "goto", "map": "library", "spawn": "from_school_gate"}]`
- **library_location** [source] 左上角状态：未知日期，图书馆深夜（immediate）
  参数：{"text": "？月 ？日 图书馆 深夜"}
  原生对应：`[{"do": "location", "text": "？月 ？日 图书馆 深夜"}]`
- **library_c** [staging] library只创建一个C，小人脚底[251, 296]，面向主角；复用方向帧；不播放不存在的伸手动作（finished）
  参数：{"operation": "show", "position": {"space": "map", "at": [251, 296], "anchor": "feet"}, "facing": "down"}
  原生对应：`[{"do": "npc", "id": "c", "sprite": "res://art/npc/c", "at": [251, 296], "pose": "down"}]`
- **library_entry_state** [staging] 地图实际切入且入口C就位后记首次入馆；在此生成后续回溯基准快照（immediate）
  参数：{"changes": [{"var": "library_entered", "op": "set", "value": true}], "native_node_set": {"ch2/library_first_entry": true}}
  待接入：按本cue的准确时刻拆原生节点set；不能提前在整段入口赠物或开图书馆。
- **library_follow** [staging] 撤焦点并恢复跟随（immediate）
  参数：{"operation": "restore_follow"}
  原生对应：`[{"do": "focus"}]`

出口：{"type": "next", "next": "library_explore"}
接入：原文P518–519到此止；猫的血迹/书架/净化/背刺不在本次编排范围，不提前消耗日记或发夜幕之泪。入口C不自动跟随。

### library_explore｜到馆后恢复探索并结束本稿

触发：{"type": "flow"}；控制：cutscene；重复：guarded。
人物：主角继承233,296；C继承251,296；不跑入下段剧情。


出口：{"type": "return_control", "handoff": "图书馆背景与library_wall正常；中央猫是底图现有内容，不再叠第二只；C留251,296可等待后续对话；恢复移动/调查/菜单/存档，日记与币仍在背包；不重启已完成追逐。"}
接入：依cue分拆原生节点，set在准确时刻执行。

## 资源与未决项

- c_sprite [verified] art/npc/c/down1.png：已查看单帧；引擎sprite绑定目录art/npc/c，up/down/side各4帧；没有挥刀/伸手专用动画
- c_neutral [verified] art/portrait/c/neutral.png：已查看透明C立绘；原生portrait=c/neutral，不能用旧c_base冒充半身
- hero_quiet [verified] art/portrait/protagonist/quiet.png：主角现有立绘，台词按需换已存在表情
- mist_sprite [verified] art/npc/shadow_cat/chase_mist_right.png：透明右向单帧，约32×21逻辑像素起调，不是逐帧动画
- key_img [verified] art/item/key.png：现有钥匙
- student_img [verified] art/item/student_id_half.png：现有半张学生证
- old_charm [verified] art/item/charm.png：已查看，为御守布袋，不能当决策币正式图
- coin_img [planned] None：新版决策币正反圆币图；不补新能力设定；替代：首次联调用“获得 决策币×1”文字，不显示御守图
- diary_pages [missing] None：作者已完成但未交包的三张日记页；替代：三页文字阅读界面，每页确认后下一页，原文完整；不重新派画
- failure_cg [planned] None：校园石路上被黑雾猫追上的近景，主角黑发红围巾，1672×941；替代：school_gate背景＋黑雾接近定格，标临时，不用梦境卧室CG
- rescue_injury [missing] None：原文救援失败主角受伤CG，本轮未核实适用成品；替代：保留原台词与短黑幕，暂不加新剧情细节；正式CG另行核对
- cat_sfx [verified] audio/sfx/cat_meow.wav：已存在；一次触发，不默认可循环
- rescue_success [verified] audio/sfx/rescue_success.wav：已存在；一次触发，不默认可循环
- rescue_mistake [verified] audio/sfx/rescue_mistake.wav：已存在；一次触发，不默认可循环
- rescue_complete [verified] audio/sfx/rescue_complete.wav：已存在；一次触发，不默认可循环
- door_open [verified] audio/sfx/door_open.wav：已存在；一次触发，不默认可循环
- door_close [verified] audio/sfx/door_close.wav：已存在；一次触发，不默认可循环
- school_music [verified] audio/bgm/reclamation.mp3：校门/教室现有BGM；不在每句话重启
- qte_policy：新版强制失败与既定双QTE如何统一？；用户2026-10-24明确选择双QTE可赢、C在门口接应；不保留固定乱码、不可赢第三段或靠C判胜。
- coin_flow：强制组队后无币如何处理？；按1.2正常路径强制组队且赠币，无币不是普通分支；旧存档缺币属于迁移/补交异常，不用“就应该找C组队”矛盾台词。币内部暂复用item/charm，显示/图像迁移待实现。

## 完成与验收

本稿止于首次进入图书馆并恢复探索。原台词、来源覆盖与状态映射以同名YAML为准。六段通路和三个脚点只通过当前静态WalkGrid检查；不代表完整救援、QTE或C接应已运行。
新增小游戏/检查点/镜头恢复须实现；两次成功可进入图书馆，失败映射稳定ID end4_iron，显示End5。D3方案中没有C接应的旧六节点稿，在重合部分以本版为准。
