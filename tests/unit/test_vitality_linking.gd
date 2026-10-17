extends GutTest
## D01 §4.1「压力↔动力一般联动」回归（2026-10-16）。
## 一般事件压力 ±1 → 动力同向 ±1；标注「单独」变化的效果不联动（跨天、游戏状态减压、学习 −5 动力）；
## 反向不成立：单独改动力不影响压力。

const SEED := 20261016
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


func _set_axes(core: SimCore, i: int, stress: float, vitality: float) -> void:
	core._stress[i] = stress
	core._vitality[i] = vitality


## 把 a、b 放到一对正交邻座（前后左右，不含对角），让 _seat_relation_between 返回 "orthogonal"。
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


func test_add_stress_links_vitality_one_to_one() -> void:
	var core := _core()
	_set_axes(core, 0, 40.0, 50.0)
	core.add_stress(0, 7.0)
	assert_almost_eq(core.stress(0), 47.0, 0.0001, "压力 +7")
	assert_almost_eq(core.vitality(0), 57.0, 0.0001, "动力同向 +7（一般联动）")


func test_add_stress_decrease_links_too() -> void:
	var core := _core()
	_set_axes(core, 0, 60.0, 60.0)
	core.add_stress(0, -12.0)
	assert_almost_eq(core.stress(0), 48.0, 0.0001, "压力 −12")
	assert_almost_eq(core.vitality(0), 48.0, 0.0001, "动力同向 −12")


func test_add_stress_unlinked_keeps_vitality() -> void:
	var core := _core()
	_set_axes(core, 0, 60.0, 60.0)
	core.add_stress(0, -20.0, false)
	assert_almost_eq(core.stress(0), 40.0, 0.0001, "压力 −20")
	assert_almost_eq(core.vitality(0), 60.0, 0.0001, "标注「单独」时不联动动力")


func test_add_vitality_does_not_touch_stress() -> void:
	var core := _core()
	_set_axes(core, 0, 60.0, 60.0)
	core.add_vitality(0, -15.0)
	assert_almost_eq(core.vitality(0), 45.0, 0.0001, "动力 −15")
	assert_almost_eq(core.stress(0), 60.0, 0.0001, "反向不成立：单独改动力不影响压力")


func test_both_axes_clamp_at_zero_and_hundred() -> void:
	var core := _core()
	_set_axes(core, 0, 3.0, 3.0)
	core.add_stress(0, -50.0)
	assert_almost_eq(core.stress(0), 0.0, 0.0001, "压力下限 0")
	assert_almost_eq(core.vitality(0), 0.0, 0.0001, "动力下限 0")
	_set_axes(core, 1, 95.0, 95.0)
	core.add_stress(1, 50.0)
	assert_almost_eq(core.stress(1), 100.0, 0.0001, "压力上限 100")
	assert_almost_eq(core.vitality(1), 100.0, 0.0001, "动力上限 100")


func test_neighbor_drip_links_vitality() -> void:
	var core := _core()
	core._begin_phase_state()
	_set_axes(core, 0, 40.0, 40.0)
	_seat_orthogonal(core, 0, 1)  # 涓流只看固定座位前后左右：0、1 必须是正交邻座
	# 直接把 1 号设为 0 号的正交邻座并让他处于学习状态（不依赖随机座位）。
	core._neighbor_idx[0] = [1]
	core._current_act[1] = "study"
	core._phase_state[1] = "free"
	core._sleeping[1] = false
	core._broken[1] = false
	core._broken[0] = false
	core._current_act[0] = null
	core._settle_neighbor_drip()
	assert_almost_eq(core.stress(0), 45.0, 0.0001, "邻座学习：压力 +5")
	assert_almost_eq(core.vitality(0), 45.0, 0.0001, "邻座学习加压联动动力 +5")


func test_harm_links_target_vitality() -> void:
	var core := _core()
	_set_axes(core, 1, 40.0, 40.0)
	core._add_hostility(1, 0, 0.0)
	core.add_stress(1, 5.0)  # 恶语攻击的压力增量走同一入口
	assert_almost_eq(core.vitality(1), 45.0, 0.0001, "伤害加压同样联动动力")


func test_play_state_relief_is_unlinked() -> void:
	var core := _core()
	core._begin_phase_state()
	_set_axes(core, 0, 50.0, 50.0)
	core._phase = "break"
	core._phase_state[0] = "play"
	core._current_act[0] = "play_phone"
	core._busy_act[0] = "play_phone"
	core._busy_phase[0] = 0
	core._busy_until[0] = 10 ** 9
	for _k in range(40):
		core._settle_units()
	assert_almost_eq(core.stress(0), 45.0, 0.0001, "游戏状态每 40 秒 −5 压力")
	assert_almost_eq(core.vitality(0), 50.0, 0.0001, "游戏状态「不减少动力」，且不联动减压")


func test_study_cost_only_changes_vitality() -> void:
	var core := _core()
	core._begin_phase_state()
	_set_axes(core, 0, 30.0, 80.0)
	core._phase = "break"
	core._phase_state[0] = "study"
	core._current_act[0] = "study"
	core._busy_act[0] = "study"
	core._busy_phase[0] = 0
	core._busy_until[0] = 10 ** 9
	for _k in range(20):
		core._settle_units()
	assert_almost_eq(core.vitality(0), 75.0, 0.0001, "学习每 20 秒 −5 动力")
	assert_almost_eq(core.stress(0), 30.0, 0.0001, "学习不直接加压，故不联动")


func test_day_carry_keeps_both_cuts_separate() -> void:
	var core := _core()
	for i in range(core.node_count()):
		core._stress[i] = 60.0
		core._vitality[i] = 60.0
	core._day = 6
	core._settle_day()
	assert_almost_eq(core.stress(0), 40.0, 0.0001, "跨天压力单独 −20")
	assert_almost_eq(core.vitality(0), 60.0, 0.0001, "跨天动力不再扣减，也不随压力的 −20 联动（2026-10-17）")
