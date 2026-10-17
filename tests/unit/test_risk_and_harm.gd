extends GutTest
## 《老师版规则合并稿》D06（风险判定 / 预警 / 退学）与 D07（伤害事件与关系修复）回归。
## 口径见主文档 §10「实施口径（2026-10-16 定稿）」与 §11.2。

const SEED := 20261016
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


## 让 0 号与 1 号成为正交邻座，其余学生隔离（崩溃 → 不参与伤害）。
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
					core._seat_of[i] = str(a)
				core._phase_state[0] = "free"
				core._phase_state[1] = "free"
				core._current_act[0] = null
				core._current_act[1] = null
				core._stress[0] = 0.0
				core._stress[1] = 0.0
				return true
	return false


## 进入课间并让 0 号必触发一次伤害检查（0 → 1 的敌对设为 hostility）。
func _arm(core: SimCore, hostility: float) -> void:
	core._phase = "break"
	core._harm_events.begin_phase(core.node_count())
	core._harm_events._trigger_p = 1.0  # 必触发，仅测门槛与类型选择
	core._h[0 * core._n + 1] = hostility


# ------------------------------------------------------------------ D07 伤害
func test_aggression_threshold_is_strictly_above_40() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	_arm(core, 40.0)  # 恰好 40：没有合格目标
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "恰好 40 不触发恶语攻击")
	_arm(core, 41.0)
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 1, "> 40 触发恶语攻击")
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "aggression", "归类为恶语攻击")


func test_shove_only_when_hostility_above_70() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._harm_events._shove_choice_p = 1.0  # 必选推搡（只在 >70 时可选）
	_arm(core, 70.0)
	core._harm_events.check(core)
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "aggression", "恰好 70 只能恶语攻击")
	_arm(core, 71.0)
	core._harm_events.check(core)
	assert_eq(str(core._harm_events.last_events()[0]["kind"]), "shove", "> 70 才可能推搡")


func test_shove_choice_follows_configuration() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._harm_events._shove_choice_p = 0.0  # >70 时一律选恶语
	_arm(core, 90.0)
	core._harm_events.check(core)
	assert_eq(
		str(core._harm_events.last_events()[0]["kind"]), "aggression", ">70 时用选择概率决定类型（0 → 恶语）"
	)


func test_aggression_raises_target_stress_and_hostility() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	_arm(core, 60.0)
	var stress_before := core.stress(1)
	var hostility_before := core.hostility(1, 0)
	core._harm_events.check(core)
	assert_almost_eq(core.stress(1), stress_before + 5.0, 0.0001, "恶语：目标压力 +5")
	assert_almost_eq(core.hostility(1, 0), hostility_before + 3.0, 0.0001, "恶语：目标对发起者敌对 +3")


func test_shove_interrupts_target_activity() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	core._harm_events._shove_choice_p = 1.0
	_arm(core, 90.0)
	core._current_act[1] = "listen_music"
	core._busy_until[1] = 9999
	core._harm_events.check(core)
	assert_eq(core._current_act[1], null, "推搡中断目标当前活动")
	assert_eq(core._busy_until[1], 0, "推搡清掉占用")


func test_study_locked_and_broken_students_do_not_take_part() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	_arm(core, 60.0)
	core._phase_state[0] = "study"
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "学习锁定的学生不参与伤害")
	_arm(core, 60.0)
	core._broken[1] = true
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "崩溃学生不参与伤害")
	core._broken[1] = false
	_arm(core, 60.0)
	core._phase_state[1] = "study"
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "学习锁定的目标不参与伤害")


func test_only_one_harm_per_student_per_break() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	_arm(core, 60.0)
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 1, "第一次检查触发一次伤害")
	core._h[0 * core._n + 1] = 60.0
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "同一课间同一发起者不再主动伤害")
	core._harm_events.begin_phase(core.node_count())
	core._h[0 * core._n + 1] = 60.0
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 1, "新课间恢复一次机会")


func test_stopped_student_cannot_start_harm() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	_arm(core, 60.0)
	core._note_stopped(0)  # 老师完成现场制止 / 调解 / 召唤
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "被老师制止的学生本课间不能再发起伤害")
	core._begin_phase()
	core._phase = "break"
	core._harm_events.begin_phase(core.node_count())
	core._h[0 * core._n + 1] = 60.0
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 1, "下一个课间恢复发起资格")


func test_harm_event_records_time_and_direction() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	_arm(core, 60.0)
	core._harm_events.check(core)
	var event: Dictionary = core._harm_events.last_events()[0]
	assert_eq(int(event["from"]), 0, "记录发起者")
	assert_eq(int(event["to"]), 1, "记录目标")
	assert_true(event.has("tick"), "记录发生时间")


func test_harm_requires_break_contact() -> void:
	var core := _core()
	assert_true(_pair_for_harm(core), "座位表里应存在正交邻座对")
	_arm(core, 60.0)
	core._phase = "class"
	core._harm_events.check(core)
	assert_eq(core._harm_events.last_events().size(), 0, "上课段不发生伤害（课间接触才判）")


func test_friendly_finished_chat_cuts_hostility_by_two() -> void:
	var core := _core()
	core._begin_phase_state()
	# 基础规则用例：挑两名**不带「不记仇」**的学生，免得被动额外 −2 混进基础断言
	# （不记仇的追加修复见 tests/unit/test_passives.gd 的专用用例）。
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


## 两名不带「不记仇」被动的学生（该被动由 data/rules/passives.csv 分配到 08 号角色）。
func _pair_without_forgiving(core: SimCore) -> Array:
	var picked: Array = []
	for i in range(core.node_count()):
		if core.passive_id_of(i) == "forgiving":
			continue
		picked.append(i)
		if picked.size() == 2:
			break
	return picked


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
	assert_true(core._is_stopped_by_teacher(0), "调解完成后涉及的双方本课间不能再主动伤害")


# ------------------------------------------------------------------ D06 风险
func _make_bullied(core: SimCore, target: int) -> void:
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
	core._risk.settle_day(core, 2)
	assert_false(core._risk.warned_of(5), "没受到伤害不判霸凌")


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
	fresh._risk.settle_day(fresh, 3)  # 第二天不满足 → 重置连续计数
	_make_bullied(fresh, 5)
	fresh._risk.settle_day(fresh, 4)
	assert_false(fresh._risk.triggered_of(5), "中间一天不满足则重置连续计数")


func test_exam_day_skips_judgement_but_keeps_streak() -> void:
	var core := _core()
	_make_bullied(core, 5)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.warned_of(5), "考前一天满足 → 预警")
	# 第 8 天是考试日：不判定、也不重置连续计数
	core._day = 8
	core._risk.settle_day(core, 8)
	assert_almost_eq(float(core._risk._streak[5]), 1.0, 0.0001, "考试日跳过判定但保留连续计数")
	_make_bullied(core, 5)
	core._day = 9  # 考后第一个普通上学日
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
		core._risk.register_breakdown(5)  # 触发前的崩溃
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
