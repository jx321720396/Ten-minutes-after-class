extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var core := SimCore.new(20261019, 16, ConfigLoader.new().load_all())
	var view = load("res://scripts/ui/teacher_interlude.gd").new()
	root.add_child(view)
	for kind in ["comfort", "praise", "scold", "ask", "encourage", "mediate"]:
		var snapshot := {
			"command": "mediate" if kind == "mediate" else "office_chat",
			"chat_kind": kind,
			"called": 0,
			"remaining_seconds": 20,
			"mediate_pair": {"a": 0, "b": 1}
		}
		view.refresh(core, snapshot)
		await process_frame
		assert(view.visible)
		assert(view.has_method("teacher_pose"), "演出必须包含真实老师动作画像")
		if not view.has_method("teacher_pose"):
			quit(1)
			return
		assert(view.teacher_pose() != null)
		if "--capture" in OS.get_cmdline_user_args():
			await create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://tools/out/teacher_interlude")
			root.get_texture().get_image().save_png(
				"res://tools/out/teacher_interlude/%s.png" % kind
			)
		assert(not paused)
		snapshot.held_by_class = true
		view.refresh(core, snapshot)
		assert(view._status.text == view.config.held)
		view.refresh(core, {})
		assert(not view.visible)
	var commands = core.teacher_commands()
	assert(commands.mediate(core, 0, 1))
	var before := core.hostility(0, 1)
	assert(commands.cancel_intervention())
	for tick in range(25):
		commands.tick(core)
	assert(core.hostility(0, 1) == before)
	print("teacher_interlude: six animations, held state, hide and cancellation PASS")
	view.queue_free()
	await process_frame
	quit()
