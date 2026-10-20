extends GutTest
## 找茬：敌对最高的人，不能拒绝，结束时双方敌对各 +5。


func _core() -> SimCore:
	return SimCore.new(7, 4, ConfigLoader.new().load_all())


func test_nitpick_picks_highest_hostility_and_adds_five() -> void:
	var core := _core()
	core._begin_phase_state()
	var n := core.node_count()
	for i in range(n):
		for j in range(n):
			if i != j:
				core._h[i * n + j] = 0.0
	core._h[0 * n + 1] = 5.0
	core._h[0 * n + 2] = 30.0
	core._phase_state[2] = "play"
	core._sleeping[3] = true
	core._h[0 * n + 3] = 80.0
	assert_eq(core._find_nitpick_target(0), 2, "跳过睡觉的更高敌对，游戏锁定仍可拉")
	var before_02 := core.hostility(0, 2)
	var before_20 := core.hostility(2, 0)
	core._start_nitpick(0, 2)
	assert_eq(core.activity_of(0), "nitpick", "发起者进入找茬")
	assert_eq(core.activity_of(2), "nitpick", "对方无法拒绝")
	assert_true(core._join_blocked(2), "找茬中不能被加入")
	core._busy_until[0] = core.global_tick()
	core._busy_until[2] = core.global_tick()
	core._settle_finished_actions()
	assert_almost_eq(core.hostility(0, 2), before_02 + 5.0, 0.001, "发起者对对方敌对 +5")
	assert_almost_eq(core.hostility(2, 0), before_20 + 5.0, 0.001, "对方对发起者敌对 +5")
