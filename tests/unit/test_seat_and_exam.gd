extends GutTest
## 《老师版规则合并稿》D04（座位基础关系结算）与 D05（第八天考试）回归（2026-10-16）。

const SEED := 20261016
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


## 只让 0／1 号参与结算：其余学生置为崩溃（D04 §8.1 明确崩溃不参与）。
func _only_pair_participates(core: SimCore) -> void:
	core._begin_phase_state()
	for i in range(2, core.node_count()):
		core._phase_state[i] = "broken"


## 在座位表里找一对满足指定关系的座位（orthogonal / diagonal / far）。
func _find_seats(core: SimCore, want: String) -> Array:
	var seats: Array = core._seat_pos.keys()
	for a in seats:
		for b in seats:
			if a == b:
				continue
			core._seat_of[0] = a
			core._seat_of[1] = b
			if core._seat_relation_between(0, 1) == want:
				return [a, b]
	return []


func _place_pair(core: SimCore, want: String) -> bool:
	var seats := _find_seats(core, want)
	if seats.is_empty():
		return false
	core._seat_of[0] = seats[0]
	core._seat_of[1] = seats[1]
	# 0 号学习、1 号娱乐（听歌）—— 两人都「在自己座位 + 学习／娱乐」，符合 D04 参与资格。
	core._phase_state[0] = "free"
	core._phase_state[1] = "free"
	core._current_act[0] = "study"
	core._current_act[1] = "listen_music"
	return true


# ------------------------------------------------------------------ D04
func test_orthogonal_neighbours_gain_affinity_on_both_sides() -> void:
	var core := _core()
	_only_pair_participates(core)
	assert_true(_place_pair(core, "orthogonal"), "座位表里应存在前后左右相邻的一对")
	var a01 := core.affinity(0, 1)
	var a10 := core.affinity(1, 0)
	core._settle_seat_relations()
	assert_almost_eq(core.affinity(0, 1), a01 + 2.0, 0.0001, "正交邻座：0 对 1 好感 +2")
	assert_almost_eq(core.affinity(1, 0), a10 + 2.0, 0.0001, "正交邻座：双方各自 +2")


func test_diagonal_neighbours_gain_no_affinity() -> void:
	var core := _core()
	_only_pair_participates(core)
	assert_true(_place_pair(core, "diagonal"), "座位表里应存在对角相邻的一对")
	var a01 := core.affinity(0, 1)
	core._settle_seat_relations()
	assert_almost_eq(core.affinity(0, 1), a01, 0.0001, "对角邻座不因座位关系加好感")


func test_far_pairs_lose_affinity() -> void:
	var core := _core()
	_only_pair_participates(core)
	assert_true(_place_pair(core, "far"), "座位表里应存在一圈以外的一对")
	var a01 := core.affinity(0, 1)
	core._settle_seat_relations()
	assert_almost_eq(core.affinity(0, 1), a01 - 1.0, 0.0001, "周围一圈以外：好感 −1")


func test_study_hostility_towards_playing_neighbour_is_one_way() -> void:
	var core := _core()
	_only_pair_participates(core)
	assert_true(_place_pair(core, "orthogonal"), "座位表里应存在前后左右相邻的一对")
	var h01 := core.hostility(0, 1)
	var h10 := core.hostility(1, 0)
	core._settle_seat_relations()
	assert_almost_eq(core.hostility(0, 1), h01 + 5.0, 0.0001, "学习者对娱乐邻座敌对 +5")
	assert_almost_eq(core.hostility(1, 0), h10, 0.0001, "不自动反向增加敌对")


func test_sleeping_student_counts_as_study_for_seat_relations() -> void:
	var core := _core()
	core._begin_phase_state()
	core._sleeping[0] = true
	assert_eq(core._seat_role(0), "study", "睡觉仅在座位关系中视同学习（D04 §8.1）")
	assert_eq(core._unit_kind(0), "", "睡觉不获得学习收益（unit_kind 仍为空）")


func test_broken_student_does_not_participate() -> void:
	var core := _core()
	_only_pair_participates(core)
	assert_true(_place_pair(core, "orthogonal"), "座位表里应存在前后左右相邻的一对")
	core._broken[0] = true
	core._phase_state[0] = "broken"
	var a01 := core.affinity(0, 1)
	var a10 := core.affinity(1, 0)
	core._settle_seat_relations()
	assert_almost_eq(core.affinity(0, 1), a01, 0.0001, "崩溃者不作接收者")
	assert_almost_eq(core.affinity(1, 0), a10, 0.0001, "崩溃者也不作来源")


func test_free_student_without_activity_does_not_participate() -> void:
	var core := _core()
	_only_pair_participates(core)
	assert_true(_place_pair(core, "orthogonal"), "座位表里应存在前后左右相邻的一对")
	core._current_act[0] = null
	var a01 := core.affinity(0, 1)
	core._settle_seat_relations()
	assert_almost_eq(core.affinity(0, 1), a01, 0.0001, "没在学习/娱乐/睡觉的学生不参加座位结算")


# ------------------------------------------------------------------ D05
func test_first_exam_is_on_the_eighth_day() -> void:
	var core := _core()
	assert_true(core._exam.is_exam_day(8), "第八天进行第一次考试（D05）")
	assert_false(core._exam.is_exam_day(7), "第七天不是考试日")
	assert_true(core._exam.is_exam_eve(7), "第七天是考前日（D05）")


func test_target_mean_by_exam_order() -> void:
	var core := _core()
	assert_almost_eq(core._exam.target_mean(), 450.0, 0.0001, "第 1 次目标 450（2026-10-18）")
	assert_almost_eq(core._exam.target_mean_for(14), 480.0, 0.0001, "第 2 次目标 480")
	assert_almost_eq(core._exam.target_mean_for(21), 500.0, 0.0001, "第 3 次目标 500")
	assert_almost_eq(core._exam.target_mean_for(28), 520.0, 0.0001, "第 4 次目标 520")
	assert_almost_eq(core._exam.target_mean_for(30), 520.0, 0.0001, "期末考沿用最后一次目标")


func test_exam_eve_raises_class_stress_by_20() -> void:
	var normal := _core()
	var eve := _core()
	# 起始压力设高一些，避免跨天 −20 后被 0 下限吃掉（clamp100）。
	for i in range(normal.node_count()):
		normal._stress[i] = 60.0
		eve._stress[i] = 60.0
	normal._day = 6
	normal._settle_day()
	eve._day = 7
	eve._settle_day()
	# 两天都做「跨天压力 −20」；考前日再 +20 → 相对普通日高 20 点。
	assert_almost_eq(eve.stress(0) - normal.stress(0), 20.0, 0.0001, "考试前一天全班压力 +20（D05）")


func test_exam_day_cuts_class_stress_by_30() -> void:
	var normal := _core()
	var exam_day := _core()
	for i in range(normal.node_count()):
		normal._stress[i] = 60.0
		exam_day._stress[i] = 60.0
	normal._day = 6
	normal._settle_day()
	exam_day._day = 8
	exam_day._settle_day()
	# 考试日：跨天 −20 再 −30 → 相对普通日低 30 点。
	assert_almost_eq(exam_day.stress(0) - normal.stress(0), -30.0, 0.0001, "考试结束全班压力 −30（D05）")


func test_exam_day_skips_student_decisions() -> void:
	var core := _core()
	core._day = 8
	assert_true(core._is_exam_only_day(), "第八天属于「只有考试」的一天")
	core._begin_phase_state()
	for i in range(core.node_count()):
		core._current_act[i] = null
	core._decide_and_act()
	for i in range(core.node_count()):
		assert_eq(core._current_act[i], null, "考试当天学生不做普通行为决策（D05）")
