class_name ActorWalker
extends Node3D
## 人物行走组件（表现层）：挂在「人物节点」下，把人物本体走到某个世界坐标。
##
## 依据：主文档 §10.4（走动 15 tick、期间不能发起 / 接受新交互、段末归位）、
##      docs/design/NPC移动决策.md（移动是状态层，不改任何矩阵）。
##
## 用法（与 speech_bubble 同风格，作为人物节点的子节点挂上）：
## [codeblock]
## var walker := preload("res://scenes/components/actor_walker.tscn").instantiate()
## actor.add_child(walker)
## walker.walk_to(Vector3(1.0, 0.0, 2.0), 4.5)   # 只取 XZ，高度由步态起伏控制
## await walker.walk_finished
## [/codeblock]
##
## ⚠️ 本组件**不做玩法判断**：该不该走、走多久、走到哪，都由驱动器（内核或演示驱动器）
##    决定；组件只负责「怎么走」（插值 / 朝向 / 起伏）与「走到没有」。
##    `stop()` 与正常到位都会发 `walk_finished`，方便调用方统一 await。
##
## 两种行走（**直线语义原样保留**给单测与无导航场景，教室一律走导航）：
##   · `walk_to()` / `walk_to_at_speed()`：两点直线插值（原语义，未改）；
##   · `walk_to_navigated()`：沿**导航网格**折线走，绕开桌椅（主文档 §10.4）。
##     取不到路线时**返回 false 且一步不走** —— 绝不用直线兜底（直线会穿桌）。

signal walk_started(target: Vector3)
signal walk_finished

@export_group("移动")
## 到位判定的容差（米）
@export var arrive_epsilon: float = 0.01
## true = 缓入缓出；false = 匀速
@export var ease_motion: bool = true

@export_group("步态")
## 走路时的上下起伏幅度（米）
@export var bob_height: float = 0.03
## 起伏频率（次 / 秒）
@export var bob_frequency: float = 2.0
## 走路时按移动方向翻转立绘朝向
@export var flip_facing: bool = true
## 到位后是否恢复正面朝向
@export var restore_facing_on_arrive: bool = true
## 立绘节点名（classroom_actors.gd 生成时的约定名）
@export var sprite_node_name: StringName = &"Sprite"

var _body: Node3D = null
var _sprite: Sprite3D = null
var _moving := false
## WASD 手动步进中（与自动行走互斥；两者都算「在移动」）
var _manual := false
var _elapsed := 0.0
var _duration := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _base_y := 0.0
var _bob_time := 0.0
## 导航折线（世界坐标）。**非空 = 折线推进**；空 = 走原有直线语义
var _path := PackedVector3Array()
var _path_index := 0
## 折线推进速度（米 / 秒，来自 data/rules/movement.csv 的 meters_per_tick）
var _nav_speed := 0.0


func _ready() -> void:
	_body = get_parent() as Node3D
	if _body == null:
		push_error("ActorWalker：父节点必须是 Node3D（本组件挂在人物节点下）")
		return
	_sprite = _find_sprite(_body)
	_base_y = _body.global_position.y
	_to = _body.global_position
	_from = _to


## 是否正在移动（自动行走中，或 WASD 手动步进期间）。
func is_moving() -> bool:
	return _moving or _manual


## 走到世界坐标 target：只改 XZ，高度由步态起伏控制。
## seconds ≤ 0 或距离已在容差内时立即到位（同样会发 walk_finished）。
func walk_to(target: Vector3, seconds: float) -> void:
	if _body == null:
		return
	_clear_path()
	var start := _body.global_position
	_from = start
	_to = Vector3(target.x, start.y, target.z)
	_update_facing(_to.x - _from.x)
	if seconds <= 0.0 or _from.distance_to(_to) <= arrive_epsilon:
		_arrive()
		return
	_duration = seconds
	_elapsed = 0.0
	_bob_time = 0.0
	_moving = true
	walk_started.emit(_to)


## 按**速度**走到世界坐标 target：秒数 = 距离 / speed。
## 依据：策划 2026-10-07 裁决第 6b 项 —— 统一速度、耗时随实际行走距离变化（放弃固定 15 tick）。
func walk_to_at_speed(target: Vector3, speed: float) -> void:
	if speed <= 0.0 or _body == null:
		return
	_manual = false
	var start := _body.global_position
	var distance := Vector2(start.x, start.z).distance_to(Vector2(target.x, target.z))
	walk_to(target, distance / speed)


## 沿**导航网格**走到世界坐标 target（主文档 §10.4）：绕开桌椅，耗时随实际路径长度变化。
## 返回 false = 这次没有可执行路线（地图未就绪 / 目标不可达）—— 调用方决定怎么办；
## 本组件**不用直线兜底**（直线会穿桌）。allow_straight_fallback 只给"没有导航地图的单测"用。
func walk_to_navigated(
	target: Vector3, speed: float, allow_straight_fallback: bool = false
) -> bool:
	if _body == null or speed <= 0.0:
		return false
	var points := _query_path(target)
	if points.size() < 2:
		if allow_straight_fallback:
			walk_to_at_speed(target, speed)
			return true
		return false
	_start_path(points, speed)
	return true


## 按**时限**沿导航折线走（速度 = 折线长度 / seconds）。
## 用于上课归位：§10.4 第 6 条要求相位切换后回到座位，不能让人走到上课段结束还在路上。
func walk_to_navigated_in(target: Vector3, seconds: float) -> bool:
	if _body == null or seconds <= 0.0:
		return false
	var points := _query_path(target)
	if points.size() < 2:
		return false
	var length := _polyline_length(points)
	if length <= arrive_epsilon:
		walk_to(target, 0.0)
		return true
	_start_path(points, length / seconds)
	return true


## 折线总长度（米）。
func _polyline_length(points: PackedVector3Array) -> float:
	var length := 0.0
	for k in range(1, points.size()):
		length += Vector2(points[k].x - points[k - 1].x, points[k].z - points[k - 1].z).length()
	return length


## 开始沿折线走。`_to` 取**折线末点**（= 导航吸附后的落点），
## 这样 _arrive() 收尾时不会因为"目标点与导航面差几厘米"而瞬移。
func _start_path(points: PackedVector3Array, speed: float) -> void:
	_clear_path()
	_manual = false
	var start := _body.global_position
	var goal := points[points.size() - 1]
	_from = start
	_to = Vector3(goal.x, start.y, goal.z)
	_base_y = start.y
	_path = points
	_path_index = 0
	_nav_speed = speed
	_elapsed = 0.0
	_bob_time = 0.0
	_moving = true
	_update_facing(points[0].x - start.x)
	walk_started.emit(_to)


## 折线推进：**先走满当前段、再消耗剩余距离**（不切角）；折线走完才 _arrive()。
## 收尾位置由 _arrive() 从 `_to` 取，所以不会跳回上一个目标。
func _advance_path(delta: float) -> void:
	var remaining := _nav_speed * delta
	_bob_time += delta
	var bob := sin(_bob_time * TAU * bob_frequency) * bob_height
	while remaining > 0.0:
		var pos := _body.global_position
		var goal := _path[_path_index]
		var flat := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
		var distance := flat.length()
		if distance <= arrive_epsilon:
			_path_index += 1
			if _path_index >= _path.size():
				_finish_path()
				return
			continue
		var direction := flat / distance
		var step := minf(remaining, distance)
		remaining -= step
		var height := (_base_y + bob) - pos.y
		_body.global_position = pos + direction * step + Vector3(0.0, height, 0.0)
		_update_facing(direction.x)
		if step < distance:
			return
		_path_index += 1
		if _path_index >= _path.size():
			_finish_path()
			return


## 折线走到头：清路径再走统一的到位收尾（位置落在 `_to` = 目标）。
func _finish_path() -> void:
	_clear_path()
	_arrive()


## 清掉折线状态（直线 / 折线 / 手动 / 瞬移之间切换时统一调用）。
func _clear_path() -> void:
	_path = PackedVector3Array()
	_path_index = 0
	_nav_speed = 0.0


## 向导航服务器取折线；地图不可用或查不到路线时返回空数组。
func _query_path(target: Vector3) -> PackedVector3Array:
	if _body == null:
		return PackedVector3Array()
	return NavReady.query_path(_body, _body.global_position, target)


## 手动步进（WASD）：立即沿 delta 移动一小段，并更新朝向与步态。
## 调用方（PlayerController）负责保证 delta 不会让人物穿进家具 —— 本组件不做玩法判断。
## 手动期间 is_moving() 为真（步态在走）；不发 walk_finished（没有「目的地」可到达）。
func move_by(delta: Vector3, delta_time: float) -> void:
	if _body == null:
		return
	_clear_path()
	_moving = false
	_manual = true
	var pos := _body.global_position + delta
	_bob_time += delta_time
	var bob := sin(_bob_time * TAU * bob_frequency) * bob_height
	_body.global_position = Vector3(pos.x, _base_y + bob, pos.z)
	_update_facing(delta.x)


## 结束手动步进：高度归位、步态停下（不发 walk_finished）。
func stop_manual() -> void:
	if not _manual:
		return
	_manual = false
	_settle_height()


## 立刻停下并停在当前位置（打断用，如上课铃响）；同样发 walk_finished。
func stop() -> void:
	if not _moving and not _manual:
		return
	_moving = false
	_manual = false
	_clear_path()
	_settle_height()
	if _body != null:
		_to = _body.global_position
	walk_finished.emit()


## 瞬移到位（初始化 / 归位兜底；不发 walk_started）。
func teleport_to(target: Vector3) -> void:
	if _body == null:
		return
	_moving = false
	_clear_path()
	var pos := _body.global_position
	_body.global_position = Vector3(target.x, pos.y, target.z)
	_from = _body.global_position
	_to = _from
	_base_y = _from.y


func _process(delta: float) -> void:
	if not _moving:
		return
	# 导航折线优先；折线为空 = 原有直线语义（walk_to）
	if not _path.is_empty():
		_advance_path(delta)
		return
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	var eased := _smoothstep(t) if ease_motion else t
	var pos := _from.lerp(_to, eased)
	_bob_time += delta
	var bob := sin(_bob_time * TAU * bob_frequency) * bob_height
	_body.global_position = Vector3(pos.x, _from.y + bob, pos.z)
	if t >= 1.0:
		_arrive()


func _arrive() -> void:
	_moving = false
	if _body != null:
		_body.global_position = Vector3(_to.x, _from.y, _to.z)
	_base_y = _from.y
	if restore_facing_on_arrive and _sprite != null:
		_sprite.flip_h = false
	walk_finished.emit()


## 停下时把高度归位，避免起伏停在半空。
func _settle_height() -> void:
	if _body == null:
		return
	var pos := _body.global_position
	_body.global_position = Vector3(pos.x, _base_y, pos.z)


func _update_facing(dx: float) -> void:
	if not flip_facing or _sprite == null:
		return
	if absf(dx) > arrive_epsilon:
		_sprite.flip_h = dx < 0.0


func _smoothstep(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## 立绘节点：优先按约定名找，找不到就递归找第一个 Sprite3D。
func _find_sprite(node: Node) -> Sprite3D:
	var named := node.get_node_or_null(NodePath(str(sprite_node_name)))
	if named is Sprite3D:
		return named as Sprite3D
	if node is Sprite3D:
		return node as Sprite3D
	for child in node.get_children():
		var found := _find_sprite(child)
		if found != null:
			return found
	return null
