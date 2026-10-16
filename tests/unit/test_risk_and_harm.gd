extends GutTest
## 《老师版规则合并稿》D06（风险判定 / 预警 / 退学）与 D07（伤害事件与关系修复）回归（2026-10-16）。

const SEED := 20261016
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


## 让 0 号与 1 号成为正交邻座并只保留他们两个可参与伤害检查。
func _pair_for_harm(core: SimCore) -> bool:
	core._begin_phase_state()
	for i in range(2, core.node_count()):
		core._phase_state[i] = "broken"
	var seats: Array = core._seat_pos.keys()
	for a in seats:
		if not core._neighbors.has(a):
			continue
		for b in core._neighbors[a]:
			core._seat_of[0] = a
			core._seat_of[1] = str(b)
			if core._are_neighbors(0, 1):
				for i in range(2, core.node_count()):
					core._seat_of[i] = str(a)  # 其余人挪远，避免意外邻接
				core._phase_state[0] = "free"
				core._phase_state[1] = "free"
				core._current_act[0] = null
				core._current_act[1] = null
				core._stress[0] = 0.0
				core._stress[1] = 0.0
				return true
	return false


# ------------------------------------------------------------------ D07 伤害
func test_aggression_threshold_is_strictly_above_40() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._phase = "break"
	core._harm_events._aggression_p = 1.0  # 必触发，仅测门槛
	core._harm_events._shove_p = 1.0
	core._h[0 * core._n + 1] = 40.0  # 恰好 40：不满足
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "恰好 40 不触发恶语攻击")
	core._h[0 * core._n + 1] = 41.0
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 1, "> 40 触发恶语攻击")
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "aggression", "归类为恶语攻击")


func test_shove_threshold_is_strictly_above_70() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._phase = "break"
	core._harm_events._aggression_p = 1.0
	core._harm_events._shove_p = 1.0
	core._h[0 * core._n + 1] = 70.0
	core._harm_events.check(core)
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "aggression", "恰好 70 只到恶语档")
	core._h[0 * core._n + 1] = 71.0
	core._harm_events.check(core)
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "shove", "> 70 归为推搡")


func test_aggression_raises_target_stress_and_hostility() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._phase = "break"
	core._harm_events._aggression_p = 1.0
	core._h[0 * core._n + 1] = 60.0
	var stress_before := core.stress(1)
	var hostility_before := core.hostility(1, 0)
	core._harm_events.check(core)
	assert_almost_eq(core.stress(1), stress_before + 5.0, 0.0001, "恶语：目标压力 +5（待定值）")
	assert_almost_eq(core.hostility(1, 0), hostility_before + 3.0, 0.0001, "恶语：目标对发起者敌对 +3（待定值）")


func test_shove_interrupts_target_activity() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._phase = "break"
	core._harm_events._shove_p = 1.0
	core._h[0 * core._n + 1] = 90.0
	core._current_act[1] = "listen_music"
	core._busy_until[1] = 9999
	core._harm_events.check(core)
	assert_eq(core._current_act[1], null, "推搡中断目标当前活动")
	assert_eq(core._busy_until[1], 0, "推搡清掉占用")


func test_study_locked_and_broken_students_do_not_take_part() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._phase = "break"
	core._harm_events._aggression_p = 1.0
	core._h[0 * core._n + 1] = 60.0
	# 发起者学习锁定 → 不参与
	core._phase_state[0] = "study"
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "学习锁定的学生不参与伤害")
	# 目标崩溃 → 不参与
	core._phase_state[0] = "free"
	core._broken[1] = true
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "崩溃学生不参与伤害")
	core._broken[1] = false
	core._phase_state[1] = "study"
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "学习锁定的目标不参与伤害")


func test_only_one_harm_per_student_per_break() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._phase = "break"
	core._harm_events.begin_phase(core.node_count())
	core._harm_events._aggression_p = 1.0
	core._h[0 * core._n + 1] = 60.0
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 1, "第一次检查触发一次伤害")
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "同一课间同一发起者不再主动伤害")
	core._harm_events.begin_phase(core.node_count())
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 1, "新课间恢复一次机会")


func test_stopped_student_cannot_start_harm() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._phase = "break"
	core._harm_events.begin_phase(core.node_count())
	core._harm_events._aggression_p = 1.0
	core._h[0 * core._n + 1] = 60.0
	core._teacher_commands.summon(core, 0)  # 老师把 0 号叫到办公室
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "被老师制止的学生本课间不能再发起伤害")


func test_harm_requires_break_contact() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._harm_events._aggression_p = 1.0
	core._h[0 * core._n + 1] = 60.0
	core._phase = "class"
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "上课段不发生伤害（课间接触才判）")


func test_friendly_finished_chat_cuts_hostility_by_two() -> void:
	var core := _core()
	core._begin_phase_state()
	core._start_conversation(0, 1)
	core._h[0 * core._n + 1] = 30.0
	core._h[1 * core._n + 0] = 30.0
	# 模拟聊天占用自然到期（完成）
	core._busy_act[0] = "chat"
	core._busy_phase[0] = 0
	core._busy_until[0] = 0
	core._settle_finished_actions()
	assert_almost_eq(core.hostility(0, 1), 28.0, 0.0001, "友善交流：双方敌对各 −2")
	assert_almost_eq(core.hostility(1, 0), 28.0, 0.0001, "友善交流：双向各自 −2")


func test_mediate_cuts_hostility_only_above_50() -> void:
	var core := _core()
	core._h[0 * core._n + 1] = 40.0
	core._h[1 * core._n + 0] = 40.0
	assert_false(core._teacher_commands.mediate(core, 0, 1), "两方向都不超过 50：不执行调解")
	core._h[0 * core._n + 1] = 60.0
	assert_true(core._teacher_commands.mediate(core, 0, 1), "任一方超过 50：执行调解")
	for _k in range(30):
		core._teacher_commands.tick(core)
	assert_almost_eq(core.hostility(0, 1), 55.0, 0.0001, "调解完成后双方敌对各 −5")
	assert_almost_eq(core.hostility(1, 0), 35.0, 0.0001, "调解对另一方向同样 −5")


# ------------------------------------------------------------------ D06 风险
func _make_bullied(core: SimCore, target: int) -> void:
	# 3 名同学对目标敌对 >50，且当天由其中一人发起伤害。
	for k in range(3):
		core._h[k * core._n + target] = 60.0
	core._note_harm(0, target, "aggression")


func test_bully_needs_three_enemies_and_daily_harm() -> void:
	var core := _core()
	_make_bullied(core, 5)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.warned_of(5), "满足霸凌条件的第一天只预警（D06）")
	assert_false(core._risk.triggered_of(5), "第一天不正式触发")
	assert_false(core._risk.is_dropped(5), "预警本身不辞退")


func test_bully_needs_daily_harm_from_those_enemies() -> void:
	var core := _core()
	for k in range(3):
		core._h[k * core._n + 5] = 60.0
	# 有 3 名敌对者，但当天没受到这些人发起的伤害 → 不算霸凌。
	core._risk.settle_day(core, 2)
	assert_false(core._risk.warned_of(5), "没受到伤害不判霸凌")


func test_isolate_needs_low_affinity_rejects_and_no_activity() -> void:
	var core := _core()
	for j in range(core.node_count()):
		if j == 5:
			continue
		core._a[j * core._n + 5] = 10.0  # 所有人对 5 号好感 <20
	for _k in range(2):
		core._risk.register_join_reject(5)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.warned_of(5), "好感低 + 当天被拒 2 次 + 没参加活动 → 孤立预警")
	# 有成功参加共同活动 → 不判孤立
	core._risk._streak[5] = 0
	core._risk._warned[5] = false
	core._risk.register_activity(5)
	for _k in range(2):
		core._risk.register_join_reject(5)
	core._risk.settle_day(core, 2)
	assert_false(core._risk.warned_of(5), "当天成功参加共同活动 → 不算孤立")


func test_trigger_on_second_consecutive_day_and_reset() -> void:
	var core := _core()
	_make_bullied(core, 5)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.warned_of(5), "第 1 天预警")
	_make_bullied(core, 5)  # 第 2 天：重新登记当天的伤害
	core._risk.settle_day(core, 2)
	assert_true(core._risk.triggered_of(5), "连续第二天正式触发")
	# 中间一天不满足 → 连续计数重置
	var fresh := _core()
	_make_bullied(fresh, 5)
	fresh._risk.settle_day(fresh, 2)
	fresh._risk.settle_day(fresh, 3)  # 第二天不满足（没有当天伤害）→ 重置连续计数
	_make_bullied(fresh, 5)
	fresh._risk.settle_day(fresh, 4)  # 重新满足 → 回到第 1 天（预警）
	assert_false(fresh._risk.triggered_of(5), "中间一天不满足则重置连续计数")


func test_earliest_day_blocks_formal_trigger() -> void:
	var core := _core()
	_make_bullied(core, 5)
	core._risk.settle_day(core, 1)
	core._note_harm(0, 5, "aggression")
	core._risk.settle_day(core, 1)
	assert_false(core._risk.triggered_of(5), "第一个上学日结束只预警（earliest_day = 2）")


func test_dropout_on_fourth_breakdown() -> void:
	var core := _core()
	for _k in range(4):
		core._risk.register_breakdown(3)
	core._risk.settle_day(core, 3)
	assert_true(core._risk.is_dropped(3), "累计崩溃超过 3 次（第 4 次）→ 退学")
	assert_true(core._class_failed(), "出现退学 → 老师被辞退")


func test_dropout_after_triggered_risk_breakdown() -> void:
	var core := _core()
	_make_bullied(core, 5)
	core._risk.settle_day(core, 2)
	_make_bullied(core, 5)
	core._risk.settle_day(core, 3)
	assert_true(core._risk.triggered_of(5), "正式触发霸凌")
	core._risk.register_breakdown(5)
	core._risk.settle_day(core, 4)
	assert_true(core._risk.is_dropped(5), "正式触发风险后再崩溃一次 → 退学")


func test_three_breakdowns_alone_do_not_drop() -> void:
	var core := _core()
	for _k in range(3):
		core._risk.register_breakdown(7)
	core._risk.settle_day(core, 3)
	assert_false(core._risk.is_dropped(7), "恰好 3 次崩溃不退学（第 4 次才退）")
