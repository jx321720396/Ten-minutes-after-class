extends SceneTree
## D9 性能基准：8 人 × 30 天无头跑，测墙钟时间（验收 < 5 s）。
##
## 运行：godot --headless --path . --script res://tools/headless_run_bench.gd

func _init() -> void:
	var tables := ConfigLoader.new().load_all()
	var core := SimCore.new(12345, 8, tables)
	var t0 := Time.get_ticks_usec()
	for d in range(30):
		core.run_day()
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	print("=== 性能基准：8 人 × 30 天 ===")
	print("  耗时 %.3f s（阈值 5 s，%s）" % [dt, "通过" if dt < 5.0 else "超时"])
	print("")
	print(core.report())
	quit(0)
