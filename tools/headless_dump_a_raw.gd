extends SceneTree
func _init() -> void:
	var tables := ConfigLoader.new().load_all()
	var core := SimCore.from_npc(12345, 16, tables)
	for _t in range(11):
		core.advance_tick()
	var pairs := [[2,3],[2,0],[3,2],[0,2],[3,0]]
	for p in pairs:
		var i: int = p[0]
		var j: int = p[1]
		var v: float = core.affinity(i, j)
		var raw := "%.17f" % v
		print("gd A[", i, "][", j, "] = ", raw, "  snapped1=", snapped(v, 0.1))
	quit(0)
