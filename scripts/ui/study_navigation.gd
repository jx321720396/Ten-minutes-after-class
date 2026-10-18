extends Node
## 资料窗口之间的导航；只传人物索引，不读取或改写隐藏关系。

const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const GameFonts := preload("res://scripts/ui/game_fonts.gd")
const COPY_PATH := "res://data/localization/study_navigation.json"

@onready var _profile: NpcProfile = get_node("../NpcProfile")
@onready var _book: CanvasLayer = get_node("../EncyclopediaEntry")

var _core: Variant
var _person := -1
var _profile_buttons: Array[Button] = []
var _copy: Dictionary
var _cfg: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_copy = JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH))
	_cfg = CampusTheme.settings().study_navigation
	_build_profile_links()
	_build_book_links()
	_profile.closed.connect(_remember_person)


func bind_sources(core: Variant) -> void:
	_core = core
	for button in _profile_buttons:
		button.disabled = core == null


func _build_profile_links() -> void:
	_profile.tool_requested.connect(_switch)
	for key in ["OpenEncyclopedia"]:
		_profile.get_node("%" + key).disabled = false


func _build_book_links() -> void:
	var footer := _book.get_node("Encyclopedia/CenterContainer/Panel/Margin/VBox/Footer")
	var button := _add_button(footer, "profile")
	footer.move_child(button, footer.get_node("Mid").get_index())


func _add_button(row: Node, destination: String) -> Button:
	var button := Button.new()
	button.name = str(_copy[destination].node_name)
	button.text = str(_copy[destination].text)
	button.icon = load(str(_copy[destination].icon))
	_style_button(button)
	row.add_child(button)
	button.pressed.connect(_switch.bind(destination))
	if destination == "profile":
		button.disabled = true
		_profile_buttons.append(button)
	return button


func _style_button(button: Button) -> void:
	CampusTheme.button(button)
	button.add_theme_font_override("font", GameFonts.regular())
	button.add_theme_font_size_override("font_size", int(_cfg.font_size))
	button.add_theme_constant_override("icon_max_width", int(_cfg.icon_size))
	for state in ["normal", "hover", "focus"]:
		button.add_theme_color_override(
			"icon_" + state + "_color", Color(CampusTheme.settings().ink)
		)
	button.add_theme_color_override("icon_pressed_color", Color(CampusTheme.settings().paper))
	button.custom_minimum_size.y = float(_cfg.height)
	button.focus_mode = Control.FOCUS_NONE


func _remember_person() -> void:
	var index := _profile.selected_index()
	if index >= 0:
		_person = index


func _switch(destination: String) -> void:
	if _profile.is_open():
		_remember_person()
	if destination == "profile" and (_core == null or _person < 0):
		return
	# 先释放来源窗口自己的暂停，再由目标窗口接管；同一回调内无模拟帧推进。
	_profile.close()
	_book.close()
	match destination:
		"profile":
			_profile.open_profile(_person)
		"encyclopedia":
			_book.open()
