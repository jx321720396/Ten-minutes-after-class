class_name SimCore
extends RefCounted
## 内核模拟器（主文档 §18.2 / 统一影响公式）。
##
## 与 Python 参考 `tools/core_sim.py` 位级对拍：同种子关键指标误差 ≤1%，
## 矩阵 hash 严格一致（见 tools/export_ticks.py）。为此：
##   · 随机数用自研 `MtRandom`（CPython `random.Random` 的逐位移植），不用 PCG32；
##   · 状态一律 `PackedFloat64Array`（float64），与 Python 的 double 逐位一致；
##   · 所有阈值 / 系数都来自 data/（不落脚本，铁律 3）。
##
## 索引约定：n = npc_count + 1（末位 n-1 为玩家）；矩阵平铺 A[i][j] → _a[i*n+j]；
## dims 为 dim-major（d*n+i），DIMS 顺序 e/n/f/p。
##
## D7 交付：确定性抽人 + 时间系统（run_day/tick，涓流每 settle_interval）；
## decide/transmission/settle 为占位（D8/D9/D10 补齐）。

const DIMS := ["e", "n", "f", "p"]
const AXES := ["affinity", "hostility", "trust"]

# —— 关系 / 个体状态（float64 平铺，与 Python 逐位一致）——
var _a := PackedFloat64Array()      # 好感 A  n*n
var _h := PackedFloat64Array()      # 敌对 H  n*n
var _h_deep := PackedFloat64Array() # 深层敌对 n*n（§10.22，永不衰减）
var _t := PackedFloat64Array()      # 信任 T  n*n
var _o := PackedFloat64Array()      # 透明度 O  n
var _stress := PackedFloat64Array() # 压力 Stress  n
var _dims := PackedFloat64Array()   # MBTI 四维（dim-major）DIMS.size()*n
var _b_a := PackedFloat64Array()    # 信念·好感 n*n
var _b_h := PackedFloat64Array()    # 信念·敌对 n*n
var _b_t := PackedFloat64Array()    # 信念·信任 n*n

var _rng: MtRandom
var _seed := 0
var _n := 0
var _day := 1
var _phase := "break"
var _tick_in_phase := 0
var _phase_index := 0
var _global_tick := 0
var _volume := 0.0

# —— 配置 ——
var _p: Dictionary = {}             # transmission 参数（含 settle_interval）
var _bp: Dictionary = {}            # belief 参数（先验 / 学习率 / 偏差）
var _kp: Dictionary = {}            # kernel 硬编码系数（kernel_params.csv）
var _probs: Dictionary = {}         # behavior_probs：行为 -> 基础概率
var _thresholds_lookup: Dictionary = {}
var _decay: Dictionary = {}
var _behaviors: Dictionary = {}
var _env: Dictionary = {}
var _nw: Dictionary = {}
var _event_rows: Array = []
var _tag_rows: Dictionary = {}
var _status_tags: Dictionary = {}

# —— 空间 / 座位 ——
var _seats: Array = []
var _seat_pos: Dictionary = {}
var _seat_of: Array = []
var _neighbors: Dictionary = {}

# —— 角色 / 相位 / 运行态 ——
var _chars: Array = []
var _bindings: Array = []
var _phase_rules: Dictionary = {}
var _phase_order: Array = []
var _character_tags: Array = []
var _current_act: Array = []
var _sleeping: Array = []
var _in_conversation: Array = []
var _next_action: Array = []
var _busy_until: Array = []
var _busy_phase: Array = []
var _knot_days: Array = []
var _vol_log: Array = []
var _day_events: Dictionary = {}
var _settled: Dictionary = {}
var _stats: Dictionary = {}


func _init(seed: int, npc_count: int, tables: Dictionary) -> void:
	_seed = seed
	_rng = MtRandom.new(seed)
	_n = npc_count + 1
	var n := _n

	_load_config(tables)

	# 抽角色（§11.5 正式版：绑定组 + 极性覆盖，不消费随机数）
	_chars = RosterSelector.new().select(
		_rows(tables, "characters/seeds"),
		_bindings,
		npc_count,
		float(_kp["mbti_neutral"]))

	_alloc(n)

	# 透明度 / MBTI 四维
	for i in range(_chars.size()):
		var ch: Dictionary = _chars[i]
		_o[i] = _float_or(ch, "opacity_init", float(_kp["opacity_default"]))
		for d in range(DIMS.size()):
			_dims[d * n + i] = float(str(ch[DIMS[d]]))
	_o[n - 1] = float(_kp["opacity_default"])
	for d in range(DIMS.size()):
		_dims[d * n + (n - 1)] = float(_kp["mbti_neutral"])

	# 信念矩阵先验
	var prior_a := float(_bp["prior_a"])
	var prior_h := float(_bp["prior_h"])
	var prior_t := float(_bp["prior_t"])
	for i in range(n):
		for j in range(n):
			_b_a[i * n + j] = prior_a
			_b_h[i * n + j] = prior_h
			_b_t[i * n + j] = prior_t

	_init_relations()
	_init_belief_bias()

	_volume = float(_env.get("init_volume", 0.0))

	_character_tags = _build_character_tags()

	# 空间层（必须在 seats/neighbors 之后）
	_neighbors = _build_neighbors()
	_assign_seats()

	# 时间 / 统计 / 每节点运行态
	_reset_runtime(n)


func _load_config(tables: Dictionary) -> void:
	_p = _params(tables, "rules/transmission")
	_bp = _params(tables, "rules/belief")
	_kp = _params(tables, "rules/kernel_params")
	_probs = _build_behavior_probs(tables)
	_thresholds_lookup = _build_thresholds(tables)
	_decay = _params(tables, "rules/decay")
	_behaviors = _build_behaviors(tables)
	_env = _params(tables, "rules/environment")
	_nw = _params(tables, "balance/npc_weights")
	_event_rows = _rows(tables, "balance/w_events")
	_tag_rows = _index_by(tables, "rules/tags", "tag_id")
	_status_tags = _index_by(tables, "rules/status_tags", "tag_id")
	_seats = _rows(tables, "rules/seats")
	_seat_pos = {}
	for r in _seats:
		_seat_pos[str(r["seat_id"])] = [int(str(r["row"])), int(str(r["col"]))]
	_phase_order = _rows(tables, "rules/phases")
	_phase_rules = {}
	for r in _phase_order:
		_phase_rules[str(r["phase_id"])] = str(r.get("active_rules", "none")).split("|")
	_bindings = _rows(tables, "characters/bindings")


func _alloc(n: int) -> void:
	_a.resize(n * n)
	_h.resize(n * n)
	_h_deep.resize(n * n)
	_t.resize(n * n)
	_o.resize(n)
	_stress.resize(n)
	_dims.resize(DIMS.size() * n)
	_b_a.resize(n * n)
	_b_h.resize(n * n)
	_b_t.resize(n * n)


func _reset_runtime(n: int) -> void:
	_day = 1
	_phase = "break"
	_tick_in_phase = 0
	_phase_index = 0
	_global_tick = 0
	_vol_log = []
	_day_events = {}
	_settled = {}
	_stats = {
		"events": 0, "chats": 0, "joins": 0, "reports": 0, "bursts": 0,
		"interrupts": 0, "transmission_ticks": 0, "skipped_events": 0,
		"dedup_skips": 0, "teases": 0, "tease_fail": 0, "rumors": 0,
		"excludes": 0, "roughhouse": 0, "sleeps": 0,
	}
	_next_action = []
	_busy_until = []
	_busy_phase = []
	_current_act = []
	_sleeping = []
	_in_conversation = []
	_knot_days = []
	_seat_of = []
	for _i in range(n):
		_next_action.append(0)
		_busy_until.append(0)
		_busy_phase.append(-1)
		_current_act.append(null)
		_sleeping.append(false)
		_in_conversation.append(false)
		_knot_days.append(0)
		_seat_of.append("")


# ------------------------------------------------------------------ 初始化关系
func _init_relations() -> void:
	var n := _n
	var base_a := float(_kp["init_affinity_base"])
	var spread_a := float(_kp["init_affinity_spread"])
	var spread_h := float(_kp["init_hostility_spread"])
	var base_t := float(_kp["init_trust_base"])
	var spread_t := float(_kp["init_trust_spread"])
	for i in range(n):
		for j in range(n):
			if i == j:
				continue
			_a[i * n + j] = _clamp100(base_a + _rng.random() * spread_a)
			_h[i * n + j] = _clamp100(_rng.random() * spread_h)
			_t[i * n + j] = _clamp100(base_t + _rng.random() * spread_t)
	_apply_bindings()


## 绑定组覆盖（按 bindings.csv 行序，后行覆盖前行）。
func _apply_bindings() -> void:
	var by_alias := {}
	for i in range(_chars.size()):
		by_alias[str(_chars[i]["alias"])] = i
	for b in _bindings:
		var from_a := str(b["from"])
		if not by_alias.has(from_a):
			continue
		var fi: int = by_alias[from_a]
		var to_a := str(b["to"])
		if to_a == "*":
			if str(b.get("affinity", "")) != "":
				var av := float(str(b["affinity"]))
				for j in range(_n):
					if j != fi:
						_a[fi * _n + j] = av
			continue
		if not by_alias.has(to_a):
			continue
		var tj: int = by_alias[to_a]
		if str(b.get("affinity", "")) != "":
			_a[fi * _n + tj] = float(str(b["affinity"]))
		if str(b.get("trust", "")) != "":
			_t[fi * _n + tj] = float(str(b["trust"]))


## 初始信念偏差（docs/design/信念矩阵.md §3，性格函数而非随机数）。
func _init_belief_bias() -> void:
	var n := _n
	var w := float(_bp["w_bias"])
	var k := float(_bp.get("bias_observer_k", 0.0))
	var tr := float(_bp.get("bias_trust_ratio", 0.0))
	var neutral := float(_kp["mbti_neutral"])
	var scale := float(_kp["mbti_scale"])
	var we := float(_kp["bias_e_weight"])
	var wf := float(_kp["bias_f_weight"])
	var ts := float(_kp["bias_trust_scale"])
	for i in range(n):
		for j in range(n):
			if i == j:
				continue
			var perceived := _friendly_bias(j, neutral, scale, we, wf)
			var observer := _friendly_bias(i, neutral, scale, we, wf)
			var bias_a := w * perceived * (1.0 + k * observer)
			_b_a[i * n + j] = _clamp100(_b_a[i * n + j] + bias_a)
			_b_h[i * n + j] = _clamp100(_b_h[i * n + j] - bias_a)
			_b_t[i * n + j] = _clamp100(_b_t[i * n + j] + tr * w * observer * ts)


## 「看起来多友善」：外向(E) + 共情(F) 归一化加权（perceived 与 observer 同式）。
func _friendly_bias(node: int, neutral: float, scale: float, we: float, wf: float) -> float:
	var e := (_dims[node] - neutral) / scale * we
	var f := (_dims[2 * _n + node] - neutral) / scale * wf
	return e + f


# ------------------------------------------------------------------ 空间层
func _build_neighbors() -> Dictionary:
	var ids: Array = []
	for r in _seats:
		ids.append(str(r["seat_id"]))
	var nb := {}
	for a in ids:
		var ra: int = int(_seat_pos[a][0])
		var ca: int = int(_seat_pos[a][1])
		var s: Array = []
		for b in ids:
			if a == b:
				continue
			var rb: int = int(_seat_pos[b][0])
			var cb: int = int(_seat_pos[b][1])
			if maxi(absi(ra - rb), absi(ca - cb)) <= 1:
				s.append(b)
		nb[a] = s
	return nb


func _assign_seats() -> void:
	var ids: Array = []
	for r in _seats:
		ids.append(str(r["seat_id"]))
	_rng.shuffle(ids)
	_seat_of = []
	for i in range(_n):
		_seat_of.append(ids[i])


# ------------------------------------------------------------------ 时间系统
## 跑完一天（三段课间 + 两段上课），返回总 tick 数。
func run_day() -> int:
	var total := 0
	var pidx := 0
	for row in _phase_order:
		if str(row["kind"]) == "settle":
			continue
		_phase_index = pidx
		_phase = str(row["kind"])
		_tick_in_phase = 0
		_settle_sleep()
		_roll_sleep()
		_free_join()
		if _phase == "break":
			_phone_exposure()
			_roll_reports()
		_check_interrupt()
		var ticks := int(str(row["tick_count"]))
		for _t in range(ticks):
			_tick()
			_tick_in_phase += 1
			total += 1
		_vol_log.append(snapped(_volume, 0.1))
		pidx += 1
	_settle_day()
	return total


func _tick() -> void:
	_global_tick += 1
	_decide_and_act()
	_update_environment()
	if _global_tick % int(_p["settle_interval"]) == 0:
		_transmission()
		_stress_drip()


## 跨天结算（D7 占位：仅推进天数；D8 补衰减/遗忘，D9 补压力爆发/心结）。
func _settle_day() -> void:
	_day_events.clear()
	_day += 1


# ------------------------------------------------------------------ 占位（D8/D9/D10 补齐）
func _settle_sleep() -> void:
	pass


func _roll_sleep() -> void:
	pass


func _free_join() -> void:
	pass


func _phone_exposure() -> void:
	pass


func _roll_reports() -> void:
	pass


func _check_interrupt() -> void:
	pass


func _decide_and_act() -> void:
	pass


func _update_environment() -> void:
	pass


func _transmission() -> void:
	pass


func _stress_drip() -> void:
	pass


# ------------------------------------------------------------------ 报告
func report() -> String:
	var n := _n
	var aff: Array = []
	for i in range(n):
		for j in range(n):
			if i != j:
				aff.append(_a[i * n + j])
	aff.sort()
	var total := 0.0
	for v in aff:
		total += v
	var mean := total / aff.size()
	var sat_th := float(_kp["saturated_threshold"])
	var sat_count := 0
	for v in aff:
		if v >= sat_th:
			sat_count += 1
	var saturated := float(sat_count) / aff.size()
	var err := 0.0
	for i in range(n):
		for j in range(n):
			if i != j:
				err += absf(_b_a[i * n + j] - _a[j * n + i])
	err /= float(aff.size())

	var lines: Array = []
	lines.append("=== 内核运行统计（seed=%d, 天数=%d, 节点=%d）===" % [_seed, _day - 1, n])
	lines.append("  好感：min %.1f / 中位 %.1f / 均值 %.1f / max %.1f" % [
		aff[0], aff[aff.size() / 2], mean, aff[aff.size() - 1]])
	lines.append("  接近饱和(>=%.0f)比例：%.1f%%" % [sat_th, saturated * 100.0])
	lines.append("  事件 %d 次（闲聊 %d / 搭话 %d / 举报 %d）" % [
		_stats["events"], _stats["chats"], _stats["joins"], _stats["reports"]])
	lines.append("  睡着 %d 人次 | 调侃 %d（过火 %d）/ 流言 %d / 排挤 %d / 打闹 %d / 被打断 %d" % [
		_stats["sleeps"], _stats["teases"], _stats["tease_fail"], _stats["rumors"],
		_stats["excludes"], _stats["roughhouse"], _stats["interrupts"]])
	lines.append("  去重跳过 %d 次" % _stats["dedup_skips"])
	lines.append("  传导结算 %d 次 | 压力爆发 %d 次（平均每 %.1f 天一次）" % [
		_stats["transmission_ticks"], _stats["bursts"],
		float(_day - 1) / float(maxi(1, _stats["bursts"]))])
	lines.append("  信念平均误差 |B − 真值|：%.1f" % err)
	return "\n".join(lines)


# ------------------------------------------------------------------ 只读访问器（§4.1）
func seed() -> int:
	return _seed


func node_count() -> int:
	return _n


func day() -> int:
	return _day


func phase() -> String:
	return _phase


func phase_index() -> int:
	return _phase_index


func global_tick() -> int:
	return _global_tick


func tick_in_phase() -> int:
	return _tick_in_phase


func volume() -> float:
	return _volume


func affinity(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= _n or j >= _n or i == j:
		return 0.0
	return _a[i * _n + j]


func hostility(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= _n or j >= _n or i == j:
		return 0.0
	return _h[i * _n + j]


func trust(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= _n or j >= _n or i == j:
		return 0.0
	return _t[i * _n + j]


func opacity(i: int) -> float:
	if i < 0 or i >= _n:
		return 0.0
	return _o[i]


func stress(i: int) -> float:
	if i < 0 or i >= _n:
		return 0.0
	return _stress[i]


# ------------------------------------------------------------------ 内部工具
func _clamp100(v: float) -> float:
	return clampf(v, 0.0, 100.0)


func _params(tables: Dictionary, name: String) -> Dictionary:
	var out := {}
	var t: Dictionary = tables.get(name, {})
	for row in t.get("rows", []):
		out[str(row["param"])] = float(str(row["value"]))
	return out


func _rows(tables: Dictionary, name: String) -> Array:
	return tables.get(name, {}).get("rows", [])


func _index_by(tables: Dictionary, name: String, key: String) -> Dictionary:
	var out := {}
	for row in _rows(tables, name):
		out[str(row[key])] = row
	return out


func _build_behavior_probs(tables: Dictionary) -> Dictionary:
	var out := {}
	for row in _rows(tables, "rules/behavior_probs"):
		out[str(row["behavior"])] = float(str(row["base_p"]))
	return out


func _build_thresholds(tables: Dictionary) -> Dictionary:
	var out := {}
	for row in _rows(tables, "rules/behavior_thresholds"):
		out["%s_%s" % [str(row["behavior"]), str(row["metric"])]] = float(str(row["value"]))
	return out


func _build_behaviors(tables: Dictionary) -> Dictionary:
	var out := {}
	for row in _rows(tables, "rules/behaviors"):
		out[str(row["behavior"])] = {
			"duration": int(float(str(row["duration"]))),
			"payoff": float(str(row["payoff"])),
			"kind": str(row["kind"]),
			"noise": float(str(row.get("noise", "0"))),
			"join_mode": str(row.get("join_mode", "none")).strip_edges(),
		}
	return out


func _build_character_tags() -> Array:
	var tags: Array = []
	for c in _chars:
		var row: Array = []
		var raw := str(c.get("tags", ""))
		if raw != "":
			for t in raw.split("|"):
				if t != "":
					row.append(t)
		tags.append(row)
	tags.append([])  # 玩家（末位）无标签
	return tags


func _float_or(row: Dictionary, key: String, fallback: float) -> float:
	var s := str(row.get(key, ""))
	if s == "":
		return fallback
	return float(s)
