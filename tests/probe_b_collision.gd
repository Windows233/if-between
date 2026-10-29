## 第二章B的真实出场配方：四向实体阻挡、对话与读档恢复回归。
extends SceneTree
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var h := TestHarness.new()
    h.setup(root)
    var main := h.new_main()
    main.enter_map(&"market", &"start")
    main.player.set_physics_process(false)
    main.map_view.queue_free()
    var scene: Cutscene = main.cutscene
    scene.instant = true
    var event := DataLoader.load_event(&"ch2_meet_a")
    for node in event.nodes:
        for step in node.stage:
            if step.kind == &"npc" and step.text("id") == "b":
                await scene.run([step])
    # Use the actual entrance recipe, including talk binding, for both initial and restored actors.
    for cycle in range(2):
        var actor: Node2D = scene._actors["b"]
        await physics_frame
        await physics_frame
        for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
            var center := actor.global_position + Vector2(0, -6)
            main.player.global_position = center - direction * 35
            var hit: KinematicCollision2D = main.player.move_and_collide(direction * 70)
            h.check("B 四向阻挡 %s/%s" % [cycle,direction], hit != null and hit.get_collider() == actor.get_node("Body"), true)
        h.check("B 对话保留",scene._talk.get("b"), &"meet_b")
        var snapshot := scene.snapshot_actors()
        scene.clear_actors()
        await process_frame
        scene.restore_actors(snapshot)
    print("B collision: ",h.passed," passed, ",h.failed," failed ",h.failures)
    main.queue_free()
    quit(0 if h.failed == 0 else 1)


