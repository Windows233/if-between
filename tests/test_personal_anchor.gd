## 首次入馆个人锚点：只恢复主角落点与背包，不回滚世界进度。
class_name TestPersonalAnchor
extends RefCounted


static func run(h: TestHarness) -> void:
	test_capture_restore(h)
	test_capture_only_once(h)
	test_snapshot_round_trip(h)
	test_restore_requires_capture(h)


static func test_capture_restore(h: TestHarness) -> void:
	var data := SaveData.new()
	data.map_id = &"library"
	data.spawn = &"entrance"
	data.player_position = Vector2(120, 84)
	data.facing = Vector2.LEFT
	data.story_event = &"library_intro"
	data.story_node = &"free_roam"
	data.story_step = 3
	data.story_spoke = true
	data.flags = {"memory/old": true, "item/serialized_only": 7}
	data.endings = [&"end1_calm"]
	data.actors = [{"id": "c", "at": [12, 30]}]

	var flags := WorldState.new()
	ItemTable.add(flags, &"decision_coin", 2)
	ItemTable.add(flags, &"cat_photo")
	flags.set_value(&"memory/library_note", "remembered")
	flags.set_value(&"map_blood/library/desk", 1)

	var anchor := PersonalAnchor.new()
	h.check("首次捕获成功", anchor.capture_once(data, flags), true)
	h.check("锚点标记为已捕获", anchor.is_captured(), true)

	data.map_id = &"classroom"
	data.spawn = &"door"
	data.player_position = Vector2(8, 9)
	data.facing = Vector2.UP
	data.story_event = &"later_event"
	data.story_node = &"later_node"
	data.story_step = 9
	data.story_spoke = false
	data.flags["memory/old"] = false
	data.endings.clear()
	data.actors.clear()

	flags.set_value(ItemTable.flag_key(&"decision_coin"), 0)
	flags.unset_value(ItemTable.flag_key(&"cat_photo"))
	ItemTable.add(flags, &"student_id", 1)
	flags.set_value(&"memory/library_note", "new memory")
	flags.set_value(&"map_blood/library/desk", 2)

	h.check("恢复成功", anchor.restore(data, flags), true)
	h.check("恢复地图落点", data.map_id, &"library")
	h.check("恢复出生点", data.spawn, &"entrance")
	h.check("恢复主角坐标", data.player_position, Vector2(120, 84))
	h.check("恢复主角朝向", data.facing, Vector2.LEFT)
	h.check("恢复剧情进度而不覆盖", data.story_event, &"later_event")
	h.check("保留当前剧情节点", data.story_node, &"later_node")
	h.check("保留当前节点步数", data.story_step, 9)
	h.check("保留当前对话进度", data.story_spoke, false)
	h.check("保留当前存档flags", data.flags, {"memory/old": false, "item/serialized_only": 7})
	h.check("保留当前结局列表", data.endings.is_empty(), true)
	h.check("保留当前临时角色", data.actors.is_empty(), true)
	h.check("恢复决策币数量", ItemTable.count_of(flags, &"decision_coin"), 2)
	h.check("恢复猫照片数量", ItemTable.count_of(flags, &"cat_photo"), 1)
	h.check("移除锚点后新获得的物品", flags.has_value(ItemTable.flag_key(&"student_id")), false)
	h.check("保留锚点后记下的记忆", flags.get_value(&"memory/library_note"), "new memory")
	h.check("保留地图血迹", flags.get_value(&"map_blood/library/desk"), 2)


static func test_capture_only_once(h: TestHarness) -> void:
	var data := SaveData.new()
	data.map_id = &"library"
	data.player_position = Vector2(40, 50)
	var flags := WorldState.new()
	ItemTable.add(flags, &"decision_coin", 1)
	var anchor := PersonalAnchor.new()

	h.check("首次捕获成功", anchor.capture_once(data, flags), true)
	data.map_id = &"office"
	data.player_position = Vector2(1, 2)
	ItemTable.add(flags, &"decision_coin", 4)
	h.check("重复捕获被拒绝", anchor.capture_once(data, flags), false)
	h.check("仍恢复第一次状态", anchor.restore(data, flags), true)
	h.check("重复捕获没有改写位置", data.map_id, &"library")
	h.check("重复捕获没有改写背包", ItemTable.count_of(flags, &"decision_coin"), 1)


static func test_snapshot_round_trip(h: TestHarness) -> void:
	var data := SaveData.new()
	data.map_id = &"library"
	data.spawn = &"entrance"
	data.player_position = Vector2(233, 296)
	var flags := WorldState.new()
	ItemTable.add(flags, &"charm", 1)
	var original := PersonalAnchor.new()
	original.capture_once(data, flags)

	var restored := PersonalAnchor.new()
	h.check("锚点可从普通存档数据恢复", restored.load_dictionary(original.to_dictionary()), true)
	data.map_id = &"classroom"
	data.player_position = Vector2(10, 12)
	ItemTable.remove(flags, &"charm")
	h.check("重载锚点恢复成功", restored.restore(data, flags), true)
	h.check("重载后还原首次入馆位置", data.player_position, Vector2(233, 296))
	h.check("重载后还原决策币", ItemTable.count_of(flags, &"charm"), 1)


static func test_restore_requires_capture(h: TestHarness) -> void:
	var data := SaveData.new()
	data.map_id = &"current"
	data.player_position = Vector2(3, 4)
	var flags := WorldState.new()
	ItemTable.add(flags, &"decision_coin", 1)
	var anchor := PersonalAnchor.new()

	h.check("未捕获的锚点不能恢复", anchor.restore(data, flags), false)
	h.check("拒绝恢复不改主角位置", data.map_id, &"current")
	h.check("拒绝恢复不改背包", ItemTable.count_of(flags, &"decision_coin"), 1)
