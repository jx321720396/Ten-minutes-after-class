extends GutTest
## 《老师版新增规则程序落地交接-2026-10-17》第 4 步验证：
## 同刻中断、上课边界、老师叫走、重复加入、风险消息与确定性。
##
## 这里只覆盖「不依赖待定边界」的可验行为（交接 §待定项 1–6 之外），
## 逐条对应交接第 4 步验收与最低交付 A–D 的可观测子集。

const SEED := 20261017
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


## 隔离除 0 号以外的所有学生（"broken" 不参与决策与结算），让用例只观察 0 号。
func _isolate_others(core: SimCore) -> void:
	core._begin_phase_state()
	for i in range(1, core.node_count()):
		core._phase_state[i] = "broken"


# ------------------------------------------------------------------ A. 同刻中断
## 交接「同刻顺序」：先记截至本 tick 已完成的完整单位，再处理边界/中断；收益已记不清空。
## 学习恰满 20 秒同时响铃 —— 完整单位记一次，未完成余额才被折算，不丢、不重。
func test_study_unit_completing_at_bell_counts_once() -> void:
	var core := _core()
	_isolate_others(core)
	core._phase_state[0] = "study"
	var gain_before := core.gain_today(0)
	for _t in range(20):
		core._settle_units()
	assert_almost_eq(core.gain_today(0), gain_before + 1.0, 0.0001, "第 20 秒完成一个单位")
	core._fold_pending_unit(0)  # 铃响：只折未完成余额，已完成单位不清空
	assert_almost_eq(core.gain_today(0), gain_before + 1.0, 0.0001, "响铃不清空已完成收益（不丢）")
	for _t in range(20):
		core._settle_units()
	assert_almost_eq(core.gain_today(0), gain_before + 2.0, 0.0001, "每 20 秒恰 +1（不重）")


# ------------------------------------------------------------------ B. 上课边界
## 交接 D09：鼓励目标跨上课保留；上课不消耗课间次数（考试日无课间同理不消耗）。
func test_encourage_target_survives_class_without_consuming_breaks() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	assert_true(tc.start_encourage(3, 5), "发起指定对象鼓励")
	assert_eq(tc.encourage_snapshot(core, 3)["breaks_left"], 4, "含当前课间共 4 次")
	tc.settle_encourage_breaks()  # 课间末：消耗 1 次
	assert_eq(tc.encourage_snapshot(core, 3)["breaks_left"], 3)
	tc.begin_class(core)  # 上课：挂起命令，但已生效目标保留
	tc.begin_break()
	var snap: Dictionary = tc.encourage_snapshot(core, 3)
	assert_eq(snap["status"], "active", "跨上课目标仍 active")
	assert_eq(snap["breaks_left"], 3, "上课不消耗课间次数")
	assert_eq(snap["target"], 5, "指定对象跨上课保留")


# ------------------------------------------------------------------ C. 老师叫走
## 交接「老师叫走或调座者退出」：三人聊天里叫走一人，其余成员沿原进度继续；
## 仅剩不足 2 人时才整场解散。
func test_summon_removes_one_member_others_continue() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	core._start_conversation(0, 1)
	core._add_member_to_conversation(2, core._conv_of[0])
	var sid := core.session_of(0)
	assert_gte(sid, 0, "三人聊天会话成立")
	assert_true(tc.summon(core, 0), "老师叫走其中一人")
	assert_eq(core.session_of(0), -1, "被叫走者退出会话")
	assert_gte(core.session_of(1), 0, "成员 1 仍在会话")
	assert_gte(core.session_of(2), 0, "成员 2 仍在会话")


# ------------------------------------------------------------------ D. 重复加入
## 交接 D09：已有未结束目标时重复鼓励无效，不覆盖、不叠加、也不扣 20 秒。
func test_duplicate_encourage_rejected_without_cost() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	assert_true(tc.summon(core, 4), "召唤学生 4")
	assert_true(tc.office_chat(core, "encourage"), "第一次鼓励开始 20 秒")
	assert_eq(tc.remaining_seconds(), 20, "鼓励耗时 20 秒")
	for _t in range(20):
		tc.tick(core)
	assert_true(tc.has_active_encourage(4), "鼓励完成后生成一次聊天目标")
	assert_false(tc.office_chat(core, "encourage"), "已有目标时重复鼓励无效")
	assert_eq(tc.current_command(), "", "不占用命令")
	assert_eq(tc.remaining_seconds(), 0, "不扣 20 秒")
	var snap: Dictionary = tc.encourage_snapshot(core, 4)
	assert_eq(snap["status"], "active", "目标不被覆盖")
	assert_eq(snap["breaks_left"], 4, "次数不叠加（仍是初始值）")


# ------------------------------------------------------------------ E. 风险消息
## 交接 D10：至少 ask_low_affinity_count 名其他学生对目标好感 < 阈值 → 低好感隐患。
func test_ask_low_affinity_hint_targets() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	var n: int = core.node_count()
	for j in range(n):
		for k in range(n):
			if j != k:
				core._a[j * n + k] = 60.0  # 默认都不构成低好感
	var count := 0
	for j in range(n):
		if j != 7 and count < 13:
			core._a[j * n + 7] = 10.0  # < 20
			count += 1
	var targets: Array = tc._low_affinity_hint_targets(core)
	assert_true(targets.has(7), "目标 7 构成低好感隐患")
	assert_false(targets.has(0), "目标 0 不构成低好感隐患")


## 交接 D10：受访者对目标敌对 > 阈值且「知道」其带对应物品 → 物品消息（只给信息，不改关系）。
func test_ask_item_hint_targets() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	var n: int = core.node_count()
	core._h[0 * n + 4] = 60.0  # 受访者 0 对目标 4 敌对 60（> 40）
	core._busy_act[4] = "play_phone"
	var targets: Array = tc._item_hint_targets(core, 0, "phone")
	assert_true(targets.has(4), "知情且敌对够 → 提供手机消息")
	core._h[0 * n + 4] = 30.0  # 敌对不足
	assert_false(tc._item_hint_targets(core, 0, "phone").has(4), "敌对 ≤ 阈值不提供")


## 交接 D10：正式风险消息读已有风险记录，不以一次打听生成正式霸凌/孤立。
func test_ask_priority_reads_existing_formal_risk() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	core._risk._triggered[6] = true
	core._risk._triggered_kind[6] = "bully"
	var msg := tc._pick_priority_message(core, 0)
	assert_true(msg.contains(core.alias(6)), "优先消息来自正式霸凌记录")
	assert_true(msg.contains("欺负"), "霸凌文案")


## 交接 D10：优先消息去重 —— 同一条未变化消息不反复占用机会，下一次给下一条。
func test_ask_priority_dedup_advances_to_next() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	core._risk._triggered[6] = true
	core._risk._triggered_kind[6] = "bully"
	core._risk._triggered[7] = true
	core._risk._triggered_kind[7] = "bully"
	var first := tc._pick_priority_message(core, 0)
	assert_true(first.contains(core.alias(6)), "第一次给目标 6")
	var second := tc._pick_priority_message(core, 0)
	assert_true(second.contains(core.alias(7)), "第二次给目标 7（不重复 6）")


# ------------------------------------------------------------------ F. 确定性
## 交接 D09：未指定时并列取带种子随机 —— 同种子同选择（可复现）。
func test_encourage_auto_pick_is_deterministic() -> void:
	var a := _core()
	var b := _core()
	var ta := a.teacher_commands()
	var tb := b.teacher_commands()
	for core in [a, b]:
		core.set_position(0, 0.0, 0.0)
		core.set_position(1, 1.0, 0.0)
		core.set_position(2, 0.0, 1.0)
		core._begin_phase_state()
		core._phase_state[1] = "free"
		core._phase_state[2] = "free"
		core._busy_act[1] = "listen_music"
		core._busy_act[2] = "listen_music"
		core._busy_until[1] = 10
		core._busy_until[2] = 10
		core._global_tick = 0
	assert_true(ta.start_encourage(0, -1), "自主模式鼓励")
	assert_true(tb.start_encourage(0, -1))
	var pa := ta._pick_encourage_target(a, 0)
	var pb := tb._pick_encourage_target(b, 0)
	assert_true(pa == 1 or pa == 2, "选的是并列的两个最近娱乐对象之一")
	assert_eq(pa, pb, "并列带种子随机 → 同种子同选择")


# ------------------------------------------------------------------ G. 多人请教（迟加入 / 退出重入）
## 专注（focus）使正学业收益翻倍；其余公开被动不改正收益的每单位数值。
func _study_unit_gain(core: SimCore, i: int) -> float:
	return 2.0 if core._passives.has(i, "focus") else 1.0


## 交接 §多人请教 算例（第 68 条）：原学习者一段 40 秒；自由学生在第 10 秒加入、40 秒同步结束
## → 请教者实际参与 30 秒 = 1 点收益、免动力；原学习者 2 点收益、正常扣动力。
func test_study_follower_late_join_no_backpay_free_vitality() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(2, core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._vitality[0] = 60.0
	core._vitality[1] = 60.0
	core._do_study(0)  # 原学习者从第 0 秒开始
	for _t in range(10):
		core._settle_units()
	core._join_study(1, core._ensure_group("study", 0))  # 请教者第 10 秒加入
	for _t in range(30):
		core._settle_units()
	assert_almost_eq(
		core.gain_today(0), 2.0 * _study_unit_gain(core, 0), 0.0001, "原学习者 40 秒 → 2 个单位"
	)
	assert_almost_eq(
		core.gain_today(1), _study_unit_gain(core, 1), 0.0001, "请教者迟加入不补奖：30 秒 → 1 个单位"
	)
	assert_almost_eq(core.vitality(1), 60.0, 0.0001, "请教者免动力")
	assert_true(core.vitality(0) < 60.0, "原学习者正常扣动力")


## 交接 §多人请教 验收 ⑤：退出重入不重算旧时长 —— 请教者退出时未完成余额折算清空，
## 重入后从零起算，各段不足 20 秒不因拼接旧时长而多发收益。
func test_study_follower_exit_rejoin_does_not_recount_old_duration() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(2, core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._do_study(0)
	core._join_study(1, core._ensure_group("study", 0))
	for _t in range(10):
		core._settle_units()
	assert_almost_eq(core.gain_today(1), 0.0, 0.0001, "10 秒未满单位，无收益")
	assert_almost_eq(float(core._settle_acc[1]), 10.0, 0.0001, "请教者已累计 10 秒")
	core.interrupt_for_seat_change(1)  # 老师叫走请教者
	assert_eq(core._study_of[1], null, "请教者退出学习组")
	assert_almost_eq(float(core._settle_acc[1]), 0.0, 0.0001, "退出时未完成余额折算清空")
	core._join_study(1, core._ensure_group("study", 0))  # 重入
	assert_almost_eq(float(core._settle_acc[1]), 0.0, 0.0001, "重入不恢复旧时长")
	for _t in range(10):
		core._settle_units()
	assert_almost_eq(core.gain_today(1), 0.0, 0.0001, "10+10 秒各自不足 20：退出重入不重算旧时长")


# ------------------------------------------------------------------ H. 多人请教（过半 / 投票 / 无上限 / 其他事件）
## 交接 §人数与时限 第 69 条：第 20 秒恰好一半允许加入；第 21 秒超过一半拒绝，
## 且此拒绝属活动条件不满足、不算关系拒绝。
func test_study_join_half_boundary_and_no_relationship_reject() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(3, core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._phase_state[2] = "free"
	core._do_study(0)
	core._busy_until[0] = 40  # 原学习者整段 40 秒（start_tick=0）
	var grp: Dictionary = core._ensure_group("study", 0)
	core._a[0 * core.node_count() + 1] = 60.0  # 现有成员 0 对 1、2 均投同意
	core._a[0 * core.node_count() + 2] = 60.0
	core._global_tick = 20  # 恰好一半
	assert_true(core._apply_join_group(1, 0, "study", grp), "恰好一半允许加入")
	assert_eq(core._study_of[1], grp, "加入者进入学习组")
	core._global_tick = 21  # 超过一半
	var rejects_before: int = int(core._stats.get("join_rejects", 0))
	assert_false(core._apply_join_group(2, 0, "study", grp), "超过一半拒绝加入")
	assert_eq(core._study_of[2], null, "被拒者未进入学习组")
	assert_eq(int(core._stats.get("join_rejects", 0)), rejects_before, "过半拒绝是条件不满足，不算关系拒绝")


## 交接 §接纳 第 51 条：成员按「自己对加入者好感−敌对 ≥ 门槛」投同意，严格过半才接受，平票拒绝。
func test_study_join_vote_tie_rejects() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(3, core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._phase_state[2] = "free"
	core._do_study(0)
	core._busy_until[0] = 100  # 足够长，不触发过半
	var n := core.node_count()
	core._a[0 * n + 1] = 60.0  # 0 同意 1 加入
	var grp: Dictionary = core._ensure_group("study", 0)
	assert_true(core._apply_join_group(1, 0, "study", grp), "1 号加入（0 投同意）")
	core._a[0 * n + 2] = 60.0  # 0 同意 2
	core._a[1 * n + 2] = 0.0
	core._h[1 * n + 2] = 50.0  # 1 反对 2（好感 0 − 敌对 50 < 门槛 10）
	assert_false(core._apply_join_group(2, 0, "study", grp), "平票拒绝")
	assert_eq(core._study_of[2], null, "被拒者未进入学习组")
	assert_eq(int(core._stats.get("join_rejects", 0)), 1, "记一次关系拒绝")


## 交接 §旧规则替换 第 60 条：取消固定 3/4 人上限，多人请教不设人数上限（仍受投票与状态约束）。
func test_study_group_no_hard_member_cap() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(6, core.node_count()):
		core._phase_state[i] = "broken"
	for i in range(6):
		core._phase_state[i] = "free"
	var n := core.node_count()
	for j in range(n):
		for k in range(n):
			if j != k:
				core._a[j * n + k] = 60.0  # 全员互相好感高 → 都投同意
	core._do_study(0)
	core._busy_until[0] = 1000  # 足够长，不触发过半
	var grp: Dictionary = core._ensure_group("study", 0)
	for j in range(1, 5):
		assert_true(core._apply_join_group(j, 0, "study", grp), "第 %d 人加入不被旧硬上限拒绝" % j)
		assert_eq(core._study_of[j], grp, "第 %d 人进入学习组" % j)
	assert_eq((grp["members"] as Array).size(), 5, "5 人学习组，无固定人数上限")


## 交接 §多人请教 第 64 条：免动力仅指请教本身，其他事件引起的动力变化照常结算。
func test_study_follower_other_events_change_vitality() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(2, core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._vitality[1] = 50.0
	core._do_study(0)
	core._join_study(1, core._ensure_group("study", 0))
	for _t in range(20):
		core._settle_units()  # 请教者完成一个单位：免动力
	assert_almost_eq(core.vitality(1), 50.0, 0.0001, "请教本身免动力")
	core.add_vitality(1, 5.0)  # 其他事件（如训斥）：动力照常变化
	assert_almost_eq(core.vitality(1), 55.0, 0.0001, "其他事件仍能改变请教者动力")


# ------------------------------------------------------------------ I. 座位涓流
## 交接 §座位涓流（第 75–90 条）：涓流只看固定座位的前后左右，不含对角、不随临时走动重建邻域；
## 离座 / 办公室 / 崩溃 / 换座期间都不作为来源或接收者，回座恢复资格。


## 把 a、b 放到一对正交邻座（前后左右，dr+dc == 1）。
func _seat_orthogonal(core: SimCore, a: int, b: int) -> void:
	for sa in core._seat_pos:
		var pa: Array = core._seat_pos[sa]
		for sb in core._seat_pos:
			if sa == sb:
				continue
			var pb: Array = core._seat_pos[sb]
			if absi(int(pa[0]) - int(pb[0])) + absi(int(pa[1]) - int(pb[1])) == 1:
				core._seat_of[a] = str(sa)
				core._seat_of[b] = str(sb)
				return


## 把 a、b 放到一对对角邻座（斜向，dr == 1 且 dc == 1）。
func _seat_diagonal(core: SimCore, a: int, b: int) -> void:
	for sa in core._seat_pos:
		var pa: Array = core._seat_pos[sa]
		for sb in core._seat_pos:
			if sa == sb:
				continue
			var pb: Array = core._seat_pos[sb]
			if absi(int(pa[0]) - int(pb[0])) == 1 and absi(int(pa[1]) - int(pb[1])) == 1:
				core._seat_of[a] = str(sa)
				core._seat_of[b] = str(sb)
				return


## 把 a、b 放到相隔一圈以上的座位（不是 8 邻接，max(dr, dc) >= 2）。
func _seat_far(core: SimCore, a: int, b: int) -> void:
	for sa in core._seat_pos:
		var pa: Array = core._seat_pos[sa]
		for sb in core._seat_pos:
			if sa == sb:
				continue
			var pb: Array = core._seat_pos[sb]
			if maxi(absi(int(pa[0]) - int(pb[0])), absi(int(pa[1]) - int(pb[1]))) >= 2:
				core._seat_of[a] = str(sa)
				core._seat_of[b] = str(sb)
				return


## 给 a、b 注入以当前位置为中心的占位矩形，使 in_own_seat 真实判别在座 / 离座。
func _pin_seats(core: SimCore, a: int, b: int) -> void:
	var half := 0.5
	(
		core
		. set_seat_zones(
			{
				a: Rect2(core._pos_x[a] - half, core._pos_z[a] - half, half * 2.0, half * 2.0),
				b: Rect2(core._pos_x[b] - half, core._pos_z[b] - half, half * 2.0, half * 2.0),
			}
		)
	)


## 交接 §座位涓流：对角也是 8 邻接，但涓流只认前后左右 —— 对角邻座学习不传播压力。
func test_drip_excludes_diagonal_neighbor() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(2, core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._current_act[0] = "study"
	core._stress[1] = 0.0
	_seat_diagonal(core, 0, 1)
	core._build_neighbor_idx()
	assert_true(core._neighbor_idx[1].has(0), "对角属于 8 邻接（_neighbor_idx 含对角）")
	core._settle_neighbor_drip()
	assert_almost_eq(core.stress(1), 0.0, 0.0001, "涓流不含对角：对角邻座学习不传播压力")


## 交接 §座位涓流（第 78 条）：固定座位决定邻域，临时走到同学身边不重建邻域。
func test_drip_neighborhood_is_fixed_seat_not_walk_position() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(2, core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._current_act[0] = "study"
	core._stress[1] = 0.0
	_seat_far(core, 0, 1)  # 固定座位相隔一圈以上
	core._build_neighbor_idx()
	assert_false(core._neighbor_idx[1].has(0), "固定座位不相邻 → 不是邻座")
	core.set_position(0, 0.0, 0.0)
	core.set_position(1, 0.1, 0.0)  # 1 临时走到 0 身边（物理贴近）
	core._settle_neighbor_drip()
	assert_almost_eq(core.stress(1), 0.0, 0.0001, "临时走近不重建邻域：不触发涓流")


## 交接 §座位涓流（第 89 条）：结算瞬间离座双向排除，回座恢复资格。
func test_drip_off_seat_excludes_both_ways_then_returns() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(2, core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._current_act[0] = "study"
	_seat_orthogonal(core, 0, 1)
	core._build_neighbor_idx()
	core.set_position(0, 0.0, 0.0)
	core.set_position(1, 1.0, 0.0)
	_pin_seats(core, 0, 1)
	core._stress[1] = 0.0
	core._settle_neighbor_drip()
	assert_gt(core.stress(1), 0.0, "在座：邻座学习 → 压力上升")
	core._pos_x[1] += 5.0  # 接收者离座
	core._stress[1] = 0.0
	core._settle_neighbor_drip()
	assert_almost_eq(core.stress(1), 0.0, 0.0001, "接收者离座 → 不接收涓流")
	core._pos_x[1] -= 5.0  # 接收者回座
	core._settle_neighbor_drip()
	assert_gt(core.stress(1), 0.0, "接收者回座恢复资格")
	core._pos_x[0] += 5.0  # 来源离座
	core._stress[1] = 0.0
	core._settle_neighbor_drip()
	assert_almost_eq(core.stress(1), 0.0, 0.0001, "来源离座 → 不传播学习加压")
	core._pos_x[0] -= 5.0  # 来源回座
	core._settle_neighbor_drip()
	assert_gt(core.stress(1), 0.0, "来源回座恢复传播")


# ------------------------------------------------------------------ J. 走动 / 找伴
## 交接 §走动与共同活动加入（第 45–57 条）：走动只是接近同学的方式、不是唯一加入资格；
## 自主找伴优先「自己对其好感最高」的合格对象，不突破学习／游戏锁定、崩溃休息或办公室占用；
## 关系拒绝后本决策点结束（`_decide_and_act` 每决策点只 `_propose_activity` 一次，不依次试第二第三对象）。


## 交接第 49 条：自主找伴读发起者→候选者的有向好感，选最高且可参与者；游戏锁定者被跳过。
func test_find_partner_prefers_highest_affinity_skips_play_locked() -> void:
	var core := _core()
	var n := core.node_count()
	core._begin_phase_state()
	for i in range(n):
		core._phase_state[i] = "free"
	for j in range(n):
		if j != 0:
			core._a[0 * n + j] = 0.0
	core._a[0 * n + 1] = 40.0
	core._a[0 * n + 2] = 60.0
	core._a[0 * n + 3] = 90.0  # 好感最高，但游戏锁定
	core._phase_state[3] = "play"
	assert_eq(core._find_partner(0, "roughhouse"), 2, "选好感最高且可参与的 2 号；游戏锁定的 3 号被跳过")


## 交接第 11 条 / 第 47 条：游戏锁定不被拉出 —— 向其提议属条件不满足，不算关系拒绝。
func test_propose_play_locked_target_is_condition_fail() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(core.node_count()):
		core._phase_state[i] = "free"
	core._phase_state[1] = "play"
	core._a[0 * core.node_count() + 1] = 60.0
	var rejects_before: int = int(core._stats.get("join_rejects", 0))
	assert_false(core._propose_activity(0, 1, "chat"), "游戏锁定不可被拉出")
	assert_eq(int(core._stats.get("join_rejects", 0)), rejects_before, "条件不满足不算关系拒绝")


## 交接 §状态锁定（第 2312–2313 条实现注）：学习锁定视同学习 —— 只可被请教加入，不被拉去别的活动。
func test_propose_study_locked_routes_to_study_join() -> void:
	var core := _core()
	core._begin_phase_state()
	for i in range(core.node_count()):
		core._phase_state[i] = "free"
	core._phase_state[1] = "study"
	core._a[1 * core.node_count() + 0] = 60.0
	core._h[1 * core.node_count() + 0] = 0.0
	core._do_study(1)
	core._ensure_group("study", 1)
	assert_true(core._propose_activity(0, 1, "chat"), "学习锁定不被拉去聊天，改为请教加入学习")
	assert_true(core._study_of[0] != null, "0 号以请教者身份进入学习组")
	assert_eq(core._conv_of[0], null, "没有建立聊天会话")


## 交接第 51 条：加入者不投票 —— 只有现有成员的一票算数，加入者自己的好感不能翻盘。
func test_vote_accept_joiner_does_not_vote() -> void:
	var core := _core()
	var n := core.node_count()
	core._a[1 * n + 0] = 0.0
	core._h[1 * n + 0] = 60.0  # 现有成员 1 对加入者 0 敌对高 → 投反对
	core._a[0 * n + 1] = 90.0  # 加入者 0 对成员 1 好感极高（但加入者不投票）
	var vote := core._vote_accept([1], 0)
	assert_false(vote["ok"], "只有成员 1 的一票：反对 → 拒绝，加入者 0 的好感不计入")


## 交接第 56–57 条：带朋友不邀请组内成员、不拉别组成员、不拉锁定者；选组外最高好感。
func test_find_friend_outside_skips_group_and_locked() -> void:
	var core := _core()
	var n := core.node_count()
	core._begin_phase_state()
	for i in range(n):
		core._phase_state[i] = "free"
	var grp := {"members": [0, 1]}
	core._a[0 * n + 2] = 60.0  # 组外最高好感
	core._a[0 * n + 3] = 90.0  # 更高，但游戏锁定
	core._phase_state[3] = "play"
	core._phase_state[5] = "study"  # 学习锁定
	core._study_of[5] = {"members": [5], "originator": 5}
	core._conv_of[4] = {"members": [4, 6]}  # 已在别的聊天组
	assert_eq(core._find_friend_outside(0, grp), 2, "选组外最高好感 2；跳过组内 1、锁定 3/5、别组 4")
