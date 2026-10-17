extends GutTest

## confirm_dialog 回归（2026-10-18 起单一口径）。
## · open()：「检测到存档」三键，警示红按钮；**无存档不再经过本面板**。
## · 主菜单：有存档才弹面板；无存档点「新游戏」直接开局。
## · 信号链不变：confirmed_clear / confirmed_keep / cancelled，Esc 走 cancelled。

const CONFIRM = preload("res://scenes/ui/confirm_dialog.tscn")
const MAIN_MENU = preload("res://scenes/ui/main_menu.tscn")


func _dialog() -> Control:
	var d: Control = CONFIRM.instantiate()
	add_child_autofree(d)
	return d


func test_open_shows_archive_three_buttons() -> void:
	var d := _dialog()
	d.open()
	assert_true(d.visible, "open 后面板可见")
	assert_eq(d.title_label.text, "检测到存档")
	assert_eq(d.clear_btn.text, "清除存档并开始")
	assert_true(d.keep_btn.visible, "「保留存档」键显示")
	assert_true(d.cancel_btn.visible, "「取消」键显示")
	assert_true(d.clear_btn.has_theme_color_override("font_color"), "警示红沿用场景样式")


func test_confirm_and_cancel_signal_chain() -> void:
	var d := _dialog()
	d.open()
	var fired := {"clear": false, "cancel": false}
	d.confirmed_clear.connect(func() -> void: fired["clear"] = true)
	d.cancelled.connect(func() -> void: fired["cancel"] = true)
	d.clear_btn.pressed.emit()
	assert_true(fired["clear"], "清除存档 -> confirmed_clear")
	d.cancel_btn.pressed.emit()
	assert_true(fired["cancel"], "取消 -> cancelled")


func test_keep_signal_still_available() -> void:
	var d := _dialog()
	d.open()
	var fired := {"keep": false}
	d.confirmed_keep.connect(func() -> void: fired["keep"] = true)
	d.keep_btn.pressed.emit()
	assert_true(fired["keep"], "保留存档 -> confirmed_keep")


func test_main_menu_new_game_flow_matches_save_state() -> void:
	# 自适应本机真实存档状态（Save 是 autoload，无法打桩，只能顺着真实存档状态分支）。
	# 老师版无选角色；_start_new_game 打桩防测试真切场景。
	var menu: Control = partial_double(MAIN_MENU).instantiate()
	add_child_autofree(menu)
	stub(menu, "_start_new_game").to_do_nothing()
	(menu.get_node("VBoxContainer/NewGame") as Button).pressed.emit()
	if Save.has_save():
		assert_true(menu.confirm_dialog.visible, "有存档先弹确认面板")
		assert_eq(menu.confirm_dialog.title_label.text, "检测到存档")
		assert_true(menu.confirm_dialog.keep_btn.visible, "三键口径")
		menu.confirm_dialog.cancel_btn.pressed.emit()
		assert_false(menu.confirm_dialog.visible, "取消后面板收起")
		assert_not_called(menu, "_start_new_game")
	else:
		assert_false(menu.confirm_dialog.visible, "无存档不再弹确认面板")
		assert_called(menu, "_start_new_game")
