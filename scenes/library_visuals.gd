## 图书馆独立猫与血迹的状态恢复。净化属于个人时间线，门口旧血迹属于地图。
## 地图仅保存图层和位置；入图、读档、剧情刷新时恢复相应贴图变体。
extends RefCounted

const CAT_HIDDEN := &"ch2/personal/library_cat_hidden"
const BLOOD := &"map_blood/library/entrance"


static func prepare(def: MapDef, flags: WorldState) -> void:
	if def == null or def.id != &"library":
		return
	var fallen: bool = flags.get_value(&"ch2/library/shelf_fallen") == true
	var source := preload("res://scenes/library_shelf_fall.gd").source_rect(def)
	for actor: MapDef.Actor in def.actors:
		if actor.id == &"shelf_d":
			actor.sprite_variants["standing"] = "res://art/props/library_shelf_d_cover.png"
			actor.sprite_variants["hidden"] = "res://art/fx/library/hidden.png"
			actor.sprite_variant = "hidden" if fallen else "standing"
			if not actor.has_meta("standing_collision"):
				actor.set_meta("standing_collision", actor.collisions.duplicate())
			actor.collisions.clear()
			if not fallen:
				actor.collisions.assign(actor.get_meta("standing_collision"))
		if actor.id != &"escape_shelf_barrier":
			continue
		if source.size.x <= 0.0 or source.size.y <= 0.0:
			actor.sprite_variant = "hidden"
			actor.has_local_collision = false
			actor.collisions.clear()
			continue
		# 倒塌物件的矩形由编辑器指定，不能用旧坐标覆盖用户落点。
		actor.sprite_variant = "fallen" if fallen else "hidden"
		actor.draw_layer = "map_top_under_player"
		actor.has_local_collision = fallen
		actor.collisions.clear()
		if fallen:
			actor.collisions.append(Rect2(Vector2(2, 2), actor.rect.size - Vector2(4, 4)))
		actor.solid = false


static func sync(host: Variant) -> void:
	if host.current_map == null or host.current_map.id != &"library":
		return
	var has_layers := false
	for actor: MapDef.Actor in host.current_map.actors:
		if actor.id == &"library_cat_visual":
			has_layers = true
			break
	if not has_layers:
		return
	# 剧本首次调查前血迹已存在；旧存档初次载入新图时也恢复它。
	if not host.flags.has_value(BLOOD):
		host.flags.set_value(BLOOD, true)
	host.set_actor_sprite_variant(&"library_cat_visual",
		&"hidden" if host.flags.get_value(CAT_HIDDEN) == true else &"visible")
	host.set_actor_sprite_variant(&"library_blood_visual",
		&"visible" if host.flags.get_value(BLOOD) == true else &"hidden")
