class_name PlayerController
extends Node3D
## 玩家操控组件（表现层）：**鼠标点击寻路** 与 **WASD 手动行走** 共用一套移动执行与权限检查。
##
## 依据：主文档 §10.5（玩家位置与交互范围）、§10.4（走动耗时）；策划 2026-10-07 裁决第 4/5 项；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §3.2。
##
## 控制规则：
##   · **WASD**：按镜头对应的地面方向移动（W 向画面上方、S 向下、A/D 左右），斜向归一化，松键即停；
##   · **鼠标左键点地面**：沿**可通行路线**（网格 A*）走过去，再次点击更换目的地；
##   · **鼠标左键点人物**：只发 `actor_picked`，**不走路**（选中交给交互控制器）；
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
## 那只是**显示**位置；可走站位是 `desk_chair.tscn` 的 `StandSpot`（z = -0.80，导航面中心），
## 把椅子也算作障碍会让人物站不进自己的座位。
## 世界坐标只写在场景里（与 seats.csv / stand_points.csv 同一约定），本组件不另建坐标表。
##
## 接近请求（计划 §3.2）：`plan_approach()` 只**算路**、零移动副作用；`follow_path()` 才真的走；
## 到达 / 取消 / 失败一律带 `request_id` —— 旧请求的回调不得影响新路径。

signal actor_picked(actor_index: int)
signal ground_clicked(point: Vector3)
signal request_arrived(request_id: int)
signal request_cancelled(request_id: int, reason: StringName)
signal request_failed(request_id: int, reason: StringName)

const MOVEMENT_TABLE := "rules/movement"
const PICK_TABLE := "rules/player_interaction"
## 拾取射线长度（米）：教室尺度远小于它
const PICK_DISTANCE := 100.0

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

@export_group("拾取与遮挡")
## 人物拾取体所在 3D 物理层（位掩码）；0 = 读配置表 `actor_pick_layer`
@export var actor_pick_layer: int = 0
## 世界静态遮挡体所在 3D 物理层（位掩码）；0 = 读配置表 `world_pick_blocker_layer`
@export var world_blocker_layer: int = 0
## 是否从桌面 / 墙的实际 Mesh 生成静态遮挡体（关掉即不挡视线）
@export var build_blockers: bool = true
## 生成静态遮挡体的房间节点（其 *Wall 子树与座位桌一起参与）
@export var room_path: NodePath = ^"../Room"

@export_group("调试")
@export var log_player: bool = false

var _core: Variant = null
var _clock: SimulationClock = null
var _player_actor: Node3D = null
var _walker: ActorWalker = null
var _player_index := -1
var _snapshot: Dictionary = {}
## 距离口径（全部来自 data/rules/movement.csv）
var _speed := 0.8
var _radius := 0.24
var _grid := 0.25
var _eps := 0.02
var _snap := 1.0
## 障碍矩形（XZ 平面，已按人物半径外扩）、**未外扩的原始矩形**（喂给内核做交互几何）与可通行范围
var _obstacles: Array[Rect2] = []
var _raw_obstacles: Array[Rect2] = []
var _bounds := Rect2()
var _nav := AStarGrid2D.new()
## 自动行走路径（世界坐标折线，y 恒为 0）与当前段
var _path := PackedVector3Array()
var _path_index := 0
var _destination := Vector3.ZERO
var _has_destination := false
var _manual := false
## 当前接近请求编号（-1 = 普通地面点击，没有请求）
var _active_request := -1
## 拾取 / 遮挡层（来自 data/rules/player_interaction.csv）
var _pick_layer := 2
var _blocker_layer := 1
## 移动状态是否已写回内核（避免每帧重复调用）
var _moving_written := false


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
	_load_pick_config()
	_build_occluders()
	_build_nav()
	_verify_player_spot()
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


## 交互几何（**未按人物半径外扩**的原始矩形 + 房间边界）—— 场景据此一次注入内核。
## 内核只用它做范围与线段阻挡判定，不引用任何场景节点。
func interaction_geometry() -> Dictionary:
	return {"obstacles": _raw_obstacles.duplicate(), "bounds": _bounds}


func effective_pick_layer() -> int:
	return _pick_layer


func effective_blocker_layer() -> int:
	return _blocker_layer


## 玩家是否正在走向某个已确认的接近请求（-1 = 普通地面点击的自动行走）。
func active_request() -> int:
	return _active_request


func is_approaching() -> bool:
	return _active_request >= 0 and _has_destination


# ------------------------------------------------------------------ 人物拾取（射线）

## 屏幕点 → 人物索引；最近命中是墙壁 / 桌椅则返回 -1（**隔着家具选不中**）。
## 由交互控制器在「地面移动」之前调用，人物输入因此不会被先走一步。
func pick_actor(screen_pos: Vector2) -> int:
	if _pick_layer <= 0 or not is_inside_tree():
		return -1
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return -1
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * PICK_DISTANCE, _pick_layer | _blocker_layer
	)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return -1
	var collider: Variant = hit.get("collider")
	if collider == null or not (collider is Node) or not (collider as Node).has_meta("actor_index"):
		return -1
	return int((collider as Node).get_meta("actor_index"))


# ------------------------------------------------------------------ 接近算路（零移动副作用）

## 在目标周围枚举合法站位，挑**路径最短**的一个；只算不走，改变不了任何移动状态。
## 返回 {ok, error, path, destination, length_m}；同长度按格点坐标固定排序（不用随机数）。
func plan_approach(targets: Array, range_m: float) -> Dictionary:
	if _player_actor == null:
		return {"ok": false, "error": "no_player"}
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return {"ok": false, "error": "no_geometry"}
	var points: Array[Vector2] = []
	for t in targets:
		var point := t as Vector3
		points.append(Vector2(point.x, point.z))
	if points.is_empty():
		return {"ok": false, "error": "no_target"}
	var from := _cell_id(_player_actor.global_position)
	if not _nav.region.has_point(from) or _nav.is_point_solid(from):
		from = _nearest_open_cell(from)
		if from.x < 0:
			return {"ok": false, "error": "no_path"}
	var best: Dictionary = {}
	for cell in _candidate_cells(points, range_m):
		var cells: PackedVector2Array = _nav.get_point_path(from, cell)
		if cells.is_empty():
			continue
		var length := _polyline_length(cells)
		if not best.is_empty():
			var current := float(best["length_m"])
			if length > current + 0.0001:
				continue
			if absf(length - current) <= 0.0001 and not _cell_before(cell, best["cell"]):
				continue
		best = {"cell": cell, "length_m": length, "cells": cells}
	if best.is_empty():
		return {"ok": false, "error": "no_path"}
	var path := PackedVector3Array()
	for cell in best["cells"]:
		path.append(Vector3(cell.x, 0.0, cell.y))
	return {
		"ok": true,
		"error": "",
		"path": path,
		"destination": path[path.size() - 1],
		"length_m": float(best["length_m"]),
	}


## 开始一条**已确认**的路径（request_id 由内核分配，随到达 / 取消 / 失败回传）。
## 路径为空或不合法时明确失败，不静默走一条坏路。
func follow_path(request_id: int, path: PackedVector3Array) -> bool:
	if _player_actor == null or path.is_empty():
		emit_signal("request_failed", request_id, &"empty_path")
		return false
	if not _path_is_walkable(path):
		emit_signal("request_failed", request_id, &"blocked_path")
		return false
	_clear_path()
	_path = path
	_path_index = 0
	_destination = path[path.size() - 1]
	_has_destination = true
	_active_request = request_id
	_sync_moving_state()
	if log_player:
		print("[player] 接近请求 %d：%d 段 → (%.2f, %.2f)" % [
			request_id, path.size(), _destination.x, _destination.z
		])
	return true


## 只取消**这一个**请求的移动：编号对不上就不动，绝不打断后来新建的路径。
func cancel_request_movement(request_id: int, reason: StringName) -> void:
	if _active_request != request_id:
		return
	_clear_path()
	_active_request = -1
	emit_signal("request_cancelled", request_id, reason)


## 每个路径点都必须是可行走格（防止拿一条穿墙的假路径去走）。
## 起点是**玩家脚下的格心**，可能因人物半径外扩而落在障碍矩形内 —— 只从第二点开始校验。
func _path_is_walkable(path: PackedVector3Array) -> bool:
	for index in range(1, path.size()):
		if not is_walkable(path[index]):
			return false
	return true


## 以目标为圆心、range_m 为半径的可站立格点（同时要求连线不穿家具）。
func _candidate_cells(points: Array[Vector2], range_m: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if range_m <= 0.0:
		return out
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for point in points:
		min_x = minf(min_x, point.x - range_m)
		max_x = maxf(max_x, point.x + range_m)
		min_z = minf(min_z, point.y - range_m)
		max_z = maxf(max_z, point.y + range_m)
	var lo := _cell_id(Vector3(min_x, 0.0, min_z))
	var hi := _cell_id(Vector3(max_x, 0.0, max_z))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell := Vector2i(x, y)
			if not _nav.region.has_point(cell) or _nav.is_point_solid(cell):
				continue
			if _cell_within_range(_cell_center(cell), points, range_m):
				out.append(cell)
	return out


func _cell_within_range(center: Vector3, points: Array[Vector2], range_m: float) -> bool:
	var here := Vector2(center.x, center.z)
	for point in points:
		if here.distance_to(point) > range_m:
			return false
		if _segment_blocked(here, point):
			return false
	return true


## 原始矩形（未外扩）上的线段阻挡判定 —— 与内核 InteractionSpace 同一口径。
func _segment_blocked(a: Vector2, b: Vector2) -> bool:
	var length := a.distance_to(b)
	var steps := maxi(1, int(ceil(length / maxf(_grid * 0.5, 0.01))))
	for k in range(steps + 1):
		var point := a.lerp(b, float(k) / float(steps))
		for rect in _raw_obstacles:
			if rect.has_point(point):
				return true
	return false


func _polyline_length(cells: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, cells.size()):
		total += cells[index - 1].distance_to(cells[index])
	return total


## 同长度时的固定排序：格点坐标字典序（与决策顺序无关的可复现选择）。
func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


# ------------------------------------------------------------------ 每帧推进


func _process(delta: float) -> void:
	if _player_actor == null:
		return
	if not can_control():
		if _is_frozen_by_hold():
			# 世界被 hold（转笔演出 / 真正暂停）：**冻结接近路径与请求**，只把位置同步回内核
			_sync_position_to_core()
			return
		_cancel_movement(&"lost_control")
		return
	var dir := _input_direction() if wasd_enabled else Vector3.ZERO
	if dir != Vector3.ZERO:
		_manual = true
		# 按下 WASD 立刻取消自动行走；松键也不恢复旧路线
		_cancel_active_request(&"wasd")
		_clear_path()
		_step(dir * _speed * delta, delta)
	else:
		if _manual:
			_manual = false
			if _walker != null:
				_walker.stop_manual()
		_advance_path(delta)
	_sync_position_to_core()
	_sync_moving_state()


## 世界是否被 hold（转笔演出 / 暂停菜单）—— 冻结而不是取消。
func _is_frozen_by_hold() -> bool:
	return _clock != null and is_instance_valid(_clock) and _clock.is_paused()


## 失去控制权（上课 / 简报 / 被占用）：停下脚步，留在原地；未提交的接近请求随之取消。
func _cancel_movement(reason: StringName = &"lost_control") -> void:
	if not _has_destination and not _manual and _active_request < 0:
		return
	_cancel_active_request(reason)
	_clear_path()
	_manual = false
	if _walker != null:
		# ⚠️ 只收尾**玩家自己**的步态：**不调** `_walker.stop()` —— 它会打断系统发起的走动
		# （上课归位由 classroom_roam 直接调 walker.walk_to_navigated_in，玩家无权取消它）。
		_walker.stop_manual()
	_sync_position_to_core()
	_sync_moving_state()


## 取消当前接近请求（没有请求时什么都不做）。
func _cancel_active_request(reason: StringName) -> void:
	if _active_request < 0:
		return
	var request_id := _active_request
	_active_request = -1
	emit_signal("request_cancelled", request_id, reason)


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
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return raw.normalized()
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.0001:
		return raw.normalized()
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	return (forward * -raw.z + right * raw.x).normalized()


## 走一小步：**沿整段采样**推进（步长取 nav_grid_size 的一半），任一点不可走就停在那里；
## 整段被挡才退而求其次只走单轴（贴桌滑行）。只检查终点会漏掉「途中穿过桌角」。
func _step(delta: Vector3, delta_time: float) -> void:
	if _walker == null or delta.length() <= 0.0:
		return
	var origin := _player_actor.global_position
	var target := _slide_sampled(origin, delta)
	var applied := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	if applied.length() <= 0.0:
		return
	_walker.move_by(applied, delta_time)


## 沿 delta 分步采样推进：每一步都必须可走，返回真正能到达的位置。
## 采样步长取寻路网格的一半（几何是格尺度的，这样不会跳过家具角）；整体只有一步时退回 `_slide`。
func _slide_sampled(origin: Vector3, delta: Vector3) -> Vector3:
	var step := maxf(_grid * 0.5, 0.05)
	var total := Vector2(delta.x, delta.z).length()
	if total <= step:
		return _slide(origin, delta)
	var steps := maxi(1, int(ceil(total / step)))
	var pos := origin
	for k in range(1, steps + 1):
		var candidate := origin + delta * (float(k) / float(steps))
		if is_walkable(candidate):
			pos = candidate
			continue
		var only_x := Vector3(candidate.x, 0.0, pos.z)
		var only_z := Vector3(pos.x, 0.0, candidate.z)
		if absf(delta.x) > 0.0 and is_walkable(only_x):
			pos = only_x
		elif absf(delta.z) > 0.0 and is_walkable(only_z):
			pos = only_z
		else:
			break
	return pos


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
	var request_id := _active_request
	_active_request = -1
	if log_player:
		print("[player] 到达目的地 (%.2f, %.2f)" % [_destination.x, _destination.z])
	_clear_path()
	# 正式到达必须带请求编号：旧请求的到达不得提交新交互
	if request_id >= 0:
		emit_signal("request_arrived", request_id)


func _clear_path() -> void:
	_path = PackedVector3Array()
	_path_index = 0
	_has_destination = false
	_sync_moving_state()


## 把「玩家在走动」这一独立状态写回内核（让 NPC 不把移动中的人拉进新交互）。
func _sync_moving_state() -> void:
	var moving := is_auto_walking() or is_manual_walking()
	if _moving_written == moving:
		return
	_moving_written = moving
	if _core != null and _player_index >= 0:
		_core.set_moving(_player_index, moving)


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
	if str(handle_click(button.position)) != "ignored":
		get_viewport().set_input_as_handled()


## 统一点击入口（可测）：人物优先，命中人物只发选中信号、**不向地面走一步**；
## 最近命中是世界遮挡体（墙 / 桌椅）时，人物不可选 —— 隔着家具点不到人。
## 返回 "actor" / "ground" / "ignored"。
func handle_click(screen_pos: Vector2) -> StringName:
	if not click_to_move or _player_actor == null or not can_control():
		return &"ignored"
	var actor_index := pick_actor(screen_pos)
	if actor_index >= 0:
		emit_signal("actor_picked", actor_index)
		return &"actor"
	var point: Variant = _ground_point(screen_pos)
	if point == null:
		return &"ignored"
	emit_signal("ground_clicked", point)
	_start_auto_walk(point)
	return &"ground"


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
	# 新的地面点击作废未提交的接近请求（已走过的时间不返还）
	_cancel_active_request(&"new_ground_click")
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
	_sync_moving_state()
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


## 障碍矩形从场景派生。
##
## **桌椅**只取 `Desk` 子树：`Chair`（z=-0.45）只是显示位置，可走站位是 `StandSpot`
## （z=-0.80），椅子不能当障碍，否则人物站不进自己的座位。
## **讲台**（`Room` 之外的 `Podium`）整棵子树取一个包围盒 —— 它原本不在障碍表里，
## 玩家会直接走进讲桌（2026-10-08）。
## 同时留下**未外扩**的原始矩形，供内核做交互几何（范围与连线阻挡）判定。
func _collect_obstacles() -> void:
	_obstacles.clear()
	_raw_obstacles.clear()
	var seats := get_node_or_null(seats_path)
	if seats != null:
		for seat in seats.get_children():
			var desk := seat.get_node_or_null("Desk")
			if desk != null:
				for mesh in _meshes_under(desk):
					var rect := _xz_rect_of(mesh)
					_raw_obstacles.append(rect)
					_obstacles.append(rect.grow(_radius))
	_append_podium_obstacle()
	var floor_node := get_node_or_null(floor_path) as MeshInstance3D
	if floor_node != null:
		_bounds = _xz_rect_of(floor_node)


## 讲台：整棵子树一个 XZ 包围盒（讲桌 + 高台），与 `_build_occluders` 找 `Podium`
## 用同一处场景节点，不另填一套家具坐标。
func _append_podium_obstacle() -> void:
	# `find_child` 只搜**子树**，而 `Podium` 与 PlayerController 是**兄弟**（都挂在场景根下），
	# 所以要先把范围抬到本场景的顶层节点。也不能走 `room_path` —— 它指向 `../Room`。
	var top: Node = self
	while top.get_parent() != null and top.get_parent() != get_tree().root:
		top = top.get_parent()
	var podium := top.find_child("Podium", true, false)
	if podium == null:
		push_warning("PlayerController：场景里找不到 Podium，讲台不会阻挡玩家。")
		return
	var box := _world_box_of(podium)
	if box.size.length() <= 0.0:
		return
	var rect := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
	_raw_obstacles.append(rect)
	_obstacles.append(rect.grow(_radius))


## 拾取层与遮挡层：数值来自 data/rules/player_interaction.csv（位掩码），导出属性优先。
func _load_pick_config() -> void:
	var rows: Array = ConfigLoader.new().get_table(PICK_TABLE).get("rows", [])
	for row in rows:
		var value := int(str(row.get("value", "0")))
		match str(row.get("param", "")):
			"actor_pick_layer":
				_pick_layer = value
			"world_pick_blocker_layer":
				_blocker_layer = value
	if actor_pick_layer > 0:
		_pick_layer = actor_pick_layer
	if world_blocker_layer > 0:
		_blocker_layer = world_blocker_layer


## 世界静态遮挡体：从桌面与墙的**实际 Mesh** 派生（不手填另一套家具坐标），
## 放在 world_pick_blocker_layer 上 —— 「隔着家具点不到人」由真实射线命中决定。
## 每处只生成**一个**包围盒（整张桌子 / 整面墙），数量与场景规模同阶。
func _build_occluders() -> void:
	if not build_blockers or _blocker_layer <= 0:
		return
	var parent := get_node_or_null(room_path)
	if parent == null:
		return
	var sources: Array[Node] = []
	var seats := get_node_or_null(seats_path)
	if seats != null:
		for seat in seats.get_children():
			var desk := seat.get_node_or_null("Desk")
			if desk != null:
				sources.append(desk)
	for child in parent.get_children():
		var name := str((child as Node).name)
		if name.ends_with("Wall") or name == "Podium":
			sources.append(child)
	var count := 0
	for source in sources:
		var box := _world_box_of(source)
		if box.size.length() <= 0.0:
			continue
		_add_occluder(parent, box)
		count += 1
	if log_player:
		print("[player] 生成 %d 个世界遮挡体（层 %d）" % [count, _blocker_layer])


## 子树里所有 Mesh 的世界包围盒并集（取 AABB 八角逐个投影，旋转后也不失真）。
func _world_box_of(node: Node) -> AABB:
	var min_point := Vector3(INF, INF, INF)
	var max_point := Vector3(-INF, -INF, -INF)
	var found := false
	for mesh in _meshes_under(node):
		var box := mesh.get_aabb()
		var xform := mesh.global_transform
		for k in range(8):
			var world := xform * box.get_endpoint(k)
			min_point = min_point.min(world)
			max_point = max_point.max(world)
			found = true
	if not found:
		return AABB()
	return AABB(min_point, max_point - min_point)


func _add_occluder(parent: Node, box: AABB) -> void:
	var body := StaticBody3D.new()
	body.name = "PickOccluder"
	body.collision_layer = _blocker_layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var shape_box := BoxShape3D.new()
	shape_box.size = box.size
	shape.shape = shape_box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = box.get_center()


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


## 出生点兜底：站位若落在家具里 / 房间外（几何被改坏、座位 StandSpot 忘了摆），
## 吸附到最近的合法格并把位置写回内核 —— 否则玩家一进教室就永远动不了（2026-10-07 复现）。
## ⚠️ 这一步只动"初始化落位"，不影响任何运行中的移动；找不到安全落点时明确停用操控。
func _verify_player_spot() -> void:
	if _player_actor == null:
		return
	var pos := _player_actor.global_position
	if is_walkable(pos):
		return
	var cell := _nearest_open_cell(_cell_id(pos))
	if cell.x < 0:
		push_error("PlayerController：出生点不可走且找不到安全落点 —— 玩家移动保持关闭。")
		enabled = false
		return
	var safe := _cell_center(cell)
	_player_actor.global_position = safe
	if _walker != null:
		_walker.teleport_to(safe)
	_sync_position_to_core()
	push_warning(
		"PlayerController：出生点不可走（%.2f, %.2f）→ 已吸附到最近可走点（%.2f, %.2f）。"
		% [pos.x, pos.z, safe.x, safe.z]
	)


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


## WASD 动作若不存在就地注册 —— 避免手改 project.godot（AGENTS.md：手改需谨慎）。
## 用 physical_keycode，非 QWERTY 布局下也仍是「同一物理键位置」。
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
		_speed = 0.8
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


## 屏幕点 → 地面（y = 0 平面）交点；无交点返回 null。
func _ground_point(screen_pos: Vector2) -> Variant:
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
