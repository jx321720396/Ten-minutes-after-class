extends SceneTree
## Independent capture fixture: uses core commands, never saves a game.

const OUTPUT := "res://docs/art/concepts/office_commands_20261016/"
var room: Node
var core: Variant
var hub: Node


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	root.get_node("GameState").start_game(20261016, 16)
	room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	room.get_node("Clock").hold(&"office_commands_capture")
	for frame in range(180):
		if room.has_node("OfficeHub"):
			break
		await physics_frame
	room.get_node("TransitionOverlay").force_hide()
	for frame in range(6):
		await process_frame
	core = root.get_node("GameState").sim_core
	hub = room.get_node("OfficeHub")
	hub.set_mode("office")
	var portraits: Array[Texture2D] = []
	for index in range(core.node_count()):
		hub.open_tool("summon")
		hub.select_student(index)
		if index == 0:
			await save("summon_travel.png")
		advance_command()
		hub._process(0.0)
		var picture: Image = await save("office_%02d.png" % int(core.character_id(index)))
		portraits.append(ImageTexture.create_from_image(picture))
		if index == 0:
			hub.office_view().action_requested.emit("scold")
			await save("scold.png")
			core.teacher_commands().begin_class(core)
			await save("held_by_class.png")
			core.teacher_commands().begin_break()
			advance_command()
		hub.office_view().action_requested.emit("send_back")
		advance_command()
	await save("returned.png")
	await gallery(portraits)
	print("OFFICE_COMMANDS: captured all 16 office identities and command states")
	quit(0)


func advance_command() -> void:
	var commands = core.teacher_commands()
	for tick in range(commands.remaining_seconds()):
		commands.tick(core)


func save(filename: String) -> Image:
	hub._process(0.0)
	room.get_node("Actors")._process(0.0)
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.save_png(OUTPUT + filename) == OK)
	return picture


func gallery(portraits: Array[Texture2D]) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1040)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var bg := ColorRect.new()
	bg.color = Color("eae8df")
	bg.size = Vector2(viewport.size)
	viewport.add_child(bg)
	for index in range(portraits.size()):
		var picture := TextureRect.new()
		picture.texture = portraits[index]
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.position = Vector2(index % 4 * 400 + 5, floori(index / 4.0) * 260 + 5)
		picture.size = Vector2(390, 220)
		viewport.add_child(picture)
		var label := Label.new()
		label.text = str(core.alias(index))
		label.position = picture.position + Vector2(0, 222)
		label.size = Vector2(390, 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color("293f45"))
		viewport.add_child(label)
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(OUTPUT + "all_16_office.png") == OK)
