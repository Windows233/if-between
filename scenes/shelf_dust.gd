## 书架触地扬尘：原生粒子绘制，不修改地图或碰撞。
## 暂停时同步停下，0.85秒后自清理。
extends Node2D
var area := Rect2()
var age := 0.0
func _ready() -> void:
	name = "ShelfImpactDust"
	z_index = 16
	process_mode = Node.PROCESS_MODE_PAUSABLE
func _process(delta: float) -> void:
	age += delta
	if age >= 0.85:
		queue_free()
	queue_redraw()
func _draw() -> void:
	var t := clampf(age / 0.85, 0.0, 1.0)
	for i: int in 14:
		var direction := Vector2(cos(i * 2.4), sin(i * 2.4) * 0.45 - 0.35)
		var at := area.get_center() + Vector2((float(i) / 13.0 - 0.5) * area.size.x * 0.8, 0)
		at += direction * t * 23.0
		var radius := (5.0 + (i % 4)) * (0.6 + t * 1.4)
		draw_circle(at + Vector2(0, -3), radius * 1.25, Color(0.64, 0.60, 0.52, sin(PI * t) * 0.12))
		draw_circle(at, radius, Color(0.64, 0.58, 0.47, sin(PI * t) * 0.36))
