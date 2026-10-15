extends GutTest

const NAV_PATH := "res://scripts/ui/study_navigation.gd"

var _ui: Node
var _profile: NpcProfile
var _board: CanvasLayer
var _book: CanvasLayer
var _nav: Node


func before_each() -> void:
	get_tree().paused = false
	_ui = Node.new()
	add_child_autofree(_ui)
	for entry in [
		["NpcProfile", "res://scenes/ui/npc_profile.tscn"],
		["ClueBoardEntry", "res://scenes/ui/clue_board_entry.tscn"],
		["EncyclopediaEntry", "res://scenes/ui/encyclopedia_entry.tscn"]
	]:
		var node: Node = load(entry[1]).instantiate()
		node.name = entry[0]
		_ui.add_child(node)
	_profile = _ui.get_node("NpcProfile")
	_board = _ui.get_node("ClueBoardEntry")
	_book = _ui.get_node("EncyclopediaEntry")
	var core := SimCore.new(12345, 16)
	_profile.bind_sources(core, null, null)
	_board.bind_sources(core, null, null)
	if ResourceLoader.exists(NAV_PATH):
		_nav = load(NAV_PATH).new()
		_ui.add_child(_nav)
		_nav.bind_sources(core)


func after_each() -> void:
	_profile.close()
	_board.close()
	_book.close()
	get_tree().paused = false
	_nav = null


func test_all_six_routes_keep_one_window_and_resume_on_close() -> void:
	assert_not_null(_nav, "应有三个资料界面的互通导航")
	if _nav == null:
		return
	_profile.open_profile(1)
	var before: Dictionary = _profile._model.state.duplicate(true)
	_board.record_observed_event({"kind": "chat", "i": 0, "j": 1}, {"day": 1, "global_tick": 1})
	for route in [
		[_profile, _board, "OpenBoard"],
		[_board, _book, "OpenEncyclopedia"],
		[_book, _profile, "OpenProfile"],
		[_profile, _book, "OpenEncyclopedia"],
		[_book, _board, "OpenBoard"],
		[_board, _profile, "OpenProfile"]
	]:
		var source: Node = (
			_profile.get_node("Root")
			if route[0] == _profile
			else route[0].get_child(route[0].get_child_count() - 1)
		)
		var button: Button = source.find_child(route[2], true, false)
		assert_not_null(button)
		if button == null:
			return
		button.pressed.emit()
		assert_false(route[0].is_open(), "离开的界面应关闭")
		assert_true(route[1].is_open(), "目标界面应显示")
		assert_true(get_tree().paused, "查看资料始终暂停")
	assert_eq(_profile.selected_index(), 1, "跨界面保留当前人物")
	assert_eq(_board.get_node("Board").displayed_page().events.size(), 1, "互通不清除当天观察")
	assert_eq(_profile._model.state, before, "导航不改写档案笔记")
	_profile.close()
	assert_false(get_tree().paused, "最后一个窗口关闭后恢复游戏")


func test_board_roster_opens_chosen_person_and_keeps_external_pause() -> void:
	assert_not_null(_nav)
	if _nav == null:
		return
	get_tree().paused = true
	_board.open()
	var picker: OptionButton = _board.get_node("Board").find_child("StudyPerson", true, false)
	assert_not_null(picker)
	if picker == null:
		return
	var item := picker.get_item_index(2)
	picker.select(item)
	picker.item_selected.emit(item)
	_board.get_node("Board").find_child("OpenProfile", true, false).pressed.emit()
	assert_eq(_profile.selected_index(), 2, "按人物栏选择打开对应资料")
	_profile.get_node("Root").find_child("OpenEncyclopedia", true, false).pressed.emit()
	_book.close()
	assert_true(get_tree().paused, "不能释放其他来源持有的暂停")


func test_native_scene_navigation_has_no_drawing_input() -> void:
	_board.open()
	var board: Control = _board.get_node("Board")
	assert_not_null(board.find_child("OpenProfile", true, false))
	assert_false(board.has_method("_input"), "推理板不再把按钮触摸当作画笔")
	assert_eq(board.get_node("Design/Graph/Cards").get_child_count(), 16)
