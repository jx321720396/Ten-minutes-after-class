extends SceneTree
## 以确定时间采样真实 Godot 渲染；输出 PNG 帧供 GIF 封装。

const SCENE := "res://scenes/game/school_student_motion_sample_showroom.tscn"
const OUTPUT := "res://tools/out/school_student_motion_sample/"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene: Node3D = load(SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automatic = false
	var settings: Dictionary = scene.settings
	root.size = Vector2i(settings["capture_size"][0], settings["capture_size"][1])
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await process_frame
	var fps := float(settings["capture_fps"])
	var count := int(ceil(scene.duration() * fps))
	for index in count:
		scene.seek(float(index) / fps)
		await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(OUTPUT + "%03d.png" % index)
		if result != OK:
			push_error("frame capture failed: %s" % result)
			quit(1)
			return
	print("Captured ", count, " frames at ", fps, " fps")
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	quit()
