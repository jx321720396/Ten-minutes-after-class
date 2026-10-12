extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene: Node2D = load("res://scenes/game/classroom_2d_motion_sample.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automatic = false
	var settings: Dictionary = scene.settings
	root.content_scale_size = Vector2i(settings["canvas"][0], settings["canvas"][1])
	root.size = Vector2i(settings["display"][0], settings["display"][1])
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var output := str(settings["output"])
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame
	var fps := float(settings["capture_fps"])
	for index in int(ceil(scene.duration() * fps)):
		scene.seek(float(index) / fps)
		await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(output + "%03d.png" % index)
		if result != OK:
			push_error("Capture failed: %s" % result)
			quit(1)
			return
	print("Captured pure 2D walk/sit sequence")
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	quit()
