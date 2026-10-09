extends SceneTree
## GDScript 侧逐 tick 状态导出（对拍基建），字段逐一对齐 tools/export_ticks.py。
##
## 采样点 = advance_tick() 返回后（= _tick() 之后），对应 Python「tick() 后 snapshot」。
## 供 tests/integration/test_tick_parity.py 调用：写 jsonl（每 tick 一行）到 --out 文件。
##
## 用法：
##   godot --headless --path . --script tests/integration/export_ticks_gd.gd \
##         -- --days=3 --seed=12345 --npc=8 --out=tools/out/ticks_gd.jsonl

const KERNEL_PATH := "res://scripts/core/sim_core.gd"


func _initialize() -> void:
	var args := _parse_user_args()
	var days: int = int(args.get("days", "3"))
	var seed_value: int = int(args.get("seed", "12345"))
	var npc: int = int(args.get("npc", "8"))
	var out_path: String = args.get("out", "tools/out/ticks_gd.jsonl")

	var tables := ConfigLoader.new().load_all()
	var core := SimCore.from_npc(seed_value, npc, tables)
	var n := core.node_count()

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("[parity] 无法打开输出文件：%s（err=%d）" % [out_path, FileAccess.get_open_error()])
		quit(1)
		return
	for _d in range(days):
		for _t in range(480):
			core.advance_tick()
			f.store_line(JSON.stringify(_snapshot(core, n)))
	f.close()
	quit(0)


func _parse_user_args() -> Dictionary:
	var out := {}
	for item in OS.get_cmdline_user_args():
		var text := String(item)
		if not text.begins_with("--") or not text.contains("="):
			continue
		var parts := text.substr(2).split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out


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
