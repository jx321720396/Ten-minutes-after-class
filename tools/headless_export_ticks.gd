extends SceneTree
## 内核侧逐 tick 状态导出（对拍基建），字段逐一对齐 tools/export_ticks.py。
##
## 与 Python export_ticks 的 hook 方式等价：每次 tick 完成后采样一行快照。
## 采样点 = advance_tick() 返回后（= _tick() 之后），对应 Python「tick() 后 snapshot」。
##
## 运行：
##   godot --headless --path . --script res://tools/headless_export_ticks.gd -- 3 12345 16 > tools/out/gd.jsonl
## 参数：days seed npc（缺省 3 / 12345 / 16）。
## 输出：每 tick 一行 JSON（stdout），字段名与 export_ticks.py 完全一致，可直接逐行 diff。


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var days := 3
	var seed := 12345
	var npc := 16
	if args.size() >= 1:
		days = int(args[0])
	if args.size() >= 2:
		seed = int(args[1])
	if args.size() >= 3:
		npc = int(args[2])

	var tables := ConfigLoader.new().load_all()
	var core := SimCore.from_npc(seed, npc, tables)
	var n := core.node_count()

	for _d in range(days):
		for _t in range(480):
			core.advance_tick()
			print(JSON.stringify(_snapshot(core, n)))
	quit(0)


## 采样一行快照：字段与 export_ticks.py 的 snapshot() 一致。
func _snapshot(core: SimCore, n: int) -> Dictionary:
	var a: Array[float] = []
	var h: Array[float] = []
	var t: Array[float] = []
	for i in range(n):
		for j in range(n):
			a.append(core.affinity(i, j))
			h.append(core.hostility(i, j))
			t.append(core.trust(i, j))
	var o: Array[float] = []
	var s: Array[float] = []
	var g: Array[float] = []
	var sa: Array[float] = []
	for i in range(n):
		o.append(core.opacity(i))
		s.append(core.stress(i))
		g.append(core.grade(i))
		sa.append(core.study_acc(i))
	return {
		"tick": core.global_tick(),
		"day": core.day(),
		"phase": core.phase(),
		"phase_index": core.phase_index(),
		"tick_in_phase": core.tick_in_phase(),
		"A_mean": _mean(a),
		"H_mean": _mean(h),
		"T_mean": _mean(t),
		"O_mean": _mean(o),
		"stress_mean": _mean(s),
		"grade_mean": _mean(g),
		"A_hash": _digest(a),
		"H_hash": _digest(h),
		"T_hash": _digest(t),
		"grade_hash": _digest(g),
		"study_acc_hash": _digest(sa),
		"events": int(core._stats.get("events", 0)),
		"bursts": int(core._stats.get("bursts", 0)),
		"transmits": int(core._stats.get("transmission_ticks", 0)),
	}


## 均值，round 到 3 位（对齐 export_ticks.py 的 _mean：round(x,3)，half-even）。
func _mean(vals: Array[float]) -> float:
	if vals.is_empty():
		return 0.0
	var total := 0.0
	for v in vals:
		total += v
	return _py_round(total / float(vals.size()), 3)


## 0.1 精度序列指纹（sha256 前 16 位），对齐 export_ticks.py 的 _digest（"%.1f" half-even）。
func _digest(vals: Array[float]) -> String:
	var parts: Array[String] = []
	for v in vals:
		parts.append("%.1f" % _py_round(v, 1))
	var text := ",".join(parts)
	return text.sha256_text().substr(0, 16)


## 复刻 Python round(v, ndigits)：round-half-even 正确舍入（ndigits >= 0）。
func _py_round(v: float, ndigits: int) -> float:
	var scale: float = pow(10.0, float(ndigits))
	var y: float = v * scale
	var flr: float = floor(y)
	var frac: float = y - flr
	if frac > 0.5:
		return (flr + 1.0) / scale
	if frac < 0.5:
		return flr / scale
	var err: float = _mul_err(v, scale, y)
	if err > 0.0:
		return (flr + 1.0) / scale
	if err < 0.0:
		return flr / scale
	if fmod(flr, 2.0) == 0.0:
		return flr / scale
	return (flr + 1.0) / scale


func _mul_err(v: float, b: float, p: float) -> float:
	var C := 134217729.0
	var tv := C * v
	var v_hi := tv - (tv - v)
	var v_lo := v - v_hi
	var tb := C * b
	var b_hi := tb - (tb - b)
	var b_lo := b - b_hi
	return ((v_hi * b_hi - p) + v_hi * b_lo + v_lo * b_hi) + v_lo * b_lo
