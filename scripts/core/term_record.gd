class_name TermRecord
extends RefCounted
## 本局只读历史：不拥有随机数，不回写矩阵，不持有场景节点。

const AXES := ["affinity", "hostility"]

var _count := 0
var _player := -1
var _baseline: Array = []
var _current: Array = []
var _frames: Array = []
var _checkpoints: Array = []
var _actions: Dictionary = {}
var _pending: Dictionary = {}
var _state_pending: Dictionary = {}
var _names: Array = []
var _phase_names: Dictionary = {}
var _seconds_per_tick: Dictionary = {}
var _study_seconds := 0.0
var _grade_start := 0.0
var _moving := false
var _finished := false
var _term_days := 0


func configure(core: Variant, tables: Dictionary) -> void:
	_count = int(core.node_count())
	_player = _count - 1
	_grade_start = float(core.grade(_player))
	for row in tables.get("rules/time_runtime", {}).get("rows", []):
		if str(row.key) == "term_days":
			_term_days = int(row.value)
	for i in _count:
		_names.append("你" if i == _player else core.alias(i))
	var ticks := {}
	for row in tables.get("rules/phases", {}).get("rows", []):
		ticks[str(row.phase_id)] = int(row.tick_count)
	for row in tables.get("rules/time_presentation", {}).get("rows", []):
		var key := str(row.phase_id)
		_phase_names[key] = str(row.display_name)
		_seconds_per_tick[key] = (
			float(row.game_duration_seconds) / float(ticks[key]) if int(ticks[key]) > 0 else 0.0
		)
	_baseline = _matrices(core)
	_current = _baseline.duplicate(true)


func _matrices(core: Variant) -> Array:
	var result: Array = []
	for axis in AXES:
		var matrix := PackedFloat64Array()
		matrix.resize(_count * _count)
		for i in _count:
			for j in _count:
				matrix[i * _count + j] = float(core.call(axis, i, j))
		result.append(matrix)
	return result


func record_changes(core: Variant, changes: Array, cause: String) -> void:
	if _finished or changes.is_empty():
		return
	for change in changes:
		_current[int(change[0])][int(change[1])] = float(change[3])
	var time: Dictionary = core.time_snapshot()
	(
		_frames
		. append(
			{
				"tick": int(core.global_tick()),
				"day": int(core.day()),
				"phase": str(time.get("phase_id", "")),
				"cause": cause,
				"changes": changes.duplicate(true),
			}
		)
	)


## 收集不走事件写入的传导/衰减等，保持事件与非事件的最终状态一致。
func capture(core: Variant, cause: String) -> void:
	if _finished:
		return
	var changes: Array = []
	for axis_index in AXES.size():
		for i in _count:
			for j in _count:
				if i == j:
					continue
				var idx := i * _count + j
				var before := float(_current[axis_index][idx])
				var after := float(core.call(AXES[axis_index], i, j))
				if before != after:
					changes.append([axis_index, idx, before, after])
	record_changes(core, changes, cause)


func settle_day(core: Variant, ended_day: int) -> void:
	if _finished:
		return
	capture(core, "day_decay")
	(
		_checkpoints
		. append(
			{
				"day": ended_day,
				"tick": int(core.global_tick()),
				"cursor": _frames.size(),
				"matrices": _current.duplicate(true),
			}
		)
	)
	_finished = ended_day >= _term_days


func _row(kind: String) -> Dictionary:
	if not _actions.has(kind):
		_actions[kind] = {
			"started": 0,
			"completed": 0,
			"rejected": 0,
			"interrupted": 0,
			"initiated": 0,
			"invited": 0,
			"invite_declined": 0,
		}
	return _actions[kind]


func begin_action(kind: String, actor: int, participants: Array) -> void:
	if _finished or not participants.has(_player):
		return
	end_state("study")
	if not _pending.is_empty() and str(_pending.kind) == kind:
		return  # 群聊扩展占用是同一件事，不按对象计数。
	if not _pending.is_empty():
		end_action("interrupted")
	_row(kind).started += 1
	_pending = {"kind": kind, "actor": actor}


func end_action(outcome: String) -> void:
	if _pending.is_empty():
		return
	var row := _row(str(_pending.kind))
	row[outcome] = int(row.get(outcome, 0)) + 1
	if outcome == "completed":
		row["initiated" if int(_pending.actor) == _player else "invited"] += 1
	_pending = {}


func rejected(kind: String, actor: int) -> void:
	if actor != _player or _finished:
		return
	if not _pending.is_empty() and str(_pending.kind) == kind:
		end_action("rejected")
	else:
		_row(kind).started += 1
		_row(kind).rejected += 1


func begin_state(kind: String) -> void:
	if _finished or _state_pending.has(kind):
		return
	_row(kind).started += 1
	_state_pending[kind] = true


func end_state(kind: String) -> void:
	if not _state_pending.has(kind):
		return
	_state_pending.erase(kind)
	_row(kind).completed += 1
	_row(kind).initiated += 1


func instant(kind: String) -> void:
	if _finished:
		return
	_row(kind).started += 1
	_row(kind).completed += 1
	_row(kind).initiated += 1


func moving(value: bool, is_break: bool) -> void:
	if value and not _moving and is_break and not _finished:
		begin_state("move")
		end_state("study")
	if not value:
		end_state("move")
	_moving = value


func tick_state(core: Variant) -> void:
	if _finished:
		return
	var act := str(core.activity_of(_player))
	if act != "study":
		end_state("study")
	if act == "study" and core.is_present(_player) and str(core.phase()) == "break":
		var phase_id := str(core.time_snapshot().get("phase_id", ""))
		_study_seconds += float(_seconds_per_tick.get(phase_id, 0.0))


func event(payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))
	if payload.has("accepted") and not bool(payload.accepted):
		rejected(kind, int(payload.get("i", -1)))
	if kind == "book_confiscated" and int(payload.get("i", -1)) == _player:
		end_action("interrupted")


func invitation(kind: String, accepted: bool) -> void:
	if not accepted:
		_row(kind).invite_declined += 1


func snapshot(core: Variant) -> Dictionary:
	return {
		"version": 1,
		"count": _count,
		"player": _player,
		"names": _names.duplicate(),
		"phase_names": _phase_names.duplicate(),
		"baseline": _baseline.duplicate(true),
		"frames": _frames.duplicate(true),
		"checkpoints": _checkpoints.duplicate(true),
		"actions": _actions.duplicate(true),
		"study_seconds": _study_seconds,
		"grade_start": _grade_start,
		"grade_end": float(core.grade(_player)),
		"finished": _finished,
		"ended_day": int(core.day()) - 1,
		"seed": int(core.seed()),
		"exam_report": str(core.exam_report(int(core.day()) - 1)),
	}


# ------------------------------------------------------------------ 存档
## 导出历史运行时状态。_baseline / _names / _phase_names 等由 configure 从 seed + tables 重建，不存。
func export_state() -> Dictionary:
	return {
		"current": _matrices_to_array(_current),
		"frames": _frames.duplicate(true),
		"checkpoints": _checkpoints.duplicate(true),
		"actions": _actions.duplicate(true),
		"pending": _pending.duplicate(true),
		"state_pending": _state_pending.duplicate(true),
		"study_seconds": _study_seconds,
		"moving": _moving,
		"finished": _finished,
	}


## 回填历史运行时状态（读档用）。JSON 往返把 int / 内嵌矩阵的 Packed 数组变 float，逐个还原。
func restore_state(data: Dictionary) -> void:
	_current = _array_to_matrices(data.get("current", []))
	_frames = data.get("frames", []).duplicate(true)
	_checkpoints = data.get("checkpoints", []).duplicate(true)
	_actions = {}
	for kind in data.get("actions", {}):
		var row: Dictionary = data["actions"][kind]
		var norm: Dictionary = {}
		for field in row:
			norm[field] = int(row[field])
		_actions[str(kind)] = norm
	var pending: Dictionary = data.get("pending", {})
	_pending = {}
	if not pending.is_empty():
		_pending = {"kind": str(pending.get("kind", "")), "actor": int(pending.get("actor", -1))}
	_state_pending = data.get("state_pending", {}).duplicate(true)
	_study_seconds = float(data.get("study_seconds", 0.0))
	_moving = bool(data.get("moving", false))
	_finished = bool(data.get("finished", false))


func _matrices_to_array(matrices: Array) -> Array:
	var out: Array = []
	for matrix in matrices:
		out.append(Array(matrix))
	return out


func _array_to_matrices(raw: Array) -> Array:
	var out: Array = []
	for rows in raw:
		out.append(PackedFloat64Array(rows))
	return out
