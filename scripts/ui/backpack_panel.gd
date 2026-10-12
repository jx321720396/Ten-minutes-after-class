extends CanvasLayer
## 只读库存与行为可用性；拿取仅发送现有行为意图。

signal action_requested(kind: StringName)
signal closed

const GameFonts := preload("res://scripts/ui/game_fonts.gd")

var take_button: Button
var reason_label: Label
var _root: Control
var _card_title: Label
var _description: Label
var _quantity: Label
var _icon: TextureRect
var _cfg: Dictionary
var _states: Dictionary = {}
var _selected := &"eat_snack"
var _tags: Dictionary = {}
var _pictures: Dictionary = {}
var _tween: Tween


func _ready() -> void:
	add_to_group("backpack_panels")
	_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/backpack.json"))
	_build()
	_root.hide()
	refresh({})


func refresh(states: Dictionary) -> void:
	_states = states.duplicate(true)
	for item in _cfg.items:
		var kind := StringName(item.kind)
		var count := _count(kind)
		_tags[kind].text = item.name + (" ×%d" % count if count >= 0 else "")
		_pictures[kind].visible = count != 0
	_update_card()


func open_item(kind: StringName = &"eat_snack") -> void:
	select_item(kind)
	_root.show()
	if _tween != null:
		_tween.kill()
	_root.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, float(_cfg.slide_seconds))


func close() -> void:
	if not is_open():
		return
	_root.hide()
	closed.emit()


func is_open() -> bool:
	return _root != null and _root.visible


func launch_height() -> float:
	return float(_cfg.launch_height)


func select_item(kind: StringName) -> void:
	if not _tags.has(kind):
		return
	_selected = kind
	_update_card()


func take_selected() -> void:
	if not is_open() or not bool(_states.get(_selected, {}).get("ok", false)):
		return
	close()
	action_requested.emit(_selected)


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _count(kind: StringName) -> int:
	var state: Dictionary = _states.get(kind, {})
	if kind == &"read_book":
		return int(state.get("books", 0))
	if kind == &"eat_snack":
		return int(state.get("snacks", 0))
	return -1


func _update_card() -> void:
	for item in _cfg.items:
		var kind := StringName(item.kind)
		_tags[kind].modulate = Color(_cfg.hover) if kind == _selected else Color.WHITE
		if kind != _selected:
			continue
		_card_title.text = item.name
		_description.text = item.description
		_icon.texture = _pictures[kind].texture
		var count := _count(kind)
		_quantity.text = (
			"随时陪你听一首歌" if count < 0 else "剩余 %d %s" % [count, "本" if kind == &"read_book" else "份"]
		)
		var state: Dictionary = _states.get(kind, {})
		take_button.disabled = not bool(state.get("ok", false))
		take_button.text = "拿出来 · " + item.action
		reason_label.text = str(state.get("reason", ""))
		if state.is_empty():
			reason_label.text = "暂不可用"
		if kind == &"read_book" and int(state.get("confiscated_books", 0)) > 0:
			reason_label.text += "\n老师保管 %d 本（暂不能取回）" % int(state.confiscated_books)


func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", GameFonts.regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(_cfg.ink))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	bind_touch(button)
	button.text = text
	button.add_theme_font_override("font", GameFonts.regular())
	button.add_theme_font_size_override("font_size", int(_cfg.font_size))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(_cfg.hover if state == "hover" else _cfg.paper)
		style.border_color = Color(_cfg.accent)
		style.set_border_width_all(1)
		style.set_corner_radius_all(int(_cfg.gap))
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color(_cfg.ink))
	button.add_theme_color_override("font_hover_color", Color(_cfg.ink))
	button.add_theme_color_override("font_disabled_color", Color(_cfg.muted))
	return button


func bind_touch(button: Button) -> void:
	button.gui_input.connect(_on_button_touch.bind(button))


func _on_button_touch(event: InputEvent, button: Button) -> void:
	if Input.emulate_mouse_from_touch:
		return
	if event is InputEventScreenDrag:
		button.remove_meta("backpack_touch")
		button.accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if not button.disabled and not button.has_meta("backpack_touch"):
				button.set_meta("backpack_touch", touch.index)
		elif int(button.get_meta("backpack_touch", -1)) == touch.index:
			button.remove_meta("backpack_touch")
			if not touch.canceled and not button.disabled and button.is_visible_in_tree():
				if Rect2(Vector2.ZERO, button.size).has_point(touch.position):
					button.pressed.emit()
		button.accept_event()


func _build() -> void:
	_root = Control.new()
	_root.name = "Inventory"
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_root.offset_left = -float(_cfg.width) - float(_cfg.margin)
	_root.offset_right = -float(_cfg.margin)
	_root.offset_top = -float(_cfg.height) - float(_cfg.bottom)
	_root.offset_bottom = -float(_cfg.bottom)
	var paper := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_cfg.paper)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = int(_cfg.shadow_size)
	style.set_corner_radius_all(int(_cfg.gap))
	paper.add_theme_stylebox_override("panel", style)
	_root.add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grain := ColorRect.new()
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/ui_paper.gdshader")
	grain.material = material
	paper.add_child(grain)
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var heading := _label(_cfg.title, int(_cfg.heading_size))
	_root.add_child(heading)
	_place(heading, _rect(_cfg.title_rect))
	var exit_button := _button("×")
	_root.add_child(exit_button)
	_place(exit_button, _rect(_cfg.close_rect))
	exit_button.pressed.connect(close)
	var hint := _label(_cfg.hint, int(_cfg.small_size))
	_root.add_child(hint)
	_place(hint, _rect(_cfg.hint_rect))
	var bag := Control.new()
	_root.add_child(bag)
	_place(bag, _rect(_cfg.bag_rect))
	var empty := TextureRect.new()
	empty.texture = load(_cfg.empty_texture)
	empty.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag.add_child(empty)
	empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var atlas: Texture2D = load(_cfg.items_texture)
	for item in _cfg.items:
		var kind := StringName(item.kind)
		var region := _rect(item.region)
		var picture := TextureRect.new()
		var texture := AtlasTexture.new()
		texture.atlas = atlas
		var source := _rect(item.source_region)
		texture.region = Rect2(source.position * atlas.get_size(), source.size * atlas.get_size())
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bag.add_child(picture)
		_place(picture, Rect2(region.position * bag.size, region.size * bag.size))
		_pictures[kind] = picture
		var hit := Button.new()
		bind_touch(hit)
		hit.flat = true
		hit.tooltip_text = item.action
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		bag.add_child(hit)
		_place(hit, Rect2(region.position * bag.size, region.size * bag.size))
		hit.pressed.connect(select_item.bind(kind))
		var tag := _button(item.name)
		bag.add_child(tag)
		var tag_rect := _rect(item.tag)
		_place(tag, Rect2(tag_rect.position * bag.size, tag_rect.size * bag.size))
		tag.add_theme_font_size_override("font_size", int(_cfg.small_size))
		tag.pressed.connect(select_item.bind(kind))
		_tags[kind] = tag
	_build_card()


func _build_card() -> void:
	var card := VBoxContainer.new()
	_root.add_child(card)
	_place(card, _rect(_cfg.card_rect))
	card.add_theme_constant_override("separation", int(_cfg.gap))
	_card_title = _label("", int(_cfg.heading_size))
	card.add_child(_card_title)
	_icon = TextureRect.new()
	_icon.custom_minimum_size.y = float(_cfg.button_height)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.add_child(_icon)
	_description = _label("", int(_cfg.font_size))
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_description)
	_quantity = _label("", int(_cfg.font_size))
	card.add_child(_quantity)
	reason_label = _label("", int(_cfg.small_size))
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(reason_label)
	take_button = _button("拿出来")
	var primary := take_button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	primary.bg_color = Color(_cfg.accent)
	take_button.add_theme_stylebox_override("normal", primary)
	take_button.add_theme_color_override("font_color", Color(_cfg.paper))
	take_button.custom_minimum_size.y = float(_cfg.button_height)
	card.add_child(take_button)
	take_button.pressed.connect(take_selected)
	var back := _button("收起书包")
	back.custom_minimum_size.y = float(_cfg.button_height)
	back.pressed.connect(close)
	card.add_child(back)
