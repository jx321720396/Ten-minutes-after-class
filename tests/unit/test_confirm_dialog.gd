extends GutTest

## confirm_dialog 双口径回归（2026-10-13，2026-10-17 起主菜单只在有存档时调用）。
## · open(true)：「检测到存档」三键，警示红按钮；
## · open(false)：「开始新游戏？」两键，隐藏「保留存档」，确定键墨色（组件保留能力）；
## · 信号链不变：confirmed_clear / confirmed_keep / cancelled，Esc 走 cancelled。

const CONFIRM = preload("res://scenes/ui/confirm_dialog.tscn")
const MAIN_MENU = preload("res://scenes/ui/main_menu.tscn")


func _dialog() -> Control:
	var d: Control = CONFIRM.instantiate()
	add_child_autofree(d)
	return d


func test_open_without_save_shows_plain_confirm() -> void:
	var d := _dialog()
	d.open(false)
	assert_true(d.visible, "open 后面板可见")
	assert_eq(d.title_label.text, d.FRESH_TITLE, "无存档标题换口径")
	assert_eq(d.msg_label.text, d.FRESH_MSG)
	assert_eq(d.clear_btn.text, d.FRESH_OK, "主按钮显示「确定」")
	assert_false(d.keep_btn.visible, "无存档不显示「保留存档」键")
	assert_true(d.cancel_btn.visible, "取消键保留")


func test_open_with_save_keeps_archive_three_buttons() -> void:
	var d := _dialog()
	d.open(false)  # 先切到无存档口径，再切回，验证口径可反复切换
	d.open(true)
	assert_eq(d.title_label.text, "检测到存档", "有存档维持原标题")
	assert_eq(d.clear_btn.text, "清除存档并开始")
	assert_true(d.keep_btn.visible, "保留存档键恢复显示")
	assert_false(d.clear_btn.has_theme_color_override("font_color"), "警示红回落到场景样式")


func test_confirm_and_cancel_signal_chain() -> void:
	var d := _dialog()
	d.open(false)
	watch_signals(d)
	d.clear_btn.pressed.emit()
	assert_signal_emitted(d, "confirmed_clear", "确定 → confirmed_clear")
	d.cancel_btn.pressed.emit()
	assert_signal_emitted(d, "cancelled", "取消 → cancelled")


func test_keep_signal_still_available_in_save_mode() -> void:
	var d := _dialog()
	d.open(true)
	watch_signals(d)
	d.keep_btn.pressed.emit()
	assert_signal_emitted(d, "confirmed_keep", "保留存档 → confirmed_keep")


func test_main_menu_new_game_flow_matches_save_state() -> void:
	# 自适应本机真实存档状态（Save 是 autoload，无法打桩，只能顺着真实存档状态分支）。
	# 2026-10-17：无存档不再弹「开始新游戏？」确认，点「新游戏」直接开局；
	# 有存档仍弹三键，取消留在主菜单。_start_new_game 打桩防测试真切场景。
	var menu: Control = partial_double(MAIN_MENU).instantiate()
	add_child_autofree(menu)
	stub(menu, "_start_new_game").to_do_nothing()
	(menu.get_node("VBoxContainer/NewGame") as Button).pressed.emit()
	if Save.has_save():
		assert_true(menu.confirm_dialog.visible, "有存档仍先弹确认面板")
		assert_eq(menu.confirm_dialog.title_label.text, "检测到存档")
		assert_true(menu.confirm_dialog.keep_btn.visible, "有存档维持三键口径")
		menu.confirm_dialog.cancel_btn.pressed.emit()  # 只取消，不动真实存档
		assert_false(menu.confirm_dialog.visible, "取消后面板收起")
		assert_not_called(menu, "_start_new_game")
	else:
		assert_false(menu.confirm_dialog.visible, "无存档不再弹确认面板")
		assert_called(menu, "_start_new_game")  # 直接开局，不再进性别选择
