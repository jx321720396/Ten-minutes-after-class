extends GutTest
## 办公室声量可选模式的端到端接线（2026-10-19）：
## 设置开 → 按住训斥 → 2.5 秒窗口锁定档位 → 20 秒谈话按倍率结算。
## 麦克风路径不在此测试（需要真实输入设备）；这里覆盖按住与内核接线。

var _was_enabled := false
var _was_mode := "mic"


func before_each() -> void:
	_was_enabled = VoiceSettings.is_enabled()
	_was_mode = VoiceSettings.input_mode()


func after_each() -> void:
	VoiceSettings.set_input_mode(_was_mode)
	VoiceSettings.set_enabled(_was_enabled)


func test_hold_scold_reaches_core_multiplier() -> void:
	var state = get_node("/root/GameState")
	state.start_game(20261019, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	add_child_autofree(room)
	for _frame in range(180):
		if room.has_node("OfficeHub"):
			break
		await get_tree().physics_frame
	if not room.has_node("OfficeHub"):
		fail_test("教室未安装 OfficeHub")
		return
	var hub = room.get_node("OfficeHub")
	var core = state.sim_core
	var commands = core.teacher_commands()
	VoiceSettings.set_enabled(true)
	VoiceSettings.set_input_mode("hold")
	hub.set_mode("office")
	hub.open_tool("summon")
	hub.select_student(0)
	hub._process(0.0)
	var meeting: Control = hub.office_view()._meeting
	var buttons: Dictionary = meeting.get("_buttons")
	core._stress[0] = 10.0
	core._vitality[0] = 10.0
	var flow = room.get_node("TimeFlow")
	flow.set_speed(3.0)
	buttons["scold"].button_down.emit()
	assert_eq(commands.current_command(), "office_chat", "按住开始训斥")
	assert_true(hub._voice_window_active, "声量窗口已开启")
	assert_eq(commands.remaining_seconds(), 10, "声量模式谈话 10 秒")
	hub._process(0.0)
	assert_true(flow._normal_owners.has(&"voice_window"), "采样强制 1× 锁")
	assert_false(flow._fast_forward_owners.has(&"office_chat"), "采样期间释放快进")
	assert_true(meeting.get("_voice_meter").visible, "谈话中显示声量条")
	hub._voice._process(0.3)
	hub._voice._process(5.0)
	assert_eq(int(commands.snapshot()["chat_tier"]), 4, "满窗锁定吼档")
	assert_false(hub._voice_window_active, "锁定后窗口关闭")
	hub._process(0.0)
	assert_false(flow._normal_owners.has(&"voice_window"), "采样结束释放 1× 锁")
	assert_true(flow._fast_forward_owners.has(&"office_chat"), "恢复 4× 快进")
	assert_eq(int(meeting.get("_voice_meter").get("_tier")), 4, "声量条显示吼档")
	for _tick in range(10):
		commands.tick(core)
	assert_almost_eq(core.stress(0), 61.0, 0.001, "吼训斥 +51 压力进入内核")
