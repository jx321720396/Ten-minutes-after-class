class_name ActivitySessions
extends RefCounted
## 真实共同活动记录器（内核侧，纯数据）：谁和谁**此刻真的在做同一件事**。
##
## 依据：主文档 §10.31（所有活动都可加入）、§10.4（行为耗时契约）；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §5.1。
##
## 为什么要它：`get_activity_circles()` 只是「按行为名汇总当前动作」，quiet 一方
## 根本没有 `_current_act`，两场并行的闲聊也会被并成一个圈。融合圈、加入查询与
## 「原会话是否还有效」都需要**真实的同一场活动**，而不是按名字分组。
##
## 职责边界：
##   · 只记录真实成立的共同活动（成员、参与连线、统一结束点），不读任何隐藏矩阵、
##     不掷骰、不引用场景节点（内核纯净）；
##   · 一人最多在一个互斥活动里 —— 已属于别场会话的成员不会被悄悄挪过去，
##     调用方拿到明确失败再决定怎么反馈；
##   · 会话编号由计数器生成（**不消耗随机数**），所有对外快照一律深拷贝。

## 会话内部结构：{session_id, kind, members（升序）, links（升序对）, end_tick}
var _sessions: Dictionary = {}
## 成员 → 会话编号（互斥判定的唯一依据）
var _member_of: Dictionary = {}
var _next_id := 1


## 清空全部记录（换局 / 测试用）。
func clear() -> void:
	_sessions.clear()
	_member_of.clear()
	_next_id = 1


## 新开一场共同活动；参与者里有任何人已在别场会话中则拒绝（返回 -1）。
## kind 为空、或去重后不足 2 人同样拒绝 —— 「同一场活动」至少要两个人。
func begin(kind: String, members: Array, end_tick: int) -> int:
	var cleaned := _clean_members(members)
	if cleaned.size() < 2 or kind.is_empty():
		return -1
	for m in cleaned:
		if _member_of.has(m):
			return -1
	return _create(kind, cleaned, end_tick)


## 成立或并入：成员里已在会话中的必须同属**同一个**会话（否则视为冲突，返回 -1）。
## 任何一场真实成立的闲聊都走这里 —— NPC 的旧路径与玩家的加入路径因此只登记一次。
func begin_or_join(kind: String, members: Array, end_tick: int) -> int:
	var cleaned := _clean_members(members)
	if cleaned.size() < 2 or kind.is_empty():
		return -1
	var existing := -1
	for m in cleaned:
		var sid := session_of(m)
		if sid < 0:
			continue
		if existing < 0:
			existing = sid
		elif existing != sid:
			return -1
	if existing < 0:
		return _create(kind, cleaned, end_tick)
	if kind_of(existing) != kind:
		return -1
	for m in cleaned:
		join(existing, m, end_tick)
	return existing


## 让一个成员加入既有会话：新边只连接真正参与的成员。
## · 该成员已在本会话 → 幂等成功（只按需延长结束点）；
## · 该成员在别场会话 → 拒绝（不能同时参加两个互斥活动）。
func join(session_id: int, member: int, end_tick: int) -> bool:
	if not _sessions.has(session_id) or member < 0:
		return false
	var other := session_of(member)
	if other == session_id:
		extend(session_id, end_tick)
		return true
	if other >= 0:
		return false
	var session: Dictionary = _sessions[session_id]
	var members: Array = session["members"]
	members.append(member)
	# 成员升序 + 连线由成员重算：快照与调用顺序无关（决策顺序不影响可复现性）
	members.sort()
	session["links"] = _build_links(members)
	_member_of[member] = session_id
	extend(session_id, end_tick)
	return true


## 延长结束点：**只取更晚的那个**，任何调用都不能把一场进行中的活动改短。
func extend(session_id: int, end_tick: int) -> bool:
	if not _sessions.has(session_id):
		return false
	var session: Dictionary = _sessions[session_id]
	if end_tick <= int(session["end_tick"]):
		return false
	session["end_tick"] = end_tick
	return true


## 成员主动离场；剩不足 2 人时整场结束（返回结束快照，否则空字典）。
func leave(session_id: int, member: int) -> Dictionary:
	if not _sessions.has(session_id) or session_of(member) != session_id:
		return {}
	var session: Dictionary = _sessions[session_id]
	var members: Array = session["members"]
	members.erase(member)
	_member_of.erase(member)
	session["links"] = _build_links(members)
	if members.size() < 2:
		return end(session_id)
	return snapshot(session_id)


## 结束一场会话，返回结束时的深拷贝快照；不存在返回空字典。
func end(session_id: int) -> Dictionary:
	if not _sessions.has(session_id):
		return {}
	var snap := snapshot(session_id)
	var members: Array = _sessions[session_id]["members"]
	for m in members:
		if int(_member_of.get(m, -1)) == session_id:
			_member_of.erase(m)
	_sessions.erase(session_id)
	return snap


## 把所有到期的会话结掉（end_tick ≤ global_tick），返回它们按编号升序的结束快照。
## 同一结束点只会被结掉一次 —— 这是「无双发线索、无双结算」的结构性保证。
func expire(global_tick: int) -> Array:
	var due: Array = []
	for sid in _sessions.keys():
		if int(_sessions[sid]["end_tick"]) <= global_tick:
			due.append(int(sid))
	due.sort()
	var out: Array = []
	for sid in due:
		out.append(end(sid))
	return out


## 某成员此刻所在会话编号；不在任何会话返回 -1。
func session_of(member: int) -> int:
	return int(_member_of.get(member, -1))


func has_session(session_id: int) -> bool:
	return _sessions.has(session_id)


func kind_of(session_id: int) -> String:
	if not _sessions.has(session_id):
		return ""
	return str(_sessions[session_id]["kind"])


func end_tick_of(session_id: int) -> int:
	if not _sessions.has(session_id):
		return -1
	return int(_sessions[session_id]["end_tick"])


## 成员升序副本（改副本不影响内部状态）。
func members_of(session_id: int) -> Array:
	if not _sessions.has(session_id):
		return []
	return (_sessions[session_id]["members"] as Array).duplicate()


## 单场快照（深拷贝）。
func snapshot(session_id: int) -> Dictionary:
	if not _sessions.has(session_id):
		return {}
	return _copy(_sessions[session_id])


## 全部活动快照（按编号升序，深拷贝）—— 供底部圈与「能不能加入」查询。
func active_snapshots() -> Array:
	var ids: Array = _sessions.keys()
	ids.sort()
	var out: Array = []
	for sid in ids:
		out.append(_copy(_sessions[sid]))
	return out


func active_count() -> int:
	return _sessions.size()


## 把成员数组清理成「去重 + 升序」的稳定形态：候选与连线因此与调用顺序无关。
func _clean_members(members: Array) -> Array:
	var seen := {}
	var out: Array = []
	for m in members:
		var idx := int(m)
		if idx < 0 or seen.has(idx):
			continue
		seen[idx] = true
		out.append(idx)
	out.sort()
	return out


func _create(kind: String, members: Array, end_tick: int) -> int:
	var sid := _next_id
	_next_id += 1
	_sessions[sid] = {
		"session_id": sid,
		"kind": kind,
		"members": members.duplicate(),
		"links": _build_links(members),
		"end_tick": end_tick,
	}
	for m in members:
		_member_of[int(m)] = sid
	return sid


## 参与连线：成员两两成对、按 (小, 大) 升序生成 —— 与加入顺序无关的稳定形态。
func _build_links(members: Array) -> Array:
	var links: Array = []
	for a in range(members.size()):
		for b in range(a + 1, members.size()):
			links.append([int(members[a]), int(members[b])])
	return links


func _copy(session: Dictionary) -> Dictionary:
	var members: Array = session["members"]
	var links: Array = []
	for pair in session["links"]:
		links.append([int(pair[0]), int(pair[1])])
	return {
		"session_id": int(session["session_id"]),
		"kind": str(session["kind"]),
		"members": members.duplicate(),
		"links": links,
		"end_tick": int(session["end_tick"]),
	}
