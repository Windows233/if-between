## 贴图尺寸变换保持碰撞和交互世界范围的回归。
##
## 独立运行：godot --headless --path <项目> --script res://tests/test_map_texture_fit.gd
extends SceneTree

const Transform := preload("res://addons/if_map_editor/map_object_transform.gd")
const MapDef := preload("res://core/map_def.gd")


func _initialize() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("视觉尺寸与游戏几何分离")
	var source := {
		"id": "desk", "rect": [100, 80, 120, 100], "sprite": "desk.png",
		"collision": [[20, 25, 50, 40], [-30, -20, 25, 18]],
		"reach_local": [-10, 60, 100, 50], "visual_parts": [
			{"sprite": "shelf.png", "rect": [-10, 20, 60, 30], "layer": "back"},
		],
	}
	var before := MapDef._actor_from(source)
	var resized := Transform.resized_actor(source, Rect2(40, 105, 240, 50))
	var after := MapDef._actor_from(resized)
	h.check("视觉拉伸只改贴图框", resized["rect"], [40, 105, 240, 50])
	h.check("视觉拉伸保留碰撞世界矩形", after.collision_rects(), before.collision_rects())
	h.check("视觉拉伸保留交互世界矩形", after.reach, before.reach)
	h.check("视觉拉伸同步视觉部件", resized["visual_parts"][0]["rect"], [-20, 10, 120, 15])
	h.check("视觉拉伸不污染来源", source["rect"], [100, 80, 120, 100])

	var default_solid := {"id": "crate", "rect": [10, 20, 30, 40], "solid": true}
	var solid_before := MapDef._actor_from(default_solid)
	var solid_resized := Transform.resized_actor(default_solid, Rect2(0, 10, 60, 20))
	var solid_after := MapDef._actor_from(solid_resized)
	h.check("默认实体碰撞在视觉变换后保持原范围", solid_after.collision_rects(), solid_before.collision_rects())
