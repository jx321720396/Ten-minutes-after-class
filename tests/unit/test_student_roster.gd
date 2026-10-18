extends GutTest

const ROSTER = preload("res://scripts/ui/student_roster.gd")


func test_roster_uses_real_portraits_and_requires_confirmation_before_swap() -> void:
	var core := SimCore.new(20261018, 16, ConfigLoader.new().load_all())
	var roster = ROSTER.new()
	add_child_autofree(roster)
	roster.open(core, "profile")
	await get_tree().process_frame
	assert_eq(roster.cards.size(), 16)
	assert_eq(roster.grid.columns, 4)
	for card in roster.cards:
		assert_not_null(card.get_node("Portrait").texture)
	roster.set_mode("seats")
	await get_tree().process_frame
	watch_signals(roster)
	roster.select_student(0)
	roster.select_student(1)
	assert_signal_not_emitted(roster, "seat_requested")
	assert_false(roster.confirm.disabled)
	roster.confirm.pressed.emit()
	assert_signal_emitted_with_parameters(roster, "seat_requested", [0, 1])
	assert_eq(core.teacher_commands().current_command(), "", "View emits intent only")
	roster.clear_selection()
	assert_true(roster.confirm.disabled)
	roster.select_student(0)
	roster.select_student(0)
	assert_true(roster.confirm.disabled, "Same student cannot occupy both selections")
	roster.clear_selection()
	var card: Button = roster.cards[0]
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = card.size / 2.0
	down.pressed = true
	card.gui_input.emit(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = down.position
	card.gui_input.emit(up)
	assert_eq(
		roster.get("_first"), int(card.get_meta("student_index")), "Native touch selects seat"
	)


func test_roster_follows_changed_seats_instead_of_character_order() -> void:
	var core := SimCore.new(20261018, 16, ConfigLoader.new().load_all())
	var commands := core.teacher_commands()
	var original_first := str(core.seat_of(0))
	var original_second := str(core.seat_of(1))
	assert_true(commands.start_seat_change(core, 0, 1))
	for tick in range(10):
		commands.tick(core)
	var roster = ROSTER.new()
	add_child_autofree(roster)
	roster.open(core, "profile")
	for card in roster.cards:
		var index := int(card.get_meta("student_index"))
		if index == 0:
			assert_eq(str(core.seat_of(index)), original_second)
		if index == 1:
			assert_eq(str(core.seat_of(index)), original_first)
	for slot in range(roster.cards.size()):
		var index := int(roster.cards[slot].get_meta("student_index"))
		assert_eq(str(core.seat_of(index)), "P%d" % (slot + 1))


func test_fullscreen_panels_and_roster_controls_fit_phone_aspect_ratios() -> void:
	var core := SimCore.new(20261018, 16, ConfigLoader.new().load_all())
	for dimensions in [Vector2i(1280, 720), Vector2i(2400, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		add_child_autofree(viewport)
		var roster = ROSTER.new()
		viewport.add_child(roster)
		roster.open(core, "seats")
		for frame in range(4):
			await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		assert_true(bounds.encloses(roster.confirm.get_global_rect()), "Confirm stays on screen")
		for card in roster.cards:
			assert_true(bounds.encloses(card.get_global_rect()), "All 16 seats stay on screen")
		roster.hide()
		for scene in ["encyclopedia", "settings_menu", "about_menu", "confirm_dialog"]:
			var screen = load("res://scenes/ui/" + scene + ".tscn").instantiate()
			viewport.add_child(screen)
			for frame in range(4):
				await get_tree().process_frame
			var panel: Control = screen.find_child("Panel", true, false)
			assert_almost_eq(panel.get_global_rect().size.x, float(dimensions.x), 1.0, scene)
			assert_almost_eq(panel.get_global_rect().size.y, float(dimensions.y), 1.0, scene)
			screen.hide()
		for script in ["class_overview_card", "attention_card"]:
			var card = load("res://scripts/ui/" + script + ".gd").new()
			viewport.add_child(card)
			for frame in range(4):
				await get_tree().process_frame
			var panel: Control = card.get("_detail_panel")
			assert_almost_eq(panel.get_global_rect().size.x, float(dimensions.x), 1.0, script)
			assert_almost_eq(panel.get_global_rect().size.y, float(dimensions.y), 1.0, script)
