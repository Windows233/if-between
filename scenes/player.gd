## 玩家角色。在室内场景里用 WASD 走动，撞到墙停下。
##
## 输入目前直接读物理键。将来要做按键重绑定，就换成 InputMap 的动作名，
## 改动只会落在这一个文件里 —— `MOVE_KEYS` 是全项目唯一的按键映射表。
##
## 这个类只管「怎么动」，不管长什么样。外观由外部挂子节点，占位阶段是色块，
## 美术到位后换成 AnimatedSprite2D，这里一行都不用改。
class_name Player
extends CharacterBody2D

const SPEED := 96.0
const CHASE_BURST_DISTANCE := 110.0
const CHASE_BURST_FRAMES := 4
const CHASE_BURST_DURATION := 0.52
const CHASE_BURST_FPS := float(CHASE_BURST_FRAMES) / CHASE_BURST_DURATION

var chase_input_locked := false
var _chase_burst_velocity := Vector2.ZERO
var _chase_burst_remaining := 0.0
var _chase_burst_distance := 0.0
var _chase_burst_time_left := 0.0
var _chase_burst_elapsed := 0.0

## 素材没到、或者缺帧时退回的占位色块，脚底在原点
const BODY_COLOR := Color("#e8b04b")
const BODY_SIZE := Vector2(10.0, 22.0)
## 碰撞体只占脚下一小块。碰撞和视觉一样高的话，
## 撞墙会变成「身子插进去半截」，玩起来像撞在看不见的东西上。
##
## 宽取角色视觉宽度的一半左右（角色宽 ≈ `DISPLAY_HEIGHT` × 0.72）。
## 2026-09-23 地图和角色一起放大之后，这里也跟着从 10 放到 16。
const FOOT_SIZE := Vector2(16.0, 16.0)
const FOOT_OFFSET := -8.0

## 帧图放这儿：`art/player/<方向><序号>.png`，由 `tools/make_player_frames.py` 生成。
const FRAME_DIR := "res://art/player"
## 每秒几帧。步子迈得比这快就会像在滑冰。
const WALK_FPS := 8.0

## 角色的统一基准高度（320×180 逻辑视口像素，包含帧图透明留边）。
## 地图中仍乘 player_scale，相机取其倒数；同一帧在任何可行走场景均显示 45。
##
## 尺子一直是委托屋左上角那扇木门：**人不能高过门框**。
## 2026-09-23 地图换成高清版（图 ÷12），门框在游戏坐标里高 50.4，所以取 45。
##
## 帧图是**高分辨率**的（见 `make_player_frames.py` 的 `FRAME_HEIGHT`），
## 真正的缩小放在这里做 —— 用节点的 `scale`。
##
## 提前把帧图压到这个高度、再由画面放大好几倍，就是一团糊。别那么干。
const DISPLAY_HEIGHT := 45.0

## 头的正中央离脚底有多远，按整个人的高度算比例。
##
## 剧情里有些位置**是按头定的**，不是按脚 —— 结尾躺床上那一幕就是：
## 「头的正中央落在枕头正中」。角色的原点在脚底，中间差着这一个偏移。
## 素材是 Q 版，头占上面大约四成，所以头心在离脚底 76% 的地方。
## 换一套小人素材时改这一个数。
const HEAD_RATIO := 0.76

## 每个动画播哪几帧，**序号来自策划给的那套编号**：
##   背面 1、3、2 循环，3 站着；侧面 1、2、3、4 循环，1 站着；
##   正面 1、2、3 循环，4 站着。
## 站着也是动画，只是只有一帧 —— 这样「停下」不用另一套逻辑。
const ANIMATIONS: Dictionary = {
	&"walk_up": [1, 3, 2],
	&"idle_up": [3],
	&"walk_side": [1, 2, 3, 4],
	&"idle_side": [1],
	# 正面 2026-09-24 换了新素材：四张是「**1 站立、2/3/4 走路**」，
	# 和旧版（1/2/3 走路、4 站立）**正好相反**。
	# 别照着上面侧面那两行抄 —— 每个方向的素材语义各是各的。
	&"walk_down": [1, 2, 3, 4],
	&"idle_down": [1],
}

## 物理键 -> 方向。
const MOVE_KEYS: Dictionary = {
	KEY_W: Vector2.UP,
	KEY_A: Vector2.LEFT,
	KEY_S: Vector2.DOWN,
	KEY_D: Vector2.RIGHT,
}


## 当前朝向。走最后一步的方向，站着不动时保持上一次的 ——
## 存档要记它，不然读档回来角色面朝的方向会变。
var facing := Vector2.DOWN
## 被按住了：不许动，也不受物理推挤。
##
## 给「强制把角色摆到某处」用（开场最后那一幕把人放到床上）。床那块本来
## 就是实体，脚落在里面会被物理每帧推出来、再弹回去 —— 画面上是站在床上
## 一直抖。既然是剧情强制摆的位置，就别让物理来管。
## 换场景、开新局、读档都会放开。
var pinned := false
var _sprite: AnimatedSprite2D = null

## 鼠标点出来的那条路：一串落脚点（世界坐标）。非空时角色**自己走**。
##
## **玩家一按方向键就清掉** —— 手动永远压过自动。不清的话会出现
## 「我在推，它却往反方向走」，而且会一直走到路径尽头才认。
var walk_path: Array[Vector2] = []

## 离下一个落脚点多近就算「走到了」。
##
## **不能比格子间距（2 像素）大。** 大的话会连着吃掉好几个点：
## 人在路左边差 3 像素时，判据一松，那几个点全都被当成"到了"吃光，
## 人就停在原地不动了。取 1 —— 一个格子的一半，误差肉眼看不出来。
const ARRIVE := 1.0


## 与地图共用最近邻采样，缩放时保留像素边缘；预览子类也继承这个默认值。
func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _physics_process(_delta: float) -> void:
	if _chase_burst_time_left > 0.0:
		if _chase_burst_remaining > 0.0:
			_chase_burst_elapsed = minf(CHASE_BURST_DURATION, _chase_burst_elapsed + _delta)
			var progress: float = _chase_burst_elapsed / CHASE_BURST_DURATION
			var burst_distance: float = CHASE_BURST_DISTANCE * scale.x
			var burst_speed: float = burst_distance / CHASE_BURST_DURATION \
				* 6.0 * progress * (1.0 - progress)
			_chase_burst_velocity = facing * burst_speed
			velocity = _chase_burst_velocity
			var motion: Vector2 = _chase_burst_velocity * _delta
			var collision := move_and_collide(motion)
			if collision != null:
				_chase_burst_remaining = 0.0
				_chase_burst_time_left = 0.0
				_chase_burst_elapsed = 0.0
			else:
				_chase_burst_distance += motion.length()
				_chase_burst_remaining = burst_distance - _chase_burst_distance
				_chase_burst_time_left = CHASE_BURST_DURATION - _chase_burst_elapsed
		if _chase_burst_time_left <= 0.0:
			_chase_burst_remaining = 0.0
			_chase_burst_distance = 0.0
			_chase_burst_velocity = Vector2.ZERO
			velocity = Vector2.ZERO
			_chase_burst_elapsed = 0.0
			chase_input_locked = false
			play_animation(false)
		return
	if chase_input_locked:
		velocity = Vector2.ZERO
		play_animation(false)
		return
	var direction := current_direction()
	if direction != Vector2.ZERO:
		# 手动操作取消自动走
		walk_path.clear()
	elif not walk_path.is_empty():
		direction = _follow_path()
	if direction != Vector2.ZERO:
		facing = direction
	velocity = direction * movement_speed()
	move_and_slide()
	play_animation(direction != Vector2.ZERO)


func start_chase_burst(direction: Vector2, distance: float = CHASE_BURST_DISTANCE) -> bool:
	if direction == Vector2.ZERO:
		return false
	var normalized := direction.normalized()
	facing = normalized
	_chase_burst_remaining = distance * scale.x
	_chase_burst_distance = 0.0
	_chase_burst_time_left = CHASE_BURST_DURATION
	_chase_burst_elapsed = 0.0
	_chase_burst_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	chase_input_locked = true
	if _sprite != null:
		var side := facing_side()
		_sprite.play(StringName("burst_" + side))
		if side == "side":
			_sprite.flip_h = facing.x > 0.0
	return true


## 立即结束冲刺并释放输入锁（剧情保险用：冲刺因故停不下来时不让流程卡住）。
func stop_chase_burst() -> void:
	_chase_burst_remaining = 0.0
	_chase_burst_distance = 0.0
	_chase_burst_time_left = 0.0
	_chase_burst_elapsed = 0.0
	_chase_burst_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	chase_input_locked = false
	play_animation(false)


func is_chase_bursting() -> bool:
	return _chase_burst_time_left > 0.0


## Returns the longest collision-free burst length in unscaled player units.
func burst_clearance(direction: Vector2, limit: float) -> float:
	if direction.is_zero_approx() or limit <= 0.0:
		return 0.0
	var unit := direction.normalized()
	var distance := 0.0
	# 每次从起点测「已走 + 这一步」的整段位移；只测单步的话永远从原地出发，
	# 隔着几格的墙测不到，窄道里会误报整段畅通（2026-10-28 图书馆门口卡死的根因之一）。
	while distance < limit:
		var step := minf(2.0, limit - distance)
		if test_move(global_transform, unit * (distance + step) * scale.x):
			break
		distance += step
	return distance


## 速度按统一显示尺度标定。地图坐标的步长随标尺变化，投影后始终 SPEED。
func movement_speed() -> float:
	return SPEED * scale.x


## 沿鼠标点出来的路走，返回这一帧往哪走。整条走完返回零向量，人就停下。
##
## **一次只沿一个轴走。** 这一点是踩出来的（2026-09-24）：
##
## 路点是四方向连出来的，看着「顺着走就行」；但「离得够近就吃掉这个点」
## 那个机制会让 `gap` 变成**斜的** —— 拐弯处前一个点被吃掉，下一个点在另一条轴上，
## 于是 `gap` 同时有 x 和 y。这时候拿 `normalized()` 走，人会**斜着抄近道切过拐角**，
## 而那正是最窄的地方：蹭到桌角就推不动了。
##
## 症状很有欺骗性：**路径还在、行走动画还在播，人卡在墙角原地踏步**，
## 看着像寻路算错了，其实是走路那一步斜了。同时「走不到目标」也是它 ——
## 卡在半路，后面的点永远轮不到。
##
## 用 `while` 一格一格吃掉走过的点：路点是 2 像素一格，密得很，
## 一帧（96 像素/秒 ÷ 60 帧 ≈ 1.6 像素）就能跨过好几个。
func _follow_path() -> Vector2:
	while not walk_path.is_empty():
		var gap := walk_path[0] - global_position
		# 先走主轴，再走另一轴。**不是「谁大先走谁」** ——
		# 那样在拐角处会来回换轴。固定「先 x 后 y」，走出来的折线是稳的。
		if absf(gap.x) > ARRIVE:
			return Vector2(signf(gap.x), 0.0)
		if absf(gap.y) > ARRIVE:
			return Vector2(0.0, signf(gap.y))
		walk_path.pop_front()
	return Vector2.ZERO


## 读当前按键并算出方向。依赖 Input 单例，不方便单测。
func current_direction() -> Vector2:
	var pressed: Array[int] = []
	for key: Variant in MOVE_KEYS:
		if Input.is_physical_key_pressed(int(key)):
			pressed.append(int(key))
	return direction_from(pressed)


## 造一个角色。建角色的活放在这里，别堆在入口里 ——
## 入口该管的是「把它放进场景」，不是「它由几个节点拼成」。
static func create() -> Player:
	var p := Player.new()
	p.name = "Player"
	p.z_index = 10

	var collision := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = FOOT_SIZE
	collision.shape = box
	collision.position = Vector2(0.0, FOOT_OFFSET)
	p.add_child(collision)

	var frames := build_frames()
	if frames != null:
		var sprite := AnimatedSprite2D.new()
		sprite.name = "Body"
		sprite.sprite_frames = frames
		sprite.centered = false
		var first := frames.get_frame_texture(&"idle_down", 0)
		var size := first.get_size() if first != null else BODY_SIZE
		# 帧图是高分辨率的，**缩小在这里做**：节点 scale，不是把图压小。
		# offset 用的是贴图自身的像素 —— 它和贴图一起被 scale 缩，所以
		# 「图宽的一半、往上一整张」这样写，脚底就落在原点上。
		var ratio := DISPLAY_HEIGHT / maxf(size.y, 1.0)
		sprite.scale = Vector2(ratio, ratio)
		sprite.offset = Vector2(-size.x * 0.5, -size.y)
		p.add_child(sprite)
		p._sprite = sprite
		p.play_animation(false)
		return p

	push_warning("[角色] 帧图读不到，先用色块顶着：%s" % FRAME_DIR)
	var half := BODY_SIZE * 0.5
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-half.x, -BODY_SIZE.y),
		Vector2(half.x, -BODY_SIZE.y),
		Vector2(half.x, 0.0),
		Vector2(-half.x, 0.0),
	])
	body.color = BODY_COLOR
	p.add_child(body)
	return p


## 主角与试走共用环境材质；换图后重建，避免携带上一场景的色温。
func configure_environment(definition: MapDef) -> void:
	if _sprite != null:
		preload("res://scenes/world_look.gd").style_actor(_sprite, definition)


## 从按下的键算出移动方向。纯函数，测试走这个。
##
## 斜向会被归一化，所以斜着走不会比直着快 —— 这类地方不加处理，
## 玩起来会立刻察觉「怎么斜着跑得更快」。
static func direction_from(pressed: Array[int]) -> Vector2:
	var direction := Vector2.ZERO
	for key: int in pressed:
		if not MOVE_KEYS.has(key):
			continue
		var step: Vector2 = MOVE_KEYS[key]
		direction += step
	if direction == Vector2.ZERO:
		return Vector2.ZERO
	return direction.normalized()


## 拼出四向的帧表。缺任何一帧就返回 null，让调用方退回色块 ——
## 缺帧的动画播起来会跳，不如直接别用。
static func build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")

	for name: StringName in ANIMATIONS:
		var direction := String(name).split("_")[1]
		var indices: Array = ANIMATIONS[name]
		frames.add_animation(name)
		frames.set_animation_speed(name, WALK_FPS)
		# 全设成循环。站着的只有一帧，循环起来就是静止画面；
		# 不循环的话播完 is_playing 变 false，每帧都要重新 play 一次。
		frames.set_animation_loop(name, true)
		for index: int in indices:
			var path := "%s/%s%d.png" % [FRAME_DIR, direction, index]
			if not ResourceLoader.exists(path):
				push_warning("[角色] 缺帧：%s" % path)
				return null
			var texture: Resource = load(path)
			if not (texture is Texture2D):
				push_warning("[角色] 帧不是图片：%s" % path)
				return null
			frames.add_frame(name, texture)
	var burst_indices_by_direction: Dictionary = {
		"up": [1, 3, 2, 3],
		"side": [1, 2, 3, 4],
		"down": [1, 2, 3, 4],
	}
	for direction: String in ["up", "side", "down"]:
		var burst_name := StringName("burst_" + direction)
		frames.add_animation(burst_name)
		frames.set_animation_speed(burst_name, CHASE_BURST_FPS)
		frames.set_animation_loop(burst_name, false)
		var walk_name := StringName("walk_" + direction)
		var burst_indices: Array = burst_indices_by_direction[direction]
		for index: int in burst_indices:
			frames.add_frame(burst_name, frames.get_frame_texture(walk_name, index - 1))
	return frames


## 按当前朝向和「在不在走」切动画。
##
## **四向**：斜着走时取分得比较开的那个轴，不是八向。
## 素材的侧面是朝左的，往右走把它翻过来。
func play_animation(moving: bool) -> void:
	if _sprite == null:
		return
	var side := facing_side()
	var name := StringName(("walk_" if moving else "idle_") + side)
	if _sprite.animation != name or not _sprite.is_playing():
		_sprite.play(name)
	if side == "side":
		_sprite.flip_h = facing.x > 0.0


## 朝向属于哪一面：上下左右四个。
func facing_side() -> String:
	if absf(facing.x) >= absf(facing.y):
		return "side"
	return "up" if facing.y < 0.0 else "down"


## 头的正中央相对于脚底在哪儿。**y 是负的** —— 往上。
func head_offset() -> Vector2:
	return global_transform.basis_xform(Vector2(0.0, -DISPLAY_HEIGHT * HEAD_RATIO))


## 让**头的正中央**落在 `point` 上。脚底自然就落在下面一截。
##
## 给「按头定位」的场合用：躺在床上要把头摆进枕头里，拿脚底当基准
## 就得在剧本里手算一个偏移，换素材那次一定忘。
func place_head_at(point: Vector2) -> void:
	global_position = point - head_offset()

