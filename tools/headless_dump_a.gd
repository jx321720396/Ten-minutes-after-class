extends SceneTree
## 临时诊断：dump 指定 tick 的完整 A 矩阵（0.1 精度，逗号分隔），用于定位分叉的 (i,j)。
## 运行：godot --headless --path . --script res://tools/headless_dump_a.gd -- 11 12345 16

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var tick_target := 11
	var seed := 12345
	var npc := 16
	if args.size() >= 1:
		tick_target = int(args[0])
	if args.size() >= 2:
		seed = int(args[1])
	if args.size() >= 3:
		npc = int(args[2])

	var tables := ConfigLoader.new().load_all()
	var core := SimCore.new(seed, npc, tables)
	for _t in range(tick_target):
		core.advance_tick()
	var n := core.node_count()
	var vals: Array[String] = []
	for i in range(n):
		for j in range(n):
			vals.append("%.1f" % core.affinity(i, j))
	print(",".join(vals))
	quit(0)
