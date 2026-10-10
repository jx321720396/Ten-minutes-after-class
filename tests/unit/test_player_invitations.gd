extends GutTest
## 玩家接受或拒绝邀请，等待回应不占用、不结算，也不代替玩家掷骰。


func _core() -> SimCore:
	var core := SimCore.from_npc(12345, 16, ConfigLoader.new().load_all())
	core.set_interaction_geometry([], Rect2(-10, -10, 20, 20))
	for i in range(core.node_count()):
		core._sleeping[i] = false
		core._busy_until[i] = 0
		core._current_act[i] = null
		core.set_position(i, 0, 0)
	return core


func _api(core: SimCore) -> bool:
	var ready := (
		core.has_method("get_player_invitation") and core.has_method("respond_player_invitation")
	)
	assert_true(ready, "内核提供玩家邀请与回应入口")
	return ready


func test_npc_chat_waits_for_player_without_effects_or_occupancy() -> void:
	var core := _core()
	var me := core.node_count() - 1
	var before := core.affinity(me, 0)
	core._do_chat(0, me)
	assert_false(core.is_busy(me), "邀请不锁移动")
	assert_false(core.is_busy(0), "等待回应不占用 NPC")
	assert_eq(core.session_of(me), -1)
	assert_eq(core.affinity(me, 0), before, "接受前不结算")
	if _api(core):
		assert_eq(str(core.get_player_invitation().kind), "chat")


func test_accepting_help_is_a_player_choice_even_at_low_npc_probability() -> void:
	var core := _core()
	if not _api(core):
		return
	var me := core.node_count() - 1
	core._a[me * core.node_count()] = 0.0
	core._dims[me] = 0.0
	core._do_ask_help(0, me)
	var invitation: Dictionary = core.get_player_invitation()
	assert_false(core.is_busy(me))
	var result: Dictionary = core.respond_player_invitation(int(invitation.id), true)
	assert_true(bool(result.ok))
	assert_true(bool(result.accepted))
	assert_eq(int(core._stats.helps), 1, "玩家接受直接进入成功分支")
	assert_true(core.is_busy(me))
	assert_true(core.get_player_invitation().is_empty())


func test_rejecting_chat_and_replaying_response_does_not_lock_or_settle() -> void:
	var core := _core()
	if not _api(core):
		return
	var me := core.node_count() - 1
	core._do_chat(0, me)
	var id := int(core.get_player_invitation().id)
	var before := core.affinity(me, 0)
	var result: Dictionary = core.respond_player_invitation(id, false)
	assert_true(bool(result.ok))
	assert_false(bool(result.accepted))
	assert_false(core.is_busy(me))
	assert_eq(core.affinity(me, 0), before)
	core.respond_player_invitation(id, true)
	assert_false(core.is_busy(me), "重复回应不能把拒绝改为参加")
	assert_eq(core.session_of(me), -1)


func test_expired_or_out_of_range_invitation_cannot_be_accepted() -> void:
	for expired in [true, false]:
		var core := _core()
		if not _api(core):
			return
		var me := core.node_count() - 1
		core._do_chat(0, me)
		var invitation: Dictionary = core.get_player_invitation()
		if expired:
			core._global_tick = int(invitation.expires_tick)
		else:
			core.set_position(me, 8, 8)
		var result: Dictionary = core.respond_player_invitation(int(invitation.id), true)
		assert_false(bool(result.ok), "接受时再次检查时间与距离")
		assert_false(core.is_busy(me))
		assert_eq(core.session_of(me), -1)


func test_npc_to_npc_chat_and_player_initiated_chat_keep_existing_rules() -> void:
	var core := _core()
	core._do_chat(0, 1)
	assert_true(core.is_busy(0))
	assert_eq(core.session_of(0), core.session_of(1))
	if not _api(core):
		return
	assert_true(core.get_player_invitation().is_empty())
	var me := core.node_count() - 1
	core._do_chat(me, 2)
	assert_true(core.is_busy(me), "玩家主动发起不需要自己批准自己")
	assert_true(core.get_player_invitation().is_empty())


func test_invitation_card_can_reject_without_blocking_player() -> void:
	var core := _core()
	if not _api(core):
		return
	var hud := ChatFeedbackHUD.new()
	add_child_autofree(hud)
	hud.bind_core(core)
	var me := core.node_count() - 1
	core._do_chat(0, me)
	hud._process(0.0)
	assert_true(hud._invitation_card.visible)
	assert_false(core.is_busy(me))
	hud._invitation_reject.pressed.emit()
	hud._process(0.0)
	assert_false(hud._invitation_card.visible)
	assert_false(core.is_busy(me))


func test_all_cooperative_behaviors_wait_for_consent() -> void:
	for kind in ["chat", "ask_help", "comfort", "apologize", "roughhouse"]:
		var core := _core()
		var me := core.node_count() - 1
		var before := core.affinity(me, 0)
		var stress := core.stress(me)
		var random_state: Variant = core._rng._mt.duplicate()
		var random_index: int = core._rng._mti
		core._behavior_registry.execute(StringName(kind), 0, me, {"bystanders": [1, 2, 3]})
		assert_eq(str(core.get_player_invitation().kind), kind)
		assert_false(core.is_busy(me), kind + " 不得在回应前占用")
		assert_eq(core.affinity(me, 0), before)
		assert_eq(core.stress(me), stress)
		core.get_player_invitation()
		assert_eq(core._rng._mt, random_state, "邀请与查询不消耗随机数")
		assert_eq(core._rng._mti, random_index)


func test_npc_joining_player_chat_requires_player_approval() -> void:
	for accept in [true, false]:
		var core := _core()
		var me := core.node_count() - 1
		core._do_chat(me, 0)
		var sid := core.session_of(me)
		core._do_chat_join(1, 0)
		var invitation: Dictionary = core.get_player_invitation()
		assert_eq(str(invitation.kind), "chat")
		assert_eq(core.session_of(1), -1, "玩家批准前 NPC 不进入玩家会话")
		var result: Dictionary = core.respond_player_invitation(int(invitation.id), accept)
		assert_true(bool(result.ok))
		assert_eq(core.session_of(1), sid if accept else -1)
		assert_eq(core.session_of(me), sid, "拒绝不破坏玩家原会话")


func test_external_harm_does_not_force_player_activity() -> void:
	var core := _core()
	var me := core.node_count() - 1
	core._do_exclude(0, me, [1, 2, 3])
	assert_false(core.is_busy(me), "被排挤不等于玩家选择参与活动")
	assert_eq(core.activity_of(me), "")
	assert_true(core.get_player_invitation().is_empty(), "外部伤害不伪装成邀请")
