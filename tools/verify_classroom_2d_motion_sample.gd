extends SceneTree


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var scene: Node2D = load("res://scenes/game/classroom_2d_motion_sample.tscn").instantiate()
	root.add_child(scene)
	scene.automatic = false
	assert(not _has_3d(scene), "pure 2D sample must contain no 3D nodes")
	scene.seek(0.0)
	var start: Vector2 = scene.actor.position
	var canvas: Vector2i = root.content_scale_size
	scene.seek(float(scene.settings["walk_duration"]) * 0.5)
	assert(scene.actor.position.y < start.y - 100.0, "character must move towards desk")
	assert(root.content_scale_size == canvas, "view must stay fixed during motion")
	for index in 20:
		scene.seek(
			(
				float(scene.settings["walk_duration"])
				+ float(scene.settings["sit_duration"]) * index / 20.0
			)
		)
		assert(
			scene.actor.texture not in scene.frames.slice(4, 7),
			"arrival must never display crouching poses"
		)
	for index in 120:
		scene.seek(float(scene.settings["walk_duration"]) * index / 120.0)
		assert(scene.actor.modulate.a == 1.0, "walking must never fade or overlay adjacent poses")
		assert(not scene.has_node("WalkFrameBlend"), "must contain only one character sprite")
	scene.seek(scene.duration() - 0.1)
	var expected := Vector2(scene.settings["seat"][0], scene.settings["seat"][1])
	assert(scene.actor.position.distance_to(expected) < 0.01, "seated pose must settle at seat")
	assert(scene.backrest.visible, "chair back must be foreground during seated hold")
	var final_texture: Texture2D = scene.actor.texture
	scene.seek(scene.duration() - 0.5)
	assert(
		scene.actor.texture == final_texture and scene.actor.position == expected,
		"seated pose must not drift"
	)
	print("PASS: pure 2D nodes, fixed view, floor movement, seat placement, stable seated hold")
	scene.queue_free()
	await process_frame
	await process_frame
	quit()


func _has_3d(node: Node) -> bool:
	if node is Node3D:
		return true
	for child in node.get_children():
		if _has_3d(child):
			return true
	return false
