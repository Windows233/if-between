extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	harness.section("可选 IF 地图编辑插件")
	preload("res://tests/test_map_editor.gd").run(harness)
	preload("res://tests/test_map_objects.gd").run(harness)
	preload("res://tests/test_map_hierarchy.gd").run(harness)
	preload("res://tests/test_map_templates.gd").run(harness)
	preload("res://tests/test_map_geometry_transfer.gd").run(harness)
	preload("res://tests/test_map_transfer_ui.gd").run(harness)
	preload("res://tests/test_map_collision_edit.gd").run(harness)
	preload("res://tests/test_map_creation.gd").run(harness)
	preload("res://tests/test_map_asset_drop.gd").run(harness)
	preload("res://tests/test_map_asset_scale.gd").run(harness)
	preload("res://tests/test_map_preview.gd").run(harness)
	preload("res://tests/test_map_scene_workflow.gd").run(harness)
	preload("res://tests/test_map_canvas_workflow.gd").run(harness)
	preload("res://tests/test_map_template_updates.gd").run(harness)
	preload("res://tests/test_map_review.gd").run(harness)
	preload("res://tests/test_map_validation.gd").run(harness)
	preload("res://tests/test_map_trigger_editor.gd").run(harness)
	await preload("res://tests/test_map_preview_options.gd").run(harness)
	await preload("res://tests/test_map_inspector_ui.gd").run(harness)
	await preload("res://tests/test_map_scene_tools_ui.gd").run(harness)
	quit(0 if harness.report() else 1)
