extends "res://scripts/ui/opening_comic.gd"
## 离线烘焙专用；游戏运行时不创建气泡。

const BUBBLE := preload("res://scripts/ui/opening_comic_bubble.gd")


func _show_page() -> void:
	super._show_page()
	var source_path := (
		"res://docs/art/opening_comic_sources/" + str(_cfg.pages[state.page].image).get_file()
	)
	var texture := ImageTexture.create_from_image(Image.load_from_file(source_path))
	for panel in _panels:
		panel.texture = texture
		panel.queue_redraw()
	var entry: Dictionary = _cfg.pages[state.page]
	for i in _panels.size():
		_add_dialogue(_panels[i], str(entry.dialogue[i]), _cfg.dialogue_rects[i], i)
		if entry.has("assessment") and i == 1:
			_add_dialogue(_panels[i], str(entry.assessment), _cfg.assessment_rect)


func _add_dialogue(parent: Control, text: String, rect: Array, index: int = -1) -> void:
	if text.is_empty():
		return
	var box: PanelContainer = BUBBLE.new() if index >= 0 else PanelContainer.new()
	box.position = Vector2(rect[0], rect[1])
	box.size = Vector2(rect[2], rect[3])
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if index >= 0:
		box.tail_anchor = float(_cfg.tail_anchors[index])
		box.tail_width = float(_cfg.tail_width)
		box.tail_depth = float(_cfg.tail_depth)
		box.tail_lean = float(_cfg.tail_leans[index])
		box.fill = Color(_cfg.bubble)
		box.ink = Color(_cfg.ink)
		box.border = float(_cfg.border_pixels)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_cfg.bubble)
	style.border_color = Color(_cfg.ink)
	style.set_border_width_all(int(_cfg.border_pixels))
	style.set_corner_radius_all(int(_cfg.bubble_radius))
	style.content_margin_left = float(_cfg.padding)
	style.content_margin_right = float(_cfg.padding)
	style.content_margin_top = float(_cfg.padding)
	style.content_margin_bottom = float(_cfg.padding)
	box.add_theme_stylebox_override("panel", style)
	parent.add_child(box)
	var label := _label(box, text, [], int(_cfg.body_font))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
