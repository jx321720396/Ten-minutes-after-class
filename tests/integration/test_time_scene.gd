extends GutTest
## 时间组件 Task 3 集成测试：「时钟 → 时间 HUD」的接线与显示口径。
##
## 依据：docs/superpowers/plans/2026-10-07-time-component.md §3、§4、Task 3。
## 这里用最小场景（SimCore + SimulationClock + TimeHUD）验证接线：GUT 运行在 --script
## 模式下 autoload 不可用，而教室场景的演示建局依赖 /root/GameState；教室内的接线由
## MCP `run_project` 的调试输出与截图另行验证。

const SEED := 20261007
const NPC_COUNT := 16


func _make_stack() -> Array:
	var tables := ConfigLoader.new().load_all()
	var core := SimCore.from_npc(SEED, NPC_COUNT, tables)
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(core, tables), "时钟应绑定成功")
	clock.set_process(false)
	var hud: TimeHUD = load("res://scenes/ui/time_hud.tscn").instantiate()
	add_child_autofree(hud)
	hud.bind_clock(clock)
	return [core, clock, hud]


## 跑若干个 pump 直到跨过当前相位（每个 pump 受每帧预算限制）。
func _pump_until_phase_changes(clock: SimulationClock, core: SimCore) -> void:
	var phase_id := str(core.time_snapshot()["phase_id"])
	for _i in range(300):
		clock.pump(1.0)
		if str(core.time_snapshot()["phase_id"]) != phase_id:
			return


func test_hud_shows_day_and_phase_display_name() -> void:
	var parts := _make_stack()
	var hud: TimeHUD = parts[2]
	assert_eq(hud.title_line(), "第 1 / 30 天 · 上午课间", "第 1 行 = 天数 + time_presentation 的 display_name")
	assert_eq(hud.detail_line(), "课间剩余 01:40", "第 2 行 = 课间真实倒计时（100 秒 = 01:40）")
	assert_almost_eq(hud.progress_percent(), 0.0, 0.0001)
	assert_false(hud.controls_locked(), "课间允许玩家操作")


func test_countdown_rounds_up() -> void:
	var parts := _make_stack()
	var clock: SimulationClock = parts[1]
	var hud: TimeHUD = parts[2]
	clock.pump(1.1)
	# 剩余 98.9 秒：向上取整 = 99 秒（01:39），若向下取整会显示 01:38
	assert_eq(hud.detail_line(), "课间剩余 01:39", "倒计时向上取整")
	assert_true(hud.progress_percent() > 0.0 and hud.progress_percent() < 100.0, "进度条随之推进")


func test_class_phase_locks_controls_and_relabels() -> void:
	var parts := _make_stack()
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var hud: TimeHUD = parts[2]
	var toast_before := hud.toast_count()

	_pump_until_phase_changes(clock, core)

	assert_eq(str(core.time_snapshot()["phase_id"]), "morning_class", "课间跑满后进入上午上课")
	assert_eq(hud.title_line(), "第 1 / 30 天 · 上午课堂", "阶段名随相位更新")
	assert_eq(hud.detail_line(), "发酵中 · 本阶段约剩余 00:15", "上课显示发酵中 + 整段 15 秒剩余")
	assert_true(hud.controls_locked(), "上课禁止玩家主动操作")
	assert_eq(hud.toast_count(), toast_before + 1, "阶段提示在边界只弹一次")


func test_report_state_shows_ended_day_and_recovers() -> void:
	var parts := _make_stack()
	var clock: SimulationClock = parts[1]
	var hud: TimeHUD = parts[2]
	for _i in range(2000):
		clock.pump(1.0)
		if str(clock.snapshot()["mode"]) != SimulationClock.MODE_RUNNING:
			break
	assert_eq(str(clock.snapshot()["mode"]), SimulationClock.MODE_REPORT, "第 1 天结束进入 report")
	assert_eq(hud.detail_line(), "第 1 天结束", "日末显示结束的那一天")
	assert_true(hud.controls_locked(), "简报停留期间不允许操作")
	assert_eq(clock.snapshot()["remaining_seconds"], 0.0, "日末剩余为 0（不出现负数）")

	assert_true(clock.continue_after_report(), "继续请求应成功")
	assert_eq(hud.title_line(), "第 2 / 30 天 · 上午课间", "进入第 2 天")
	assert_false(hud.controls_locked(), "恢复课间后允许操作")


func test_rebinding_same_clock_does_not_duplicate_connections() -> void:
	var parts := _make_stack()
	var clock: SimulationClock = parts[1]
	var hud: TimeHUD = parts[2]
	assert_eq(hud.connection_count(), 4, "四个时钟信号各连一次")
	var toast_before := hud.toast_count()
	hud.bind_clock(clock)
	hud.bind_clock(clock)
	assert_eq(hud.connection_count(), 4, "重复绑定不增加连接")

	_pump_until_phase_changes(clock, parts[0])
	assert_eq(hud.toast_count(), toast_before + 1, "相位提示仍只弹一次（没有重复连接）")
