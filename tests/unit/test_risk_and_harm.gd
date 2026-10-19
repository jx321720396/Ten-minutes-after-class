extends GutTest
## 课间冲突（吵架 / 推搡 / 打架）与霸凌、孤立、退学回归。

const SEED := 20261016
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


func _ready_pair(core: SimCore, toward_b: float, toward_a: float) -> void:
	core._phase = "break"
	core._day = 1
	for i in range(2, core.node_count()):
		core._broken[i] = true
	core._broken[0] = false
	core._broken[1] = false
	for i in range(core.node_count()):
		for j in range(core.node_count()):
			core._h[i * core._n + j] = 0.0
	core._h[0 * core._n + 1] = toward_b
	core._h[1 * core._n + 0] = toward_a
	core._stress[0] = 10.0
	core._stress[1] = 10.0


func test_min_hostility_picks_quarrel_for_50_and_70() -> void:
	var core := _core()
	_ready_pair(core, 50.0, 70.0)
	core._harm_events.begin_break(core)
	assert_eq(core._harm_events.last_events().size(), 1, "50 和 70 发生一场冲突")
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "quarrel", "较低值 50 算吵架")
	assert_almost_eq(core.stress(0), 10.0, 0.0001, "吵架不改压力")
	assert_almost_eq(core.stress(1), 10.0, 0.0001, "吵架不改对方压力")


func test_tiers_and_natural_hostility() -> void:
	var core := _core()
	_ready_pair(core, 90.0, 100.0)
	core._harm_events.begin_break(core)
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "fight", "较低值 90 算打架")
	for _k in range(20):
		core._harm_events.tick(core)
	assert_almost_eq(core.hostility(0, 1), 50.0, 0.0001, "打架结束双方各 −40")
	assert_almost_eq(core.hostility(1, 0), 60.0, 0.0001, "另一方向同样 −40")
	assert_eq(core._harm_events.fight_count_of(0), 1, "档案累计打架 +1")
	assert_true(bool(core._risk._ever_fought[0]), "打架双方记曾经打过")
	assert_true(bool(core._risk._ever_fought[1]), "另一方也记曾经打过")


func test_quarrel_cooldown_and_mediate_stops_early() -> void:
	var core := _core()
	_ready_pair(core, 45.0, 55.0)
	core._harm_events.begin_break(core)
	assert_eq(str(core._harm_events.mediate(core, 0, 1)), "stopped", "调解立刻终止吵架")
	assert_almost_eq(core.hostility(0, 1), 50.0, 0.0001, "调解终止吵架只 +5")
	assert_almost_eq(core.hostility(1, 0), 60.0, 0.0001, "另一方向也只 +5")
	assert_eq(core._harm_events.active_kind(0), "", "终止后不再处于吵架")
	core._harm_events.begin_break(core)
	assert_eq(core._harm_events.last_events().size(), 0, "吵架当课间起四个课间内不能再吵架")


func test_fight_cannot_be_mediated_and_class_skips() -> void:
	var core := _core()
	_ready_pair(core, 95.0, 95.0)
	core._harm_events.begin_break(core)
	assert_eq(str(core._harm_events.mediate(core, 0, 1)), "fight", "打架不能调解终止")
	assert_eq(core._harm_events.active_kind(0), "fight", "打架还在进行")
	core._phase = "class"
	var before: int = core._harm_events.last_events().size()
	core._harm_events.begin_break(core)
	assert_eq(core._harm_events.last_events().size(), before, "上课段不重新判定")


func test_broken_student_is_excluded_and_study_is_not() -> void:
	var core := _core()
	_ready_pair(core, 80.0, 80.0)
	core._broken[0] = true
	core._harm_events.begin_break(core)
	assert_eq(core._harm_events.last_events().size(), 0, "崩溃学生不参加")
	core._broken[0] = false
	core._phase_state.resize(core.node_count())
	core._phase_state[0] = "study"
	core._harm_events.begin_break(core)
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "shove", "学习中的人仍参加推搡")


func test_friendly_finished_chat_cuts_hostility_by_two() -> void:
	var core := _core()
	core._begin_phase_state()
	var pair := _pair_without_forgiving(core)
	core._start_conversation(pair[0], pair[1])
	core._h[pair[0] * core._n + pair[1]] = 30.0
	core._h[pair[1] * core._n + pair[0]] = 30.0
	core._busy_act[pair[0]] = "chat"
	core._busy_phase[pair[0]] = 0
	core._busy_until[pair[0]] = 0
	core._settle_finished_actions()
	assert_almost_eq(core.hostility(pair[0], pair[1]), 28.0, 0.0001, "友善交流：双方敌对各 −2")
	assert_almost_eq(core.hostility(pair[1], pair[0]), 28.0, 0.0001, "友善交流：双向各自 −2")


func _pair_without_forgiving(core: SimCore) -> Array:
	var picked: Array = []
	for i in range(core.node_count()):
		if core.passive_id_of(i) == "forgiving":
			continue
		picked.append(i)
		if picked.size() == 2:
			break
	return picked


func test_mediate_without_conflict_cuts_ten() -> void:
	var core := _core()
	core._phase = "break"
	core._h[0 * core._n + 1] = 30.0
	core._h[1 * core._n + 0] = 20.0
	assert_true(core._teacher_commands.mediate(core, 0, 1), "没有进行中的冲突也可以调解")
	for _k in range(20):
		core._teacher_commands.tick(core)
	assert_almost_eq(core.hostility(0, 1), 20.0, 0.0001, "调解完成后双方敌对各 −10")
	assert_almost_eq(core.hostility(1, 0), 10.0, 0.0001, "另一方向同样 −10")
	assert_false(core._teacher_commands.mediate(core, 0, 1), "三个课间内不能再调解这对人")


func _make_bullied(core: SimCore, target: int) -> void:
	for k in range(3):
		core._h[k * core._n + target] = 60.0
	core._note_harm(0, target, "fight")


func _clear_enemies(core: SimCore, target: int) -> void:
	for k in range(3):
		core._h[k * core._n + target] = 0.0


func test_bully_needs_three_enemies_and_a_past_fight() -> void:
	var core := _core()
	_make_bullied(core, 5)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.warned_of(5), "满足霸凌条件的第一天只预警")
	assert_false(core._risk.triggered_of(5), "第一天不正式触发")
	assert_false(core._risk.is_dropped(5), "预警本身不辞退")


func test_bully_needs_a_past_fight() -> void:
	var core := _core()
	for k in range(3):
		core._h[k * core._n + 5] = 60.0
	core._risk.settle_day(core, 2)
	assert_false(core._risk.warned_of(5), "没打过架不判霸凌")


func test_isolate_needs_low_affinity_rejects_and_no_activity() -> void:
	var core := _core()
	for j in range(core.node_count()):
		if j == 5:
			continue
		core._a[j * core._n + 5] = 10.0
	for _k in range(2):
		core._risk.register_join_reject(5)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.warned_of(5), "好感低 + 当天被拒 2 次 + 没参加活动 → 孤立预警")
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
	_make_bullied(core, 5)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.triggered_of(5), "连续第二天正式触发")
	var fresh := _core()
	_make_bullied(fresh, 5)
	fresh._risk.settle_day(fresh, 2)
	_clear_enemies(fresh, 5)
	fresh._risk.settle_day(fresh, 3)
	_make_bullied(fresh, 5)
	fresh._risk.settle_day(fresh, 4)
	assert_false(fresh._risk.triggered_of(5), "中间一天敌对者不足则重置连续计数")


func test_exam_day_skips_judgement_but_keeps_streak() -> void:
	var core := _core()
	_make_bullied(core, 5)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.warned_of(5), "考前一天满足 → 预警")
	core._day = 8
	core._risk.settle_day(core, 8)
	assert_almost_eq(float(core._risk._streak[5]), 1.0, 0.0001, "考试日跳过判定但保留连续计数")
	_make_bullied(core, 5)
	core._day = 9
	core._risk.settle_day(core, 9)
	assert_true(core._risk.triggered_of(5), "考后第一个普通上学日再满足即算连续第二天")


func test_earliest_day_blocks_formal_trigger() -> void:
	var core := _core()
	_make_bullied(core, 5)
	core._risk.settle_day(core, 1)
	_make_bullied(core, 5)
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


func test_breakdown_before_trigger_is_not_counted_as_after() -> void:
	var core := _core()
	for _k in range(2):
		core._risk.register_breakdown(5)
	_make_bullied(core, 5)
	core._risk.settle_day(core, 2)
	_make_bullied(core, 5)
	core._risk.settle_day(core, 3)
	assert_true(core._risk.triggered_of(5), "正式触发霸凌")
	assert_false(core._risk.is_dropped(5), "触发之前的崩溃不回溯算作「后再一次」")


func test_three_breakdowns_alone_do_not_drop() -> void:
	var core := _core()
	for _k in range(3):
		core._risk.register_breakdown(7)
	core._risk.settle_day(core, 3)
	assert_false(core._risk.is_dropped(7), "恰好 3 次崩溃不退学（第 4 次才退）")
