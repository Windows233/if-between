## 演出指令：过场里的一条动作。
##
## 台词之外的东西 —— 黑屏、章标题、等人点一下、把谁挪到哪、放一张大图、
## 画面碎掉 —— 都写成这里的一条条指令，按顺序执行。
##
## **纯数据，不碰界面。** 执行在 `scenes/cutscene.gd`，推进在
## `core/story_director.gd`。这么分是为了指令能被单独解析和校验：
## 一个字母写错，加载时就报出来，而不是演到那一步才莫名其妙地停住。
class_name StageStep
extends RefCounted

## 支持哪些动作。
##
## 每条后面的括号是必填字段，`validate()` 按这个查。
const KINDS: Dictionary = {
	&"say": [],                 # 播一段对话，播完才往下走
	&"fade": ["to"],            # 淡到黑（black）/ 淡回画面（clear）
	&"banner": ["text"],        # 黑屏上的一行大字，章标题用
	&"caption": ["lines"],      # 屏幕正中依次浮现的几行字（心声、结局文字）
	&"location": [],            # 左上角的日期/时间/地点。text 写空就是收起
	&"hint": ["text"],          # 一条提示，三秒后自己消失
	&"play_sound": ["path"],    # 放一段音效
	&"music": ["path"],         # 换背景音乐。**`path` 写空就是停** ——
	                            # 开场那三行黑屏旁白要靠它压住，
	                            # 等画面亮起来、人出现在屋里再起前奏
	&"wait": [],                # 干等一段时间
	&"wait_click": [],          # 等玩家点一下鼠标或按空格
	&"save": [],                # 写入当前槽位（用于剧情检查点）
	&"image": ["path"],         # 屏幕中央的大图淡入
	&"image_hide": [],          # 大图淡出
	&"npc": ["id", "sprite", "at"],  # 在地图上放一个临时角色
	                                # 可选 `z`：盖住家具的层级。站在会挡人的
	                                # 家具（书桌）**前面**时要给，否则被家具切掉
	                                # 可选 `pose`：出场就摆好的姿势（`idle_<名字>`，
	                                # 比如 A 的 `crouch`）。不写用他有的第一组
	                                # 可选 `talk`：这人身上挂着哪段对话（事件 id）。
	                                # **演出演完、控制权交回玩家之后**，走到他跟前
	                                # 按交互就能起那一段（见 `Cutscene._talk`）
	&"npc_move": ["id", "to"],  # 让那个角色走到别处
	                            # 可选 `fade`：**一边平移一边淡出**（淡出只占前
	                            # 80%，走到终点前就看不见了）。没有走路动画的角色
	                            # 只能这么退场 —— 硬切帧看着像一张贴纸在滑
	&"npc_pose": ["id"],        # 换个姿势 / 翻个面（不写 `pose` 就只翻面）。
	                            # 可选 `pose`（`idle_<名字>`）、`flip`（水平翻转）。
	                            # A 没有走路动画，「转过身去」只能靠翻侧面图
	&"npc_remove": ["id"],      # 收走那个角色
	&"hide_player": [],         # 把**玩家角色**藏起来 / 显示回来。
	                            # 用在「场景图上已经画着人了」那几幕 —— 比如
	                            # 「床上躺着主角」那张图，图上本来就有人。
	                            # 可选 `visible`（默认 true = 显示回来）。
	&"hold": [],                # 摆好两个人，停在「等选择」的状态上
	&"focus": [],               # 指定镜头看哪儿（不写 at 就是还给角色）
	&"place_player": [],     # 摆角色 / 让它走过去。
	                        # **三种写法**：
	                        #   `at` 不带 `time` —— 直接摆在那儿（不算走路）；
	                        #   `at` 带 `time` —— 从当前位置走过去；
	                        #   `path` —— 一串路径点，一段一段走，终点是最后一个点。
	                        # 可选 `anchor: "head"` = 这个坐标指的是头的正中央，
	                        # 不写就是脚底。躺床上那一幕用前者。
	                        # 可选 `facing` 给最终朝向；走路时不写就保持最后一段的朝向。
	                        # 可选 `pin: true` = 按住不动（落点在家具里时用，
	                        # 不然物理每帧把人推出来，画面上是在抖）。
	                        # **走路的时长不用手写**：不写 `time` 就按脚程算
	                        # （总长 ÷ 走路速度），和玩家自己走一样快。
	&"goto": ["map"],           # 换场景
	&"shatter": [],             # 画面碎掉（把这一屏切成瓦片飞散）
	&"if_panel": [],            # 画面正中弹出 **IF 条件框**，让玩家看「如果…就会…」。
	                            # 可选 `condition` / `result`（填空处那两句），
	                            # `disabled: true` 让四个事项块都禁用（只能看不能改），
	                            # `hold` 停几秒；**不写 hold 就是等玩家点一下**。
	&"flash": [],               # 黑白闪几下。可选 `color`（white / black，默认白）、
	                            # `times`、`time`（一次闪多久）、`hold`（亮着停多久）、
	                            # `mono: true`（白黑交替，那才是「黑白闪烁」）。
	                            # **和 `fade` 不是一回事**：淡出是「画面暗下去」，
	                            # 闪是「被打断」—— 梦里那一下该用白闪，不是碎屏。
	                            # 一次闪 = `time/2` 亮起 + `hold` + `time/2` 暗回，
	                            # 嫌快就把这三个加大。
	&"bg_blink": [],            # 背景闪几下：集市和纯黑来回切，**主角留在画面上**。
	                            # 可选 `times`（切换几次，默认 3）、`hold`（每次停多久，
	                            # 默认 1 秒）。三次就是「黑 / 亮 / 黑」，最后停在黑。
	&"eye_open": [],            # 睁眼：黑幕中间一个椭圆先睁开、眨两下，再全亮。
	                            # 可选 `blinks`（眨几下，默认 2）。
	                            # **调用前要先把幕（`fade`）揭开**，不然椭圆里
	                            # 看见的还是黑。
	&"rescue": ["flag"],
	&"glass": [],               # 碎玻璃从正中炸开（黑底素材叠加，不压黑）。
	                            # 可选 `hold`（炸完停多久）、`fade`（淡出用多久）
}

var kind: StringName = &""
var data: Dictionary = {}


static func from_dictionary(raw: Variant) -> StageStep:
	var step := StageStep.new()
	if not (raw is Dictionary):
		return step
	var source := raw as Dictionary
	step.kind = StringName(str(source.get("do", "")))
	step.data = source
	return step


# ---------------------------------------------------------------- 取值

func has(key: String) -> bool:
	return data.has(key)


func text(key: String, fallback: String = "") -> String:
	return str(data.get(key, fallback))


func number(key: String, fallback: float = 0.0) -> float:
	var raw: Variant = data.get(key, fallback)
	if raw is float or raw is int:
		return float(raw)
	return fallback


func flag(key: String, fallback: bool = false) -> bool:
	var raw: Variant = data.get(key, fallback)
	if raw is bool:
		return raw
	return fallback


## 坐标写成 `[x, y]`。缺了就退回 `fallback`。
func point(key: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var raw: Variant = data.get(key)
	if raw is Array and (raw as Array).size() >= 2:
		var pair := raw as Array
		return Vector2(float(pair[0]), float(pair[1]))
	return fallback


## 一串坐标，写成 `[[x, y], [x, y], ...]`。缺了或者格式不对就是空数组。
##
## 只给 `place_player` 用（路径点）。**每一段里可能同时差着 x 和 y**，
## 拆成「先横后竖」是执行那边的事，这里只负责把数读出来。
func points(key: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var raw: Variant = data.get(key)
	if not (raw is Array):
		return out
	for item: Variant in raw as Array:
		if item is Array and (item as Array).size() >= 2:
			var pair := item as Array
			out.append(Vector2(float(pair[0]), float(pair[1])))
	return out


## `say` 要播的那段对话。
##
## 两种写法都收：给 `lines` 写一整段，或者把一行拆在指令自己身上
## （`speaker` / `text` / `portrait` / `side`）。前者用来念一整段，
## 后者是「就一句」的简写。
func dialogue() -> Dialogue:
	if data.has("lines"):
		return Dialogue.from_array(data.get("lines"))

	var one: Dictionary = {"text": text("text")}
	for key: String in ["speaker", "portrait", "side"]:
		if data.has(key):
			one[key] = data[key]
	return Dialogue.from_array([one])


# ---------------------------------------------------------------- 校验

## 这条指令写对了吗。返回问题列表，空数组表示没问题。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if kind == &"":
		problems.append("有一条演出指令没写 do")
		return problems
	if not KINDS.has(kind):
		problems.append("不认识的演出指令：%s" % kind)
		return problems

	for key: String in KINDS[kind]:
		if not data.has(key):
			problems.append("演出指令 %s 少了 %s" % [kind, key])

	# `slide: "out"` 是「把对话框收下去」，本来就没有文本；
	# 除此之外的 say 必须有东西可念。
	if kind == &"say" and text("slide") != "out" \
			and not data.has("lines") and not data.has("text"):
		problems.append("演出指令 say 既没有 lines 也没有 text")
	# **`place_player` 要落到一个地方** —— 要么给 `at`，要么给一串 `path`
	# （路径点的最后一个就是终点）。两个都不写，这一步没有意义，
	# 多半是脚本里漏了一行。
	if kind == &"place_player" and not data.has("at") and points("path").is_empty():
		problems.append("演出指令 place_player 既没有 at 也没有 path")
	if kind == &"place_player" and data.has("path") and points("path").is_empty():
		problems.append("演出指令 place_player 的 path 得是 [[x, y], ...] 这样的数组")
	if kind == &"fade" and text("to") not in ["black", "clear"]:
		problems.append("演出指令 fade 的 to 只能是 black 或 clear，写的是「%s」" % text("to"))
	if kind == &"caption":
		var raw_lines: Variant = data.get("lines")
		if not (raw_lines is Array) or (raw_lines as Array).is_empty():
			problems.append("演出指令 caption 的 lines 得是一个非空的数组")
	if kind == &"hint" and text("at") not in ["", "corner", "center"]:
		problems.append("演出指令 hint 的 at 只能是 corner 或 center，写的是「%s」" % text("at"))
	# 图存不存在**不在这里查** —— core 层不碰资源系统，
	# 那条由 `tools/check_data.py` 把关。
	return problems
