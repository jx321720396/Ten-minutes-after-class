class_name TermReplay
extends RefCounted
## 回放只改展示副本；同tick的每条增减保持顺序。

var history: Dictionary = {}
var cursor := 0
var _matrices: Array = []
var _directions: Dictionary = {}
var _current_frame: Dictionary = {}


func configure(record: Dictionary) -> void:
	history = record.duplicate(true)
	restart()


func restart() -> void:
	cursor = 0
	_matrices = history.get("baseline", []).duplicate(true)
	_directions.clear()
	_current_frame = {"day": 1, "tick": 0, "cause": "opening", "changes": []}


func step() -> bool:
	_directions.clear()
	var frames: Array = history.get("frames", [])
	if cursor >= frames.size():
		return false
	_current_frame = frames[cursor]
	for change in _current_frame.changes:
		var axis := int(change[0])
		var idx := int(change[1])
		_matrices[axis][idx] = float(change[3])
		_directions["%d:%d" % [axis, idx]] = int(signf(float(change[3]) - float(change[2])))
	cursor += 1
	return true


func seek_tick(tick: int) -> void:
	restart()
	for checkpoint in history.get("checkpoints", []):
		if int(checkpoint.tick) <= tick:
			_matrices = checkpoint.matrices.duplicate(true)
			cursor = int(checkpoint.cursor)
			_current_frame = {
				"day": int(checkpoint.day),
				"tick": int(checkpoint.tick),
				"cause": "day_decay",
				"changes": []
			}
	var frames: Array = history.get("frames", [])
	while cursor < frames.size() and int(frames[cursor].tick) <= tick:
		step()
	_directions.clear()


func value(axis: int, source: int, target: int) -> float:
	if source == target or axis < 0 or axis >= _matrices.size():
		return 0.0
	return float(_matrices[axis][source * int(history.get("count", 0)) + target])


func direction(axis: int, source: int, target: int) -> int:
	return int(_directions.get("%d:%d" % [axis, source * int(history.get("count", 0)) + target], 0))


func frame() -> Dictionary:
	return _current_frame.duplicate(true)


func finished() -> bool:
	return cursor >= history.get("frames", []).size()


func last_tick() -> int:
	var frames: Array = history.get("frames", [])
	return int(frames[-1].tick) if not frames.is_empty() else 0


func affects_pair(source: int, target: int) -> bool:
	var count := int(history.get("count", 0))
	for change in _current_frame.get("changes", []):
		if int(change[1]) in [source * count + target, target * count + source]:
			return true
	return str(_current_frame.get("cause", "")) == "day_decay"
