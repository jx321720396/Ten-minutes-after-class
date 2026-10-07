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
## D8 交付：统一影响公式（apply_event）+ 传导（transmission）+ 涓流（stress_drip
## 及环境层/社会层）移植自 tools/core_sim.py；行为决策/跨天衰减/压力爆发仍为 D9/D10。

const DIMS := ["e", "n", "f", "p"]
const AXES := ["affinity", "hostility", "trust"]
const _NEVER := -999  # 时间哨兵：「从未发生」（Python 参考用 -10**9 / -999；语义等价，统一 -999）

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
var _neighbor_idx: Array = []        # 角色 → 邻居角色索引（对称，对应 Python assign_seats 的 neighbor_idx）
var _feedback := 0.0                  # 负反馈强度（transmission.csv 的 feedback）

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
var _hurt_day: Array = []             # 施害者侧证据：最近一次 i 对 j 做重大敌对行为的日（§8.4）
var _exclude_last_day: Array = []     # 排挤冷却：同一目标最近被驱逐的日（§10.25）
var _witness_day: Array = []          # 举报把柄：i 最近目击 j 违规的日（§10.2）


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

	# 时间 / 统计 / 每节点运行态（须在空间层之前，避免清掉 _seat_of）
	_reset_runtime(n)

	# 空间层（座位 + 邻接索引；须在 _reset_runtime 之后，_seat_of 才不会被清空）
	_neighbors = _build_neighbors()
	_assign_seats()
	_build_neighbor_idx()


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
	_feedback = float(_p.get("feedback", 0.0))


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
		"excludes": 0, "roughhouse": 0, "sleeps": 0, "deep_writes": 0,
		"noise_grudges": 0, "free_joins": 0, "join_accepts": 0,
		"join_rejects": 0, "humiliations": 0,
	}
	_next_action = []
	_busy_until = []
	_busy_phase = []
	_current_act = []
	_sleeping = []
	_in_conversation = []
	_knot_days = []
	_exclude_last_day = []
	_hurt_day = []
	_witness_day = []
	for _i in range(n):
		_next_action.append(0)
		_busy_until.append(0)
		_busy_phase.append(-1)
		_current_act.append(null)
		_sleeping.append(false)
		_in_conversation.append(false)
		_knot_days.append(0)
		_exclude_last_day.append(_NEVER)
	for _ij in range(n * n):
		_hurt_day.append(_NEVER)
		_witness_day.append(_NEVER)


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


## 邻接索引：角色 i 的邻居角色索引集（对称；Python assign_seats 的 neighbor_idx）。
func _build_neighbor_idx() -> void:
	_neighbor_idx = []
	for i in range(_n):
		var my_seat: String = _seat_of[i]
		var row: Array = []
		for k in range(_n):
			if _neighbors[my_seat].has(_seat_of[k]):
				row.append(k)
		_neighbor_idx.append(row)


func _are_neighbors(i: int, j: int) -> bool:
	return _neighbor_idx[i].has(j)


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


# ------------------------------------------------------------------ 统一影响公式（UIF，docs/design/统一影响公式.md）
## 四舍五入到 0.1（Python round(x,1)；结构常量 0.1 已白名单）。
func _r1(v: float) -> float:
	return snapped(v, 0.1)


## 性格倍率：M_personality = clamp(1 + Σ w_k·d_k, 0.1, 1.2)。
func _mult_personality(row: Dictionary, i: int) -> float:
	var neutral := float(_kp["mbti_neutral"])
	var scale := float(_kp["mbti_scale"])
	var w := [
		float(str(row["w_e"])), float(str(row["w_s"])),
		float(str(row["w_f"])), float(str(row["w_j"])),
	]
	var total := 1.0
	for k in range(DIMS.size()):
		total += w[k] * (_dims[k * _n + i] - neutral) / scale
	return clampf(total, 0.1, 1.2)


## 关系调制：M_relation = clamp((A−H)/50, −1, 1)。重大档（major）由调用方跳过。
func _m_relation(i: int, j: int) -> float:
	return clampf((_a[i * _n + j] - _h[i * _n + j]) / 50.0, -1.0, 1.0)


## 状态调制：M_state，按压力分段（UIF §2.3）。
func _m_state(i: int, negative: bool) -> float:
	var s := _stress[i]
	if s < 40.0:
		return 1.0
	if s < 70.0:
		return 1.5 if negative else 0.75
	if s < 90.0:
		return 1.5
	return 1.0


## 负反馈空间余量：room_for = 1 − feedback·value/100（敌对/压力不受限）。
func _room_for(axis: String, value: float) -> float:
	if _feedback <= 0.0 or axis == "hostility" or axis == "stress":
		return 1.0
	return maxf(0.0, 1.0 - _feedback * value / 100.0)


## 软饱和：sat(u) = u / (1 + |u|/U)，U 按轴取自 transmission.csv。
func _sat(u: float, axis: String) -> float:
	var key := "u_a"
	if axis == "hostility":
		key = "u_h"
	elif axis == "trust":
		key = "u_t"
	elif axis == "stress":
		key = "u_s"
	var U := float(_p.get(key, 25.0))
	return u / (1.0 + absf(u) / U)


## 统一影响公式落表：Δ = M_state · sat(P)；P = base·scale·M_personality(·M_relation)。
func _apply_event(i: int, j: int, event_id: String, scale: float = 1.0) -> bool:
	var dkey := "%d|%d|%s|%d|%d" % [i, j, event_id, _day, _phase_index]
	if _settled.has(dkey):
		_stats["dedup_skips"] = int(_stats["dedup_skips"]) + 1
		return false
	_settled[dkey] = true
	var dekey := "%d,%d" % [i, j]
	_day_events[dekey] = int(_day_events.get(dekey, 0)) + 1
	var applied := false
	for row in _event_rows:
		if str(row["event_id"]) != event_id:
			continue
		var axis := str(row["axis"])
		var base := float(str(row["base"]))
		var e_val := base * scale * _mult_personality(row, i)
		var is_axis := axis == "affinity" or axis == "hostility" or axis == "trust"
		if is_axis and str(row.get("tier", "normal")) != "major":
			e_val *= _m_relation(i, j)
		var p_val := e_val
		var negative := (base < 0.0) == is_axis
		var delta := 0.0
		if axis == "stress":
			delta = _r1(_sat(p_val, axis))
		else:
			delta = _r1(_m_state(i, negative) * _sat(p_val, axis))
		if axis == "hostility" and str(row.get("tier", "normal")) == "major":
			if delta > 0.0:
				_hurt_day[i * _n + j] = _day
			var cap := float(_env.get("deep_cap", 70.0))
			_h_deep[i * _n + j] = minf(cap, _h_deep[i * _n + j] + absf(delta))
			_stats["deep_writes"] = int(_stats.get("deep_writes", 0)) + 1
		if axis == "stress":
			_stress[i] = _clamp100(_stress[i] + delta)
		else:
			var idx := i * _n + j
			var cur := 0.0
			if axis == "affinity":
				cur = _a[idx]
			elif axis == "hostility":
				cur = _h[idx]
			else:
				cur = _t[idx]
			delta = _r1(_room_for(axis, cur) * delta)
			var v := _clamp100(cur + delta)
			if axis == "affinity":
				_a[idx] = v
			elif axis == "hostility":
				_h[idx] = v
			else:
				_t[idx] = v
		applied = true
		_stats["events"] = int(_stats["events"]) + 1
	return applied


# ------------------------------------------------------------------ 传导（§11 信念矩阵 / 统一影响公式 §3）
func _transmission() -> void:
	var n := _n
	var th_a := float(_p["theta_a"])
	var th_h := float(_p["theta_h"])
	var th_t := float(_p["theta_t"])
	var beta_a := float(_p["beta_a"])
	var beta_h := float(_p["beta_h"])
	var beta_t := float(_p["beta_t"])
	var eps := float(_p["epsilon"])
	var d_a := PackedFloat64Array()
	var d_h := PackedFloat64Array()
	var d_t := PackedFloat64Array()
	d_a.resize(n * n)
	d_h.resize(n * n)
	d_t.resize(n * n)
	for i in range(n):
		for k in range(n):
			if i == k:
				continue
			var w_sum := 0.0
			var num_a := 0.0
			var num_h := 0.0
			var num_t := 0.0
			for j in range(n):
				if j == i or j == k:
					continue
				var w := _a[i * n + j] / 100.0
				if w <= 0.0:
					continue
				w_sum += w
				num_a += w * maxf(0.0, _perceive(j, k, "affinity") - th_a)
				num_h += w * maxf(0.0, _perceive(j, k, "hostility") - th_h)
				num_t += w * maxf(0.0, _perceive(j, k, "trust") - th_t)
			if w_sum <= 0.0:
				continue
			var denom := w_sum + eps
			var net_a := (num_a - num_h) / denom
			var net_h := (num_h - num_a) / denom
			d_a[i * n + k] = _r1(_room_for("affinity", _a[i * n + k]) * _sat(beta_a * net_a, "affinity"))
			d_h[i * n + k] = _r1(_sat(beta_h * net_h, "hostility"))
			d_t[i * n + k] = _r1(_sat(beta_t * num_t / denom, "trust"))
	for i in range(n):
		for k in range(n):
			if i != k:
				_a[i * n + k] = _clamp100(_a[i * n + k] + d_a[i * n + k])
				_h[i * n + k] = _clamp100(_h[i * n + k] + d_h[i * n + k])
				_t[i * n + k] = _clamp100(_t[i * n + k] + d_t[i * n + k])
	_stats["transmission_ticks"] = int(_stats["transmission_ticks"]) + 1


## 观测档位（§11.2，通透/可见/模糊/封闭）。
func _tier(opacity: float) -> String:
	if opacity >= 80.0:
		return "clear"
	if opacity >= 50.0:
		return "visible"
	if opacity >= 20.0:
		return "blurry"
	return "sealed"


func _sigma_max(axis: String) -> float:
	if axis == "affinity":
		return float(_bp["sigma_max_a"])
	if axis == "hostility":
		return float(_bp["sigma_max_h"])
	return float(_bp["sigma_max_t"])


## FNV-1a 确定性噪声（j,k,axis 决定，无随机数）。
func _hash01(parts: Array) -> float:
	var h := 2166136261
	for p in parts:
		for b in str(p).to_utf8_buffer():
			h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return float(h % 10000) / 10000.0


## 感知值：j 对 k 的态度，加透明度噪声（封闭=0，模糊放大 1.5×）。
func _perceive(j: int, k: int, axis: String) -> float:
	var t := _tier(_o[j])
	if t == "sealed":
		return 0.0
	var val := 0.0
	if axis == "affinity":
		val = _a[j * _n + k]
	elif axis == "hostility":
		val = _h[j * _n + k]
	else:
		val = _t[j * _n + k]
	var z := _hash01([j, k, axis]) * 2.0 - 1.0
	var sigma := _sigma_max(axis) * (1.0 - _o[j] / 100.0)
	if t == "blurry":
		return _clamp100(val + sigma * z * 1.5)
	return _clamp100(val + sigma * z)


# ------------------------------------------------------------------ 涓流结算（stress_drip 及其环境/社会层）
## 环境音量：追踪当前进行中行为的噪声，向目标音量缓慢逼近。
func _update_environment() -> void:
	var target := 0.0
	for i in range(_n):
		if _global_tick >= _busy_until[i]:
			_current_act[i] = null
		var act = _current_act[i]
		if act == null:
			continue
		target += float(_behaviors.get(act, {}).get("noise", 0.0))
	var volume_max := float(_env["volume_max"])
	target = clampf(target, 0.0, volume_max)
	var rate := float(_env["adapt_rate"])
	_volume = clampf(_volume + rate * (target - _volume), 0.0, volume_max)


## 压力涓流：噪声压力 + 噪声敌对 + 从众敌对 + 偏差压力 + 学习/独处滴注。
func _stress_drip() -> void:
	_noise_pressure()
	_noise_hostility()
	_conformity_hostility()
	_deviance_pressure()
	for i in range(_n):
		if _in_conversation[i]:
			continue
		if _doing_study(i):
			_stress[i] = _clamp100(_stress[i] + float(_probs["study_stress"]))
		else:
			_stress[i] = _clamp100(_stress[i] + float(_probs["alone_stress"]))


func _noise_pressure() -> void:
	var excess := maxf(0.0, _volume - float(_env["volume_threshold"]))
	if excess <= 0.0:
		return
	var k := float(_env["stress_k"])
	var fj := float(_env["fear_j"])
	var fe := float(_env["fear_e"])
	var base := float(_env["noise_base_fear"])
	for i in range(_n):
		var fear := base + maxf(0.0, fj * _arg_j(i) + fe * _arg_i(i))
		_stress[i] = _clamp100(_stress[i] + excess * k * fear)


func _noise_hostility() -> void:
	var excess := maxf(0.0, _volume - float(_env["volume_threshold"]))
	if excess <= 0.0:
		return
	var scale := float(_env["noise_scale"])
	var base := float(_env["noise_hostility_base"]) * minf(2.0, excess / scale)
	if base <= 0.0:
		return
	for i in range(_n):
		var fear := _noise_fear(i)
		if fear <= 0.05:
			continue
		var culprits: Array = []
		for j in _neighbor_idx[i]:
			if j != i and not _sleeping[j] and _noise_of(j) > 0.0:
				culprits.append(j)
		if culprits.is_empty():
			continue
		culprits.sort_custom(func(a, b): return _noise_of(int(a)) > _noise_of(int(b)))
		for t in range(mini(2, culprits.size())):
			var j: int = culprits[t]
			_apply_event(i, j, "noise_hostility", base * fear)
			_stats["noise_grudges"] = int(_stats.get("noise_grudges", 0)) + 1


func _conformity_hostility() -> void:
	var see_window := float(_thresholds_lookup.get("conformity_see_window", 14.0))
	var need := int(_thresholds_lookup.get("conformity_min", 2.0))
	for i in range(_n):
		var conf := _conformity(i)
		if conf <= 0.05:
			continue
		for j in range(_n):
			if i == j:
				continue
			var haters: Array = []
			for k in _neighbor_idx[i]:
				if k == j or _sleeping[k]:
					continue
				var span: int = _day - int(_hurt_day[k * _n + j])
				if span >= 0 and span <= see_window:
					haters.append(k)
			if haters.size() >= need:
				_apply_event(i, j, "conformity_hostility", conf * float(haters.size()) / float(maxi(1, need)))


func _deviance_pressure() -> void:
	var k := float(_env.get("deviance_k", 0.0))
	if k <= 0.0:
		return
	var v := _volume / 100.0
	var loud := ["chat", "join_chat", "tease", "roughhouse"]
	for i in range(_n):
		var act = _current_act[i]
		if act == null:
			act = "study"
		if loud.has(act) and v < 0.4:
			_stress[i] = _clamp100(_stress[i] + k * (0.4 - v) * 10.0)
		elif act == "study" and v > 0.72:
			_stress[i] = _clamp100(_stress[i] + k * (v - 0.72) * 10.0)


func _noise_of(j: int) -> float:
	var act = _current_act[j]
	if act == null:
		return 0.0
	return float(_behaviors.get(act, {}).get("noise", 0.0))


func _noise_fear(i: int) -> float:
	var fj := float(_env["fear_j"])
	var fe := float(_env["fear_e"])
	return maxf(0.0, fj * _arg_j(i) + fe * _arg_i(i))


func _doing_study(_i: int) -> bool:
	return true


# ------------------------------------------------------------------ 相位结算
func _settle_sleep() -> void:
	var relief := float(_probs.get("sleep_relief", 0.0))
	for i in range(_n):
		if _sleeping[i]:
			_stress[i] = _clamp100(_stress[i] - relief)
			_sleeping[i] = false
			_busy_until[i] = 0
			_current_act[i] = null


func _check_interrupt() -> void:
	var cost := float(_probs.get("interrupted_stress", 0.0))
	for i in range(_n):
		if _busy_phase[i] >= 0 and _busy_phase[i] != _phase_index:
			_busy_until[i] = 0
			_busy_phase[i] = -1
			if cost > 0.0:
				_stress[i] = _clamp100(_stress[i] + cost)
			_stats["interrupts"] = int(_stats["interrupts"]) + 1


# ------------------------------------------------------------------ 行为决策（D10 补齐）
func _roll_sleep() -> void:
	pass


func _free_join() -> void:
	pass


func _phone_exposure() -> void:
	pass


func _roll_reports() -> void:
	pass


func _decide_and_act() -> void:
	pass


# ------------------------------------------------------------------ 性格/规则辅助（D8 涓流依赖，D10 行为决策复用）
func _arg_j(i: int) -> float:
	return (_dims[3 * _n + i] - float(_kp["mbti_neutral"])) / float(_kp["mbti_scale"])


func _arg_i(i: int) -> float:
	return (float(_kp["mbti_neutral"]) - _dims[i]) / float(_kp["mbti_scale"])


func _conformity(i: int) -> float:
	var neutral := float(_kp["mbti_neutral"])
	var f := (_dims[2 * _n + i] - neutral) / 100.0
	var j := _arg_j(i) / 2.0
	var n := (_dims[_n + i] - neutral) / 100.0
	return clampf(0.5 + f - j * 0.5 - n * 0.5, 0.0, 1.0)


func _crowd_bias(i: int, kind: String) -> float:
	var conf := _conformity(i)
	var v := _volume / 100.0
	if kind == "loud":
		return conf * v
	return conf * (1.0 - v)


func _tag_bias(i: int, effect_key: String) -> float:
	if _character_tags.is_empty():
		return 0.0
	var total := 0.0
	for tid in _character_tags[i]:
		var row: Dictionary = _tag_rows.get(tid, {})
		if row.is_empty() or str(row.get("effect", "")) != effect_key:
			continue
		total += 0.1 if str(row.get("strength", "")) == "weak" else 0.5
	return total


func _allowed(behavior: String) -> bool:
	var pid := ""
	if _phase_index >= 0 and _phase_index < _phase_order.size():
		pid = str(_phase_order[_phase_index]["phase_id"])
	var rules: Array = _phase_rules.get(pid, ["all"])
	if rules.has("all"):
		return true
	var banned := ["chat", "join_chat", "pass_note", "tease", "ask_help", "inform",
		"comfort", "apologize", "share_secret", "roughhouse", "exclude", "report", "move"]
	return not banned.has(behavior)


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
