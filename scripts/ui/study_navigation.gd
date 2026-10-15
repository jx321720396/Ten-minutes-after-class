extends Node
## 资料窗口之间的导航；只传人物索引，不读取或改写隐藏关系。

const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const GameFonts := preload("res://scripts/ui/game_fonts.gd")
const COPY_PATH := "res://data/localization/study_navigation.json"

@onready var _profile: NpcProfile = get_node("../NpcProfile")
@onready var _board: CanvasLayer = get_node("../ClueBoardEntry")
@onready var _book: CanvasLayer = get_node("../EncyclopediaEntry")

var _core: Variant
var _person := -1
var _picker: OptionButton
var _profile_buttons: Array[Button] = []
var _copy: Dictionary
var _cfg: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_copy = JSON.parse_string(FileAccess.get_file_as_string(COPY_PATH))
	_cfg = CampusTheme.settings().study_navigation
	_build_profile_links()
	_build_book_links()
	_build_board_links()
	_profile.closed.connect(_remember_person)


func bind_sources(core: Variant) -> void:
	_core = core
	_picker.clear()
	for index in range(int(core.node_count())):
		_picker.add_item(str(core.alias(index)), index)
	_person = _picker.get_selected_id() if _picker.item_count > 0 else -1
	for button in _profile_buttons:
		button.disabled = _person < 0


func _build_profile_links() -> void:
	_profile.tool_requested.connect(_switch)
	for key in ["OpenBoard", "OpenEncyclopedia"]:
		_profile.get_node("%" + key).disabled = false


func _build_book_links() -> void:
	var footer := _book.get_node("Encyclopedia/CenterContainer/Panel/Margin/VBox/Footer")
	for destination in ["profile", "board"]:
		var button := _add_button(footer, destination)
		footer.move_child(button, footer.get_node("Mid").get_index())


func _build_board_links() -> void:
	var board := _board.get_node("Board")
	_picker = board.get_node("Design/StudyPerson")
	_picker.item_selected.connect(_on_person_selected)
	board.person_selected.connect(_on_board_person)
	for destination in ["profile", "encyclopedia"]:
		var button: Button = board.get_node("Design/" + str(_copy[destination].node_name))
		button.pressed.connect(_switch.bind(destination))
		if destination == "profile":
			_profile_buttons.append(button)


func _on_board_person(index: int) -> void:
	var item := _picker.get_item_index(index)
	if item >= 0:
		_picker.select(item)
		_on_person_selected(item)


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
	var item := _picker.get_item_index(index)
	if item >= 0:
		_person = index
		_picker.select(item)


func _on_person_selected(item: int) -> void:
	_person = _picker.get_item_id(item)


func _switch(destination: String) -> void:
	if _profile.is_open():
		_remember_person()
	if destination == "profile" and (_core == null or _person < 0):
		return
	# 先释放来源窗口自己的暂停，再由目标窗口接管；同一回调内无模拟帧推进。
	_profile.close()
	_board.close()
	_book.close()
	match destination:
		"profile":
			_profile.open_profile(_person)
		"board":
			_board.open()
		"encyclopedia":
			_book.open()
