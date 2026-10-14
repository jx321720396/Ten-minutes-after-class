class_name BehaviorRegistry
extends RefCounted
## 固定行为注册与分发；构造不消费随机数。每个内核实例独立持有。

const CHAT = preload("res://scripts/systems/behaviors/chat_behavior.gd")
const ROUGH_HOUSE = preload("res://scripts/systems/behaviors/roughhouse_behavior.gd")

var _context: RefCounted
var _components: Dictionary


func _init(context: RefCounted) -> void:
	_context = context
	_components = {
		&"chat": CHAT.new(),
		&"roughhouse": ROUGH_HOUSE.new(),
	}
	_context.bind_registry(self)


func execute(kind: StringName, actor: int, target: int, options: Dictionary = {}) -> bool:
	if not _components.has(kind):
		push_warning("BehaviorRegistry：未知行为 %s" % kind)
		return false
	if not _context.is_bound():
		push_warning("BehaviorRegistry：本局内核已释放")
		return false
	if _context.defer_for_player(str(kind), actor, target, options):
		return false
	_components[kind].execute(_context, actor, target, options)
	return true


func has_behavior(kind: StringName) -> bool:
	return _components.has(kind)


## 取组件实例：供内核在**非分发**时机调用（纸条链的「拿到纸条」不在 kind 分发里，
## 它是同一张纸条的后续处理，见 §8.6）。不存在返回 null。
func component(kind: StringName) -> RefCounted:
	return _components.get(kind, null)


func behavior_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for kind in _components:
		ids.append(kind)
	return ids
