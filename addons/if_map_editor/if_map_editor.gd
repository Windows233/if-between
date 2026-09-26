## 地图编辑器的入口：挂一个底栏面板。
##
## **为什么整个画布自带缩放与平移，而不是借 2D 编辑器**：
## 借 2D 编辑器就得往当前打开的场景里塞节点（要 @tool、要场景开着、
## 还和别人的编辑互相干扰）。自带一套最简单，也不影响编辑器里其他操作。
##
## 插件整体在 `addons/` 下，**不进导出包**（`export_presets.cfg` 的
## `exclude_filter` 第一项就是 `addons/*`），所以它存在不会让游戏变大一丁点。
@tool
extends EditorPlugin

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "IF 地图编辑器"
	add_control_to_dock(DOCK_SLOT_BOTTOM, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
