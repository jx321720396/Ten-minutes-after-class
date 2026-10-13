extends SceneTree

const SCENE := "res://scenes/game/normal_student_motion_sample.tscn"


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	if not ResourceLoader.exists(SCENE):
		push_error("Normal-proportion motion sample scene is missing")
		quit(1)
		return
	var scene: Node3D = load(SCENE).instantiate()
	root.add_child(scene)
	scene.automatic = false
	var actor: Node3D = scene.actor
	assert(actor.frames.get_animation_names().size() == 13)
	assert(actor.frames.has_animation("sit_front"))
	assert(not actor.frames.has_animation("sit_back"))
	assert(not actor.frames.has_animation("sit_left"))
	assert(not actor.frames.has_animation("sit_right"))
	assert(actor.frames.get_animation_speed("walk_front") <= 3.0)
	assert(actor.frames.get_animation_speed("chat_front") <= 1.5)
	for direction in ["front", "back", "left", "right"]:
		assert(actor.play_pose("walk", direction))
		assert(actor.frames.get_frame_count("walk_" + direction) == 4)
		actor.advance(0.0)
		var first: Texture2D = actor.sprite.texture
		actor.advance(0.6)
		assert(actor.sprite.texture != first, "walk must advance to another atlas region")
	assert(actor.play_pose("sit", "back"))
	assert(actor.clip == "sit_front", "seated views must resolve to front")
	assert(actor.sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED)
	var legs: Sprite3D = actor.get_node("SeatedLegs")
	assert(legs.visible and legs.position.z > actor.sprite.position.z)
	actor.advance(0.0)
	var seated: Texture2D = actor.sprite.texture
	actor.advance(2.0)
	assert(actor.sprite.texture == seated, "seated hold must remain a single frame")
	actor.play_pose("idle", "front")
	assert(not legs.visible, "seated legs must disappear on standing")
	var value: Array = scene.settings["path_start"]
	var start := Vector3(value[0], value[1], value[2])
	scene.seek(float(scene.settings["idle_duration"]))
	assert(scene.actor.position.distance_to(start) < 0.001)
	scene.seek(float(scene.settings["idle_duration"]) + float(scene.settings["walk_duration"]))
	var end: Array = scene.settings["walk_goal"]
	assert(scene.actor.position.distance_to(Vector3(end[0], end[1], end[2])) < 0.001)
	scene.seek(scene.duration() - 0.01)
	assert(scene.actor.clip == "sit_front")
	assert(scene.actor.position.distance_to(scene.seat_floor_position()) < 0.001)
	assert(scene.actor.sprite.flip_h == false)
	print(
		"PASS: 13 clips; four-direction playback; front-only seated hold; movement and seat anchor"
	)
	scene.queue_free()
	await process_frame
	quit(0)
