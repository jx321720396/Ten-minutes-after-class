extends SceneTree
## 使用真实教室与生产书包组件截图；示例库存只注入 UI，不写内核。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.get_node("GameState").start_game(12345, 16)
	var scene: Node3D = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.get_node("Clock").hold(&"backpack_capture")
	for frame in range(90):
		await process_frame
	scene.get_node("TransitionOverlay").force_hide()
	scene.get_node("TransitionOverlay").visible = false
	var bar = scene.get_node("ActionBar")
	DirAccess.make_dir_recursive_absolute("res://tools/out/backpack")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/out/backpack/entry.png")
	var entry: Button = bar.get_node("BackpackEntry/BackpackButton")
	root.warp_mouse(entry.get_global_rect().get_center())
	var motion := InputEventMouseMotion.new()
	motion.position = entry.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/out/backpack/entry-hover.png")
	entry.pressed.emit()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tools/out/backpack")
	root.get_texture().get_image().save_png("res://tools/out/backpack/actual-inventory.png")
	scene.get_node("Interaction").set_process(false)
	bar.backpack.refresh(
		{
			&"eat_snack": {"ok": true, "snacks": 5},
			&"read_book": {"ok": true, "books": 1},
			&"listen_music": {"ok": true}
		}
	)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/out/backpack/owned-book.png")
	quit()
