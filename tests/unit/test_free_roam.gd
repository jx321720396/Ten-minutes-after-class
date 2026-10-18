extends GutTest
## 自由状态的定向走动与「先加入好感最高者」（主文档 §5.1.1 / §9.1.5，2026-10-19 用户裁定）。

const SEED := 20261019
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


## 把某人固定成自由状态并设定动力。
func _make_free(core: SimCore, i: int, vitality: float) -> void:
	core._phase_state[i] = "free"
	core._vitality[i] = vitality


## 找一对前后左右相邻的座位，把 1 号与 2 号放上去（邻座回落分支用）。
func _seat_orthogonal_pair(core: SimCore) -> Array:
	var seats: Array = core._seat_pos.keys()
	for a in seats:
		for b in seats:
			if a == b:
				continue
			core._seat_of[1] = a
			core._seat_of[2] = b
			if core._seat_relation_between(1, 2) == "orthogonal":
				return [a, b]
	return []


func test_free_state_enters_study_or_play_when_crossing() -> void:
	var core := _core()
	core._day = 2
	core._phase = "break"
	core._begin_phase_state()
	_make_free(core, 0, 61.0)
	_make_free(core, 1, 29.0)
	_make_free(core, 2, 45.0)
	FreeRoam.refresh_states(core)
	assert_eq(str(core._phase_state[0]), "study", "自由状态动力 >60 → 进入学习并锁定")
	assert_eq(str(core._phase_state[1]), "play", "自由状态动力 <30 → 进入游戏并锁定")
	assert_eq(str(core._phase_state[2]), "free", "30–60 仍为自由状态")


func test_locked_state_does_not_leave_when_vitality_returns() -> void:
	var core := _core()
	core._day = 2
	core._phase = "break"
	core._begin_phase_state()
	core._phase_state[0] = "study"
	core._vitality[0] = 25.0
	core._phase_state[1] = "play"
	core._vitality[1] = 70.0
	FreeRoam.refresh_states(core)
	assert_eq(str(core._phase_state[0]), "study", "进入学习后动力跌回范围也不退出（锁定）")
	assert_eq(str(core._phase_state[1]), "play", "进入游戏后动力升回范围也不退出（锁定）")


func test_try_join_best_joins_shared_music() -> void:
	var core := _core()
	core._day = 2
	core._phase = "break"
	core._phase_index = 0
	core._begin_phase_state()
	for i in range(NODES):
		_make_free(core, i, 45.0)
	assert_true(core._start_leisure(0, "listen_music"), "0 号应能开始听歌")
	# 1 号最在意 0 号；0 号也接纳 1 号（好感 − 敌对 ≥ 10）。
	for j in range(NODES):
		core._a[1 * NODES + j] = 40.0
		core._h[1 * NODES + j] = 0.0
		core._a[0 * NODES + j] = 60.0
		core._h[0 * NODES + j] = 0.0
	core._a[1 * NODES + 0] = 95.0
	assert_true(FreeRoam.try_join_best(core, 1), "1 号应加入 0 号的听歌")
	assert_eq(str(core._busy_act[1]), "listen_music", "加入者做同款娱乐")
	assert_eq(int(core._busy_until[1]), int(core._busy_until[0]), "与发起者同步结束")
	assert_false(FreeRoam.try_join_best(core, 1), "同一课间只尝试一次")


func test_try_join_best_skips_idle_target() -> void:
	var core := _core()
	core._day = 2
	core._phase = "break"
	core._phase_index = 0
	core._begin_phase_state()
	for i in range(NODES):
		_make_free(core, i, 45.0)
		core._current_act[i] = null
		core._busy_until[i] = 0
	assert_false(FreeRoam.try_join_best(core, 1), "好感最高者与邻座都没在做什么：不追、也不消耗本段机会")


func test_shared_book_does_not_need_own_book() -> void:
	var core := _core()
	core._day = 2
	core._phase = "break"
	core._phase_index = 0
	core._begin_phase_state()
	for i in range(NODES):
		_make_free(core, i, 45.0)
	core._book[0] = 1
	core._book[1] = 0
	for j in range(NODES):
		core._a[1 * NODES + j] = 40.0
		core._h[1 * NODES + j] = 0.0
		core._a[0 * NODES + j] = 60.0
		core._h[0 * NODES + j] = 0.0
	core._a[1 * NODES + 0] = 95.0
	assert_true(core._start_leisure(0, "read_book"), "0 号有书应能看课外书")
	assert_true(FreeRoam.try_join_best(core, 1), "无书的 1 号也能加入共享看书（加入者免物品）")
	assert_eq(str(core._busy_act[1]), "read_book", "加入者做同款娱乐")


## 回归（2026-10-19 运行时崩）：_neighbor_doing 曾把好感访问器误写成仿私有的名字，
## 只要好感最高者空闲、而正交邻座正在娱乐，整个课间就抛错中断。
func test_neighbor_fallback_joins_orthogonal_classmate() -> void:
	var core := _core()
	core._day = 2
	core._phase = "break"
	core._phase_index = 0
	core._begin_phase_state()
	for i in range(NODES):
		_make_free(core, i, 45.0)
		core._current_act[i] = null
		core._busy_until[i] = 0
	var seats := _seat_orthogonal_pair(core)
	assert_eq(seats.size(), 2, "需要一对正交座位")
	if seats.is_empty():
		return
	core._neighbor_idx[1] = [2]
	core._neighbor_idx[2] = [1]
	for j in range(NODES):
		core._a[1 * NODES + j] = 0.0
		core._h[1 * NODES + j] = 0.0
		core._h[2 * NODES + j] = 0.0
	core._a[1 * NODES + 0] = 50.0  # 1 号最在意 0 号；0 号空闲 → 走邻座回落
	core._a[2 * NODES + 1] = 50.0  # 邻座 2 号接纳 1 号
	assert_true(core._start_leisure(2, "listen_music"), "2 号应能开始听歌")
	assert_true(FreeRoam.try_join_best(core, 1), "好感最高者空闲、邻座在听歌：应加入邻座")
	assert_eq(str(core._busy_act[1]), "listen_music", "1 号加入同款娱乐")
