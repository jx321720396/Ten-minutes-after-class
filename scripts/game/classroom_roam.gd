extends Node3D
## 课间走动驱动器（表现层；**不是玩法真相**）。
##
## 时间由内核驱动：本组件**不自造节拍**，课间 / 上课边界一律来自 `SimulationClock` 的
## `phase_changed`（而时钟只调用内核对拍接口）。这里负责把主文档 §10.4 的
## 「课间走动 → 段末 / 上课归位」表现出来。
##
## 做什么：
##   · **课间段**：每隔 `decide_interval` 秒让一部分 NPC 离座，目标按 §10.4 的权重式挑
##     （`1 + Σ_j A[i][j]/100 − Σ_j H[i][j]/200`，目标点附近有活动圈则 ×1.5，下限 0.1）；
##   · **上课段**：进入上课时全体走回自己座位，整段不动（§10.4 第 6 条归位）；
##   · **占用**：每个站立点同时只容纳一个人（含玩家），先到者锁定（NPC移动决策 §2.2）；
##   · **玩家**：点击地面任意位置走过去（快照 `player_control` 为假时直接拒绝点击）。
##
## 数值口径：
##   · 移动耗时 = `data/rules/behaviors.csv` 的 `move.duration`（15 tick）×
##     `data/rules/time_presentation.csv` 给出的每 tick 真实秒数（课间 100 tick / 100 秒 → 15 秒）；
##   · `leave_probability` 是**演示参数，不是玩法数值** —— 内核的离座概率来自
##     `data/rules/behavior_probs.csv` 的 `move`（当前 0.05）。

const BEHAVIORS_TABLE := "rules/behaviors"
const PHASES_TABLE := "rules/phases"
const PRESENTATION_TABLE := "rules/time_presentation"
const MOVE_BEHAVIOR := "move"
const KIND_BREAK := "break"
## §10.4：想加入的活动圈所在位置额外 ×1.5
const CIRCLE_BONUS := 1.5
## §10.4：权重下限 0.1（再不喜欢也偶尔走动，不锁死）
const MIN_WEIGHT := 0.1
## 活动圈判定半径（米）：点附近这个范围内有 ≥2 人 → 视为可加入的活动圈（§15.1）
const CIRCLE_RADIUS := 1.2

@export_group("表现开关")
## 关掉即纯静态教室（便于截图 / 对比）
@export var enabled: bool = true
## 课间里每隔多久让一批人重新决定去留（秒）—— 表现节奏，不影响内核 tick
@export var decide_interval: float = 6.0
## 演示用离座概率（见文件头：非玩法数值）
@export var leave_probability: float = 0.35

@export_group("节点路径")
@export var stand_points_path: NodePath = ^"../StandPoints"
@export var seats_path: NodePath = ^"../Seats"
@export var actors_path: NodePath = ^"../Actors"

@export_group("玩家")
## 允许点地面让玩家走过去
@export var player_click_to_move: bool = true
## 与家具的最小净距（米）：点击点比这更近就吸附到最近站立点
@export var furniture_clearance: float = 0.55

@export_group("站立点标记")
## 画一圈可见标记（关掉即只保留逻辑点）
@export var show_stand_markers: bool = true
@export var marker_radius: float = 0.16
@export var marker_color: Color = Color(0.35, 0.62, 0.85, 0.45)

@export_group("调试")
## 打印每批离座与归位的汇总 —— 演示期默认开，便于在编辑器 / MCP 的调试输出里
## 确认走动真的在发生；接上内核后建议关掉。
@export var log_roam: bool = true

var _core: Variant = null
var _clock: SimulationClock = null
var _rng := RandomNumberGenerator.new()
var _batch_count := 0
var _actors: Array[Node3D] = []
var _walkers: Array = []
var _point_positions: Dictionary = {}
var _owner_of_point: Dictionary = {}
var _occupant: Dictionary = {}
var _point_of_actor: Dictionary = {}
var _actor_count := 0
var _player_index := -1
var _move_seconds := 1.0
var _snapshot: Dictionary = {}
var _decide_timer := 0.0


func _ready() -> void:
	# 等一帧：人物由 Actors 节点（classroom_actors.gd）在自己的 _ready 里生成，
	# 这里不依赖同级节点的 _ready 顺序（确定性 > 巧合）。
	await get_tree().process_frame
	_core = _current_core()
	if _core == null:
		push_warning("ClassroomRoam：没有本局内核实例 —— 走动演示关闭（请从主菜单「新游戏」进教室）。")
		return
	_actor_count = int(_core.node_count())
	_player_index = _actor_count - 1
	_move_seconds = _load_move_seconds()
	_collect_points()
	_collect_actors()
	if show_stand_markers:
		_build_markers()
	_occupy_seats()


## 绑定时钟：课间 / 上课边界全部来自它的 phase_changed，本组件不再自己计时。
func bind_clock(clock: SimulationClock) -> void:
	if _clock == clock:
		return
	if _clock != null and is_instance_valid(_clock):
		_clock.phase_changed.disconnect(_on_phase_changed)
	_clock = clock
	if _clock == null:
		return
	_clock.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(_clock.snapshot())


func _process(delta: float) -> void:
	if not enabled or _core == null or _clock == null:
		return
	# 只课间推进决策；上课段不发起新走动（§10.4）
	if not is_break_phase():
		return
	_decide_timer += delta
	if _decide_timer < decide_interval:
		return
	_decide_timer = 0.0
	_decide_batch()


## 相位切换（由时钟驱动）：进课间 → 可以离座；进上课 → 全体归位（§10.4 第 6 条）。
func _on_phase_changed(snapshot_data: Dictionary) -> void:
	_snapshot = snapshot_data
	_occupy_seats()
	_decide_timer = decide_interval
	if is_break_phase():
		return
	for i in range(_actor_count):
		var walker: ActorWalker = _walkers[i]
		if walker == null:
			continue
		var seat_id := str(_core.seat_of(i))
		walker.walk_to(_point_positions.get(seat_id, _point_positions.values()[0]), _home_seconds())
	if log_roam:
		print("[roam] 进入上课：全体归位（本段共 %d 批离座）" % _batch_count)
	_batch_count = 0


## 归位时长：不超过上课段剩余时间的 80%，保证铃响后尽快坐好。
func _home_seconds() -> float:
	var remaining := float(_snapshot.get("remaining_seconds", 0.0))
	if remaining <= 0.0:
		return _move_seconds
	return minf(_move_seconds, maxf(remaining * 0.8, 0.5))


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not player_click_to_move or _core == null:
		return
	# 上课 / 日末简报期间玩家操作被锁：命令入口直接拒绝（不能只靠隐藏按钮）
	if not bool(_snapshot.get("player_control", false)) or _player_index < 0:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var target: Variant = _ground_target(button.position)
	if target == null:
		return
	_move_actor_to(_player_index, _resolve_ground_target(target), true)
	get_viewport().set_input_as_handled()


## 当前是否处于课间段（读时钟快照；尚未绑定时按课间处理）。
func is_break_phase() -> bool:
	if _snapshot.is_empty():
		return true
	return str(_snapshot.get("kind", "")) == KIND_BREAK


## 站立点总数（公共点 + 座位点）—— 供测试与调试。
func point_count() -> int:
	return _point_positions.size()


## 全部站立点编号（公共点 + 座位点）—— 供测试与调试。
func point_ids() -> Array:
	return _point_positions.keys()


## 某点当前被谁占用；-1 = 没人。越界返回 -1。
func occupant_of(point_id: String) -> int:
	return int(_occupant.get(point_id, -1))


## 移动耗时（秒，由 data 的 move.duration 换算）。
func move_seconds() -> float:
	return _move_seconds


# ------------------------------------------------------------------ 装配
func _current_core() -> Variant:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return null
	return state.sim_core


## 收集站立点：公共点（StandPoints/<point_id>）+ 座位点（Seats/<seat_id>）。
func _collect_points() -> void:
	var stand_root := get_node_or_null(stand_points_path)
	if stand_root != null:
		for child in stand_root.get_children():
			var node := child as Node3D
			if node != null:
				_point_positions[node.name] = node.global_position
	var seat_root := get_node_or_null(seats_path)
	if seat_root != null:
		for i in range(_actor_count):
			var seat_id := str(_core.seat_of(i))
			var seat := seat_root.get_node_or_null(seat_id) as Node3D
			if seat == null:
				continue
			# 座位点的站位取椅子处（与人物落位的偏移一致）
			_point_positions[seat_id] = seat.global_position + Vector3(0.0, 0.0, -0.45)
			_owner_of_point[seat_id] = i


func _collect_actors() -> void:
	var actors_root := get_node_or_null(actors_path)
	if actors_root == null:
		push_warning("ClassroomRoam：找不到人物父节点 %s" % str(actors_path))
		return
	for i in range(_actor_count):
		var actor := actors_root.get_child(i) as Node3D
		_actors.append(actor)
		if actor == null:
			_walkers.append(null)
			continue
		_walkers.append(actor.get_node_or_null("Walker") as ActorWalker)


func _occupy_seats() -> void:
	for i in range(_actor_count):
		var seat_id := str(_core.seat_of(i))
		if _point_positions.has(seat_id):
			_occupy(seat_id, i)


func _build_markers() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = marker_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := CylinderMesh.new()
	mesh.top_radius = marker_radius
	mesh.bottom_radius = marker_radius
	mesh.height = 0.01
	mesh.material = material
	for point_id in _point_positions.keys():
		var marker := MeshInstance3D.new()
		marker.name = "Marker_%s" % str(point_id)
		marker.mesh = mesh
		marker.position = _point_positions[point_id]
		add_child(marker)


## 移动秒数：真读 data（move.duration / 课间 tick 数 × break_seconds）。
## 移动秒数 = move.duration（tick）× 每个 tick 的真实秒数（来自 time_presentation）。
## 课间：15 tick × (100 秒 / 100 tick) = 15 秒 —— 数值全部来自 data，本组件不留常数。
func _load_move_seconds() -> float:
	var loader := ConfigLoader.new()
	var duration_ticks := 0.0
	var rows: Array = loader.get_table(BEHAVIORS_TABLE).get("rows", [])
	for row in rows:
		if str(row.get("behavior", "")) == MOVE_BEHAVIOR:
			duration_ticks = float(str(row.get("duration", "0")))
			break
	var presentation_rows: Array = loader.get_table(PRESENTATION_TABLE).get("rows", [])
	var phase_rows: Array = loader.get_table(PHASES_TABLE).get("rows", [])
	var seconds_per_tick := 0.0
	for row in phase_rows:
		if str(row.get("kind", "")) == KIND_BREAK:
			seconds_per_tick = _break_seconds_per_tick(row, presentation_rows)
			break
	if duration_ticks <= 0.0 or seconds_per_tick <= 0.0:
		push_warning("ClassroomRoam：读不到 move.duration / 课间 tick 间隔，移动时长回退 1 秒。")
		return 1.0
	return duration_ticks * seconds_per_tick


func _break_seconds_per_tick(phase_row: Dictionary, presentation_rows: Array) -> float:
	var ticks := float(str(phase_row.get("tick_count", "0")))
	var phase_id := str(phase_row.get("phase_id", ""))
	if ticks <= 0.0:
		return 0.0
	for row in presentation_rows:
		if str(row.get("phase_id", "")) == phase_id:
			return float(str(row.get("real_duration_seconds", "0"))) / ticks
	return 0.0


# ------------------------------------------------------------------ 决策


## 课间一批离座决策：按角色索引升序（NPC移动决策 §9 可复现性）。
func _decide_batch() -> void:
	_batch_count += 1
	var moved := 0
	for i in range(_actor_count):
		if i == _player_index:
			continue
		var walker: ActorWalker = _walkers[i]
		if walker == null or walker.is_moving():
			continue
		if _rng.randf() > leave_probability:
			continue
		var point_id := _pick_point(i)
		if point_id.is_empty():
			continue
		_go_to_point(i, point_id)
		moved += 1
	if log_roam and moved > 0:
		print("[roam] 课间第 %d 批：%d 人离座" % [_batch_count, moved])


## 按 §10.4 权重抽一个站立点；没有候选返回空串。
func _pick_point(i: int) -> String:
	var ids: Array = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total := 0.0
	for point_id in _point_positions.keys():
		var pid := str(point_id)
		if pid == str(_point_of_actor.get(i, "")):
			continue
		if _occupant.has(pid) and int(_occupant[pid]) != i:
			continue
		var weight := _point_weight(i, pid)
		ids.append(pid)
		weights.append(weight)
		total += weight
	if ids.is_empty() or total <= 0.0:
		return ""
	var roll := _rng.randf() * total
	for k in range(ids.size()):
		roll -= weights[k]
		if roll <= 0.0:
			return str(ids[k])
	return str(ids[ids.size() - 1])


## §10.4：权重 = 1 + Σ_j A[i][j]/100 − Σ_j H[i][j]/200；附近有活动圈 ×1.5；下限 0.1。
func _point_weight(i: int, point_id: String) -> float:
	var total_a := 0.0
	var total_h := 0.0
	for j in range(_actor_count):
		if j == i:
			continue
		total_a += float(_core.affinity(i, j))
		total_h += float(_core.hostility(i, j))
	var weight := 1.0 + total_a / 100.0 - total_h / 200.0
	if _people_near(i, point_id) >= 2:
		weight *= CIRCLE_BONUS
	return maxf(weight, MIN_WEIGHT)


## 该点附近（CIRCLE_RADIUS 内）站着多少人（不含自己）。
func _people_near(i: int, point_id: String) -> int:
	var pos: Vector3 = _point_positions[point_id]
	var count := 0
	for j in range(_actor_count):
		if j == i:
			continue
		var actor: Node3D = _actors[j]
		if actor == null:
			continue
		if actor.global_position.distance_to(pos) <= CIRCLE_RADIUS:
			count += 1
	return count


func _go_to_point(i: int, point_id: String) -> void:
	_release_point(i)
	_occupy(point_id, i)
	_move_actor_to(i, _point_positions[point_id], false)


func _move_actor_to(i: int, pos: Vector3, keep_occupancy: bool) -> void:
	var walker: ActorWalker = _walkers[i]
	if walker == null:
		return
	if keep_occupancy:
		_release_point(i)
		var nearest := _nearest_point(pos)
		if not nearest.is_empty():
			_occupy(nearest, i)
	walker.walk_to(pos, _move_seconds)


# ------------------------------------------------------------------ 占用


func _occupy(point_id: String, i: int) -> void:
	_occupant[point_id] = i
	_point_of_actor[i] = point_id


func _release_point(i: int) -> void:
	var current := str(_point_of_actor.get(i, ""))
	if current.is_empty():
		return
	if int(_occupant.get(current, -1)) == i:
		_occupant.erase(current)
	_point_of_actor.erase(i)


# ------------------------------------------------------------------ 玩家点地面
## 屏幕点 → 地面（y=0 平面）交点；无交点返回 null。
func _ground_target(screen_pos: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return null
	var distance := -origin.y / direction.y
	if distance <= 0.0:
		return null
	return origin + direction * distance


## 点击点若离家具太近，吸附到最近的站立点（避免站进桌椅里）。
func _resolve_ground_target(point: Vector3) -> Vector3:
	if _is_clear(point):
		return point
	var nearest := _nearest_point(point)
	if nearest.is_empty():
		return point
	return _point_positions[nearest]


func _is_clear(point: Vector3) -> bool:
	if absf(point.x) > 4.6 or absf(point.z) > 5.6:
		return false
	for point_id in _owner_of_point.keys():
		var seat_pos: Vector3 = _point_positions[point_id]
		if seat_pos.distance_to(point) < furniture_clearance:
			return false
	return true


func _nearest_point(point: Vector3) -> String:
	var best := ""
	var best_distance := INF
	for point_id in _point_positions.keys():
		var candidate: Vector3 = _point_positions[point_id]
		if _occupant.has(point_id) and int(_occupant[point_id]) >= 0:
			continue
		var distance := candidate.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = str(point_id)
	return best
