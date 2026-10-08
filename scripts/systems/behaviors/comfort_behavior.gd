extends RefCounted
## comfort：由 SimCore 兼容入口调用，共用本局结算服务。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, _options: Dictionary = {}) -> void:
	context.occupy(i, j, "comfort")
	context.apply_event(i, j, "comfort_cost_stress")
	context.apply_event(j, i, "comfort_target_stress")
	context.apply_event(j, i, "comfort_target_affinity")
	context.apply_event(j, i, "comfort_target_trust")
	context.increment_stat("comforts")
	context.emit_event("event_happened", {"kind": "comfort", "i": i, "j": j})
