extends SceneTree
## 真实引擎画面；只使用独立演示局，不写存档。

var _folder := "res://tools/out/office_hub"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.get_node("GameState").start_game(20261014, 16)
	var scene: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in range(180):
		if scene.has_node("OfficeHub"):
			break
		await physics_frame
	if not scene.has_node("OfficeHub"):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_folder)
	var hub: Node = scene.get_node("OfficeHub")
	scene.get_node("TransitionOverlay").force_hide()
	scene.get_node("Clock").hold(&"office_capture")
	root.borderless = true
	await _save("classroom-initial")
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		hub.set_mode("classroom")
		await _save("classroom-" + str(dimensions.x))
		hub.set_mode("office")
		await _save("office-" + str(dimensions.x))
		hub.open_tool("summon")
		await _save("picker-" + str(dimensions.x))
		hub.select_student(0)
		await _save("summon-" + str(dimensions.x))
		hub.close_picker()
		hub.set_mode("monitor")
		await _save("monitor-" + str(dimensions.x))
		hub.select_observed_student(0)
		await _save("selected-student-" + str(dimensions.x))
		hub.set_mode("classroom")
		await _save("teacher-classroom-" + str(dimensions.x))
		hub.set_mode("office")
	hub.open_tool("encyclopedia")
	await _save("encyclopedia")
	scene.get_node("UI/EncyclopediaEntry").close()
	hub.open_tool("profile")
	hub.select_student(0)
	await _save("profile")
	scene.get_node("UI/NpcProfile").close()
	hub._on_action("settings")
	await _save("settings")
	scene.get_node("UI/PauseMenu").settings_panel.hide()
	scene.get_node("UI/PauseMenu")._on_resume()
	hub.set_mode("monitor")
	await _save("monitor")
	hub.set_mode("classroom")
	await _save("classroom-return")
	print("OFFICE CAPTURE: PASS")
	quit(0)


func _save(label: String) -> void:
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(_folder + "/" + label + ".png")
	if result != OK:
		push_error("截图写入失败：" + label)
		quit(1)
