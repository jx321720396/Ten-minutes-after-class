extends GutTest


func test_restyled_menu_opens_and_closes_existing_panels() -> void:
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child_autofree(menu)
	for entry in [
		["Setting", "settings_panel"],
		["Encyclopedia", "encyclopedia_panel"],
		["About", "about_panel"]
	]:
		var button: Button = menu.get_node("VBoxContainer/" + entry[0])
		var panel: Control = menu.get(entry[1])
		assert_false(panel.visible)
		button.pressed.emit()
		assert_true(panel.visible, entry[0] + "仍打开原有功能")
		panel.closed.emit()
		assert_false(panel.visible)
	assert_eq(menu.continue_btn.disabled, not Save.has_save())
