extends SceneTree
## 期末视觉验收：离线真实内核记录，随后在真实教室显示；不写玩家归档。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1920, 1080)
	var state: Node = root.get_node("GameState")
	state.start_game(20261011, 16)
	var core: Variant = state.sim_core
	var term_days := 0
	for row in ConfigLoader.new().load_all()["rules/time_runtime"].rows:
		if row.key == "term_days":
			term_days = int(row.value)
	while core.day() <= term_days:
		var time: Dictionary = core.time_snapshot()
		var me: int = int(core.node_count()) - 1
		if bool(time.player_control) and (not core.is_busy(me) or core.activity_of(me) == "study"):
			if int(time.tick_in_phase) == 20:
				core.set_moving(me, true)
				core.set_moving(me, false)
				core.player_action("chat", 0)
			elif core.activity_of(me).is_empty():
				core.player_action("study", me)
		core.advance_tick()
		core.finish_time_boundary()
	var scene: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 12:
		await process_frame
	scene.get_node("TransitionOverlay").force_hide()
	scene.get_node("Clock").hold(&"term_screenshot")
	var report: Node = scene.get_node("TermReport")
	assert(report.open_record(core.term_record()))
	report.set("_playing", false)
	report.seek_tick(0)
	report.advance_replay()
	await _save("details")
	report.show_matrix(0)
	await _save("matrix")
	report.call("_show_page", "stats")
	await _save("stats")
	print("record frames: ", core.term_record().frames.size())
	quit()


func _save(state: String) -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/out/term-report-%s.png" % state)
	print("saved term-report-", state)
