extends GutTest


func test_non_chat_actions_display_progress_from_busy_ticks() -> void:
	var core := _core()
	var me := core.node_count() - 1
	var hud := ChatFeedbackHUD.new()
	add_child_autofree(hud)
	hud.bind_core(core)
	for kind in ["study", "roughhouse"]:
		core._busy_act[me] = kind
		core._busy_until[me] = core.global_tick() + 10
		core._busy_phase[me] = core._phase_index
		hud._process(0.0)
		assert_true(hud._progress_bar.visible, kind)
		assert_gte(hud.progress_percent(), 0.0)
		assert_lte(hud.progress_percent(), 100.0)


## 玩家不会被 NPC 决策自动安排睡觉；被动活动必须能在界面看见。


func _core() -> SimCore:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	core.set_interaction_geometry([], Rect2(-10, -10, 20, 20))
	for i in range(core.node_count()):
		core._sleeping[i] = false
		core._busy_until[i] = 0
		core._current_act[i] = null
		core.set_position(i, 0, 0)
	return core


func test_random_sleep_only_decides_for_npcs() -> void:
	var core := _core()
	var me := core.node_count() - 1
	core._probs["sleep"] = 100.0
	core._roll_sleep()
	assert_true(core._sleeping[0], "NPC 仍可以自主睡觉")
	assert_false(core._sleeping[me], "玩家不参加随机睡觉判定")
	assert_false(core.is_busy(me), "玩家不会被随机锁住整段课间")


func test_disabled_roam_does_not_start_a_batch_at_phase_boundary() -> void:
	var roam = load("res://scripts/game/classroom_roam.gd").new()
	autofree(roam)
	roam.enabled = false
	roam._core = _core()
	roam._actor_count = 0
	roam._on_phase_changed({"kind": "break"})
	assert_eq(roam._batch_count, 0, "禁用走动后绑定时钟也不能隐式启动第一批")


func test_passive_chat_shows_activity_and_clears_after_completion() -> void:
	var core := _core()
	var me := core.node_count() - 1
	var hud := ChatFeedbackHUD.new()
	add_child_autofree(hud)
	hud.bind_core(core)
	core._do_chat(0, me)
	assert_false(core.is_busy(me), "NPC 先发邀请，等待回应不占用玩家")
	core.respond_player_invitation(int(core.get_player_invitation().id), true)
	assert_true(core.is_busy(me), "玩家接受后才占用")
	hud._process(0.0)
	assert_true(hud._progress_card.visible, "没有玩家请求也必须显示被动聊天")
	assert_string_contains(hud._progress_text.text, "聊天")
	assert_string_contains(hud._progress_text.text, "秒")
	core._global_tick = int(core._busy_until[me])
	core._settle_finished_actions()
	hud._process(0.0)
	assert_false(core.is_busy(me))
	assert_string_contains(hud._progress_text.text, "可以移动")


func test_active_countdown_tracks_extended_session() -> void:
	var core := _core()
	var me := core.node_count() - 1
	core._do_chat(0, me)
	core.respond_player_invitation(int(core.get_player_invitation().id), true)
	var sid := core.session_of(me)
	var end_tick := int(core._busy_until[me])
	var hud := ChatFeedbackHUD.new()
	add_child_autofree(hud)
	hud.bind_core(core)
	hud.show_active({"mode": "start", "session_id": sid, "end_tick": end_tick})
	core._sessions.extend(sid, end_tick + 10)
	assert_eq(hud.remaining_seconds(), float(end_tick + 10 - core.global_tick()), "会话延长不能留下过期倒计时")
