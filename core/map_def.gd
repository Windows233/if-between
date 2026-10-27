## 场景定义：描述一个场景（室内房间 / 室外地点）的静态布局。
##
## 只认数据，不认节点。读 JSON 是外面的事，这里负责把 Dictionary
## 变成「可校验、可查询」的对象。core 层不许碰 FileAccess 和 SceneTree。
##
## 坐标用像素，原点在场景左上角，y 轴向下（Godot 的默认方向）。
## 场景大小、墙的位置、传送点的连接，全部来自数据，代码里不该出现具体地名。
class_name MapDef
extends RefCounted

const Trigger := preload("res://core/map_trigger.gd")
const DRAW_LAYERS := ["", "back", "auto", "front", "above_overlay"]

## 场景类型。决定「怎么触发连接」和「角色能不能走」。
enum Kind {
	ROOM,       ## 室内：角色可走动，踩在连接上按交互键触发
	OVERWORLD,  ## 大地图：角色不出现，鼠标点选连接触发
}

## 朝向判定的松紧：点积大于这个数才算「在面前」。
## 0.2 大约是正面左右各 78 度 —— 够宽，贴着桌角按也不会没反应，
## 又窄到能把「背后那个书架」排除掉。
const FACING_DOT := 0.2

## 一个连接。房间之间的门和大地图上的一处地点共用这份结构，
## 区别只在**触发方式**，由所在场景的 `kind` 决定。
class Portal:
	extends RefCounted

	## 触发之后干什么。
	##
	## **别把这个枚举叫 `Action`。** 项目里已经有一个全局的 `class_name Action`
	## （规则动作），同名会让 GDScript 在外部解析成那个类，
	## 报「Invalid operands Action and MapDef::Portal.Action」。
	enum Outcome {
		GOTO,          ## 直接切到 target_map 的 target_spawn
		TO_OVERWORLD,  ## 打开大地图。用于「出门」，不需要 target_map
		## 摆在那儿但去不了的地方。
		##
		## 大地图上现在有七个地点，只有委托店和集市做好了场景
		## （2026-09-24 策划定的）。剩下五个照样有标签和介绍、
		## 鼠标悬停也照旧提亮，就是点了不走 —— 点了会弹一句提示。
		##
		## **和「写漏了 `to`」必须分开**：那种是 GOTO 没有目标，
		## 校验会拦下来（`validate` 里那条）。要是拿「没有 target_map」
		## 当未开放，写漏的那种就再也报不出来了。
		NONE,
	}

	## 这个连接在本场景内的标识。大地图靠它记住鼠标正悬停在哪一块上。
	## 数据里不写也能用：会用 label，label 也没有就按序号生成。
	var id: StringName = &""
	var rect: Rect2 = Rect2()
	## 地图上显示的名字。房间里的门不用，留空即可。
	var label: String = ""
	## 鼠标悬停时显示的详细介绍。留空则不弹提示。
	var detail: String = ""
	## 地点贴图。大地图上用插画里那一块当按钮的最简办法。
	## 留空：有背景图时不画任何标记（插画上本来就画着房子），
	## 没有背景图时退回绿色占位块。
	var sprite: String = ""
	var outcome: Outcome = Outcome.GOTO
	var target_map: StringName = &""
	var target_spawn: StringName = &""
	## 满足这个条件才存在。为 null 表示一直在。
	## 例：某扇门要拿到钥匙之后才通。
	var condition: Condition = null

	## 大地图上：将来做「带引线的大信息面板」时，面板该摆在光点的哪一侧。
	##
	## **现在还没用上。** 眼下的做法是「一个小框套着名字、中心对齐地点」
	## （见 `MapView._add_place`），不带引线也不需要分左右。
	## 留着是因为策划那份互动示意里有带引线的面板，早晚要接；
	## 数据先写在那儿，接的时候不用回头补一遍。
	var side: String = "left"
	## 大地图上：这个名字要不要用**强调色**（粉）。
	##
	## 异界裂缝是特殊领域，策划的示意里它的标题是粉色的。
	var accent := false


	## 被拦着的门：`flags` 里这个键为真时，这扇门走不出去，只会弹一句话。
	##
	## 用在「今天已经晚了，不让出门」这种**临时门禁**上 —— 和 `condition`
	## 不是一回事：`condition` 是让连接整个消失（连点都点不着），
	## 这个是**门还在、但推不开**，玩家得听到一句解释。
	var blocked_by: String = ""
	## 被拦着时弹的那句话。`blocked_by` 有值时才有意义。
	var blocked_text: String = ""
	## 按互动键时**演一段事件**，而不是传送。
	##
	## 给「推门进去之后还有一段过程动画」用（走进卧室、走向床、睡着……）：
	## 光靠 `to` 只会瞬移过去，接不上后面那段。
	## 写了这个 `to` 就不生效 —— 进门那一步交给事件去演，它自己 `goto`。
	var event_id: StringName = &""

	## 这个地点**还没开放**（摆在大地图上、有名字有介绍，但场景还没做）。
	##
	## 给界面用的便利读法 —— 界面上判「该不该用禁用态那张底」、
	## 名字该不该压暗，不该去记 `outcome` 的枚举名。
	func is_locked() -> bool:
		return outcome == Outcome.NONE


	func is_active(p_flags: WorldState) -> bool:
		if condition == null or p_flags == null:
			return true
		return condition.eval(p_flags)


## 一个可互动的动作：交谈、查看、购买……
## 单独一层，是为了支持「靠近一个物件弹出几个选项让玩家挑」这种做法。
class Interaction:
	extends RefCounted

	var id: StringName = &""
	var label: String = ""
	## 直接播一段对话
	var dialogue: Dialogue = Dialogue.new()
	## 或者触发一段剧情事件（填事件 id）。非空时优先走事件。
	var event_id: StringName = &""
	## 这段事件只演一次吗。填 true 之后，演过就不再触发 ——
	## 「有没有演过」记在世界状态里（`seen/<事件 id>`），**跟着存档走**，
	## 所以读档回到过去也不会把一次性的剧情再送一遍。
	var once := false
	## 触发时写什么状态，`变量名 -> 值`。写法同剧情节点的 `set`。
	##
	## 「捡起易拉罐，里面竟然有把钥匙」这种事不该为了写状态专门建一段剧情，
	## 所以交互自己就能写。物品的键是 `item/<id>`，值就是数量。
	var effects: Dictionary = {}


## 场景里的 NPC 或可调查的物件。玩家走到附近按交互键触发。
class VisualPart:
	extends RefCounted

	var id: StringName = &""
	var sprite := ""
	var rect := Rect2()
	var layer := "auto"
	var sort_offset := 0.0


class Actor:
	extends RefCounted
	var raw: Dictionary = {}

	var id: StringName = &""
	## 物件本体：贴图按它摆，交互也默认按它算。
	var rect: Rect2 = Rect2()
	## 「够得着」的范围。默认就是 `rect`。
	##
	## 有的家具前面还挡着另一件家具 —— 书桌前面有椅子，玩家只能站在椅子
	## 外面。这时按本体算距离就永远差一截，手怎么伸都点不到。把这一格
	## 往前铺到玩家站得住的地方，桌子才点得着。
	## **只影响「够不够得着」，不影响挡不挡路**（那只看 `walls`）。
	var reach: Rect2 = Rect2()
	var collisions: Array[Rect2] = []
	var has_local_collision := false
	var sort_collider := 0
	var sort_offset := 0.0
	## 显示用名字。没有贴图时直接画在方块上。
	var label: String = ""
	## 物件贴图。**从地图插画里切出来的那一块**（`art/props/`），
	## 按 `rect` 的大小贴上，于是「画好的桌子」和「要交互的桌子」是同一个东西。
	## 留空则退回占位色块 + 名字。
	var sprite: String = ""
	## 同一主贴图位置的命名状态贴图；运行时可由 MapView 按 Actor ID 切换。
	var sprite_variants: Dictionary = {}
	## 默认及当前运行时使用的变体；空串表示使用 sprite。
	var sprite_variant: String = ""
	## 空串继承旧over/cover或各视觉部件设置；显式值覆盖此物件全部视觉部件。
	var draw_layer: String = ""
	## 同一实际绘制层内越大越靠前；相同值仍采用地图原来的物件次序。
	var draw_order: int = 0
	## 非空时替代旧 sprite。每段 rect 相对旋转后 actor.rect 左上角，几何已由编辑器烘焙。
	var visual_parts: Array[VisualPart] = []
	## 源纹理先沿局部轴翻转，再顺时针旋转 quarter_turns 个 90 度；不再变换碰撞或交互。
	var quarter_turns := 0
	var flip_h := false
	var flip_v := false
	var _visual_problems: Array[String] = []
	## 整块挡路吗。**默认不挡。**
	##
	## 挡不挡由地图的 `walls` 说了算 —— 那是策划在示意图上涂绿的地方，
	## 一张图一个准。物件自己再挡一遍，只会把框画得比绿块大，
	## 于是「该能踩进去的猫窝踩不进去」这种毛病就来了。
	##
	## 只在两处需要它：
	##   - 人（没有贴图的东西）：不挡的话玩家会从他身体里穿过去，所以挡脚下一条；
	##   - 极少数要单独挡、而示意图上没涂的家具。
	var solid: bool = false
	## 这件家具**挡不挡人**（2.5D 的前后关系）。
	##
	## 为真时按「脚站在哪儿」排序：角色脚落在它 `rect` 的下边界**以北**
	## （人在家具后面）→ 家具画在角色之上，人的下半身被压住；
	## 以南（人在家具前面）→ 角色画在家具之上。
	## 基准取 `rect` 的下边界，那是家具「落在地上」的那条边。
	##
	## 只给真会挡到人的家具开（书桌那种摆在房间当中的）。墙边那一排货架
	## **别开** —— 开了之后人在它们旁边走过也会被盖一下，反而看不清自己。
	var cover: bool = false
	## 遮挡基线的**手动覆盖**（一个 Y 值）。不写就是 `-1`，表示自动取 `rect`
	## 的下边界 —— 那是物件「落在地上」的那条边。
	##
	## 什么时候才写：贴图底下自带一圈阴影、或者切件时多切了几像素，
	## 「贴图底边」就不再等于落地的位置了。这时用地图编辑器
	## （`addons/if_map_editor`）把那条黄线拉到该在的地方，它写回来的就是这个。
	##
	## ⚠️ **写了它，`rect` 的底边就不再管遮挡了** —— 两个真相。
	## 只在该手调的那几件上写，别养成每件都写的习惯。
	var cover_y: float = -1.0
	## **永远画在角色之上。**
	##
	## 和 `cover` 分开是因为判据不同：`cover` 是「按站位分前后」，
	## 这个是「不管站哪儿都盖住人」。给**前景里的独立小物件**用 ——
	## 门口那盏提灯就是：玩家会从它后面绕过去，希望灯始终挡在前面。
	##
	## 别拿它当`cover` 的替代：开了之后人在它旁边走过也会被盖一下，
	## 而 `over` 是连盖一下的机会都不给，全程盖着。
	var over: bool = false
	## 这是**一个人**（NPC），不是家具。
	##
	## 为真时在脚下建一小条实体，玩家不能从他身体里穿过去。
	## 家具**不**走这条 —— 挡不挡路由 `walls` 说了算（策划涂绿的地方），
	## 家具自己再挡一遍只会把框画得比绿块大。
	##
	## 早先这里没有这个字段，靠「有没有贴图」猜是不是人。后来家具也不再
	## 从插画上切贴图了（背景上本来就画着，见开发纪要 36），那个判据就废了 ——
	## 于是所有家具都被当成「人」，脚下各冒出一条实体，玩家走不到跟前。
	var person: bool = false
	## 纯装饰物件：只参与渲染（含 `cover` 的层级），**不参与交互**。
	##
	## 这个字段存在是因为解析器有个兜底（见 `_actor_from` 的写法三）——
	## 没写 `line` / `event` 的物件也会自动得到一个「交谈」动作，内容是空的。
	## 集市那批盖满场地的楼房就栽在这上面：玩家落在它的 `rect` 里、
	## `rect_distance` 算出来是 0，每次按交互都被它截胡，人反而说不上话。
	## 标了 `decor` 就不进这个兜底，`actor_near` 也会跳过它。
	var decor: bool = false
	## 走进这件物件的 `reach` 时，**自动弹出它的动作菜单**（不用按交互键）。
	##
	## 为死巷铁门做的：人类定的交互方式是「走到蓝色框，右上角浮出
	## 『推开铁门』，点一下进门」。菜单复用 `choice_menu`（本来就是
	## 右上角的独立面板），每帧在 `_check_auto_menu()` 里查。
	var auto_menu: bool = false
	## 能做的动作。只有一个时直接执行，多个时先弹菜单让玩家挑。
	var interactions: Array[Interaction] = []
	## 满足这个条件才出现在场景里。为 null 表示一直在。
	## 这是概念图里「NPC 头顶的 IF 气泡」的基础。
	var condition: Condition = null


	func collision_rects() -> Array[Rect2]:
		var result: Array[Rect2] = []
		if has_local_collision:
			for shape: Rect2 in collisions:
				result.append(Rect2(rect.position + shape.position, shape.size))
		elif solid:
			result.append(rect)
		elif person:
			result.append(Rect2(rect.position + Vector2(2.0, rect.size.y - 8.0),
				Vector2(maxf(rect.size.x - 4.0, 1.0), 8.0)))
		return result


	func auto_cover_y() -> float:
		if has_local_collision and sort_collider >= 0 and sort_collider < collisions.size():
			return rect.position.y + collisions[sort_collider].position.y
		return rect.end.y


	func effective_cover_y() -> float:
		return cover_y if cover_y >= 0.0 else auto_cover_y() + sort_offset


	## 返回各部件的世界 AABB，按 visual_parts 原序；无部件时返回单个旧 rect。
	func world_visual_rects() -> Array[Rect2]:
		var result: Array[Rect2] = []
		if visual_parts.is_empty():
			result.append(rect)
		else:
			for part: VisualPart in visual_parts:
				result.append(Rect2(rect.position + part.rect.position, part.rect.size))
		return result


	## 与 world_visual_rects 同序的贴图路径；无部件时返回单个旧 sprite，允许空路径。
	func visual_sprites() -> PackedStringArray:
		var result := PackedStringArray()
		if visual_parts.is_empty():
			result.append(sprite_for_variant(sprite_variant))
		else:
			for part: VisualPart in visual_parts:
				result.append(part.sprite)
		return result


	## 返回指定变体的贴图；空变体使用旧 sprite 字段。
	func sprite_for_variant(variant_id: String = "") -> String:
		if variant_id.is_empty():
			return sprite
		return str(sprite_variants.get(variant_id, ""))


	## 与世界矩形同序的 back/auto/front；旧物件由 over、cover 映射成同一协议。
	func visual_layers() -> PackedStringArray:
		var result := PackedStringArray()
		if not draw_layer.is_empty():
			for index: int in maxi(visual_parts.size(), 1):
				result.append(draw_layer)
			return result
		if visual_parts.is_empty():
			result.append("front" if over else ("auto" if cover else "back"))
		else:
			for part: VisualPart in visual_parts:
				result.append(part.layer)
		return result


	## 与世界矩形同序的有效基线加部件偏移；只有 auto 层使用这些值。
	func visual_cover_ys() -> PackedFloat64Array:
		var result := PackedFloat64Array()
		if visual_parts.is_empty():
			result.append(effective_cover_y())
		else:
			for part: VisualPart in visual_parts:
				result.append(effective_cover_y() + part.sort_offset)
		return result


	## 将第 index 段的源纹理像素坐标映射到世界矩形；纹理原点必须在左上角。
	func visual_texture_transform(index: int, texture_size: Vector2) -> Transform2D:
		var rectangles := world_visual_rects()
		if index < 0 or index >= rectangles.size():
			return Transform2D.IDENTITY
		return MapDef.texture_transform(rectangles[index], texture_size,
			quarter_turns, flip_h, flip_v)


	func is_active(p_flags: WorldState) -> bool:
		if condition == null or p_flags == null:
			return true
		return condition.eval(p_flags)


var id: StringName = &""
var kind: Kind = Kind.ROOM
var size: Vector2i = Vector2i(320, 180)
## 背景图路径。大地图是一整张插画，室内将来也可能直接贴图。
## 留空就用底色铺满。
var background: String = ""
## 叠在角色**之上**的一层图（前景遮挡）。空 = 没有。
##
## 一张和背景同尺寸的**扣图**：中间是空的，只留该盖住角色的部分
## （画面下方那道围墙、四周的建筑）。`map_view` 把它铺在最上面，
## 角色走到那一带就被压住 —— **不需要任何碰撞箱配合**，
## 图上画着的那一块本来就是「角色该被挡住」的地方。
##
## 路径写法和 `background` 一样。
var overlay: String = ""
## 场景的名字。地图占位阶段画在哪张糟糕的手绘稿上就看它 ——
## 还没有背景图时，这一行字铺在底色中央，玩家知道自己在哪。
var name: String = ""
## 这个场景的背景音乐。**留空就是没有音乐**（卧室白天黑夜都没有，是策划定的）。
##
## 写的是资源路径，不是曲名 —— 跟 `background` 一个道理：数据里放路径最直白，
## 也方便 `check_data.py` 查文件在不在。
##
## **切场景时同一首不重放**（见 `main._play_map_music`）：从委托屋走到集市
## 再走回来，不该每次都从头响。
var music: String = ""

## 这个场景里走路的脚步音效。**留空就是没有**（户外、石板地不响）。
##
## 和 `music` 一样是可选字段：写在地图 json 顶层，`res://` 路径。
## 现在只有木地板的三个场景（委托屋、卧室白天/夜里）填了它 ——
## 集市是户外的石板地，踩上去不该是木板声。
##
## 谁在走都响：主角，以及演出里的临时角色（老人上门那段）。
var footstep: String = ""

## 这里算不算「屋子里面」。**只影响进门音效**，默认是室内。
##
## 为什么不复用 `kind`：`kind` 管的是「怎么走」（`OVERWORLD` 是点选传送、
## `ROOM` 是走动），而集市和委托屋都是 `ROOM` —— 走动方式一样，
## 但一个是露天市集、一个是屋子，**只有后者进门该有门轴声**。
## 给集市单独标一个 `kind` 会把 `main.gd` 里「在房间里」那套判断一起带偏，
## 表现是人在集市里走不动。
##
## 2026-09-24 策划定的：露天场景不该有进门音效。
var indoor := true
## 这张地图里玩家的缩放。默认 1（45 像素高的老比例）。
##
## 学校那套美术密度比集市细得多（门卫室的门才 23 像素高），
## 45 像素的主角站进去比门还高一头半 —— 按图给个缩放，
## 进图时 `main.enter_map` 挂到玩家节点上，整只（含碰撞）一起缩。
var player_scale: float = 1.0

## 挡路的矩形。可行走区域 = size 减去这些墙。
var walls: Array[Rect2] = []
var portals: Array[Portal] = []
## 出生点。别的场景传过来时落在哪，键是出生点名字。
var spawns: Dictionary = {}
## 场景里的 NPC 与可调查物件
var actors: Array[Actor] = []
var triggers: Array = []
var _trigger_problems: Array[String] = []


## 从字典构造。字段缺失时用默认值，不做严格校验（严格校验交给 validate）。
static func from_dictionary(data: Dictionary) -> MapDef:
	var def := MapDef.new()
	def.id = StringName(str(data.get("id", "")))
	def.kind = _to_kind(data.get("kind"))
	def.size = _to_vector2i(data.get("size"), Vector2i(320, 180))
	def.background = str(data.get("background", ""))
	def.overlay = str(data.get("overlay", ""))
	def.name = str(data.get("name", ""))
	def.music = str(data.get("music", ""))
	def.footstep = str(data.get("footstep", ""))
	# 不写就是室内。**只有露天场景需要显式写 false**（集市）。
	def.indoor = bool(data.get("indoor", true))
	def.player_scale = float(data.get("player_scale", 1.0))

	var raw_walls: Variant = data.get("walls", [])
	if raw_walls is Array:
		for raw: Variant in raw_walls:
			def.walls.append(_to_rect(raw))

	var raw_portals: Variant = data.get("portals", [])
	if raw_portals is Array:
		var index := 0
		for raw: Variant in raw_portals:
			var portal := _portal_from(raw)
			# 没写 id 就补一个，保证每个连接都有稳定标识
			if portal.id == &"":
				portal.id = StringName(portal.label) if portal.label != "" \
					else StringName("portal_%d" % index)
			def.portals.append(portal)
			index += 1

	var raw_spawns: Variant = data.get("spawns", {})
	if raw_spawns is Dictionary:
		for key: Variant in raw_spawns:
			def.spawns[StringName(str(key))] = _to_vector2(raw_spawns[key], Vector2.ZERO)

	var raw_actors: Variant = data.get("actors", [])
	if raw_actors is Array:
		for raw: Variant in raw_actors:
			def.actors.append(_actor_from(raw))
	var raw_triggers: Variant = data.get("triggers", [])
	if raw_triggers is Array:
		for raw: Variant in raw_triggers:
			if raw is Dictionary:
				def.triggers.append(Trigger.from_dictionary(raw))
			else:
				def._trigger_problems.append("triggers 项必须是字典")
	else:
		def._trigger_problems.append("triggers 必须是数组")

	return def


## 取出生点。找不到就退回场景中心，保证角色不会落在场景外。
func spawn_point(spawn_name: StringName) -> Vector2:
	if spawns.has(spawn_name):
		return spawns[spawn_name]
	return Vector2(size) * 0.5


## 找出覆盖某个坐标的连接。条件不满足的连接视同不存在。
func portal_at(point: Vector2, flags: WorldState = null) -> Portal:
	for portal: Portal in portals:
		if not portal.is_active(flags):
			continue
		if portal.rect.has_point(point):
			return portal
	return null


## 找出离某点最近、且在 max_distance 之内的角色。没有就返回 null。
##
## 用于「按下交互键该跟谁说话」。范围内有多个时取最近的，
## 否则两个 NPC 站得近一点，说话对象就变得看运气。
## 条件不满足的角色视同不存在。
## 半径内最近的、**在朝向面前**的人或东西。
##
## `facing` 传零向量表示不挑方向（测试、以及「附近有什么」这类查询用）。
## 传了方向就只认面前那一侧：背后和身侧的东西理都不理 ——
## 不然站在书架前面朝门口按交互，会跟背后那本书说起话来。
func actor_near(point: Vector2, max_distance: float, flags: WorldState = null,
		facing: Vector2 = Vector2.ZERO) -> Actor:
	var best: Actor = null
	var best_distance := max_distance
	for actor: Actor in actors:
		if not actor.is_active(flags):
			continue
		# 没有动作的物件（纯装饰）不算交互对象 —— 它们贴图框大，
		# 玩家常整个落在框里，`rect_distance` 算出来是 0，会把附近
		# 真正能说话的人截胡（2026-09-26 集市：玩家对着 A 按交互，
		# 被脚下的街边楼房抢走，A 永远说不上话）。
		if actor.decor:
			continue
		if facing != Vector2.ZERO and not faces_target(point, actor.reach, facing):
			continue
		var distance := rect_distance(actor.reach, point)
		if distance < best_distance:
			best_distance = distance
			best = actor
	return best


## 目标在不在朝向这一侧。
##
## 拿「玩家到矩形最近点」的方向和朝向比：夹角在 FACING_DOT 允许的范围内就算。
## 已经站在矩形里（脚底就踩着它）时方向无从谈起，一律算数。
static func faces_target(point: Vector2, rect: Rect2, facing: Vector2) -> bool:
	var cx := clampf(point.x, rect.position.x, rect.position.x + rect.size.x)
	var cy := clampf(point.y, rect.position.y, rect.position.y + rect.size.y)
	var to_target := Vector2(cx, cy) - point
	if to_target.length() < 1.0:
		return true
	return to_target.normalized().dot(facing.normalized()) > FACING_DOT


## 点到矩形的最近距离。点在矩形里就是 0。
##
## 用「到矩形」而不是「到中心」：物件贴图是按 rect 摆的，玩家贴到桌子边
## 就该能交互。按中心算的话，一张宽 100 的柜台得走到正中间才算够得着，
## 站在桌角按空格会没反应。
static func rect_distance(rect: Rect2, point: Vector2) -> float:
	var cx := clampf(point.x, rect.position.x, rect.position.x + rect.size.x)
	var cy := clampf(point.y, rect.position.y, rect.position.y + rect.size.y)
	return Vector2(cx, cy).distance_to(point)


## 当前存在的角色。**渲染和交互都要用它**，
## 两边用同一份判断，才不会有「看得见但点不到」或者「看不见却挡路」。
func active_actors(flags: WorldState = null) -> Array[Actor]:
	var out: Array[Actor] = []
	for actor: Actor in actors:
		if actor.is_active(flags):
			out.append(actor)
	return out


## 当前存在的连接。
func active_portals(flags: WorldState = null) -> Array[Portal]:
	var out: Array[Portal] = []
	for portal: Portal in portals:
		if portal.is_active(flags):
			out.append(portal)
	return out


## 校验。返回问题列表，空数组表示没问题。
##
## 在地图加载时调用一次，把错误挡在启动阶段。
## 不校验的话，一个写歪的 JSON 会变成「游戏能跑但角色卡在墙里」
## 这种要玩到那一幕才发现的问题。
func validate() -> Array[String]:
	var problems: Array[String] = []

	if id == &"":
		problems.append("场景缺少 id")
	if size.x <= 0 or size.y <= 0:
		problems.append("场景 %s 的 size 不合法：%s" % [id, size])
	if not is_finite(player_scale) or player_scale <= 0.0:
		problems.append("场景 %s 的 player_scale 必须是大于 0 的有限数值" % id)

	for i: int in walls.size():
		var wall: Rect2 = walls[i]
		if wall.size.x <= 0.0 or wall.size.y <= 0.0:
			problems.append("场景 %s 的第 %d 面墙尺寸为 0" % [id, i])

	for i: int in portals.size():
		var portal: Portal = portals[i]
		if portal.rect.size.x <= 0.0 or portal.rect.size.y <= 0.0:
			problems.append("场景 %s 的第 %d 个连接尺寸为 0" % [id, i])
		# 打开大地图的连接不需要目标场景；**交给事件去演的也不需要**
		# （`event` 那个字段：进门之后那段过程动画由它自己 `goto`）；
		# 剩下「直接切场景」的必须有，没有就是写漏了。
		if portal.outcome == Portal.Outcome.GOTO and portal.target_map == &"" \
				and portal.event_id == &"":
			problems.append("场景 %s 的第 %d 个连接是 GOTO，却没有 target_map" % [id, i])

	# 出生点必须落在场景内，否则角色一进场就在墙里或者出界
	for key: Variant in spawns:
		var point: Vector2 = spawns[key]
		if point.x < 0.0 or point.y < 0.0 or point.x > float(size.x) or point.y > float(size.y):
			problems.append("场景 %s 的出生点 %s 落在场景外：%s" % [id, key, point])

	for i: int in actors.size():
		var actor: Actor = actors[i]
		if actor.id == &"":
			problems.append("场景 %s 的第 %d 个角色没有 id" % [id, i])
		if actor.rect.size.x <= 0.0 or actor.rect.size.y <= 0.0:
			problems.append("场景 %s 的角色 %s 尺寸为 0" % [id, actor.id])
		if not actor.rect.position.is_finite() or not actor.rect.size.is_finite() \
				or not actor.rect.end.is_finite() or not actor.reach.position.is_finite() \
				or not actor.reach.size.is_finite() or not actor.reach.end.is_finite() \
				or not is_finite(actor.sort_offset) or not is_finite(actor.cover_y):
			problems.append("场景 %s 的角色 %s 几何或遮挡基线必须是有限数值" % [id, actor.id])
		for shape: Rect2 in actor.collisions:
			if not _valid_visual_rect(shape):
				problems.append("场景 %s 的角色 %s 局部碰撞尺寸无效" % [id, actor.id])
		if actor.has_local_collision and actor.visual_layers().has("auto") \
				and (actor.sort_collider < 0 or actor.sort_collider >= actor.collisions.size()):
			problems.append("场景 %s 的角色 %s 没有有效排序参考碰撞箱" % [id, actor.id])
		for problem: String in actor._visual_problems:
			problems.append("场景 %s 的角色 %s：%s" % [id, actor.id, problem])
		if actor.quarter_turns < 0 or actor.quarter_turns > 3:
			problems.append("角色 %s 的 quarter_turns 必须是 0..3 的整数" % actor.id)
		if actor.draw_layer not in DRAW_LAYERS:
			problems.append("角色 %s 的 draw_layer 必须是空串/back/auto/front/above_overlay" % actor.id)
		if actor.sprite_variant != "" and not actor.sprite_variants.has(actor.sprite_variant):
			problems.append("角色 %s 的默认贴图变体不存在：%s" % [actor.id, actor.sprite_variant])
		if not actor.sprite_variants.is_empty() and not actor.visual_parts.is_empty():
			problems.append("角色 %s 不能同时使用贴图变体和 visual_parts" % actor.id)
		for variant_id: Variant in actor.sprite_variants:
			var variant_path: Variant = actor.sprite_variants[variant_id]
			if not variant_id is String or str(variant_id).strip_edges().is_empty() \
					or not variant_path is String or str(variant_path).strip_edges().is_empty():
				problems.append("角色 %s 的贴图变体必须使用非空名称和路径" % actor.id)
		var part_ids := {}
		for part: VisualPart in actor.visual_parts:
			if part.id != &"" and part_ids.has(part.id):
				problems.append("角色 %s 的 visual_parts id 重复：%s" % [actor.id, part.id])
			part_ids[part.id] = true
			if part.sprite.is_empty() or not _valid_visual_rect(part.rect) \
					or not _valid_visual_rect(Rect2(actor.rect.position + part.rect.position, part.rect.size)) \
					or part.layer not in ["back", "auto", "front"] \
					or not is_finite(part.sort_offset) \
					or not is_finite(actor.effective_cover_y() + part.sort_offset):
				problems.append("角色 %s 的 visual_parts 项无效：%s" % [actor.id, part.id])

	problems.append_array(_trigger_problems)
	var trigger_ids := {}
	for trigger: Variant in triggers:
		for problem: String in trigger.validate():
			problems.append("场景 %s 的触发区：%s" % [id, problem])
		if trigger_ids.has(trigger.id):
			problems.append("场景 %s 的触发区 id 重复：%s" % [id, trigger.id])
		trigger_ids[trigger.id] = true

	return problems


## 供日志与调试使用。
func to_text() -> String:
	return "MapDef(%s) %sx%s，墙 %d 面，传送点 %d 个，出生点 %d 个" % [
		id, size.x, size.y, walls.size(), portals.size(), spawns.size(),
	]


# ---------------------------------------------------------------- 转换工具

## 返回副本，按同层绘制顺序升序排列；同值保留源数组次序，不能依赖非稳定sort。
static func ordered_actors(source: Array[Actor]) -> Array[Actor]:
	var indices: Array[int] = []
	for index: int in source.size():
		indices.append(index)
	indices.sort_custom(func(first: int, second: int) -> bool:
		var before := source[first].draw_order
		var after := source[second].draw_order
		return first < second if before == after else before < after)
	var result: Array[Actor] = []
	for index: int in indices:
		result.append(source[index])
	return result

static func _to_vector2i(raw: Variant, fallback: Vector2i) -> Vector2i:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return fallback


static func _to_vector2(raw: Variant, fallback: Vector2) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return fallback


## 接受 [x, y, w, h] 形式的矩形。
static func _to_rect(raw: Variant) -> Rect2:
	if raw is Array and (raw as Array).size() >= 4:
		return Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	return Rect2()


## 将左上角为零的源纹理映射到已烘焙的世界 AABB。先局部翻转，再绕矩形中心顺时针旋转。
## 返回可用于 Sprite2D(centered=false) 或 canvas 绘制的完整变换；无效尺寸返回单位矩阵。
static func texture_transform(rect: Rect2, texture_size: Vector2,
		quarter_turns: int = 0, flip_h: bool = false, flip_v: bool = false) -> Transform2D:
	if not _valid_visual_rect(rect) or not texture_size.is_finite() \
			or texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Transform2D.IDENTITY
	var turns := posmod(quarter_turns, 4)
	var draw_size := rect.size if turns % 2 == 0 else Vector2(rect.size.y, rect.size.x)
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	var axis_x := directions[turns] * (draw_size.x / texture_size.x) * (-1.0 if flip_h else 1.0)
	var axis_y := directions[(turns + 1) % 4] * (draw_size.y / texture_size.y) * (-1.0 if flip_v else 1.0)
	return Transform2D(axis_x, axis_y,
		rect.get_center() - axis_x * texture_size.x * 0.5 - axis_y * texture_size.y * 0.5)


static func _finite_number(raw: Variant) -> bool:
	return (raw is int or raw is float) and is_finite(float(raw))


static func _valid_visual_rect(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.end.is_finite() \
		and rect.size.x > 0.0 and rect.size.y > 0.0


static func _visuals_from(actor: Actor, raw: Dictionary) -> void:
	var turns: Variant = raw.get("quarter_turns", 0)
	if _finite_number(turns) and float(turns) == floorf(float(turns)) \
			and float(turns) >= 0.0 and float(turns) <= 3.0:
		actor.quarter_turns = int(turns)
	else:
		actor._visual_problems.append("quarter_turns 必须是 0..3 的整数")
	for field: String in ["flip_h", "flip_v"]:
		if raw.get(field, false) is bool:
			actor.set(field, raw.get(field, false))
		else:
			actor._visual_problems.append("%s 必须是布尔值" % field)
	var parts: Variant = raw.get("visual_parts", [])
	if not (parts is Array):
		actor._visual_problems.append("visual_parts 必须是数组")
		actor.visual_parts.append(VisualPart.new())
		return
	for entry: Variant in parts:
		var part := VisualPart.new()
		actor.visual_parts.append(part)
		if not (entry is Dictionary):
			actor._visual_problems.append("visual_parts 项必须是字典")
			continue
		if entry.get("id", "") is String:
			part.id = StringName(entry.get("id", ""))
		else:
			actor._visual_problems.append("visual_parts.id 必须是字符串")
		if entry.get("sprite") is String:
			part.sprite = entry["sprite"]
		if entry.get("layer") is String:
			part.layer = entry["layer"]
		else:
			actor._visual_problems.append("visual_parts.layer 必须是 back/auto/front")
		var bounds: Variant = entry.get("rect")
		var valid_bounds: bool = bounds is Array and bounds.size() == 4
		if valid_bounds:
			for value: Variant in bounds:
				if not _finite_number(value):
					valid_bounds = false
		if valid_bounds:
			part.rect = _to_rect(bounds)
		else:
			actor._visual_problems.append("visual_parts.rect 必须是四个有限数值")
		if _finite_number(entry.get("sort_offset", 0.0)):
			part.sort_offset = float(entry.get("sort_offset", 0.0))
		else:
			actor._visual_problems.append("visual_parts.sort_offset 必须是有限数值")


static func _portal_from(raw: Variant) -> Portal:
	var portal := Portal.new()
	if raw is Dictionary:
		portal.id = StringName(str(raw.get("id", "")))
		portal.rect = _to_rect(raw.get("rect"))
		portal.label = str(raw.get("label", ""))
		portal.detail = str(raw.get("detail", ""))
		portal.sprite = str(raw.get("sprite", ""))
		portal.side = str(raw.get("side", "left"))
		portal.blocked_by = str(raw.get("blocked_by", ""))
		portal.blocked_text = str(raw.get("blocked_text", ""))
		portal.event_id = StringName(str(raw.get("event", "")))
		portal.accent = bool(raw.get("accent", false))
		portal.condition = Condition.from_dictionary(raw.get("if"))
		var action := str(raw.get("action", "")).to_lower()
		portal.target_map = StringName(str(raw.get("to", "")))
		portal.target_spawn = StringName(str(raw.get("spawn", "")))
		if action == "overworld":
			portal.outcome = Portal.Outcome.TO_OVERWORLD
		elif bool(raw.get("locked", false)):
			# 写了 `locked`：**摆在那儿但还没开放的地点**。
			# 显式写一个标记，而不是拿「没有 `to`」当未开放 ——
			# 那样就和「写漏了 `to`」分不开了，而后者是校验要抓的错
			# （`validate` 里那条「GOTO 却没有 target_map」）。
			portal.outcome = Portal.Outcome.NONE
	return portal


static func _to_kind(raw: Variant) -> Kind:
	if str(raw).to_lower() == "overworld":
		return Kind.OVERWORLD
	return Kind.ROOM


static func _actor_from(raw: Variant) -> Actor:
	var actor := Actor.new()
	if not (raw is Dictionary):
		return actor
	actor.raw = (raw as Dictionary).duplicate(true)

	actor.id = StringName(str(raw.get("id", "")))
	actor.rect = _to_rect(raw.get("rect"))
	actor.reach = _to_rect(raw.get("reach")) if raw.has("reach") else actor.rect
	if raw.has("reach_local"):
		var local_reach := _to_rect(raw["reach_local"])
		actor.reach = Rect2(actor.rect.position + local_reach.position, local_reach.size)
	actor.has_local_collision = raw.has("collision")
	var local_shapes: Variant = raw.get("collision", [])
	if local_shapes is Array:
		for shape: Variant in local_shapes:
			actor.collisions.append(_to_rect(shape))
	actor.sort_collider = int(raw.get("sort_collider", 0))
	actor.sort_offset = float(raw.get("sort_offset", 0.0))
	actor.label = str(raw.get("label", ""))
	actor.sprite = str(raw.get("sprite", ""))
	var raw_variants: Variant = raw.get("sprite_variants", {})
	if raw_variants is Dictionary:
		actor.sprite_variants = raw_variants.duplicate(true)
	else:
		actor._visual_problems.append("sprite_variants 必须是对象")
	actor.sprite_variant = str(raw.get("sprite_variant", ""))
	var raw_layer: Variant = raw.get("draw_layer", "")
	if raw_layer is String:
		actor.draw_layer = raw_layer
	else:
		actor._visual_problems.append("draw_layer 必须是字符串")
	var raw_order: Variant = raw.get("draw_order", 0)
	if raw_order is int:
		actor.draw_order = raw_order
	elif _finite_number(raw_order) and float(raw_order) == floorf(float(raw_order)) \
			and float(raw_order) >= -9223372036854775808.0 and float(raw_order) < 9223372036854775808.0:
		actor.draw_order = int(raw_order)
	else:
		actor._visual_problems.append("draw_order 必须是有限整数")
	_visuals_from(actor, raw)
	actor.solid = bool(raw.get("solid", false))
	actor.cover = bool(raw.get("cover", false))
	actor.cover_y = float(raw.get("cover_y", -1.0))
	actor.over = bool(raw.get("over", false))
	actor.person = bool(raw.get("person", false))
	actor.decor = bool(raw.get("decor", false))
	actor.auto_menu = bool(raw.get("auto_menu", false))
	actor.condition = Condition.from_dictionary(raw.get("if"))

	# 纯装饰物件：只画不交互。**直接返回**，别落到下面那三个兜底 ——
	# 兜底会塞给它一个空对话，场面上就成了「对着楼按交互弹出空气」。
	if actor.decor:
		return actor

	# 写法一：`actions` 是一组动作，靠近后弹菜单让玩家挑
	var raw_actions: Variant = raw.get("actions", [])
	if raw_actions is Array and not (raw_actions as Array).is_empty():
		for item: Variant in raw_actions:
			actor.interactions.append(_interaction_from(item))
		return actor

	# 写法二：只写 `event`，就当成触发那段剧情的唯一动作
	if raw.has("event"):
		var story := Interaction.new()
		story.id = &"talk"
		story.label = actor.label if actor.label != "" else "交谈"
		story.event_id = StringName(str(raw.get("event", "")))
		actor.interactions.append(story)
		return actor

	# 写法三：只写 `talk`（数组）或 `line`（字符串），就当成唯一的动作
	var talk := Dialogue.new()
	if raw.has("talk"):
		talk = Dialogue.from_array(raw.get("talk"))
	else:
		talk = Dialogue.single(actor.label, str(raw.get("line", "")))

	var only := Interaction.new()
	only.id = &"talk"
	only.label = actor.label if actor.label != "" else "交谈"
	only.dialogue = talk
	actor.interactions.append(only)
	return actor


static func _interaction_from(raw: Variant) -> Interaction:
	var inter := Interaction.new()
	if not (raw is Dictionary):
		return inter
	inter.id = StringName(str(raw.get("id", "")))
	inter.label = str(raw.get("label", inter.id))
	inter.event_id = StringName(str(raw.get("event", "")))
	inter.once = bool(raw.get("once", false))

	var raw_set: Variant = raw.get("set", {})
	if raw_set is Dictionary:
		for key: Variant in raw_set:
			inter.effects[StringName(str(key))] = raw_set[key]

	if raw.has("talk"):
		inter.dialogue = Dialogue.from_array(raw.get("talk"))
	elif inter.event_id == &"":
		inter.dialogue = Dialogue.single("", str(raw.get("line", "")))
	return inter
