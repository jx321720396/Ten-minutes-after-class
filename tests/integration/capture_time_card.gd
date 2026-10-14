extends SceneTree
## 真实教室与生产时间卡截图；只暂停观察，不修改成绩或正式存档。


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var state: Node = root.get_node("GameState")
	state.start_game(20261014, 16)
	var scene: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var clock: SimulationClock = scene.get_node("Clock")
	for frame in range(180):
		if scene.get_node("Interaction")._core != null:
			break
		await physics_frame
	clock.hold(&"time_card_capture")
	root.borderless = true
	scene.get_node("TransitionOverlay").bind_clock(null)
	scene.get_node("TransitionOverlay").force_hide()
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		for frame in range(12):
			await process_frame
		scene.get_node("TransitionOverlay").force_hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var folder := "res://tools/out/time_card"
		DirAccess.make_dir_recursive_absolute(folder)
		var suffix := str(dimensions.x)
		var result := picture.save_png(folder + "/classroom-" + suffix + ".png")
		if result != OK:
			quit(1)
			return
		var hud: TimeHUD = scene.get_node("TimeHUD")
		var rect := hud._panel.get_global_rect()
		var crop := picture.get_region(Rect2i(rect))
		result = crop.save_png(folder + "/card-" + suffix + ".png")
		if result != OK:
			quit(1)
			return
		var attention: Control = hud.get_node("AttentionCard")
		var attention_rect := attention.get_global_rect()
		if attention_rect.end.y > dimensions.y:
			push_error("Attention card extends below viewport")
			quit(1)
			return
		picture.get_region(Rect2i(attention_rect)).save_png(
			folder + "/attention-" + suffix + ".png"
		)
		var overview: Control = hud.get_node("ClassOverviewCard")
		var overview_image := picture.get_region(Rect2i(overview.get_global_rect()))
		overview_image.save_png(folder + "/overview-" + suffix + ".png")
		overview.find_child("OverviewButton", true, false).pressed.emit()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/overview-details-" + suffix + ".png")
		overview.find_child("CloseOverview", true, false).pressed.emit()
		print("Captured ", dimensions, ": ", hud.title_line(), " | ", hud.detail_line())
		print(hud.get_node("Card/Rows/GradeLabel").get_parsed_text())
	quit(0)
