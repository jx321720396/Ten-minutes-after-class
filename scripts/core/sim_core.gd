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
## 及环境层/社会层）；D9 交付：压力爆发（try_burst/spread_knot）+ 跨天衰减
## （settle_day：各轴衰减 + 深/浅层敌对 + 信念遗忘回归）。行为决策（decide_and_act
## 及 do_report/do_tease 等 7 行为）仍为 D10。

const DIMS := ["e", "n", "f", "p"]
const AXES := ["affinity", "hostility", "trust"]
const _NEVER := -999  # 时间哨兵：「从未发生」（Python 参考用 -10**9 / -999；语义等价，统一 -999）
const _FOREVER := 1000000000  # 时间哨兵：「忙碌到远超本段」（睡觉等整段占用的 busy_until，对齐 Python 10**9）
const _ObserverLayer = preload("res://scripts/systems/observer/observer_layer.gd")

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
var _active_phases: Array = []   # 非 settle 段（课间/上课）顺序，供单步推进（D11）
var _phase_setup_done := false   # 当前段是否已跑段首一次性结算（D11）

## 事件出口（D11 缺口④）：表现层把此回调绑到 EventBus 四信号，内核零 autoload 依赖。
## 收到 {"type": String, "payload": Dictionary}；type ∈ event_happened / day_settled / tag_changed / stress_burst。
var event_sink: Callable = Callable()

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


func _init(seed: int, difficulty: int, tables: Dictionary = {}) -> void:
	# §4.1 契约：SimCore.new(seed, difficulty)。tables 为空时内核内部自取（ConfigLoader 非 autoload，不违反反向依赖铁律）。
	if tables.is_empty():
		tables = ConfigLoader.new().load_all()
	_seed = seed
	_rng = MtRandom.new(seed)
	var npc_count := _difficulty_npc_count(difficulty, tables)
	_n = npc_count + 1
	var n := _n

	_load_config(tables)

	# 单步推进游标：非 settle 段（课间/上课）顺序（D11）
	_active_phases = []
	for row in _phase_order:
		if str(row["kind"]) != "settle":
			_active_phases.append(row)

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


## difficulty（1/2/3）→ npc_count（8/16/24），映射表 data/rules/difficulty.csv（铁律 3：数值不落脚本）。
func _difficulty_npc_count(difficulty: int, tables: Dictionary) -> int:
	for row in _rows(tables, "rules/difficulty"):
		if int(str(row["difficulty"])) == difficulty:
			return int(str(row["npc_count"]))
	push_warning("SimCore: rules/difficulty 未命中 difficulty=%d，回退默认 8 NPC" % difficulty)
	return 8


## 测试/对拍专用入口：直接指定 npc_count，绕过 difficulty 映射。
## 经 data/rules/difficulty 反查 difficulty 后走同一构造，避免数值落脚本。
static func from_npc(seed: int, npc_count: int, tables: Dictionary) -> SimCore:
	for row in tables.get("rules/difficulty", {}).get("rows", []):
		if int(str(row["npc_count"])) == npc_count:
			return SimCore.new(seed, int(str(row["difficulty"])), tables)
	push_warning("SimCore.from_npc: npc_count=%d 不在 difficulty 映射，回退难度 1" % npc_count)
	return SimCore.new(seed, 1, tables)


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
## 段首一次性结算：睡觉收尾 / 入睡 / 自由跟随 /（课间）举报 / 打断（§10.8 等）。
func _begin_phase() -> void:
	var row: Dictionary = _active_phases[_phase_index]
	_phase = str(row["kind"])
	_tick_in_phase = 0
	_settle_sleep()
	_roll_sleep()
	_free_join()
	if _phase == "break":
		_phone_exposure()
		_roll_reports()
	_check_interrupt()
	_phase_setup_done = true


## 推进一个 tick（D11 单步粒度）。段未开始则先跑段首结算；段跑完自动跨段/跨天。
func advance_tick() -> int:
	if not _phase_setup_done:
		if _phase_index >= _active_phases.size():
			_phase_index = 0
		_begin_phase()
	_tick()
	_tick_in_phase += 1
	var row: Dictionary = _active_phases[_phase_index]
	if _tick_in_phase >= int(str(row["tick_count"])):
		_vol_log.append(snapped(_volume, 0.1))
		_phase_index += 1
		_phase_setup_done = false
		if _phase_index >= _active_phases.size():
			_settle_day()
	return _global_tick


## 推进一个段（从当前位置跑到当前段末尾），返回本段跑的 tick 数。
func advance_phase() -> int:
	if _phase_index >= _active_phases.size():
		return 0
	var ran := 0
	if not _phase_setup_done:
		_begin_phase()
	var target := int(str(_active_phases[_phase_index]["tick_count"]))
	while _tick_in_phase < target:
		advance_tick()
		ran += 1
	return ran


## 推进一天（从当前位置跑到当天结束并跨天结算），返回当天跑的 tick 数。
func advance_day() -> int:
	var total := 0
	if _phase_index >= _active_phases.size():
		_phase_index = 0
		_phase_setup_done = false
	while _phase_index < _active_phases.size():
		total += advance_phase()
	return total


## 跑完一天（三段课间 + 两段上课），返回总 tick 数。等价 advance_day()。
func run_day() -> int:
	return advance_day()


func _tick() -> void:
	_global_tick += 1
	_decide_and_act()
	_update_environment()
	if _global_tick % int(_p["settle_interval"]) == 0:
		_transmission()
		_stress_drip()


# ------------------------------------------------------------------ 事件出口（D11 缺口④：内核 → 表现层，零 autoload 依赖）
## 向注入的事件出口派发一条事件（type + payload）。event_sink 为空时无副作用（headless/测试）。
func _emit(type: String, payload: Dictionary) -> void:
	if event_sink.is_valid():
		event_sink.call({"type": type, "payload": payload})


# ------------------------------------------------------------------ 跨天结算（D9：§3.5 / §10.22 / §10.29）
## 概率爆发（不是「到点必爆」，§3.5 / §8.3）。压力跨过入口阈值 burst_stress 后**每天判定一次**：
##   p = burst_p_max × severity，severity = (stress − θ) / (100 − θ)。
## severity 同时放大波及范围与心结时长 —— 「拖得越久、压力越高、爆得越大」。
func _try_burst() -> void:
	var th := float(_thresholds_lookup.get("burst_stress", 70.0))
	var pmax := float(_probs.get("burst_p_max", 0.0))
	if pmax <= 0.0:
		return
	var tag: Dictionary = _status_tags.get("heart_knot", {})
	for i in range(_n):
		var s := _stress[i]
		if s < th:
			continue
		var severity := clampf((s - th) / (100.0 - th), 0.0, 1.0)
		if _rng.random() >= pmax * severity:
			continue
		_stress[i] = _clamp100(s - 40.0)
		if not tag.is_empty():
			_knot_days[i] = maxi(_knot_days[i], roundi(float(tag["days"]) * (1.0 + severity)))
			_emit("tag_changed", {"id": i, "tag": "heart_knot"})
		_spread_knot(i, severity)
		_stats["bursts"] = int(_stats["bursts"]) + 1
		_emit("stress_burst", {"i": i})
		_emit("event_happened", {"kind": "burst", "i": i, "severity": severity})


## 爆发传染：把「心结」扩散给与 i 关系最鲜明的少数人（|A − H| 越大越容易被波及）。
## 关系最鲜明者优先（稳定排序等价 Python list.sort：键值相同按 j 升序）。
func _spread_knot(i: int, severity: float) -> void:
	var tag: Dictionary = _status_tags.get("heart_knot", {})
	if tag.is_empty():
		return
	var ratio := float(tag.get("spread_ratio", 0))
	var kmax := int(float(tag.get("spread_max", 0)))
	if ratio <= 0.0 or kmax <= 0:
		return
	var others: Array = []
	for j in range(_n):
		if j != i and _knot_days[j] == 0:
			others.append(j)
	if others.is_empty():
		return
	others.sort_custom(func(a, b):
		var ka := -absf(_a[i * _n + a] - _h[i * _n + a])
		var kb := -absf(_a[i * _n + b] - _h[i * _n + b])
		if ka != kb:
			return ka < kb
		return a < b
	)
	var pool_size := maxi(1, int(float(others.size()) * ratio))
	var pool: Array = others.slice(0, pool_size)
	var kmax_eff := roundi(float(kmax) * (1.0 + severity))
	var days_eff := roundi(float(tag["days"]) * (1.0 + severity))
	for j in _rng.sample(pool, mini(kmax_eff, pool.size())):
		_knot_days[j] = maxi(_knot_days[j], days_eff)
		_emit("tag_changed", {"id": j, "tag": "heart_knot"})


## 跨天结算（§3.5）：压力爆发概率判定 → 信念遗忘回归 → 心结每日加压 → 各轴衰减。
func _settle_day() -> void:
	_try_burst()
	# 信念遗忘回归（lambda_b）：每天把信念向先验缓慢拉回（§18.9，本轮补齐）。
	var lam := float(_bp.get("lambda_b", 0.0))
	if lam > 0.0:
		var prior_a := float(_bp["prior_a"])
		var prior_h := float(_bp["prior_h"])
		var prior_t := float(_bp["prior_t"])
		for i in range(_n):
			for j in range(_n):
				if i == j:
					continue
				var idx := i * _n + j
				_b_a[idx] = _clamp100(_b_a[idx] + lam * (prior_a - _b_a[idx]))
				_b_h[idx] = _clamp100(_b_h[idx] + lam * (prior_h - _b_h[idx]))
				_b_t[idx] = _clamp100(_b_t[idx] + lam * (prior_t - _b_t[idx]))
	# 「心结」：爆发后的几天里，每天先加压（长线心理创伤，§3.5）。
	for i in range(_n):
		if _knot_days[i] > 0:
			_stress[i] = _clamp100(_stress[i] + float(_status_tags["heart_knot"]["daily_stress"]))
			_knot_days[i] -= 1
	# 各轴衰减：深层敌对原样保留、只衰减表层（§10.22），深层极慢衰减（§10.29）。
	var decay_h := float(_decay["decay_h"])
	var decay_t := float(_decay["decay_t"])
	var decay_a_interact := float(_decay["decay_a_interact"])
	var decay_a_no_interact := float(_decay["decay_a_no_interact"])
	var deep_decay := float(_decay["deep_decay"])
	var interact_min := float(_decay["interact_min_events"])
	var retain_s := float(_decay["retain_s"])
	for i in range(_n):
		for j in range(_n):
			if i == j:
				continue
			var idx := i * _n + j
			var interacted := float(_day_events.get("%d,%d" % [i, j], 0)) >= interact_min
			_a[idx] *= decay_a_interact if interacted else decay_a_no_interact
			_h_deep[idx] *= deep_decay
			var deep := _h_deep[idx]
			var surf := maxf(0.0, _h[idx] - deep)
			_h[idx] = minf(100.0, deep + surf * decay_h)
			_t[idx] *= decay_t
		_stress[i] *= retain_s
	_day_events.clear()
	_day += 1
	_emit("day_settled", {"day": _day - 1, "stats": _stats.duplicate(true)})


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
			# ⚠️ `_hurt_day` 不在此维护（2026-10-07 同步 main `1458563` 修复）：本方法的
			#    (i, j) 是「被作用方 → 作用方」，而读者（排挤 §10.25、从众 §10.24）要的是
			#    「施害者 → 受害者」，两者恰好相反，曾把受害者误记为施害者。
			#    改由调用点用 `_mark_hurt(施害者, 受害者)` 显式记录（D10 接线 do_report/do_tease）。
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


## 记录「施害者 → 受害者」的最近一次**重大**敌对行为（§10.25 排挤判据、§10.24 从众判据）。
## ⚠️ 只在 tier = major 的事件调用点使用（do_report/do_tease，D10 接线）——日常摩擦
##    （noise_hostility 等）每天让几乎所有人互相「损害」，若一并记录，「被 3 人损害」会成常态、排挤天天发生。
func _mark_hurt(perpetrator: int, victim: int) -> void:
	_hurt_day[perpetrator * _n + victim] = _day


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


# ------------------------------------------------------------------ 信念观测（§11 信念矩阵，D10）
## i 通过一次观测更新「j 对 i 的 axis」信念：噪声由被观测者透明度决定、学习率由信任决定。
func _observe(i: int, j: int, axis: String, weight: float = 1.0) -> void:
	if i == j:
		return
	var idx := i * _n + j
	var true_val := 0.0
	var cur := 0.0
	if axis == "affinity":
		true_val = _a[j * _n + i]
		cur = _b_a[idx]
	elif axis == "hostility":
		true_val = _h[j * _n + i]
		cur = _b_h[idx]
	else:
		true_val = _t[j * _n + i]
		cur = _b_t[idx]
	var sigma := _sigma_max(axis) * (1.0 - _o[j] / 100.0)
	var z := _hash01([i, j, axis]) * 2.0 - 1.0
	var bias := 0.0
	if axis == "affinity":
		# 外观偏差：外向/共情越高越「看起来友善」（与 Python 逐字一致：50/50 基准、各 0.5 权重）
		bias = float(_bp["w_bias"]) * _friendly_bias(j, float(_kp["mbti_neutral"]), float(_kp["mbti_scale"]), 0.5, 0.5)
	var obs := _clamp100(true_val + sigma * z + bias)
	var eta_key := "eta0_a"
	if axis == "hostility":
		eta_key = "eta0_h"
	elif axis == "trust":
		eta_key = "eta0_t"
	var eta := float(_bp[eta_key]) * (0.3 + 0.7 * _t[idx] / 100.0) * weight
	var updated := _clamp100(cur + eta * (obs - cur))
	if axis == "affinity":
		_b_a[idx] = updated
	elif axis == "hostility":
		_b_h[idx] = updated
	else:
		_b_t[idx] = updated


# ------------------------------------------------------------------ 决策辅助（D10）
## logistic：p ∈ (0,1)，无 0/1 硬闸门（§6.4）。
func _sigmoid(z: float) -> float:
	if z >= 0.0:
		return 1.0 / (1.0 + exp(-z))
	var e := exp(z)
	return e / (1.0 + e)


## softmax 采样：返回选中下标；tau 必须 > 0（§8 不变式 5）。
func _softmax(scores: Array, tau: float) -> int:
	assert(tau > 0.0, "softmax: tau 必须 > 0")
	var m := float(scores[0])
	for s in scores:
		m = maxf(m, float(s))
	var exps: Array = []
	var total := 0.0
	for s in scores:
		var e := exp((float(s) - m) / tau)
		exps.append(e)
		total += e
	var r := _rng.random() * total
	var acc := 0.0
	for k in range(exps.size()):
		acc += float(exps[k])
		if r <= acc:
			return k
	return exps.size() - 1


## 意向权重 alpha：MBTI 四维线性组合后归一化（Σ=1，§4.3）。
func _alpha(i: int) -> Dictionary:
	var raw := {
		"affinity": float(_nw["alpha_a_base"]) + float(_nw["alpha_a_f"]) * _dims[2 * _n + i] / 100.0 \
				+ float(_nw["alpha_a_e"]) * _dims[i] / 100.0,
		"trust": float(_nw["alpha_t_base"]) + float(_nw["alpha_t_j"]) * (1.0 + _arg_j(i)) / 2.0,
		"hostility": float(_nw["alpha_h_base"]) + float(_nw["alpha_h_f"]) * (1.0 - _dims[2 * _n + i] / 100.0) \
				+ float(_nw["alpha_h_j"]) * (1.0 + _arg_j(i)) / 2.0,
		"stress": float(_nw["alpha_s_base"]) + float(_nw["alpha_s_e"]) * (1.0 - _dims[i] / 100.0),
	}
	var total := float(raw["affinity"]) + float(raw["trust"]) + float(raw["hostility"]) + float(raw["stress"])
	return {
		"affinity": float(raw["affinity"]) / total,
		"trust": float(raw["trust"]) / total,
		"hostility": float(raw["hostility"]) / total,
		"stress": float(raw["stress"]) / total,
	}


## 意向温度 tau：高 J 更确定（温度更低）；压力 ≥70 更冲动（温度放大）；下限 0.01（§4.4）。
func _tau(i: int) -> float:
	var t := float(_nw["tau0"]) * (1.0 + float(_nw["tau_j"]) * (0.5 - _arg_j(i) / 2.0))
	if _stress[i] >= 70.0:
		t *= float(_nw["tau_stress_mult"])
	return maxf(t, 0.01)


## 搭话决策侧软门槛：低于门槛只降概率、不排除候选（§6.4）。
func _join_gate_utility(i: int, j: int) -> float:
	var ga := float(_thresholds_lookup["join_chat_gate_affinity"])
	var gs := float(_thresholds_lookup["join_chat_gate_stress"])
	var scale := float(_thresholds_lookup["join_chat_gate_scale"])
	var w := float(_thresholds_lookup["join_chat_gate_weight"])
	var za := (_a[i * _n + j] - ga) / scale
	var zs := (gs - _stress[i]) / scale
	return w * (_sigmoid(za) + _sigmoid(zs) - 1.0)


## 搭话判定侧 score：**被请求者的真值好感 A[j][i]** + 对方外向度 − 对方压力惩罚（§6.4）。
## 判定读真值 ——「他会不会接纳我」由他的真实态度决定，不由我的猜测决定；我的猜测只进
## 决策侧（要不要去试）与展示层（成功率）。读 A[j][i] 不违反 §18.7 不变式 3 ——
## 该不变式禁止的是**决策路径**读它；本方法属**判定路径**，规格要求它读真值。
func _join_score(i: int, j: int) -> float:
	var base := _a[j * _n + i] + (_dims[j] - 50.0) * 0.3
	var hot := maxf(0.0, _stress[j] - 50.0) / 50.0
	var penalty := float(_thresholds_lookup["join_chat_stress_penalty"])
	return base - penalty * hot


## 搭话判定侧概率：p = σ((score − θ)/scale)，永不为 0/1（§6.4）。
func _join_probability(i: int, j: int) -> float:
	var theta := float(_thresholds_lookup["join_chat_affinity"])
	var scale := float(_thresholds_lookup["join_chat_scale"])
	return _sigmoid((_join_score(i, j) - theta) / scale)


## 只读：玩家侧看到的成功率 p（从信念 B_A 算，不泄露真值；§10.32.3）。
## 显示值与实际结算值（_join_probability 读真值）刻意不同 ——「我明明有 80% 把握却被拒」
## 正是认知偏差的具象化，不是 bug（§10.32.4）。
func _join_feedback(i: int, j: int) -> Dictionary:
	var hot := maxf(0.0, _stress[j] - 50.0) / 50.0
	var score := _b_a[i * _n + j] + (_dims[j] - 50.0) * 0.3 \
		- float(_thresholds_lookup["join_chat_stress_penalty"]) * hot
	var theta := float(_thresholds_lookup["join_chat_affinity"])
	var scale := float(_thresholds_lookup["join_chat_scale"])
	return {"p": snapped(_sigmoid((score - theta) / scale), 0.01)}


## 一次判定的展示包（只读，不参与结算；实际掷骰在 _do_join_chat 里做，D11 玩家侧用）。
func _verdict(i: int, j: int, kind: String = "join_chat") -> Dictionary:
	if kind == "join_chat":
		var fb: Dictionary = _join_feedback(i, j)
		var roll := _rng.random()
		return {
			"kind": kind,
			"p": fb["p"],
			"roll": roll,
			"ok": roll < _join_probability(i, j),
			"note": "成功率来自「你以为对方怎么看你」，不是事实 —— 把握大也可能被拒。",
		}
	return {}


# ------------------------------------------------------------------ 行为决策（D10）
## 每课间段开始掷一次睡觉（§10.8：睡 = 本段不做其他事，段粒度而非 tick）。
func _roll_sleep() -> void:
	if not _allowed("sleep"):
		return
	var p := float(_probs["sleep"])
	for i in range(_n):
		if _sleeping[i]:
			continue
		if _rng.random() < p * (1.0 + _tag_bias(i, "alone_bias")):
			_sleeping[i] = true
			_current_act[i] = "sleep"
			_busy_until[i] = _FOREVER
			_stats["sleeps"] = int(_stats["sleeps"]) + 1


## 「别人做什么我也跟着做」：join_mode=free 的活动可自由跟随（§10.31），强度由从众度决定。
func _free_join() -> void:
	for i in range(_n):
		if _sleeping[i] or _busy_until[i] > _global_tick:
			continue
		var acts: Array = []
		for k in _neighbor_idx[i]:
			if k == i or _sleeping[k]:
				continue
			var a = _current_act[k]
			if a != null and _behaviors.get(a, {}).get("join_mode", "none") == "free":
				acts.append(a)
			elif a == null and _busy_until[k] <= _global_tick:
				acts.append("study")
		if acts.is_empty():
			continue
		var conf := _conformity(i)
		if conf <= 0.05:
			continue
		if _rng.random() < float(_probs["free_join_rate"]) * conf:
			var a = _rng.choice(acts)
			if a == "sleep" and _allowed("sleep"):
				_sleeping[i] = true
				_current_act[i] = "sleep"
				_busy_until[i] = _FOREVER
			elif a == "study":
				_current_act[i] = null
			_stats["free_joins"] = int(_stats.get("free_joins", 0)) + 1


## 举报把柄虚拟层（§10.2）：带手机者课间可能被邻居目击「玩手机」，产生把柄。
func _phone_exposure() -> void:
	var p := float(_probs["phone_expose_p"])
	if p <= 0.0:
		return
	for j in range(_n):
		if _sleeping[j] or not _character_tags[j].has("带手机"):
			continue
		if _rng.random() >= p:
			continue
		for i in _neighbor_idx[j]:
			if i == j or _sleeping[i]:
				continue
			_witness_day[i * _n + j] = _day


## 举报判定（§10.2）：每段课间对有把柄的候选掷一次骰（好友几乎不举报，但概率永不为 0）。
func _roll_reports() -> void:
	var th_rep := float(_thresholds_lookup["report_hostility"])
	var sc_rep := float(_thresholds_lookup["report_scale"])
	var win := float(_thresholds_lookup["report_witness_window"])
	var w_a := float(_thresholds_lookup["report_affinity_penalty"])
	var w_t := float(_thresholds_lookup["report_trust_penalty"])
	var p_rep := float(_probs["report_p"])
	for i in range(_n):
		if _sleeping[i]:
			continue
		for j in range(_n):
			if i == j or _sleeping[j] or _day - _witness_day[i * _n + j] > win:
				continue
			var z := (_h[i * _n + j] - th_rep) / sc_rep - w_a * _a[i * _n + j] / 100.0 - w_t * _t[i * _n + j] / 100.0
			if _rng.random() < p_rep * _sigmoid(z):
				_do_report(i, j)
				break


## 一 tick 内的行为决策：闲聊 → 调侃 → 打闹 → 排挤 → 流言 → 搭话。
## 铁律：决策顺序按索引升序（可复现，取代 Python 的 shuffle）；只读信念 B_*，不读真值 A[j][i]。
func _decide_and_act() -> void:
	var n := _n
	var busy: Array = []
	for _k in range(n):
		busy.append(false)
	for i in range(n):
		if _sleeping[i] or busy[i] or _global_tick < _busy_until[i]:
			continue
		_in_conversation[i] = false
		# 环境类：闲聊（标签调制：爱学习更少聊、爱聊天更多聊）
		var chat_gain := 1.0 + _tag_bias(i, "chat_bias") - _tag_bias(i, "study_bias")
		chat_gain = maxf(0.1, chat_gain)
		if _allowed("chat") and _rng.random() < float(_probs["chat"]) * chat_gain:
			var tgt := _pick_target(i)
			if tgt >= 0:
				_do_chat(i, tgt)
				busy[i] = true
				busy[tgt] = true
				continue
		# 意向类：当众调侃（需物理接近 + ≥3 人围观；目标偏好敌对高 / 好感低者）
		var cands_t: Array = []
		for j in range(n):
			if j != i and not busy[j] and not _sleeping[j] and _are_neighbors(i, j) \
					and (_a[i * n + j] >= 40.0 or _b_h[i * n + j] >= 25.0 or _a[i * n + j] < 25.0):
				cands_t.append(j)
		if _allowed("tease") and cands_t.size() >= 3 \
				and _rng.random() < float(_probs["tease_p"]) * (1.0 + _tag_bias(i, "tease_bias")):
			var wts: Array = []
			for t in cands_t:
				wts.append(maxf(1.0, pow((100.0 - _a[i * n + t]) + _h[i * n + t], 2.0)))
			var tgt: int = int(_rng.choices(cands_t, wts, 1)[0])
			var audience: Array = []
			for k in _neighbor_idx[i]:
				if _neighbor_idx[tgt].has(k) and k != i and k != tgt and not busy[k] and not _sleeping[k]:
					audience.append(k)
			if audience.size() >= 3:
				_do_tease(i, tgt, audience)
				busy[i] = true
				busy[tgt] = true
				continue
		# 意向类：追逐打闹（敌对种子：参与者好感↑ / 旁观者敌对↑）
		var th_rh := float(_thresholds_lookup["roughhouse_affinity"])
		var th_rc := int(_thresholds_lookup["roughhouse_count"])
		if _allowed("roughhouse") and _dims[i] >= th_rh \
				and _rng.random() < float(_probs["roughhouse_p"]):
			var others: Array = []
			for j in range(n):
				if j != i and not busy[j] and not _sleeping[j]:
					others.append(j)
			if not others.is_empty():
				var w_rh: Array = []
				for r in others:
					w_rh.append(maxf(1.0, _dims[r] - 30.0))
				var tgt: int = int(_rng.choices(others, w_rh, 1)[0])
				var bys: Array = []
				for k in range(n):
					if k != i and k != tgt and not busy[k]:
						bys.append(k)
				if bys.size() >= th_rc:
					# 旁观者聚焦「安静专注型」随机采样；结果弃用，仅对齐参考 RNG 流
					bys = _rng.sample(bys, mini(bys.size(), 4))
					# 打闹只吵到邻座（i、j 邻居并集，去重升序取前 3）
					var nb: Array = []
					for k in (_neighbor_idx[i] + _neighbor_idx[tgt]):
						if k != i and k != tgt and not _sleeping[k]:
							nb.append(k)
					var nb_set := {}
					for k in nb:
						nb_set[k] = true
					var nb_sorted: Array = nb_set.keys()
					nb_sorted.sort()
					_do_roughhouse(i, tgt, nb_sorted.slice(0, 3))
					busy[i] = true
					busy[tgt] = true
					continue
		# 阈值类：排挤（「大家都讨厌他」→ 集体驱逐；证据在施害者一侧）
		if _allowed("exclude") and _rng.random() < float(_probs["exclude_p"]):
			var th_n := int(_thresholds_lookup["exclude_count"])
			var cd_days := float(_thresholds_lookup["exclude_cooldown"])
			var window := float(_thresholds_lookup["exclude_window"])
			var done := false
			for j in range(n):
				if j == i or busy[j]:
					continue
				if _day - _exclude_last_day[j] < cd_days:
					continue
				var hurters: Array = []
				for k in range(n):
					if k != j and _day - _hurt_day[k * n + j] <= window:
						hurters.append(k)
				if hurters.size() >= th_n:
					_do_exclude(i, j, hurters.slice(0, 4))
					_exclude_last_day[j] = _day
					busy[i] = true
					done = true
					break
			if done:
				continue
		# 附加行为：流言（负面染色；目标偏好敌对高者）
		if _allowed("rumor") and _rng.random() < float(_probs["rumor_p"]):
			var c2: Array = []
			for j in range(n):
				if j != i and not busy[j] and not _sleeping[j]:
					c2.append(j)
			if not c2.is_empty():
				var w2: Array = []
				for m in c2:
					w2.append(maxf(1.0, 20.0 + _h[i * n + m] - _a[i * n + m] * 0.5))
				var tgt: int = int(_rng.choices(c2, w2, 1)[0])
				_do_rumor(i, tgt)
				busy[i] = true
				busy[tgt] = true
				continue
		# 意向类：搭话（softmax 采样）
		var cands: Array = []
		for j in range(n):
			if j != i and not _sleeping[j] and not busy[j]:
				cands.append(j)
		if not cands.is_empty():
			var alpha := _alpha(i)
			var scores: Array = []
			for c in cands:
				var gain_a := _b_a[i * n + c] / 100.0 * 3.0
				var gain_t := _b_t[i * n + c] / 100.0 * 2.0
				var risk_h := _b_h[i * n + c] / 100.0 * 2.0
				var u := float(alpha["affinity"]) * gain_a + float(alpha["trust"]) * gain_t - float(alpha["hostility"]) * risk_h
				u += _crowd_bias(i, "loud")
				u += _tag_bias(i, "chat_bias") - _tag_bias(i, "alone_bias")
				u += _join_gate_utility(i, c)
				scores.append(u)
			if not scores.is_empty():
				var k := _softmax(scores, _tau(i))
				var tgt: int = int(cands[k])
				_do_join_chat(i, tgt)
				busy[i] = true
				busy[tgt] = true


## 选交互目标：邻居优先（§10.15 相邻修正）。neighbors_only 时只在邻居里选。
func _pick_target(i: int, neighbors_only: bool = false) -> int:
	if neighbors_only:
		var others: Array = []
		for j in _neighbor_idx[i]:
			if not _sleeping[j]:
				others.append(j)
		if others.is_empty():
			return -1
		return int(_rng.choice(others))
	var w_nb := float(_probs["neighbor_pick_mult"])
	var pool: Array = []
	for j in range(_n):
		if j == i or _sleeping[j]:
			continue
		pool.append([j, w_nb if _neighbor_idx[i].has(j) else 1.0])
	if pool.is_empty():
		return -1
	var tot := 0.0
	for e in pool:
		tot += float(e[1])
	var r := _rng.random() * tot
	var acc := 0.0
	for e in pool:
		acc += float(e[1])
		if r <= acc:
			return int(e[0])
	return int(pool[pool.size() - 1][0])


## 按行为耗时把双方置为忙碌（收益越大耗时越长）。
func _occupy(i: int, j: int, behavior: String, quiet: bool = false) -> void:
	_current_act[i] = behavior
	_current_act[j] = null if quiet else behavior
	var dur := int(_behaviors.get(behavior, {}).get("duration", 0))
	if dur > 0:
		_busy_until[i] = _global_tick + dur
		_busy_until[j] = _global_tick + dur
		_busy_phase[i] = _phase_index
		_busy_phase[j] = _phase_index


## 闲聊：话题共鸣事件 + 双方观测。
func _do_chat(i: int, j: int) -> void:
	_in_conversation[i] = true
	_in_conversation[j] = true
	_occupy(i, j, "chat", true)
	_apply_event(i, j, "topic_affinity")
	_apply_event(i, j, "topic_trust")
	_apply_event(i, j, "topic_stress")
	_apply_event(j, i, "topic_affinity")
	_apply_event(j, i, "topic_trust")
	_observe(i, j, "affinity")
	_observe(j, i, "affinity")
	_stats["chats"] = int(_stats["chats"]) + 1
	_emit("event_happened", {"kind": "chat", "i": i, "j": j})


## 搭话判定侧：p 掷骰，无硬闸门；roll 可由调用方预掷（保证三拍展示一致）。
func _do_join_chat(i: int, j: int, roll: float = -1.0) -> void:
	_in_conversation[i] = true
	_in_conversation[j] = true
	_occupy(i, j, "join_chat", true)
	var p := _join_probability(i, j)
	if roll < 0.0:
		roll = _rng.random()
	if roll < p:
		_do_chat(i, j)
		_stats["joins"] = int(_stats["joins"]) + 1
		_stats["join_accepts"] = int(_stats.get("join_accepts", 0)) + 1
	else:
		_apply_event(i, j, "reject_affinity")
		_apply_event(i, j, "reject_hostility")
		_apply_event(i, j, "reject_stress")
		_observe(i, j, "affinity")
		_stats["joins"] = int(_stats["joins"]) + 1
		_stats["join_rejects"] = int(_stats.get("join_rejects", 0)) + 1
		_stats["skipped_events"] = int(_stats["skipped_events"]) + 1
	_emit("event_happened", {"kind": "join_chat", "i": i, "j": j, "accepted": roll < p})


## 举报（§10.2）：i = 举报者，j = 被举报者；效果落在被举报者身上。
func _do_report(i: int, j: int) -> void:
	_apply_event(j, i, "report_stress")
	_apply_event(j, i, "report_hostility")
	_mark_hurt(i, j)
	_h[i * _n + j] = _clamp100(_h[i * _n + j] - 5.0)
	_stats["reports"] = int(_stats["reports"]) + 1
	_emit("event_happened", {"kind": "report", "i": i, "j": j})


## 当众调侃（§10.12）：方向由绝对阈值判档；围观者按「他对被调侃者的态度」站队。
func _do_tease(i: int, j: int, audience: Array) -> void:
	_occupy(i, j, "tease")
	if _a[i * _n + j] >= float(_thresholds_lookup["tease_laugh_affinity"]) \
			and _h[i * _n + j] < float(_thresholds_lookup["tease_laugh_hostility"]):
		_apply_event(i, j, "tease_success_affinity")
		_apply_event(j, i, "tease_success_affinity")
		for k in audience:
			_apply_event(k, j, "tease_success_affinity")
		_apply_event(j, i, "tease_laugh_stress")
	elif _h[i * _n + j] >= float(_thresholds_lookup["tease_taunt_hostility"]) \
			or _a[i * _n + j] < float(_thresholds_lookup["tease_taunt_affinity"]):
		_apply_event(j, i, "tease_hostility")
		_apply_event(j, i, "tease_stress")
		for k in audience:
			if _a[k * _n + j] >= float(_thresholds_lookup["tease_stand_affinity"]):
				_apply_event(k, i, "tease_hostility")
			elif _h[k * _n + j] >= float(_thresholds_lookup["tease_sneer_hostility"]):
				_apply_event(k, j, "tease_affinity")
		if audience.size() >= int(_thresholds_lookup["humiliate_bystanders"]):
			_apply_event(j, i, "humiliate_hostility")
			_mark_hurt(i, j)
			_stats["humiliations"] = int(_stats.get("humiliations", 0)) + 1
		_stats["tease_fail"] = int(_stats["tease_fail"]) + 1
	_stats["teases"] = int(_stats["teases"]) + 1
	_emit("event_happened", {"kind": "tease", "i": i, "j": j})


## 排挤（B 类纯损害）：群体驱逐；被排挤者压力↑且对参与者好感↓（双向疏远）。
func _do_exclude(i: int, j: int, crowd: Array) -> void:
	_occupy(i, j, "exclude")
	_apply_event(j, i, "exclude_stress")
	_apply_event(j, i, "exclude_affinity")
	for k in crowd:
		if k != i:
			_apply_event(j, k, "exclude_affinity")
	_apply_event(i, j, "exclude_affinity")
	for k in crowd:
		if k != i:
			_apply_event(k, j, "exclude_affinity")
	_stats["excludes"] = int(_stats["excludes"]) + 1
	_emit("event_happened", {"kind": "exclude", "i": i, "j": j})


## 流言（§10.1）：i 传关于 j 的话；旁观者二手观测（带噪声）。
func _do_rumor(i: int, j: int) -> void:
	var negative := _h[i * _n + j] > _a[i * _n + j]
	_apply_event(j, i, "rumor_hostility")
	if negative:
		_apply_event(i, j, "rumor_stress")
		_apply_event(i, j, "tease_hostility")
	for k in range(_n):
		if k != i and k != j:
			_observe(k, j, "hostility")
	_stats["rumors"] = int(_stats["rumors"]) + 1
	_emit("event_happened", {"kind": "rumor", "i": i, "j": j})


## 追逐打闹（§10.18）：参与者互相好感↑、旁观者对参与者敌对↑（敌对种子）。
func _do_roughhouse(i: int, j: int, bystanders: Array) -> void:
	_occupy(i, j, "roughhouse")
	_apply_event(i, j, "roughhouse_affinity")
	_apply_event(j, i, "roughhouse_affinity")
	for k in bystanders:
		_apply_event(k, i, "roughhouse_hostility")
		_apply_event(k, j, "roughhouse_hostility")
	_stats["roughhouse"] = int(_stats["roughhouse"]) + 1
	_emit("event_happened", {"kind": "roughhouse", "i": i, "j": j})


# ------------------------------------------------------------------ 玩家行动（D11 缺口③）
## 玩家显式行动：来源固定玩家（n-1）、目标由玩家指定，走与 NPC 相同的 do_* 统一影响公式，
## 不做 NPC 自动决策。返回结果字典供表现层渲染反馈；topic 暂作透传记录。
func player_action(kind: String, target: int, topic: String = "") -> Dictionary:
	var me := _n - 1
	if target < 0 or target >= _n or target == me:
		return {"ok": false, "error": "invalid_target"}
	if _sleeping[me] or _global_tick < _busy_until[me]:
		return {"ok": false, "error": "player_busy"}
	var a_before := _a[target * _n + me]   # 目标→玩家的好感（行动前的反应基线）
	var h_before := _h[target * _n + me]
	var accepted := true
	match kind:
		"chat":
			_do_chat(me, target)
		"join_chat":
			var p := _join_probability(me, target)
			var roll := _rng.random()
			accepted = roll < p
			_do_join_chat(me, target, roll)
		"tease":
			_do_tease(me, target, _player_audience(target))
		"rumor":
			_do_rumor(me, target)
		"report":
			_do_report(me, target)
		"roughhouse":
			_do_roughhouse(me, target, _player_bystanders(target))
		"exclude":
			_do_exclude(me, target, _player_hurters(target))
		_:
			return {"ok": false, "error": "unknown_kind"}
	return {
		"ok": true,
		"kind": kind,
		"target": target,
		"topic": topic,
		"accepted": accepted,
		"affinity_delta": snapped(_a[target * _n + me] - a_before, 0.1),
		"hostility_delta": snapped(_h[target * _n + me] - h_before, 0.1),
	}


## 玩家调侃的围观者：玩家与目标的共同邻居（不含双方，未睡）。
func _player_audience(j: int) -> Array:
	var me := _n - 1
	var out: Array = []
	for k in _neighbor_idx[me]:
		if k != me and k != j and _neighbor_idx[j].has(k) and not _sleeping[k]:
			out.append(k)
	return out


## 玩家打闹的旁观者：玩家与目标的邻居并集（不含双方，未睡），升序取前 3。
func _player_bystanders(j: int) -> Array:
	var me := _n - 1
	var nb := {}
	for k in (_neighbor_idx[me] + _neighbor_idx[j]):
		if k != me and k != j and not _sleeping[k]:
			nb[k] = true
	var sorted: Array = nb.keys()
	sorted.sort()
	return sorted.slice(0, 3)


## 玩家排挤的群众：近期伤害过目标的 NPC（与 NPC 排挤判据一致），取前 4。
func _player_hurters(j: int) -> Array:
	var window := float(_thresholds_lookup["exclude_window"])
	var out: Array = []
	for k in range(_n):
		if k != j and _day - _hurt_day[k * _n + j] <= window:
			out.append(k)
	return out.slice(0, 4)


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


## 某人此刻在做什么（UI 用；空闲/学习 = 空串）。
func activity_of(i: int) -> String:
	if i < 0 or i >= _n or _current_act[i] == null:
		return ""
	return _current_act[i]


# ------------------------------------------------- 表现层只读：角色身份 + 座位
## i 的别名（名字牌用）；玩家自身没有别名 → 空串。
func alias(i: int) -> String:
	if i < 0 or i >= _chars.size():
		return ""
	return str(_chars[i].get("alias", ""))


## i 在种子表里的编号（"01"…"24"）；玩家自身 → 空串。
## 表现层用它查 data/characters/appearance.csv（外观绑定在 data/，不在脚本里判断角色名）。
func character_id(i: int) -> String:
	if i < 0 or i >= _chars.size():
		return ""
	return str(_chars[i].get("id", ""))


## i 坐的座位号（seats.csv 的 seat_id，如 "P7"）；越界 → 空串。
## ⚠️ 座位由 _assign_seats() 消费内核 RNG 随机分配，表现层必须读这里、不得自行随机，
##    否则画面上「谁挨着谁」会与内核判定用的邻接关系不一致（§15.1 空间聚散）。
func seat_of(i: int) -> String:
	if i < 0 or i >= _seat_of.size():
		return ""
	return str(_seat_of[i])


## i 是不是玩家自身（玩家恒为最后一个节点，§4.1）。
func is_player(i: int) -> bool:
	return i == _n - 1


## 观察层（只读）：当前「活动圈」—— 按「此刻在做同一件事」分组（§15.1，≥2 人才成圈）。
func get_activity_circles() -> Dictionary:
	var groups := {}
	for i in range(_n):
		var a = _current_act[i]
		if a == null:
			continue
		if not groups.has(a):
			groups[a] = []
		groups[a].append(i)
	var out := {}
	for a in groups:
		if groups[a].size() >= 2:
			var v: Array = groups[a]
			v.sort()
			out[a] = v
	return out


## 观察层（只读）：viewer 眼中的小团体簇（§11.1，A≥60 强连接连通分量）。
func get_clusters(viewer: int = -1) -> Array:
	return _ObserverLayer.new(self).cluster_tags(viewer)


## 观察层（只读）：viewer 眼中的「被孤立者」（§10.26.3）。
func get_isolated(viewer: int = -1) -> Array:
	return _ObserverLayer.new(self).isolated_tags(viewer)


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
