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
## 玩家可通过 player_action 发起的行为（与 data/rules/behaviors.csv 的行名一致）
## 观察的固定时长（tick）：对象空闲或做「持续型」活动时用这一档（§10.3.1）
const OBSERVE_TICKS := 10
## 超过这个剩余量就视为「持续型 / 整段占用」（学习、睡觉），不跟随其剩余时间
const OBSERVE_FOLLOW_LIMIT := 120
const PLAYER_KINDS := ["chat", "tease", "report", "roughhouse", "exclude", "pass_note", "observe"]
const _NEVER := -999  # 时间哨兵：「从未发生」（Python 参考用 -10**9 / -999；语义等价，统一 -999）
const _FOREVER := 1000000000  # 时间哨兵：「忙碌到远超本段」（睡觉等整段占用的 busy_until，对齐 Python 10**9）
const OBSERVER_LAYER = preload("res://scripts/systems/observer/observer_layer.gd")
const BEHAVIOR_CONTEXT = preload("res://scripts/systems/behaviors/behavior_context.gd")
const BEHAVIOR_REGISTRY = preload("res://scripts/systems/behaviors/behavior_registry.gd")
const ACTIVITY_SESSIONS = preload("res://scripts/core/activity_sessions.gd")
const INTERACTION_SPACE = preload("res://scripts/core/interaction_space.gd")
const PLAYER_CHAT_INTEL = preload("res://scripts/core/player_chat_intel.gd")
const PLAYER_INTERACTIONS = preload("res://scripts/core/player_interactions.gd")
const PLAYER_INVITATIONS = preload("res://scripts/core/player_invitations.gd")
const PLAYER_INTERACTION_TABLE := "rules/player_interaction"

var _behavior_context: RefCounted
var _behavior_registry: RefCounted
## 真实共同活动（谁和谁此刻真在一起）、交互几何、玩家交互服务与线索日志
var _sessions: ActivitySessions
var _space: InteractionSpace
## 场景注入的本座位入口世界坐标；与座位表的行列分开，不引用节点。
var _seat_world_positions: Dictionary = {}
var _scene_space_required := false
var _intel: PlayerChatIntel
var _player_interactions: PlayerInteractions
var _player_invitations: RefCounted

# —— 关系 / 个体状态（float64 平铺，与 Python 逐位一致）——
var _a := PackedFloat64Array()  # 好感 A  n*n
var _h := PackedFloat64Array()  # 敌对 H  n*n
var _h_deep := PackedFloat64Array()  # 深层敌对 n*n（§10.22，永不衰减）
var _t := PackedFloat64Array()  # 信任 T  n*n
var _o := PackedFloat64Array()  # 透明度 O  n
var _stress := PackedFloat64Array()  # 压力 Stress  n
var _grade := PackedFloat64Array()  # 成绩 grade  n（§17.1）
var _study_acc := PackedFloat64Array()  # 学习时长累加器 study_acc  n（§17.1.2）
var _dims := PackedFloat64Array()  # MBTI 四维（dim-major）DIMS.size()*n
var _b_a := PackedFloat64Array()  # 信念·好感 n*n
var _b_h := PackedFloat64Array()  # 信念·敌对 n*n
var _b_t := PackedFloat64Array()  # 信念·信任 n*n

var _rng: MtRandom
var _seed := 0
var _n := 0
var _day := 1
var _phase := "break"
var _tick_in_phase := 0
var _phase_index := 0
var _global_tick := 0
var _volume := 0.0
var _active_phases: Array = []  # 非 settle 段（课间/上课）顺序，供单步推进（D11）
var _phase_setup_done := false  # 当前段是否已跑段首一次性结算（D11）
var _settled_boundary := Vector2i(-1, -1)  # 已结算的相位边界幂等键（天, 旧相位）
var _interrupted_nodes: Array = []  # 本段边界被打断的节点（供 _cleanup_phase 清理）

## 事件出口（D11 缺口④）：表现层把此回调绑到 EventBus 四信号，内核零 autoload 依赖。
## 收到 {"type": String, "payload": Dictionary}；
## type ∈ event_happened / day_settled / tag_changed / stress_burst。
var event_sink: Callable = Callable()  # gdlint:ignore = class-definitions-order

# —— 配置 ——
var _p: Dictionary = {}  # transmission 参数（含 settle_interval）
var _bp: Dictionary = {}  # belief 参数（先验 / 学习率 / 偏差）
var _kp: Dictionary = {}  # kernel 硬编码系数（kernel_params.csv）
var _grade_bands: Array = []  # 成绩分段表（[band_upper, ticks_per_point]，按上界升序）
var _probs: Dictionary = {}  # behavior_probs：行为 -> 基础概率
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
var _neighbor_idx: Array = []  # 角色 → 邻居角色索引（对称，对应 Python assign_seats 的 neighbor_idx）
var _feedback := 0.0  # 负反馈强度（transmission.csv 的 feedback）

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
## 占用中的行为名（含 quiet 一方：_current_act 会清成 null，「被动参与」也要记得住）
var _busy_act: Array = []
## 本 tick **刚完成**的行为（到期收尾时写入），给「行为完成才发信息」做挂点（如玩家闲聊线索）
var _last_finished: Array = []
## 空间层：节点在教室里的真实平面位置（米，世界坐标；由表现层 / 内核空间层写入）
var _pos_x: Array = []
var _pos_z: Array = []
var _knot_days: Array = []
var _vol_log: Array = []
var _day_events: Dictionary = {}
var _settled: Dictionary = {}
var _stats: Dictionary = {}
var _hurt_day: Array = []  # 施害者侧证据：最近一次 i 对 j 做重大敌对行为的日（§8.4）
var _exclude_last_day: Array = []  # 排挤冷却：同一目标最近被驱逐的日（§10.25）
var _witness_day: Array = []
var _notes: Array = []  # 活跃纸条（§8.6 纸条链）
var _note_next_id := 0
var _choice: Dictionary = {}  # 选择侧系数表（§4.5）  # 举报把柄：i 最近目击 j 违规的日（§10.2）


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

	# 抽角色（简化：随机取 npc_count 个；对齐 main 的 core_sim.py，消费随机数）
	# ⚠️ 必须 .duplicate()：_rows 返回共享缓存引用，shuffle 原地改写会污染跨实例共享的 tables。
	var pool: Array = _rows(tables, "characters/seeds").duplicate()
	_rng.shuffle(pool)
	_chars = pool.slice(0, npc_count)

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
	_init_grade()
	_init_belief_bias()

	_volume = float(_env.get("init_volume", 0.0))

	_character_tags = _build_character_tags()

	# 时间 / 统计 / 每节点运行态（须在空间层之前，避免清掉 _seat_of）
	_reset_runtime(n)

	# 空间层（座位 + 邻接索引；须在 _reset_runtime 之后，_seat_of 才不会被清空）
	_neighbors = _build_neighbors()
	_assign_seats()
	_build_neighbor_idx()
	_behavior_context = BEHAVIOR_CONTEXT.new(self)
	_behavior_registry = BEHAVIOR_REGISTRY.new(_behavior_context)

	# 真实共同活动 + 交互几何 + 玩家交互服务 + 线索日志（构造不消费随机数）
	_sessions = ACTIVITY_SESSIONS.new()
	_space = INTERACTION_SPACE.new()
	_intel = PLAYER_CHAT_INTEL.new(_seed)
	_player_interactions = PLAYER_INTERACTIONS.new(self, _space, _sessions, _intel)
	var pi_params := _params(tables, PLAYER_INTERACTION_TABLE)
	_player_interactions.configure(pi_params)
	_intel.configure(pi_params)
	_player_invitations = PLAYER_INVITATIONS.new(self, tables, pi_params)


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
	_grade_bands = _build_grade_bands(tables)
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
	_choice = _build_choice_weights(tables)


func _alloc(n: int) -> void:
	_a.resize(n * n)
	_h.resize(n * n)
	_h_deep.resize(n * n)
	_t.resize(n * n)
	_o.resize(n)
	_stress.resize(n)
	_grade.resize(n)
	_study_acc.resize(n)
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
	_settled_boundary = Vector2i(-1, -1)
	_interrupted_nodes = []
	_stats = {
		"events": 0,
		"chats": 0,
		"joins": 0,
		"reports": 0,
		"bursts": 0,
		"interrupts": 0,
		"transmission_ticks": 0,
		"skipped_events": 0,
		"dedup_skips": 0,
		"teases": 0,
		"tease_fail": 0,
		"excludes": 0,
		"roughhouse": 0,
		"sleeps": 0,
		"deep_writes": 0,
		"noise_grudges": 0,
		"free_joins": 0,
		"join_accepts": 0,
		"join_rejects": 0,
		"humiliations": 0,
		"comforts": 0,
		"apologizes": 0,
		"apologize_rejects": 0,
		"notes_written": 0,
		"notes_read": 0,
		"notes_destroyed": 0,
	}
	_notes.clear()
	_note_next_id = 0
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
		# --- 空间层：节点在教室里的真实平面位置（米，世界坐标；由表现层 / 内核空间层写入）---
		# 依据：主文档 §10.5 / §15.1；策划 2026-10-07 裁决第 4 项「加临时位置与交互范围」。
		# ⚠️ 本层**只记录**：内核不自己算移动，也不因位置改变任何矩阵 —— 位置只用于范围判定与展示。
		_pos_x.append(0.0)
		_pos_z.append(0.0)
		_busy_until.append(0)
		_busy_phase.append(-1)
		_busy_act.append(null)
		_last_finished.append(null)
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


## 成绩初始化（§17.1.1）：NPC 种子化均匀 [min,max)，玩家固定。消费 len(chars) 次 RNG。
## ⚠️ 必须紧跟 _init_relations() 之后调用，与 Python 同一点插入，保同种子 RNG 流不漂移。
func _init_grade() -> void:
	var gmin := float(_kp["grade_init_npc_min"])
	var gmax := float(_kp["grade_init_npc_max"])
	for i in range(_chars.size()):
		_grade[i] = gmin + _rng.random() * (gmax - gmin)
	_grade[_n - 1] = float(_kp["grade_init_player"])


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
## 统一边界协议 ②③④⑤：结束旧段（不推进 tick）。
## 顺序固定：到期结算 → 睡眠收尾 → 中断 → 清理 →（日末）跨天结算。
## 幂等键 = (天, 旧相位)：finish_time_boundary / advance_tick 重复进入同一边界只结算一次。
func _end_phase() -> void:
	var key := Vector2i(_day, _phase_index)
	if _settled_boundary == key:
		return
	_settled_boundary = key
	_settle_finished_actions()
	_settle_sleep()
	_check_interrupt()
	_cleanup_phase()
	if _phase_index + 1 >= _active_phases.size():
		_settle_day()


## 统一边界协议 ⑥⑦：进入当前段（_phase_index 已指向本段）并执行新段判定。
## 核心 RNG 消费序：roll_sleep → free_join → [break: phone_exposure → roll_reports]。
func _begin_phase() -> void:
	var row: Dictionary = _active_phases[_phase_index]
	_phase = str(row["kind"])
	_tick_in_phase = 0
	_roll_sleep()
	_free_join()
	if _phase == "break":
		_phone_exposure()
		_roll_reports()
	_phase_setup_done = true


## 推进一个 tick（D11 单步粒度）。段未开始则先跑段首结算。
## 跨段/跨天的游标推进推迟到「下一 tick 开始前」（见 _transition_if_needed），
## 使段末/日末采样到的 snapshot 仍属上一段/上一天 —— 与 Python tick() 的观测一致。
func advance_tick() -> int:
	_transition_if_needed()
	if not _phase_setup_done:
		_begin_phase()
	_tick()
	_tick_in_phase += 1
	var row: Dictionary = _active_phases[_phase_index]
	if _tick_in_phase >= int(str(row["tick_count"])):
		_vol_log.append(_r1(_volume))
	return _global_tick


## 上一段跑完后，结束旧段并把游标推进到下一段（跨天结算由 _end_phase 负责）。
func _transition_if_needed() -> void:
	if not _phase_setup_done:
		return
	var row: Dictionary = _active_phases[_phase_index]
	if _tick_in_phase < int(str(row["tick_count"])):
		return
	_end_phase()  # ②③④⑤（末段触发 _settle_day）
	_phase_index = (_phase_index + 1) % _active_phases.size()
	_phase_setup_done = false


## 推进一个段（从当前位置跑到当前段末尾），返回本段跑的 tick 数。
func advance_phase() -> int:
	_transition_if_needed()
	if _phase_index >= _active_phases.size():
		return 0
	if not _phase_setup_done:
		_begin_phase()
	var ran := 0
	var target := int(str(_active_phases[_phase_index]["tick_count"]))
	while _tick_in_phase < target:
		advance_tick()
		ran += 1
	# 段跑完 → 显式推进到下一段（D11 语义：advance_phase 返回后 phase_index 指向下一段）
	_transition_if_needed()
	return ran


## 推进一天（从当前位置跑到当天结束并跨天结算），返回当天跑的 tick 数。
func advance_day() -> int:
	var total := 0
	_transition_if_needed()
	if _phase_index >= _active_phases.size():
		_phase_index = 0
		_phase_setup_done = false
	var phases_left := _active_phases.size() - _phase_index
	for _i in range(phases_left):
		total += advance_phase()
	return total


## 时间快照（只读）：表现层据此显示与判定，不得自行推算相位 / tick。
## 字段固定（时间组件计划 §4）：day / phase_id / kind / phase_index / tick_in_phase /
## tick_count / global_tick / player_control。`kind` 只区分课间与上课，
## 上午 / 下午必须看 `phase_id`。
func time_snapshot() -> Dictionary:
	var row: Dictionary = _active_phases[_phase_index]
	return {
		"day": _day,
		"phase_id": str(row["phase_id"]),
		"kind": str(row["kind"]),
		"phase_index": _phase_index,
		"tick_in_phase": _tick_in_phase,
		"tick_count": int(str(row["tick_count"])),
		"global_tick": _global_tick,
		"player_control": int(str(row.get("player_control", "0"))) == 1,
	}


## 显式完成当前阶段的时间边界（时间组件计划 §4）：只在当前段 tick 已耗尽时有效，
## 完成与 _transition_if_needed() 相同的边界动作（含跨天结算），**不推进任何 tick**。
## 返回 {changed, ended_day, day_settled, snapshot}；tick 未耗尽时 changed = false，
## 重复调用不重复结算、不重复发事件。
func finish_time_boundary() -> Dictionary:
	var day_before := _day
	var index_before := _phase_index
	_transition_if_needed()
	if _phase_index != index_before or _day != day_before:
		# 边界完成后新相位还没跑过 tick：显式归零。
		# 否则快照会出现「phase_id 已是下一段、tick_in_phase 却还是上一段的满值」这种
		# 自相矛盾的状态，实时驱动会据此误判「剩余 0 秒」并立刻重复触发边界、跳掉一整段。
		# 段首设置仍留给下一次 advance_tick；「结束旧活动」已由 _transition_if_needed →
		# _end_phase（含 _check_interrupt + _cleanup_phase）在发布归位信号前完成。
		_tick_in_phase = 0
	var day_settled := _day != day_before
	return {
		"changed": _phase_index != index_before or day_settled,
		"ended_day": day_before if day_settled else 0,
		"day_settled": day_settled,
		"snapshot": time_snapshot(),
	}


## 跑完一天（三段课间 + 两段上课），返回总 tick 数。等价 advance_day()。
func run_day() -> int:
	return advance_day()


## 行为完成结算：把**已到期**的占用收尾（§10.4 / §12.2 行为耗时契约）。
## 占用到期即「这件事做完了」：清 _current_act、清 _busy_phase，并把行为名写进
## _last_finished（仅本 tick 有效）。**「行为完成才发信息」的规则必须挂在这里**
## （例如玩家的闲聊线索），不能挂在「发起」上 —— 发起不等于做完。
## ⚠️ 与「被铃声打断」严格互斥：到期的不算被打断；未到期的才可能被 _check_interrupt()
## 在相位切换时处理。两边都不重复记。
##
## 顺序（计划 §5.3）：① 认定到期 → ② 读取这一刻情报并写入本局日志 → ③ 清理活动／占用
## → ④ 发布线索与完成通知（下一步才继续本 tick 的 NPC 决策）。
func _settle_finished_actions() -> void:
	_player_invitations.expire()
	_last_finished = []
	for i in range(_n):
		_last_finished.append(null)
	# ① 认定到期：真实共同活动（同一结束点只结一次 —— 无双发线索、无双结算）
	var due_sessions: Array = _sessions.expire(_global_tick)
	# ② 读取这一刻情报 + 写入本局日志（只有玩家参与的自然完成才登记线索）
	var notifications: Array = _player_interactions.on_sessions_completed(due_sessions)
	# ③ 清理占用/当前动作
	for i in range(_n):
		if _busy_phase[i] < 0 or _busy_until[i] > _global_tick:
			continue
		_last_finished[i] = _busy_act[i]
		_current_act[i] = null
		_busy_act[i] = null
		_busy_phase[i] = -1
	# 加入路径（原 join_chat）的占用不建立会话，靠占用到期收尾（群聊拒绝不再占用请求者）
	notifications.append_array(_player_interactions.on_occupancy_completed(_global_tick))
	# 玩家不再处于任何会话、也不再被占用时，清掉「正在对话」标记
	# （NPC 的标记由 _decide_and_act 每回合自清；玩家没有决策回合，必须在这里清）
	var me := _n - 1
	if _in_conversation[me] and _sessions.session_of(me) < 0 and _global_tick >= _busy_until[me]:
		_in_conversation[me] = false
	# ④ 发布通知：完成在前，线索在后
	for payload in notifications:
		_emit("event_happened", payload)


func _tick() -> void:
	_global_tick += 1
	_settle_finished_actions()
	_decide_and_act()
	_process_notes()  # 纸条链（§8.6）：每 tick 处理一张纸条
	_study_accumulate()
	_update_environment()
	if _global_tick % int(_p["settle_interval"]) == 0:
		_transmission()
		_stress_drip()


## 成绩涓流（§17.1.2）：每 tick 处于「学习状态」（默认空闲 = 无行为且不忙碌）时累积 study_acc，
## 满档 +1 分。上课段不累积；跨天保留（_settle_day 不清 study_acc）。不消耗 RNG。
func _study_accumulate() -> void:
	if _phase != "break":
		return
	var gmax := float(_kp["grade_max"])
	for i in range(_n):
		if _grade[i] >= gmax:
			_study_acc[i] = 0.0
			continue
		if _current_act[i] != null or _global_tick < _busy_until[i]:
			continue
		_study_acc[i] += 1.0
		var tpp := _grade_ticks_per_point(_grade[i])
		if tpp <= 0.0:
			continue
		if _study_acc[i] >= tpp:
			_grade[i] += 1.0
			_study_acc[i] -= tpp


## 当前成绩档的「每 +1 分所需 tick」（§17.1.2 分段表）；越界返回 0。
func _grade_ticks_per_point(g: float) -> float:
	for band in _grade_bands:
		if g < float(band[0]):
			return float(band[1])
	return 0.0


# -------------------------------------------------- 事件出口（D11 缺口④：内核 → 表现层，零 autoload 依赖）
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
			_knot_days[i] = maxi(_knot_days[i], _rint(float(tag["days"]) * (1.0 + severity)))
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
	others.sort_custom(
		func(a, b):
			var ka := -absf(_a[i * _n + a] - _h[i * _n + a])
			var kb := -absf(_a[i * _n + b] - _h[i * _n + b])
			if ka != kb:
				return ka < kb
			return a < b
	)
	var pool_size := maxi(1, int(float(others.size()) * ratio))
	var pool: Array = others.slice(0, pool_size)
	var kmax_eff := _rint(float(kmax) * (1.0 + severity))
	var days_eff := _rint(float(tag["days"]) * (1.0 + severity))
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


# -------------------------------------------------- 统一影响公式（UIF，docs/design/统一影响公式.md）
## 精确复刻 Python 3.13+ round(v, ndigits)：round-half-even 的正确舍入。
## 单纯 snapped()（half-away）或 roundi() 会在值恰好落在二进制可精确表示的 .x5 中点
## （如 1.25/1.75）时差 0.1，导致 16 人场景 tick 11 起 A 矩阵分叉。这里用 Dekker TwoProduct
## 求 v*scale 的精确误差，区分「恰在中点（tie→half-even）」与「浮点略偏（round-to-nearest）」。
func _r1(v: float) -> float:
	return _round_scaled(v, 10.0)


func _r2(v: float) -> float:
	return _round_scaled(v, 100.0)


## round-half-even 到整数（对齐 Python int(round(v))）；无缩放，故 frac==0.5 即精确中点。
func _rint(v: float) -> int:
	var flr: float = floor(v)
	var frac: float = v - flr
	if frac > 0.5:
		return int(flr + 1.0)
	if frac < 0.5:
		return int(flr)
	if fmod(flr, 2.0) == 0.0:
		return int(flr)
	return int(flr + 1.0)


func _round_scaled(v: float, scale: float) -> float:
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


## v*b 的精确浮点误差（v*b == p + err 精确成立）。Dekker 拆半（2^27+1，双精度适用）。
func _mul_err(v: float, b: float, p: float) -> float:
	var c := 134217729.0  # 2^27 + 1
	var tv := c * v
	var v_hi := tv - (tv - v)
	var v_lo := v - v_hi
	var tb := c * b
	var b_hi := tb - (tb - b)
	var b_lo := b - b_hi
	return ((v_hi * b_hi - p) + v_hi * b_lo + v_lo * b_hi) + v_lo * b_lo


## 性格倍率：M_personality = clamp(1 + Σ w_k·d_k, 0.1, 1.2)。
func _mult_personality(row: Dictionary, i: int) -> float:
	var neutral := float(_kp["mbti_neutral"])
	var scale := float(_kp["mbti_scale"])
	var w := [
		float(str(row["w_e"])),
		float(str(row["w_s"])),
		float(str(row["w_f"])),
		float(str(row["w_j"])),
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
	var u_cap := float(_p.get(key, 25.0))
	return u / (1.0 + absf(u) / u_cap)


## 统一影响公式落表：Δ = M_state · sat(P)；P = base·scale·M_personality(·M_relation)。
func _apply_event(
	i: int, j: int, event_id: String, scale: float = 1.0, no_modulation: bool = false
) -> bool:
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
		if is_axis and str(row.get("tier", "normal")) != "major" and not no_modulation:
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


## 举报旧回落的精确兼容点：仅封装原写入，后续规则迁移单独处理。
func _reduce_reporter_hostility(actor: int, target: int) -> void:
	_h[actor * _n + target] = _clamp100(_h[actor * _n + target] - 5.0)


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
			d_a[i * n + k] = _r1(
				_room_for("affinity", _a[i * n + k]) * _sat(beta_a * net_a, "affinity")
			)
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
				_apply_event(
					i, j, "conformity_hostility", conf * float(haters.size()) / float(maxi(1, need))
				)


func _deviance_pressure() -> void:
	var k := float(_env.get("deviance_k", 0.0))
	if k <= 0.0:
		return
	var v := _volume / 100.0
	var loud := ["chat", "tease", "roughhouse"]
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


## 铃声打断（统一边界协议 ③）：只断**未到期**的占用。
## 到期结算由 ① _settle_finished_actions 负责（完成时刻恰好等于铃声 → 不误算中断、不漏线索）。
## ⚠️ 判据是「是否仍在进行」（`_busy_until > _global_tick`）；边界协议里本方法先于
##    switch_phase 执行，此刻 _phase_index 仍指向旧段，因此不能再按「跨段」判据。
func _check_interrupt() -> void:
	# ③ 未到期的占用 → 中断（施加打断代价，与完成严格互斥）
	var cost := float(_probs.get("interrupted_stress", 0.0))
	_interrupted_nodes = []
	for i in range(_n):
		if _busy_phase[i] < 0:
			continue
		if _busy_until[i] > _global_tick:
			_busy_until[i] = 0
			_busy_phase[i] = -1
			if cost > 0.0:
				_stress[i] = _clamp100(_stress[i] + cost)
			_stats["interrupts"] = int(_stats["interrupts"]) + 1
			_interrupted_nodes.append(i)


## 统一边界协议 ④：清理被打断动作的残余状态（占用 / 会话 / 移动锁）。
## 不消耗 RNG；抽象内核（无移动输入）下移动锁清理为 no-op。
func _cleanup_phase() -> void:
	for i in _interrupted_nodes:
		_current_act[i] = null
		_busy_act[i] = null
		_in_conversation[i] = false
	# 纸条链（§8.6）：纸条只在当前时间段内存活，进入下一个时间段即销毁。
	_notes.clear()
	# 有成员被打断的共同活动整场中断（不留半场会话、不残留融合圈）
	var unfinished: Array = []
	if not _interrupted_nodes.is_empty():
		for snap in _sessions.active_snapshots():
			for m in snap["members"]:
				if _interrupted_nodes.has(int(m)):
					unfinished.append(snap)
					_sessions.end(int(snap["session_id"]))
					break
	# 发布中断通知（未揭晓的结果不再发完成类信息）
	for payload in _player_interactions.on_interrupted(unfinished, _interrupted_nodes):
		_emit("event_happened", payload)
	# 跨段不再保留「正在走过去」的移动锁（铃声响起，各自归位）
	for i in range(_n):
		if is_moving(i):
			set_moving(i, false)


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
		bias = (
			float(_bp["w_bias"])
			* _friendly_bias(j, float(_kp["mbti_neutral"]), float(_kp["mbti_scale"]), 0.5, 0.5)
		)
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
		"affinity":
		(
			float(_nw["alpha_a_base"])
			+ float(_nw["alpha_a_f"]) * _dims[2 * _n + i] / 100.0
			+ float(_nw["alpha_a_e"]) * _dims[i] / 100.0
		),
		"trust": float(_nw["alpha_t_base"]) + float(_nw["alpha_t_j"]) * (1.0 + _arg_j(i)) / 2.0,
		"hostility":
		(
			float(_nw["alpha_h_base"])
			+ float(_nw["alpha_h_f"]) * (1.0 - _dims[2 * _n + i] / 100.0)
			+ float(_nw["alpha_h_j"]) * (1.0 + _arg_j(i)) / 2.0
		),
		"stress": float(_nw["alpha_s_base"]) + float(_nw["alpha_s_e"]) * (1.0 - _dims[i] / 100.0),
	}
	var total := (
		float(raw["affinity"])
		+ float(raw["trust"])
		+ float(raw["hostility"])
		+ float(raw["stress"])
	)
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


## 加入闲聊决策侧软门槛：低于门槛只降概率、不排除候选（§6.4）。
func _join_gate_utility(i: int, j: int) -> float:
	var ga := float(_thresholds_lookup["chat_join_gate_affinity"])
	var gs := float(_thresholds_lookup["chat_join_gate_stress"])
	var scale := float(_thresholds_lookup["chat_join_gate_scale"])
	var w := float(_thresholds_lookup["chat_join_gate_weight"])
	var za := (_a[i * _n + j] - ga) / scale
	var zs := (gs - _stress[i]) / scale
	return w * (_sigmoid(za) + _sigmoid(zs) - 1.0)


## 加入闲聊判定侧 score：**被请求者的真值好感 A[j][i]** + 对方外向度 − 对方压力惩罚（§6.4）。
## 判定读真值 ——「他会不会接纳我」由他的真实态度决定，不由我的猜测决定；我的猜测只进
## 决策侧（要不要去试）与展示层（成功率）。读 A[j][i] 不违反 §18.7 不变式 3 ——
## 该不变式禁止的是**决策路径**读它；本方法属**判定路径**，规格要求它读真值。
func _join_score(i: int, j: int) -> float:
	var base := _a[j * _n + i] + (_dims[j] - 50.0) * 0.3
	var hot := maxf(0.0, _stress[j] - 50.0) / 50.0
	var penalty := float(_thresholds_lookup["chat_join_stress_penalty"])
	return base - penalty * hot


## 加入闲聊判定侧概率：p = σ((score − θ)/scale)，永不为 0/1（§6.4）。
func _join_probability(i: int, j: int) -> float:
	var theta := float(_thresholds_lookup["chat_join_affinity"])
	var scale := float(_thresholds_lookup["chat_join_scale"])
	return _sigmoid((_join_score(i, j) - theta) / scale)


## 只读：玩家侧看到的成功率 p（从信念 B_A 算，不泄露真值；§10.32.3）。
## 显示值与实际结算值（_join_probability 读真值）刻意不同 ——「我明明有 80% 把握却被拒」
## 正是认知偏差的具象化，不是 bug（§10.32.4）。
func _join_feedback(i: int, j: int) -> Dictionary:
	var hot := maxf(0.0, _stress[j] - 50.0) / 50.0
	var score := (
		_b_a[i * _n + j]
		+ (_dims[j] - 50.0) * 0.3
		- float(_thresholds_lookup["chat_join_stress_penalty"]) * hot
	)
	var theta := float(_thresholds_lookup["chat_join_affinity"])
	var scale := float(_thresholds_lookup["chat_join_scale"])
	return {"p": _r2(_sigmoid((score - theta) / scale))}


## 一次判定的展示包（只读，不参与结算；实际掷骰在 _do_chat_join 里做，D11 玩家侧用）。
func _verdict(i: int, j: int, kind: String = "join") -> Dictionary:
	if kind == "join":
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
	# 玩家由人的主动选择驱动，不参加 NPC 的睡觉决策。
	for i in range(_n - 1):
		if _sleeping[i] or is_moving(i):
			continue
		if _rng.random() < p * (1.0 + _tag_bias(i, "alone_bias")):
			_sleeping[i] = true
			_current_act[i] = "sleep"
			_busy_until[i] = _FOREVER
			_stats["sleeps"] = int(_stats["sleeps"]) + 1


## 「别人做什么我也跟着做」：join_mode=free 的活动可自由跟随（§10.31），强度由从众度决定。
func _free_join() -> void:
	# 自动跟随同样属于 NPC 决策，不能覆盖玩家选择。
	for i in range(_n - 1):
		if _sleeping[i] or _busy_until[i] > _global_tick or is_moving(i):
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
			var z := (
				(_h[i * _n + j] - th_rep) / sc_rep
				- w_a * _a[i * _n + j] / 100.0
				- w_t * _t[i * _n + j] / 100.0
			)
			if _rng.random() < p_rep * _sigmoid(z):
				_do_report(i, j)
				break


## 一 tick 内的行为决策：闲聊 → 调侃 → 打闹 → 排挤 → 搭话。
## 铁律：决策顺序按索引升序（可复现，取代 Python 的 shuffle）；只读信念 B_*，不读真值 A[j][i]。
func _decide_and_act() -> void:
	var n := _n
	var busy: Array = []
	for _k in range(n):
		busy.append(false)
	# 玩家（末位节点，§4.1）由人的主动选择驱动，**不参与 NPC 自主决策**（§12.1）；
	# 但它仍是被交互对象 —— 下方候选集合与 _pick_target 都不排除末位。
	var order: Array = []
	for _k in range(n - 1):
		order.append(_k)
	_rng.shuffle(order)
	for i in order:
		if _sleeping[i] or busy[i] or _global_tick < _busy_until[i] or is_moving(i):
			continue
		if _player_invitations.is_waiting(i):
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
		# 环境类：传纸条（§8.6 纸条链）—— 写一张纸条，投给相邻或走近的人
		# 纸条本身不做判定；接收者的「看不看 / 销毁 / 继传」由 _process_notes() 走 §4.5 选择侧公式
		if _allowed("pass_note") and _rng.random() < float(_probs["pass_note"]):
			var pn_target := _pick_target(i)
			if pn_target >= 0:
				_do_pass_note(i, pn_target)
				busy[i] = true
				busy[pn_target] = true
				continue
		# 意向类：当众调侃（需物理接近 + ≥3 人围观；目标偏好敌对高 / 好感低者）
		var cands_t: Array = []
		for j in range(n):
			if (
				j != i
				and not busy[j]
				and _can_interact_with(j)
				and _are_neighbors(i, j)
				and (_a[i * n + j] >= 40.0 or _b_h[i * n + j] >= 25.0 or _a[i * n + j] < 25.0)
			):
				cands_t.append(j)
		if (
			_allowed("tease")
			and cands_t.size() >= 3
			and _rng.random() < float(_probs["tease_p"]) * (1.0 + _tag_bias(i, "tease_bias"))
		):
			var wts: Array = []
			for t in cands_t:
				wts.append(maxf(1.0, pow((100.0 - _a[i * n + t]) + _h[i * n + t], 2.0)))
			var tgt: int = int(_rng.choices(cands_t, wts, 1)[0])
			var audience: Array = []
			for k in _neighbor_idx[i]:
				if (
					_neighbor_idx[tgt].has(k)
					and k != i
					and k != tgt
					and not busy[k]
					and not _sleeping[k]
				):
					audience.append(k)
			if audience.size() >= 3:
				_do_tease(i, tgt, audience)
				busy[i] = true
				busy[tgt] = true
				continue
		# 意向类：追逐打闹（敌对种子：参与者好感↑ / 旁观者敌对↑）
		var th_rh := float(_thresholds_lookup["roughhouse_affinity"])
		var th_rc := int(_thresholds_lookup["roughhouse_count"])
		if (
			_allowed("roughhouse")
			and _dims[i] >= th_rh
			and _rng.random() < float(_probs["roughhouse_p"])
		):
			var others: Array = []
			for j in range(n):
				if j != i and not busy[j] and _can_interact_with(j):
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
					for k in _neighbor_idx[i] + _neighbor_idx[tgt]:
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
		# ---------- 意向类：三条「主动接近他人」的行为（§10.10 / §10.11 / §10.13）----------
		# 三者都必须排在下面无门槛的加入回退块之前，否则会被它永远抢先。
		# 门槛一律读「我自己的立场」（A[i][j] / H[i][j] / Stress[j]）与信念 B，
		# 不读 A[j][i] / H[j][i]（§18.7 不变式 3：决策路径不得读「别人对我的态度」）。
		var e_i := _dims[i]
		# 意向类：安慰（§10.13，A 类）—— 有人正处在高压区，而我和他关系够近
		if _allowed("comfort") and _rng.random() < float(_probs["comfort_p"]):
			var base_cf := float(_thresholds_lookup["comfort_trigger_affinity"])
			var intro_cf := float(_thresholds_lookup["comfort_trigger_introvert_affinity"])
			var need_cf := base_cf + (intro_cf - base_cf) * maxf(0.0, (50.0 - e_i) / 50.0)
			var cands_cf: Array = []
			for j in range(n):
				if (
					j != i
					and not busy[j]
					and _can_interact_with(j)
					and _stress[j] >= float(_thresholds_lookup["comfort_trigger_target_stress"])
					and _a[i * n + j] >= need_cf
				):
					cands_cf.append(j)
			if not cands_cf.is_empty():
				var w_cf: Array = []
				for c in cands_cf:
					w_cf.append(maxf(1.0, _stress[c]))
				var j := int(_rng.choices(cands_cf, w_cf, 1)[0])
				_do_comfort(i, j)
				busy[i] = true
				busy[j] = true
				continue
		# 意向类：道歉 / 和解（§10.11，E 类）—— 僵局够深才有「和解」这件事
		if _allowed("apologize") and _rng.random() < float(_probs["apologize_p"]):
			var th_ap := float(_thresholds_lookup["apologize_trigger_hostility"])
			var cands_ap: Array = []
			for j in range(n):
				if j != i and not busy[j] and _can_interact_with(j) and _h[i * n + j] >= th_ap:
					cands_ap.append(j)
			if not cands_ap.is_empty():
				var w_ap: Array = []
				for c in cands_ap:
					w_ap.append(maxf(1.0, _h[i * n + c] + _b_h[i * n + c]))
				var j := int(_rng.choices(cands_ap, w_ap, 1)[0])
				_do_apologize(i, j)
				busy[i] = true
				busy[j] = true
				continue
		# 意向类：加入闲聊（softmax 采样）
		var cands: Array = []
		for j in range(n):
			if j != i and not busy[j] and _can_interact_with(j) and chat_pair_in_range(i, j):
				cands.append(j)
		if not cands.is_empty():
			var alpha := _alpha(i)
			var scores: Array = []
			for c in cands:
				var gain_a := _b_a[i * n + c] / 100.0 * 3.0
				var gain_t := _b_t[i * n + c] / 100.0 * 2.0
				var risk_h := _b_h[i * n + c] / 100.0 * 2.0
				var u := (
					float(alpha["affinity"]) * gain_a
					+ float(alpha["trust"]) * gain_t
					- float(alpha["hostility"]) * risk_h
				)
				u += _crowd_bias(i, "loud")
				u += _tag_bias(i, "chat_bias") - _tag_bias(i, "alone_bias")
				u += _join_gate_utility(i, c)
				scores.append(u)
			if not scores.is_empty():
				var k := _softmax(scores, _tau(i))
				var tgt: int = int(cands[k])
				_do_chat_join(i, tgt)
				busy[i] = true
				busy[tgt] = true


## 选交互目标：邻居优先（§10.15 相邻修正）。neighbors_only 时只在邻居里选。
## 节点此刻是否正处在占用型行为中（§10.4 行为耗时）—— 表现层权限判定用（如玩家操控）。
func is_busy(i: int) -> bool:
	if i < 0 or i >= _n:
		return false
	return _global_tick < _busy_until[i]


## 写入节点在教室里的真实平面位置（米）。越界静默忽略（表现层防御性调用）。
func set_position(i: int, x: float, z: float) -> void:
	if i < 0 or i >= _n:
		return
	_pos_x[i] = x
	_pos_z[i] = z


## 节点当前位置 (x, z)，单位米。
func position_of(i: int) -> Vector2:
	if i < 0 or i >= _n:
		return Vector2.ZERO
	return Vector2(_pos_x[i], _pos_z[i])


## 两点的平面距离（米）—— 空间层判定（交互范围 / 活动圈）的统一口径。
func distance_between(i: int, j: int) -> float:
	var a := position_of(i)
	var b := position_of(j)
	return a.distance_to(b)


## 目标此刻能否接受一次新交互（集中只读判定）。
##
## §10.8 睡眠排除 + **行为耗时占用**：`_busy_until` 未到的人不能被拉去做新交互
## （策划 2026-10-07 裁决：禁止同时参与第二个占用型交互；群聊算同一个交互，
## 靠 `_occupy` 的时长**累积**而不是覆盖）。
## **忙碌者仍可被旁观、被议论、被环境影响** —— 本判定只用于「挑交互目标」，
## 不用于围观者 / 旁白 / 环境查询。
func _can_interact_with(j: int) -> bool:
	return not _sleeping[j] and _global_tick >= _busy_until[j] and not is_moving(j)


func _pick_target(i: int, neighbors_only: bool = false) -> int:
	if neighbors_only:
		var others: Array = []
		for j in _neighbor_idx[i]:
			if _can_interact_with(j) and chat_pair_in_range(i, j):
				others.append(j)
		if others.is_empty():
			return -1
		return int(_rng.choice(others))
	var w_nb := float(_probs["neighbor_pick_mult"])
	var pool: Array = []
	for j in range(_n):
		if j == i or not _can_interact_with(j) or not chat_pair_in_range(i, j):
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
	var occupy_target: bool = not is_player(j) or is_player(i) or _player_invitations.authorizes(i)
	if occupy_target:
		_current_act[j] = null if quiet else behavior
	var dur := int(_behaviors.get(behavior, {}).get("duration", 0))
	if dur > 0:
		# 时长**累积**而不是覆盖（策划 2026-10-07：「群聊作为同一个交互管理，
		# 不能靠覆盖占用实现」）—— 否则加入一场进行中的活动会把已占用的时长改短。
		var until := _global_tick + dur
		_busy_until[i] = maxi(_busy_until[i], until)
		_busy_phase[i] = _phase_index
		_busy_act[i] = behavior
		if occupy_target:
			_busy_until[j] = maxi(_busy_until[j], until)
			_busy_phase[j] = _phase_index
			_busy_act[j] = behavior


## 按成员列表占用（群聊编排用）：全体占用与共同结束点**对齐**，只取更晚的结束点。
## 声源只有一个（音量按「场」计）：`sound_source` 之外的人一律不计声源，
## 加入者不会因为「多一个人说话」把音量叠上去。
func _occupy_members(
	members: Array, behavior: String, until: int, sound_source: int, actor: int = -1
) -> void:
	for m in members:
		var idx := int(m)
		if idx < 0 or idx >= _n:
			continue
		if is_player(idx) and not is_player(actor) and not _player_invitations.authorizes(actor):
			continue
		_current_act[idx] = behavior if idx == sound_source else null
		_busy_until[idx] = maxi(_busy_until[idx], until)
		_busy_phase[idx] = _phase_index
		_busy_act[idx] = behavior


## 真实共同活动的结束点（不存在返回 -1）。
func session_end_tick(session_id: int) -> int:
	return int(_sessions.end_tick_of(session_id))


## 闲聊：话题共鸣事件 + 双方观测。
# ------------------------------------------------------------------ 纸条链（§8.6，2026-10-10）
## 纸条链：**状态与时机在内核，行为逻辑在 pass_note_behavior.gd**（与 chat 同构）。
## 依据：主文档 §8.6（纸条链）、§4.5（选择侧统一公式）、§8.2（1 级把柄）。
## 参考实现 tools/core_sim.py —— 两套内核必须同种子逐位一致（RNG 顺序与次数对齐）。


## 新建一张纸条（**不消耗 RNG**）。返回纸条编号。
func _note_create(author: int, target: int, tone: int, template: int, holder: int) -> int:
	_note_next_id += 1
	var note := {
		"id": _note_next_id,
		"author": author,
		"target": target,
		"tone": tone,
		"tpl": template,
		"holder": holder,
		"prev": author,
		"seen": [author, holder],
		"read": false,
	}
	_notes.append(note)
	return _note_next_id


## 某张纸条的深拷贝快照（不存在返回空字典）。
func _note_row(note_id: int) -> Dictionary:
	for nt in _notes:
		if int(nt["id"]) == note_id:
			return {
				"id": int(nt["id"]),
				"author": int(nt["author"]),
				"target": int(nt["target"]),
				"tone": int(nt["tone"]),
				"tpl": int(nt["tpl"]),
				"holder": int(nt["holder"]),
				"prev": int(nt["prev"]),
				"seen": (nt["seen"] as Array).duplicate(),
				"read": bool(nt["read"]),
			}
	return {}


## 纸条转手：prev 递给了 new_holder（已经手集合去重）。
func _note_pass_on(note_id: int, prev: int, new_holder: int) -> void:
	for nt in _notes:
		if int(nt["id"]) == note_id:
			nt["prev"] = prev
			nt["holder"] = new_holder
			var seen: Array = nt["seen"]
			if not seen.has(new_holder):
				seen.append(new_holder)
			return


## 销毁一张纸条。
func _note_destroy(note_id: int) -> void:
	for i in range(_notes.size() - 1, -1, -1):
		if int(_notes[i]["id"]) == note_id:
			_notes.remove_at(i)
			return


## §4.5 选择侧统一公式（与 Python 参考的 choice_prob 同式；未登记退回 0.5）。
func _choice_prob(event: String, option: String, i: int) -> float:
	var row: Dictionary = _choice.get("%s|%s" % [event, option], {})
	if row.is_empty():
		return 0.5
	var d0 := (_dims[i] - 50.0) / 50.0
	var d1 := (_dims[_n + i] - 50.0) / 50.0
	var d2 := (_dims[2 * _n + i] - 50.0) / 50.0
	var d3 := (_dims[3 * _n + i] - 50.0) / 50.0
	var score := (
		float(row["w_e"]) * d0
		+ float(row["w_s"]) * d1
		+ float(row["w_f"]) * d2
		+ float(row["w_j"]) * d3
		+ float(row["w_stress"]) * (_stress[i] - 50.0) / 50.0
	)
	return _sigmoid((score - float(row["theta"])) / float(row["scale"]))


## 选择侧系数表（§4.5）：event|option -> 系数行。
func _build_choice_weights(tables: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for r in _rows(tables, "rules/choice_weights"):
		var stress_col := str(r.get("w_stress", ""))
		out["%s|%s" % [str(r["event"]), str(r["option"])]] = {
			"theta": float(str(r["theta"])),
			"scale": float(str(r["scale"])),
			"w_e": float(str(r["w_e"])),
			"w_s": float(str(r["w_s"])),
			"w_f": float(str(r["w_f"])),
			"w_j": float(str(r["w_j"])),
			"w_stress": float(stress_col) if stress_col != "" else 0.0,
		}
	return out


## 写纸条（§8.6）：内核只做触发与状态，行为逻辑在组件里。
func _do_pass_note(i: int, j: int) -> void:
	_behavior_registry.execute(&"pass_note", i, j)


# ------------------------------------------------------------------ 观察（§10.3.1，玩家独有只读行为）
## 观察：内核只做校验与分发，信息口径在 `observe_behavior.gd`（零副作用）。
func _do_observe(i: int, j: int) -> void:
	_behavior_registry.execute(&"observe", i, j)


## 观察的可达性：沿用闲聊那套空间口径（普通 1.2 m / 同列前后邻座 1.8 m）。
func _observe_reachable(me: int, target: int) -> bool:
	return chat_pair_in_range(me, target)


## 对象在做「有明确结束点」的活动时，剩余必须 ≥ OBSERVE_TICKS 才谈得上观察（§10.3.1）。
## 空闲与持续型（学习 / 睡觉等整段占用）不受此限。
func _observe_long_enough(target: int) -> bool:
	var left := int(_busy_until[target]) - int(_global_tick)
	if left <= 0 or left >= OBSERVE_FOLLOW_LIMIT:
		return true
	return left >= OBSERVE_TICKS


## 每 tick 处理一张纸条：按编号升序找第一张可处理的
## （持有者不忙不睡、且不是玩家 —— 玩家持有的纸条等玩家选择）。
func _process_notes() -> void:
	if _notes.is_empty():
		return
	var ids: Array = []
	for nt in _notes:
		ids.append(int(nt["id"]))
	ids.sort()
	var me := _n - 1
	for note_id in ids:
		var row := _note_row(int(note_id))
		if row.is_empty():
			continue
		var holder := int(row["holder"])
		if holder < 0 or holder == me:
			continue
		if _sleeping[holder] or _global_tick < _busy_until[holder]:
			continue
		var component: RefCounted = _behavior_registry.component(&"pass_note")
		if component != null:
			component.handle_receipt(_behavior_context, int(note_id))
		return


## 当前手里拿着纸条的节点编号（升序，只读）—— 供表现层画「纸条」徽标（§21.2.9）。
## 不消耗 RNG，也不改任何状态。
func note_holders() -> Array:
	var out: Array = []
	for nt in _notes:
		var h := int(nt["holder"])
		if h >= 0 and not out.has(h):
			out.append(h)
	out.sort()
	return out


## 玩家手上是否有待处理的纸条（供 UI / 表现层查询）。不消耗 RNG。
func note_pending_for_player() -> Dictionary:
	var me := _n - 1
	var ids: Array = []
	for nt in _notes:
		ids.append(int(nt["id"]))
	ids.sort()
	for note_id in ids:
		var row := _note_row(int(note_id))
		if not row.is_empty() and int(row["holder"]) == me:
			return row
	return {}


## 玩家手上最早的一张纸条（没有返回空字典）。
func _player_note_id() -> int:
	var me := _n - 1
	var ids: Array = []
	for nt in _notes:
		if int(nt["holder"]) == me:
			ids.append(int(nt["id"]))
	if ids.is_empty():
		return -1
	ids.sort()
	return int(ids[0])


## **只读**（§8.6）：结算一次并占 10 tick 打断当前行为；纸条留在手上等归属决策。
## 已读过的不重复结算。消耗 RNG：0 次。返回是否真的读了。
func read_note() -> bool:
	var me := _n - 1
	var note_id := _player_note_id()
	if note_id < 0:
		return false
	var row := _note_row(note_id)
	if row.is_empty() or bool(row["read"]):
		return false
	var component: RefCounted = _behavior_registry.component(&"pass_note")
	if component == null:
		return false
	component.settle(_behavior_context, me, int(row["target"]), int(row["tone"]))
	_behavior_context.occupy(me, me, "pass_note")
	_behavior_context.increment_stat("notes_read")
	_note_mark_read(note_id)
	return true


## 标记某张纸条已被读过（玩家侧）。
func _note_mark_read(note_id: int) -> void:
	for nt in _notes:
		if int(nt["id"]) == note_id:
			nt["read"] = true
			return


## 归属决策（§8.6）：继续传 / 撕掉 / **当场举报**（只能在看之后做）。
## 消耗 RNG：继续传时 1 次（randbelow 挑下一个）。
func finish_note(forward: bool = true, report_prev: bool = false) -> bool:
	var me := _n - 1
	var note_id := _player_note_id()
	if note_id < 0:
		return false
	var row := _note_row(note_id)
	if report_prev:
		if not bool(row["read"]):
			return false
		if int(row["prev"]) >= 0:
			# 1 级把柄：写入现有举报链的把柄表（被举报者 = 上一个递给我的人）；
			# 等级在判定里的数值口径待定（§8.2，聊举报那轮定）。
			_witness_day[me * _n + int(row["prev"])] = _day
	if forward:
		var component: RefCounted = _behavior_registry.component(&"pass_note")
		if component != null:
			var next_holder := int(component.pick_next(_behavior_context, me, row["seen"]))
			if next_holder >= 0:
				_note_pass_on(note_id, me, next_holder)
				_behavior_context.occupy(me, me, "pass_note")
				return true
	_note_destroy(note_id)
	_behavior_context.increment_stat("notes_destroyed")
	return true


## 玩家处理手上的纸条（§8.6）：read / forward / report_prev。
## - read：读（立即结算并占 10 tick）；forward：是否继续传（false = 撕掉）
## - report_prev：**当场举报** —— 把柄写给「上一个递给我的人」（§8.2，1 级把柄）
func respond_note(read: bool, forward: bool, report_prev: bool = false) -> bool:
	if read:
		read_note()
	return finish_note(forward, report_prev)


func _do_chat(i: int, j: int) -> void:
	_behavior_registry.execute(&"chat", i, j)


## 加入闲聊判定侧：p 掷骰，无硬闸门；roll 可由调用方预掷（保证三拍展示一致）。
func _do_chat_join(i: int, j: int, roll: float = -1.0) -> void:
	_behavior_registry.execute(&"chat", i, j, {"mode": "join", "roll": roll})


## 举报（§10.2）：i = 举报者，j = 被举报者；效果落在被举报者身上。
func _do_report(i: int, j: int) -> void:
	_behavior_registry.execute(&"report", i, j)


## 当众调侃（§10.12）：方向由绝对阈值判档；围观者按「他对被调侃者的态度」站队。
func _do_tease(i: int, j: int, audience: Array) -> void:
	_behavior_registry.execute(&"tease", i, j, {"audience": audience})


## 排挤（B 类纯损害）：群体驱逐；被排挤者压力↑且对参与者好感↓（双向疏远）。
func _do_exclude(i: int, j: int, crowd: Array) -> void:
	_behavior_registry.execute(&"exclude", i, j, {"crowd": crowd})


## 追逐打闹（§10.18）：参与者互相好感↑、旁观者对参与者敌对↑（敌对种子）。
func _do_roughhouse(i: int, j: int, bystanders: Array) -> void:
	_behavior_registry.execute(&"roughhouse", i, j, {"bystanders": bystanders})


## 安慰（§10.13，A 类）：i 主动关心高压区的 j。目标压力↓、对安慰者好感↑/信任↑；发起者付成本。
func _do_comfort(i: int, j: int) -> void:
	_behavior_registry.execute(&"comfort", i, j)


## 道歉 / 和解（§10.11，E 类）：i 主动向 j 低头。判定读真值（A[j][i] + F_j 随和 − H[j][i]×惩罚）；
## 效果行一律 no_modulation=True（和解与关系调制 M 结构性冲突，否则「越道歉越糟」）。
func _do_apologize(i: int, j: int) -> void:
	_behavior_registry.execute(&"apologize", i, j)


# ------------------------------------------------------------------ 玩家行动（D11 缺口③）
## 玩家显式行动：来源固定玩家（n-1）、目标由玩家指定，走与 NPC 相同的 do_* 统一影响公式，
## 不做 NPC 自动决策。返回结果字典供表现层渲染反馈；topic 暂作透传记录。
## 玩家行动的可执行性校验：返回空串表示可以做，否则返回错误码。
## 与 NPC 共用同一套「能不能做」门槛（§3.3 相位权限、§10.8 目标睡眠）——
## 内核策划符合性审查 P1-02：不能只靠 UI 隐藏按钮，内核入口必须自己拒绝。
func _player_action_error(kind: String, target: int, me: int) -> String:
	if target < 0 or target >= _n or target == me:
		return "invalid_target"
	if not PLAYER_KINDS.has(kind):
		return "unknown_kind"
	if _sleeping[me] or _global_tick < _busy_until[me] or is_moving(me):
		return "player_busy"
	if not _allowed(kind):
		return "phase_not_allowed"
	if kind == "observe":
		# 观察是**只读**的：睡着的人也能看，也不要求对方空闲（对象不知情、不被打断）
		if not _observe_reachable(me, target):
			return "out_of_range"
		if not _observe_long_enough(target):
			return "too_little_time"
		return ""
	if not _can_interact_with(target):
		return "target_unavailable"
	return ""


func player_action(kind: String, target: int, topic: String = "") -> Dictionary:
	var me := _n - 1
	# 闲聊（发起／加入）统一走交互服务：真实范围校验、幂等提交、真实会话登记。
	# 玩家只有一个聊天入口：`kind=chat` + `mode=start/join` 由预览决定参与方式。
	if kind == "chat":
		return _player_chat_entry(kind, target, topic)
	# 「能不能做」先过公共门槛，再执行具体行为（玩家可跳过「想不想」，不能跳过「能不能」）
	var blocked := _player_action_error(kind, target, me)
	if not blocked.is_empty():
		return {"ok": false, "error": blocked}
	var a_before := _a[target * _n + me]  # 目标→玩家的好感（行动前的反应基线）
	var h_before := _h[target * _n + me]
	match kind:
		"tease":
			_do_tease(me, target, _player_audience(target))
		"report":
			_do_report(me, target)
		"roughhouse":
			_do_roughhouse(me, target, _player_bystanders(target))
		"exclude":
			_do_exclude(me, target, _player_hurters(target))
		"pass_note":
			_do_pass_note(me, target)
		"observe":
			_do_observe(me, target)
		_:
			return {"ok": false, "error": "unknown_kind"}
	return {
		"ok": true,
		"kind": kind,
		"target": target,
		"topic": topic,
		"accepted": true,
		"affinity_delta": snapped(_a[target * _n + me] - a_before, 0.1),
		"hostility_delta": snapped(_h[target * _n + me] - h_before, 0.1),
	}


## 玩家聊天入口：由预览决定参与方式（start / join），提交时使用内核分配的请求编号。
func _player_chat_entry(_kind: String, target: int, topic: String) -> Dictionary:
	var pv: Dictionary = _player_interactions.preview("chat", target)
	if not bool(pv.get("ok", false)):
		return {"ok": false, "error": str(pv.get("error", "invalid"))}
	if not bool(pv["eligible"]):
		return {"ok": false, "error": str(pv["reason"])}
	if not bool(pv["in_range"]):
		return {"ok": false, "error": "out_of_range"}
	var request_id: int = _player_interactions.next_request_id()
	var packet: Dictionary = commit_player_interaction(
		request_id, "chat", target, str(pv["mode"]), int(pv["session_id"])
	)
	if not bool(packet.get("ok", false)):
		return packet
	packet["topic"] = topic
	return packet


# ------------------------------------------------- 玩家交互服务（闲聊：发起／加入）
## 只读预览（零 RNG、零状态变化）：mode=start/join、合法性与范围；仅 join 含信念估计。
func preview_player_interaction(kind: String, target: int) -> Dictionary:
	return _player_interactions.preview(kind, target)


## 原子提交：失败不掷骰、不改矩阵、不新增占用与会话；成功发布一次开始通知。
func commit_player_interaction(
	request_id: int, kind: String, target: int, mode: String, session_id: int = -1
) -> Dictionary:
	var known: bool = bool(_player_interactions.get_request(request_id).get("ok", false))
	var packet: Dictionary = _player_interactions.commit(request_id, kind, target, mode, session_id)
	if not bool(packet.get("ok", false)):
		return packet
	if not known:
		_emit("event_happened", _started_payload(request_id, target, packet))
	return packet


func _started_payload(request_id: int, target: int, packet: Dictionary) -> Dictionary:
	return {
		"kind": "player_interaction_started",
		"request_id": request_id,
		"mode": str(packet["mode"]),
		"target": target,
		"session_id": int(packet["linked_session"]),
		"origin_session": int(packet["session_id"]),
		"accepted": bool(packet["accepted"]),
		"end_tick": int(packet["end_tick"]),
	}


## 请求状态查询：active / completed / interrupted + outcome（深拷贝）。
func get_player_interaction(request_id: int) -> Dictionary:
	return _player_interactions.get_request(request_id)


## 请求编号由本局内核分配（只生成编号，不掷骰）。
func next_player_request_id() -> int:
	return _player_interactions.next_request_id()


## 真正共同活动的只读快照（供底部圈与「能不能加入」查询，深拷贝）。
func get_active_sessions() -> Array:
	return _sessions.active_snapshots()


func get_player_invitation() -> Dictionary:
	return _player_invitations.pending()


func respond_player_invitation(id: int, accepted: bool) -> Dictionary:
	return _player_invitations.respond(id, accepted)


func is_waiting_for_player(i: int) -> bool:
	return _player_invitations.is_waiting(i)


## 玩家本局已获得的线索（历史日志；记录于当时，不跟着矩阵实时刷新）。
func get_player_intel() -> Array:
	return _player_interactions.intel_history()


## 交互几何注入：**纯数据**（障碍矩形 + 房间边界），场景从寻路几何导出后一次注入。
## 未注入时一切交互判定返回明确错误，不静默放行。
func set_interaction_geometry(obstacles: Array, bounds: Rect2) -> void:
	_scene_space_required = true
	_space.set_geometry(obstacles, bounds)


func interaction_space_ready() -> bool:
	return _space.is_ready()


## 真实教室的聊天空间门槛；无场景几何的离线标定保持原抽象模型。
func chat_pair_in_range(i: int, j: int) -> bool:
	if not _space.is_ready():
		return not _scene_space_required
	if _at_own_seat(i) and _at_own_seat(j):
		var a: Array = _seat_pos[seat_of(i)]
		var b: Array = _seat_pos[seat_of(j)]
		return (
			int(a[1]) == int(b[1])
			and absi(int(a[0]) - int(b[0])) == 1
			and distance_between(i, j) <= _player_interactions.seated_chat_range()
		)
	return (
		_space.position_valid(position_of(j))
		and _space.valid_position_for(
			position_of(i),
			[position_of(j)],
			_player_interactions.chat_range(),
			_player_interactions.range_step()
		)
	)


func set_seat_position(i: int, position: Vector2) -> void:
	if i >= 0 and i < _n:
		_seat_world_positions[i] = position


func _at_own_seat(i: int) -> bool:
	return (
		_seat_world_positions.has(i)
		and (
			position_of(i).distance_to(_seat_world_positions[i])
			<= _player_interactions.seated_tolerance()
		)
	)


## 独立移动状态：玩家走动中不被 NPC 拉进新占用交互；**不是**聊天占用。
func set_moving(i: int, moving: bool) -> void:
	_player_interactions.set_moving(i, moving)


func is_moving(i: int) -> bool:
	return _player_interactions.is_moving(i)


## 某人此刻所在共同活动（不在任何会话返回 -1）。
func session_of(i: int) -> int:
	return int(_sessions.session_of(i))


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
	for k in _neighbor_idx[me] + _neighbor_idx[j]:
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
	var banned := [
		"chat",
		"tease",
		"comfort",
		"apologize",
		"share_secret",
		"roughhouse",
		"exclude",
		"report",
		"move"
	]
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
	lines.append(
		(
			"  好感：min %.1f / 中位 %.1f / 均值 %.1f / max %.1f"
			% [aff[0], aff[aff.size() / 2], mean, aff[aff.size() - 1]]
		)
	)
	lines.append("  接近饱和(>=%.0f)比例：%.1f%%" % [sat_th, saturated * 100.0])
	lines.append(
		(
			"  事件 %d 次（闲聊 %d / 加入 %d / 举报 %d）"
			% [_stats["events"], _stats["chats"], _stats["joins"], _stats["reports"]]
		)
	)
	lines.append(
		(
			"  睡着 %d 人次 | 调侃 %d（过火 %d）/ 排挤 %d / 打闹 %d / 被打断 %d"
			% [
				_stats["sleeps"],
				_stats["teases"],
				_stats["tease_fail"],
				_stats["excludes"],
				_stats["roughhouse"],
				_stats["interrupts"]
			]
		)
	)
	lines.append(
		(
			"  纸条：写 %d / 读 %d / 销毁 %d（活跃 %d）"
			% [
				_stats["notes_written"],
				_stats["notes_read"],
				_stats["notes_destroyed"],
				_notes.size()
			]
		)
	)
	lines.append("  去重跳过 %d 次" % _stats["dedup_skips"])
	lines.append(
		(
			"  传导结算 %d 次 | 压力爆发 %d 次（平均每 %.1f 天一次）"
			% [
				_stats["transmission_ticks"],
				_stats["bursts"],
				float(_day - 1) / float(maxi(1, _stats["bursts"]))
			]
		)
	)
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


func grade(i: int) -> float:
	if i < 0 or i >= _n:
		return 0.0
	return _grade[i]


func study_acc(i: int) -> float:
	if i < 0 or i >= _n:
		return 0.0
	return _study_acc[i]


## 性格四维第 dim 轴（0=E, 1=N, 2=F, 3=P）；越界返回 50（中性值）。
func dimension(i: int, dim: int) -> float:
	if i < 0 or i >= _n or dim < 0 or dim >= DIMS.size():
		return 50.0
	return _dims[dim * _n + i]


## 行为基础概率（来自 data/rules/behavior_probs.csv）；未注册返回 0.0。
func behavior_base_p(behavior: String) -> float:
	return float(_probs.get(behavior, 0.0))


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
	return OBSERVER_LAYER.new(self).cluster_tags(viewer)


## 观察层（只读）：viewer 眼中的「被孤立者」（§10.26.3）。
func get_isolated(viewer: int = -1) -> Array:
	return OBSERVER_LAYER.new(self).isolated_tags(viewer)


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


func _build_grade_bands(tables: Dictionary) -> Array:
	var bands: Array = []
	for row in _rows(tables, "rules/grade_table"):
		bands.append([float(row["band_upper"]), float(row["ticks_per_point"])])
	bands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return bands


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
