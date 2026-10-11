extends RefCounted
## 校园纸面主题。只处理控件外观，不读取或修改玩法状态。

const SETTINGS := "res://data/ui/campus_theme.json"
const PAPER_SHADER := preload("res://assets/shaders/ui_paper.gdshader")


static func settings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))


static func utility_button(view: Button, slot: int) -> void:
	var cfg := settings()
	button(view, true)
	var normal := box("teal", "paper")
	normal.set_border_width_all(2)
	view.add_theme_stylebox_override("normal", normal)
	view.add_theme_font_size_override("font_size", int(cfg.utility_font_size))
	view.icon = load(
		"res://assets/icons/actions/%s.svg" % ("board" if slot == 0 else "encyclopedia")
	)
	view.add_theme_constant_override("icon_max_width", int(cfg.utility_icon_size))
	view.custom_minimum_size = Vector2(cfg.utility_width, cfg.utility_height)
	view.anchor_left = 1.0
	view.anchor_right = 1.0
	view.anchor_top = 1.0
	view.anchor_bottom = 1.0
	view.offset_right = -cfg.utility_margin - slot * (cfg.utility_width + cfg.utility_gap)
	view.offset_left = view.offset_right - cfg.utility_width
	view.offset_bottom = -cfg.utility_margin
	view.offset_top = view.offset_bottom - cfg.utility_height


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
	panel.position = menu.position - Vector2(cfg.margin, cfg.margin)
	panel.size = Vector2(
		cfg.menu_width + cfg.margin * 2,
		cfg.menu_button_height * 6 + cfg.menu_spacing * 5 + cfg.margin * 2
	)
	panel.add_theme_stylebox_override("panel", box("paper", "line"))
	view.add_child(panel)
	view.move_child(panel, menu.get_index())
	for item in menu.get_children():
		if item is Button:
			item.custom_minimum_size.y = cfg.menu_button_height
			item.add_theme_font_size_override("font_size", int(cfg.font_size) + 8)
			button(item, item.name == "NewGame")
