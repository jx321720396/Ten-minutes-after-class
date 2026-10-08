class_name PlayerInteractions
extends RefCounted
## 玩家交互服务（内核侧）：闲聊的统一入口 —— 校验、幂等提交、请求状态与完成 / 中断。
##
## 依据：主文档 §10.5（闲聊）、§10.7（加入闲聊）、§10.31（所有活动都可加入）、
##      §10.32（同一次判定两种呈现）、§12.1／§12.2（玩家不是特权者）；
##      docs/superpowers/plans/2026-07-07-chat-playable-loop.md §5。
##
## 三条铁律：
##   ① **只读预览零副作用**：`preview()` 不掷骰、不改矩阵、不新增占用与会话；
##   ② **一次合法加入只有一次接受判定**：roll 由本服务在提交时掷一次，展示值来自信念；
##   ③ **失败不落地**：校验不通过时没有结算、没有占用、没有会话，返回明确错误码。
##
## 与内核的关系：弱引用内核（不持有强引用），只读矩阵与内部运行态；所有写入都经由
## 内核既有的统一结算服务（`_behavior_registry`），本服务不复制公式。

const KIND_CHAT := "chat"
const MODE_START := "start"
const MODE_JOIN := "join"

const STATUS_ACTIVE := "active"
const STATUS_COMPLETED := "completed"
const STATUS_INTERRUPTED := "interrupted"

const OUTCOME_STARTED := "chat_started"
const OUTCOME_JOIN_ACCEPTED := "join_accepted"
const OUTCOME_JOIN_REJECTED := "join_rejected"

## 拒绝理由（表现层据此显示「为什么现在不能聊」）
const REASON_PLAYER_BUSY := "player_busy"
const REASON_PHASE := "phase_not_allowed"
const REASON_MOVING := "player_moving"
const REASON_TARGET_SLEEPING := "target_sleeping"
const REASON_TARGET_BUSY := "target_busy"
const REASON_GEOMETRY := "geometry_missing"
const REASON_OUT_OF_RANGE := "out_of_range"
const REASON_LAYOUT := "group_layout_invalid"

var _core_ref: WeakRef
var _space: InteractionSpace
var _sessions: ActivitySessions
var _intel: PlayerChatIntel
## 交互几何参数（来自 data/rules/player_interaction.csv）
var _chat_range := 1.2
var _step_m := 0.1
var _seated_tolerance := 0.0
var _seated_chat_range := 0.0
## request_id → 请求记录
var _requests: Dictionary = {}
var _next_request_id := 1
## 独立移动状态（不是聊天占用：玩家走路时不该被自己挡住）
var _moving: Dictionary = {}


func _init(
	core: RefCounted,
	space: InteractionSpace,
	sessions: ActivitySessions,
	intel: PlayerChatIntel
) -> void:
	_core_ref = weakref(core)
	_space = space
	_sessions = sessions
	_intel = intel


## 注入交互几何参数（表值；不落魔法数字）。
func configure(params: Dictionary) -> void:
	_chat_range = float(params.get("chat_range_m", _chat_range))
	_step_m = float(params.get("range_step_m", _step_m))
	_seated_tolerance = float(params.get("seated_tolerance_m", 0.0))
	_seated_chat_range = float(params.get("seated_chat_range_m", 0.0))


func chat_range() -> float:
	return _chat_range


func range_step() -> float:
	return _step_m


func seated_tolerance() -> float:
	return _seated_tolerance


func seated_chat_range() -> float:
	return _seated_chat_range


func space() -> InteractionSpace:
	return _space


# ------------------------------------------------------------------ 请求编号与状态
## 内核分配请求编号：只生成编号，**不掷骰、不改任何状态**。
func next_request_id() -> int:
	var rid := _next_request_id
	_next_request_id += 1
	return rid


## 请求状态查询（深拷贝）：status = active / completed / interrupted。
## 拒绝也先处于 active 等占用到期，不依赖只存在一 tick 的「刚完成」。
func get_request(request_id: int) -> Dictionary:
	if not _requests.has(request_id):
		return {"ok": false, "error": "unknown_request"}
	var rec: Dictionary = _requests[request_id]
	return {"ok": true, "request": _copy_record(rec)}


func has_active_request() -> bool:
	for rid in _requests:
		if str(_requests[rid]["status"]) == STATUS_ACTIVE:
			return true
	return false


func request_count() -> int:
	return _requests.size()


## 独立移动状态：只影响「能不能被拉进新交互」，不影响玩家自己的移动。
func set_moving(i: int, moving: bool) -> void:
	if moving:
		_moving[i] = true
	else:
		_moving.erase(i)


func is_moving(i: int) -> bool:
	return _moving.has(i)


## 本局已获得的线索（历史日志，深拷贝）。
func intel_history() -> Array:
	return _intel.history()


func intel_clue_count() -> int:
	return _intel.clue_count()


# ------------------------------------------------------------------ 预览（只读）
## 只读预览：返回参与方式、合法性、范围与（仅 join）信念估计。零副作用、零 RNG。
func preview(kind: String, target: int) -> Dictionary:
	var core: Variant = _core()
	if core == null:
		return {"ok": false, "error": "no_core"}
	if kind != KIND_CHAT:
		return {"ok": false, "error": "unknown_kind"}
	var me := _player_index()
	var count: int = int(core.node_count())
	if target < 0 or target >= count or target == me:
		return {"ok": false, "error": "invalid_target"}
	var out := {
		"ok": true,
		"kind": KIND_CHAT,
		"target": target,
		"mode": MODE_START,
		"session_id": -1,
		"eligible": false,
		"in_range": false,
		"reason": "",
		"duration_ticks": _duration(core, "chat"),
		"reject_duration_ticks": _duration(core, "join_chat"),
		"p_belief": -1.0,
	}
	var session_id: int = int(_sessions.session_of(target))
	var joining: bool = session_id >= 0 and _sessions.kind_of(session_id) == KIND_CHAT
	if joining:
		out["mode"] = MODE_JOIN
		out["session_id"] = session_id
		out["p_belief"] = float(core._join_feedback(me, target)["p"])
	# 先给「为什么不能聊」的状态原因（更贴近玩家视角），几何缺失作为独立错误后置
	var reason := _blocked_reason(core, me, target, joining)
	if not reason.is_empty():
		out["reason"] = reason
		return out
	if not _space.is_ready():
		out["reason"] = REASON_GEOMETRY
		return out
	var members: Array = _sessions.members_of(session_id) if joining else [target]
	if joining:
		for a in members:
			for b in members:
				if a != b and not core.chat_pair_in_range(int(a), int(b)):
					out["reason"] = REASON_LAYOUT
					return out
	out["eligible"] = true
	out["in_range"] = true
	for member in members:
		if not core.chat_pair_in_range(me, int(member)):
			out["in_range"] = false
			break
	if not bool(out["in_range"]):
		out["reason"] = REASON_OUT_OF_RANGE
	return out


## 玩家此刻「为什么不能聊」（空串 = 通过）。真实原因只来自状态，不来自 UI 猜测。
func _blocked_reason(core: Variant, me: int, target: int, joining: bool) -> String:
	if core._sleeping[me] or core.is_busy(me):
		return REASON_PLAYER_BUSY
	if not core._allowed(KIND_CHAT):
		return REASON_PHASE
	if is_moving(me):
		return REASON_MOVING
	if core._sleeping[target]:
		return REASON_TARGET_SLEEPING
	if is_moving(target):
		return "target_moving"
	if joining:
		# 加入既有闲聊：只要求「目标在他那场闲聊里」，不因忙碌拒绝（同一场活动允许新增成员）
		var session_id := int(_sessions.session_of(target))
		for m in _sessions.members_of(session_id):
			if core._sleeping[m]:
				return REASON_TARGET_SLEEPING
			if is_moving(int(m)):
				return "target_moving"
		return ""
	if core.is_busy(target):
		return REASON_TARGET_BUSY
	return ""


## 提交时要满足距离条件的目标点集合（start：目标一人；join：全体原成员）。
func _target_positions(
	core: Variant, me: int, target: int, joining: bool, session_id: int
) -> Array:
	if joining:
		return _member_positions(core, session_id)
	return [core.position_of(target)]


func _member_positions(core: Variant, session_id: int) -> Array:
	var out: Array = []
	for m in _sessions.members_of(session_id):
		out.append(core.position_of(int(m)))
	return out


# ------------------------------------------------------------------ 提交（原子）
## 原子提交：再次校验并执行；成功返回缓存包，失败不掷骰、不改矩阵、不新增占用与会话。
## 同一 request_id 改目标 / 行为 / 参与方式 → request_conflict。
func commit(
	request_id: int, kind: String, target: int, mode: String, session_id: int = -1
) -> Dictionary:
	var core: Variant = _core()
	if core == null:
		return {"ok": false, "error": "no_core"}
	if request_id <= 0:
		return {"ok": false, "error": "invalid_request_id"}
	if kind != KIND_CHAT:
		return {"ok": false, "error": "unknown_kind"}
	var cached: Variant = _requests.get(request_id, null)
	if cached != null:
		return _replay(cached, kind, target, mode, session_id)
	var pv := preview(kind, target)
	if not bool(pv.get("ok", false)):
		return {"ok": false, "error": str(pv.get("error", "invalid"))}
	if str(pv["mode"]) != mode:
		return {"ok": false, "error": "mode_changed"}
	if mode == MODE_JOIN and int(pv["session_id"]) != session_id:
		return {"ok": false, "error": "session_changed"}
	if not bool(pv["eligible"]):
		return {"ok": false, "error": str(pv["reason"])}
	if not bool(pv["in_range"]):
		return {"ok": false, "error": REASON_OUT_OF_RANGE}
	if mode == MODE_JOIN:
		return _commit_join(request_id, target, session_id, pv)
	return _commit_start(request_id, target, pv)


## 同 request_id 重复调用：签名一致返回缓存结果，否则冲突；已中断的请求不再受理。
func _replay(rec: Dictionary, kind: String, target: int, mode: String, session_id: int) -> Dictionary:
	if not _same_signature(rec, kind, target, mode, session_id):
		return {"ok": false, "error": "request_conflict"}
	if str(rec["status"]) == STATUS_INTERRUPTED:
		return {"ok": false, "error": "request_interrupted"}
	return (rec["packet"] as Dictionary).duplicate(true)


func _same_signature(
	rec: Dictionary, kind: String, target: int, mode: String, session_id: int
) -> bool:
	if str(rec["kind"]) != kind or int(rec["target"]) != target:
		return false
	if str(rec["mode"]) != mode:
		return false
	if mode == MODE_JOIN and int(rec["origin_session"]) != session_id:
		return false
	return true


func _commit_start(request_id: int, target: int, pv: Dictionary) -> Dictionary:
	var core: Variant = _core()
	var me := _player_index()
	var before := _player_snapshot(core, me)
	core._behavior_registry.execute(&"chat", me, target, {})
	var session_id := int(_sessions.session_of(me))
	var end_tick: int = int(core._busy_until[me])
	var effects := _player_effects(core, me, before)
	var packet := _packet(request_id, MODE_START, target, session_id, true, end_tick, pv, effects)
	_store(
		request_id,
		KIND_CHAT,
		MODE_START,
		target,
		-1,
		session_id,
		STATUS_ACTIVE,
		OUTCOME_STARTED,
		true,
		end_tick,
		packet
	)
	return packet


func _commit_join(request_id: int, target: int, session_id: int, pv: Dictionary) -> Dictionary:
	var core: Variant = _core()
	var me := _player_index()
	var members := _sessions.members_of(session_id)
	var before := _player_snapshot(core, me)
	# 一次合法加入只有一次接受判定：这里掷一次骰，展示值来自信念（§10.32.3）
	var roll: float = float(core._rng.random())
	var accepted: bool = roll < float(core._join_probability(me, target))
	core._behavior_registry.execute(
		&"join_chat",
		me,
		target,
		{"mode": "group", "session_id": session_id, "members": members, "roll": roll}
	)
	var linked := session_id if accepted else -1
	var end_tick: int = (
		int(_sessions.end_tick_of(session_id)) if accepted else int(core._busy_until[me])
	)
	var outcome := OUTCOME_JOIN_ACCEPTED if accepted else OUTCOME_JOIN_REJECTED
	var effects := _player_effects(core, me, before)
	var packet := _packet(request_id, MODE_JOIN, target, linked, accepted, end_tick, pv, effects)
	packet["session_id"] = session_id
	packet["linked_session"] = linked
	_store(
		request_id,
		KIND_CHAT,
		MODE_JOIN,
		target,
		session_id,
		linked,
		STATUS_ACTIVE,
		outcome,
		accepted,
		end_tick,
		packet
	)
	return packet


func _store(
	request_id: int,
	kind: String,
	mode: String,
	target: int,
	origin_session: int,
	linked_session: int,
	status: String,
	outcome: String,
	accepted: bool,
	end_tick: int,
	packet: Dictionary
) -> void:
	_requests[request_id] = {
		"request_id": request_id,
		"kind": kind,
		"mode": mode,
		"target": target,
		"origin_session": origin_session,
		"linked_session": linked_session,
		"status": status,
		"outcome": outcome,
		"accepted": accepted,
		"end_tick": end_tick,
		"packet": packet.duplicate(true),
	}


func _packet(
	request_id: int,
	mode: String,
	target: int,
	session_id: int,
	accepted: bool,
	end_tick: int,
	pv: Dictionary,
	effects: Dictionary
) -> Dictionary:
	return {
		"ok": true,
		"request_id": request_id,
		"kind": KIND_CHAT,
		"mode": mode,
		"target": target,
		"session_id": session_id,
		"linked_session": session_id,
		"accepted": accepted,
		"end_tick": end_tick,
		"p_belief": float(pv.get("p_belief", -1.0)),
		"duration_ticks": int(pv.get("duration_ticks", 0)),
		"player_effects": effects,
	}


# ------------------------------------------------------------------ 玩家自身效果摘要
## 只统计**玩家自己这一侧**的变化（自身压力 + 玩家→他人三轴合计），供情绪反馈使用。
## 不扫 NPC 内心，也不泄露他人对玩家的真值。
func _player_snapshot(core: Variant, me: int) -> Dictionary:
	var n: int = int(core.node_count())
	var aff := 0.0
	var hos := 0.0
	var tru := 0.0
	for j in range(n):
		if j == me:
			continue
		aff += float(core._a[me * n + j])
		hos += float(core._h[me * n + j])
		tru += float(core._t[me * n + j])
	return {"stress": float(core._stress[me]), "a": aff, "h": hos, "t": tru}


func _player_effects(core: Variant, me: int, before: Dictionary) -> Dictionary:
	var after := _player_snapshot(core, me)
	return {
		"stress_delta": snapped(float(after["stress"]) - float(before["stress"]), 0.1),
		"affinity_delta": snapped(float(after["a"]) - float(before["a"]), 0.1),
		"hostility_delta": snapped(float(after["h"]) - float(before["h"]), 0.1),
		"trust_delta": snapped(float(after["t"]) - float(before["t"]), 0.1),
	}


# ------------------------------------------------------------------ 内核回调：完成 / 中断
## 自然完成：会话到期。读取**这一刻**的真值生成线索 → 写入本局日志 → 返回待发布通知。
## 返回的通知由内核照原顺序经 event_sink 发布（本服务不直接持有事件出口）。
func on_sessions_completed(snapshots: Array) -> Array:
	var out: Array = []
	for snap in snapshots:
		var session_id: int = int(snap["session_id"])
		var rec := _find_active_by_session(session_id)
		if rec.is_empty():
			continue
		out.append_array(_complete_request(rec, session_id, snap))
	return out


## 占用到期（拒绝加入的 10 tick 占用）：拒绝没有会话，靠占用结束收尾，不发线索。
func on_occupancy_completed(at_tick: int) -> Array:
	var out: Array = []
	for rid in _sorted_request_ids():
		var rec: Dictionary = _requests[rid]
		if str(rec["status"]) != STATUS_ACTIVE or int(rec["linked_session"]) >= 0:
			continue
		if int(rec["end_tick"]) > at_tick:
			continue
		out.append(_finish_request(rid, rec, STATUS_COMPLETED))
	return out


## 铃声中断：会话未到期就被清掉（或玩家占用被清掉）→ interrupted，不再发完成类信息。
func on_interrupted(snapshots: Array, members: Array) -> Array:
	var out: Array = []
	var session_ids := {}
	for snap in snapshots:
		session_ids[int(snap["session_id"])] = true
	var touched := {}
	for m in members:
		touched[int(m)] = true
	for rid in _sorted_request_ids():
		var rec: Dictionary = _requests[rid]
		if str(rec["status"]) != STATUS_ACTIVE:
			continue
		var linked: int = int(rec["linked_session"])
		var hit := linked >= 0 and session_ids.has(linked)
		if not hit and linked < 0:
			hit = touched.has(_player_index())
		if not hit:
			continue
		out.append(_finish_request(rid, rec, STATUS_INTERRUPTED))
	return out


## 一个请求真正完成：先读情报写日志，再标记状态（顺序见计划 §5.3）。
func _complete_request(rec: Dictionary, session_id: int, snap: Dictionary) -> Array:
	var core: Variant = _core()
	var out: Array = []
	var request_id: int = int(rec["request_id"])
	var source: int = int(rec["target"])
	var clues: Array = []
	if core != null:
		clues = _draw_clues(core, request_id, session_id, source)
	# 线索通知排在完成通知**之前**：完成通知一旦发出，调用方就会收掉本次请求的上下文
	for clue in clues:
		out.append({
			"kind": "player_intel_received",
			"request_id": request_id,
			"session_id": session_id,
			"clue": clue,
		})
	out.append(_finish_request(request_id, rec, STATUS_COMPLETED))
	return out


## 抽取线索：条数由**闲聊对象当时的透明度**决定，候选排除玩家与 source，
## 每条只透露一个轴，取值来自自然完成这一刻的真值矩阵。
func _draw_clues(core: Variant, request_id: int, session_id: int, source: int) -> Array:
	var me := _player_index()
	var candidates: Array = []
	var n: int = int(core.node_count())
	for j in range(n):
		if j == me or j == source:
			continue
		candidates.append(j)
	candidates.sort()
	var drawn := _intel.draw_subjects(float(core._o[source]), candidates)
	var at := {
		"day": int(core.day()),
		"phase_id": str(core.time_snapshot().get("phase_id", "")),
		"global_tick": int(core.global_tick()),
	}
	var out: Array = []
	for entry in drawn:
		var subject: int = int(entry["subject"])
		var axis := str(entry["axis"])
		out.append(
			_intel.record(
				request_id, session_id, source, subject, axis, _axis_value(core, source, subject, axis), at
			)
		)
	return out


## 单轴真值：source → subject 方向明确，绝不写成反方向。
func _axis_value(core: Variant, source: int, subject: int, axis: String) -> float:
	match axis:
		"hostility":
			return float(core.hostility(source, subject))
		"trust":
			return float(core.trust(source, subject))
		_:
			return float(core.affinity(source, subject))


func _finish_request(request_id: int, rec: Dictionary, status: String) -> Dictionary:
	rec["status"] = status
	_requests[request_id] = rec
	var interrupted: bool = status == STATUS_INTERRUPTED
	return {
		"kind": "player_interaction_interrupted" if interrupted else "player_interaction_finished",
		"request_id": request_id,
		"mode": str(rec["mode"]),
		"target": int(rec["target"]),
		"session_id": int(rec["linked_session"]),
		"origin_session": int(rec["origin_session"]),
		"outcome": str(rec["outcome"]),
		"accepted": bool(rec["accepted"]),
		"player_effects": (rec["packet"] as Dictionary).get("player_effects", {}),
	}


# ------------------------------------------------------------------ 内部工具
func _core() -> Variant:
	if _core_ref == null:
		return null
	return _core_ref.get_ref()


func _player_index() -> int:
	var core: Variant = _core()
	if core == null:
		return -1
	return int(core.node_count()) - 1


func _duration(core: Variant, behavior: String) -> int:
	var row: Dictionary = core._behaviors.get(behavior, {})
	return int(row.get("duration", 0))


func _find_active_by_session(session_id: int) -> Dictionary:
	for rid in _sorted_request_ids():
		var rec: Dictionary = _requests[rid]
		if str(rec["status"]) == STATUS_ACTIVE and int(rec["linked_session"]) == session_id:
			return rec
	return {}


func _sorted_request_ids() -> Array:
	var ids: Array = _requests.keys()
	ids.sort()
	return ids


func _copy_record(rec: Dictionary) -> Dictionary:
	var packet: Dictionary = rec["packet"]
	return {
		"request_id": int(rec["request_id"]),
		"kind": str(rec["kind"]),
		"mode": str(rec["mode"]),
		"target": int(rec["target"]),
		"session_id": int(rec["linked_session"]),
		"origin_session": int(rec["origin_session"]),
		"status": str(rec["status"]),
		"outcome": str(rec["outcome"]),
		"accepted": bool(rec["accepted"]),
		"end_tick": int(rec["end_tick"]),
		"packet": packet.duplicate(true),
	}
