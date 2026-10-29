extends SceneTree
## 一次性探针：正式地图上旧/新交互目标选择差异统计。

func _old_pick(def: MapDef, p: Vector2, facing: Vector2) -> MapDef.Actor:
	var best: MapDef.Actor = null
	var best_d := 24.0
	for a: MapDef.Actor in def.actors:
		if a.decor or not a.is_active(null):
			continue
		if not MapDef.faces_target(p, a.reach, facing):
			continue
		var d := MapDef.rect_distance(a.reach, p)
		if d < best_d:
			best_d = d
			best = a
	return best


func _init() -> void:
	var dirs := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for file: String in DirAccess.get_files_at("res://data/maps"):
		if not file.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/" + file))
		if not (data is Dictionary):
			continue
		var def := MapDef.from_dictionary(data)
		var total := 0
		var changed := 0
		var lost := 0
		var examples: Dictionary = {}
		var lost_hist: Dictionary = {}
		var reachable_old: Dictionary = {}
		var reachable_new: Dictionary = {}
		var y := 0.0
		while y < def.size.y:
			var x := 0.0
			while x < def.size.x:
				var p := Vector2(x, y)
				if WalkGrid.is_free(def, p):
					for f: Vector2 in dirs:
						var o := _old_pick(def, p, f)
						var n := def.actor_near(p, 24.0, null, f)
						if o != null:
							reachable_old[o.id] = true
						if n != null:
							reachable_new[n.id] = true
						if o == null and n == null:
							continue
						total += 1
						if o != n:
							changed += 1
							if n == null:
								lost += 1
								var bucket := int(MapDef.rect_distance(o.reach, p) / 4.0) * 4
								lost_hist[bucket] = int(lost_hist.get(bucket, 0)) + 1
							var k := "%s->%s" % [o.id if o else &"-", n.id if n else &"-"]
							examples[k] = int(examples.get(k, 0)) + 1
				x += 4.0
			y += 4.0
		var missing: Array = []
		for id: Variant in reachable_old:
			if not reachable_new.has(id):
				missing.append(id)
		print("%s: 有目标%d 变化%d 变无%d 新规则不可达物件=%s" % [def.id, total, changed, lost, missing])
		var hk := lost_hist.keys()
		hk.sort()
		var hs := ""
		for k: Variant in hk:
			hs += "%d+:%d " % [k, lost_hist[k]]
		print("    变无时旧距离分布 ", hs)
		var keys := examples.keys()
		keys.sort_custom(func(a, b): return examples[a] > examples[b])
		for i in mini(keys.size(), 6):
			print("    ", keys[i], " x", examples[keys[i]])
	quit()
