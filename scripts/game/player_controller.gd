class_name PlayerController
extends Node3D
## 玩家操控组件（表现层）：**鼠标点击寻路** 与 **WASD 手动行走** 共用一套移动执行与权限检查。
##
## 依据：主文档 §10.5（玩家位置与交互范围）、§10.4（走动耗时）；策划 2026-10-07 裁决第 4/5 项。
##
## 控制规则：
##   · **WASD**：按镜头对应的地面方向移动（W 向画面上方、S 向下、A/D 左右），斜向归一化，松键即停；
##   · **鼠标左键点地面**：沿**可通行路线**（网格 A*）走过去，再次点击更换目的地；
##   · **按下 WASD 立刻取消鼠标自动行走**，切手动；松键后不恢复旧路线；
##   · 点击 UI 不会触发移动 —— 本组件只收 `_unhandled_input`（被 Control 消费的输入收不到）；
##   · 上课 / 简报 / 暂停 / 转笔演出期间停止控制；**占用型行为（聊天等）进行中也不能用移动覆盖**。
##
## ⚠️ 本组件不做玩法判断：「什么时候能动」由这里决定，但**占用状态来自内核**（`core.is_busy`）。
##    位置写回内核供范围判定与展示（`core.set_position`）—— 内核不自己算移动。
##
## 移动速度统一：`data/rules/movement.csv` 的 `meters_per_tick`（米 / tick；课间 1 tick = 1 秒）。
## 手动与自动共用同一速度，耗时一律随**实际行走距离**变化，不再有「固定 15 秒到达」。
##
## 碰撞：桌椅矩形**从场景派生**，只取 `Seats/*/Desk` 子树 —— `Chair` 位于 z = -0.45，
## 正是 `classroom_roam._collect_points()` 算出的座位站位，把它当障碍会让人物站不进自己的座位。
## 世界坐标只写在场景里（与 seats.csv / stand_points.csv 同一约定），本组件不另建坐标表。

const MOVEMENT_TABLE := "rules/movement"

@export_group("开关")
@export var enabled: bool = true
## 允许鼠标左键点地面自动寻路走过去
@export var click_to_move: bool = true
## 允许 WASD 手动行走
@export var wasd_enabled: bool = true

@export_group("节点路径")
@export var actors_path: NodePath = ^"../Actors"
@export var stand_points_path: NodePath = ^"../StandPoints"
@export var seats_path: NodePath = ^"../Seats"
## 地板（用于取可通行范围）
@export var floor_path: NodePath = ^"../Room/Floor"
## 走动驱动器（取站立点占用情况；缺失则不做空闲判定）
@export var roam_path: NodePath = ^"../Roam"
## 玩家人物节点名；留空 = Actors 的最后一个子节点（与内核「末位是玩家」一致）
@export var player_node_name: StringName = &""

@export_group("输入")
@export var click_button: MouseButton = MOUSE_BUTTON_LEFT
@export var action_up: StringName = &"move_up"
@export var action_down: StringName = &"move_down"
@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"

@export_group("调试")
@export var log_player: bool = false

var _core: Variant = null
var _clock: SimulationClock = null
var _player_actor: Node3D = null
var _walker: ActorWalker = null
var _player_index := -1
var _snapshot: Dictionary = {}
## 距离口径（全部来自 data/rules/movement.csv）
var _speed := 0.13
var _radius := 0.24
var _grid := 0.25
var _eps := 0.02
var _snap := 1.0
## 障碍矩形（XZ 平面，已按人物半径外扩）与可通行范围
var _obstacles: Array[Rect2] = []
var _bounds := Rect2()
var _nav := AStarGrid2D.new()
## 自动行走路径（世界坐标折线，y 恒为 0）与当前段
var _path := PackedVector3Array()
var _path_index := 0
var _destination := Vector3.ZERO
var _has_destination := false
var _manual := false


func _ready() -> void:
	_register_actions()
	# 等一帧：人物由 Actors（classroom_actors.gd）在自己的 _ready 里生成
	await get_tree().process_frame
	_core = _current_core()
	if _core == null:
		push_warning("PlayerController：没有本局内核实例 —— 玩家操控关闭（请从主菜单「新游戏」进教室）。")
		return
	_player_index = int(_core.node_count()) - 1
	_load_config()
	_locate_player()
	_collect_obstacles()
	_build_nav()
	_sync_position_to_core()


## 绑定时钟：相位与暂停状态都从它的快照读，本组件不自己计时。
func bind_clock(clock: SimulationClock) -> void:
	if _clock == clock:
		return
	if (
		_clock != null
		and is_instance_valid(_clock)
		and _clock.phase_changed.is_connected(_on_phase_changed)
	):
		_clock.phase_changed.disconnect(_on_phase_changed)
	_clock = clock
	if _clock == null:
		return
	_clock.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(_clock.snapshot())


# ------------------------------------------------------------------ 对外查询（测试 / UI）


## 玩家此刻能否被操控。
## 不能：上课 / 日末简报 / 学期结束（快照 `player_control` 为假）、暂停或转笔演出（时钟非 running）、
## 以及**占用型行为进行中**（闲聊等 —— 不能被移动覆盖）。
func can_control() -> bool:
	if not enabled or _core == null or _player_actor == null:
		return false
	if _clock != null and _clock.snapshot().get("mode", "") != SimulationClock.MODE_RUNNING:
		return false
	if not _snapshot.is_empty() and not bool(_snapshot.get("player_control", false)):
		return false
	return not bool(_core.is_busy(_player_index))


## 玩家内核索引（末位）。
func player_index() -> int:
	return _player_index


## 玩家在自动行走中（点地面寻路）。
func is_auto_walking() -> bool:
	return _has_destination and not _path.is_empty()


## 玩家在 WASD 手动行走中。
func is_manual_walking() -> bool:
	return _manual


## 当前自动行走的目的地（未在寻路时为零向量）。
func destination() -> Vector3:
	return _destination


## 当前移动速度（米 / 秒）。
func speed() -> float:
	return _speed


## 障碍矩形数量（测试用）。
func obstacle_count() -> int:
	return _obstacles.size()


## 该点是否可站立（在房间内 + 不落在任何桌椅矩形里）。p 取人物中心的 XZ。
func is_walkable(p: Vector3) -> bool:
	return _is_walkable_2d(Vector2(p.x, p.z))


# ------------------------------------------------------------------ 每帧推进


func _process(delta: float) -> void:
	if _player_actor == null:
		return
	if not can_control():
		_cancel_movement()
		return
	var dir := _input_direction() if wasd_enabled else Vector3.ZERO
	if dir != Vector3.ZERO:
		_manual = true
		# 按下 WASD 立刻取消自动行走；松键也不恢复旧路线
		_clear_path()
		_step(dir * _speed * delta, delta)
	else:
		if _manual:
			_manual = false
			if _walker != null:
				_walker.stop_manual()
		_advance_path(delta)
	_sync_position_to_core()


## 失去控制权（上课 / 简报 / 暂停 / 被占用）：停下脚步，留在原地。
func _cancel_movement() -> void:
	_clear_path()
	_manual = false
	if _walker != null and _walker.is_moving():
		_walker.stop()
	_sync_position_to_core()


## WASD → 世界方向：按摄像机的地面朝向换算（W = 画面上方），斜向归一化。
func _input_direction() -> Vector3:
	var raw := Vector3.ZERO
	if Input.is_action_pressed(action_left):
		raw.x -= 1.0
	if Input.is_action_pressed(action_right):
		raw.x += 1.0
	if Input.is_action_pressed(action_up):
		raw.z -= 1.0
	if Input.is_action_pressed(action_down):
		raw.z += 1.0
	if raw == Vector3.ZERO:
		return Vector3.ZERO
	var viewport := get_viewport()
	if viewport == null:
		return raw.normalized()
	var camera := viewport.get_camera_3d()
	if camera == null:
		return raw.normalized()
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.0001:
		return raw.normalized()
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	return (forward * -raw.z + right * raw.x).normalized()


## 走一小步：带桌椅滑动（先整体、再退而求其次只走单轴），不会穿进家具。
func _step(delta: Vector3, delta_time: float) -> void:
	if _walker == null or delta.length() <= 0.0:
		return
	var origin := _player_actor.global_position
	var target := _slide(origin, delta)
	var applied := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	if applied.length() <= 0.0:
		return
	_walker.move_by(applied, delta_time)


## 沿 delta 尝试移动：整体不行就只走单轴（贴着桌椅滑过去，不卡死）。
func _slide(origin: Vector3, delta: Vector3) -> Vector3:
	if is_walkable(origin + delta):
		return origin + delta
	if absf(delta.x) > 0.0 and is_walkable(origin + Vector3(delta.x, 0.0, 0.0)):
		return origin + Vector3(delta.x, 0.0, 0.0)
	if absf(delta.z) > 0.0 and is_walkable(origin + Vector3(0.0, 0.0, delta.z)):
		return origin + Vector3(0.0, 0.0, delta.z)
	return origin


## 沿自动路径推进：每帧走 speed × delta，走到当前路径点就切下一段。
func _advance_path(delta: float) -> void:
	if _path.is_empty() or _walker == null or _player_actor == null:
		return
	var origin := _player_actor.global_position
	var goal := _path[_path_index]
	var remaining := Vector3(goal.x - origin.x, 0.0, goal.z - origin.z)
	var step := _speed * delta
	if remaining.length() <= maxf(step, _eps):
		_path_index += 1
		_step(remaining, delta)
		if _path_index >= _path.size():
			_finish_path()
		return
	_step(remaining.normalized() * step, delta)


func _finish_path() -> void:
	if log_player:
		print("[player] 到达目的地 (%.2f, %.2f)" % [_destination.x, _destination.z])
	_clear_path()


func _clear_path() -> void:
	_path = PackedVector3Array()
	_path_index = 0
	_has_destination = false


# ------------------------------------------------------------------ 玩家输入（点地面）


func _on_phase_changed(snapshot_data: Dictionary) -> void:
	_snapshot = snapshot_data
	# 换段的瞬间就复查一次：上课铃一响马上停住（不等到下一帧）
	if not can_control():
		_cancel_movement()


func _unhandled_input(event: InputEvent) -> void:
	if not click_to_move or _player_actor == null or not can_control():
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != click_button:
		return
	var point: Variant = _ground_point(button.position)
	if point == null:
		return
	# 只处理**地面**点击：点击人物（选中 / 交互）留待后续，届时这里要加人物命中判定
	_start_auto_walk(point)


## 点地面 → 吸附落点 → 网格 A* → 开始自动行走（再次点击即更换目的地）。
func _start_auto_walk(point: Vector3) -> void:
	if _bounds.size.x <= 0.0:
		return
	var goal: Variant = _resolve_goal(point)
	if goal == null:
		return
	var from := _cell_id(_player_actor.global_position)
	var to := _cell_id(goal)
	if not _nav.region.has_point(to) or _nav.is_point_solid(to):
		to = _nearest_open_cell(to)
		if to.x < 0:
			return
	_clear_path()
	var cells: PackedVector2Array = _nav.get_point_path(from, to)
	if cells.is_empty():
		return
	_path = PackedVector3Array()
	for cell in cells:
		_path.append(Vector3(cell.x, 0.0, cell.y))
	_path_index = 0
	_destination = goal
	_has_destination = true
	if log_player:
		print("[player] 自动寻路 %d 段 → (%.2f, %.2f)" % [_path.size(), goal.x, goal.z])


## 目的地：**合法且空闲**的站立点在吸附半径内 → 用它（裁决第 5 项）；否则用最近的可行走格。
func _resolve_goal(point: Vector3) -> Variant:
	var stand: Variant = _nearest_free_stand(point)
	if stand != null:
		return stand
	var cell := _cell_id(point)
	if not _nav.region.has_point(cell) or _nav.is_point_solid(cell):
		cell = _nearest_open_cell(cell)
	if cell.x < 0:
		return null
	return _cell_center(cell)


## 吸附半径内最近的空闲站立点（已被占用的跳过）；没有则返回 null。
func _nearest_free_stand(point: Vector3) -> Variant:
	var root := get_node_or_null(stand_points_path)
	if root == null:
		return null
	var roam := get_node_or_null(roam_path)
	var best: Variant = null
	var best_distance := INF
	for child in root.get_children():
		var node := child as Node3D
		if node == null:
			continue
		if roam != null and int(roam.occupant_of(str(node.name))) >= 0:
			continue
		var pos := node.global_position
		var distance := Vector2(pos.x - point.x, pos.z - point.z).length()
		if distance <= _snap and distance < best_distance:
			best_distance = distance
			best = pos
	return best


# ------------------------------------------------------------------ 场景 → 几何（障碍 / 导航格）


## 桌椅矩形从场景派生。**只取 `Desk` 子树**：`Chair` 在 z=-0.45，是座位站位，不能当障碍。
func _collect_obstacles() -> void:
	_obstacles.clear()
	var seats := get_node_or_null(seats_path)
	if seats != null:
		for seat in seats.get_children():
			var desk := seat.get_node_or_null("Desk")
			if desk != null:
				for mesh in _meshes_under(desk):
					_obstacles.append(_xz_rect_of(mesh).grow(_radius))
	var floor_node := get_node_or_null(floor_path) as MeshInstance3D
	if floor_node != null:
		_bounds = _xz_rect_of(floor_node)


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes_under(child))
	return out


## MeshInstance3D 在 XZ 平面上的世界包围矩形（取 AABB 八个角投影，避免旋转后失真）。
func _xz_rect_of(node: MeshInstance3D) -> Rect2:
	var box := node.get_aabb()
	var xform := node.global_transform
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for k in range(8):
		var world := xform * box.get_endpoint(k)
		min_x = minf(min_x, world.x)
		max_x = maxf(max_x, world.x)
		min_z = minf(min_z, world.z)
		max_z = maxf(max_z, world.z)
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


## 建导航网格：可行走 = 在地板范围内且不在任何桌椅矩形里。
func _build_nav() -> void:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		push_warning("PlayerController：读不到地板范围 —— 鼠标寻路关闭（WASD 不受影响）。")
		return
	var cells := Vector2i(
		maxi(1, int(ceil(_bounds.size.x / _grid))), maxi(1, int(ceil(_bounds.size.y / _grid)))
	)
	_nav.clear()
	_nav.region = Rect2i(Vector2i.ZERO, cells)
	_nav.cell_size = Vector2(_grid, _grid)
	_nav.offset = _bounds.position + Vector2(_grid, _grid) * 0.5
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.update()
	for y in range(cells.y):
		for x in range(cells.x):
			var center := _cell_center(Vector2i(x, y))
			if not _is_walkable_2d(Vector2(center.x, center.z)):
				_nav.set_point_solid(Vector2i(x, y), true)


func _is_walkable_2d(p: Vector2) -> bool:
	if not _bounds.has_point(p):
		return false
	for rect in _obstacles:
		if rect.has_point(p):
			return false
	return true


func _cell_id(p: Vector3) -> Vector2i:
	return Vector2i(
		floori((p.x - _bounds.position.x) / _grid), floori((p.z - _bounds.position.y) / _grid)
	)


func _cell_center(id: Vector2i) -> Vector3:
	return Vector3(
		_bounds.position.x + (float(id.x) + 0.5) * _grid,
		0.0,
		_bounds.position.y + (float(id.y) + 0.5) * _grid
	)


## 从不可走的格向外一圈圈找最近的可行走格；找不到返回 (-1, -1)。
func _nearest_open_cell(start: Vector2i) -> Vector2i:
	for radius in range(1, 16):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var cell := start + Vector2i(dx, dy)
				if _nav.region.has_point(cell) and not _nav.is_point_solid(cell):
					return cell
	return Vector2i(-1, -1)


# ------------------------------------------------------------------ 装配


## WASD 动作已在 project.godot 的 [input] 段静态声明（编辑器 / 输入映射界面可见可改），
## 这里是幂等兜底：正常路径下 has_action() 为真直接跳过，只有静态映射被人误删时才会补注册。
## keycode + physical_keycode 双写，QWERTY 与非 QWERTY 布局下都命中同一物理键位置。
func _register_actions() -> void:
	_add_key_action(action_up, KEY_W)
	_add_key_action(action_down, KEY_S)
	_add_key_action(action_left, KEY_A)
	_add_key_action(action_right, KEY_D)


func _add_key_action(action: StringName, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _load_config() -> void:
	var rows: Array = ConfigLoader.new().get_table(MOVEMENT_TABLE).get("rows", [])
	for row in rows:
		var value := float(str(row.get("value", "0")))
		match str(row.get("param", "")):
			"meters_per_tick":
				_speed = value
			"player_radius":
				_radius = value
			"nav_grid_size":
				_grid = value
			"walk_epsilon":
				_eps = value
			"stand_snap_radius":
				_snap = value
	if _speed <= 0.0:
		_speed = 0.13
	if _grid <= 0.0:
		_grid = 0.25


func _locate_player() -> void:
	var root := get_node_or_null(actors_path)
	if root == null:
		push_warning("PlayerController：找不到人物父节点 %s" % str(actors_path))
		return
	if str(player_node_name).is_empty():
		var children := root.get_children()
		if children.is_empty():
			push_warning("PlayerController：Actors 下还没有人物 —— 玩家操控关闭。")
			return
		_player_actor = children[children.size() - 1] as Node3D
	else:
		_player_actor = root.get_node_or_null(NodePath(str(player_node_name))) as Node3D
	if _player_actor == null:
		push_warning("PlayerController：定位不到玩家人物节点。")
		return
	_walker = _player_actor.get_node_or_null("Walker") as ActorWalker
	if _walker == null:
		push_warning("PlayerController：玩家人物没有 Walker 组件 —— 移动无法表现。")


func _current_core() -> Variant:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return null
	return state.sim_core


## 把玩家当前位置写回内核（供范围判定 / 展示用）。NPC 的位置由走动驱动器同步。
func _sync_position_to_core() -> void:
	if _core == null or _player_actor == null or _player_index < 0:
		return
	var pos := _player_actor.global_position
	_core.set_position(_player_index, pos.x, pos.z)


## 屏幕点 → 地面（y = 0 平面）交点；无交点 / 无摄像机返回 null。
func _ground_point(screen_pos: Vector2) -> Variant:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var camera := viewport.get_camera_3d()
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
