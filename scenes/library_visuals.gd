## 图书馆独立猫与血迹的状态恢复。净化属于个人时间线，门口旧血迹属于地图。
## 地图仅保存图层和位置；入图、读档、剧情刷新时恢复相应贴图变体。
extends RefCounted

const CAT_HIDDEN := &"ch2/personal/library_cat_hidden"
const BLOOD := &"map_blood/library/entrance"


static func prepare(def: MapDef, flags: WorldState) -> void:
	if def == null or def.id != &"library":
		return
	for actor: MapDef.Actor in def.actors:
		if actor.id != &"escape_shelf_barrier":
			continue
		var fallen: bool = flags.get_value(&"ch2/library/shelf_fallen") == true
		actor.sprite_variant = "fallen" if fallen else "hidden"
		actor.draw_layer = "map_top_under_player"
		actor.has_local_collision = fallen
		actor.collisions.clear()
		if fallen:
			actor.collisions.append(Rect2(0, 10, 64, 14))
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
