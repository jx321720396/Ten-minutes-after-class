class_name GroupActivitySpacing
extends RefCounted
## 已成立会话的靠近导航；不扩大可聊天范围，不移动坐在本座位的人。

var _handled: Dictionary = {}


static func has_clearance(
	target: Vector2, occupied: Array[Vector2], reserved: Array[Vector2], gap: float
) -> bool:
	for point in occupied + reserved:
		if target.distance_to(point) < gap:
			return false
	return true


func update(
	core: Variant,
	actors: Array[Node3D],
	walkers: Array,
	roam: Node,
	distance: float,
	minimum_gap: float
) -> void:
	var alive := {}
	for session in core.get_active_sessions():
		var sid := int(session["session_id"])
		alive[sid] = true
		if not _handled.has(sid):
			_handled[sid] = {}
		var members: Array = []
		for member in session["members"]:
			var index := int(member)
			if (
				index < actors.size()
				and core.is_present(index)
				and walkers[index] != null
				and not walkers[index].is_moving()
			):
				members.append(index)
		if members.size() < 2:
			continue
		var anchor := int(members[0])
		for member in members:
			if core._at_own_seat(member):
				anchor = int(member)
				break
		var anchor_pos := Vector2(
			actors[anchor].global_position.x, actors[anchor].global_position.z
		)
		for member in members:
			var index := int(member)
			if (
				index == anchor
				or _handled[sid].has(index)
				or core._at_own_seat(index)
				or str(core.activity_of(index)) == "study"
			):
				continue
			_handled[sid][index] = true
			var pos := actors[index].global_position
			var start := Vector2(pos.x, pos.z)
			var target := closer_target(start, anchor_pos, maxf(distance, minimum_gap))
			if target.is_equal_approx(start) or not core._space.position_valid(target):
				continue
			if core._space.segment_blocked(start, target, core.range_step()):
				continue
			var route: PackedVector3Array = walkers[index]._query_path(
				Vector3(target.x, pos.y, target.y)
			)
			if route.size() < 2:
				continue
			var end := route[route.size() - 1]
			if target.distance_to(Vector2(end.x, end.z)) > core.range_step():
				continue
			var occupied: Array[Vector2] = []
			var reserved: Array[Vector2] = []
			for other in range(actors.size()):
				if other != index and core.is_present(other):
					var point := actors[other].global_position
					occupied.append(Vector2(point.x, point.z))
					if walkers[other] != null and walkers[other].is_moving():
						var goal: Vector3 = walkers[other]._to
						reserved.append(Vector2(goal.x, goal.z))
			var clear := has_clearance(Vector2(end.x, end.z), occupied, reserved, minimum_gap)
			# 拒绝经过当前人物的路线，避免在行走组件里永久等待一个静止同伴。
			for point in occupied:
				for step in range(1, route.size()):
					var first := Vector2(route[step - 1].x, route[step - 1].z)
					var second := Vector2(route[step].x, route[step].z)
					if (
						point.distance_to(
							Geometry2D.get_closest_point_to_segment(point, first, second)
						)
						< minimum_gap
					):
						clear = false
			if clear and roam._send_to_point(index, Vector3(target.x, pos.y, target.y)):
				roam._release_point(index)
	for sid in _handled.keys():
		if not alive.has(sid):
			_handled.erase(sid)


static func closer_target(position: Vector2, anchor: Vector2, distance: float) -> Vector2:
	var offset := position - anchor
	if offset.length() <= distance:
		return position
	return anchor + offset.normalized() * distance
