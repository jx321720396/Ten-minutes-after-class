extends GutTest
## 设置菜单里的声量开关与警告文案（2026-10-19）。
## 会临时改写 VoiceSettings 的全局偏好，after_each 恢复，避免污染本机设置。

const SETTINGS = preload("res://scenes/ui/settings_menu.tscn")

var _was_enabled := false
var _was_mode := "mic"


func before_each() -> void:
	_was_enabled = VoiceSettings.is_enabled()
	_was_mode = VoiceSettings.input_mode()
	VoiceSettings.set_enabled(false)


func after_each() -> void:
	VoiceSettings.set_input_mode(_was_mode)
	VoiceSettings.set_enabled(_was_enabled)


func test_voice_row_and_warning_copy() -> void:
	var menu: Control = SETTINGS.instantiate()
	add_child_autofree(menu)
	var desc: Label = menu.get("_voice_desc")
	assert_not_null(desc, "设置菜单应创建声量说明")
	assert_string_contains(desc.text, "无法通关", "说明必须提示可能无法通关")
	var scroll: Control = menu.get_node_or_null("Overlay/CenterContainer/Panel/SettingsScroll")
	assert_not_null(scroll, "设置内容应包在可滚动容器里，避免底部被裁切")
	assert_not_null(menu.get("_voice_input_row"), "输入行应存在")
	var confirm: Control = menu.get("_voice_confirm")
	assert_not_null(confirm, "设置菜单应创建二次确认框")
	confirm.open_warning("开启声量模式？", "使用本功能可能无法通关。", "仍然开启")
	assert_true(confirm.visible, "警告框可见")
	assert_string_contains(confirm.msg_label.text, "无法通关", "警告正文重复风险")
	assert_false(confirm.keep_btn.visible, "警告口径不显示保留存档")


func test_toggle_requires_warning_then_enables() -> void:
	var menu: Control = SETTINGS.instantiate()
	add_child_autofree(menu)
	var toggle: Button = menu.get("_voice_toggle")
	var confirm: Control = menu.get("_voice_confirm")
	toggle.button_pressed = true
	toggle.pressed.emit()
	assert_true(confirm.visible, "开启先弹警告")
	assert_false(VoiceSettings.is_enabled(), "确认前不生效")
	confirm.clear_btn.pressed.emit()
	assert_true(VoiceSettings.is_enabled(), "确认后开启")
	assert_eq(toggle.text, "开启")
	assert_false(confirm.visible)


func test_cancel_keeps_mode_off() -> void:
	var menu: Control = SETTINGS.instantiate()
	add_child_autofree(menu)
	var toggle: Button = menu.get("_voice_toggle")
	var confirm: Control = menu.get("_voice_confirm")
	toggle.button_pressed = true
	toggle.pressed.emit()
	confirm.cancel_btn.pressed.emit()
	assert_false(VoiceSettings.is_enabled(), "取消保持关闭")
	assert_false(toggle.button_pressed, "开关回到关闭")
	assert_eq(toggle.text, "关闭")


func test_disable_immediately_turns_off() -> void:
	VoiceSettings.set_enabled(true)
	var menu: Control = SETTINGS.instantiate()
	add_child_autofree(menu)
	var toggle: Button = menu.get("_voice_toggle")
	assert_true(toggle.button_pressed, "读档开启时开关为开")
	toggle.button_pressed = false
	toggle.pressed.emit()
	assert_false(VoiceSettings.is_enabled(), "关闭不需要二次确认")
