extends SceneTree
## 验证独立试片的座位锚点、移动和稳定坐姿；无窗口也可运行。


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var scene: Node3D = (
		load("res://scenes/game/school_student_motion_sample_showroom.tscn").instantiate()
	)
	root.add_child(scene)
	scene.automatic = false
	scene.seek(0.0)
	var initial: Vector3 = scene.actor.position
	var standing_top := _visible_top(scene.sprite)
	scene.seek(float(scene.settings["walk_duration"]) * 0.5)
	assert(scene.actor.position.distance_to(initial) > 0.4, "walking must change world position")
	scene.seek(scene.duration() - 0.1)
	var seat: Vector3 = scene.get_node("Sample/SitPoint").global_position
	assert(
		scene.actor.global_position.distance_to(seat) < 0.001,
		"must settle at actual desk seat anchor"
	)
	var seated_top := _visible_top(scene.sprite)
	assert(
		seated_top < standing_top - 0.3,
		"sit must lower anatomy, not just slide the standing sprite"
	)
	var final_texture: Texture2D = scene.sprite.texture
	scene.seek(scene.duration() - 0.5)
	assert(scene.sprite.texture == final_texture, "seated hold must not continue stepping frames")
	assert(scene.actor.global_position.distance_to(seat) < 0.001, "seated hold must not drift")
	print(
		"PASS: world movement, real seat anchor, lowered anatomy, stable seated frame and position"
	)
	scene.queue_free()
	await process_frame
	await process_frame
	quit()


func _visible_top(sprite: Sprite3D) -> float:
	var image := sprite.texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= sprite.alpha_scissor_threshold:
				return sprite.position.y + (image.get_height() * 0.5 - y) * sprite.pixel_size
	return sprite.position.y
