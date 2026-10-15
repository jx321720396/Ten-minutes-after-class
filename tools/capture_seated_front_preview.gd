extends SceneTree


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1100, 800)
	var scene = load("res://scenes/game/school_student_sample_showroom.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Sample").hide()
	scene.get_node("Student").hide()
	var desk = scene.get_node("Original")
	desk.show()
	desk.position = Vector3.ZERO
	var camera = scene.get_node("Camera3D")
	camera.size = 1.4
	camera.look_at_from_position(Vector3(0, 1.48, 3.6), Vector3(0, 0.62, -0.2))
	var environment = scene.get_node("@WorldEnvironment@2").environment
	environment.background_color = Color(0.32, 0.35, 0.38)
	environment.ambient_light_energy = 0.25
	scene.get_node("WindowKey").light_energy = 0.45
	scene.get_node("SoftFill").light_energy = 0.15
	var image = Image.load_from_file(
		"res://docs/art/concepts/seated_front_20261015/char_01_study_connected.png"
	)
	var settings = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/seated_front_preview.json")
	)
	var tex = ImageTexture.create_from_image(image)
	var actor = Sprite3D.new()
	actor.texture = tex
	actor.pixel_size = 0.00075
	actor.position = Vector3(0, 0.561, -0.10)
	actor.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	actor.alpha_scissor_threshold = 0.7
	actor.no_depth_test = false
	actor.shaded = false
	scene.add_child(actor)
	# Split at hips; extend only upper body, keeping feet fixed.
	var split = int(settings["body_split_y"])
	var upper_tex = AtlasTexture.new()
	upper_tex.atlas = tex
	upper_tex.region = Rect2(0, 0, image.get_width(), split)
	var upper = actor.duplicate()
	upper.texture = upper_tex
	var gain = float(settings["upper_height_gain"])
	var upper_height = split * actor.pixel_size
	var floor_y = actor.position.y - image.get_height() * 0.5 * actor.pixel_size
	var lower_height = (
		(image.get_height() - split) * actor.pixel_size + float(settings["lower_height_gain"])
	)
	var bottom_y = floor_y + lower_height
	upper.scale.y = (upper_height + gain) / upper_height
	upper.position.y = bottom_y + (upper_height + gain) * 0.5
	scene.add_child(upper)
	var lower_tex = AtlasTexture.new()
	lower_tex.atlas = tex
	lower_tex.region = Rect2(0, split, image.get_width(), image.get_height() - split)
	actor.texture = lower_tex
	actor.scale.y = lower_height / ((image.get_height() - split) * actor.pixel_size)
	actor.position.y = floor_y + lower_height * 0.5
	# Render independent passes: chair/ground, character, desk.
	# Composite them as CanvasLayer children, giving an explicit stable order.
	var table = desk.get_node("Desk")
	var chair = desk.get_node("Chair")
	var ground = scene.get_node("Ground")
	var passes: Array[Image] = []
	for pass_index in range(3):
		table.visible = pass_index == 2
		chair.visible = pass_index == 0
		ground.visible = pass_index == 0
		actor.visible = pass_index == 1
		upper.visible = pass_index == 1
		root.transparent_bg = pass_index != 0
		for frame in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		passes.append(root.get_texture().get_image())
	# Draw captured render passes from back to front.
	table.hide()
	chair.hide()
	ground.hide()
	actor.hide()
	upper.hide()
	root.transparent_bg = false
	var composite = CanvasLayer.new()
	scene.add_child(composite)
	for pass_image in passes:
		var layer = TextureRect.new()
		layer.texture = ImageTexture.create_from_image(pass_image)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.size = Vector2(passes[0].get_size())
		composite.add_child(layer)
	# The foreground uses the SAME pose texture and projection as the body.
	if bool(settings["study"]):
		for outline in settings["foreground_polygons"]:
			var foreground = Polygon2D.new()
			var pixels = PackedVector2Array()
			var projected = PackedVector2Array()
			for point in outline:
				var pixel = Vector2(point[0], point[1])
				pixels.append(pixel)
				var world_y = bottom_y + (split - pixel.y) * actor.pixel_size * upper.scale.y
				var world_x = (pixel.x - image.get_width() * 0.5) * actor.pixel_size
				projected.append(
					camera.unproject_position(Vector3(world_x, world_y, actor.position.z))
				)
			foreground.texture = tex
			foreground.polygon = projected
			foreground.uv = pixels
			composite.add_child(foreground)
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png(
		"res://docs/art/concepts/seated_front_20261015/desk_preview_study_v5.png"
	)
	print("Layered screenshot result: ", error)
	quit(error)
