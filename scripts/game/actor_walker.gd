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


## 手动步进（WASD）：立即沿 delta 移动一小段，并更新朝向与步态。
## 调用方（PlayerController）负责保证 delta 不会让人物穿进家具 —— 本组件不做玩法判断。
## 手动期间 is_moving() 为真（步态在走）；不发 walk_finished（没有「目的地」可到达）。
func move_by(delta: Vector3, delta_time: float) -> void:
	if _body == null:
		return
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
	_settle_height()
	if _body != null:
		_to = _body.global_position
	walk_finished.emit()


## 瞬移到位（初始化 / 归位兜底；不发 walk_started）。
func teleport_to(target: Vector3) -> void:
	if _body == null:
		return
	_moving = false
	var pos := _body.global_position
	_body.global_position = Vector3(target.x, pos.y, target.z)
	_from = _body.global_position
	_to = _from
	_base_y = _from.y


func _process(delta: float) -> void:
	if not _moving:
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
