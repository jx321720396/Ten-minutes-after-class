extends SceneTree
## Defer resource loading until autoloads exist; retain real runtime actors.

const OUTPUT := "res://docs/art/concepts/ceiling_preview_20261015/compact_layout/"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.size = Vector2i(1440, 900)
	root.get_node("GameState").start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	await process_frame
	room.get_node("Clock").hold(&"compact_capture")
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	for frame in range(60):
		await process_frame
	room.get_node("TransitionOverlay").force_hide()
	for layer in room.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	for label in room.get_node("Actors").find_children("*", "Label3D", true, false):
		label.visible = false
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + "godot_compact.png") == OK)
	var camera = room.get_node("Camera3D")
	camera.fov = 62.0
	camera.look_at_from_position(Vector3(-0.6, 2.05, 5.7), Vector3(0.1, 1.95, -1))
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + "godot_compact_interior.png") == OK)
	room.get_node("Actors").visible = false
	camera.fov = 60.0
	camera.look_at_from_position(Vector3(0, 2.0, -1.0), Vector3(0.2, 1.8, -5.2))
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + "godot_rear_wall.png") == OK)
	camera.look_at_from_position(Vector3(0.5, 2.0, 2.5), Vector3(-2.6, 1.7, 0.4))
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + "godot_left_wall.png") == OK)
	print("PASS: compact classroom runtime screenshots")
	quit(0)
