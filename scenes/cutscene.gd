## 演出执行器：把一条条演出指令翻译成实际动作，逐条 await。
##
## 从 `main.gd` 分出来，理由跟 `MenuFlow` 一样 —— 它要碰的东西太多
## （黑幕、覆盖层、对话框、地图上的临时角色、玩家位置、换场景），
## 混进入口里，入口就只省下「谁跟谁连起来」这一件事可做了。
##
## **它持有 main 的引用**，直接调 `main.enter_map()` 这些动作。
## 用引用而不是信号，是因为这些活本来就是「替 main 干」，
## 再绕一层信号只会让读的人多点一次跳转。
##
## 它不认识剧情推进 —— 指令列表是导演递进来的，这里只管「演出来」。
##
## ## 即时模式（`instant`）
##
## 真实运行里一切都是异步的：等补间、等计时器、等玩家点。
## 但**无头测试里没有帧循环**，等这些永远等不到。
## 所以 `instant` 为真时：动画一律不做、时间一律不算、等点击直接跳过，
## 每一步只落实「这一步造成了什么状态」。
## 断言因此能同步跑完，而画面上是什么样由真窗口烟测和截图去管。
class_name Cutscene
extends RefCounted

const C_RESCUE_BINDING_SCRIPT = preload("res://scenes/c_rescue_binding.gd")

## 玩家点了一下 / 按了空格，而且演出正在等这一下。
signal clicked

var main: Node2D = null
## 即时模式：不等动画、不等计时器、不等点击。无头测试用。
var instant := false
## 地图上临时出现的角色，`id -> Sprite2D`。
## 用字典而不是给每个角色建类：它们只会站、走、消失，没有别的行为。
var _actors: Dictionary = {}
## 正在等玩家点一下吗。
var _waiting := false
## 场上这些临时角色各自挂着哪段对话：`id -> 事件 id`。
##
## 它们**比演出活得久** —— 演出演完、控制权交回玩家之后，人还站在那儿，
## 玩家走过去按交互就能搭话（`main.interact()` 会来问这里）。
## 换场景时跟着 `clear_actors()` 一起清掉：那些人是**这一个场景**里的。
var _talk: Dictionary = {}
## 场上这些临时角色是**怎么造出来的**：`id -> 配方`（贴图 / 高度 / 层级 / 出场姿势）。
##
## 存档要记「场上站着谁」—— 光记坐标没用，读档得能把人重新造出来，
## 所以造的时候把配方留一份（见 `snapshot_actors()` / `restore_actors()`）。
var _recipes: Dictionary = {}
## 演过哪些指令，按顺序。测试与调试用 —— 动画被跳过时，这是唯一能查的痕迹。
var _log: Array[String] = []
var _generation: int = 0


func setup(p_main: Node2D) -> void:
	main = p_main


func is_waiting_click() -> bool:
	return _waiting


## 主循环把「继续」事件交给它。等着点击时返回 true，表示这一下被它吃掉了。
func consume_click() -> bool:
	if not _waiting:
		return false
	_waiting = false
	clicked.emit()
	return true


## 收干净。切场景、取消剧情时调用。
func cancel() -> void:
	_generation += 1
	if main != null and main.get("rescue_panel") != null:
		main.rescue_panel.close()
	_waiting = false
	clear_actors()


func clear_actors() -> void:
	if main != null and main.get("rescue_panel") != null:
		main.rescue_panel.set_binding_sprite(null)
	for key: Variant in _actors:
		var node: Node = _actors[key]
		if is_instance_valid(node):
			node.queue_free()
	_actors.clear()
	_talk.clear()
	_recipes.clear()


## 地图上还有临时角色吗。测试用。
func actor_ids() -> Array:
	return _actors.keys()


func place_c_at_school_gate_wait_spawn() -> bool:
	if main == null or main.current_map == null or main.current_map.id != &"school_gate" or not main.current_map.spawns.has(&"near_classroom"):
		return false
	var spawn: Variant = main.current_map.spawns[&"near_classroom"]
	if not (spawn is Vector2) or not Vector2(spawn).is_finite():
		return false
	var actor := add_actor_with_talk("c", "res://art/npc/c",
		main.current_map.spawn_point(&"near_classroom"), 32.0, 12, "down", "ch2_c_wait")
	return actor != null


func restore_school_yard_c() -> void:
	if main == null or main.current_map == null \
			or main.current_map.id != &"school_yard":
		return
	if _actors.has("c") and is_instance_valid(_actors["c"]):
		return

	var rescued := _c_is_rescued()
	var talk := "ch2_c_wait" if rescued else "ch2_swing"
	var c_height := 32.0
	var actor := add_actor_with_talk("c", "res://art/npc/c",
		Vector2(186, 88), c_height, 12, "down", talk)
	if not rescued and actor != null \
			and _add_c_rescue_binding(actor, c_height) != null:
		_recipes["c"]["rescue_binding"] = true


## 往场景里放一个临时角色，脚底中点落在 `at`。
##
## `_npc` 指令走的就是它。单独开出来是给烟测和截图用的 ——
## 那两处只想摆一个「老人站在桌前」的画面，不必把整段演出跑一遍。
##
## `z` 默认 9：比家具（5）高、比玩家（10）低。站在**会挡人的**家具前面时
## 要显式给（书桌挡人时是 11，得给 12），不然会被那件家具切掉半截身子。
func add_actor(id: String, sprite_path: String, at: Vector2,
		height: float = 30.0, z: int = 9, pose: String = "") -> Node2D:
	return add_actor_with_talk(id, sprite_path, at, height, z, pose, "")


## 同上，另外挂一段对话。`talk` 是事件 id，空表示这人只是站着好看。
##
## 这一段对话**不在这儿演** —— 演出结束、控制权交回玩家之后，
## 玩家走到他跟前按交互键（或者点他）时才会起。见 `_talk`。
func add_actor_with_talk(id: String, sprite_path: String, at: Vector2,
		height: float, z: int, pose: String, talk: String) -> Node2D:
	# **同一个 id 已经站着的话先把旧的收掉。** 不然旧节点留在树里没人管
	#（`_actors` 被覆盖了，`clear_actors` 再也找不到它）—— 读档恢复时
	# 尤其明显：会看见两个同名角色叠在一起。
	_drop_actor(id)

	var sprite := _make_actor(sprite_path, height, z, pose)
	if sprite == null or main == null:
		return null
	sprite.position = at
	if id == "c":
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	main.stage_view.add_child(sprite)
	if main.current_map != null:
		preload("res://scenes/world_look.gd").style_actor(sprite, main.current_map)
	_actors[id] = sprite
	_talk.erase(id)
	if talk != "":
		_talk[id] = StringName(talk)
	_recipes[id] = {
		"sprite": sprite_path, "height": height, "z": z, "pose": pose,
	}
	return sprite


## 把某个人从场上收掉（内部用；外面要收人走 `npc_remove` 那条指令）。
func _drop_actor(id: String) -> void:
	if not _actors.has(id):
		return
	if id == "c" and main != null and main.get("rescue_panel") != null:
		main.rescue_panel.set_binding_sprite(null)
	var node: Node = _actors[id]
	if is_instance_valid(node):
		node.queue_free()
	_actors.erase(id)
	_talk.erase(id)
	_recipes.erase(id)


## 场上站着谁：id、贴图、脚底坐标、高度、层级、姿势、翻面、挂着哪段对话。
## **存档要这一份** —— 读档时照它把人摆回来。
func snapshot_actors() -> Array:
	var out: Array = []
	for key: Variant in _recipes:
		var id := str(key)
		if not _actors.has(id) or not is_instance_valid(_actors[id]):
			continue
		var sprite := _actors[id] as Node2D
		var recipe: Dictionary = _recipes[key]
		var entry: Dictionary = {
			"id": id,
			"sprite": str(recipe.get("sprite", "")),
			"at": [sprite.global_position.x, sprite.global_position.y],
			"height": float(recipe.get("height", 45.0)),
			"z": int(recipe.get("z", 9)),
			"pose": str(recipe.get("pose", "")),
			"talk": str(_talk.get(id, "")),
		}
		if recipe.get("rescue_binding", false) == true:
			entry["rescue_binding"] = true
		# 翻面过的人（转身走掉的）也要记，不然读档回来他是正着的
		if sprite is AnimatedSprite2D:
			entry["flip"] = (sprite as AnimatedSprite2D).flip_h
		out.append(entry)
	return out


## 照存档把场上的临时角色摆回来。读档用。
##
## **已经有同名的人就跳过** —— 剧情自己会摆的（节点里的 `npc`）优先级更高，
## 两边都摆会变成两个人。
##
## `flip` 在第二个人身上（`add_actor_with_talk` 不收翻面），所以摆完单独补一下。
func restore_actors(entries: Array) -> void:
	for raw: Variant in entries:
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		var id := str(item.get("id", ""))
		if id == "" or _actors.has(id):
			continue
		var at := Vector2.ZERO
		var pair: Variant = item.get("at", null)
		if pair is Array and (pair as Array).size() >= 2:
			at = Vector2(float((pair as Array)[0]), float((pair as Array)[1]))
		var sprite := add_actor_with_talk(id, str(item.get("sprite", "")), at,
			float(item.get("height", 45.0)), int(item.get("z", 9)),
			str(item.get("pose", "")), str(item.get("talk", "")))
		if id == "c" and item.get("rescue_binding", false) == true \
				and not _c_is_rescued():
			if _add_c_rescue_binding(sprite, float(item.get("height", 45.0))) != null:
				_recipes[id]["rescue_binding"] = true
		if sprite is AnimatedSprite2D and item.get("flip", false) == true:
			(sprite as AnimatedSprite2D).flip_h = true


## 场上有没有这么一个能搭话的临时角色，他现在站在哪儿。
## 返回 `[事件 id, 脚底坐标]`，没有就返回空数组。
##
## `main.interact()` 用这个来判断「玩家面前站着的这个人能不能说话」——
## 地图上那些常驻 NPC 走的是另一条路（`MapDef.actor_near`），
## 这两边都得问，缺一边就是「他站在这儿但你按交互没反应」。
func talkable_at(id: String) -> Array:
	if not _talk.has(id) or not _actors.has(id):
		return []
	var node: Node = _actors[id]
	if not is_instance_valid(node):
		return []
	return [_talk[id], (node as Node2D).global_position]


## 场上所有能搭话的临时角色：`[[id, 脚底坐标, 事件 id], ...]`。
func talkable_list() -> Array:
	var out: Array = []
	for id: Variant in _talk:
		var found := talkable_at(str(id))
		if not found.is_empty():
			out.append([str(id), found[1], found[0]])
	return out


## 演过的指令，按顺序。测试用。
func history() -> Array[String]:
	return _log


# ---------------------------------------------------------------- 跑

## 按顺序演完这一串指令。整段跑完才返回。
##
## `replay_to` 是**读档重入**用的：先把前 `replay_to` 条补演一遍，
## 让画面回到存档那一刻的样子（人站在哪儿、窗帘拉没拉、大图在不在）。
## 补演是**静音且瞬时**的，理由见 `_replay()`。正常演出传 0 就行。
##
## `on_step_done` 每演完一条回调一次，参数是「已经演完几条」。
## 导演拿它记节点内的进度，存档要写进去 —— 这就是它存在的唯一理由。
func run(steps: Array[StageStep], replay_to: int = 0,
		on_step_done: Callable = Callable()) -> void:
	var generation := _generation
	for i: int in range(0, mini(replay_to, steps.size())):
		await _replay(steps[i])
	for i: int in range(replay_to, steps.size()):
		if main == null or generation != _generation:
			return
		await _perform(steps[i])
		if generation != _generation:
			return
		if on_step_done.is_valid():
			on_step_done.call(i + 1)


func _perform(step: StageStep) -> void:
	_log.append(str(step.kind))
	await _apply(step)


## 补演时**不做**的指令。
##
## - `say`：台词已经念过了。**这条就是用户报的那个 bug** ——
##   在「等选择」那一步存档、读回来，整段对白又从头放了一遍
## - `goto` / `place_player`：场景和坐标存档里记着，比演出自己算的更准，
##   补演一遍等于用旧值把新值盖掉
## - `play_sound`：读档不该凭空响一声
## - `wait` / `wait_click`：补演是瞬时的，等时间、等点击都说不通
const REPLAY_SKIP: Array[StringName] = [
	&"say", &"goto", &"place_player", &"play_sound", &"wait", &"wait_click",
	&"save", &"rescue",
]


## 补演一条指令：只把画面还原出来，不念台词、不花时间。
##
## 走 `_apply` 而不是 `_perform`，是为了**不记进 `_log`** ——
## 补演不是「演过一遍」，是「把画面摆回原样」。日志里多出一堆重复条目，
## 之后拿它查「这段到底演了哪几条」就没法看了。
func _replay(step: StageStep) -> void:
	if REPLAY_SKIP.has(step.kind):
		return
	var was := instant
	instant = true
	await _apply(step)
	instant = was


## 真正执行一条指令。`_perform` 负责记一笔演过什么，这里不记。
func _apply(step: StageStep) -> void:
	match step.kind:
		&"say":
			await _say(step)
		&"fade":
			await _fade(step)
		&"banner":
			await _banner(step)
		&"caption":
			await _caption(step)
		&"location":
			_location(step)
		&"hint":
			_hint(step)
		&"play_sound":
			_play_sound(step)
		&"music":
			_play_music(step)
		&"wait":
			await _sleep(step.number("time", 0.5))
		&"wait_click":
			await _wait_click()
		&"save":
			_save_game()
		&"image":
			await _image(step)
		&"image_hide":
			await _overlay().hide_image(_time(step.number("fade", 0.4)))
		&"personal_anchor":
			main.capture_personal_anchor()
		&"personal_anchor_restore":
			main.restore_personal_anchor()
		&"map_actor_variant":
			main.set_actor_sprite_variant(
				StringName(step.text("actor")), StringName(step.text("variant")))
		&"ch2_checkpoint_save":
			main.capture_ch2_checkpoint(step.text("checkpoint"))
		&"ch2_checkpoint_restore":
			main.restore_ch2_checkpoint(step.text("checkpoint"))
		&"ch2_checkpoint_clear":
			main.clear_ch2_checkpoint(step.text("checkpoint"))
		&"ch2_chase_validate":
			main.flags.set_value(&"ch2/chase_ready", main.chase_session.can_start())
		&"ch2_chase_start":
			main.chase_session.begin()
		&"ch2_chase_qte":
			await main.chase_session.run_qte(StringName(step.text("key")), step.number("trigger_x"))
		&"ch2_chase_arrive":
			await main.chase_session.wait_for_arrival()
		&"ch2_chase_mist_retreat":
			await main.chase_session.retreat_mist(step.number("time", 0.3))
		&"ch2_dodge_qte":
			var dodge_success: bool = await main.chase_session.run_dodge_qte(StringName(step.text("key")))
			main.flags.set_value(&"ch2/dodge_succeeded", dodge_success)
		&"npc":
			await _npc(step)
		&"npc_move":
			await _npc_move(step)
		&"npc_pose":
			_npc_pose(step)
		&"npc_remove":
			await _npc_remove(step)
		&"npc_talk":
			_npc_talk(step)
		&"hold":
			_hold(step)
		&"focus":
			await _focus(step)
		&"place_player":
			await _place_player(step)
		&"hide_player":
			_hide_player(step)
		&"goto":
			_goto(step)
		&"eye_open":
			await _eye_open(step)
		&"bg_blink":
			await _bg_blink(step)
		&"shatter":
			await _shatter(step)
		&"flash":
			await _flash(step)
		&"if_panel":
			await _if_panel(step)
		&"rescue":
			await _rescue(step)
		&"glass":
			await _glass(step)
		_:
			push_warning("[演出] 不认识的指令：%s" % step.kind)


# ---------------------------------------------------------------- 各条指令

## 播一小段对话，播完才往下走。
##
## 这段由演出自己播：外面（`main._on_dialogue_finished`）那条回调会被
## 导演的 `_running` 挡住，所以不会绕回推进器去。
func _say(step: StageStep) -> void:
	var box: DialogueBox = main.dialogue
	if box == null:
		return

	# 「把对话框收下去」这一步没有台词
	if step.text("slide") == "out":
		await box.slide_out(_time(step.number("slide_time", 0.28)))
		return

	var dialogue := step.dialogue()
	if dialogue.is_empty():
		return

	box.play(dialogue, false, step.flag("keep_open", false))
	if step.text("slide") == "in":
		box.slide_in(_time(step.number("slide_time", 0.24)))

	if instant:
		# 即时模式不留在这里等玩家点：把这一段记完，直接往下走。
		# 这不是「跳过剧情」—— 台词照样进了记录，只是不等按键。
		box.skip()
		return
	await box.finished


func _fade(step: StageStep) -> void:
	var curtain: StageCurtain = main.stage_curtain
	if curtain == null:
		return
	var to_black := step.text("to") == "black"
	if instant:
		if to_black:
			curtain.snap_down()
		else:
			curtain.snap_up()
		return
	if to_black:
		await curtain.cover(step.number("time", 0.5))
	else:
		await curtain.lift(step.number("time", 0.5))


func _banner(step: StageStep) -> void:
	var overlay: StageOverlay = main.stage_overlay
	if overlay == null or instant:
		return
	await overlay.show_banner(
		step.text("text"),
		step.number("hold", 1.6),
		step.number("fade", 0.5)
	)


## 屏幕正中依次浮现几行字。
##
## 黑屏上的心声（开场那三句）和 end1 的两行都走这条 —— 它们**不该占对话框**：
## 那会儿没有人在说话，底下一块面板反而像有人在念旁白。
##
## `wait_click` 为真就停在场上等玩家点一下；写了 `out` 才在点完后收起，
## 没写则保留字幕直到后续演出接手。`hold` 是「停这么久然后自己淡下去」。
## 两个都不写就是浮完留在场上，由后面那一幕接手。
##
## **即时模式照样把字摆上**，只是不做动画。它跟黑幕一样是「状态」——
## `main.show_ending()` 要看场上有没有这几行字来决定结局文字由谁来演。
func _caption(step: StageStep) -> void:
	var overlay: StageOverlay = main.stage_overlay
	if overlay == null:
		return
	var raw: Variant = step.data.get("lines")
	var lines: Array = raw if raw is Array else []
	await overlay.show_caption(lines, _time(step.number("fade", 0.7)))
	if instant:
		return
	if step.flag("wait_click", false):
		await _wait_click()
		if step.has("out"):
			await overlay.hide_caption(step.number("out", 0.5))
	elif step.has("hold"):
		await _sleep(_time(step.number("hold", 0.0)))
		await overlay.hide_caption(step.number("out", 0.5))


## 左上角的日期 / 时间 / 地点。`text` 写空就是收起来。
func _location(step: StageStep) -> void:
	if main != null:
		main.show_location(step.text("text"))


func _save_game() -> void:
	if main != null:
		main.save_game()


## 一条提示。`at` 不写就是右上角（稿子②），写 `center` 是画面中线上方。
##
## **不等它消失** —— 提示是浮着的一句话，不该把剧情卡住三秒。
func _hint(step: StageStep) -> void:
	if main != null:
		main.show_hint(step.text("text"), step.text("at", "corner"))


## 黑白闪几下。梦里「白光炸开、然后梦碎了」那一下用它。
##
## 默认白闪：黑闪和普通的淡出太像了，分不出是「切场景」还是「被打断」。
## `mono: true` 就让白黑交替 —— 那才是「黑白闪烁」，一路白闪只是一直被打断。
##
## `hold` 是**亮着停多久** —— 嫌闪得太快看不见就加这个，或者把 `time` 放大。
## 一次闪 = `time/2` 亮起 + `hold` + `time/2` 暗回。
func _flash(step: StageStep) -> void:
	# **即时模式下不闪。** 闪是靠补间跑的，等下去测试就卡在中间那一步 ——
	# 和 `_walk_player` 是同一个道理（2026-09-24 踩的）。
	if main == null or main.fade == null or instant:
		return

	var base := Color.WHITE
	if step.text("color", "white").to_lower() == "black":
		base = Color(0.02, 0.02, 0.03)
	var dark := Color(0.02, 0.02, 0.03)

	var colors := PackedColorArray()
	var times := maxi(1, int(step.number("times", 3.0)))
	var mono := step.flag("mono", false)
	for i: int in times:
		colors.append(dark if mono and i % 2 == 1 else base)

	await main.fade.flash(colors, _time(step.number("time", 0.12)),
		_time(step.number("hold", 0.0)))


## 画面正中弹出 IF 条件框。
##
## 数据：
##
##     { "do": "if_panel", "condition": "猫不见了",
##       "if_block": "猫不见了", "then": "来找主角帮忙",
##       "blocks": ["", "立即离开", "", ""],
##       "solve": "立即离开", "wrong": "tutorial_death" }
##
## - `if_block` / `then`：两个块位里**先放着**的块。
##   `if_block` 优先于 `condition`（后者是「if 后面还没摆块」时的固定文字兜底）
## - `blocks`：下面四格（空串 = 空位）
## - `solve`：拖到 `then` 的**得是这块**才算过。不写就是纯展示
## - `wrong`：**什么都没改就按确定**时跳到哪个节点（教学那段的「又一遍」）
##
## **按确定时有三种结果：**
##
## 1. `then` 已经是 `solve` → 过，往下演
## 2. `then` 还是开局那个值 → 跳到 `wrong`（没改，等于没听懂）
## 3. 别的组合 → **把块丢回开局的位置**，让玩家重排（2026-09-25 策划要的）
##
## **即时模式下不等** —— 测试里没人拖、也没人点确定，等下去整段就卡住了。
func _if_panel(step: StageStep) -> void:
	if main == null or main.if_panel == null:
		return
	# **类型要显式标。** `main` 在这是 `Node2D`，取出来的都是 `Variant`，
	# 用 `:=` 会报「Cannot infer the type」。
	var panel: IfPanel = main.if_panel
	var disabled: bool = step.data.get("disabled", false) == true
	var solve := step.text("solve")
	var wrong := step.text("wrong")
	## 「玩家改没改对」记到哪个状态位。剧本用 `next_when` 读它分下游。
	var flag := step.text("flag")
	# **老字段 `result` 也认。** 2026-09-25 之前 `then` 那个位置叫 `result`，
	# 改名之后漏改的剧本会静默变成空块（老人那段就是这么坏的）——
	# 空块不报错，只是画面上少一块。
	var then_block := step.text("then")
	if then_block == "":
		then_block = step.text("result")

	panel.open(step.text("condition"), then_block, step.text("if_block"))
	var blocks: Array = step.data.get("blocks", [])
	for i: int in panel.slot_count():
		panel.set_slot_block(i, str(blocks[i]) if i < blocks.size() else "")
		panel.set_slot_state(i, IfPanel.SlotState.DISABLED if disabled \
			else IfPanel.SlotState.NORMAL)
	# **只读**：`disabled: true` 的框是纯展示，两个块位里的块也不许拽走。
	panel.set_read_only(disabled)
	panel.remember_layout()

	if instant:
		# 测试里没人拖、也没人点确定。**直接摆成答案**，让后面的剧情接得上 ——
		# 不然这段在无头里永远等不到 `confirmed`。
		if solve != "":
			for i: int in panel.slot_count():
				if panel.slot_block(i) == solve:
					panel.move_to_then(i)
					break
		panel.close()
		return

	if solve != "":
		while panel.is_open():
			await panel.confirmed
			# 收尾条件：面板被关掉（剧情取消、回标题）时不能再等下去，
			# 否则协程永远挂在这儿。
			if not panel.is_open():
				break
			# **判定交给 `IfPanel.judge()`** —— 它是纯函数，测试够得着。
			# 夹在协程里的话，「什么都不做按确定就能往下演」那种毛病测不出来
			#（2026-09-25 就是这么被报上来的）。
			var verdict := panel.judge(solve)
			if verdict == IfPanel.Verdict.SOLVED:
				_write_verdict(flag, true)
				break
			if verdict == IfPanel.Verdict.UNTOUCHED:
				# **什么都没改。** 记下来，然后往下走 ——
				# 两条出口**走同一段对话**（策划要的「重演一遍」），
				# 分岔交给下游节点的 `next_when` 读这个 flag。
				#
				# 配了 `wrong` 的话就不走那条路，直接跳过去（以前只有这一种写法）。
				_write_verdict(flag, false)
				if wrong != "":
					panel.close()
					var story: StoryDirector = main.story
					story.jump_to(wrong)
					return
				break
			# 排了别的组合（或者没配 `wrong`）：块丢回原处，让他重排
			panel.reset_blocks()
		if not panel.is_open():
			return
		# 对了停半拍再收 —— 让玩家看清那一块真的换进去了
		await _sleep(0.6)
		panel.close()
		return

	var hold := step.number("hold", 0.0)
	if hold > 0.0:
		await _sleep(hold)
	else:
		# **纯展示也等「确定」**（2026-09-25 起）。
		# 面板要收鼠标才能拖，收进来之后原来那套「点一下继续」就够不着
		# 面板背后的东西了 —— 「观察老人那一步关不掉窗口」的卡关就是这么来的。
		await panel.confirmed
	panel.close()


## 把「玩家改没改对」写进状态。剧本用 `next_when` 读它分下游。
##
## 不写 `flag` 字段就跳过 —— 不需要分下游的那种框（纯展示）不关心这个。
func _rescue(step: StageStep) -> void:
	var binding := _actor_binding("c")
	if instant:
		if binding != null:
			binding.call("set_state", RescueTiming.LINE_COUNT)
		_write_verdict(step.text("flag"), true)
		return
	var panel: RescuePanel = main.rescue_panel
	if panel == null or not main.is_inside_tree():
		return
	var generation := _generation
	panel.set_binding_sprite(binding)
	panel.open()
	while panel.is_open() and generation == _generation:
		await main.get_tree().process_frame
	panel.set_binding_sprite(null)
	if generation == _generation:
		_write_verdict(step.text("flag"), panel.success_result)


func _write_verdict(flag: String, solved: bool) -> void:
	if flag == "" or main == null or main.flags == null:
		return
	main.flags.set_value(StringName(flag), solved)


## 放一段音效。
##
## 素材还没到，`main.play_sound()` 找不到文件会静默跳过 —— 所以剧本里这条
## 现在就可以照写（路径按约定填），文件一到位就响。路径写错不会报错，
## 由 `tools/check_data.py` 负责把它查出来。
func _play_sound(step: StageStep) -> void:
	if main != null:
		main.play_sound(step.text("path"))


## 换背景音乐。`path` 留空**就是停**。
##
## 走的还是 `main.play_music()` —— 和地图自带的 `music` 字段同一套，
## 所以「同一首还在播就不重放」在这儿一样成立。
##
## 为什么剧本要能压这一手：地图的 `music` 是「**进这个场景该放什么**」，
## 进场景就响；而开场那一段要先黑屏、念三行旁白，**那时候得是安静的**，
## 等画面亮起来、人出现在屋里才该起前奏。光靠地图字段压不住，
## 只好让剧本自己说「先停，等我说放再放」。
func _play_music(step: StageStep) -> void:
	if main != null:
		main.play_music(step.text("path"))


func _wait_click() -> void:
	if instant:
		return
	_waiting = true
	if not _waiting:
		return
	await clicked
	_waiting = false


## 等这么久，**中途点一下可以提前过**。
##
## 做法是「一边等一边听点击」：`_waiting` 被 `consume_click()` 清掉就收工。
## 收工之后**要把 `_waiting` 放下来**，不然下一段本来就该等的点击会被吃掉。
func _wait_click_or_hold(seconds: float) -> void:
	if instant:
		return
	_waiting = true
	var left := seconds
	while left > 0.0 and _waiting:
		await _sleep(minf(0.1, left))
		left -= 0.1
	_waiting = false


## 屏幕中央的大图。
##
## 「淡入 → 点一下 → 淡出」是最常要的节奏，所以写成一条：
## `wait_click` 为真就等玩家点，`hide` 不为假就自己收掉。
func _image(step: StageStep) -> void:
	var overlay: StageOverlay = main.stage_overlay
	if overlay == null:
		return
	var fade := _time(step.number("fade", 0.4))
	var fill := step.flag("fill", false)
	if not await overlay.show_image(step.text("path"), fade, fill):
		return
	# `hold` 是「这张图停多久」。**停的过程中点一下可以提前翻过去** ——
	# 一张 CG 三秒，看腻了的人不该被按在那儿。
	var hold := _time(step.number("hold", 0.0))
	if hold > 0.0:
		await _wait_click_or_hold(hold)
	elif step.flag("wait_click", false):
		await _wait_click()
	if step.flag("hide", true):
		await overlay.hide_image(fade)


## 把玩家角色**藏起来 / 显示回来**。
##
## 用在「场景图上已经画着人了」那几幕 —— 比如「床上躺着主角」那张图，
## 上面本来就画着躺的人，再叠一个小人上去就是两个主角。
##
##     { "do": "hide_player", "visible": false }   ← 藏
##     { "do": "hide_player" }                     ← 显示回来（默认）
##
## **和「把镜头挪开」不是一回事。** 镜头挪开只是碰巧看不见他 ——
## 人还在场上，位置、碰撞、脚下的东西都照旧。要真不在，用这条。
##
## 补演（读档）时会跟着跑：藏着这个状态本身是要还原的画面。
func _hide_player(step: StageStep) -> void:
	if main == null or main.player == null:
		return
	main.player.visible = step.flag("visible", true)


## 在地图上放一个临时角色（老人这种）。
##
## 用的是立绘 —— 没有专门的「行走小人」，把立绘缩到人物的高度顶上去。
## 真素材到位后只要换 `sprite` 路径，这一条指令不用改。
func _npc(step: StageStep) -> void:
	var height := step.number("height", 30.0)
	# `pose` 是出场时就摆好的姿势（`idle_<名字>`），不写就用他有的第一组。
	# A 出场是蹲着的：「a 蹲在店铺门口修留声机」。
	# `talk` 是「这人身上挂着哪段对话」—— 演出演完、控制权交回玩家之后，
	# 玩家走到他跟前按交互就能起那一段。
	var sprite := add_actor_with_talk(step.text("id"), step.text("sprite"),
		step.point("at"), height, int(step.number("z", 9.0)), step.text("pose"),
		step.text("talk"))
	if sprite == null:
		return
	var id := step.text("id")
	if id == "c" and step.flag("rescue_binding", false) and not _c_is_rescued():
		if _add_c_rescue_binding(sprite, height) != null:
			_recipes[id]["rescue_binding"] = true

	var fade := _time(step.number("fade", 0.0))
	sprite.modulate.a = 0.0 if fade > 0.0 else 1.0

	if fade > 0.0:
		var tween := _tween()
		tween.tween_property(sprite, "modulate:a", 1.0, fade)
		await tween.finished


func _add_c_rescue_binding(actor: Node2D, height: float) -> Sprite2D:
	if not actor is AnimatedSprite2D:
		return null
	var animated := actor as AnimatedSprite2D
	var frame := animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
	if frame == null or height <= 0.0 or animated.scale.x <= 0.0 or animated.scale.y <= 0.0:
		return null
	var binding: Sprite2D = C_RESCUE_BINDING_SCRIPT.new()
	binding.name = "RescueBinding"
	binding.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	binding.call("set_state", 0)
	var binding_size: Vector2 = binding.texture.get_size()
	# 束缚是 C 的子节点，地图/角色缩放会由父节点统一带下去。
	# 这里只把两张源画布对齐，不能再除 actor.scale 抵消地图比例。
	var binding_scale := frame.get_size().y / maxf(binding_size.y, 1.0)
	binding.position = Vector2(0.0, -frame.get_size().y * 0.5)
	binding.scale = Vector2.ONE * binding_scale
	binding.z_index = 1
	animated.add_child(binding)
	return binding


func _actor_binding(id: String) -> Sprite2D:
	var actor := _actor(id)
	if actor == null:
		return null
	return actor.get_node_or_null("RescueBinding") as Sprite2D


func _c_is_rescued() -> bool:
	return main != null and main.flags != null \
		and main.flags.get_value(&"ch2/rescued_c") == true


func _npc_move(step: StageStep) -> void:
	var actor := _actor(step.text("id"))
	if actor == null:
		return
	var target := step.point("to")
	var time := _time(step.number("time", 1.0))
	_walk_actor(actor, target)
	# **脚步和走路一起跑。** 这一句不 await —— 让它自己在后台按步频踩，
	# 下面照旧等补间跑完。要是 await 它，人就得先踩完脚步才开始走。
	_footsteps_for(time)
	if step.flag("fade", false):
		# **一边平移一边淡出。** 没有走路动画的角色（A 只有侧站和蹲着两张图）
		# 只能这么退场 —— 硬切帧的话他会像一张贴纸在滑。
		#
		# 淡出**提前跑完**（走完这一段的 80% 就全透明了）：策划专门叮嘱
		# 「注意在撞到什么东西之前就要消失」—— 人挪到摊位跟前还没淡完的话，
		# 会看见一张半透明的人叠在摊子上。
		await _move_and_fade(actor, target, time)
	else:
		await _move_to(actor, target, time)
	_stop_actor(actor)


## 演出里临时角色走路的步频（秒）。
##
## 和主角那边对齐：主角 96 像素/秒、每 24 像素一步，合 0.25 秒一步。
## 写的是字面值 —— 常量里引用别的类的常量，GDScript 解析不过。
const STEP_SECONDS := 0.25


## 走这一段路的时候，替这个人踩几步。
##
## 按**时间**撒，不是按位移量：演出里的移动是补间直接改 `position` 的，
## 中途插不进「每走 24 像素算一次」那种判断（主角那边可以，因为它每帧
## 都在 `_physics_process` 里）。步频取 `STEP_SECONDS`，和主角那边对齐。
##
## 场景的 `footstep` 是空就什么也不做 —— 户外不该有木板声，
## 老人要是走到集市上，自然就没声了。
func _footsteps_for(seconds: float) -> void:
	var sound := _footstep_sound()
	if sound == "":
		return
	var left := seconds
	while left > STEP_SECONDS:
		left -= STEP_SECONDS
		await _sleep(STEP_SECONDS)
		if main != null:
			main.play_sound(sound)


## 这个场景里走路踩的是什么。没指定就是空。
func _footstep_sound() -> String:
	if main == null or main.current_map == null:
		return ""
	return main.current_map.footstep


## 让临时角色**开始走**。静态立绘走到这里是空操作 —— 它没有动画，只会被平移。
##
## 方向只看 `y`：屏幕坐标 y 变小就是往上走，露背面；其余都露正面。
func _walk_actor(actor: Node2D, target: Vector2) -> void:
	if not (actor is AnimatedSprite2D):
		return
	var sprite := actor as AnimatedSprite2D
	var face := "up" if target.y < sprite.position.y else "down"
	_play_if_any(sprite, StringName("walk_" + face))


## 走完了，换成站立帧。
##
## `idle_*` 那一组用的就是 `walk_*` 的第 1 帧，而策划给的素材里 1 号是站姿，
## 所以「停下 = 播 idle」正好落在对的那张上。
func _stop_actor(actor: Node2D) -> void:
	if not (actor is AnimatedSprite2D):
		return
	var sprite := actor as AnimatedSprite2D
	_play_if_any(sprite, StringName(String(sprite.animation).replace("walk_", "idle_")))


## 有这个动画才播，没有就保持原样。
##
## 比如某个角色只画了背面一帧，那就一直露背面 ——
## 不该因为缺 `walk_up` 就报错或者停在半路。
func _play_if_any(sprite: AnimatedSprite2D, name: StringName) -> void:
	if sprite.sprite_frames.has_animation(name):
		sprite.play(name)


## 这个角色该从哪个姿势起手。
##
## `pose` 写的是姿势/方向名（对应 `idle_<名字>`）。**没写、或者这个角色没有
## 那一组帧，就退到它有的第一组** —— 写死 `idle_down` 的话，
## 只有侧面和蹲下两张图的 A 会什么都不显示。
func _idle_animation(frames: SpriteFrames, pose: String) -> StringName:
	if pose != "":
		var want := StringName("idle_" + pose)
		if frames.has_animation(want):
			return want
	var names := frames.get_animation_names()
	for name: String in names:
		if name.begins_with("idle_"):
			return StringName(name)
	return StringName(names[0]) if not names.is_empty() else &""


## 换个姿势 / 翻个面。
##
## A 没有走路动画，「转过身去」只能靠把侧面图水平翻过来。静态立绘也能翻
##（`Sprite2D` 和 `AnimatedSprite2D` 都有 `flip_h`）。
##
## `pose` 不写就只翻面。翻面**不会自己翻回去** —— 后面要正回来就再写一条。
func _npc_pose(step: StageStep) -> void:
	var actor := _actor(step.text("id"))
	if actor == null:
		return

	if step.has("flip"):
		var flipped := step.flag("flip", false)
		if actor is AnimatedSprite2D:
			(actor as AnimatedSprite2D).flip_h = flipped
		elif actor is Sprite2D:
			(actor as Sprite2D).flip_h = flipped

	var pose := step.text("pose")
	if pose == "" or not (actor is AnimatedSprite2D):
		return
	_play_if_any(actor as AnimatedSprite2D, StringName("idle_" + pose))


func _npc_talk(step: StageStep) -> void:
	var id := step.text("id")
	if _actor(id) == null:
		return
	var talk := step.text("talk")
	if talk.is_empty():
		_talk.erase(id)
	else:
		_talk[id] = StringName(talk)


func _npc_remove(step: StageStep) -> void:
	var id := step.text("id")
	var sprite := _actor(id)
	if sprite == null:
		return

	var fade := _time(step.number("fade", 0.0))
	if fade > 0.0:
		var tween := _tween()
		tween.tween_property(sprite, "modulate:a", 0.0, fade)
		await tween.finished

	_actors.erase(id)
	sprite.queue_free()


## 摆好两边的人，停在「等选择」的状态上。
##
## 这一步之后**没有台词**：面板空着留在场上，选项由导演摆进
## `DialogueBox.hold_rect()` 那一块。之所以要单独一条指令，
## 是因为「谁站在哪」是编排的事 —— 对话框自己不知道剧情里谁该出场。
func _hold(step: StageStep) -> void:
	var box: DialogueBox = main.dialogue
	if box == null:
		return
	var cast: Dictionary = {
		"left": step.data.get("left", {}),
		"right": step.data.get("right", {}),
	}
	box.hold_open(cast, step.flag("slide", true) and not instant)


## 让镜头看某个点。不写 `at` 就是还给角色。
##
## `time` 大于 0 时是**平摇**过去：镜头从当前位置滑到新的位置。
## 老人从门口走上来那一段就靠它 —— 先框住门口，人走到半路镜头再抬上来，
## 最后两个人都在画面里。
func _focus(step: StageStep) -> void:
	if main == null:
		return

	if not step.has("at"):
		main.camera_focus = null
		main.update_camera()
		return

	var target := step.point("at")
	var time := _time(step.number("time", 0.0))
	if time <= 0.0 or main.camera_focus == null:
		main.camera_focus = target
		main.update_camera()
		return

	var tween := _tween()
	tween.tween_property(main, "camera_focus", target, time)
	await tween.finished


## 把角色摆到某处，或者让它**沿路径点走过去**。
##
## 三种写法：
##   - `at`，不带 `time` —— 直接摆在那儿，不算走路；
##   - `at`，带 `time` —— 从当前位置走过去；
##   - `path` —— 一串路径点，一段一段走，**最后一个点就是终点**。
##
## `at` 默认是**脚底**落在哪儿；写 `anchor: "head"` 就改成**头的正中央**
## 落在哪儿。躺床上那一幕要的是后者：头进枕头，脚自然在下面，
## 剧本里不用手算那个偏移。
##
## **这一步必须 `await`**（见 `_perform`）。它是全篇唯一一条会等自己的指令，
## 漏了 `await` 的后果很具体（2026-09-24 策划报的）：走路补间还在跑，
## 后面几步已经压上来了 —— 人一边往右走、一边按后一步的朝向露背面，
## 最后「还没走到床边，黑屏就下来了」。
##
## `pin: true` 让角色**被按住**：不参与物理，也不被挤出去。躺床上那一幕
## 要靠它 —— 那个点落在床的碰撞箱里，物理每帧会把人推出来，画面上是在抖。
func _place_player(step: StageStep) -> void:
	if main.player == null:
		return

	var route := step.points("path")
	var target := step.point("at")
	if not route.is_empty():
		target = route[route.size() - 1]
	else:
		route.append(target)

	var walk := _time(step.number("time", 0.0))
	var walking := not instant and (walk > 0.0 or step.has("path"))

	# **即时模式下不走、直接落位。** 走路是 `await` 出来的，一 await 就把
	# 控制权让出去 —— 而测试依赖「`interact()` 之后整段同步跑完」，
	# 让出去的话后面几步根本轮不到，测试会看到演出停在半路
	# （2026-09-24 踩的：加了走路之后两条断言立刻红）。
	if walking:
		await _walk_player(route, walk)
	elif step.text("anchor") == "head":
		main.player.place_head_at(target)
	else:
		main.player.global_position = target

	main.player.velocity = Vector2.ZERO
	# 朝向：不写 `facing` 就不动它 —— 走完那段留着的朝向本来就是对的
	# （往上走完该露背面），硬写成默认的「朝下」会把最后一步拧回去。
	if not walking or step.has("facing"):
		main.player.facing = _facing(step.text("facing", "down"))
	main.player.play_animation(false)
	# `pin` 是给「落在实体里」的场合用的：床上那一幕脚就落在床的碰撞箱里，
	# 不按住的话物理会每帧把人推出来 —— 画面上是一直在抖。
	#
	# **设完必须让 `update_player_control()` 过一遍**：`pinned` 只是个普通变量，
	# 真正 `set_physics_process(false)` 的是那一步。少了它，物理照跑，
	# 人会当场被挤出床（2026-09-23 踩到：人躺到床头板上方去了，
	# 看着像坐标算错，其实是物理推的）。
	main.player.pinned = step.flag("pin", false)
	main.update_player_control()
	main.update_camera()


## 让主角沿路径点走。**每一段都拆成「先横后竖」**，画面上只有四个方向。
##
## 直接补间到目标点是**斜着飘过去**的，小人看着像在水上漂（2026-09-24 策划报的）。
## 角色在屋里本来就只会上下左右走，路线也该是折的。
##
## `total_time` 不写（0）就按角色当前地图标尺下的脚程算；显式时长保持剧本值。
## 和玩家自己走是一个速度 —— 剧情里走路快一截或者慢一截，一眼就出戏。
## 写了就按距离摊到每一段（不分的话短的那段会显得飞快）。
##
## 路径点用 `tests/probe_route.gd` 量出来：脚底方块那 16 个像素、
## 每一件挡人的家具都要算进去，手算差两像素就贴着墙走不过去。
func _walk_player(route: Array[Vector2], total_time: float) -> void:
	var player: Player = main.player
	# 从**人在哪**起步，不从第一个路径点起步 —— 两者差几像素的时候，
	# 按路径点算出来的位移会让人最后停偏。
	var full: Array[Vector2] = [player.global_position]
	full.append_array(route)
	var legs := _legs_of(full)
	if legs.is_empty():
		return

	var total := 0.0
	for leg: Vector2 in legs:
		total += leg.length()
	var span := total_time if total_time > 0.0 else total / player.movement_speed()

	# 脚步按时间撒，和走路一起跑（不 await：await 的话人得先踩完脚步才动）。
	_footsteps_for(span)

	for leg: Vector2 in legs:
		player.facing = _facing(_facing_name(leg))
		player.play_animation(true)
		# **按位移量补间，不是按目标坐标。** 补间改的是 `position`，
		# 而演出里说的坐标都是 `global_position`；用位移量就不必管
		# 角色挂在哪个父节点底下、那个节点有没有偏移。
		await _move_to(player, player.position + leg,
			maxf(0.02, span * leg.length() / total))
	player.play_animation(false)


## 把路径点拆成一串**只含正方向**的小段。
##
## 两个点之间要是同时差着 x 和 y（手写路径点时会这样），就拆成「先横后竖」
## 两段 —— 直接斜着补间过去，小人就成了漂移。
func _legs_of(route: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in range(1, route.size()):
		var gap := route[i] - route[i - 1]
		if absf(gap.x) > 0.5:
			out.append(Vector2(gap.x, 0.0))
		if absf(gap.y) > 0.5:
			out.append(Vector2(0.0, gap.y))
	return out


## 一个位移方向算是「上/下/左/右」的哪一个。四向，斜着走时取分得比较开的那个轴。
func _facing_name(gap: Vector2) -> String:
	if absf(gap.x) >= absf(gap.y):
		return "right" if gap.x > 0.0 else "left"
	return "down" if gap.y > 0.0 else "up"


func _goto(step: StageStep) -> void:
	# 换场景时先把上一张图上的临时角色收掉：他们是上一个场景的东西
	clear_actors()
	main.enter_map(StringName(step.text("map")),
		StringName(step.text("spawn", "default")), true)


## 碎玻璃：一张黑底素材从正中炸开，叠在画面上。
##
## 它**不压黑** —— 压黑是 `StageCurtain` 的事，两者是两层。
## 演出里通常是「先 `glass` 裂开、再 `fade` 黑下去」，
## 反了就成了黑屏上冒出一道裂痕，看不出是屏幕碎了。
func _glass(step: StageStep) -> void:
	var overlay: StageOverlay = main.stage_overlay
	if overlay == null:
		return
	if instant:
		# 无头模式没有帧循环，动画推不动。把「已经碎好了」这个状态摆上 ——
		# 截图和测试要看的是这一帧的样子，不是动画过程。
		overlay.glass_show()
		return
	await overlay.glass_burst(
		step.number("hold", 0.6), step.number("fade", 0.5))


## 画面碎掉。
##
## 顺序要紧：**先切片盖上去，再把底黑掉**。反过来的话截图截到的就是黑的。
## 碎片自己盖满整屏，所以黑底那一刻画面上看不出变化，等碎片飞散才露出来。
func _shatter(step: StageStep) -> void:
	var overlay: StageOverlay = main.stage_overlay
	if overlay == null:
		return
	if instant:
		# 无头模式截不到画面，特效本来也跑不起来；
		# 黑底这一步是状态，得留下 —— 后面那句台词是在黑屏上说的。
		if main.stage_curtain != null:
			main.stage_curtain.snap_down()
		return

	var ready: bool = await overlay.shatter_begin()
	if not ready:
		return
	if main.stage_curtain != null:
		main.stage_curtain.snap_down()
	await overlay.shatter_play(step.number("time", 1.0))


## 背景闪几下：集市和纯黑来回切，最后停在黑。**主角一直留在画面上。**
##
## 用在「门」那一幕的余波：背景在闪，人定在原地。
##
## 做法是把 `map_view` 和 `stage_view`（演出里的临时角色）**一起藏起来** ——
## 它俩是 `main` 底下的兄弟节点，而**主角不在它们里面**（主角是 `main`
## 自己的子节点），所以藏了之后画面上只剩主角一个人，背后是视口的底色（近黑）。
##
## 只藏 `map_view` 不够：临时角色挂在 `stage_view` 上，会留下一个人飘在黑里。
func _bg_blink(step: StageStep) -> void:
	if main == null:
		return
	var times := maxi(1, int(step.number("times", 3.0)))
	var hold := _time(step.number("hold", 1.0))

	# 即时模式：直接当成「已经闪完、停在黑」—— 这一步留下的是**状态**
	if instant:
		_set_world_visible(false)
		return

	for i: int in times:
		# 从头数：第 1 下切黑、第 2 下切亮、第 3 下再切黑（三次切换）
		_set_world_visible(i % 2 == 1)
		await _sleep(hold)
	_set_world_visible(false)


## 把「世界」（地图 + 演出里的临时角色）藏起来或露出来。
## 主角不在里头，所以藏了之后他还是站着。
##
## **`enter_map()` 会把两边都恢复**（见那儿的一句）—— 这个安排是
## 「某一幕」的，换场景以后不该跟过来。
func _set_world_visible(on: bool) -> void:
	var view: MapView = main.map_view
	if view != null:
		view.visible = on
	var stage: Node2D = main.stage_view
	if stage != null:
		stage.visible = on


## 睁眼：黑幕中间一个椭圆睁开、眨两下，再完全亮起来。
##
## **脚本里得先把幕布揭开**（`{"do":"fade","to":"clear","time":0}`），
## 不然椭圆里看见的是幕布那层黑 —— 这一条只管眼罩那一层。
func _eye_open(step: StageStep) -> void:
	var overlay: StageOverlay = main.stage_overlay
	if overlay == null:
		return
	# **即时模式下直接当成睁完了。** 它靠补间推，等下去测试就卡在中间那一步
	#（和 `_flash` / `_walk_player` 同一个道理）。
	if instant:
		overlay.eye_finish()
		return
	await overlay.eye_open(int(step.number("blinks", 2.0)))


# ---------------------------------------------------------------- 工具

func _overlay() -> StageOverlay:
	return main.stage_overlay


## 走一段路。即时模式里直接落位。
func _move_to(node: Node2D, target: Vector2, time: float) -> void:
	if instant or time <= 0.0 or main == null:
		node.position = target
		return
	var tween := _tween()
	tween.tween_property(node, "position", target, time)
	await tween.finished


## 边走边淡出时，淡出占整段的几成。
##
## **不到 1**：走到终点之前就该全透明了 —— 策划专门叮嘱「注意在撞到什么东西
## 之前就要消失」。人挪到摊位跟前还没淡完的话，会看见一张半透明的人叠在摊子上。
const MOVE_FADE_RATIO := 0.8


## 走一段路，同时淡出。位置和透明度**并行**补间 —— 串行的话人要走到位才消失。
func _move_and_fade(node: Node2D, target: Vector2, time: float) -> void:
	if instant or time <= 0.0 or main == null:
		node.position = target
		node.modulate.a = 0.0
		return
	var tween := _tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position", target, time)
	tween.tween_property(node, "modulate:a", 0.0, time * MOVE_FADE_RATIO)
	await tween.finished


## 造一个临时角色。**`path` 指目录还是文件，决定造哪一种：**
##
## - 指一个**目录** → `AnimatedSprite2D`，会走路。目录里放 `<方向><序号>.png`，
##   由 `tools/make_npc_frames.py` 生成。
## - 指一张**图** → `Sprite2D`，静态。一张立绘当小人用。
##
## 为什么要能做动画：静态图在 `_move_to` 里是**平移**，看着像一张贴纸在滑。
## 老人上门那段是从门口一路走进来的，滑过去很出戏。
##
## height 是与主角共用的逻辑显示高度，制作时换成当前地图标尺。
## 配方/快照仍保存原 height，恢复时重新换算，不重复累乘；脚底坐标不变。
func _make_actor(path: String, height: float, z: int = 9, pose: String = "") -> Node2D:
	height *= _map_character_scale()
	if DirAccess.dir_exists_absolute(path):
		return _make_animated_actor(path, height, z, pose)
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[演出] 找不到临时角色的图：%s" % path)
		return null
	var res: Resource = load(path)
	if not (res is Texture2D):
		push_warning("[演出] 临时角色的图不对：%s" % path)
		return null

	var texture: Texture2D = res
	var picture := texture.get_size()
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	# 和玩家一个道理：offset 按贴图像素写，它和贴图一起被 scale 缩
	var ratio := height / maxf(picture.y, 1.0)
	sprite.scale = Vector2(ratio, ratio)
	sprite.offset = Vector2(-picture.x * 0.5, -picture.y)
	# 站在场景里的人要盖住家具，但别盖住玩家
	sprite.z_index = z
	_add_actor_body(sprite, Vector2(picture.x * ratio, picture.y * ratio))
	return sprite


## 人物共用地图标尺：不改变剧情的高度参数或脚底世界坐标。
func _map_character_scale() -> float:
	return main.current_map.player_scale if main != null and main.current_map != null else 1.0


## 造一个会走路的临时角色。
##
## 朝向只有**正面和背面** —— NPC 素材现在只给了这两面（见
## `tools/make_npc_frames.py` 的 `DIR_NAMES`）。左右移动也算正面：
## 没有侧面素材的时候硬套一张，比不动还怪。
func _make_animated_actor(folder: String, height: float, z: int,
		pose: String = "") -> AnimatedSprite2D:
	var frames := _actor_frames(folder)
	if frames == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.centered = false
	sprite.animation = _idle_animation(frames, pose)
	# 尺寸按**动画的第一帧**算 —— 同一个角色的帧共用一张画布，大小都一样
	var texture := frames.get_frame_texture(sprite.animation, 0)
	if texture == null:
		return null
	var picture := texture.get_size()
	var ratio := height / maxf(picture.y, 1.0)
	sprite.scale = Vector2(ratio, ratio)
	sprite.offset = Vector2(-picture.x * 0.5, -picture.y)
	sprite.z_index = z
	_add_actor_body(sprite, Vector2(picture.x * ratio, picture.y * ratio))
	return sprite


## 给临时角色脚下加一条挡人的碰撞。
##
## **和地图上常驻 NPC 一个规矩**（见 `MapView._build_actor_collision` 里
## `person` 那一段）：只挡脚下一小条。挡整个人会把上半身也算成墙 ——
## 角色是 Q 版的，肩以上的轮廓全是透明的，玩家从旁边过会被看不见的东西绊住。
##
## 为什么要有：**没有它，玩家从小人身上直接穿过去**（2026-09-24 策划报的）。
## 演出期间本来无所谓（那时候玩家动不了），但「演完留在场上、还能搭话」
## 的角色就必须挡人 —— 他是这个场景里的人，不是一张贴图。
##
## `drawn` 是这个人画出来多大（贴图尺寸 × 缩放）。
func _add_actor_body(sprite: Node2D, drawn: Vector2) -> void:
	# **尺寸要按 sprite 的缩放除回去。** 碰撞体挂在 sprite 底下，
	# 会跟着它一起被 scale 缩 —— 直接写「宽 21、高 8」的话，实际只剩 2.7 像素宽，
	# 挡不住人（2026-09-24 实测：玩家停在 358.7，而算出来该停在 349）。
	var s := sprite.scale
	var wide := Vector2(s.x, s.y)
	if wide.x <= 0.0 or wide.y <= 0.0:
		wide = Vector2.ONE

	var body := StaticBody2D.new()
	body.name = "Body"
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	# 脚下那一条按统一显示标尺：宽＝画出来的宽度减 4，高 8。
	var map_scale := _map_character_scale()
	box.size = Vector2(maxf(drawn.x - 4.0 * map_scale, map_scale) / wide.x,
		8.0 * map_scale / wide.y)
	shape.shape = box
	# 原点在脚底，所以这一条的中心在往上 4 的地方
	shape.position = Vector2(0.0, -4.0 * map_scale / wide.y)
	body.add_child(shape)
	sprite.add_child(body)


## 扫一个角色的帧目录，拼出帧表。
##
## 每个方向两组：`walk_<方向>` 整组循环走，`idle_<方向>` 只用**第 1 帧**。
## 第 1 帧当站立是策划给的约定（他给的素材里 1 号就是站姿）。
##
## **帧号是按目录里实际有什么扫出来的，不是写死的数组。** 老奶奶背面只有一张
## （背对着走也看不出步子），将来谁多给几帧，这里不用改。
##
## 一个方向都没有就返回 null，让外面别建这个角色 —— 缺帧的动画播起来会跳。
func _actor_frames(folder: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var found := 0
	# `side` 和 `crouch` 不是方向，是 A 的两个姿势（侧站、蹲着）。
	# 帧目录和动画名的机制一样，所以就并在这张表里，不另开一套。
	for direction: String in ["down", "up", "side", "crouch"]:
		var numbers := _scan_frames(folder, direction)
		if numbers.is_empty():
			continue
		var walk := StringName("walk_" + direction)
		frames.add_animation(walk)
		# 帧率和玩家取同一个值：同一段路，步子快慢该一致
		frames.set_animation_speed(walk, Player.WALK_FPS)
		frames.set_animation_loop(walk, true)
		for number: int in numbers:
			var texture: Resource = load("%s/%s%d.png" % [folder, direction, number])
			if texture is Texture2D:
				frames.add_frame(walk, texture)
		# 站立那组只有一帧，**也要设循环**：不循环的话播完 `is_playing` 变 false，
		# 每帧都得重新 play 一次。理由同 `Player.build_frames()`。
		var idle := StringName("idle_" + direction)
		frames.add_animation(idle)
		frames.set_animation_speed(idle, Player.WALK_FPS)
		frames.set_animation_loop(idle, true)
		frames.add_frame(idle, frames.get_frame_texture(walk, 0))
		found += 1
	return frames if found > 0 else null


## 目录里这个方向有哪些帧号，升序，比如 `[1, 2, 3, 4]`。
##
## 用目录列表，不从 1 往上试文件在不在 —— 试的写法要在循环里问十几次文件系统，
## 而且帧号断档（1、2、4）时它会停在第 2 帧，**少一帧不报错**。
func _scan_frames(folder: String, direction: String) -> Array[int]:
	var numbers: Array[int] = []
	var seen := {}
	for name: String in DirAccess.get_files_at(folder):
		# **导出包里列出来的是 `down1.png.import`，不是 `down1.png`。**
		# 编辑器里两个都在（走真实文件系统），打包之后只剩带 `.import` 的那些 ——
		# 只认 `.png` 结尾的话，编辑器里一切正常，exe 里一帧都扫不到，
		# 临时角色静默消失（2026-09-24，策划报「第一章开场老人没出来」）。
		var base := name
		if base.ends_with(".import"):
			base = base.substr(0, base.length() - ".import".length())
		if not base.begins_with(direction) or not base.ends_with(".png"):
			continue
		var middle := base.substr(direction.length(),
			base.length() - direction.length() - 4)
		if not middle.is_valid_int():
			continue
		# 同一帧可能两个名字都给出来（编辑器里就是），去重
		var number := int(middle)
		if seen.has(number):
			continue
		seen[number] = true
		numbers.append(number)
	numbers.sort()
	return numbers


## 取场上那个临时角色。
##
## **返回 `Node2D`，不是 `Sprite2D`。** 静态立绘是 `Sprite2D`、
## 会走路的那种是 `AnimatedSprite2D`，两者只共用到 `Node2D` 这一层 ——
## 写成 `Sprite2D` 的话，动画那种取出来会变成 null，表现是「角色放出来了、
## 但之后所有的移动和收场都当它不存在」。
func _actor(id: String) -> Node2D:
	if id == "" or not _actors.has(id):
		push_warning("[演出] 临时角色「%s」还没放出来" % id)
		return null
	var node: Node = _actors[id]
	if not is_instance_valid(node):
		return null
	return node as Node2D


func _facing(name: String) -> Vector2:
	match name:
		"up":
			return Vector2.UP
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		_:
			return Vector2.DOWN


## 一段时间的长度。即时模式里一律换成 0 —— 所有动画都按 0 处理。
func _time(seconds: float) -> float:
	return 0.0 if instant else seconds


## 建一个**会跟着世界一起停**的补间。
##
## 为什么不直接 `main.create_tween()`：`main` 设了 `PROCESS_MODE_ALWAYS`
## （为了保住输入通路，见 `main.boot()`），而补间默认跟着宿主节点走 ——
## 于是暂停菜单开着的时候，老人的走动补间还在跑（2026-09-24 报的）。
##
## 挂到 `main.stage_view` 上就对了：它是 `PROCESS_MODE_PAUSABLE`，
## 而且演出里那些临时 NPC 本来就挂在它底下 —— 补间和它动的东西在同一个节点下。
func _tween() -> Tween:
	return main.stage_view.create_tween()


func _sleep(seconds: float) -> void:
	if instant:
		return
	# **先问在不在树里。** 直接 `main.get_tree()` 的话，节点没进树时
	# 它会一边返回 null 一边喷 `Parameter "data.tree" is null` —— 那行报错
	# 跟演出对不对没有关系，只会把真问题淹掉。
	if main == null or not main.is_inside_tree():
		push_warning("[演出] 主场景不在树里，这一步的等待被跳过")
		return
	# **第二个参数必须写 false。** `create_timer(sec)` 默认是「暂停时也走」
	# （`process_always = true`），于是 ESC 菜单开着的时候演出照推进 ——
	# 玩家看着老人继续走、立绘继续浮（2026-09-24 报的）。
	# 传 false 才是「跟着世界一起停」。
	await main.get_tree().create_timer(seconds, false).timeout
