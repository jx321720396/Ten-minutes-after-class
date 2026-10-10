class_name PlayerInvitations
extends RefCounted
## 玩家参与由人决定。邀请是纯数据，等待回应不占用、不结算、不掷骰。

var _core_ref: WeakRef
var _kinds: Dictionary = {}
var _pending: Dictionary = {}
var _results: Dictionary = {}
var _next_allowed: Dictionary = {}
var _next_id := 1
var _timeout := 0
var _cooldown := 0
var _choice: Dictionary = {}


func _init(core: RefCounted, tables: Dictionary, params: Dictionary) -> void:
	_core_ref = weakref(core)
	_timeout = int(params.get("invitation_timeout_ticks", 0))
	_cooldown = int(params.get("invitation_cooldown_ticks", 0))
	for row in tables.get("rules/player_invitation_kinds", {}).get("rows", []):
		_kinds[str(row.behavior)] = str(row.requires_choice) == "1"


## true 表示本次行为必须等待玩家，注册表此时不执行任何效果。
func intercept(kind: String, actor: int, target: int, options: Dictionary) -> bool:
	var core: Variant = _core_ref.get_ref()
	if (
		core == null
		or actor == int(core.node_count()) - 1
		or not bool(_kinds.get(kind, false))
		or (not _choice.is_empty() and int(_choice.actor) == actor)
	):
		return false
	var me := int(core.node_count()) - 1
	var sid: int = int(core.session_of(target))
	var involves_player := target == me
	if kind == "chat" and sid >= 0:
		involves_player = involves_player or int(core.session_of(me)) == sid
	if not involves_player:
		return false
	expire()
	if not _pending.is_empty() or int(core.global_tick()) < int(_next_allowed.get(actor, 0)):
		return true
	var invite_kind := "chat" if kind == "chat" and sid >= 0 else kind
	var candidate := {
		"id": _next_id,
		"kind": invite_kind,
		"actor": actor,
		"target": target,
		"session_id": sid if invite_kind == "chat" else -1,
		"phase": int(core._phase_index),
		"expires_tick": int(core.global_tick()) + _timeout,
		"options": options.duplicate(true),
	}
	if _timeout <= 0 or not _valid(candidate):
		return true
	_pending = candidate
	_next_id += 1
	_next_allowed[actor] = int(core.global_tick()) + _cooldown
	return true


## 只读查询；不把内部参数或隐藏关系数值交给 UI。
func pending() -> Dictionary:
	if _pending.is_empty() or not _valid(_pending):
		return {}
	var out := _pending.duplicate(true)
	out.erase("options")
	return out


func expire() -> void:
	if _pending.is_empty() or _valid(_pending):
		return
	_results[int(_pending.id)] = {"ok": false, "error": "invitation_expired"}
	_pending = {}


## 同一个编号只能回应一次；改变按钮也不会重结算。
func respond(id: int, accepted: bool) -> Dictionary:
	expire()
	if _results.has(id):
		return (_results[id] as Dictionary).duplicate(true)
	if _pending.is_empty() or int(_pending.id) != id:
		return {"ok": false, "error": "unknown_invitation"}
	var rec := _pending
	_pending = {}
	var core: Variant = _core_ref.get_ref()
	var kind := str(rec.kind)
	var options: Dictionary = rec.options.duplicate(true)
	if kind == "chat" and int(rec.session_id) >= 0:
		options["mode"] = "group"
		options["session_id"] = int(rec.session_id)
		options["members"] = core._sessions.members_of(int(rec.session_id))
	_choice = {"actor": int(rec.actor), "accepted": accepted}
	if accepted or kind in ["apologize"]:
		core._behavior_registry.execute(StringName(kind), int(rec.actor), int(rec.target), options)
	_choice = {}
	var result := {"ok": true, "id": id, "accepted": accepted, "kind": kind}
	_results[id] = result
	return result.duplicate(true)


func choice_for(actor: int) -> Variant:
	if _choice.is_empty() or int(_choice.actor) != actor:
		return null
	return bool(_choice.accepted)


func authorizes(actor: int) -> bool:
	return choice_for(actor) == true


func is_waiting(actor: int) -> bool:
	return not _pending.is_empty() and int(_pending.actor) == actor and _valid(_pending)


func _valid(rec: Dictionary) -> bool:
	var core: Variant = _core_ref.get_ref()
	if core == null:
		return false
	var actor := int(rec.actor)
	var target := int(rec.target)
	var me := int(core.node_count()) - 1
	if actor < 0 or actor >= me or target < 0 or target > me:
		return false
	if int(core.global_tick()) >= int(rec.expires_tick) or int(core._phase_index) != int(rec.phase):
		return false
	var kind := str(rec.kind)
	if not core._allowed(kind):
		return false
	if (
		core._sleeping[me]
		or core._sleeping[actor]
		or core.is_moving(me)
		or core.is_moving(actor)
		or core.is_busy(actor)
	):
		return false
	return _valid_participants(core, rec, me)


func _valid_participants(core: Variant, rec: Dictionary, me: int) -> bool:
	var actor := int(rec.actor)
	var target := int(rec.target)
	var sid := int(rec.session_id)
	if sid >= 0:
		if int(core.session_of(target)) != sid or int(core.session_of(me)) != sid:
			return false
		for member in core._sessions.members_of(sid):
			if not core.chat_pair_in_range(actor, int(member)):
				return false
		return int(core.session_end_tick(sid)) > int(core.global_tick())
	if core.is_busy(me) or core.is_busy(target) or core._sleeping[target] or core.is_moving(target):
		return false
	return core.chat_pair_in_range(actor, me)
