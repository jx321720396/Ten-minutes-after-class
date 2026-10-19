extends GutTest
## 声量可选模式（2026-10-19）：档位边界、倍率、鼓励目标池、存档。
## 只测内核与数据表；麦克风/按住/设置开关在表现层，另测。

const SEED := 20261019
const NODES := 16


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, ConfigLoader.new().load_all())


func _isolate(core: SimCore, keep: int = 0) -> void:
	core._begin_phase_state()
	for i in range(core.node_count()):
		core._phase_state[i] = "free" if i == keep else "broken"


## 选一个不触发弹簧 / 听劝的节点，便于精确断言训斥的压力与动力。
func _plain_student(core: SimCore) -> int:
	for i in range(core.node_count()):
		if not core._passives.has(i, "spring") and not core._passives.has(i, "receptive"):
			return i
	return 0


func _prepare_entertainers(core: SimCore, count: int) -> void:
	var n := core.node_count()
	core._pos_x[0] = 0.0
	core._pos_z[0] = 0.0
	for j in range(1, count + 1):
		core._phase_state[j] = "free"
		core._busy_act[j] = "listen_music"
		core._busy_until[j] = core._global_tick + 100
		core._pos_x[j] = float(j)
		core._pos_z[j] = 0.0
	# 其余学生保持隔离，避免成为候选。
	for j in range(count + 1, n):
		core._phase_state[j] = "broken"


func test_voice_rules_loads_csv_and_boundaries() -> void:
	var rules := VoiceRules.new()
	rules.configure_table(ConfigLoader.new().get_table("rules/voice"))
	assert_almost_eq(rules.mult_for(2), 1.0, 0.0001, "平常档 = 1.0（现行数值）")
	assert_almost_eq(rules.mult_for(1), 0.6, 0.0001)
	assert_almost_eq(rules.mult_for(3), 1.4, 0.0001)
	assert_almost_eq(rules.mult_for(4), 1.7, 0.0001)
	assert_eq(rules.tier_for_intensity(24.9), 1, "24.9 → 轻声")
	assert_eq(rules.tier_for_intensity(25.0), 2, "25 → 平常")
	assert_eq(rules.tier_for_intensity(49.9), 2)
	assert_eq(rules.tier_for_intensity(50.0), 3, "50 → 提高")
	assert_eq(rules.tier_for_intensity(74.9), 3)
	assert_eq(rules.tier_for_intensity(75.0), 4, "75 → 吼")
	assert_eq(rules.tier_for_intensity(100.0), 4)
	assert_eq(rules.office_chat_seconds(), 10, "声量模式谈话 10 秒（常模仍 20 秒）")


func test_voice_tier_hysteresis_stabilizes_boundaries() -> void:
	var rules := VoiceRules.new()
	rules.configure_table(ConfigLoader.new().get_table("rules/voice"))
	assert_eq(rules.tier_with_hysteresis(51.0, 2), 2, "回差内不升档")
	assert_eq(rules.tier_with_hysteresis(55.0, 2), 3, "超过回差才升档")
	assert_eq(rules.tier_with_hysteresis(48.0, 3), 3, "回差内不降档")
	assert_eq(rules.tier_with_hysteresis(44.0, 3), 2, "低于回差才降档")


func test_voice_rules_hold() -> void:
	var rules := VoiceRules.new()
	rules.configure_table(ConfigLoader.new().get_table("rules/voice"))
	assert_eq(rules.tier_for_hold(5.0), 4, "按满 5 秒 → 吼")
	assert_eq(rules.tier_for_hold(2.5), 2, "约 2.5 秒 → 平常")
	var intensity := rules.intensity_for_rms(1.0, 0.1, 1.0, 2.2)
	assert_almost_eq(intensity, 41.463, 0.01, "平常音量约 41")
	assert_eq(rules.tier_for_intensity(intensity), 2)


func test_scold_tier_scales_stress_and_linked_vitality() -> void:
	var core := _core()
	var idx := _plain_student(core)
	_isolate(core, idx)
	core._stress[idx] = 10.0
	core._vitality[idx] = 10.0
	var commands := core.teacher_commands()
	assert_true(commands.summon(core, idx))
	assert_true(commands.office_chat(core, "scold"))
	assert_true(commands.set_office_voice(4))
	for _t in range(20):
		commands.tick(core)
	assert_almost_eq(core.stress(idx), 61.0, 0.001, "吼训斥 +51 压力")
	assert_almost_eq(core.vitality(idx), 61.0, 0.001, "压力联动 +51 动力")


func test_comfort_tier_scales_stress_and_linked_vitality() -> void:
	var core := _core()
	_isolate(core)
	core._stress[0] = 50.0
	core._vitality[0] = 50.0
	var commands := core.teacher_commands()
	assert_true(commands.summon(core, 0))
	assert_true(commands.office_chat(core, "comfort"))
	assert_true(commands.set_office_voice(4))
	for _t in range(20):
		commands.tick(core)
	assert_almost_eq(core.stress(0), 16.0, 0.001, "吼安抚 −34 压力")
	assert_almost_eq(core.vitality(0), 16.0, 0.001, "减压联动 −34 动力")


func test_praise_scales_vitality_with_voice_tier() -> void:
	var core := _core()
	_isolate(core)
	core._vitality[0] = 50.0
	var commands := core.teacher_commands()
	assert_true(commands.summon(core, 0))
	assert_true(commands.office_chat(core, "praise", true), "表扬走声量模式谈话")
	assert_true(commands.set_office_voice(4), "表扬接入声量")
	for _t in range(10):
		commands.tick(core)
	assert_almost_eq(core.vitality(0), 76.0, 0.001, "吼表扬 +26 动力（15 × 1.7 取整）")


func test_encourage_tier_selects_pool_and_pick() -> void:
	var core := _core()
	_isolate(core)
	_prepare_entertainers(core, 4)
	core._neighbor_idx[0] = [3]
	var n := core.node_count()
	core._a[0 * n + 1] = 10.0
	core._a[0 * n + 2] = 90.0
	core._a[0 * n + 3] = 50.0
	core._a[0 * n + 4] = 99.0
	var commands := core.teacher_commands()
	commands.reset_encourage(n)
	assert_true(commands.start_encourage(0, -1, 1))
	assert_eq(commands._pick_encourage_target(core, 0), 3, "轻声只看邻座")
	commands.reset_encourage(n)
	assert_true(commands.start_encourage(0, -1, 2))
	assert_eq(commands._pick_encourage_target(core, 0), 1, "平常取最近（现行）")
	commands.reset_encourage(n)
	assert_true(commands.start_encourage(0, -1, 3))
	assert_eq(commands._pick_encourage_target(core, 0), 2, "提高在最近 3 人中取好感最高")
	commands.reset_encourage(n)
	assert_true(commands.start_encourage(0, -1, 4))
	assert_eq(commands._pick_encourage_target(core, 0), 4, "吼在全班取好感最高")
	assert_eq(int(commands.encourage_snapshot(core, 0)["tier"]), 4, "档位随目标保存")


func test_voice_tier_survives_export_restore() -> void:
	var core := _core()
	_isolate(core)
	var commands := core.teacher_commands()
	assert_true(commands.summon(core, 0))
	assert_true(commands.office_chat(core, "scold"))
	assert_true(commands.set_office_voice(3))
	var data := commands.export_state()
	var restored := TeacherCommands.new()
	restored.configure({}, {})
	restored.restore_state(data)
	assert_eq(int(restored.snapshot()["chat_tier"]), 3, "谈话档位随存档保留")
	restored.reset_encourage(16)
	restored.start_encourage(0, -1, 4)
	var data2 := restored.export_state()
	var restored2 := TeacherCommands.new()
	restored2.configure({}, {})
	restored2.restore_state(data2)
	assert_eq(int(restored2.encourage_snapshot(core, 0)["tier"]), 4, "鼓励档位随目标保留")
