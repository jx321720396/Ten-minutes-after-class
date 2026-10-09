extends GutTest
## 玩家闲聊交互服务单测：只读预览、空间与状态校验、一次判定、幂等提交、群聊编排。
##
## 依据：主文档 §10.5、§10.7、§10.31、§10.32、§12.1；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §2、§3、§4、§5。
##
## 夹具一律白盒（直接摆位置 / 清占用），因为要验证的是**规则**，不是场景装配。

const SEED := 12345
const NPC := 8
const TICKS_BREAK := 100


func _core() -> SimCore:
	return SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())


func _me(core: SimCore) -> int:
	return int(core.node_count()) - 1


## 一间 8×8 的空房间；把玩家与 0 号放在互相够得着的位置，并清掉两人的占用与睡眠。
func _room(core: SimCore, with_target: bool = true) -> int:
	var me := _me(core)
	core.set_interaction_geometry([], Rect2(-4.0, -4.0, 8.0, 8.0))
	var sleeping: Array = core._sleeping
	var busy: Array = core._busy_until
	var acts: Array = core._current_act
	var busy_act: Array = core._busy_act
	var busy_phase: Array = core._busy_phase
	sleeping[me] = false
	busy[me] = 0
	acts[me] = null
	busy_act[me] = null
	busy_phase[me] = -1
	if with_target:
		sleeping[0] = false
		busy[0] = 0
		acts[0] = null
		busy_act[0] = null
		busy_phase[0] = -1
	core._sleeping = sleeping
	core._busy_until = busy
	core._current_act = acts
	core._busy_act = busy_act
	core._busy_phase = busy_phase
	core.set_position(me, 0.4, 0.0)
	core.set_position(0, 0.0, 0.0)
	core.set_position(1, 0.5, 0.2)
	return me


func _digest(core: SimCore) -> PackedByteArray:
	var values: Array = []
	for field in ["_a", "_h", "_t", "_stress", "_current_act", "_busy_until", "_busy_phase", "_stats"]:
		values.append(core.get(field))
	values.append(core._rng._mt)
	values.append(core._rng._mti)
	values.append(core.get_active_sessions())
	values.append(core.get_player_intel())
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(values))
	return hashing.finish()


# ------------------------------------------------------------------ 只读预览


func test_preview_is_read_only_and_reports_start() -> void:
	var core := _core()
	_room(core)
	var before := _digest(core)
	var pv := core.preview_player_interaction("chat", 0)
	assert_true(bool(pv["ok"]), "预览本身必须成功")
	assert_eq(str(pv["mode"]), "start", "空闲对象 → 发起新聊天")
	assert_true(bool(pv["eligible"]), "范围内的空闲对象可以聊")
	assert_true(bool(pv["in_range"]), "两人相距 0.4m → 在范围内")
	assert_eq(int(pv["session_id"]), -1, "发起模式没有原会话")
	assert_eq(_digest(core), before, "预览零副作用：矩阵 / 占用 / 会话 / 主 RNG 都不变")


func test_unknown_kind_and_bad_target_are_rejected() -> void:
	var core := _core()
	_room(core)
	assert_eq(str(core.preview_player_interaction("tease", 0)["error"]), "unknown_kind")
	assert_eq(str(core.preview_player_interaction("chat", -1)["error"]), "invalid_target")
	assert_eq(str(core.preview_player_interaction("chat", _me(core))["error"]), "invalid_target")


func test_out_of_range_target_is_reported_not_rejected() -> void:
	var core := _core()
	var me := _room(core)
	core.set_position(me, 3.0, 3.0)
	var pv := core.preview_player_interaction("chat", 0)
	assert_true(bool(pv["ok"]), "够不着不是错误码，而是「要走过去」")
	assert_false(bool(pv["in_range"]), "距离 4.2m > 1.2m")
	assert_true(bool(pv["eligible"]), "位置不合法不妨碍「可以走过去」")
	assert_eq(str(pv["reason"]), "out_of_range")
	var request_id := core.next_player_request_id()
	var packet := core.commit_player_interaction(request_id, "chat", 0, "start")
	assert_false(bool(packet["ok"]), "够不着就提交不了（不能远程开聊）")
	assert_eq(str(packet["error"]), "out_of_range")


func test_desk_between_two_people_blocks_the_interaction() -> void:
	# 隔着一张桌子不算「在一起」：距离够但连线穿桌子 → 不合法。
	var core := _core()
	var me := _room(core)
	core.set_interaction_geometry([Rect2(-1.0, -0.5, 2.0, 1.0)], Rect2(-4.0, -4.0, 8.0, 8.0))
	core.set_position(me, -2.0, 0.0)
	var pv := core.preview_player_interaction("chat", 0)
	assert_false(bool(pv["in_range"]), "直线穿过桌椅 → 不能算在范围内")
	var packet := core.commit_player_interaction(core.next_player_request_id(), "chat", 0, "start")
	assert_false(bool(packet["ok"]), "隔着桌子不能开聊")


func test_geometry_missing_is_an_explicit_error() -> void:
	var core := _core()
	assert_false(core.interaction_space_ready(), "未注入几何 → 未就绪")
	var packet := core.commit_player_interaction(core.next_player_request_id(), "chat", 0, "start")
	assert_false(bool(packet["ok"]))
	assert_eq(str(packet["error"]), "geometry_missing")


# ------------------------------------------------------------------ 状态校验


func test_sleeping_busy_moving_and_phase_states_give_distinct_reasons() -> void:
	var core := _core()
	var me := _room(core)
	# 目标睡眠
	var sleeping: Array = core._sleeping
	sleeping[0] = true
	core._sleeping = sleeping
	assert_eq(str(core.preview_player_interaction("chat", 0)["reason"]), "target_sleeping")
	sleeping[0] = false
	core._sleeping = sleeping
	# 目标忙于别的占用型行为
	var busy: Array = core._busy_until
	busy[0] = int(core.global_tick()) + 20
	core._busy_until = busy
	assert_eq(str(core.preview_player_interaction("chat", 0)["reason"]), "target_busy")
	busy[0] = 0
	core._busy_until = busy
	# 玩家走动中（独立移动状态，不是聊天占用）
	core.set_moving(me, true)
	assert_eq(str(core.preview_player_interaction("chat", 0)["reason"]), "player_moving")
	core.set_moving(me, false)
	# 玩家自己被占用
	busy[me] = int(core.global_tick()) + 20
	core._busy_until = busy
	assert_eq(str(core.preview_player_interaction("chat", 0)["reason"]), "player_busy")
	busy[me] = 0
	core._busy_until = busy
	# 上课段
	for _i in range(TICKS_BREAK):
		core.advance_tick()
	core.finish_time_boundary()
	core.advance_tick()
	_room(core)
	assert_eq(str(core.time_snapshot()["kind"]), "class", "应已进入上课段")
	assert_eq(str(core.preview_player_interaction("chat", 0)["reason"]), "phase_not_allowed")


# ------------------------------------------------------------------ 加入闲聊（mode=join）


## 让 0 号与 1 号建立一场真实闲聊会话（NPC 路径），返回会话编号。
func _npc_chat(core: SimCore) -> int:
	core._do_chat(0, 1)
	return int(core.session_of(0))


func test_preview_reports_join_and_belief_probability() -> void:
	var core := _core()
	_room(core)
	var sid := _npc_chat(core)
	var pv := core.preview_player_interaction("chat", 0)
	assert_eq(str(pv["mode"]), "join", "目标是聊天成员 → 通用加入操作")
	assert_eq(int(pv["session_id"]), sid, "锁定原会话编号")
	assert_almost_eq(
		float(pv["p_belief"]),
		float(core._join_feedback(_me(core), 0)["p"]),
		0.0001,
		"展示用成功率来自信念，不是真值"
	)


func test_busy_member_of_the_same_chat_can_still_be_joined() -> void:
	# §10.31：同一场活动允许新增成员 —— 忙碌不能一概拒绝。
	var core := _core()
	_room(core)
	_npc_chat(core)
	var busy: Array = core._busy_until
	assert_gt(int(busy[0]), int(core.global_tick()), "0 号在闲聊占用中")
	var pv := core.preview_player_interaction("chat", 0)
	assert_true(bool(pv["eligible"]), "同一场闲聊的成员仍可加入")
	assert_ne(str(pv["reason"]), "target_busy")


func test_original_session_ending_invalidates_the_frozen_request() -> void:
	var core := _core()
	_room(core)
	var sid := _npc_chat(core)
	var pv := core.preview_player_interaction("chat", 0)
	var request_id := core.next_player_request_id()
	# 接近途中原组散场：冻结的 mode/session 必须失效，不能静默改成 start
	core._sessions.end(sid)
	var packet := core.commit_player_interaction(request_id, "chat", 0, str(pv["mode"]), sid)
	assert_false(bool(packet["ok"]), "原会话结束 → 旧请求作废")
	assert_eq(str(packet["error"]), "mode_changed")


func test_caller_cannot_fake_mode_to_bypass_session_checks() -> void:
	var core := _core()
	var me := _room(core)
	# 目标空闲却硬报 join：不能靠伪造 mode 绕过会话校验
	var packet := core.commit_player_interaction(core.next_player_request_id(), "chat", 0, "join", -1)
	assert_false(bool(packet["ok"]))
	assert_eq(str(packet["error"]), "mode_changed")
	# 冻结的是另一场会话的编号：同样拒绝
	var sid := _npc_chat(core)
	var wrong := core.commit_player_interaction(core.next_player_request_id(), "chat", 0, "join", sid + 99)
	assert_false(bool(wrong["ok"]))
	assert_eq(str(wrong["error"]), "session_changed")
	assert_eq(str(core.get_player_interaction(1)["error"]), "unknown_request", "失败的提交不留下记录")
	assert_eq(me, _me(core))


func test_conflicting_reused_request_id_is_refused() -> void:
	var core := _core()
	_room(core)
	var request_id := core.next_player_request_id()
	var first := core.commit_player_interaction(request_id, "chat", 0, "start")
	assert_true(bool(first["ok"]), "首次提交成功：%s" % str(first))
	var conflict := core.commit_player_interaction(request_id, "chat", 1, "start")
	assert_false(bool(conflict["ok"]))
	assert_eq(str(conflict["error"]), "request_conflict")
	var replay := core.commit_player_interaction(request_id, "chat", 0, "start")
	assert_eq(replay, first, "同编号同参数 → 返回缓存结果")


# ------------------------------------------------------------------ 一次判定、群聊结算


## 与 core 完全同源的参照局：只用来提前读出「提交将要掷的那一次骰」。
## 夹具不消费随机数以外的任何状态，因此两局的主随机流始终一致。
func _reference_like(core: SimCore, with_chat: bool) -> SimCore:
	var ref := _core()
	_room(ref)
	if with_chat:
		_npc_chat(ref)
	return ref


## 让「加入判定」几乎必然通过：真值好感极高 + 外向度最高 + 压力为零。
## 只改矩阵，不消费随机数（否则参照局的流就对不上了）。
func _force_accept(core: SimCore, me: int) -> void:
	var n := int(core.node_count())
	var a := core._a
	a[0 * n + me] = 100.0
	core._a = a
	var dims := core._dims
	dims[0] = 100.0
	core._dims = dims
	var stress := core._stress
	stress[0] = 0.0
	core._stress = stress


## 让「加入判定」几乎必然被拒：真值好感为零 + 外向度最低 + 压力满。
func _force_reject(core: SimCore, me: int) -> void:
	var n := int(core.node_count())
	var a := core._a
	a[0 * n + me] = 0.0
	core._a = a
	var dims := core._dims
	dims[0] = 0.0
	core._dims = dims
	var stress := core._stress
	stress[0] = 100.0
	core._stress = stress


func test_accept_settles_new_edges_once_and_aligns_end_tick() -> void:
	var core := _core()
	var me := _room(core)
	var sid := _npc_chat(core)
	var ref := _reference_like(core, true)
	_force_accept(core, me)
	# 玩家自身压力先抬起来，减压效果才可观测
	var pstress := core._stress
	pstress[me] = 60.0
	core._stress = pstress
	var roll: float = ref._rng.random()
	var p_true: float = core._join_probability(me, 0)
	assert_lt(roll, p_true, "夹具应保证这一次判定通过（roll=%.4f p=%.4f）" % [roll, p_true])

	var n := int(core.node_count())
	var old_edge_before := float(core._a[0 * n + 1])
	var old_h_before := float(core._h[0 * n + 1])
	var stress_before := float(core.stress(me))
	var session_end_before := core.session_end_tick(sid)
	var request_id := core.next_player_request_id()
	var packet := core.commit_player_interaction(request_id, "chat", 0, "join", sid)
	assert_true(bool(packet["ok"]), "接受后提交成功：%s" % str(packet))
	assert_true(bool(packet["accepted"]), "这一次判定应被接受")
	assert_eq(int(packet["linked_session"]), sid, "加入的是原会话，不是新开一场")
	assert_eq(int(core.session_of(me)), sid, "玩家真的进了原会话")
	var snap := core._sessions.snapshot(sid)
	assert_eq(snap["members"], [0, 1, me], "原成员保留、玩家加入")
	assert_true((snap["links"] as Array).has([0, me]), "玩家与每位原成员都有新边")
	assert_true((snap["links"] as Array).has([1, me]), "玩家与 1 号也有新边")
	assert_gt(core.affinity(me, 0), 0.0, "新边（玩家 → 0 号）已结算")
	assert_gt(core.affinity(me, 1), 0.0, "新边（玩家 → 1 号）已结算")
	assert_eq(float(core._a[0 * n + 1]), old_edge_before, "原成员之间的旧边不重算（好感）")
	assert_eq(float(core._h[0 * n + 1]), old_h_before, "原成员之间的旧边不重算（敌对）")
	assert_lt(float(core.stress(me)), stress_before, "玩家减压只执行一次")
	assert_gte(core.session_end_tick(sid), session_end_before, "结束点只后延，不提前")
	assert_eq(
		int(core._busy_until[me]), core.session_end_tick(sid), "玩家占用与共同结束点对齐"
	)
	assert_eq(int(core._busy_until[0]), core.session_end_tick(sid), "原成员占用同样被对齐")
	assert_eq(int(core._stats["join_accepts"]), 1, "接受统计一次")
	assert_eq(int(core._stats["joins"]), 1, "加入请求统计一次")


func test_one_commit_draws_exactly_one_roll_and_is_replayable() -> void:
	var core := _core()
	var me := _room(core)
	var sid := _npc_chat(core)
	var ref := _reference_like(core, true)
	# 接受判定：参照局预读一次 roll，主局对同样的流只应消耗这一个
	_force_accept(core, me)
	var roll: float = ref._rng.random()
	assert_lt(roll, float(core._join_probability(me, 0)), "夹具应保证通过")
	var before := var_to_bytes([core._rng._mt, core._rng._mti])
	var request_id := core.next_player_request_id()
	var packet := core.commit_player_interaction(request_id, "chat", 0, "join", sid)
	assert_true(bool(packet["ok"]), str(packet))
	assert_ne(var_to_bytes([core._rng._mt, core._rng._mti]), before, "判定确实消耗了随机数")
	var after_first := var_to_bytes([core._rng._mt, core._rng._mti])
	var digest := _digest(core)
	# 参照局此刻停在「读出判定那一次 roll」的位置（aligned+1）：
	# 主局提交后也应恰好停在同一位置 —— 多掷一次都会对不上。
	assert_eq(
		var_to_bytes([core._rng._mt, core._rng._mti]),
		var_to_bytes([ref._rng._mt, ref._rng._mti]),
		"一次合法加入只有一次接受判定"
	)
	var replay := core.commit_player_interaction(request_id, "chat", 0, "join", sid)
	assert_eq(replay, packet, "重复提交返回缓存结果")
	assert_eq(var_to_bytes([core._rng._mt, core._rng._mti]), after_first, "重复提交不掷骰")
	assert_eq(_digest(core), digest, "重复提交不改矩阵 / 统计 / 会话 / 线索")


func test_reject_occupies_only_the_player_and_leaves_the_group_alone() -> void:
	var core := _core()
	var me := _room(core)
	var sid := _npc_chat(core)
	var ref := _reference_like(core, true)
	var roll: float = ref._rng.random()
	var n := int(core.node_count())
	# 让 0 号对玩家的真值好感为 0、外向度最低、压力满 → 判定必然落在 roll 之上（拒绝）
	_force_reject(core, me)
	var p_true: float = core._join_probability(me, 0)
	assert_gte(roll, p_true, "夹具应保证这一次判定被拒（roll=%.4f p=%.4f）" % [roll, p_true])
	var member_end_before := int(core._busy_until[1])
	var session_end_before := core.session_end_tick(sid)
	var old_edge_before := float(core._a[0 * n + 1])
	var busy_before := int(core._busy_until[me])
	var request_id := core.next_player_request_id()
	var packet := core.commit_player_interaction(request_id, "chat", 0, "join", sid)
	assert_true(bool(packet["ok"]), "拒绝也是一次合法提交：%s" % str(packet))
	assert_false(bool(packet["accepted"]), "这一次判定应被拒")
	assert_lt(float(core.stress(me)), 100.0, "拒绝的玩家自身效果已结算（压力）")
	assert_eq(int(core._stats["join_rejects"]), 1, "拒绝统计一次")
	assert_eq(core.session_end_tick(sid), session_end_before, "原组结束点不被改短或延长")
	assert_eq(int(core._busy_until[1]), member_end_before, "原成员占用不变")
	assert_eq(int(core._busy_until[me]), busy_before, "拒绝不占用玩家——玩家立即可移动")
	assert_eq(float(core._a[0 * n + 1]), old_edge_before, "原成员之间的关系不被拒绝改写")
	assert_false((core._sessions.snapshot(sid)["members"] as Array).has(me), "拒绝不把玩家塞进原会话")
	assert_eq(core.get_player_intel().size(), 0, "拒绝不给线索")


func test_reject_hostility_lands_on_every_original_member() -> void:
	var core := _core()
	var me := _room(core)
	var sid := _npc_chat(core)
	var ref := _reference_like(core, true)
	var roll: float = ref._rng.random()
	var n := int(core.node_count())
	_force_reject(core, me)
	var stress0 := core._stress
	stress0[1] = 100.0
	core._stress = stress0
	assert_gte(roll, float(core._join_probability(me, 0)), "夹具应保证被拒")
	var h0_before := float(core.hostility(me, 0))
	var h1_before := float(core.hostility(me, 1))
	core.commit_player_interaction(core.next_player_request_id(), "chat", 0, "join", sid)
	assert_gt(float(core.hostility(me, 0)), h0_before, "应答者被记为敌对上升")
	assert_gt(float(core.hostility(me, 1)), h1_before, "其他原成员同样收到敌对反馈")


# ------------------------------------------------------------------ 线索（§8.4）


func test_clue_count_follows_source_opacity_and_single_axis() -> void:
	var me := int(_core().node_count()) - 1
	var low := _run_player_chat(_core(), 20.0)
	assert_eq(low.size(), 1, "O < 50 只透露 1 条")
	var high := _run_player_chat(_core(), 80.0)
	assert_eq(high.size(), 2, "O ≥ 50 透露 2 条")
	assert_ne(int(high[0]["clue"]["subject"]), int(high[1]["clue"]["subject"]), "两条线索的对象不重复")
	for entry in high:
		var clue: Dictionary = entry["clue"]
		assert_eq(int(clue["source"]), 0, "来源固定为本次闲聊对象")
		assert_ne(int(clue["subject"]), me, "对象排除玩家")
		assert_ne(int(clue["subject"]), 0, "对象排除 source")
		assert_true(["affinity", "hostility", "trust"].has(str(clue["axis"])), "只透露一个轴")
		assert_gt(int(clue["global_tick"]), 0, "线索带获知时间")
		assert_almost_eq(
			float(clue["value"]),
			snapped(float(entry["now"]), 0.1),
			0.0001,
			"取「自然完成这一刻」的真值（方向为 source → subject）"
		)


## 让玩家与 0 号聊一次并跑到自然完成；返回完成瞬间采集到的线索与**当刻**真值。
## 采集点挂在通知回调里：那正是「读取这一刻情报」的同一时刻，晚一步就会被同 tick 的后续决策改掉。
func _run_player_chat(core: SimCore, opacity: float) -> Array:
	var me := _room(core)
	var o := core._o
	o[0] = opacity
	core._o = o
	var captured: Array = []
	core.event_sink = func(e: Dictionary) -> void:
		var payload: Dictionary = e["payload"]
		if str(payload.get("kind", "")) != "player_intel_received":
			return
		var clue: Dictionary = payload["clue"]
		captured.append({"clue": clue, "now": _axis_now(core, clue)})
	var request_id := core.next_player_request_id()
	assert_true(bool(core.commit_player_interaction(request_id, "chat", 0, "start")["ok"]))
	var until := int(core._busy_until[me])
	while core.global_tick() < until:
		core.advance_tick()
	return captured


## clue 指向的单轴真值：source → subject 方向明确。
func _axis_now(core: SimCore, clue: Dictionary) -> float:
	var source := int(clue["source"])
	var subject := int(clue["subject"])
	match str(clue["axis"]):
		"hostility":
			return float(core.hostility(source, subject))
		"trust":
			return float(core.trust(source, subject))
		_:
			return float(core.affinity(source, subject))


func test_intel_log_does_not_change_after_the_fact() -> void:
	var core := _core()
	var me := _room(core)
	var request_id := core.next_player_request_id()
	assert_true(bool(core.commit_player_interaction(request_id, "chat", 0, "start")["ok"]))
	var until := int(core._busy_until[me])
	while core.global_tick() < until:
		core.advance_tick()
	var logged := core.get_player_intel()
	# 记录之后再改真值矩阵：历史卡片不跟着刷新
	var a: Array = core._a
	var subject := int(logged[0]["subject"])
	a[0 * int(core.node_count()) + subject] = 0.0
	core._a = a
	assert_eq(core.get_player_intel(), logged, "历史线索不随矩阵变化刷新")
	assert_eq(int(core.get_player_intel()[0]["value"]), int(logged[0]["value"]))


func test_clue_draw_is_reproducible_for_the_same_seed() -> void:
	var first := _core()
	var second := _core()
	for core: SimCore in [first, second]:
		var me := _room(core)
		var request_id := core.next_player_request_id()
		assert_true(bool(core.commit_player_interaction(request_id, "chat", 0, "start")["ok"]))
		var until := int(core._busy_until[me])
		while core.global_tick() < until:
			core.advance_tick()
	assert_eq(first.get_player_intel(), second.get_player_intel(), "同种子 / 同完成输入 → 线索可复现")
