extends RefCounted
## apologize：由 SimCore 兼容入口调用，共用本局结算服务。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, _options: Dictionary = {}) -> void:
	context.occupy(i, j, "apologize")
	context.apply_event(i, j, "apologize_cost_stress")
	var score := (
		context.affinity(j, i)
		+ context.dimension(j, 2) / 100.0 * context.threshold("apologize_calm_bonus")
		- context.hostility(j, i) * context.threshold("apologize_hostility_penalty")
	)
	var p := context.sigmoid(
		(
			(score - context.threshold("apologize_accept_theta"))
			/ context.threshold("apologize_accept_scale")
		)
	)
	var choice: Variant = context.player_choice(i)
	var accepted: bool = bool(choice) if choice != null else context.random() < p
	if accepted:
		context.apply_event(i, j, "apologize_ok_hostility", 1.0, true)
		context.apply_event(i, j, "apologize_ok_affinity", 1.0, true)
		context.apply_event(i, j, "apologize_ok_trust", 1.0, true)
		context.apply_event(i, j, "apologize_ok_stress", 1.0, true)
		context.apply_event(j, i, "apologize_ok_hostility", 1.0, true)
		context.apply_event(j, i, "apologize_ok_affinity", 1.0, true)
		context.apply_event(j, i, "apologize_ok_trust", 1.0, true)
		context.apply_event(j, i, "apologize_ok_stress", 1.0, true)
		context.increment_stat("apologizes")
	else:
		context.apply_event(i, j, "apologize_no_hostility", 1.0, true)
		context.apply_event(i, j, "apologize_no_stress", 1.0, true)
		context.apply_event(i, j, "apologize_no_trust", 1.0, true)
		context.increment_stat("apologize_rejects")
	context.emit_event(
		"event_happened", {"kind": "apologize", "i": i, "j": j, "accepted": accepted}
	)
