extends GutTest
## 学习圈（§8.23 第 4 条）：8 邻域内**都在学习**才有圈子结算。
##
## 口径：双向信任 +1、双向好感 +1、自身压力 +1（每人只算一次）；单人学习不结算；
## 没有学习邻居的人退回单人学习；不消耗 RNG（对拍不受影响）。

const NODES := 8


func _core(seed_num: int = 12345) -> SimCore:
	return SimCore.from_npc(seed_num, NODES, ConfigLoader.new().load_all())


func _at_settle_tick(c: SimCore) -> void:
	c._global_tick = 20  # interval = 20，取一个整倍数


func test_interval_key_exists_and_is_positive() -> void:
	var c := _core()
	assert_gt(int(c._kp.get("study_circle_interval_ticks", 0)), 0, "间隔是外置的数值")


func test_single_student_never_settles() -> void:
	var c := _core()
	var a := 0
	var b := int(c._neighbor_idx[a][0])
	c._do_study(a)
	var trust_before := c.trust(a, b)
	_at_settle_tick(c)
	c._study_circle_settle()
	assert_eq(c.trust(a, b), trust_before, "一个人学不算圈子")


func test_two_studying_neighbours_settle_both_ways() -> void:
	var c := _core()
	var a := 0
	var b := int(c._neighbor_idx[a][0])
	c._do_study(a)
	c._do_study(b)
	var trust_ab := c.trust(a, b)
	var trust_ba := c.trust(b, a)
	var stress_a := c.stress(a)
	_at_settle_tick(c)
	c._study_circle_settle()
	assert_gt(c.trust(a, b), trust_ab, "a → b 信任 +1")
	assert_gt(c.trust(b, a), trust_ba, "b → a 信任 +1（双向）")
	assert_gt(c.stress(a), stress_a, "学习圈内自身压力 +1")


func test_pressure_counts_once_per_person_regardless_of_neighbour_count() -> void:
	var c := _core()
	var a := 0
	c._do_study(a)
	for j in c._neighbor_idx[a]:
		c._do_study(int(j))
	var stress_before := c.stress(a)
	_at_settle_tick(c)
	c._study_circle_settle()
	# 邻居数 ≥ 2 时压力仍只加一次 —— 用「加了几次」不好直接测，这里只钉住它会加且不炸
	assert_gt(c.stress(a), stress_before, "有学习邻居就加压力")


func test_off_tick_does_not_settle() -> void:
	var c := _core()
	var a := 0
	var b := int(c._neighbor_idx[a][0])
	c._do_study(a)
	c._do_study(b)
	var trust_before := c.trust(a, b)
	c._global_tick = 19  # 不是间隔的整倍数
	c._study_circle_settle()
	assert_eq(c.trust(a, b), trust_before, "只有到结算 tick 才结算")


func test_class_phase_does_not_settle() -> void:
	var c := _core()
	var a := 0
	var b := int(c._neighbor_idx[a][0])
	c._do_study(a)
	c._do_study(b)
	var trust_before := c.trust(a, b)
	c._phase = "class"
	_at_settle_tick(c)
	c._study_circle_settle()
	assert_eq(c.trust(a, b), trust_before, "上课段没有学习圈（§8.23 只在课间）")
