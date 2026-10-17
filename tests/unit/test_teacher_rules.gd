extends GutTest
## 《老师版规则合并稿 D01至D07》第一阶段落地回归（2026-10-16）：
## D01 开局分布 / 跨天继承 / 动力状态机 / 崩溃入口；D02 单位结算与中断折算；D03 老师命令与上课延后。

const SEED := 20261016
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


## 隔离除 0 号以外的所有学生（"broken" 不参与决策与结算），让用例只观察 0 号。
func _isolate_others(core: SimCore, keep_free: bool = false) -> void:
	core._begin_phase_state()
	for i in range(1, core.node_count()):
		core._phase_state[i] = "broken" if not keep_free else "free"


func test_initial_distribution_follows_d01() -> void:
	var core := _core()
	var total := 0.0
	for i in range(core.node_count()):
		var stress := core.stress(i)
		assert_true(stress >= 0.0 and stress <= 20.0, "开局压力 0–20（D01）")
		assert_almost_eq(core.vitality(i), stress, 0.0001, "开局动力 = 该生压力（D01）")
		var grade := core.grade(i)
		assert_true(grade >= 250.0 and grade <= 450.0, "开局成绩 250–450（D01）")
		total += grade
	assert_almost_eq(total / float(core.node_count()), 350.0, 60.0, "开局平均成绩落在 250–450 的中段（D01）")


func test_phase_state_follows_vitality_thresholds() -> void:
	var core := _core()
	core._vitality[0] = 70.0
	core._vitality[1] = 20.0
	core._vitality[2] = 45.0
	core._begin_phase_state()
	assert_eq(core.phase_state_of(0), "study", "动力 >60 → 学习状态（D01）")
	assert_eq(core.phase_state_of(1), "play", "动力 <30 → 游戏状态（D01）")
	assert_eq(core.phase_state_of(2), "free", "两者之间 → 自由状态（D01）")


func test_study_settles_every_20_seconds() -> void:
	var core := _core()
	_isolate_others(core)
	core._phase_state[0] = "study"
	var gain_before := core.gain_today(0)
	var vitality_before := core.vitality(0)
	for _t in range(20):
		core._settle_units()
	assert_almost_eq(core.gain_today(0), gain_before + 1.0, 0.0001, "学习每 20 秒 +1 学业收益（D02）")
	assert_almost_eq(core.vitality(0), vitality_before - 5.0, 0.0001, "学习每 20 秒 -5 动力（D02）")


func test_leisure_relieves_every_10_seconds() -> void:
	var core := _core()
	_isolate_others(core)
	core._stress[0] = 50.0
	core._phase_state[0] = "free"
	core._current_act[0] = "listen_music"
	for _t in range(10):
		core._settle_units()
	assert_almost_eq(core.stress(0), 45.0, 0.0001, "娱乐每 10 秒 -5 压力（D02）")


func test_play_state_costs_gain_and_relieves_stress_without_vitality_cost() -> void:
	var core := _core()
	_isolate_others(core)
	core._stress[0] = 50.0
	core._vitality[0] = 30.0
	core._phase_state[0] = "play"
	var gain_before := core.gain_today(0)
	for _t in range(20):
		core._settle_units()
	assert_almost_eq(core.gain_today(0), gain_before - 1.0, 0.0001, "游戏每 20 秒 -1 学业收益（D02）")
	assert_almost_eq(core.stress(0), 45.0, 0.0001, "游戏每 20 秒 -5 压力（D02）")
	assert_almost_eq(core.vitality(0), 30.0, 0.0001, "游戏不减少动力（D02）")


func test_interrupted_activity_folds_by_time() -> void:
	var core := _core()
	_isolate_others(core)
	core._stress[0] = 50.0
	core._phase_state[0] = "free"
	core._current_act[0] = "listen_music"
	for _t in range(5):
		core._settle_units()
	core._fold_pending_unit(0)
	assert_almost_eq(core.stress(0), 48.0, 0.0001, "5 秒被打断 → 按每 2 秒 1 点折算 2 点（D02 第 4 条）")


func test_day_carry_follows_d01() -> void:
	var core := _core()
	for i in range(core.node_count()):
		core._stress[i] = 0.0
		core._gain_today[i] = 0.0
	core._stress[0] = 60.0
	core._vitality[0] = 40.0
	core._gain_today[0] = 8.0
	var grade_before := core.grade(0)
	core._settle_day()
	assert_almost_eq(core.stress(0), 40.0, 0.0001, "跨天压力单独 −20（D01）")
	assert_almost_eq(core.vitality(0), 30.0, 0.0001, "跨天动力单独 −10（D01）")
	assert_almost_eq(core.grade(0), minf(grade_before + 8.0, 750.0), 0.0001, "成绩 += 当日学业收益（D01）")
	assert_almost_eq(core.gain_today(0), 0.0, 0.0001, "学业收益跨天清零（D01）")


func test_breakdown_enters_rest_and_recovers_next_day() -> void:
	var core := _core()
	core._begin_phase_state()
	core._stress[0] = 95.0
	core._vitality[0] = 60.0
	core._check_breakdown()
	assert_true(core.is_broken(0), "压力 >90 → 崩溃（D01 / D06）")
	assert_true(core._sleeping[0], "崩溃休息：当天只睡觉（§5.3）")
	assert_eq(core._unit_kind(0), "", "崩溃休息的睡觉不作为邻座学习来源，也不产生学业收益")
	assert_eq(core.phase_state_of(0), "broken", "崩溃者不参与决策与座位结算")
	# 旧出口已废止：压力降到下限也不会即时恢复
	core._stress[0] = 10.0
	core._check_breakdown()
	assert_true(core.is_broken(0), "旧的「压力 <70 即时恢复」出口已废止")
	# 次日跨天：压力／动力各 −50（替代普通 −20／−10），并解除休息
	core._stress[0] = 90.0
	core._vitality[0] = 90.0
	core._resting[0] = true
	core._knot_days[0] = 0  # 隔离心结，只看崩溃次日恢复本身
	for j in core._neighbor_idx[0]:
		core._knot_days[int(j)] = 0
	core._day = 6
	core._settle_day()
	assert_false(core.is_broken(0), "崩溃休息在次日跨天时解除（§5.3）")
	assert_almost_eq(core.stress(0), 40.0, 0.0001, "次日压力 −50（替代普通 −20）")
	assert_almost_eq(core.vitality(0), 40.0, 0.0001, "次日动力 −50（替代普通 −10，且不联动）")


func test_breakdown_gives_knot_to_self_and_orthogonal_neighbours_only() -> void:
	var core := _core()
	core._begin_phase_state()
	core._neighbor_idx[0] = [1]
	core._stress[0] = 95.0
	core._check_breakdown()
	assert_eq(core._knot_days[0], 3, "崩溃者本人获得心结，天数为 3（§5.3）")
	assert_eq(core._knot_days[1], 3, "正交邻座同样获得心结")
	assert_eq(core._knot_days[2], 0, "非邻座不会获得（不遍及全班、不传染）")


func test_knot_repeats_refresh_without_stacking() -> void:
	var core := _core()
	core._begin_phase_state()
	core._neighbor_idx[0] = [1]
	core._stress[0] = 95.0
	core._check_breakdown()
	core._knot_days[0] = 1  # 手动消耗两天后再次崩溃
	core._broken[0] = false
	core._stress[0] = 96.0
	core._check_breakdown()
	assert_eq(core._knot_days[0], 3, "重复获得只刷新为 3 天，不叠层")


func test_knot_raises_stress_and_vitality_daily_for_three_days() -> void:
	var core := _core()
	core._knot_days[0] = 3
	core._stress[0] = 30.0
	core._vitality[0] = 30.0
	for _d in range(3):
		core._day = 6
		core._stress[0] = 30.0
		core._vitality[0] = 30.0
		core._settle_day()
	# 跨天 −20／−10 后再心结 +10（动力按一般规则同步 +10）
	assert_almost_eq(core._knot_days[0], 0.0, 0.0001, "第三次生效后心结结束")
	assert_almost_eq(core.stress(0), 20.0, 0.0001, "每天压力净 −10（−20 跨天 +10 心结）")
	assert_almost_eq(core.vitality(0), 30.0, 0.0001, "动力按一般规则同步 +10")


func test_teacher_summon_arrives_instantly_then_office_chat_timings() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	assert_true(tc.summon(core, 3), "可以召唤一名学生（D03）")
	assert_eq(tc.remaining_seconds(), 0, "召唤即时到达，不再等待路程（2026-10-16 裁定）")
	assert_eq(tc.current_command(), "", "召唤当场完成")
	assert_true(core._is_in_office(3), "被召唤的学生立刻在办公室")
	assert_false(tc.summon(core, 5), "办公室同时只能召唤一名学生（D03）")
	assert_true(tc.office_chat(core, "scold"), "到达后可以立即开始办公室聊天")
	assert_eq(tc.remaining_seconds(), 20, "办公室聊天统一 20 秒（D03）")
	var before := core.stress(3)
	var vitality_before := core.vitality(3)
	for _t in range(20):
		tc.tick(core)
	assert_almost_eq(core.stress(3), minf(before + 30.0, 100.0), 0.0001, "训斥 +30 压力")
	assert_almost_eq(core.vitality(3), minf(vitality_before + 30.0, 100.0), 0.0001, "训斥 +30 动力")


func test_praise_adds_only_the_targets_vitality() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	core._stress[4] = 40.0
	core._vitality[4] = 40.0
	core._stress[5] = 40.0
	core._vitality[5] = 40.0
	assert_true(tc.summon(core, 4), "可以召唤被表扬的学生")
	assert_true(tc.office_chat(core, "praise"), "表扬走与训斥相同的办公室聊天")
	assert_eq(tc.remaining_seconds(), 20, "表扬同样耗时 20 秒")
	for _t in range(19):
		tc.tick(core)
	assert_almost_eq(core.vitality(4), 40.0, 0.0001, "谈话未完成前不加动力")
	tc.tick(core)
	assert_almost_eq(core.vitality(4), 55.0, 0.0001, "表扬只给该生 +15 动力")
	assert_almost_eq(core.stress(4), 40.0, 0.0001, "表扬不加压力")
	assert_almost_eq(core.vitality(5), 40.0, 0.0001, "不影响其他学生的动力")
	assert_almost_eq(core.stress(5), 40.0, 0.0001, "不影响其他学生的压力")


func test_ask_once_per_break() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	assert_true(tc.summon(core, 0), "可以召唤被打听的学生")
	assert_true(tc.office_chat(core, "ask"), "打听走办公室聊天")
	assert_eq(tc.remaining_seconds(), 20, "打听耗时 20 秒")
	for _t in range(20):
		tc.tick(core)
	assert_gt(int(tc.snapshot()["ask_id"]), 0, "打听完成后给出消息")
	assert_false(tc.office_chat(core, "ask"), "本课间已打听过，不再扣时")
	assert_eq(tc.current_command(), "", "没有新命令")
	tc.begin_break()
	assert_true(tc.office_chat(core, "ask"), "新课间可再次打听")


func test_ask_relation_records_directed_single_axis() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	var speaker := _student_without_extra_messages(core)
	assert_true(tc.summon(core, speaker), "召唤受访者")
	assert_true(tc.office_chat(core, "ask"), "发起打听")
	for _t in range(20):
		tc.tick(core)
	var records: Array = tc.snapshot()["ask_records"]
	assert_eq(records.size(), 3, "普通学生恰 3 条有向单轴关系信息")
	for rec in records:
		assert_eq(int(rec["source"]), speaker, "方向固定受访者→对象")
		assert_ne(int(rec["subject"]), speaker, "对象不是本人")
		assert_true(str(rec["axis"]) in ["affinity", "hostility"], "每条只含一轴")
		assert_true(rec.has("value") and rec.has("day") and rec.has("phase_id"), "带值、时间与来源")
		var line := tc._relation_line(core, rec)
		assert_true(line.contains("好感") or line.contains("敌对"), "关系文案含轴名")


func test_ask_well_informed_reports_up_to_six() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	var speaker := -1
	for i in range(core.node_count()):
		if core.passive_id_of(i) == "well_informed":
			speaker = i
	assert_ne(speaker, -1, "本局有百事通")
	assert_true(tc.summon(core, speaker))
	assert_true(tc.office_chat(core, "ask"))
	for _t in range(20):
		tc.tick(core)
	var records: Array = tc.snapshot()["ask_records"]
	assert_eq(records.size(), 6, "百事通一次打听 6 条关系信息")
	for rec in records:
		assert_eq(int(rec["source"]), speaker, "方向受访者→对象")


func test_ask_discloses_band_not_raw_value() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	assert_eq(tc._disclose_band(80.0), "很高")
	assert_eq(tc._disclose_band(50.0), "较高")
	assert_eq(tc._disclose_band(25.0), "一般")
	assert_eq(tc._disclose_band(24.0), "较低")
	var rec := {"source": 0, "subject": 1, "axis": "affinity", "value": 80.0}
	assert_eq(
		tc._relation_line(core, rec), "我（%s）对%s的好感：很高" % [core.alias(0), core.alias(1)], "关系文案用档位"
	)


func test_ask_priority_hostility_hint() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	var n := core.node_count()
	for j in range(n):
		for k in range(n):
			if j != k:
				core._h[j * n + k] = 0.0
	for j in range(n):
		if j != 5:
			core._h[j * n + 5] = 60.0
	assert_eq(tc._hostility_hint_targets(core), [5], "仅目标 5 构成敌对隐患")
	var msg := tc._pick_priority_message(core, 0)
	assert_true(msg.contains(core.alias(5)), "优先消息指出敌对隐患目标")
	assert_true(msg.contains("敌意"), "敌对隐患文案")


func test_ask_deterministic_same_seed() -> void:
	var core_a := _core()
	var core_b := _core()
	var tc_a := core_a.teacher_commands()
	var tc_b := core_b.teacher_commands()
	assert_true(tc_a.summon(core_a, 0))
	assert_true(tc_b.summon(core_b, 0))
	assert_true(tc_a.office_chat(core_a, "ask"))
	assert_true(tc_b.office_chat(core_b, "ask"))
	for _t in range(20):
		tc_a.tick(core_a)
		tc_b.tick(core_b)
	assert_eq(tc_a.snapshot()["ask_lines"], tc_b.snapshot()["ask_lines"], "同种子打听结果一致")
	assert_eq(tc_a.snapshot()["ask_records"], tc_b.snapshot()["ask_records"], "关系记录一致")


func _student_without_extra_messages(core: SimCore) -> int:
	for i in range(core.node_count()):
		var extra := int(core.teacher_student_snapshot(i).get("well_informed_messages", 0))
		if extra == 0:
			return i
	return 0


func test_teacher_enter_classroom_once_per_break() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	var before := core.stress(0)
	assert_true(tc.enter_classroom(core), "本课间首次进入生效（D03）")
	assert_false(tc.enter_classroom(core), "同一课间不重复生效（D03）")
	assert_almost_eq(core.stress(0), minf(before + 5.0, 100.0), 0.0001, "首次进教室全班 +5 压力（D01）")
	tc.begin_break()
	assert_true(tc.enter_classroom(core), "下一个课间恢复一次生效机会（D03）")


func test_teacher_command_deferred_by_class() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	assert_true(tc.summon(core, 2), "召唤即时到达（2026-10-16 裁定）")
	assert_true(tc.office_chat(core, "scold"), "到达后立即开始 20 秒的办公室聊天")
	tc.tick(core)
	var remaining := tc.remaining_seconds()
	tc.begin_class(core)
	assert_true(tc.is_held(), "上课期间命令挂起（D03 第 9 条）")
	tc.tick(core)
	assert_eq(tc.remaining_seconds(), remaining, "上课期间不推进耗时、不产生效果（D03 第 9 条）")
	tc.begin_break()
	tc.tick(core)
	assert_eq(tc.remaining_seconds(), remaining - 1, "下课后续跑（当前按「保留已用时间」，待确认）")


func test_seat_change_applies_after_10_seconds() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	var seat_a := core.seat_of(0)
	var seat_b := core.seat_of(1)
	assert_true(tc.start_seat_change(core, 0, 1), "可以发起调座位（D03 第 4 条）")
	assert_eq(core.seat_of(0), seat_a, "10 秒内尚未生效（D03 第 4 条）")
	for _t in range(10):
		tc.tick(core)
	assert_eq(core.seat_of(0), seat_b, "10 秒后生效：座位交换（D03 第 4 条）")
	assert_eq(core.seat_of(1), seat_a, "两人的座位互换")


func test_seat_change_parks_neighbor_drip() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	core._begin_phase_state()
	core._phase_state[0] = "study"
	core._phase_state[1] = "free"
	var seat0 := str(core._seat_of[0])
	var neighbor_seat := ""
	for seat_id in core._neighbors[seat0]:
		neighbor_seat = str(seat_id)
		break
	core._seat_of[1] = neighbor_seat
	core._build_neighbor_idx()
	core._stress[1] = 0.0
	assert_true(tc.start_seat_change(core, 0, 1), "换座窗口开始")
	core._settle_neighbor_drip()
	assert_almost_eq(core.stress(1), 0.0, 0.0001, "换座期间不参加课间涓流（D03 第 5 条）")


func test_class_phase_enters_study_above_30_and_never_plays() -> void:
	var core := _core()
	core._phase = "class"
	core._vitality[0] = 31.0
	core._vitality[1] = 30.0
	core._vitality[2] = 5.0
	core._begin_phase_state()
	assert_eq(core.phase_state_of(0), "study", "上课：动力 >30 → 学习状态")
	assert_eq(core.phase_state_of(1), "free", "上课：恰好 30 → 自由")
	assert_eq(core.phase_state_of(2), "free", "上课：低动力也是自由，不进入游戏状态")


func test_class_study_is_sticky_and_settles_gain() -> void:
	var core := _core()
	core._phase = "class"
	core._vitality[0] = 31.0
	core._begin_phase_state()
	assert_eq(core.phase_state_of(0), "study", "上课开始进入学习状态")
	var gain_before := core.gain_today(0)
	for _k in range(40):
		core._settle_units()
	assert_almost_eq(core.vitality(0), 21.0, 0.0001, "学习每 20 秒 −5 动力（两次 → 21）")
	assert_eq(core.phase_state_of(0), "study", "段内粘性：跌破 30 仍保持学习到段末")
	assert_almost_eq(core.gain_today(0), gain_before + 2.0, 0.0001, "上课学习正常结算学业收益")


func test_class_phase_state_is_decided_once_per_phase() -> void:
	var core := _core()
	core._phase = "class"
	core._vitality[0] = 31.0
	core._begin_phase_state()
	core._vitality[0] = 1.0  # 段中动力暴跌，不重判（段首一次）
	core._begin_phase_state()
	assert_eq(core.phase_state_of(0), "free", "再次调用段首判定才会按新动力重算")


func test_leisure_units_do_not_settle_during_class() -> void:
	var core := _core()
	core._phase = "class"
	core._begin_phase_state()  # 先按段首判定建好状态数组
	core._phase_state[0] = "free"
	core._current_act[0] = "listen_music"
	core._stress[0] = 50.0
	core._vitality[0] = 50.0
	for _k in range(20):
		core._settle_units()
	assert_almost_eq(core.stress(0), 50.0, 0.0001, "上课不执行娱乐单位（不减压）")


func test_failure_reason_reports_dropout_with_evidence() -> void:
	var core := _core()
	for _k in range(4):
		core._risk.register_breakdown(3)
	core._risk.settle_day(core, 3)
	assert_true(core._risk.is_dropped(3), "累计第 4 次崩溃 → 退学（D06）")
	var reason := core._failure_reason()
	assert_ne(reason, "", "已辞退时必须给出原因")
	assert_true(reason.contains("退学"), "原因说明触发了退学判据")
	assert_true(reason.length() > 4, "原因附上涉及的学生，不是空泛结论")


func test_failure_reason_reports_exam_failure_with_numbers() -> void:
	var core := _core()
	core._exam._means[8] = 300.0
	core._exam._passed[8] = false
	var reason := core._failure_reason()
	assert_true(reason.contains("首次考核不达标"), "考核不达标时给出对应判据")
	assert_true(reason.contains("300"), "原因给出实际均分")
	assert_true(reason.contains("380"), "原因给出目标均分")


func test_no_failure_reason_when_no_trigger() -> void:
	var core := _core()
	assert_eq(core._failure_reason(), "", "没触发任何判据时没有辞退原因")


func test_summon_is_immediately_sendable() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	assert_true(tc.summon(core, 2), "召唤即到（2026-10-16 裁定）")
	assert_true(core._is_in_office(2), "学生立刻在办公室")
	assert_true(tc.send_back(core), "送回教室即时完成")
	assert_eq(tc.current_command(), "", "送回教室不占用命令、不消耗时间")
	assert_eq(tc.called_index(), -1, "学生立刻离开办公室")
	assert_false(core._is_in_office(2), "送回后立刻回到教室")
