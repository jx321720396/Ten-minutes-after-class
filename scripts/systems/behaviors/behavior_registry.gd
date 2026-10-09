class_name BehaviorRegistry
extends RefCounted
## 固定行为注册与分发；构造不消费随机数。每个内核实例独立持有。

const CHAT = preload("res://scripts/systems/behaviors/chat_behavior.gd")
const JOIN_CHAT = preload("res://scripts/systems/behaviors/join_chat_behavior.gd")
const TEASE = preload("res://scripts/systems/behaviors/tease_behavior.gd")
const REPORT = preload("res://scripts/systems/behaviors/report_behavior.gd")
const RUMOR = preload("res://scripts/systems/behaviors/rumor_behavior.gd")
const ROUGH_HOUSE = preload("res://scripts/systems/behaviors/roughhouse_behavior.gd")
const EXCLUDE = preload("res://scripts/systems/behaviors/exclude_behavior.gd")
const COMFORT = preload("res://scripts/systems/behaviors/comfort_behavior.gd")
const ASK_HELP = preload("res://scripts/systems/behaviors/ask_help_behavior.gd")
const APOLOGIZE = preload("res://scripts/systems/behaviors/apologize_behavior.gd")

var _context: RefCounted
var _components: Dictionary


func _init(context: RefCounted) -> void:
	_context = context
	_components = {
		&"chat": CHAT.new(),
		&"join_chat": JOIN_CHAT.new(),
		&"tease": TEASE.new(),
		&"report": REPORT.new(),
		&"rumor": RUMOR.new(),
		&"roughhouse": ROUGH_HOUSE.new(),
		&"exclude": EXCLUDE.new(),
		&"comfort": COMFORT.new(),
		&"ask_help": ASK_HELP.new(),
		&"apologize": APOLOGIZE.new(),
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


func behavior_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for kind in _components:
		ids.append(kind)
	return ids
