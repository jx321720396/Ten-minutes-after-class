extends RefCounted
## report：由 SimCore 兼容入口调用，共用本局结算服务。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, _options: Dictionary = {}) -> void:
	context.apply_event(j, i, "report_stress")
	context.apply_event(j, i, "report_hostility")
	context.mark_hurt(i, j)
	context.reduce_reporter_hostility(i, j)
	context.increment_stat("reports")
	context.emit_event("event_happened", {"kind": "report", "i": i, "j": j})
