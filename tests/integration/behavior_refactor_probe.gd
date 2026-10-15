extends SceneTree
## 记录老师版内核（A/H + 压力/成绩）的完整状态、RNG 和事件顺序；不改模拟实现。
## --out=<路径> 指定输出；--core-script=<脚本路径> 可换源内核脚本（默认当前 sim_core）。
## 基线不提交为数值金样，只作跨次重构的对拍快照。

const FIELDS := [
	"_a",
	"_h",
	"_stress",
	"_grade",
	"_day",
	"_phase",
	"_tick_in_phase",
	"_phase_index",
	"_global_tick",
	"_phase_setup_done",
	"_current_act",
	"_sleeping",
	"_in_conversation",
	"_next_action",
	"_busy_until",
	"_busy_phase",
	"_busy_act",
	"_last_finished",
	"_pos_x",
	"_pos_z",
	"_knot_days",
	"_vol_log",
	"_day_events",
	"_settled",
	"_stats",
	"_volume",
	"_seat_of"
]


func _initialize() -> void:
	var out_path := "user://behavior_probe.json"
	var core_path := "res://scripts/core/sim_core.gd"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)
		elif arg.begins_with("--core-script="):
			core_path = arg.substr(14)
	var core_script: GDScript = load(core_path)
	var tables := ConfigLoader.new().load_all()
	var rows: Array = []
	for scenario in [
		"chat",
		"join_accept",
		"join_reject",
		"join_random",
		"roughhouse"
	]:
		var c: Variant = _new_core(core_script, 12345, tables)
		var events: Array = []
		c.event_sink = func(e: Dictionary): events.append(e)
		c._a[1] = 80.0
		c._h[1] = 0.0
		match scenario:
			"chat":
				c._do_chat(0, 1)
			"join_accept":
				c._do_chat_join(0, 1, 0.0)
			"join_reject":
				c._do_chat_join(0, 1, 1.0)
			"join_random":
				c._do_chat_join(0, 1)
			"roughhouse":
				c._do_roughhouse(0, 1)
		rows.append(_snapshot(c, events, scenario))
		# 同对子重复调用与完成/相位边界也需保持原样。
		c._do_chat(0, 1)
		c.advance_phase()
		c.advance_tick()
		rows.append(_snapshot(c, events, scenario + "_boundary"))
	for kind in ["chat", "roughhouse"]:
		var c: Variant = _new_core(core_script, 12345, tables)
		var events: Array = []
		c.event_sink = func(e: Dictionary): events.append(e)
		var result: Dictionary = c.player_action(kind, 0)
		var player_row := _snapshot(c, events, "player_" + kind)
		player_row["result"] = result
		rows.append(player_row)
	for seed_value in [12345, 42, 2024]:
		var c: Variant = _new_core(core_script, seed_value, tables)
		var events: Array = []
		c.event_sink = func(e: Dictionary): events.append(e)
		for day_index in range(30):
			events.clear()
			c.run_day()
			rows.append(_snapshot(c, events, "seed_%d_day_%d" % [seed_value, day_index + 1]))
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入基线：" + out_path)
		quit(1)
		return
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("BEHAVIOR_PROBE: %d 个分支/边界/日末快照已写入 %s" % [rows.size(), out_path])
	quit(0)


func _new_core(script: GDScript, seed_value: int, tables: Dictionary) -> Variant:
	# 2026-10-12：不再有难度档映射，人数直接给 16（角色池 = 一局人数）
	return script.new(seed_value, 16, tables)


func _snapshot(c: Variant, events: Array, label: String) -> Dictionary:
	var state := {}
	for field in FIELDS:
		state[field] = _digest(c.get(field))
	state["rng_state"] = _digest([c._rng._mt, c._rng._mti])
	state["events_in_order"] = _digest(events)
	return {"label": label, "state": state}


func _digest(value: Variant) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value))
	return hashing.finish().hex_encode()
