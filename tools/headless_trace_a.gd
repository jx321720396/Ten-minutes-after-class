extends SceneTree
func _init() -> void:
	var tables := ConfigLoader.new().load_all()
	var core := SimCore.from_npc(12345, 16, tables)
	for _t in range(12):
		core.advance_tick()
		var gt: int = core.global_tick()
		if gt >= 10 and gt <= 12:
			var v: float = core.affinity(2, 3)
			print("gd tick=", gt, " A[2][3]=", "%.17f" % v)
	quit(0)
