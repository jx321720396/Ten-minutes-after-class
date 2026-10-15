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
## 索引约定：n = 本局入局 NPC 数 + 1（末位 n-1 为玩家；人数由调用方直接给出，
## 正式玩法取 `data/rules/roster.csv` 的 16，角色池见 `characters/seeds.csv`）；矩阵平铺 A[i][j] → _a[i*n+j]；
##
## 老师版（2026-10-14）：删除四维/透明度/信任及信念矩阵、传导、深层敌对，以及从众/调侃/举报/
## 排挤/道歉/安慰/传纸条/学习圈/书礼/提问/讲题等学生版依赖子系统；只保留 A/H + 压力/动力/学业收益/成绩
## 与公开专属被动。行为集 = 老师版 §9.2 + §9.4（多人聊天 / 搭话 / 打闹 / 学习 / 娱乐 / 崩溃 / 座位结算）。

const AXES := ["affinity", "hostility"]
## 玩家可通过 player_action 发起的行为（与 data/rules/behaviors.csv 的行名一致）
## 自指行为（对自己做的事）：不需要对象，玩家直接发起
const LEISURE_KINDS := {"listen_music": "music", "eat_snack": "snack", "read_book": "book"}
const PLAYER_SELF_KINDS := [
	"study", "sleep", "listen_music", "eat_snack", "read_book", "leave_class"
]
const PLAYER_KINDS := [
	"chat",
	"roughhouse",
	"study",
	"sleep",
	"listen_music",
	"eat_snack",
	"read_book",
	"leave_class",
]
## 讲桌旁的皇帝位（§18.3.2）。座位号是座位表的标识，不是角色判断。
const EMPEROR_SEAT := "P0"
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
const EXAM_SETTLE := preload("res://scripts/core/exam_settle.gd")
const TERM_RECORD := preload("res://scripts/core/term_record.gd")

var _term_record: RefCounted

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
var _stress := PackedFloat64Array()  # 压力 Stress  n
var _grade := PackedFloat64Array()  # 成绩 grade  n（§17.1）
var _study_acc := PackedFloat64Array()  # 学习时长累加器 study_acc  n（§17.1.2）
var _exam: RefCounted  # 周考 / 期末考（§19.1），脚本见 exam_settle.gd

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
var _conversations: Array = []  # 多人会话列表：{"members": Array(升序)}（2026-10-14 重构）
var _conv_of: Array = []  # 节点 -> 所在会话 dict（null = 不在会话）
var _join_log: Array = []  # 通用加入日志（投票/跟随/不合流/满员，只读观察，§9.1.4 交接 3）
# 通用加入（§9.1.4，2026-10-15）：活动组（打闹/学习/零食分享）+ 带朋友冷却 + 分享去重
var _rough_groups: Array = []  # 打闹组：{"members": Array(升序)}
var _rough_of: Array = []  # 节点 -> 打闹组 dict（null = 不在打闹组）
var _study_groups: Array = []  # 学习组：{"members": Array(升序)}（一起学习：各自按真实单位结算）
var _study_of: Array = []  # 节点 -> 学习组 dict
var _snack_groups: Array = []  # 零食分享组：{"members": Array(升序), "provider": int}
var _snack_of: Array = []  # 节点 -> 零食分享组 dict
var _snack_provider: Array = []  # 加入者 -> 分享者（自然完成单位后结算分享好感）
var _share_units: Dictionary = {}  # Vector2i(provider, receiver) -> 已结算分享单位数（去重，只读观察）
var _joined_tick: Array = []  # 最近一次加入活动的 tick（本决策点新加入者不带朋友，§9.1.4）
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
## 每个节点的座位站位世界坐标（表现层注入；内核只读）
var _seat_world: Dictionary = {}
var _leisure: Dictionary = {}
var _absence: Dictionary = {}
var _book: Array = []
var _teacher := TeacherPatrol.new()
var _snacks_remaining := 0
var _player_absent := false
var _leave_count := 0


func _init(seed: int, npc_count: int, tables: Dictionary = {}) -> void:
	# §4.1 契约：SimCore.new(seed, npc_count)。tables 为空时内核内部自取（ConfigLoader 非 autoload，不违反反向依赖铁律）。
	# 2026-10-12：删除难度档概念 —— 人数由调用方直接给出（正式玩法取 data/rules/roster.csv 的 16）。
	if tables.is_empty():
		tables = ConfigLoader.new().load_all()
	_seed = seed
	_rng = MtRandom.new(seed)
	# 本局阵容人数：不得超过角色池人数（池里没有的人不会凭空入局；多传的人数被忽略并明确告警）
	var pool: Array = _rows(tables, "characters/seeds").duplicate()
	var want := clampi(npc_count, 1, pool.size())
	if npc_count != want:
		push_warning(
			"SimCore：npc_count=%d 超出 1..%d（角色池），本局按 %d 人开局。" % [npc_count, pool.size(), want]
		)
	_n = want + 1
	var n := _n

	_load_config(tables)

	# 单步推进游标：非 settle 段（课间/上课）顺序（D11）
	_active_phases = []
	for row in _phase_order:
		if str(row["kind"]) != "settle":
			_active_phases.append(row)

	# ⚠️ 必须 .duplicate()：_rows 返回共享缓存引用，shuffle 原地改写会污染跨实例共享的 tables。
	_rng.shuffle(pool)
	_chars = LeisureActions.select_roster(pool, want, _leisure)
	if _chars.size() != want:
		push_error(
			(
				"SimCore：角色装配 %d 人 ≠ 目标 %d 人（characters/seeds.csv 与 rules/leisure 的持书配额不匹配）。"
				% [_chars.size(), want]
			)
		)
	for ch in _chars:
		_book.append(int(str(ch["book"])))
	_book.append(0)
	_snacks_remaining = int(_leisure["snack_count_per_run"])

	_alloc(n)

	_init_relations()
	_init_grade()

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
	_exam = EXAM_SETTLE.new()
	_exam.configure(tables, _seed, _n, float(_kp["grade_max"]))
	_exam.capture_baseline(_grade)

	# 真实共同活动 + 交互几何 + 玩家交互服务 + 线索日志（构造不消费随机数）
	_sessions = ACTIVITY_SESSIONS.new()
	_space = INTERACTION_SPACE.new()
	_intel = PLAYER_CHAT_INTEL.new(_seed)
	_player_interactions = PLAYER_INTERACTIONS.new(self, _space, _sessions, _intel)
	var pi_params := _params(tables, PLAYER_INTERACTION_TABLE)
	_player_interactions.configure(pi_params)
	_intel.configure(pi_params)
	_player_invitations = PLAYER_INVITATIONS.new(self, tables, pi_params)
	_term_record = TERM_RECORD.new()
	_term_record.configure(self, tables)


func _load_config(tables: Dictionary) -> void:
	_teacher.configure(_params(tables, "rules/teacher"), _n)
	_leisure = _params(tables, "rules/leisure")
	_absence = _params(tables, "rules/player_absence")
	_p = _params(tables, "rules/transmission")
	_kp = _params(tables, "rules/kernel_params")
	_grade_bands = _build_grade_bands(tables)
	_probs = _build_behavior_probs(tables)
	_thresholds_lookup = _build_thresholds(tables)
	_decay = _params(tables, "rules/decay")
	_behaviors = _build_behaviors(tables)
	for kind in LEISURE_KINDS:
		var prefix: String = LEISURE_KINDS[kind]
		_behaviors[kind] = {
			"duration": int(_leisure[prefix + "_duration"]),
			"noise": float(_leisure[prefix + "_noise"]),
			"kind": "env",
			"join_mode": "none"
		}
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
	_stress.resize(n)
	_grade.resize(n)
	_study_acc.resize(n)


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
		"bursts": 0,
		"interrupts": 0,
		"skipped_events": 0,
		"dedup_skips": 0,
		"roughhouse": 0,
		"sleeps": 0,
		"studies": 0,
		"join_accepts": 0,
		"join_rejects": 0,
		"chat_joins": 0,
		"chat_leaves": 0,
		"chat_max_size": 0,
		"invite_friends": 0,
		"share_units": 0,
	}
	_next_action = []
	_busy_until = []
	_busy_phase = []
	_current_act = []
	_sleeping = []
	_in_conversation = []
	_conversations = []
	_conv_of = []
	_join_log = []
	_rough_groups = []
	_rough_of = []
	_study_groups = []
	_study_of = []
	_snack_groups = []
	_snack_of = []
	_snack_provider = []
	_joined_tick = []
	_share_units = {}
	_knot_days = []
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
		_conv_of.append(null)
		_rough_of.append(null)
		_study_of.append(null)
		_snack_of.append(null)
		_snack_provider.append(null)
		_joined_tick.append(-1)
		_knot_days.append(0)


# ------------------------------------------------------------------ 初始化关系
func _init_relations() -> void:
	var n := _n
	var base_a := float(_kp["init_affinity_base"])
	var spread_a := float(_kp["init_affinity_spread"])
	var spread_h := float(_kp["init_hostility_spread"])
	for i in range(n):
		for j in range(n):
			if i == j:
				continue
			_a[i * n + j] = _clamp100(base_a + _rng.random() * spread_a)
			_h[i * n + j] = _clamp100(_rng.random() * spread_h)
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


## 成绩初始化（§17.1.1）：NPC 种子化均匀 [min,max)，玩家固定。消费 len(chars) 次 RNG。
## ⚠️ 必须紧跟 _init_relations() 之后调用，与 Python 同一点插入，保同种子 RNG 流不漂移。
func _init_grade() -> void:
	var gmin := float(_kp["grade_init_npc_min"])
	var gmax := float(_kp["grade_init_npc_max"])
	for i in range(_chars.size()):
		_grade[i] = gmin + _rng.random() * (gmax - gmin)
	_grade[_n - 1] = float(_kp["grade_init_player"])


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
	if _phase == "class":
		_class_affinity_settle()
	_settle_sleep()
	_check_interrupt()
	_cleanup_phase()
	if _phase_index + 1 >= _active_phases.size():
		_settle_day()


## 统一边界协议 ⑥⑦：进入当前段（_phase_index 已指向本段）并执行新段判定。
## 核心 RNG 消费序：roll_sleep。
func _begin_phase() -> void:
	var row: Dictionary = _active_phases[_phase_index]
	_phase = str(row["kind"])
	_tick_in_phase = 0
	_teacher.begin_phase(self)
	_roll_sleep()
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
	_tick_in_phase = 0


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
	var leisure_notifications: Array = []
	# ③ 清理占用/当前动作
	for i in range(_n):
		if _busy_phase[i] < 0 or _busy_until[i] > _global_tick:
			continue
		_last_finished[i] = _busy_act[i]
		if is_player(i):
			_term_record.end_action("completed")
		if LEISURE_KINDS.has(_busy_act[i]):
			var prefix: String = LEISURE_KINDS[_busy_act[i]]
			_stress[i] = _clamp100(_stress[i] - float(_leisure[prefix + "_relief"]))
			if _busy_act[i] == "eat_snack" and _snack_provider[i] != null:
				# 分享零食（§9.1.4）：自然完成一个共同进食单位 → 对分享者结算一次分享好感；
				# 中断 / 退出不结算；同一对子每课间段至多一次（沿用事件去重，防退出重入刷收益）
				var provider := int(_snack_provider[i])
				_apply_event(i, provider, "snack_share_affinity")
				var skey := Vector2i(provider, i)
				_share_units[skey] = int(_share_units.get(skey, 0)) + 1
				_snack_provider[i] = null
				_stats["share_units"] = int(_stats.get("share_units", 0)) + 1
			leisure_notifications.append(
				{
					"kind": "leisure_finished",
					"i": i,
					"activity": _busy_act[i],
					"snacks_remaining": _snacks_remaining
				}
			)
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
	for payload in leisure_notifications:
		_emit("event_happened", payload)
	for payload in notifications:
		_emit("event_happened", payload)


func _tick() -> void:
	_global_tick += 1
	_settle_finished_actions()
	_settle_conversations()
	_settle_groups()
	_teacher.step(self)
	_decide_and_act()
	_term_record.tick_state(self)
	_study_accumulate()
	_update_environment()
	if _global_tick % int(_p["settle_interval"]) == 0:
		_stress_drip()


## 成绩涓流（§17.1.2）：每 tick 处于「学习状态」（默认空闲 = 无行为且不忙碌）时累积 study_acc，
## 满档 +1 分。上课段不累积；跨天保留（_settle_day 不清 study_acc）。不消耗 RNG。
func _study_accumulate() -> void:
	if _phase != "break":
		return
	var gmax := float(_kp["grade_max"])
	for i in range(_n):
		if not is_present(i):
			continue
		if _grade[i] >= gmax:
			_study_acc[i] = 0.0
			continue
		# §8.23：学习是**主动行为** —— 玩家与 NPC 都必须处于学习态才累积成绩
		if _current_act[i] != "study":
			continue
		_study_acc[i] += 1.0
		var tpp := _grade_ticks_per_point(_grade[i])
		if tpp <= 0.0:
			continue
		_fold_study_acc(i)


## 把已经灌进 study_acc 的时长折成分数。满档 +1，并给自身压力（§8.23）。
func _fold_study_acc(i: int) -> void:
	var gmax := float(_kp["grade_max"])
	while _grade[i] < gmax:
		var tpp := _grade_ticks_per_point(_grade[i])
		if tpp <= 0.0 or _study_acc[i] < tpp:
			return
		_study_acc[i] -= tpp
		_grade[i] += 1.0
		_apply_event(i, i, "study_stress")


## 当前成绩档的「每 +1 分所需 tick」（§17.1.2 分段表）；越界返回 0。
func _grade_ticks_per_point(g: float) -> float:
	for band in _grade_bands:
		if g < float(band[0]):
			return float(band[1])
	return 0.0


# -------------------------------------------------- 事件出口（D11 缺口④：内核 → 表现层，零 autoload 依赖）
## 向注入的事件出口派发一条事件（type + payload）。event_sink 为空时无副作用（headless/测试）。
func _emit(type: String, payload: Dictionary) -> void:
	if _term_record != null and type == "event_happened":
		_term_record.event(payload)
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


## 跨天结算（§3.5）：压力爆发概率判定 → 心结每日加压 → 各轴衰减。
func _settle_day() -> void:
	_try_burst()
	# 「心结」：爆发后的几天里，每天先加压（长线心理创伤，§3.5）。
	for i in range(_n):
		if _knot_days[i] > 0:
			_stress[i] = _clamp100(_stress[i] + float(_status_tags["heart_knot"]["daily_stress"]))
			_knot_days[i] -= 1
	# 各轴衰减（§10.22）：好感/敌对按是否互动分档，压力保留系数。
	var decay_h := float(_decay["decay_h"])
	var decay_a_interact := float(_decay["decay_a_interact"])
	var decay_a_no_interact := float(_decay["decay_a_no_interact"])
	var interact_min := float(_decay["interact_min_events"])
	var retain_s := float(_decay["retain_s"])
	for i in range(_n):
		for j in range(_n):
			if i == j:
				continue
			var idx := i * _n + j
			var interacted := float(_day_events.get("%d,%d" % [i, j], 0)) >= interact_min
			_a[idx] *= decay_a_interact if interacted else decay_a_no_interact
			_h[idx] *= decay_h
		_stress[i] *= retain_s
	_day_events.clear()
	if _exam != null:
		_exam.settle(_day, _grade, _stress, _alias_list())
	_term_record.settle_day(self, _day)
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


## 关系调制：M_relation = clamp((A−H)/50, −1, 1)。
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
	elif axis == "stress":
		key = "u_s"
	var u_cap := float(_p.get(key, 25.0))
	return u / (1.0 + absf(u) / u_cap)


## 统一影响公式落表：Δ = M_state · sat(P)；P = base·scale（·M_relation）。
## 老师版（2026-10-14）：删除性格倍率与 trust 轴，只写好感/敌对/压力；删除深层敌对。
func _apply_event(i: int, j: int, event_id: String, scale: float = 1.0) -> bool:
	if not is_present(i) or not is_present(j):
		return false
	var dkey := "%d|%d|%s|%d|%d" % [i, j, event_id, _day, _phase_index]
	if _settled.has(dkey):
		_stats["dedup_skips"] = int(_stats["dedup_skips"]) + 1
		return false
	_settled[dkey] = true
	var dekey := "%d,%d" % [i, j]
	_day_events[dekey] = int(_day_events.get(dekey, 0)) + 1
	var applied := false
	var changes: Array = []
	for row in _event_rows:
		if str(row["event_id"]) != event_id:
			continue
		var axis := str(row["axis"])
		var base := float(str(row["base"]))
		var e_val := base * scale
		var is_axis := axis == "affinity" or axis == "hostility"
		if is_axis:
			e_val *= _m_relation(i, j)
		var negative := (base < 0.0) == is_axis
		var delta := 0.0
		if axis == "stress":
			delta = _r1(_sat(e_val, axis))
		else:
			delta = _r1(_m_state(i, negative) * _sat(e_val, axis))
		if axis == "stress":
			_stress[i] = _clamp100(_stress[i] + delta)
		else:
			var idx := i * _n + j
			var cur := 0.0
			if axis == "affinity":
				cur = _a[idx]
			else:
				cur = _h[idx]
			delta = _r1(_room_for(axis, cur) * delta)
			var v := _clamp100(cur + delta)
			if v != cur:
				changes.append([AXES.find(axis), idx, cur, v])
			if axis == "affinity":
				_a[idx] = v
			else:
				_h[idx] = v
		applied = true
		_stats["events"] = int(_stats["events"]) + 1
	_term_record.record_changes(self, changes, event_id)
	return applied


# ------------------------------------------------------------------ 涓流结算（stress_drip 及其环境/社会层）
## 环境音量：追踪当前进行中行为的噪声，向目标音量缓慢逼近。
func _update_environment() -> void:
	var target := 0.0
	for i in range(_n):
		if _global_tick >= _busy_until[i] and _current_act[i] != "study":
			_current_act[i] = null
		var act = _current_act[i]
		if act == null:
			continue
		target += float(_behaviors.get(act, {}).get("noise", 0.0))
	if _teacher.present:
		target *= float(_teacher.params["volume_target_mult"])
	var volume_max := float(_env["volume_max"])
	target = clampf(target, 0.0, volume_max)
	var rate := float(_env["adapt_rate"])
	_volume = clampf(_volume + rate * (target - _volume), 0.0, volume_max)


## 压力涓流：偏差压力 + 学习/独处滴注（老师版删除噪声压力/噪声敌对/从众敌对）。
func _stress_drip() -> void:
	_deviance_pressure()
	for i in range(_n):
		if not is_present(i):
			continue
		if _in_conversation[i]:
			continue
		if _doing_study(i):
			_stress[i] = _clamp100(_stress[i] + float(_probs["study_stress"]))
		else:
			_stress[i] = _clamp100(_stress[i] + float(_probs["alone_stress"]))


func _deviance_pressure() -> void:
	var k := float(_env.get("deviance_k", 0.0))
	if k <= 0.0:
		return
	var v := _volume / 100.0
	var loud := ["chat", "roughhouse"]
	for i in range(_n):
		if not is_present(i):
			continue
		var act = _current_act[i]
		if act == null:
			act = "study"
		if loud.has(act) and v < 0.4:
			_stress[i] = _clamp100(_stress[i] + k * (0.4 - v) * 10.0)
		elif act == "study" and v > 0.72:
			_stress[i] = _clamp100(_stress[i] + k * (v - 0.72) * 10.0)


func _doing_study(_i: int) -> bool:
	return true


# ------------------------------------------------------------------ 相位结算
func _settle_sleep() -> void:
	var relief := float(_probs.get("sleep_relief", 0.0))
	for i in range(_n):
		if _sleeping[i]:
			if is_player(i):
				_term_record.end_state("sleep")
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
			if is_player(i):
				_term_record.end_action("interrupted")
			_busy_until[i] = 0
			_busy_phase[i] = -1
			var action_cost := (
				float(_leisure["interrupted_stress"]) if LEISURE_KINDS.has(_busy_act[i]) else cost
			)
			if action_cost > 0.0:
				_stress[i] = _clamp100(_stress[i] + action_cost)
			_stats["interrupts"] = int(_stats["interrupts"]) + 1
			_interrupted_nodes.append(i)


## 统一边界协议 ④：清理被打断动作的残余状态（占用 / 会话 / 移动锁）。
## 不消耗 RNG；抽象内核（无移动输入）下移动锁清理为 no-op。
func _cleanup_phase() -> void:
	_interrupt_conversations()
	_clear_join_groups()
	_term_record.end_state("study")
	_term_record.moving(false, false)
	var leisure_notifications: Array = []
	for i in range(_n):
		if _current_act[i] == "study":
			_current_act[i] = null
			_study_acc[i] = 0.0
	for i in _interrupted_nodes:
		if LEISURE_KINDS.has(_busy_act[i]):
			leisure_notifications.append(
				{"kind": "leisure_interrupted", "i": i, "activity": _busy_act[i]}
			)
		_current_act[i] = null
		_busy_act[i] = null
		_in_conversation[i] = false
	for payload in leisure_notifications:
		_emit("event_happened", payload)
	if _player_absent:
		_term_record.end_state("leave_class")
		_player_absent = false
		_busy_until[_n - 1] = 0
		_current_act[_n - 1] = null
		_emit("event_happened", {"kind": "player_returned"})
	_leave_count = 0
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


## 意向权重 alpha：老师版删四维，退化为 A/H/stress 常数后归一化（Σ=1，§5）。
func _alpha(_i: int) -> Dictionary:
	var raw := {
		"affinity": float(_nw["alpha_a_base"]),
		"hostility": float(_nw["alpha_h_base"]),
		"stress": float(_nw["alpha_s_base"]),
	}
	var total := float(raw["affinity"]) + float(raw["hostility"]) + float(raw["stress"])
	return {
		"affinity": float(raw["affinity"]) / total,
		"hostility": float(raw["hostility"]) / total,
		"stress": float(raw["stress"]) / total,
	}


## 意向温度 tau：压力 ≥70 更冲动（温度放大）；下限 0.01（§4.4）。
func _tau(i: int) -> float:
	var t := float(_nw["tau0"])
	if _stress[i] >= 70.0:
		t *= float(_nw["tau_stress_mult"])
	return maxf(t, 0.01)


## 加入闲聊判定侧 score：**被请求者的真值好感 A[j][i]** + 对方外向度 − 对方压力惩罚（§6.4）。
## 判定读真值 ——「他会不会接纳我」由他的真实态度决定，不由我的猜测决定；我的猜测只进
## 决策侧（要不要去试）与展示层（成功率）。读 A[j][i] 不违反 §18.7 不变式 3 ——
## 该不变式禁止的是**决策路径**读它；本方法属**判定路径**，规格要求它读真值。
func _join_score(i: int, j: int) -> float:
	# 2026-10-14 删四维外向项（老师版删除隐藏性格四维，聊天机制规格 E）
	var base := _a[j * _n + i]
	var hot := maxf(0.0, _stress[j] - 50.0) / 50.0
	var penalty := float(_thresholds_lookup["chat_join_stress_penalty"])
	return base - penalty * hot


## 加入闲聊判定侧概率：p = σ((score − θ)/scale)，永不为 0/1（§6.4）。
func _join_probability(i: int, j: int) -> float:
	var theta := float(_thresholds_lookup["chat_join_affinity"])
	var scale := float(_thresholds_lookup["chat_join_scale"])
	return _sigmoid((_join_score(i, j) - theta) / scale)


## 只读：玩家侧看到的成功率 p（§10.32）。老师版删信念/透明度后玩家可读真值，
## 显示概率 = 实际结算概率（读 A[j][i]）。
func _join_feedback(i: int, j: int) -> Dictionary:
	var hot := maxf(0.0, _stress[j] - 50.0) / 50.0
	var score := _a[j * _n + i] - float(_thresholds_lookup["chat_join_stress_penalty"]) * hot
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
			"note": "成功与否看对方对你的真实好感。",
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


## 一 tick 内的行为决策：休闲 → 学习 → 闲聊 / 打闹（通用加入 §9.1.4）→ 带朋友 pass。
## 铁律：决策顺序按索引升序（可复现，取代 Python 的 shuffle）；决策读「我对他」的 A/H（§18.7 不变式 3）。
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
		var leisure_started := false
		for kind in LEISURE_KINDS:
			var prefix: String = LEISURE_KINDS[kind]
			if _allowed(kind) and (kind != "read_book" or _book[i] > 0):
				if _rng.random() < float(_probs[prefix + "_p"]):
					_start_leisure(i, kind)
					leisure_started = true
					break
		if leisure_started:
			busy[i] = true
			continue
		# 环境类：学习（§8.23）—— 主动坐下学一整个课间；爱学习的人更常坐下来
		var study_gain := 1.0 + _tag_bias(i, "study_bias")
		if _allowed("study") and _rng.random() < float(_probs["study_p"]) * study_gain:
			_do_study(i)
			busy[i] = true
			continue
		# 环境类：闲聊 —— 通用加入（§9.1.4）：找伴 → 提议 / 加入 / 跟随（确定投票 §9.1.2）
		# 标签调制（§11、§18.9）：爱学习更少聊、爱聊天更多聊
		var chat_gain := 1.0 + _tag_bias(i, "chat_bias") - _tag_bias(i, "study_bias")
		chat_gain = maxf(0.1, chat_gain)
		if _allowed("chat") and _rng.random() < float(_probs["chat"]) * chat_gain:
			var tgt := _find_partner(i, "chat")
			if tgt >= 0:
				# 一个决策点只发起一次伙伴尝试：成败都到此为止（§9.1.4 循环与时序）
				_propose_activity(i, tgt, "chat")
				busy[i] = true
				continue
		# 意向类：追逐打闹（§9.2）—— 同走通用加入找伴；场地条件沿用旁观者门槛
		var th_rc := int(_thresholds_lookup["roughhouse_count"])
		if (
			_allowed("roughhouse")
			and _rng.random() < float(_probs["roughhouse_p"]) * _teacher.multiplier("roughhouse")
		):
			var tgt := _find_partner(i, "roughhouse")
			if tgt >= 0:
				var bys: Array = []
				for k in range(n):
					if k != i and k != tgt and not busy[k] and is_present(k) and not _sleeping[k]:
						bys.append(k)
				if bys.size() >= th_rc:
					_propose_activity(i, tgt, "roughhouse")
					busy[i] = true
					continue

	# 带朋友（§9.1.3/§9.1.4）：活动组成员的邀请 pass；
	# 随机数顺序固定（组按创建序、成员按节点号升序），同种子可复现。
	_invite_friends_pass()


## 节点此刻是否正处在占用型行为中（§10.4 行为耗时）—— 表现层权限判定用（如玩家操控）。
func is_present(i: int) -> bool:
	return not (i == _n - 1 and _player_absent)


func inventory_of(i: int) -> Dictionary:
	return {
		"books": int(_book[i]),
		"snacks": _snacks_remaining if is_player(i) else -1,
		"confiscated_books": int(_teacher.confiscated[i]),
		"exemption_tokens": int(_teacher.exemption_tokens[i]),
	}


func _start_leisure(i: int, kind: String) -> bool:
	return LeisureActions.start_leisure(self, i, kind)


func _leave_class() -> void:
	LeisureActions.leave_class(self)


func _class_affinity_settle() -> void:
	LeisureActions.class_affinity_settle(self)


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
	return (
		is_present(j) and not _sleeping[j] and _global_tick >= _busy_until[j] and not is_moving(j)
	)


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
	if _current_act[i] == "study":
		_study_acc[i] = 0.0
	_current_act[i] = behavior
	var occupy_target: bool = not is_player(j) or is_player(i) or _player_invitations.authorizes(i)
	if is_player(i) or (is_player(j) and occupy_target):
		_term_record.begin_action(behavior, i, [i, j])
	if occupy_target:
		if _current_act[j] == "study":
			_study_acc[j] = 0.0
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
	if members.has(_n - 1) and (is_player(actor) or _player_invitations.authorizes(actor)):
		_term_record.begin_action(behavior, actor, members)
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


## 学习（§8.23）：进入学习态。**不占时间槽**，靠 `_current_act` 表达；
## 起身 / 移动 / 相位切换即中断（`_cleanup_phase` 清 `_current_act`）。
func _do_study(i: int) -> void:
	if is_player(i):
		_term_record.begin_state("study")
	_current_act[i] = "study"
	# 2026-10-14 学习置占用（聊天机制规格 A）：busy_until 覆盖本段剩余时间，
	# 把「学习中」衔接进 _can_interact_with ↔ busy_until，否则会被聊天／搭话拉走。
	var remaining := int(str(_active_phases[_phase_index]["tick_count"])) - _tick_in_phase
	_busy_until[i] = _global_tick + remaining
	_stats["studies"] = int(_stats.get("studies", 0)) + 1
	_emit("event_happened", {"kind": "study", "i": i})


## 睡觉（§8.8）：玩家主动入睡 —— 与 NPC 同规则（段末由 `_settle_sleep` 一次性减压、
## 期间不被任何人交互）。原规格只写了 NPC 的概率触发。
func _do_sleep(i: int) -> void:
	if is_player(i):
		_term_record.begin_state("sleep")
	_sleeping[i] = true
	_current_act[i] = "sleep"
	_stats["sleeps"] = int(_stats["sleeps"]) + 1
	_emit("event_happened", {"kind": "sleep", "i": i})


## 表现层注入每个座位的**桌椅占位矩形**（世界 xz，Rect2）。内核只读。
func set_seat_zones(zones: Dictionary) -> void:
	_seat_world = zones.duplicate()


## 该节点是否**在自己的座位范围内**（§8.23：学习等「只能在自己座位上做」的行为的硬前置）。
## 未注入座位坐标时保守返回 true（离线 / 无场景时不该卡住行为）。
func in_own_seat(i: int) -> bool:
	if not _seat_world.has(i):
		return true
	# 范围 = 自己那张桌椅的**占位矩形**（§8.23）；矩形由表现层从 NavBlocker 注入
	var rect: Rect2 = _seat_world[i]
	return rect.has_point(Vector2(_pos_x[i], _pos_z[i]))


## 闲聊（会话种子，规格 B）：i 与 j 开聊，形成二人会话，他人可随后加入。
## NPC→玩家仍走邀请机制（拦截后等待玩家回应，不在此直接开聊）。
func _do_chat(i: int, j: int) -> void:
	if _player_invitations.intercept("chat", i, j, {}):
		return
	_start_conversation(i, j)


## 搭话（二人会话种子，含接纳判定，规格 E/I）：i 接近 j，j 按 p=σ((score−θ)/scale)
## 接纳则开聊（score 已删四维项）；拒绝则记单向拒绝事件，不占时间槽。无硬闸门。
## roll 可由调用方（玩家 UI）预掷（保证三拍展示与实际结算一致）。
func _do_chat_join(i: int, j: int, roll: float = -1.0) -> void:
	if _player_invitations.intercept("chat", i, j, {}):
		return
	var p := _join_probability(i, j)
	var choice: Variant = _player_invitations.choice_for(i)
	if choice != null:
		p = 1.0 if bool(choice) else 0.0
		roll = 0.0
	elif roll < 0.0:
		roll = _rng.random()
	if roll < p:
		_start_conversation(i, j)
		_stats["joins"] = int(_stats["joins"]) + 1
		_stats["join_accepts"] = int(_stats.get("join_accepts", 0)) + 1
	else:
		_apply_event(i, j, "reject_affinity")
		_apply_event(i, j, "reject_hostility")
		_apply_event(i, j, "reject_stress")
		_stats["joins"] = int(_stats["joins"]) + 1
		_stats["join_rejects"] = int(_stats.get("join_rejects", 0)) + 1
		_stats["skipped_events"] = int(_stats["skipped_events"]) + 1


# ------------------------------------------------------------------ 多人聊天会话子系统（2026-10-14 重构：2→3→4 递进加入）
## 二人开聊（会话种子，规格 B）：形成会话 {i,j}，逐人独立计时，他人可随后加入。
func _start_conversation(i: int, j: int) -> void:
	var members: Array = [i, j]
	members.sort()
	var conv := {"members": members}
	_conversations.append(conv)
	_conv_of[i] = conv
	_conv_of[j] = conv
	_in_conversation[i] = true
	_in_conversation[j] = true
	_occupy_chat(i)
	_occupy_chat(j)
	_settle_chat_pair(i, j)
	_stats["chats"] = int(_stats["chats"]) + 1
	# 真实共同活动登记（显示层，不消耗 RNG）
	_sessions.begin_or_join("chat", members, _conv_until(conv))


## 聊天时长：base × uniform[jitter_min, jitter_max]，逐人独立（规格 ③）。
## MtRandom 无 uniform：等价 CPython `random.uniform` 内联为 lo + (hi−lo)·random()。
func _chat_duration() -> int:
	var base := int(_behaviors.get("chat", {}).get("duration", 30))
	var lo := float(_thresholds_lookup.get("chat_duration_jitter_min", 0.8))
	var hi := float(_thresholds_lookup.get("chat_duration_jitter_max", 1.2))
	return maxi(1, int(base * (lo + (hi - lo) * _rng.random())))


## 把 i 置为聊天占用（独立时长）。不写 busy_phase —— 聊天由 _settle_conversations /
## _interrupt_conversations 专责，不经过「到期结算 / 被打断」两套通用协议。
func _occupy_chat(i: int) -> void:
	_current_act[i] = "chat"
	_busy_until[i] = maxi(int(_busy_until[i]), _global_tick + _chat_duration())
	_busy_act[i] = "chat"


## initiator 与 existing 之间的聊天结算。与旧 do_chat 同口径：发起方多一次 topic_stress 减压。
## 老师版：删除 topic_trust 与观测（无信任/信念轴）。
func _settle_chat_pair(initiator: int, existing: int) -> void:
	_apply_event(initiator, existing, "topic_affinity")
	_apply_event(initiator, existing, "topic_stress")
	_apply_event(existing, initiator, "topic_affinity")


## k 成功加入：加入者作为本次「发起」方，对每位现有成员做一次定向聊天结算。
func _add_member_to_conversation(k: int, conv: Dictionary) -> void:
	var sid := _sessions.session_of(int(conv["members"][0]))
	var members: Array = conv["members"]
	members.append(k)
	members.sort()
	conv["members"] = members
	_conv_of[k] = conv
	_in_conversation[k] = true
	_occupy_chat(k)
	for m in members:
		if int(m) != k:
			_settle_chat_pair(k, int(m))
	_stats["chat_joins"] = int(_stats.get("chat_joins", 0)) + 1
	_stats["chat_max_size"] = maxi(int(_stats.get("chat_max_size", 0)), members.size())
	# 真实共同活动：并入既有会话（显示层，不消耗 RNG）
	if sid >= 0:
		_sessions.join(sid, k, _conv_until(conv))


## m 离开会话（自然到期或解散）。不清 _busy_until —— 已到期，无需清零。
func _leave_conversation(m: int, conv: Dictionary) -> void:
	var sid := _sessions.session_of(m)
	if sid >= 0:
		_sessions.leave(sid, m)
	(conv["members"] as Array).erase(m)
	_conv_of[m] = null
	_in_conversation[m] = false
	_current_act[m] = null
	_busy_act[m] = null
	_stats["chat_leaves"] = int(_stats.get("chat_leaves", 0)) + 1


## 逐人离场（规格 G）：每人独立计时，到期即离场；成员 < 2 则会话解散。
func _settle_conversations() -> void:
	for conv in _conversations.duplicate():
		var members: Array = (conv["members"] as Array).duplicate()
		for m in members:
			if int(_busy_until[int(m)]) <= _global_tick:
				_leave_conversation(int(m), conv)
		if (conv["members"] as Array).size() < 2:
			for m in (conv["members"] as Array).duplicate():
				_leave_conversation(int(m), conv)
			_conversations.erase(conv)


## 铃响打断（规格 A/G）：结束所有未完成会话；仍在聊的人付中断代价。
func _interrupt_conversations() -> void:
	var cost := float(_probs.get("interrupted_stress", 0.0))
	for conv in _conversations.duplicate():
		var members: Array = (conv["members"] as Array).duplicate()
		var sid := _sessions.session_of(int(members[0]))
		for m in members:
			var mi := int(m)
			if int(_busy_until[mi]) > _global_tick and cost > 0.0:
				_stress[mi] = _clamp100(_stress[mi] + cost)
				_stats["interrupts"] = int(_stats.get("interrupts", 0)) + 1
			_conv_of[mi] = null
			_in_conversation[mi] = false
			_current_act[mi] = null
			_busy_act[mi] = null
			_busy_until[mi] = 0
		if sid >= 0:
			_sessions.end(sid)
		_conversations.erase(conv)


## 会话统一结束点（显示层近似）：取成员中最晚的 busy_until。逐人精确计时由 _conversations 负责。
func _conv_until(conv: Dictionary) -> int:
	var until := 0
	for m in conv["members"]:
		until = maxi(until, int(_busy_until[int(m)]))
	return until


# ------------------------------------------------------------------ 通用加入（§9.1.1–§9.1.4，2026-10-15）
## 找伴、接受、加入与带朋友共用一套规则，不限于聊天（主文档 §9.1.4）：
##   · 找伴：发起者读「我对他」的有向好感，选最高且可参与者；正在活动也可以被邀请；
##   · 接受：现有成员逐人确定投票（好感−敌对 ≥ join_vote_margin 投同意，严格过半，平票拒绝）；
##   · 决定做什么：活动相同就合流；不同时好感更高的一方跟随另一方（相等不合流）；
##   · 加入：参与同一活动，按实际参与时间获得效果，原活动已产生的收益保留；
##   · 带朋友：成员按找伴规则邀请朋友，仍走同一套接受规则。
## 铁律：投票只读真值有向关系（§9.1.2 判定路径），不掷概率、不叠隐藏修正；
## 拒绝 / 满员 / 相等不合流都不占用发起者（拒绝不代表活动已经发生）。


func _join_margin() -> float:
	## §9.1.2 个人同意门槛（data：join_vote_margin；不得硬编码）。
	return float(_thresholds_lookup.get("join_vote_margin", 10.0))


func _join_cap() -> int:
	## 同一场活动的人数上限（data：join_max_members；防同一决策点无限连锁邀请）。
	return int(_thresholds_lookup.get("join_max_members", 4))


func _invite_friend_p() -> float:
	## 带朋友：活动组成员每决策点尝试邀请朋友的概率（data：invite_friend_p）。
	return float(_probs.get("invite_friend_p", 0.0))


func _join_blocked(j: int) -> bool:
	## j 此刻不可被邀请（**条件不满足**，不算关系拒绝，§9.1.2/§9.1.4）：
	## 睡觉、不在场、出门、正在走动；崩溃等不可中断状态同理。
	return (
		_sleeping[j]
		or not is_present(j)
		or _current_act[j] == "leave_class"
		or is_moving(j)
		or (_busy_act[j] == "move" and _global_tick < _busy_until[j])
	)


func _find_partner(i: int, kind: String) -> int:
	## 找伴（§9.1.1/§9.1.4）：自己对其好感最高、且可参与的人；正在活动也可以被邀请。
	## 读「发起者 → 候选者」的有向好感，不取双向平均；并列取最低节点号
	## （data：join_tie_break = 0，同种子可复现）。不消耗随机数。
	var best := -1
	var best_a := 0.0
	var has_best := false
	for j in range(_n):
		if j == i or _join_blocked(j):
			continue
		if kind == "chat" and not chat_pair_in_range(i, j):
			continue
		var a := float(_a[i * _n + j])
		if not has_best or a > best_a:
			best = j
			best_a = a
			has_best = true
	return best


func _join_activity_of(j: int) -> Array:
	## j 的当前活动（只读，通用加入视角）。返回 [kind, group]；group 为 null 表示独自活动。
	## "idle" = 空闲；"solo" = 独自的不可共享活动（听歌/读课外书，§9.1.4 未开放加入）。
	if _conv_of[j] != null:
		return ["chat", _conv_of[j]]
	if _rough_of[j] != null:
		return ["roughhouse", _rough_of[j]]
	if _busy_act[j] == "eat_snack" and _global_tick < _busy_until[j]:
		return ["snack", _snack_of[j]]
	if _current_act[j] == "study" and _global_tick < _busy_until[j]:
		return ["study", _study_of[j]]
	if (
		(_busy_act[j] == "listen_music" or _busy_act[j] == "read_book")
		and _global_tick < _busy_until[j]
	):
		return ["solo", null]
	return ["idle", null]


func _vote_accept(members: Array, joiner: int) -> Dictionary:
	## §9.1.2 确定投票：成员 m 读自己对加入者的有向关系，好感−敌对 ≥ 门槛投同意；
	## 同意票严格超过现有成员总数的一半才接受（平票拒绝）。不掷概率、不叠隐藏修正。
	var margin := _join_margin()
	var yes: Array = []
	var no: Array = []
	for m in members:
		var mi := int(m)
		if float(_a[mi * _n + joiner]) - float(_h[mi * _n + joiner]) >= margin:
			yes.append(mi)
		else:
			no.append(mi)
	return {"ok": yes.size() * 2 > members.size(), "yes": yes, "no": no}


func _log_join_event(
	joiner: int,
	members: Array,
	stage: String,
	activity: String,
	yes: Array,
	no: Array,
	extra: Dictionary
) -> void:
	## 只读观察（§9.1.4 交接 3）：区分条件不满足 / 关系拒绝 / 相等不合流 / 跟随 / 成功加入，
	## 记录投票方向；观察层仅展示，不写矩阵。
	(
		_join_log
		. append(
			{
				"tick": _global_tick,
				"joiner": joiner,
				"members": members.duplicate(),
				"stage": stage,
				"activity": activity,
				"yes": yes.duplicate(),
				"no": no.duplicate(),
				"extra": extra.duplicate(),
			}
		)
	)


func _reject_join(
	i: int, anchor: int, members: Array, activity: String, yes: Array, no: Array
) -> void:
	## 投票被拒（关系拒绝）：对齐旧搭话拒绝口径 —— 亲和/压力记在发起者→锚点，
	## 敌对反馈对全体现有成员（§10.7）。拒绝不占用发起者。
	_apply_event(i, anchor, "reject_affinity")
	for m in members:
		_apply_event(i, int(m), "reject_hostility")
	_apply_event(i, anchor, "reject_stress")
	_stats["join_rejects"] = int(_stats.get("join_rejects", 0)) + 1
	_log_join_event(i, members, "vote_reject", activity, yes, no, {"anchor": anchor})


func _propose_activity(i: int, j: int, kind: String) -> bool:
	## i（空闲发起者）向 j 提议 / 申请加入活动 kind（§9.1.4 决策树）。
	## 返回 true = i 已被占用（成事）；false = 未占用（条件不满足 / 关系拒绝 / 相等不合流）。
	## 玩家伙伴走既有邀请机制（玩家自己决定是否接受），不进入投票。
	_stats["joins"] = int(_stats["joins"]) + 1
	if j == _n - 1:
		if kind == "chat":
			_do_chat(i, j)
		else:
			_do_roughhouse(i, j)
		return true
	var act := _join_activity_of(j)
	var akind: String = act[0]
	var group: Variant = act[1]
	if akind == "idle":
		# 两人新建活动：被邀请者是唯一现有成员，投票定夺（§9.1.2）
		var vote := _vote_accept([j], i)
		if not vote["ok"]:
			_reject_join(i, j, [j], kind, vote["yes"], vote["no"])
			return false
		if kind == "chat":
			_do_chat(i, j)
		else:
			_do_roughhouse(i, j)
		_stats["join_accepts"] = int(_stats.get("join_accepts", 0)) + 1
		_log_join_event(i, [j], "joined", kind, vote["yes"], vote["no"], {})
		return true
	if akind == kind:
		# 活动相同就合流：申请加入原活动（全体成员投票）
		return _apply_join_group(i, j, akind, group)
	var members := _group_members_sorted(group, j)
	if members.size() >= 2:
		# 已有多人活动：新人跟随原活动，不重新比较好感改变整组活动（§9.1.4）
		return _apply_join_group(i, j, akind, group)
	# j 独自活动且活动不同：先接纳，再比较单向好感决定谁跟随（§9.1.4 表）
	var vote := _vote_accept([j], i)
	if not vote["ok"]:
		_reject_join(i, j, [j], kind, vote["yes"], vote["no"])
		return false
	var a_i := float(_a[i * _n + j])
	var a_j := float(_a[j * _n + i])
	if a_i == a_j:
		# 两个方向好感相等：各自保持活动，本次不合流
		_log_join_event(i, [j], "tie_no_merge", kind, vote["yes"], vote["no"], {})
		return false
	if a_j > a_i:
		# j 更在意 i：j 跟随 i 的活动（放弃原活动；学业收益保留）
		_switch_activity(j, kind, i)
		_stats["join_accepts"] = int(_stats.get("join_accepts", 0)) + 1
		_log_join_event(i, [j], "follow", kind, vote["yes"], vote["no"], {"follower": j})
		return true
	# i 更在意 j：i 加入 j 的原活动（原活动须可加入；听歌/读书未开放共享）
	if not ("chat" == akind or "roughhouse" == akind or "study" == akind or "snack" == akind):
		_log_join_event(
			i, [j], "condition_fail", kind, vote["yes"], vote["no"], {"reason": "unshared"}
		)
		return false
	return _apply_join_group(i, j, akind, group)


func _apply_join_group(i: int, anchor: int, akind: String, group: Variant) -> bool:
	## i 加入 anchor 所在的活动组（§9.1.4 加入）：全体成员确定投票；满员属条件不满足。
	## 加入后与原成员做同一活动：按实际参与时间获得效果；不重置老成员计时、
	## 不补发新人加入前的收益、不重复结算旧成员互动（交接 2）。
	var grp: Dictionary = group if group is Dictionary else _ensure_group(akind, anchor)
	if grp.is_empty():
		return false
	var members := (grp["members"] as Array).duplicate()
	members.sort()
	if members.has(_n - 1):
		# 含玩家的活动不参与 NPC 自主加入（玩家交互走邀请机制，§9.4 同口径）
		_log_join_event(i, members, "condition_fail", akind, [], [], {"reason": "player_session"})
		return false
	if members.size() >= _join_cap():
		_log_join_event(i, members, "condition_fail", akind, [], [], {"reason": "full"})
		return false
	var vote := _vote_accept(members, i)
	if not vote["ok"]:
		_reject_join(i, anchor, members, akind, vote["yes"], vote["no"])
		return false
	# 加入前先脱离当前独自活动（占用被新活动接管；未完成单位不结算，学业收益保留）
	_leave_solo_activity(i)
	if akind == "chat":
		_add_member_to_conversation(i, grp)
	elif akind == "roughhouse":
		_join_roughhouse(i, grp)
	elif akind == "study":
		_join_study(i, grp)
	else:
		_join_snack(i, grp)
	_joined_tick[i] = _global_tick
	_stats["join_accepts"] = int(_stats.get("join_accepts", 0)) + 1
	_log_join_event(i, members, "joined", akind, vote["yes"], vote["no"], {"anchor": anchor})
	return true


func _group_members_sorted(group: Variant, solo: int) -> Array:
	## 组成员升序；group 为 null（独自活动）时返回 [solo]。
	if group is Dictionary and (group["members"] as Array).size() > 0:
		var out: Array = (group["members"] as Array).duplicate()
		out.sort()
		return out
	return [solo]


func _ensure_group(akind: String, j: int) -> Dictionary:
	## j 独自做 akind 活动时，为其补建活动组（通用加入的成员管理载体；只登记不结算）。
	if akind == "chat":
		return _conv_of[j] if _conv_of[j] != null else {}
	if akind == "study":
		if _study_of[j] == null:
			var grp := {"members": [j]}
			_study_groups.append(grp)
			_study_of[j] = grp
		return _study_of[j]
	if akind == "snack":
		if _snack_of[j] == null:
			var grp := {"members": [j], "provider": j}
			_snack_groups.append(grp)
			_snack_of[j] = grp
		return _snack_of[j]
	if akind == "roughhouse":
		if _rough_of[j] == null:
			var grp := {"members": [j]}
			_rough_groups.append(grp)
			_rough_of[j] = grp
		return _rough_of[j]
	return {}


func _register_rough_pair(i: int, j: int) -> void:
	## 打闹结组（打闹行为结算后调用）：登记打闹组，后续加入者与全体成员互相结算。
	var grp: Variant = _rough_of[i] if _rough_of[i] != null else _rough_of[j]
	if grp == null:
		grp = {"members": []}
		_rough_groups.append(grp)
	(grp["members"] as Array).append(i)
	if not (grp["members"] as Array).has(j):
		(grp["members"] as Array).append(j)
	(grp["members"] as Array).sort()
	_rough_of[i] = grp
	_rough_of[j] = grp


func _join_roughhouse(i: int, grp: Dictionary) -> void:
	## 加入打闹组：与每位现有成员互相结算一次打闹好感（旧成员之间不重算）。
	var members: Array = (grp["members"] as Array).duplicate()
	members.sort()
	for m in members:
		_apply_event(i, int(m), "roughhouse_affinity")
		_apply_event(int(m), i, "roughhouse_affinity")
	_occupy(i, i, "roughhouse")
	(grp["members"] as Array).append(i)
	(grp["members"] as Array).sort()
	_rough_of[i] = grp
	_stats["roughhouse"] = int(_stats["roughhouse"]) + 1
	_emit("event_happened", {"kind": "roughhouse", "i": i, "mode": "join"})


func _join_study(i: int, grp: Dictionary) -> void:
	## 加入学习组：进入学习态（各自按真实学习单位结算，不新增讲题加成，§9.1.4 表）。
	_do_study(i)
	(grp["members"] as Array).append(i)
	(grp["members"] as Array).sort()
	_study_of[i] = grp


func _join_snack(i: int, grp: Dictionary) -> void:
	## 加入零食分享（§9.1.4 表）：加入者无需自带零食；正常娱乐效果；
	## 自然完成一个共同进食单位后，对分享者结算一次分享好感（见 _settle_finished_actions）。
	_occupy(i, i, "eat_snack")
	_snack_provider[i] = grp["provider"]
	(grp["members"] as Array).append(i)
	(grp["members"] as Array).sort()
	_snack_of[i] = grp


func _switch_activity(j: int, kind: String, i: int) -> void:
	## j 放弃当前独自活动、跟随 i 的新活动（§9.1.4 不同活动跟随）。
	## 活动切换不清空既有学业收益（§9.1.4）：StudyAcc 原样保留；未完成的娱乐单位不结算。
	var acc := float(_study_acc[j])
	_leave_solo_activity(j)
	_study_acc[j] = acc
	if kind == "chat":
		_do_chat(i, j)
	else:
		_do_roughhouse(i, j)


func _leave_solo_activity(f: int) -> void:
	## f 在决策边界放弃当前独自活动（跟随 / 被带入新活动，§9.1.4）：
	## 清占用与未完成进度；组内成员不走此路径（不同时参与多个活动）。
	if _study_of[f] != null:
		_dissolve_from_group(_study_groups, _study_of, f)
	if _snack_of[f] != null:
		_dissolve_from_group(_snack_groups, _snack_of, f)
	_snack_provider[f] = null  # 未完成的进食单位不结算分享好感
	_busy_until[f] = 0
	_busy_phase[f] = -1
	_busy_act[f] = null
	_current_act[f] = null


func _dissolve_from_group(groups: Array, of: Array, f: int) -> void:
	## f 离开所在活动组；剩余成员少于 2 人则整组解散（各自继续独自活动）。
	var grp: Dictionary = of[f]
	(grp["members"] as Array).erase(f)
	of[f] = null
	if (grp["members"] as Array).size() < 2:
		for m in (grp["members"] as Array).duplicate():
			of[int(m)] = null
		groups.erase(grp)


func _invite_friends_pass() -> void:
	## 带朋友（§9.1.3/§9.1.4）：活动组成员按找伴规则邀请朋友加入当前活动。
	## 每人每个决策点最多发起一次邀请；本决策点新加入者从下一决策点起才能带朋友；
	## 朋友仍须满足活动参与条件，并由全部现有成员按同一套规则投票（邀请者不能替
	## 其他成员保证接纳）。随机数顺序固定（组按创建序、成员按节点号升序）。
	var p := _invite_friend_p()
	if p <= 0.0:
		return
	var cap := _join_cap()
	for akind in ["chat", "roughhouse", "study", "snack"]:
		var groups: Array = _groups_of_kind(akind)
		for grp in groups:
			if (grp["members"] as Array).has(_n - 1) or (grp["members"] as Array).size() >= cap:
				continue
			var members: Array = (grp["members"] as Array).duplicate()
			members.sort()
			for m in members:
				var mi := int(m)
				if _joined_tick[mi] >= _global_tick:
					continue
				if _rng.random() >= p:
					continue
				var f := _find_friend_outside(mi, grp)
				if f < 0:
					continue
				if _apply_join_group(f, mi, akind, grp):
					_stats["invite_friends"] = int(_stats.get("invite_friends", 0)) + 1


func _groups_of_kind(akind: String) -> Array:
	## 当前全部活动组（按创建序）：聊天会话 + 打闹组 + 学习组 + 零食分享组。
	match akind:
		"chat":
			return _conversations
		"roughhouse":
			return _rough_groups
		"study":
			return _study_groups
		"snack":
			return _snack_groups
	return []


func _find_friend_outside(m: int, grp: Dictionary) -> int:
	## m 的组外最佳朋友（§9.1.1 找伴规则）：不邀请组内成员、不拉正在别组的人
	## （不同时参与多个活动）、不邀请玩家（玩家走邀请 UI）。并列取最低节点号。
	var best := -1
	var best_a := 0.0
	var has_best := false
	for f in range(_n - 1):
		if f == m or (grp["members"] as Array).has(f) or _join_blocked(f):
			continue
		if (
			_conv_of[f] != null
			or _rough_of[f] != null
			or _study_of[f] != null
			or _snack_of[f] != null
		):
			continue
		var a := float(_a[m * _n + f])
		if not has_best or a > best_a:
			best = f
			best_a = a
			has_best = true
	return best


func _settle_groups() -> void:
	## 活动组维护（每 tick，只读 busy 状态）：成员活动到期即离组；少于 2 人解散。
	## 统一管理成员但保留逐人加入时间与退出（§9.1.4 交接 2）—— 不重置老成员计时。
	_prune_groups(_rough_groups, _rough_of, "roughhouse")
	_prune_groups(_study_groups, _study_of, "study")
	_prune_groups(_snack_groups, _snack_of, "snack")


func _prune_groups(groups: Array, of: Array, akind: String) -> void:
	for grp in groups.duplicate():
		var members: Array = (grp["members"] as Array).duplicate()
		for m in members:
			var mi := int(m)
			var active := false
			if akind == "roughhouse":
				active = _busy_act[mi] == "roughhouse" and _busy_until[mi] > _global_tick
			elif akind == "study":
				active = _current_act[mi] == "study" and _busy_until[mi] > _global_tick
			else:
				active = _busy_act[mi] == "eat_snack" and _busy_until[mi] > _global_tick
			if not active:
				(grp["members"] as Array).erase(mi)
				of[mi] = null
		if (grp["members"] as Array).size() < 2:
			for m in (grp["members"] as Array).duplicate():
				of[int(m)] = null
			groups.erase(grp)


func _clear_join_groups() -> void:
	## 相位边界：清空全部活动组与未完成的分享关联（未完成单位不结算，§9.1.4）。
	_rough_groups = []
	_study_groups = []
	_snack_groups = []
	for i in range(_n):
		_rough_of[i] = null
		_study_of[i] = null
		_snack_of[i] = null
		_snack_provider[i] = null


## 追逐打闹（§9.2）：参与者互相好感↑（老师版去四维门槛与旁观者敌对，只留参与者好感）。
func _do_roughhouse(i: int, j: int) -> void:
	_behavior_registry.execute(&"roughhouse", i, j)


# ------------------------------------------------------------------ 玩家行动（D11 缺口③）
## 玩家显式行动：来源固定玩家（n-1）、目标由玩家指定，走与 NPC 相同的 do_* 统一影响公式，
## 与 NPC 共用同一套「能不能做」门槛（§3.3 相位权限、§10.8 目标睡眠）——
## 内核策划符合性审查 P1-02：不能只靠 UI 隐藏按钮，内核入口必须自己拒绝。
func _player_action_error(kind: String, target: int, me: int) -> String:
	if not is_present(me):
		return "player_absent"
	if kind in PLAYER_SELF_KINDS:
		return LeisureActions.action_error(self, kind, me)
	if target < 0 or target >= _n or target == me:
		return "invalid_target"
	if not PLAYER_KINDS.has(kind):
		return "unknown_kind"
	if _sleeping[me] or _global_tick < _busy_until[me] or is_moving(me):
		return "player_busy"
	if not _allowed(kind):
		return "phase_not_allowed"
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
	if kind != "study" and _current_act[me] == "study":
		_current_act[me] = null
		_study_acc[me] = 0.0
	if PLAYER_SELF_KINDS.has(kind):
		var teacher_feedback: bool = (
			kind == "read_book" and _teacher.present and not _teacher.exempt_this_visit[me]
		)
		match kind:
			"study":
				_do_study(me)
			"sleep":
				_do_sleep(me)
			"leave_class":
				_leave_class()
			_:
				_start_leisure(me, kind)
		return {
			"ok": true,
			"kind": kind,
			"accepted": true,
			"confiscated": kind == "read_book" and _busy_act[me] != "read_book",
			"teacher_feedback": teacher_feedback,
		}
	var a_before := _a[target * _n + me]  # 目标→玩家的好感（行动前的反应基线）
	var h_before := _h[target * _n + me]
	match kind:
		"roughhouse":
			_do_roughhouse(me, target)
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
	if is_player(i):
		_term_record.moving(moving, _phase == "break")
	if moving and _current_act[i] == "study":
		_current_act[i] = null
		_study_acc[i] = 0.0
	_player_interactions.set_moving(i, moving)


func is_moving(i: int) -> bool:
	return _player_interactions.is_moving(i)


## 某人此刻所在共同活动（不在任何会话返回 -1）。
func session_of(i: int) -> int:
	return int(_sessions.session_of(i))


# ------------------------------------------------------------------ 规则辅助（D8 涓流依赖，D10 行为决策复用）
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
	if LEISURE_KINDS.has(behavior) or behavior == "leave_class":
		return str(time_snapshot()["kind"]) == "break"
	var pid := ""
	if _phase_index >= 0 and _phase_index < _phase_order.size():
		pid = str(_phase_order[_phase_index]["phase_id"])
	var rules: Array = _phase_rules.get(pid, ["all"])
	if rules.has("all"):
		return true
	var banned := ["chat", "roughhouse", "move"]
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
	var sat_count := 0
	for v in aff:
		if v >= 95.0:
			sat_count += 1
	var saturated := float(sat_count) / aff.size()

	var lines: Array = []
	lines.append("=== 内核运行统计（seed=%d, 天数=%d, 节点=%d）===" % [_seed, _day - 1, n])
	lines.append(
		(
			"  好感：min %.1f / 中位 %.1f / 均值 %.1f / max %.1f"
			% [aff[0], aff[aff.size() / 2], mean, aff[aff.size() - 1]]
		)
	)
	lines.append("  接近饱和(>=95)比例：%.1f%%" % [saturated * 100.0])
	lines.append(
		(
			"  事件 %d 次（闲聊 %d / 搭话 %d / 打闹 %d）"
			% [_stats["events"], _stats["chats"], _stats["joins"], _stats.get("roughhouse", 0)]
		)
	)
	lines.append("  睡着 %d 人次 | 被打断 %d" % [_stats.get("sleeps", 0), _stats.get("interrupts", 0)])
	lines.append("  去重跳过 %d 次" % _stats["dedup_skips"])
	lines.append(
		(
			"  压力爆发 %d 次（平均每 %.1f 天一次）"
			% [_stats["bursts"], float(_day - 1) / float(maxi(1, _stats["bursts"]))]
		)
	)
	return "\n".join(lines)


# ------------------------------------------------------------------ 只读访问器（§4.1）
func seed() -> int:
	return _seed


## 期末只读记录。复制数据，UI不可借此修改内核或历史。
func term_record() -> Dictionary:
	return _term_record.snapshot(self)


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


## 行为基础概率（来自 data/rules/behavior_probs.csv）；未注册返回 0.0。
func behavior_base_p(behavior: String) -> float:
	return float(_probs.get(behavior, 0.0)) * _teacher.multiplier(behavior)


## 某人此刻在做什么（UI 用）：真实行为名（如 "study"）；空闲才是空串。
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


func exam_banner(day: int) -> String:
	if _exam == null:
		return ""
	return _exam.banner(day)


func exam_report(day: int) -> String:
	if _exam == null:
		return ""
	return _exam.report_text(day)


func exemption_tokens(i: int) -> int:
	if _exam == null:
		return 0
	return _exam.tokens_of(i)


func _alias_list() -> PackedStringArray:
	var names := PackedStringArray()
	names.resize(_n)
	for i in _n:
		names[i] = alias(i)
	return names


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


## 老师位置是环境事实，不暴露 NPC 关系数据。
func teacher_state() -> Dictionary:
	return _teacher.snapshot()
