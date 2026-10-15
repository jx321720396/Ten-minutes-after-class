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
		assert_true(grade >= 150.0 and grade <= 450.0, "开局成绩 150–450（D01）")
		total += grade
	assert_almost_eq(total / float(core.node_count()), 300.0, 60.0, "开局平均成绩落在 150–450 的中段（D01）")


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


func test_breakdown_enters_and_recovers() -> void:
	var core := _core()
	core._stress[0] = 95.0
	core._check_breakdown()
	assert_true(core.is_broken(0), "压力 >90 → 崩溃（D01 / D06）")
	core._stress[0] = 65.0
	core._check_breakdown()
	assert_false(core.is_broken(0), "压力 <70 → 恢复（D01 / D06）")


func test_teacher_summon_and_office_chat_timings() -> void:
	var core := _core()
	var tc := core.teacher_commands()
	assert_true(tc.summon(core, 3), "可以召唤一名学生（D03）")
	assert_eq(tc.remaining_seconds(), 10, "召唤 10 秒到达（D03）")
	assert_false(tc.summon(core, 5), "办公室同时只能召唤一名学生（D03）")
	for _t in range(10):
		tc.tick(core)
	assert_eq(tc.current_command(), "", "10 秒后到达")
	assert_true(tc.office_chat(core, "scold"), "到达后可以开始办公室聊天")
	assert_eq(tc.remaining_seconds(), 20, "办公室聊天统一 20 秒（D03）")
	var before := core.stress(3)
	for _t in range(20):
		tc.tick(core)
	assert_almost_eq(core.stress(3), minf(before + 20.0, 100.0), 0.0001, "训斥 +20 压力（D01）")


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
	assert_true(tc.summon(core, 2))
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
