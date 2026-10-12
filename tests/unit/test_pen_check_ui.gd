extends GutTest


func _hud() -> ChatFeedbackHUD:
	var hud := ChatFeedbackHUD.new()
	add_child_autofree(hud)
	return hud


func _packet(accepted: bool = true, probability: float = 0.72) -> Dictionary:
	return {"mode": "join", "request_id": 42, "accepted": accepted, "p_belief": probability}


func test_ready_waits_for_click_and_spin_waits_for_second_click() -> void:
	var hud := _hud()
	hud.present_locked_result(_packet())
	watch_signals(hud)
	await wait_seconds(1.6)
	assert_eq(hud.revealed_request_id(), -1)
	var button: Button = hud.get_node("PenCard/Column/PenButton")
	assert_eq(button.text, "开始转笔")
	button.pressed.emit()
	await wait_seconds(1.6)
	assert_eq(hud.revealed_request_id(), -1)
	assert_eq(button.text, "停下揭晓")
	button.pressed.emit()
	button.pressed.emit()
	await wait_seconds(0.4)
	assert_eq(hud.revealed_request_id(), 42)
	assert_signal_emit_count(hud, "result_revealed", 1)
	assert_eq(button.text, "继续")
	button.pressed.emit()
	assert_false(hud.get_node("PenCard").visible)


func test_probability_is_belief_and_rejection_uses_locked_result() -> void:
	var hud := _hud()
	hud.present_locked_result(_packet(false, 0.9))
	var wheel = hud.get_node("PenCard/Column/Spinner")
	assert_almost_eq(wheel.probability, 0.9, 0.001)
	var button: Button = hud.get_node("PenCard/Column/PenButton")
	button.pressed.emit()
	button.pressed.emit()
	await wait_seconds(0.4)
	assert_eq(hud.get_node("PenCard/Column/Result").text, "✕ 对方婉拒了")


func test_clear_releases_result_pause_and_zero_full_probabilities_are_valid() -> void:
	var hud := _hud()
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	hud.bind_clock(clock)
	for probability in [0.0, 1.0]:
		hud.present_locked_result(_packet(true, probability))
		var button: Button = hud.get_node("PenCard/Column/PenButton")
		button.pressed.emit()
		button.pressed.emit()
		await wait_seconds(0.4)
		assert_true(clock.is_paused())
		hud.clear()
		assert_false(clock.is_paused())
