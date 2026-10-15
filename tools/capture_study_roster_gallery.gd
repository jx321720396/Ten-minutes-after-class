extends SceneTree

const FOLDER := "res://assets/textures/characters/study_front_v1/"
const OUTPUT := "res://docs/art/concepts/study_roster_20261015/"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	var rows = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "manifest.json"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 2040)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("e9e5dc")
	background.size = Vector2(viewport.size)
	viewport.add_child(background)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var title := Label.new()
	title.text = "全班 16 人 · 正面低头学习坐姿"
	title.position = Vector2(20, 14)
	title.size = Vector2(1560, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("263b4a"))
	viewport.add_child(title)
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var panel := Panel.new()
		panel.position = Vector2(20 + (index % 4) * 395, 80 + floori(index / 4.0) * 485)
		panel.size = Vector2(375, 465)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("faf9f5")
		style.set_corner_radius_all(12)
		panel.add_theme_stylebox_override("panel", style)
		viewport.add_child(panel)
		var image := Image.load_from_file(FOLDER + str(row["file"]))
		assert(image != null and not image.is_empty())
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.texture = ImageTexture.create_from_image(image)
		picture.position = Vector2(10, 8)
		picture.size = Vector2(355, 412)
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(picture)
		var label := Label.new()
		label.text = "%s  %s" % [row["id"], row["name"]]
		label.position = Vector2(10, 424)
		label.size = Vector2(355, 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 25)
		label.add_theme_color_override("font_color", Color("263b4a"))
		panel.add_child(label)
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var result = viewport.get_texture().get_image().save_png(OUTPUT + "study_roster_overview.png")
	print("Study roster gallery result: ", result)
	quit(result)
