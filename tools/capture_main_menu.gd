extends SceneTree
## Capture the actual cover and validate the menu stays inside its paper.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(1.0).timeout
	var buttons := menu.get_node("VBoxContainer") as VBoxContainer
	var paper := menu.get_node("MenuPaper") as Control
	var exit := buttons.get_node("Exit") as Button
	assert(buttons.get_child_count() == 6)
	assert(paper.get_global_rect().encloses(exit.get_global_rect()))
	assert(exit.has_node("Caption") and exit.pressed.is_connected(menu._on_quit))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--selected="):
			buttons.get_node(argument.trim_prefix("--selected=")).grab_focus()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tools/out/main_menu")
	var error := root.get_texture().get_image().save_png("res://tools/out/main_menu/cover.png")
	print("Cover capture: ", error, "; six buttons; exit inside paper and connected")
	quit(error)
