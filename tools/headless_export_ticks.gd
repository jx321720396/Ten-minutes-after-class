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
	var core := SimCore.new(seed, npc, tables)
	var n := core.node_count()

	for _d in range(days):
		_run_day_sampled(core, n, func(c: SimCore, n2: int) -> void:
			print(JSON.stringify(_snapshot(c, n2))))
	quit(0)


## 跑完一天并逐 tick 采样，与 Python core_sim.run_day 同构：上课段黑幕硬跳过
## （skip_class：全员固定学业收益 + 崩溃判定，无逐 tick 结算、不采样），
## 课间段逐 tick 采样；段边界用 finish_time_boundary 推进，日末结算后返回。
func _run_day_sampled(core: SimCore, n: int, sink: Callable) -> void:
	while true:
		var snap: Dictionary = core.time_snapshot()
		if str(snap["kind"]) == "class":
			core.skip_class()
			continue
		if int(snap["tick_in_phase"]) < int(snap["tick_count"]):
			core.advance_tick()
			sink.call(core, n)
			continue
		if bool(core.finish_time_boundary()["day_settled"]):
			return


## 采样一行快照：字段与 export_ticks.py 的 snapshot() 一致。
## 老师版（2026-10-16）：信任 T 与透明度 O 轴已删除；新增动力 / 今日学业收益 / 崩溃计数。
func _snapshot(core: SimCore, n: int) -> Dictionary:
	var a: Array[float] = []
	var h: Array[float] = []
	for i in range(n):
		for j in range(n):
			a.append(core.affinity(i, j))
			h.append(core.hostility(i, j))
	var s: Array[float] = []
	var g: Array[float] = []
	var sa: Array[float] = []
	var v: Array[float] = []
	var gn: Array[float] = []
	for i in range(n):
		s.append(core.stress(i))
		g.append(core.grade(i))
		sa.append(core.study_acc(i))
		v.append(core.vitality(i))
		gn.append(core.gain_today(i))
	return {
		"tick": core.global_tick(),
		"rng_random_calls": core._rng.random_calls,
		"rng_words_consumed": core._rng.words_consumed,
		"day": core.day(),
		"phase": core.phase(),
		"phase_index": core.phase_index(),
		"tick_in_phase": core.tick_in_phase(),
		"A_mean": _mean(a),
		"H_mean": _mean(h),
		"stress_mean": _mean(s),
		"grade_mean": _mean(g),
		"vitality_mean": _mean(v),
		"gain_mean": _mean(gn),
		"broken_count": _broken_count(core),
		"A_hash": _digest(a),
		"H_hash": _digest(h),
		"grade_hash": _digest(g),
		"study_acc_hash": _digest(sa),
		"events": int(core._stats.get("events", 0)),
		"bursts": int(core._stats.get("bursts", 0)),
	}


## 崩溃人数（《老师版规则合并稿》D01 / D06）：与 tools/export_ticks.py 的 broken_count 对齐。
func _broken_count(core: SimCore) -> int:
	var count := 0
	for i in range(int(core.node_count())):
		if core.is_broken(i):
			count += 1
	return count


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
	var split_c := 134217729.0
	var tv := split_c * v
	var v_hi := tv - (tv - v)
	var v_lo := v - v_hi
	var tb := split_c * b
	var b_hi := tb - (tb - b)
	var b_lo := b - b_hi
	return ((v_hi * b_hi - p) + v_hi * b_lo + v_lo * b_hi) + v_lo * b_lo
