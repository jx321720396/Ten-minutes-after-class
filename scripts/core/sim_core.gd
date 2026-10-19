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
## 索引约定：n = 本局入局学生数（老师版 16 名学生、无玩家节点，末位也是普通学生；
## 人数由调用方直接给出，正式玩法取 `data/rules/roster.csv` 的 16，角色池见 `characters/seeds.csv`）；矩阵平铺 A[i][j] → _a[i*n+j]；
##
## 老师版（2026-10-14）：删除四维/透明度/信任及信念矩阵、传导、深层敌对，以及从众/调侃/举报/
## 排挤/道歉/安慰/传纸条/学习圈/书礼/提问/讲题等学生版依赖子系统；只保留 A/H + 压力/动力/学业收益/成绩
## 与公开专属被动。行为集 = 老师版 §9.2 + §9.4（多人聊天 / 搭话 / 打闹 / 学习 / 娱乐 / 崩溃 / 座位结算）。

const AXES := ["affinity", "hostility"]
## 娱乐行为 → rules/leisure.csv 与 behavior_probs.csv 的前缀（学生自主娱乐，§9.2）
const LEISURE_KINDS := {
	"listen_music": "music", "eat_snack": "snack", "read_book": "book", "play_phone": "phone"
}
const _NEVER := -999  # 时间哨兵：「从未发生」（Python 参考用 -10**9 / -999；语义等价，统一 -999）
const _FOREVER := 1000000000  # 时间哨兵：「忙碌到远超本段」（睡觉等整段占用的 busy_until，对齐 Python 10**9）
const OBSERVER_LAYER = preload("res://scripts/systems/observer/observer_layer.gd")
const PASSIVES = preload("res://scripts/core/passives.gd")
const BEHAVIOR_CONTEXT = preload("res://scripts/systems/behaviors/behavior_context.gd")
const BEHAVIOR_REGISTRY = preload("res://scripts/systems/behaviors/behavior_registry.gd")
const ACTIVITY_SESSIONS = preload("res://scripts/core/activity_sessions.gd")
const FREE_ROAM = preload("res://scripts/core/free_roam.gd")
const INTERACTION_SPACE = preload("res://scripts/core/interaction_space.gd")
## 闲聊空间几何（2026-10-16 从已删的 rules/player_interaction.csv 迁出，见 rules/chat_space.csv）
const CHAT_SPACE_TABLE := "rules/chat_space"
## 老师版状态与结算配置（2026-10-16，《老师版规则合并稿 D01至D07》D01 / D02 / D03）
const PSYCHE_TABLE := "rules/psyche"
const ACTIVITIES_TABLE := "rules/activities"
const TEACHER_COMMANDS_TABLE := "rules/teacher_commands"
const SEAT_RELATIONS_TABLE := "rules/seat_relations"
const HARM_TABLE := "rules/harm"
const RISK_TABLE := "rules/risk"
const EXAM_SETTLE := preload("res://scripts/core/exam_settle.gd")
const HARM_EVENTS := preload("res://scripts/core/harm_events.gd")
const RISK_MONITOR := preload("res://scripts/core/risk_monitor.gd")
const TERM_RECORD := preload("res://scripts/core/term_record.gd")

var _term_record: RefCounted

var _behavior_context: RefCounted
var _behavior_registry: RefCounted
## 真实共同活动（谁和谁此刻真在一起）与交互几何
var _sessions: ActivitySessions
var _space: InteractionSpace
## 闲聊空间几何（rules/chat_space.csv，只读）
var _chat_space: Dictionary = {}
## 表现层注入的「正在移动」标记：内核不据此改矩阵，只作交互前置（§10.5）
var _moving: Array = []
## 场景注入的本座位入口世界坐标；与座位表的行列分开，不引用节点。
var _seat_world_positions: Dictionary = {}
var _scene_space_required := false

# —— 关系 / 个体状态（float64 平铺，与 Python 逐位一致）——
var _a := PackedFloat64Array()  # 好感 A  n*n
var _h := PackedFloat64Array()  # 敌对 H  n*n
var _stress := PackedFloat64Array()  # 压力 Stress  n
var _grade := PackedFloat64Array()  # 成绩 grade  n（§17.1）
var _study_acc := PackedFloat64Array()  # 学习时长累加器 study_acc  n（§17.1.2）
var _exam: RefCounted  # 周考 / 期末考（§19.1），脚本见 exam_settle.gd

var _rng: MtRandom
var _seed := 0
var _config_fingerprint := ""  # 本局配置摘要（存档校验用，构造时算好）
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
var _study_start_tick: Array = []  # 学习开始 tick（请教「过半禁加入」：原学习者进度基准）
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
## 崩溃休息锁（§5.3）：崩溃当天只睡觉、不学习不社交、不参加座位结算；次日跨天时特殊恢复并解除。
var _resting: Array = []
var _vol_log: Array = []
var _settled: Dictionary = {}
var _stats: Dictionary = {}
## 每个节点的座位站位世界坐标（表现层注入；内核只读）
var _seat_world: Dictionary = {}
var _leisure: Dictionary = {}
var _book: Array = []
var _teacher := TeacherPatrol.new()
## 公开专属被动（主文档 §10）：角色 → 被动读 data/rules/passives.csv，数值读 rules/passive_params.csv。
var _passives: RefCounted
## 老师命令与时间规则（D03）：召唤 / 遣返 / 办公室聊天 / 去教室 / 调座位 + 上课延后
var _teacher_commands := TeacherCommands.new()
# —— 老师版状态层（《老师版规则合并稿 D01至D07》D01 / D02）——
## 动力（0–100）：>60 进入学习状态、<30 进入游戏状态，之间为自由状态（D01）
var _vitality := PackedFloat64Array()
## 今日学业收益（有符号；按整数单位累计，跨天并入成绩后清零，D01/D02）
var _gain_today := PackedFloat64Array()
## 崩溃标记：压力 >90 进入，<70 恢复；一次连续崩溃只计一次（D01 / D06）
var _broken: Array = []
## 本课间状态："study" / "play" / "free"（段首按动力决定；中途跨线也进入并锁定，见 FreeRoam）
var _phase_state: Array = []
## 本段「已尝试加入好感最高者」的标记（段序号 = day*10+phase_index）；只作冷却，不存档。
var _best_join_phase := PackedInt32Array()
## 学习／娱乐／游戏的结算游标（按秒累计，每满一个单位结算一次；D02）
var _settle_acc: Array = []
## 配置：rules/psyche.csv（心理状态与跨天）、rules/activities.csv（单位与结算）
var _psyche: Dictionary = {}
var _acts: Dictionary = {}
## 课间活动效果（2026-10-18）：behavior → {stress_per_unit, stress_once, grade_once, vitality_once}。
## 数值在 rules/leisure_effects.csv；此前 6 种娱乐都是「每 10 秒 −5 压力」，选择没有区别。
var _leisure_effects: Dictionary = {}
var _seat_rel: Dictionary = {}
var _harm_events: RefCounted  # 伤害事件（D07），脚本见 harm_events.gd
## D07 §10：本课间被老师制止（现场制止 / 调解 / 召唤到办公室）的学生，不能主动伤害。
var _phase_stopped: Array = []
var _risk: RefCounted  # 风险判定 / 预警 / 退学（D06），脚本见 risk_monitor.gd


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
	_n = want
	var n := _n

	_load_config(tables)
	_config_fingerprint = SimCoreSerializer.config_fingerprint(tables)

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

	_alloc(n)
	_passives = PASSIVES.new()
	_passives.configure(tables, _character_ids())

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

	# 真实共同活动 + 交互几何（构造不消费随机数）
	_sessions = ACTIVITY_SESSIONS.new()
	_space = INTERACTION_SPACE.new()
	_term_record = TERM_RECORD.new()
	_term_record.configure(self, tables)
	_teacher_commands.configure(
		_params(tables, TEACHER_COMMANDS_TABLE), _acts, tables.get("rules/voice", {})
	)


func _load_config(tables: Dictionary) -> void:
	_teacher.configure(_params(tables, "rules/teacher"), _n)
	_leisure = _params(tables, "rules/leisure")
	_chat_space = _params(tables, CHAT_SPACE_TABLE)
	_psyche = _params(tables, PSYCHE_TABLE)
	_acts = _params(tables, ACTIVITIES_TABLE)
	_leisure_effects = LeisureActions.build_effects(tables)
	_seat_rel = _params(tables, SEAT_RELATIONS_TABLE)
	_harm_events = HARM_EVENTS.new()
	_harm_events.configure(_params(tables, HARM_TABLE))
	_risk = RISK_MONITOR.new()
	_risk.configure(_params(tables, RISK_TABLE), _n)
	_p = _params(tables, "rules/transmission")
	_kp = _params(tables, "rules/kernel_params")
	_grade_bands = TableBuilders.grade_bands(tables)
	_probs = TableBuilders.behavior_probs(tables)
	_thresholds_lookup = TableBuilders.thresholds(tables)
	_behaviors = TableBuilders.behaviors(tables)
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
	_vitality.resize(n)
	_gain_today.resize(n)


func _reset_runtime(n: int) -> void:
	_day = 1
	_phase = "break"
	_tick_in_phase = 0
	_phase_index = 0
	_global_tick = 0
	_vol_log = []
	_settled = {}
	_settled_boundary = Vector2i(-1, -1)
	_interrupted_nodes = []
	_moving = []
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
	_best_join_phase = PackedInt32Array()
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
		_moving.append(false)
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
		_best_join_phase.append(-1)
		_study_start_tick.append(-1)
		_knot_days.append(0)
		_resting.append(false)
	_teacher_commands.reset_encourage(n)


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


## 绑定组覆盖（bindings.csv 行序，后行覆盖前行）；2026-10-19 起表为空，机制保留。
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


## 成绩初始化（§17.1.1）：**镜像配对**，开局班级平均分恒为 (min+max)/2。
## ⚠️ 必须紧跟 _init_relations() 之后调用，与 Python 同一点插入，保同种子 RNG 流不漂移。
## 开局状态（《老师版规则合并稿》D01）：压力 0–20 随机、动力 = 该生压力、成绩 min–max 镜像配对。
## 平均分是**固定值而非期望值**（2026-10-18 裁定）：前 half 名学生各自均匀随机 [min,max)，
## 后 half 名各自为其关于中值的镜像（g' = min + max − g），故总和恒为 n×(min+max)/2，
## 任意种子下开局均分都是同一个数值 —— 否则开局随机抖动本身就会造出「必不达标」的局。
## 中值随 data/rules/psyche.csv 的 grade_init_min/max 走，不写死 350。
## 配对不固定：_chars 顺序来自本函数之前的 _rng.shuffle(pool)，配对每局随机分配。
## 奇人数时最后一名取中值，均值同样严格成立。
## ⚠️ 随机数顺序固定（先 n 次压力，每人一次；再 half 次成绩），Python 参考实现需同序。
func _init_grade() -> void:
	var smin := float(_psyche["stress_init_min"])
	var smax := float(_psyche["stress_init_max"])
	var gmin := float(_psyche["grade_init_min"])
	var gmax := float(_psyche["grade_init_max"])
	var vitality_pins_stress := int(_psyche["vitality_equals_stress"]) == 1
	var n := _chars.size()
	# 整数除法：半数学生随机、半数镜像（n 为奇数时中间那名取中值）
	var half := n >> 1
	var mirror_sum := gmin + gmax
	_broken = []
	for i in range(n):
		var stress := _clamp100(smin + _rng.random() * (smax - smin))
		_stress[i] = stress
		_vitality[i] = stress if vitality_pins_stress else 0.0
		_gain_today[i] = 0.0
		_broken.append(false)
	for i in range(half):
		var g := float(_rint(gmin + _rng.random() * (gmax - gmin)))
		_grade[i] = g
		_grade[half + i] = mirror_sum - g
	if n % 2 == 1:
		_grade[n - 1] = float(_rint(mirror_sum * 0.5))


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
	# D04：课间末读一次状态，同时结算「邻座学习加压」与「座位基础关系」（不每秒重复累加）。
	# D05：考试当天只有考试，不发生普通事件与相关结算。
	if _phase == "break" and not _is_exam_only_day():
		_settle_neighbor_drip()
		_settle_seat_relations()
		_teacher_commands.settle_encourage_breaks()
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
	# D07 §10：每课间重置「主动伤害一次」与「被老师制止」的名单。
	_phase_stopped = []
	if _harm_events != null:
		_harm_events.begin_phase(_n)
	# D03：课间开始恢复挂起命令与「首次进教室」机会；上课开始则把未完成命令挂起。
	if _phase == "break":
		_teacher_commands.begin_break()
	else:
		_teacher_commands.begin_class(self)
	_teacher.begin_phase(self)
	_roll_sleep()
	_begin_phase_state()
	# 课间冲突在学生选定活动之前判定一次（吵架 / 推搡 / 打架）。
	if _phase == "break" and not _is_exam_only_day() and _harm_events != null:
		_harm_events.begin_break(self)
	_phase_setup_done = true


## 段首状态判定（《老师版规则合并稿》D01）：动力 >60 → 学习状态、<30 → 游戏状态，
## 之间为自由状态；状态持续一个课间，不因同学拉朋友而改变（D01 第 2 条）。
## 崩溃者的状态为 "broken"（D06：不能互动、不参加座位结算，由老师安抚恢复）。
func _begin_phase_state() -> void:
	_phase_state = []
	_settle_acc = []
	var study_threshold := float(_psyche["vitality_study_threshold"])
	var play_threshold := float(_psyche["vitality_play_threshold"])
	var class_threshold := float(_psyche["vitality_class_study_threshold"])
	for i in range(_n):
		_settle_acc.append(0.0)
		if _broken[i]:
			_phase_state.append("broken")
		elif _phase == "class":
			# 上课段（2026-10-16 裁定）：动力 > 上课阈值 → 学习，否则自由；**不进入游戏状态**。
			# 只在段首判定一次 —— 进入学习后本段**粘性**，中途动力跌破阈值也不退出学习。
			_phase_state.append("study" if _vitality[i] > class_threshold else "free")
		elif _phase != "break":
			_phase_state.append("free")
		elif _vitality[i] > study_threshold:
			_phase_state.append("study")
		elif _vitality[i] < play_threshold:
			_phase_state.append("play")
		else:
			_phase_state.append("free")


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
	# 上课段硬跳过（2026-10-17 裁定）：批处理同样跳过 class、不逐 tick（只做 class_gain 收益 + 崩溃判定），
	# 保证 advance_day / run_day 与实时时钟 pump 走同一条「上课无 tick」口径，同种子对拍一致。
	if str(_active_phases[_phase_index]["kind"]) == "class":
		skip_class()
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


## 上课段硬跳过（2026-10-17 裁定）：上课时间黑幕一闪即过，不逐 tick 模拟，
## 只保留两项效果 —— 全员固定学业收益 + 崩溃判定；压力涓流 / 睡觉 / 老师命令挂起 /
## 学习逐单位结算全部取消（即上课段不消耗动力、不涨压力）。
## 不调 _begin_phase（避免 roll_sleep 消费 RNG、begin_class 挂起、段首状态判定），
## 也不调 _end_phase（class 从未开始、无占用可收尾；且此时 _phase 仍为上一段 "break"，
## 误调会把课间结算重复一遍）。只推进游标到下一段；class 从不是末相位，故不会触发 _settle_day。
func skip_class() -> void:
	var gain := float(_acts["class_gain"])
	# D05 考试日不计入上课；§5.3 崩溃休息者当天不产生学业收益 —— 两类都不发这一节的收益。
	var paying := not _is_exam_only_day()
	for i in range(_n):
		if not paying or _broken[i]:
			continue
		_gain_today[i] += gain
	# 崩溃判定保留：跳过期间压力冻结，跳过时判一次 = class 结束时判一次（兜底边界的邻居涓流抬压）。
	# 睡觉跨段（2026-10-19）：先结算睡下的人再判崩溃，否则新崩溃者会被同一次结算唤醒。
	_settle_sleep()
	_check_breakdown()
	_phase_index = (_phase_index + 1) % _active_phases.size()
	_phase_setup_done = false
	_tick_in_phase = 0


## 行为完成结算：把**已到期**的占用收尾（§10.4 / §12.2 行为耗时契约）。
## 到期即「做完了」：写 _last_finished（仅本 tick 有效）、清占用；「行为完成才发信息」必须挂这里，
## 不能挂「发起」。与「被铃声打断」严格互斥：到期的不算打断，未到期的由 _check_interrupt 处理。
## 顺序：① 认定到期 → ② 清理活动／占用 → ③ 发布完成通知（再继续本 tick 的 NPC 决策）。
func _settle_finished_actions() -> void:
	_last_finished = []
	for i in range(_n):
		_last_finished.append(null)
	# ① 认定到期：真实共同活动（同一结束点只结一次，无双结算）
	_sessions.expire(_global_tick)
	var notifications: Array = []
	var leisure_notifications: Array = []
	# ③ 清理占用/当前动作
	for i in range(_n):
		if _busy_phase[i] < 0 or _busy_until[i] > _global_tick:
			continue
		_last_finished[i] = _busy_act[i]
		# D02 第 4 条：未满一个单位的部分按时间比例折算（压力按 2 秒 1 点；收益只按整数单位）。
		_fold_pending_unit(i)
		# 2026-10-18：活动自然完成时结算一次性附加效果（学业／动力，见 leisure_effects.csv）。
		LeisureActions.apply_finished_bonus(self, i)
		# 减压按各活动自己的压力率，由 _settle_units 逐单位给。
		if LEISURE_KINDS.has(_busy_act[i]):
			if _busy_act[i] == "eat_snack" and _snack_provider[i] != null:
				# 分享零食（§9.1.4）：自然完成一个共同进食单位 → 对分享者结算一次分享好感；
				# 中断 / 退出不结算；同一对子每课间段至多一次（沿用事件去重，防退出重入刷收益）
				var provider := int(_snack_provider[i])
				_apply_event(i, provider, "snack_share_affinity")
				var skey := Vector2i(provider, i)
				_share_units[skey] = int(_share_units.get(skey, 0)) + 1
				_snack_provider[i] = null
				_stats["share_units"] = int(_stats.get("share_units", 0)) + 1
			# 乐观（§10.2）：完成一次娱乐 → 压力单独额外 −3（不联动动力，不按单位重复发）。
			var leisure_relief: float = _passives.leisure_completed(i)
			if leisure_relief < 0.0:
				add_stress(i, leisure_relief, false)
			leisure_notifications.append(
				{"kind": "leisure_finished", "i": i, "activity": _busy_act[i]}
			)
		# D07 友善交流：正常接纳并实际完成聊天 → 对子双方敌对各 −2（不额外加修复概率）。
		if _busy_act[i] == "chat" and _conv_of.size() > i and _conv_of[i] != null:
			_settle_friendly_chat(i)
			_stats["friendly_chats"] = int(_stats.get("friendly_chats", 0)) + 1
		_current_act[i] = null
		_busy_act[i] = null
		_busy_phase[i] = -1
	# 加入路径（原 join_chat）的占用不建立会话，靠占用到期收尾（群聊拒绝不再占用请求者）
	# ④ 发布通知：完成在前
	for payload in leisure_notifications:
		_emit("event_happened", payload)
	for payload in notifications:
		_emit("event_happened", payload)


## 友善聊天完成结算（D07 基础敌对修复 + 主文档 §10.2 的四条聊天被动）。
## 口径与原有基础规则一致：以「完成者 i」为单位，对会话内每个其他成员各结算一次。
##   · 健谈：本人对聊天对象的好感 +2
##   · 讨人喜欢：聊天对象对本人好感 +2
##   · 不记仇：本人对聊天对象的敌对在基础修复之上额外 −2
##   · 善解人意：聊天对象的压力单独 −5（不联动动力）
func _settle_friendly_chat(i: int) -> void:
	var friendly_cut := float(_harm_events.friendly_cut())
	var bonus: Dictionary = _passives.chat_completed(i)
	var cut := friendly_cut - float(bonus["owner_hostility"])
	for m in (_conv_of[i] as Dictionary)["members"] as Array:
		var other := int(m)
		if other == i:
			continue
		_h[i * _n + other] = _clamp100(_h[i * _n + other] - cut)
		_h[other * _n + i] = _clamp100(_h[other * _n + i] - friendly_cut)
		if float(bonus["owner_affinity"]) > 0.0:
			_a[i * _n + other] = _clamp100(_a[i * _n + other] + float(bonus["owner_affinity"]))
		if float(bonus["other_affinity"]) > 0.0:
			_a[other * _n + i] = _clamp100(_a[other * _n + i] + float(bonus["other_affinity"]))
		if float(bonus["other_stress"]) < 0.0:
			add_stress(other, float(bonus["other_stress"]), false)


func _tick() -> void:
	_global_tick += 1
	_settle_finished_actions()
	_settle_conversations()
	_settle_groups()
	_teacher.step(self)
	# D03：老师命令按秒推进（上课期间由 TeacherCommands 自行挂起，不产生效果）。
	if _phase == "break":
		_teacher_commands.tick(self)
	# 自由状态中途跨线即进入学习／游戏并锁定（2026-10-19 用户裁定），再进决策。
	FREE_ROAM.refresh_states(self)
	_decide_and_act()
	_term_record.tick_state(self)
	_settle_units()
	_check_breakdown()
	_update_environment()
	# 进行中的吵架 / 推搡 / 打架按秒倒数，到点结算；不改压力。
	if _phase == "break" and _harm_events != null:
		_harm_events.tick(self)
	# D05：考试当天只有考试，压力涓流也属「相关结算」，当天不跑。
	if _global_tick % int(_p["settle_interval"]) == 0 and not _is_exam_only_day():
		_stress_drip()


## 单位结算（《老师版规则合并稿》D02）：按秒累计，每满一个单位结算一次；只对课间生效。
## · 学习：每 20 秒 +1 学业收益、-5 动力（不直接加成绩 —— 跨天由 _settle_day 把当日收益并入成绩）
## · 娱乐（吃零食 / 聊天 / 打闹 / 听歌 / 看课外书）：每 10 秒 -5 压力
## · 游戏状态：每 40 秒 -1 学业收益、-5 压力（不减少动力）
## 未完成的余额不在这里结算：自然完成 / 被打断时由 _fold_pending_unit 按 D02 第 4 条折算。
func _settle_units() -> void:
	# D02 + 2026-10-16 裁定：学习单位在**任何段**都结算（上课也积累学业收益）；
	# 娱乐／游戏状态只在课间结算 —— 规格写明上课不执行课间事件。D05：考试日一律不结算。
	if _is_exam_only_day():
		return
	var in_break := _phase == "break"
	var study_seconds := float(_acts["study_settle_seconds"])
	var play_seconds := float(_acts["play_settle_seconds"])
	var unit_seconds := float(_acts["unit_seconds"])
	for i in range(_n):
		var kind := _unit_kind(i)
		if kind == "":
			_settle_acc[i] = 0.0
			continue
		if kind != "study" and not in_break:
			# 上课段只结算学习：娱乐 / 游戏单位不生效，也不累计进度。
			_settle_acc[i] = 0.0
			continue
		_settle_acc[i] += 1.0
		if kind == "study":
			var settled := false
			while _settle_acc[i] >= study_seconds:
				_settle_acc[i] -= study_seconds
				# 请教者免动力（2026-10-17 交接「多人请教」）：加入他人学习的跟随者
				# 每满 20 秒 +1 收益、不消耗动力；原学习者（学习组 originator）照常扣动力。
				# 收益仍走公开被动（§10.2：专注翻倍收益增减 → 收放自如减半 → 自律少耗动力）。
				var cost := float(_acts["study_vitality_cost"])
				if _study_of[i] != null and int(_study_of[i].get("originator", i)) != i:
					cost = 0.0
				var unit: Dictionary = _passives.study_unit(i, float(_acts["study_gain"]), cost)
				_gain_today[i] += float(unit["gain"])
				add_vitality(i, -float(unit["cost"]))
				settled = true
			# §5.1.1：自由状态的自主学习只做一个单位，完成后重选，不锁整段（请教跟随者仍按组结算）。
			if settled and _is_solo_free_study(i):
				_settle_acc[i] = 0.0
				_current_act[i] = null
				_busy_until[i] = 0
		elif kind == "play":
			while _settle_acc[i] >= play_seconds:
				_settle_acc[i] -= play_seconds
				_gain_today[i] += _passives.play_gain(i, float(_acts["play_gain"]))
				add_stress(i, -float(_acts["play_relief"]), false)
				# 2026-10-17：游戏状态回复动力 —— 与学习消耗对称，让动力能自动循环。
				add_vitality(i, float(_acts["play_vitality_gain"]))
		else:
			# 逐活动压力率（rules/leisure_effects.csv，2026-10-18）：不同娱乐的减压效率不同。
			var per_unit := LeisureActions.stress_per_unit(self, str(_current_act[i]))
			while _settle_acc[i] >= unit_seconds:
				_settle_acc[i] -= unit_seconds
				if per_unit != 0.0:
					add_stress(i, per_unit)


## 该生此刻按哪一类结算："" = 不结算｜"study"｜"play"｜"leisure"（状态来自段首判定或中途跨线锁定）。
func _unit_kind(i: int) -> String:
	if _broken[i] or _sleeping[i] or not is_present(i):
		return ""
	# 冲突发生在选定活动之前，这 20 秒不按学习 / 游戏 / 娱乐结算。
	if _harm_events != null and _harm_events.active_kind(i) != "":
		return ""
	if _phase_state.size() > i and str(_phase_state[i]) == "study":
		return "study"
	if _phase_state.size() > i and str(_phase_state[i]) == "play":
		return "play"
	var act: Variant = _current_act[i]
	if act == "study":
		return "study"
	if act != null and LEISURE_KINDS.has(act):
		return "leisure"
	return ""


## §5.1.1：自由状态里自己投入的学习只做一个单位，完成后重选（请教跟随者不算）。
func _is_solo_free_study(i: int) -> bool:
	if i >= _phase_state.size() or str(_phase_state[i]) != "free":
		return false
	return _current_act[i] == "study" and _study_of[i] == null


## 未完成单位的折算（D02 第 4 条）：压力按每 2 秒 1 点折算，学业收益只按整数单位计（不足不计）。
func _fold_pending_unit(i: int) -> void:
	if _settle_acc.size() <= i:
		return
	var pending := float(_settle_acc[i])
	_settle_acc[i] = 0.0
	if pending <= 0.0:
		return
	var per_point := float(_acts["interrupt_stress_per_point_seconds"])
	if per_point <= 0.0:
		return
	var relief := floorf(pending / per_point)
	if relief > 0.0:
		add_stress(i, -relief)


## 崩溃判定（D01 / D06）：压力 >90 进入崩溃（中断活动、保留已得收益），当天只睡觉；
## 次日跨天特殊恢复（§5.3）。一次连续崩溃只计一次。
func _check_breakdown() -> void:
## 崩溃与恢复（§5.3，2026-10-16）：压力 > 阈值进入崩溃休息 —— 当天只睡觉、不学习不社交、
## 不参加座位结算；**次日跨天时**特殊恢复（压力／动力各减固定值）并解除。旧「压力 <70 即时恢复」出口已废止。
	var enter := float(_psyche["breakdown_enter_stress"])
	var knot_days := int(float(_status_tags["heart_knot"]["days"]))
	for i in range(_n):
		if _broken[i] or _stress[i] <= enter:
			continue
		_broken[i] = true
		_resting[i] = true
		_fold_pending_unit(i)
		_current_act[i] = null
		_busy_act[i] = null
		_busy_phase[i] = -1
		_busy_until[i] = 0
		# 崩溃休息：当天只睡觉。这种睡觉不作为邻座学习来源，也不产生学业收益（见 _unit_kind）。
		_sleeping[i] = true
		if _phase_state.size() > i:
			_phase_state[i] = "broken"
		_stats["breakdowns"] = int(_stats.get("breakdowns", 0)) + 1
		if _risk != null:
			_risk.register_breakdown(i)
		# 心结（§5.3）：本人与当时固定座位的前后左右邻座获得，不含对角、不遍及全班；
		# 记录当时对象，之后换座不转移标签。重复获得只刷新天数，不叠层。
		_knot_days[i] = knot_days
		_emit("tag_changed", {"id": i, "tag": "heart_knot"})
		for j in _neighbor_idx[i]:
			_knot_days[int(j)] = knot_days
			_emit("tag_changed", {"id": int(j), "tag": "heart_knot"})
		_emit("event_happened", {"kind": "breakdown", "i": i})


func _settle_neighbor_drip() -> void:
	var drip := float(_acts["neighbor_study_stress"])
	for i in range(_n):
		# 涓流只看固定座位的前后左右，不含对角，不随临时走动重建邻域（交接 2026-10-17）。
		# 接收者必须实际在自己座位：离座 / 办公室 / 崩溃 / 换座期间都不作接收者。
		if _broken[i] or not is_present(i) or not in_own_seat(i):
			continue
		# D03 第 5 条：换座期间的学生不参加课间涓流（既不作接收者也不作来源）。
		# 2026-10-19 起换座即时生效（seat_change_seconds=0）→ 无窗口；保留给配回 >0 的口径。
		if _teacher_commands.is_seat_changing(i):
			continue
		var studying := 0
		var delta := 0.0
		for j in _neighbor_idx[i]:
			var source := int(j)
			# 来源也必须是正交邻座且实际在自己座位 —— 远处走到同学旁请教的人
			# 能拿请教收益，但不因此成为邻座、不把学习加压传播给临时站在周围的人。
			if _seat_relation_between(i, source) != "orthogonal":
				continue
			if _teacher_commands.is_seat_changing(source):
				continue
			if not in_own_seat(source):
				continue
			if _unit_kind(source) != "study":
				continue
			studying += 1
			# §10.2：卷王（来源）与玻璃心（目标）各 +100%，加法叠加 —— 基础 5 点单项 10、双项 15。
			delta += _passives.neighbor_drip(source, i, drip)
		if studying > 0:
			add_stress(i, delta)
			_stats["neighbor_drip"] = int(_stats.get("neighbor_drip", 0)) + studying


## 座位结算参与资格（D04 / §8.1）：实际在自己座位、处于学习／娱乐／睡觉，
## 且非崩溃、非换座。离座、办公室、崩溃与换座期间既不作来源也不作接收者。
func _seat_eligible(i: int) -> bool:
	if _broken[i] or not is_present(i) or not in_own_seat(i):
		return false
	if _teacher_commands.is_seat_changing(i):
		return false
	return _seat_role(i) != ""


## 座位关系里的角色（D04 / §8.1）：睡觉仅在座位关系中视同学习，不获得学习收益。
func _seat_role(i: int) -> String:
	if _broken[i] or not is_present(i):
		return ""
	if _sleeping[i]:
		return "study"
	return _unit_kind(i)


## 两学生的座位关系：前后左右 = orthogonal，斜向 = diagonal，其余 = 一圈以外。
func _seat_relation_between(i: int, j: int) -> String:
	if i == j or not _seat_pos.has(_seat_of[i]) or not _seat_pos.has(_seat_of[j]):
		return "none"
	var a: Array = _seat_pos[_seat_of[i]]
	var b: Array = _seat_pos[_seat_of[j]]
	var dr: int = absi(int(a[0]) - int(b[0]))
	var dc: int = absi(int(a[1]) - int(b[1]))
	if dr + dc == 1:
		return "orthogonal"
	if dr == 1 and dc == 1:
		return "diagonal"
	return "far"


## 座位基础关系结算（D04 / §8.2、§8.4）：每个课间末读一次状态，结算一次。正交邻座双方好感 +2、
## 对角不加、一圈以外双方 −1；学习者的正交娱乐邻座敌对 +5（不反向）。只在不同学生之间写入。
func _settle_seat_relations() -> void:
	var orth := float(_seat_rel.get("orthogonal_h", 0.0))
	var diag := float(_seat_rel.get("diagonal_h", 0.0))
	var far := float(_seat_rel.get("far_h", 0.0))
	var hostility := float(_seat_rel.get("study_play_hostility", 0.0))
	var eligible: Array = []
	for i in range(_n):
		if _seat_eligible(i):
			eligible.append(i)
	for a in range(eligible.size()):
		for b in range(a + 1, eligible.size()):
			var i := int(eligible[a])
			var j := int(eligible[b])
			var rel := _seat_relation_between(i, j)
			var delta := orth if rel == "orthogonal" else (diag if rel == "diagonal" else far)
			var idx_ij := i * _n + j
			var idx_ji := j * _n + i
			# 好感（_a = affinity）承接基础增减；敌对（_h = hostility）只由「学习者对娱乐者」写入。
			_a[idx_ij] = _clamp100(_a[idx_ij] + delta)
			_a[idx_ji] = _clamp100(_a[idx_ji] + delta)
			if rel != "orthogonal":
				continue
			var ri := _seat_role(i)
			var rj := _seat_role(j)
			# 「娱乐」包含段首游戏状态（play）与具体娱乐活动（leisure）两种角色。
			var i_play: bool = ri == "play" or ri == "leisure"
			var j_play: bool = rj == "play" or rj == "leisure"
			if ri == "study" and j_play:
				_h[idx_ij] = _clamp100(_h[idx_ij] + hostility)
			elif rj == "study" and i_play:
				_h[idx_ji] = _clamp100(_h[idx_ji] + hostility)
	_stats["seat_settles"] = int(_stats.get("seat_settles", 0)) + 1
	_term_record.capture(self, "seat_relations")


## 游戏状态（D01 / D02）：动力 <30 整课间走 play 口径（见 _settle_units）；做哪类自指娱乐由
## `behavior_probs.csv` 的 `*_p` 概率决定（2026-10-17，与自由状态共用），一次决策只掷一次。
func _start_play_activity(i: int) -> bool:
	var kinds: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for kind in LEISURE_KINDS:
		var prob_key: String = LEISURE_KINDS[kind] + "_p"
		if not _probs.has(prob_key):
			continue
		var weight := float(_probs[prob_key])
		if weight <= 0.0:
			continue
		if not _allowed(kind):
			continue
		if kind == "read_book" and _book[i] <= 0:
			continue
		kinds.append(kind)
		weights.append(weight)
		total += weight
	if kinds.is_empty():
		return false
	var roll := _rng.random() * total
	var picked: String = kinds[kinds.size() - 1]
	for index in range(kinds.size()):
		roll -= weights[index]
		if roll <= 0.0:
			picked = kinds[index]
			break
	return _start_leisure(i, picked)


## 动力（0–100，D01）：>60 进入学习状态、<30 进入游戏状态。
func vitality(i: int) -> float:
	if i < 0 or i >= _n:
		return 0.0
	return _vitality[i]


## 今日学业收益（D01 / D02）：跨天并入成绩后清零，可为负。
func gain_today(i: int) -> float:
	if i < 0 or i >= _n:
		return 0.0
	return _gain_today[i]


## 是否处于崩溃（D01 / D06）。
func is_broken(i: int) -> bool:
	return i >= 0 and i < _n and bool(_broken[i])


## 老师命令服务（D03）：表现层通过它发意图、读只读快照。
func teacher_commands() -> TeacherCommands:
	return _teacher_commands


## 压力写入的唯一入口（§4.1 一般联动）：一般事件压力 ±1 → 动力同向 ±1，两者各自钳制 0–100。
## 标注「单独」变化的效果传 linked = false（跨天继承、游戏状态减压等）。
## 反向不成立：单独改动力（见 add_vitality）不影响压力。不消耗随机数。
## 弹簧（主文档 §10.2）：累计**获得**的压力每满 5 点，动力额外 +2 —— 只加动力、不反向产生压力，
## 所以不会递归触发本函数；减压（delta < 0）不计入累计、也不回退已发放的动力。
func add_stress(i: int, delta: float, linked: bool = true) -> void:
	if i < 0 or i >= _n:
		return
	_stress[i] = _clamp100(_stress[i] + delta)
	if linked:
		_vitality[i] = _clamp100(_vitality[i] + delta)
	if delta > 0.0 and _passives != null:
		var bonus: float = _passives.spring(i, delta)
		if bonus > 0.0:
			add_vitality(i, bonus)


## 只改动力（§4.1「反向不成立」）：用于明确「单独」的动力变化，例如学习每次结算 −5 动力。
func add_vitality(i: int, delta: float) -> void:
	if i < 0 or i >= _n:
		return
	_vitality[i] = _clamp100(_vitality[i] + delta)


## 调座位发起时打断参与者当前行为（D03 第 6 / 7 条）：保留已得收益、不发放完成奖励；
## 处在共同活动里则从该活动移出（其他人不自动停下，人数不足时活动自然结束）。
func interrupt_for_seat_change(i: int) -> void:
	if i < 0 or i >= _n:
		return
	_fold_pending_unit(i)
	_current_act[i] = null
	_busy_act[i] = null
	_busy_phase[i] = -1
	_busy_until[i] = 0
	# 聊天会话：被叫走/调座者退出，其余成员沿原进度继续；剩不足 2 人则整场解散（交接 2026-10-17）。
	if _conv_of.size() > i and _conv_of[i] != null:
		_leave_conversation(i, _conv_of[i])
	# 打闹组：同样只移出本人，不足 2 人则解散。
	if _rough_of.size() > i and _rough_of[i] != null:
		_dissolve_from_group(_rough_groups, _rough_of, i)
	# 学习 / 零食组移出（人数不足时自然解散）。
	_leave_solo_activity(i)


## 调座位生效（D03 第 4 条）：交换两人的座位号并重算邻接；不写任何关系矩阵。
func apply_seat_change(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= _n or b >= _n or a == b:
		return
	var tmp: Variant = _seat_of[a]
	_seat_of[a] = _seat_of[b]
	_seat_of[b] = tmp
	# Geometry is indexed by student too; it must follow their new assigned seats.
	for geometry in [_seat_world, _seat_world_positions]:
		if geometry.has(a) and geometry.has(b):
			var previous: Variant = geometry[a]
			geometry[a] = geometry[b]
			geometry[b] = previous
	_build_neighbor_idx()
	_emit("event_happened", {"kind": "seat_changed", "a": a, "b": b})


## 本课间的段首状态："study" / "play" / "free" / "broken"。
func phase_state_of(i: int) -> String:
	if i < 0 or i >= _phase_state.size():
		return ""
	return str(_phase_state[i])


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
## 概率爆发（§8.3）：压力跨过阈值后每天判定一次，p = burst_p_max × severity。
## 心结**不再**由爆发给出（§5.3 改为崩溃时本人与正交邻座获得），这里只做减压与统计。
	var th := float(_thresholds_lookup.get("burst_stress", 70.0))
	var pmax := float(_probs.get("burst_p_max", 0.0))
	if pmax <= 0.0:
		return
	for i in range(_n):
		var s := _stress[i]
		if s < th:
			continue
		var severity := clampf((s - th) / (100.0 - th), 0.0, 1.0)
		if _rng.random() >= pmax * severity:
			continue
		add_stress(i, -40.0)
		_stats["bursts"] = int(_stats["bursts"]) + 1
		_emit("stress_burst", {"i": i})
		_emit("event_happened", {"kind": "burst", "i": i, "severity": severity})


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


# ------------------------------------------------------------------ 风险与伤害（D06 / D07）
## 伤害触发用的随机数（带种子、两侧同序；HarmEvents 只通过这里取随机）。
func _next_unit_random() -> float:
	return _rng.random()


## 当前段类型（"break" / "class"）——伤害与座位结算的时段判定口径。
func _current_phase_kind() -> String:
	return _phase


## 进入一场课间冲突：清掉本段睡觉，占住决策，直到冲突结束。
func _enter_conflict(i: int, kind: String) -> void:
	if i < 0 or i >= _n:
		return
	_sleeping[i] = false
	_current_act[i] = kind
	_busy_act[i] = kind
	_busy_until[i] = _FOREVER


## 冲突结束：放开决策。已经开始的学业单位不在这里折算（冲突开始前还没有活动）。
func _leave_conflict(i: int) -> void:
	if i < 0 or i >= _n:
		return
	if str(_current_act[i]) in ["quarrel", "shove", "fight"]:
		_current_act[i] = null
	if str(_busy_act[i]) in ["quarrel", "shove", "fight"]:
		_busy_act[i] = null
		_busy_phase[i] = -1
		_busy_until[i] = 0


## 有向敌对增量（吵架 / 推搡 / 打架与调解都是双向各记一次）。
func _add_hostility(from_i: int, to_i: int, delta: float) -> void:
	if from_i < 0 or to_i < 0 or from_i >= _n or to_i >= _n or from_i == to_i:
		return
	_h[from_i * _n + to_i] = _clamp100(_h[from_i * _n + to_i] + delta)


## 同学来源的正向加压（伤害事件等）：目标有「玻璃心」时按 §10.2 额外 +100%。
## 只修正正向加压，不扩大到减压；邻座学习涓流不走这里（那边已按来源 + 目标一次算好，避免双计）。
func _add_peer_stress(target: int, base: float) -> void:
	if _passives == null:
		add_stress(target, base)
		return
	add_stress(target, _passives.peer_stress(target, base))


## 两人是否在同一场共同活动里（多人会话 / 学习组 / 零食分享组）。
func _shares_activity(i: int, j: int) -> bool:
	for conv in _conversations:
		var members: Array = conv["members"]
		if members.has(i) and members.has(j):
			return true
	if (
		_study_of.size() > i
		and _study_of.size() > j
		and _study_of[i] != null
		and _study_of[i] == _study_of[j]
	):
		return true
	if (
		_snack_of.size() > i
		and _snack_of.size() > j
		and _snack_of[i] != null
		and _snack_of[i] == _snack_of[j]
	):
		return true
	return false


## 学生是否在办公室（D07：在办公室期间不参与伤害）。
func _is_in_office(i: int) -> bool:
	return _teacher_commands.called_index() == i and not _teacher_commands.is_held()


## 老师制止（D07 §10）：老师完成现场制止 / 调解，或把伤害参与者召唤到办公室后，
## 涉及的学生本课间不能再主动伤害；仅仅进入教室不算制止、也不让全班自动停手。
func _is_stopped_by_teacher(i: int) -> bool:
	return _phase_stopped.has(i)


## 登记「本课间被老师制止」的学生（由 TeacherCommands 在命令完成时调用）。
func _note_stopped(i: int) -> void:
	if i < 0 or i >= _n:
		return
	if not _phase_stopped.has(i):
		_phase_stopped.append(i)


## 老师训斥**实际完成**时调用（D03 + 主文档 §10.2 听劝）：压力已由调用方按
## office_scold_stress / class_scold_stress 结算；有「听劝」的学生动力额外 +10。
## 只加动力（add_vitality）——不反向产生压力，也不触发弹簧的累计。
func _note_scolded(i: int) -> void:
	if i < 0 or i >= _n:
		return
	var bonus: float = _passives.scolded(i)
	if bonus > 0.0:
		add_vitality(i, bonus)


## 学习锁定（D07：处于学习状态或正在学习的学生不参与伤害）。
func _is_study_locked(i: int) -> bool:
	if i < 0 or i >= _n:
		return false
	if _phase_state.size() > i and str(_phase_state[i]) == "study":
		return true
	return _current_act[i] == "study"


## 中断当前活动（推搡效果；已得学业收益不清空 —— 按 D02 折算后保留）。
func _interrupt_activity(i: int) -> void:
	if i < 0 or i >= _n:
		return
	_fold_pending_unit(i)
	_current_act[i] = null
	_busy_act[i] = null
	_busy_phase[i] = -1
	_busy_until[i] = 0


## 伤害登记。只有打架会把双方记成「曾经打过一次架」。
func _note_harm(from_i: int, to_i: int, kind: String) -> void:
	if _risk != null:
		_risk.register_harm(from_i, to_i, kind)


## 风险快照（只读：预警、正式触发、退学原因与每人崩溃计数）。
func _risk_snapshot() -> Dictionary:
	return _risk.snapshot() if _risk != null else {}


func _is_dropped_out(i: int) -> bool:
	return _risk != null and _risk.is_dropped(i)


## 老师被辞退的**原因**（空串 = 尚未辞退）。§11.4 要求失败必须说明触发了哪个判据，
## 并附上可查的证据（哪些学生退学、考核均分与目标的差距），不做无证据的随机辞退。
func _failure_reason() -> String:
	if _risk != null and _risk.has_dropout():
		var names := _alias_list()
		var who: PackedStringArray = PackedStringArray()
		for i in range(_n):
			if _risk.is_dropped(i):
				who.append(str(names[i]) if i < names.size() else "某同学")
		for i in range(_n):
			if _risk.is_dropped(i):
				return "退学：%s 累计崩溃超过 3 次，或正式触发霸凌／孤立后再次崩溃" % "、".join(who)
	if _exam != null and not _exam.last_passed():
		return (
			"考核不达标：第 %d 天全班均分 %d，低于目标均分 %d"
			% [
				_exam.last_exam_day(),
				int(round(_exam.last_exam_mean())),
				int(round(_exam.target_mean())),
			]
		)
	return ""


## 老师是否被辞退：任一次考核不达标（D05）或出现退学（D06）。
func _class_failed() -> bool:
	if _risk != null and _risk.has_dropout():
		return true
	return _exam != null and not _exam.last_passed()


## D05：考试当天只有考试 —— 当天不发生普通事件与相关结算（座位、涓流、学生行为）。
func _is_exam_only_day() -> bool:
	return _exam != null and _exam.exam_only_day() and _exam.is_exam_day(_day)


## D05（2026-10-17 裁定）：考试当天只有考试 —— 老师命令层据此拒绝一切操作，
## 在途命令由 `TeacherCommands.tick` 冻结，考试结束后继续。
func is_exam_only_day() -> bool:
	return _is_exam_only_day()


## 跨天结算（§3.5 + 《老师版规则合并稿》D01）：压力继承 → 爆发判定 → 心结加压。
## D01（2026-10-17 修订）：跨天压力单独减少 20 点，**动力不再统一扣减**（保留前日剩余值）；
## 关系不再跨天衰减（§4.2：好感恩对原值保留，变化只来自真实结算与干预）。
func _settle_day() -> void:
	var carry_stress := float(_psyche["carry_stress_cut"])
	var rest_stress_cut := float(_psyche["breakdown_rest_stress_cut"])
	var rest_vitality_cut := float(_psyche["breakdown_rest_vitality_cut"])
	for i in range(_n):
		if _resting[i]:
			# §5.3：崩溃后次日特殊恢复 —— 压力／动力各减固定值，替代普通跨天的 −20；
			# 不重复扣除，也不因这次减压额外联动一次动力（两者各自单独）。
			add_stress(i, -rest_stress_cut, false)
			add_vitality(i, -rest_vitality_cut)
			_broken[i] = false
			_resting[i] = false
			_sleeping[i] = false
			if _phase_state.size() > i:
				_phase_state[i] = "free"
			_emit("event_happened", {"kind": "breakdown_recovered", "i": i})
		else:
			add_stress(i, -carry_stress, false)
		_settle_daily_gain(i)
		_gain_today[i] = 0.0
	_try_burst()
	# D06：当天末判定霸凌 / 孤立（预警、正式触发）与退学。
	if _risk != null:
		_risk.settle_day(self, _day)
	# 「心结」：爆发后的几天里，每天先加压（长线心理创伤，§3.5）。
	for i in range(_n):
		if _knot_days[i] > 0:
			add_stress(i, float(_status_tags["heart_knot"]["daily_stress"]))
			_knot_days[i] -= 1
	if _exam != null:
		# D05 第 4 条：考试前一天全班压力 +20（考试日当天再照常跨天继承）。
		if _exam.is_exam_eve(_day):
			var pre: float = float(_exam.pre_stress_bonus())
			for i in range(_n):
				add_stress(i, pre)
		_exam.settle(_day, _grade, _stress, _alias_list())
		# D05 第 4 条：考试结束全班压力 −30（动力按一般规则联动，不额外强制改动力）。
		if _exam.is_exam_day(_day):
			var cut: float = float(_exam.post_stress_cut())
			for i in range(_n):
				add_stress(i, -cut)
	_term_record.settle_day(self, _day)
	_day += 1
	_emit("day_settled", {"day": _day - 1, "stats": _stats.duplicate(true)})


## 当日学业收益并入成绩（《老师版规则合并稿》D01 + 主文档 §10.2 的日结类被动）。
## 顺序：群策群力（当天学业收益 +1 / 名达标同学）→ 善于吸收（净收益为正再 +3 成绩）
## → 钳制到 [0, grade_max] → **四舍五入到整数分**（2026-10-18 裁定：成绩恒为整数值）
## → 正反馈按**实际提高量**给动力（初始成绩赋值不算提高）。
## 主文档 §10.2 把「群策群力与收益转成绩的先后」列为待确认项；此处按「先并入当天收益、再转成成绩」实现。
func _settle_daily_gain(i: int) -> void:
	var net := _gain_today[i]
	if _passives.has(i, PASSIVES.TEAM_SPIRIT):
		net += _passives.team_spirit_gain(i, _team_spirit_count(i))
	var before := _grade[i]
	var merged := clampf(
		_grade[i] + net + _passives.absorb_bonus(i, net), 0.0, float(_kp["grade_max"])
	)
	_grade[i] = float(_rint(merged))
	var raised := _grade[i] - before
	if raised > 0.0:
		var bonus: float = _passives.grade_raised(i, raised)
		if bonus > 0.0:
			add_vitality(i, bonus)


## 群策群力：有多少名同学对 i 的好感**严格**超过阈值（恰好等于不计入）；只在日末算一次。
func _team_spirit_count(i: int) -> int:
	var threshold: float = _passives.team_spirit_threshold()
	var count := 0
	for j in range(_n):
		if j != i and _a[j * _n + i] > threshold:
			count += 1
	return count


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
			add_stress(i, delta)
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


## 压力涓流：只剩环境层的偏离氛围通道（老师版删除噪声压力/噪声敌对/从众敌对）。
## 2026-10-19 删除「学习 +0.4 / 独处 −2」滴注：这两个键是学生版 §8.4 遗留
## （`study_stress` 于 2026-10-09 由 1.0 标定到 0.4，`alone_stress` 于 2026-10-05 引入），
## 老师版主文档无此条款；且 `_doing_study()` 恒 true 使独处分支本来就不可达。
## 老师版的学习加压（`w_events.study_stress`，不联动动力）尚未接入，见主文档 §13.3。
func _stress_drip() -> void:
	_deviance_pressure()


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
			add_stress(i, k * (0.4 - v) * 10.0)
		elif act == "study" and v > 0.72:
			add_stress(i, k * (v - 0.72) * 10.0)


# ------------------------------------------------------------------ 相位结算
## 睡觉结算：醒来一次 −`sleep_relief` 压力（不联动）＋ +`sleep_vitality_gain` 动力。
## 2026-10-19 起跨过紧邻上课段：课间段末不结算，等上课段末（`skip_class`）或下一非上课段末。
func _settle_sleep() -> void:
	var nxt := _phase_index + 1
	if nxt < _active_phases.size() and str(_active_phases[nxt]["kind"]) == "class":
		return
	var relief := float(_probs.get("sleep_relief", 0.0))
	var gain := float(_probs.get("sleep_vitality_gain", 0.0))
	for i in range(_n):
		if _sleeping[i]:
			add_stress(i, -relief, false)
			add_vitality(i, gain)
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
			# D02 第 4 条：被打断的活动按时间比例结算，保留已得收益、不发放完成奖励。
			_fold_pending_unit(i)
			_busy_until[i] = 0
			_busy_phase[i] = -1
			# D02 第 4 条：被打断按时间比例结算（减压与收益都已由 _fold_pending_unit 折算）；
			# 通用打断代价仍来自 behavior_probs.csv（不再是娱乐专属的 leisure.interrupted_stress）。
			if cost > 0.0:
				add_stress(i, cost)
			_stats["interrupts"] = int(_stats["interrupts"]) + 1
			_interrupted_nodes.append(i)


## 统一边界协议 ④：清理被打断动作的残余状态（占用 / 会话 / 移动锁）。
## 不消耗 RNG；抽象内核（无移动输入）下移动锁清理为 no-op。
func _cleanup_phase() -> void:
	_interrupt_conversations()
	_clear_join_groups()
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
	# 有成员被打断的共同活动整场中断（不留半场会话、不残留融合圈）
	if not _interrupted_nodes.is_empty():
		for snap in _sessions.active_snapshots():
			for m in snap["members"]:
				if _interrupted_nodes.has(int(m)):
					_sessions.end(int(snap["session_id"]))
					break
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
## 2026-10-19：只在课间段掷；睡下后占满本段并跨过紧邻上课段，到下一段末才结算（`_settle_sleep`）。
func _roll_sleep() -> void:
	if _phase != "break":
		return
	# D05：考试当天只有考试 —— 不掷睡觉，当天 NPC 不产生任何活动。
	if _is_exam_only_day():
		return
	if not _allowed("sleep"):
		return
	var p := float(_probs["sleep"])
	# 老师不占学生节点，全部学生都参与段首判定，保持与 Python 同序。
	for i in range(_n):
		if _sleeping[i] or is_moving(i):
			continue
		if _rng.random() < p * (1.0 + _tag_bias(i, "alone_bias")):
			_sleeping[i] = true
			_current_act[i] = "sleep"
			_busy_until[i] = _FOREVER
			_stats["sleeps"] = int(_stats["sleeps"]) + 1


## 一 tick 内的行为决策：加入好感最高者 → 休闲 → 学习 → 闲聊 / 打闹 → 带朋友 pass。
## 决策顺序按洗牌（可复现）；决策读「我对他」的 A/H（§18.7 不变式 3）。
func _decide_and_act() -> void:
	var n := _n
	# D05：考试当天只有考试 —— 学生不做普通行为决策（不产生事件与相关结算）。
	if _is_exam_only_day():
		return
	var busy: Array = []
	for _k in range(n):
		busy.append(false)
	# 全体学生参与自主决策（§12.1）
	var order: Array = []
	for _k in range(n):
		order.append(_k)
	_rng.shuffle(order)
	for i in order:
		if (
			not is_present(i)
			or _sleeping[i]
			or busy[i]
			or _global_tick < _busy_until[i]
			or is_moving(i)
		):
			continue
		_in_conversation[i] = false
		# 段首状态（D01）：学习状态整课间学习、游戏状态整课间娱乐，且不被拉朋友规则改变；
		# 崩溃者不参与决策（D06：不能互动、找伴、加入或带朋友）。
		var state := str(_phase_state[i]) if _phase_state.size() > i else "free"
		if state == "broken":
			continue
		if state == "study":
			_do_study(i)
			busy[i] = true
			continue
		if state == "play":
			# 游戏状态（动力 <30，D01）：伙伴类活动不受状态限制（2026-10-17 裁定）——
			# 先按同一批概率尝试闲聊 / 打闹，未成立再落到自指娱乐；收益口径仍走 play（见 _unit_kind）。
			if _try_partner_activity(i, busy) or _start_play_activity(i):
				busy[i] = true
				continue
		# 鼓励目标（D09）：自由学生有未结束目标时优先尝试一次聊天（不打断锁定；
		# 忙碌 / 条件不满足算等待、不算关系拒绝，学生可落回正常决策）。
		if _teacher_commands.has_active_encourage(i):
			if _teacher_commands.try_encourage(self, i):
				busy[i] = true
				continue
		# 自由状态先去找「自己好感最高的人」，按对方正在做的事加入（每课间一次）。
		if state == "free" and FREE_ROAM.try_join_best(self, i):
			busy[i] = true
			continue
		var leisure_started := false
		for kind in LEISURE_KINDS:
			var prefix: String = LEISURE_KINDS[kind]
			var prob_key: String = prefix + "_p"
			# 具体娱乐的概率键在 behavior_probs.csv；缺键时跳过而不是让决策崩掉
			# （旧实现曾因 phone_p 缺键在场景里报运行时错误）。
			if not _probs.has(prob_key):
				continue
			if _allowed(kind) and (kind != "read_book" or _book[i] > 0):
				if _rng.random() < float(_probs[prob_key]):
					_start_leisure(i, kind)
					leisure_started = true
					break
		if leisure_started:
			busy[i] = true
			continue
		# 环境类：学习（§8.23）—— 必须**在自己的座位上**才能坐下学一整个课间（用户 2026-10-16 裁定补回）；
		# 爱学习的人更常坐下来。⚠️ 座位检查放在掷骰前，Python 参考实现保持同序，同种子可复现。
		var study_gain := 1.0 + _tag_bias(i, "study_bias")
		if (
			_allowed("study")
			and in_own_seat(i)
			and _rng.random() < float(_probs["study_p"]) * study_gain
		):
			_do_study(i)
			busy[i] = true
			continue
		# 伙伴类活动（闲聊 / 打闹，§9.1.4）：自由状态与游戏状态共用同一入口
		if _try_partner_activity(i, busy):
			busy[i] = true
			continue

	# 带朋友（§9.1.3/§9.1.4）：活动组成员的邀请 pass；
	# 随机数顺序固定（组按创建序、成员按节点号升序），同种子可复现。
	_invite_friends_pass()


## 伙伴类活动（闲聊 / 打闹）的一次尝试（§9.1.4）：按 behavior_probs 掷骰 → 找伴 → 提议。
## 2026-10-17 裁定：游戏状态（动力 <30）也允许伙伴类娱乐，故自由状态与游戏状态共用本函数；
## 学习状态仍锁定学习，不调用。返回 true 表示本决策点已被占用。
func _try_partner_activity(i: int, busy: Array) -> bool:
	# 标签调制（§11、§18.9）：爱学习更少聊、爱聊天更多聊
	var chat_gain := 1.0 + _tag_bias(i, "chat_bias") - _tag_bias(i, "study_bias")
	chat_gain = maxf(0.1, chat_gain)
	if _allowed("chat") and _rng.random() < float(_probs["chat"]) * chat_gain:
		var chat_tgt := _find_partner(i, "chat")
		if chat_tgt >= 0:
			# 一个决策点只发起一次伙伴尝试：成败都到此为止（§9.1.4 循环与时序）
			_propose_activity(i, chat_tgt, "chat")
			return true
	# 意向类：追逐打闹（§9.2）—— 同走通用加入找伴；场地条件沿用旁观者门槛
	var th_rc := int(_thresholds_lookup["roughhouse_count"])
	if (
		_allowed("roughhouse")
		and _rng.random() < float(_probs["roughhouse_p"]) * _teacher.multiplier("roughhouse")
	):
		var rough_tgt := _find_partner(i, "roughhouse")
		if rough_tgt >= 0:
			var bys: Array = []
			for k in range(_n):
				if k != i and k != rough_tgt and not busy[k] and is_present(k) and not _sleeping[k]:
					bys.append(k)
			if bys.size() >= th_rc:
				_propose_activity(i, rough_tgt, "roughhouse")
				return true
	return false


## 节点此刻是否在教室里；召唤／办公室／返程期间离场，上课挂起时回到课堂。
func is_present(i: int) -> bool:
	return i >= 0 and i < _n and not _is_in_office(i)


func inventory_of(i: int) -> Dictionary:
	return {
		"books": int(_book[i]),
		"confiscated_books": int(_teacher.confiscated[i]),
		"exemption_tokens": int(_teacher.exemption_tokens[i]),
	}


func _start_leisure(i: int, kind: String, ignore_book: bool = false) -> bool:
	return LeisureActions.start_leisure(self, i, kind, ignore_book)


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
		_busy_until[j] = maxi(_busy_until[j], until)
		_busy_phase[j] = _phase_index
		_busy_act[j] = behavior


## 按成员列表占用（群聊编排用）：全体占用与共同结束点**对齐**，只取更晚的结束点。
## 声源只有一个（音量按「场」计）：`sound_source` 之外的人一律不计声源，
## 加入者不会因为「多一个人说话」把音量叠上去。
func _occupy_members(
	members: Array, behavior: String, until: int, sound_source: int, _actor: int = -1
) -> void:
	for m in members:
		var idx := int(m)
		if idx < 0 or idx >= _n:
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
	_current_act[i] = "study"
	_study_start_tick[i] = _global_tick
	# 2026-10-14 学习置占用（聊天机制规格 A）：busy_until 覆盖本段剩余时间，
	# 把「学习中」衔接进 _can_interact_with ↔ busy_until，否则会被聊天／搭话拉走。
	var remaining := int(str(_active_phases[_phase_index]["tick_count"])) - _tick_in_phase
	_busy_until[i] = _global_tick + remaining
	_stats["studies"] = int(_stats.get("studies", 0)) + 1
	_emit("event_happened", {"kind": "study", "i": i})


## 睡觉（§8.8）：玩家主动入睡 —— 与 NPC 同规则（段末由 `_settle_sleep` 一次性减压、
## 期间不被任何人交互）。原规格只写了 NPC 的概率触发。
func _do_sleep(i: int) -> void:
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
## 前置（内核入口自己拒绝，不靠调用方）：双方都不在移动中，且满足真实空间范围（§8.7 / §10.5）。
## ⚠️ 离线标定没有场景几何 / 移动输入时两个前置恒成立，因此不影响同种子标定结果。
func _do_chat(i: int, j: int) -> void:
	if is_moving(i) or is_moving(j) or not chat_pair_in_range(i, j):
		return
	_start_conversation(i, j)


## 搭话（二人会话种子，含接纳判定，规格 E/I）：i 接近 j，j 按 p=σ((score−θ)/scale)
## 接纳则开聊（score 已删四维项）；拒绝则记单向拒绝事件，不占时间槽。无硬闸门。
func _do_chat_join(i: int, j: int, roll: float = -1.0) -> void:
	# 同一套前置（§8.7 / §10.5）：移动中或不在范围内时不进入接纳判定，也不消耗随机数。
	if is_moving(i) or is_moving(j) or not chat_pair_in_range(i, j):
		return
	var p := _join_probability(i, j)
	if roll < 0.0:
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
		# D06 孤立判据：发起者当天主动找伴被拒次数（忙碌 / 满员不算关系拒绝）。
		if _risk != null:
			_risk.register_join_reject(i)
		_stats["skipped_events"] = int(_stats["skipped_events"]) + 1


# ------------------------------------------------------------------ 多人聊天会话子系统（2026-10-14 重构：2→3→4 递进加入）
## 二人开聊（会话种子，规格 B）：形成会话 {i,j}，逐人独立计时，他人可随后加入。
func _start_conversation(i: int, j: int) -> void:
	var members: Array = [i, j]
	# D06 孤立判据：新建共同活动 → 双方当天都算「成功参加共同活动」。
	if _risk != null:
		_risk.register_activity(i)
		_risk.register_activity(j)
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
	# D06 孤立判据：当天成功参加过共同活动。
	if _risk != null:
		_risk.register_activity(k)
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
				add_stress(mi, cost)
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


func _activity_past_half(akind: String, grp: Dictionary) -> bool:
	## 发起者活动进度超过一半则拒绝新人（2026-10-17 交接）：恰好一半允许。目前只对学习生效，
	## 进度 = 原学习者已学时长 / 其整段学习时长；聊天 / 打闹 / 零食的进度基准待接入。
	if akind != "study":
		return false
	var orig := int(grp.get("originator", -1))
	var start := int(grp.get("start_tick", -1))
	if orig < 0 or start < 0:
		return false
	var total := int(_busy_until[orig]) - start
	if total <= 0:
		return false
	return (_global_tick - start) * 2 > total


func _invite_friend_p() -> float:
	## 带朋友：活动组成员每决策点尝试邀请朋友的概率（data：invite_friend_p）。
	return float(_probs.get("invite_friend_p", 0.0))


func _join_blocked(j: int) -> bool:
	## j 此刻不可被邀请（**条件不满足**，不算关系拒绝，§9.1.2/§9.1.4）：
	## 睡觉、不在场、出门、正在走动、游戏锁定；崩溃等不可中断状态同理。
	return (
		_sleeping[j]
		or not is_present(j)
		or _current_act[j] == "leave_class"
		or is_moving(j)
		or (_busy_act[j] == "move" and _global_tick < _busy_until[j])
		or (_phase_state.size() > j and str(_phase_state[j]) == "play")
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
	## "idle" = 空闲；"play" = 游戏锁定（不可被拉出）；听歌／看书返回具体 kind（可共享加入）。
	# 状态锁定（D01，2026-10-17）：学习锁定视同学习（可被请教、不被拉去别的活动）；
	# 游戏锁定不可被拉出。崩溃／睡觉由 _join_blocked 排除，这里防御性再挡一次。
	if not _broken[j] and not _sleeping[j] and _phase_state.size() > j:
		if str(_phase_state[j]) == "study":
			return ["study", _study_of[j]]
		if str(_phase_state[j]) == "play":
			return ["play", null]
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
		# 个人娱乐（2026-10-19）：听歌／看书可被加入，跟随者与发起者同步结束。
		return [str(_busy_act[j]), null]
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
	# D06 孤立判据：投票被拒同样计入「主动找伴被拒」。
	if _risk != null:
		_risk.register_join_reject(i)
	_log_join_event(i, members, "vote_reject", activity, yes, no, {"anchor": anchor})


func _propose_activity(i: int, j: int, kind: String) -> bool:
	## i（空闲发起者）向 j 提议 / 申请加入活动 kind（§9.1.4 决策树）。
	## 返回 true = i 已被占用（成事）；false = 未占用（条件不满足 / 关系拒绝 / 相等不合流）。
	_stats["joins"] = int(_stats["joins"]) + 1
	var act := _join_activity_of(j)
	var akind: String = act[0]
	var group: Variant = act[1]
	# 状态锁定（D01，2026-10-17 交接「不突破状态锁定」）：
	# 游戏锁定不可被拉出；学习锁定只可被「请教加入」，不可被拉去别的活动。
	# 注意这里读 _phase_state 而非 akind：自由学生「正在学习」（phase_state=free、
	# current_act=study）不是锁定，仍可被拉去别的活动（走下方跟随逻辑）。
	if akind == "play":
		_log_join_event(i, [j], "condition_fail", kind, [], [], {"reason": "unshared"})
		return false
	if _phase_state.size() > j and str(_phase_state[j]) == "study":
		return _apply_join_group(i, j, "study", group)
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
	# i 更在意 j：i 加入 j 的原活动（跟随分支只认这四种组；共享娱乐由 try_join_best 走同活动加入）
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
	if FREE_ROAM.is_shared(akind):
		return FREE_ROAM.join_shared_leisure(self, i, anchor, akind)
	var grp: Dictionary = group if group is Dictionary else _ensure_group(akind, anchor)
	if grp.is_empty():
		return false
	var members := (grp["members"] as Array).duplicate()
	members.sort()
	if _activity_past_half(akind, grp):
		_log_join_event(i, members, "condition_fail", akind, [], [], {"reason": "past_half"})
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
			# 学习锁定但尚未轮到决策（被提前请教）：先按原学习者开始学习，保证过半进度基准正确。
			if _study_start_tick[j] < 0:
				_do_study(j)
			# originator = 原学习者（独自开始学习的发起者）；后续加入者为请教者（免动力，见 _settle_units）。
			# start_tick = 原学习者实际开始学习的 tick（过半禁加入的进度基准）。
			var grp := {"members": [j], "originator": j, "start_tick": _study_start_tick[j]}
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
	# D06 孤立判据：加入共同活动（各自按真实学习单位结算）。
	if _risk != null:
		_risk.register_activity(i)
	(grp["members"] as Array).append(i)
	(grp["members"] as Array).sort()
	_study_of[i] = grp


func _join_snack(i: int, grp: Dictionary) -> void:
	## 加入零食分享（§9.1.4 表）：加入者无需自带零食；正常娱乐效果；
	## 自然完成一个共同进食单位后，对分享者结算一次分享好感（见 _settle_finished_actions）。
	_occupy(i, i, "eat_snack")
	# D06 孤立判据：加入共同活动。
	if _risk != null:
		_risk.register_activity(i)
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
	## 带朋友（§9.1.3/§9.1.4）：组成员按找伴规则邀请朋友；每人每决策点最多一次，
	## 本决策点新加入者下个决策点起才能带朋友；朋友仍须全体成员投票。随机数顺序固定。
	var p := _invite_friend_p()
	if p <= 0.0:
		return
	for akind in ["chat", "roughhouse", "study", "snack"]:
		var groups: Array = _groups_of_kind(akind)
		for grp in groups:
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
	## （不同时参与多个活动）。并列取最低节点号。
	var best := -1
	var best_a := 0.0
	var has_best := false
	for f in range(_n):
		if f == m or (grp["members"] as Array).has(f) or _join_blocked(f):
			continue
		# 状态锁定（D01，2026-10-17）：学习锁定／游戏锁定的朋友不能被拉入别的活动。
		if _phase_state.size() > f and str(_phase_state[f]) in ["study", "play"]:
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


## 真正共同活动的只读快照（供底部圈与「能不能加入」查询，深拷贝）。
func get_active_sessions() -> Array:
	return _sessions.active_snapshots()


## 交互几何注入：**纯数据**（障碍矩形 + 房间边界），场景从寻路几何导出后一次注入。
## 未注入时一切交互判定返回明确错误，不静默放行。
func set_interaction_geometry(obstacles: Array, bounds: Rect2) -> void:
	_scene_space_required = true
	_space.set_geometry(obstacles, bounds)


func interaction_space_ready() -> bool:
	return _space.is_ready()


## 闲聊空间几何（规则来源 data/rules/chat_space.csv；2026-10-16 从 player_interaction.csv 迁出）。
func chat_range() -> float:
	return float(_chat_space["chat_range_m"])


func seated_chat_range() -> float:
	return float(_chat_space["seated_chat_range_m"])


func range_step() -> float:
	return float(_chat_space["range_step_m"])


func seated_tolerance() -> float:
	return float(_chat_space["seated_tolerance_m"])


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
			and distance_between(i, j) <= seated_chat_range()
		)
	return (
		_space.position_valid(position_of(j))
		and _space.valid_position_for(position_of(i), [position_of(j)], chat_range(), range_step())
	)


func set_seat_position(i: int, position: Vector2) -> void:
	if i >= 0 and i < _n:
		_seat_world_positions[i] = position


func _at_own_seat(i: int) -> bool:
	return (
		_seat_world_positions.has(i)
		and position_of(i).distance_to(_seat_world_positions[i]) <= seated_tolerance()
	)


## 独立移动状态（由表现层注入）：移动中的学生不被拉进新占用交互；**不是**聊天占用。
func set_moving(i: int, moving: bool) -> void:
	if i < 0 or i >= _n:
		return
	_moving[i] = moving
	if moving and _current_act[i] == "study":
		_current_act[i] = null
		_study_acc[i] = 0.0


func is_moving(i: int) -> bool:
	return i >= 0 and i < _n and bool(_moving[i])


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


## 本局节点顺序的角色编号（查 data/rules/passives.csv 的分配用；不参与行为判断）。
func _character_ids() -> Array[String]:
	var ids: Array[String] = []
	for ch in _chars:
		ids.append(str(ch.get("id", "")))
	return ids


## i 在种子表里的编号（"01"…"24"）。
## 表现层用它查 data/characters/appearance.csv（外观绑定在 data/，不在脚本里判断角色名）。
func character_id(i: int) -> String:
	if i < 0 or i >= _chars.size():
		return ""
	return str(_chars[i].get("id", ""))


## 公开专属被动的 id（主文档 §10.1：档案与行为预览直接显示；空串 = 本局没有分配到被动）。
func passive_id_of(i: int) -> String:
	if _passives == null:
		return ""
	return _passives.id_of(i)


## 老师版学生档案的公开状态快照（§10.1）。只读：不写任何矩阵，也不经观察层过滤 —— 被动是公开信息。
## reveals_incoming_affinity = 群策群力（§10.2）：该生可以看到所有其他同学对本人好感，
## 由档案在只读预览里逐人读 affinity(j, i) 显示。
func teacher_student_snapshot(i: int) -> Dictionary:
	if i < 0 or i >= _n:
		return {}
	var out := {
		"passive_id": _passives.id_of(i),
		"grade_max": float(_kp["grade_max"]),
		"reveals_incoming_affinity": _passives.reveals_incoming_affinity(i),
		"well_informed_messages": _passives.well_informed_messages(i),
		"fight_count": _harm_events.fight_count_of(i) if _harm_events != null else 0,
	}
	var goal := _teacher_commands.encourage_goal_text(self, i)
	if goal != "":
		out["communication_goal"] = goal
	return out


## i 坐的座位号（seats.csv 的 seat_id，如 "P7"）；越界 → 空串。
## ⚠️ 座位由 _assign_seats() 消费内核 RNG 随机分配，表现层必须读这里、不得自行随机，
##    否则画面上「谁挨着谁」会与内核判定用的邻接关系不一致（§15.1 空间聚散）。
func seat_of(i: int) -> String:
	if i < 0 or i >= _seat_of.size():
		return ""
	return str(_seat_of[i])


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
	return tags


func _float_or(row: Dictionary, key: String, fallback: float) -> float:
	var s := str(row.get(key, ""))
	if s == "":
		return fallback
	return float(s)


## 老师位置是环境事实，不暴露 NPC 关系数据。
func teacher_state() -> Dictionary:
	return _teacher.snapshot()
