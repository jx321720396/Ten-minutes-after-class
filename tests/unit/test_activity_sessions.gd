extends GutTest
## 真实共同活动（ActivitySessions）与「完成 / 中断」语义单测。
##
## 依据：主文档 §10.31（所有活动都可加入）、§10.4（行为耗时）；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §5.1、§5.3。
##
## 覆盖：两场同为 chat 的人不是一场、quiet 成员仍在正确会话、重复通知不重复建场、
##      一人不能同时在两场互斥活动、extend 只延长不缩短、快照是深拷贝、
##      到期与中断互斥、最后一 tick 到期后切段仍算完成。

const SEED := 12345
const NPC := 8
const CHAT_DURATION := 30


func _core() -> SimCore:
	return SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())


# ------------------------------------------------------------------ ActivitySessions 本体


func test_two_chat_pairs_are_two_sessions() -> void:
	var sessions := ActivitySessions.new()
	var first := sessions.begin("chat", [0, 1], 100)
	var second := sessions.begin("chat", [2, 3], 100)
	assert_ne(first, second, "两对闲聊必须是两场会话（不能按行为名并成一圈）")
	assert_eq(sessions.session_of(0), first)
	assert_eq(sessions.session_of(3), second)
	assert_eq(sessions.active_count(), 2)


func test_members_are_sorted_and_links_are_stable() -> void:
	var sessions := ActivitySessions.new()
	var sid := sessions.begin("chat", [5, 1], 100)
	var snap := sessions.snapshot(sid)
	assert_eq(snap["members"], [1, 5], "成员一律升序")
	assert_eq(snap["links"], [[1, 5]], "连线由成员派生，与调用顺序无关")
	sessions.join(sid, 3, 100)
	var after := sessions.snapshot(sid)
	assert_eq(after["members"], [1, 3, 5], "加入后仍升序")
	assert_eq(after["links"], [[1, 3], [1, 5], [3, 5]], "新边只连接真正参与的成员")


func test_one_member_cannot_be_in_two_sessions() -> void:
	var sessions := ActivitySessions.new()
	var first := sessions.begin("chat", [0, 1], 100)
	var second := sessions.begin("chat", [1, 2], 100)
	assert_eq(second, -1, "已在一场活动里的人不能再开一场")
	assert_eq(sessions.active_count(), 1, "失败的那次不留下空壳会话")
	assert_false(sessions.join(second, 3, 100), "不存在的会话拒绝加入")
	var other := sessions.begin("chat", [4, 5], 100)
	assert_false(sessions.join(other, 1, 100), "别场成员不能被悄悄挪过来")
	assert_eq(sessions.session_of(1), first, "1 仍在原来的会话里")


func test_begin_or_join_does_not_merge_two_sessions() -> void:
	var sessions := ActivitySessions.new()
	sessions.begin("chat", [0, 1], 100)
	sessions.begin("chat", [2, 3], 100)
	assert_eq(sessions.begin_or_join("chat", [1, 2], 100), -1, "两场不同会话不得被合并")
	assert_eq(sessions.begin_or_join("chat", [0, 4], 100), sessions.session_of(0), "同一会话则并入")
	assert_eq(sessions.session_of(4), sessions.session_of(0))


func test_extend_never_shortens() -> void:
	var sessions := ActivitySessions.new()
	var sid := sessions.begin("chat", [0, 1], 100)
	assert_false(sessions.extend(sid, 80), "更早的结束点不生效")
	assert_eq(sessions.end_tick_of(sid), 100, "结束点不被改短")
	assert_true(sessions.extend(sid, 140), "更晚的结束点生效")
	assert_eq(sessions.end_tick_of(sid), 140)


func test_snapshot_is_a_deep_copy() -> void:
	var sessions := ActivitySessions.new()
	var sid := sessions.begin("chat", [0, 1], 100)
	var snap := sessions.snapshot(sid)
	(snap["members"] as Array).append(99)
	(snap["links"] as Array).clear()
	assert_eq((sessions.snapshot(sid)["members"] as Array).size(), 2, "改快照不影响内部成员")
	assert_eq((sessions.active_snapshots()[0]["links"] as Array).size(), 1, "活动列表同样是深拷贝")


func test_expire_ends_only_due_sessions() -> void:
	var sessions := ActivitySessions.new()
	var due := sessions.begin("chat", [0, 1], 100)
	var later := sessions.begin("chat", [2, 3], 140)
	var ended := sessions.expire(100)
	assert_eq(ended.size(), 1, "只结掉到期的那一场")
	assert_eq(int(ended[0]["session_id"]), due)
	assert_true(sessions.has_session(later), "未到期的会话仍在")
	assert_eq(sessions.session_of(0), -1, "结束后成员不再属于任何会话")
	assert_eq(sessions.expire(100).size(), 0, "同一结束点只结一次")


func test_leave_below_two_ends_the_session() -> void:
	var sessions := ActivitySessions.new()
	var sid := sessions.begin("chat", [0, 1, 2], 100)
	assert_true(sessions.has_session(sid), "还剩两人：会话继续")
	assert_false(sessions.leave(sid, 2).is_empty(), "离场返回当时的快照")
	var ended := sessions.leave(sid, 1)
	assert_eq(int(ended["session_id"]), sid, "剩不足两人 → 整场结束")
	assert_false(sessions.has_session(sid))


func test_session_ids_do_not_consume_randomness() -> void:
	var sessions := ActivitySessions.new()
	sessions.begin("chat", [0, 1], 10)
	sessions.begin("chat", [2, 3], 10)
	assert_eq(sessions.begin("chat", [4, 5], 10), 3, "编号由计数器生成，与随机数无关")


# ------------------------------------------------------------------ 与内核接线的完成 / 中断


## 把 0 号与玩家清成「可以随时开聊」的状态（夹具，不改变玩法规则）。
func _make_room(core: SimCore) -> int:
	var me := int(core.node_count()) - 1
	core.set_interaction_geometry([], Rect2(-4.0, -4.0, 8.0, 8.0))
	core._sessions.clear()
	var sleeping: Array = core._sleeping
	var busy: Array = core._busy_until
	var acts: Array = core._current_act
	var busy_act: Array = core._busy_act
	var busy_phase: Array = core._busy_phase
	for i in [0, me]:
		sleeping[i] = false
		busy[i] = 0
		acts[i] = null
		busy_act[i] = null
		busy_phase[i] = -1
	core._sleeping = sleeping
	core._busy_until = busy
	core._current_act = acts
	core._busy_act = busy_act
	core._busy_phase = busy_phase
	return me


## 推进到本段第 tick 个 tick（不跨段）。
func _advance_to(core: SimCore, tick: int) -> void:
	while int(core.time_snapshot()["tick_in_phase"]) < tick:
		core.advance_tick()


func test_real_chat_registers_one_session_even_with_two_notifications() -> void:
	# NPC 的 chat 与「加入成功后复用 chat」都只在**真实成立点**登记一次，不按事件数重复登记。
	var core := _core()
	core._do_chat(0, 1)
	var after_chat := int(core.session_of(0))
	assert_gte(after_chat, 0, "闲聊成立后 0 号在一场真实会话里")
	assert_eq(core.get_active_sessions().size(), 1, "一场闲聊只登记一场活动")
	assert_eq(int(core.session_of(0)), after_chat, "重复查询不会新建会话")


func test_chat_session_disappears_when_it_completes() -> void:
	var core := _core()
	core._do_chat(0, 1)
	var sid := int(core.session_of(0))
	var until := int(core._busy_until[0])
	while core.global_tick() < until:
		core.advance_tick()
	assert_false(core._sessions.has_session(sid), "到期即结束，不留半场会话")
	# 「到期 = 完成」而不是「被打断」：0 号的完成记录应能被观测到
	assert_eq(core._last_finished[0], "chat", "到期的行为算完成，不算中断")


func test_completion_exactly_at_the_bell_is_not_an_interrupt() -> void:
	# 计划 §5.3：完成时刻恰好等于铃声 —— 完成不误算中断、不漏线索。
	var core := _core()
	var me := _make_room(core)
	# 让一段 30 tick 的玩家闲聊正好在课间最后一 tick（第 100 tick）到期
	_advance_to(core, 100 - CHAT_DURATION)
	me = _make_room(core)
	var request_id := core.next_player_request_id()
	var packet := core.commit_player_interaction(request_id, "chat", 0, "start")
	assert_true(bool(packet["ok"]), "提交应成功：%s" % str(packet))
	assert_eq(int(packet["end_tick"]), 100, "结束点正好落在铃声上")
	_advance_to(core, 100)
	var status: Dictionary = core.get_player_interaction(request_id)
	assert_eq(str(status["request"]["status"]), "completed", "到期即完成")
	assert_eq(str(status["request"]["outcome"]), "chat_started")
	assert_gte(core.get_player_intel().size(), 1, "自然完成的玩家闲聊必有线索")
	# 跨过铃声：完成过的请求不发生「完成→中断」翻转
	core.advance_tick()
	assert_eq(str(core.get_player_interaction(request_id)["request"]["status"]), "completed")


func test_interrupted_chat_clears_session_and_does_not_complete() -> void:
	var core := _core()
	var me := _make_room(core)
	_advance_to(core, 95)
	me = _make_room(core)
	var request_id := core.next_player_request_id()
	var packet := core.commit_player_interaction(request_id, "chat", 0, "start")
	assert_true(bool(packet["ok"]), "提交应成功：%s" % str(packet))
	assert_gt(int(packet["end_tick"]), 100, "占用应跨过本段边界（否则测不到中断）")
	while str(core.time_snapshot()["phase_id"]) == "morning_break":
		core.advance_tick()
	var status: Dictionary = core.get_player_interaction(request_id)
	assert_eq(str(status["request"]["status"]), "interrupted", "被铃声打断 → interrupted")
	assert_eq(core.get_active_sessions().size(), 0, "中断不留半场会话")
	assert_eq(core.get_player_intel().size(), 0, "中断不发完成线索")
	var acts: Array = core._current_act
	assert_eq(acts[me], null, "中断后当前动作被清空")
	assert_eq(int(core._busy_phase[me]), -1, "中断后占用记录被清空")
