extends GutTest

const NAV_PATH := "res://scripts/ui/study_navigation.gd"

var _ui: Node
var _profile: NpcProfile
var _book: CanvasLayer
var _nav: Node


func before_each() -> void:
	get_tree().paused = false
	_ui = Node.new()
	add_child_autofree(_ui)
	for entry in [
		["NpcProfile", "res://scenes/ui/npc_profile.tscn"],
		["EncyclopediaEntry", "res://scenes/ui/encyclopedia_entry.tscn"]
	]:
		var node: Node = load(entry[1]).instantiate()
		node.name = entry[0]
		_ui.add_child(node)
	_profile = _ui.get_node("NpcProfile")
	_book = _ui.get_node("EncyclopediaEntry")
	var core := SimCore.new(12345, 16)
	_profile.bind_sources(core, null, null)
	if ResourceLoader.exists(NAV_PATH):
		_nav = load(NAV_PATH).new()
		_ui.add_child(_nav)
		_nav.bind_sources(core)


func after_each() -> void:
	_profile.close()
	_book.close()
	get_tree().paused = false
	_nav = null


func test_profile_and_encyclopedia_switch_both_ways() -> void:
	assert_not_null(_nav, "应有档案与百科的互通导航")
	if _nav == null:
		return
	_profile.open_profile(1)
	var before: Dictionary = _profile._model.state.duplicate(true)
	_profile.get_node("Root").find_child("OpenEncyclopedia", true, false).pressed.emit()
	assert_false(_profile.is_open(), "离开的界面应关闭")
	assert_true(_book.is_open(), "目标界面应显示")
	var footer := _book.get_node("Encyclopedia/CenterContainer/Panel/Margin/VBox/Footer")
	footer.find_child("OpenProfile", true, false).pressed.emit()
	assert_false(_book.is_open(), "离开的界面应关闭")
	assert_true(_profile.is_open(), "目标界面应显示")
	assert_eq(_profile.selected_index(), 1, "跨界面保留当前人物")
	assert_eq(_profile._model.state, before, "导航不改写档案笔记")
	_profile.close()
	assert_false(get_tree().paused, "最后一个窗口关闭后恢复游戏")
