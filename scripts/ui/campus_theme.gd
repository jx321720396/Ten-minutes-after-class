extends RefCounted
## 校园纸面主题。只处理控件外观，不读取或修改玩法状态。

const SETTINGS := "res://data/ui/campus_theme.json"
const PAPER_SHADER := preload("res://assets/shaders/ui_paper.gdshader")
const GameFonts := preload("res://scripts/ui/game_fonts.gd")


static func settings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))


static func utility_button(view: Button, slot: int) -> void:
	var cfg := settings()
	var entry: Dictionary = cfg.utility_style
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := box(
			"disabled" if state == "disabled" else "paper", "gold" if state == "hover" else "teal"
		)
		style.set_border_width_all(int(entry.border_width))
		style.shadow_color = Color(cfg.teal, float(entry.shadow_alpha))
		style.shadow_size = int(entry.shadow_size)
		style.shadow_offset = Vector2(float(entry.shadow_offset[0]), float(entry.shadow_offset[1]))
		if state == "hover":
			style.border_width_bottom = int(entry.hover_underline)
		view.add_theme_stylebox_override(state, style)
	var focus := box("paper", "gold")
	focus.bg_color = Color.TRANSPARENT
	focus.set_border_width_all(int(entry.border_width))
	view.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		view.add_theme_color_override(state, Color(cfg.teal))
	view.add_theme_color_override("font_disabled_color", Color(cfg.line))
	for state in ["normal", "hover", "pressed", "focus"]:
		view.add_theme_color_override("icon_" + state + "_color", Color(cfg.teal))
	view.add_theme_font_override("font", GameFonts.regular())
	view.add_theme_font_size_override("font_size", int(cfg.utility_font_size))
	view.icon = load("res://assets/icons/actions/%s.svg" % entry.icons[slot])
	view.tooltip_text = str(entry.tooltips[slot])
	view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	view.add_theme_constant_override("icon_max_width", int(cfg.utility_icon_size))
	view.add_theme_constant_override("h_separation", int(entry.icon_gap))
	view.custom_minimum_size = Vector2(cfg.utility_width, cfg.utility_height)
	view.anchor_left = 1.0
	view.anchor_right = 1.0
	view.anchor_top = 1.0
	view.anchor_bottom = 1.0
	view.offset_right = -cfg.utility_margin - slot * (cfg.utility_width + cfg.utility_gap)
	view.offset_left = view.offset_right - cfg.utility_width
	view.offset_bottom = -cfg.utility_margin
	view.offset_top = view.offset_bottom - cfg.utility_height
	if not view.has_node("CampusPaperGrain"):
		var grain := ColorRect.new()
		grain.name = "CampusPaperGrain"
		grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = PAPER_SHADER
		grain.material = material
		view.add_child(grain)
		grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not view.pressed.is_connected(_close_backpacks.bind(view)):
		view.pressed.connect(_close_backpacks.bind(view))


static func _close_backpacks(view: Button) -> void:
	if view.name == "BackpackButton":
		return
	for panel in view.get_tree().get_nodes_in_group("backpack_panels"):
		panel.close()


static func box(fill: String, border: String) -> StyleBoxFlat:
	var cfg := settings()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(cfg[fill])
	style.border_color = Color(cfg[border])
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(cfg.radius))
	style.set_content_margin_all(float(cfg.margin))
	style.shadow_color = Color(0, 0, 0, 0.16)
	style.shadow_size = int(cfg.shadow)
	return style


static func button(view: Button, primary: bool = false) -> void:
	var cfg := settings()
	view.add_theme_stylebox_override(
		"normal", box("teal" if primary else "paper", "teal" if primary else "line")
	)
	view.add_theme_stylebox_override("hover", box("teal", "gold"))
	view.add_theme_stylebox_override("pressed", box("ink", "gold"))
	view.add_theme_stylebox_override("disabled", box("disabled", "line"))
	var focus := box("paper", "gold")
	focus.bg_color = Color.TRANSPARENT
	focus.set_border_width_all(2)
	view.add_theme_stylebox_override("focus", focus)
	view.add_theme_color_override("font_color", Color(cfg.paper if primary else cfg.ink))
	view.add_theme_color_override("font_hover_color", Color(cfg.paper))
	view.add_theme_color_override("font_pressed_color", Color(cfg.paper))
	view.add_theme_color_override("font_disabled_color", Color(cfg.line).darkened(0.3))


static func apply_tree(root: Node) -> void:
	if root is PanelContainer:
		root.add_theme_stylebox_override("panel", box("paper", "line"))
		if root.name == "Card" and root.get_parent() is TimeHUD:
			root.add_theme_stylebox_override("panel", paper_card())
			root.custom_minimum_size.y = settings().time_card_height
		if not root.has_node("CampusPaperGrain"):
			var grain := ColorRect.new()
			grain.name = "CampusPaperGrain"
			grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var material := ShaderMaterial.new()
			material.shader = PAPER_SHADER
			grain.material = material
			root.add_child(grain)
			grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			grain.z_index = 1
	if root is Button:
		button(root)
	if root is ProgressBar:
		root.add_theme_stylebox_override("background", box("disabled", "line"))
		var fill := box("gold", "gold")
		fill.set_content_margin_all(0)
		root.add_theme_stylebox_override("fill", fill)
	for child in root.get_children():
		apply_tree(child)


static func paper_card() -> StyleBoxTexture:
	var cfg := settings()
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/textures/ui/paper/campus-paper-card-v1.png")
	style.content_margin_left = cfg.paper_content_left
	style.content_margin_top = cfg.paper_content_top
	style.content_margin_right = cfg.paper_content_right
	style.content_margin_bottom = cfg.paper_content_bottom
	return style


static func main_menu(view: Control) -> void:
	var cfg := settings()
	view.get_node("ColorRect").hide()
	view.get_node("TopAccent").hide()
	view.get_node("Label").hide()
	view.get_node("Separator").hide()
	var background := TextureRect.new()
	background.name = "CampusBackground"
	background.texture = load("res://assets/promotional/classroom-social-1920x1080-v1.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(background)
	view.move_child(background, 0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var logo := TextureRect.new()
	logo.name = "CampusLogo"
	logo.texture = load("res://assets/logos/xiake-ten-minutes-logo-transparent-v1.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(cfg.logo_x, cfg.logo_y)
	logo.size = Vector2(cfg.logo_width, cfg.logo_height)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(logo)
	var menu: VBoxContainer = view.get_node("VBoxContainer")
	menu.position = Vector2(cfg.menu_x, cfg.menu_y)
	menu.size = Vector2(cfg.menu_width, 0)
	menu.add_theme_constant_override("separation", int(cfg.menu_spacing))
	var panel := Panel.new()
	panel.name = "MenuPaper"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(cfg.menu_paper_x, cfg.menu_paper_y)
	panel.size = Vector2(cfg.menu_paper_width, cfg.menu_paper_height)
	var paper := StyleBoxTexture.new()
	paper.texture = load("res://assets/textures/ui/paper/campus-menu-paper-v1.png")
	panel.add_theme_stylebox_override("panel", paper)
	view.add_child(panel)
	view.move_child(panel, menu.get_index())
	menu.move_child(menu.get_node("Encyclopedia"), 3)
	for item in menu.get_children():
		if item is Button:
			item.custom_minimum_size.y = cfg.menu_button_height
			item.add_theme_font_size_override("font_size", int(cfg.menu_font_size))
			button(item, item.name == "NewGame")
			var menu_font := GameFonts.regular()

			item.add_theme_font_override("font", menu_font)
			var normal := box("paper", "line")
			normal.bg_color.a = 0.2
			normal.shadow_size = 0
			item.add_theme_stylebox_override("normal", normal)
			match str(item.name):
				"NewGame":
					item.text = "新游戏　›"
					item.custom_minimum_size.y = cfg.menu_primary_height
					var brush := StyleBoxTexture.new()
					brush.texture = load("res://assets/textures/ui/paper/campus-menu-brush-v1.png")
					item.add_theme_stylebox_override("normal", brush)
				"ContinueGame":
					item.custom_minimum_size.y = cfg.menu_primary_height
					var disabled_brush := StyleBoxTexture.new()
					disabled_brush.texture = load(
						"res://assets/textures/ui/paper/campus-menu-brush-disabled-v1.png"
					)
					item.add_theme_stylebox_override("disabled", disabled_brush)
				"Setting", "Encyclopedia", "About", "Exit":
					var icon_name: String = {
						"Setting": "settings",
						"Encyclopedia": "study",
						"About": "about",
						"Exit": "exit"
					}[str(item.name)]
					item.icon = load("res://assets/icons/actions/%s.svg" % icon_name)
					item.add_theme_constant_override("icon_max_width", int(cfg.menu_icon_size))
					item.text = {"Setting": "设置", "Encyclopedia": "百科", "About": "关于", "Exit": "退出"}[str(
						item.name
					)]
