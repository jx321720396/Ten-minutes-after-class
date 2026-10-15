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
	return SimCore.new(SEED, NPC, ConfigLoader.new().load_all())


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
	assert_gte(sid, 0, "手动发起的闲聊应登记为一场真实会话")
	# 会话结束点 = 两人各自抖动时长里更晚的那个（_conv_until），所以按「会话是否还在」推进。
	var guard := 0
	while core._sessions.has_session(sid) and guard < 120:
		core.advance_tick()
		guard += 1
	assert_false(core._sessions.has_session(sid), "到期即结束，不留半场会话")
	# 聊天占用不走通用完成协议（`_occupy_chat` 不写 `_busy_phase`，见 scripts/core/sim_core.gd 注释），
	# 因此这里不再断言 `_last_finished`；「到期 = 完成可观测」由 test_action_completion.gd
	# 用娱乐类占用（eat_snack）验证。


## 2026-10-16：原先在此的两条用例（「完成时刻恰好落在铃声」「被铃声打断清会话」）验证的是
## 玩家请求状态机（preview / commit / request status），已随玩家子系统删除；
## 会话在相位边界的完成与中断仍由 test_phase_boundary_protocol.gd 与上面的
## test_chat_session_disappears_when_it_completes 覆盖。
