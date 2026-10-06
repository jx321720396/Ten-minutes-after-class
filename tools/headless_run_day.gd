extends SceneTree
## D7 无头演示：抽取函数验证 + 跑完 1 天（占位结算）。
##
## 运行：godot --headless --path . --script res://tools/headless_run_day.gd

const DIMS := ["e", "n", "f", "p"]


func _init() -> void:
	var tables := ConfigLoader.new().load_all()
	var seeds: Array = tables["characters/seeds"]["rows"]
	var bindings: Array = tables["characters/bindings"]["rows"]
	var kp := _params(tables, "rules/kernel_params")
	var neutral := float(kp["mbti_neutral"])

	var roster: Array = RosterSelector.new().select(seeds, bindings, 8, neutral)

	print("=== 抽取结果（8 人，绑定组 + MBTI 四维极性覆盖）===")
	for row in roster:
		print("  %s %s  E=%s N=%s F=%s P=%s" % [
			row["alias"], row["mbti"], row["e"], row["n"], row["f"], row["p"]])
	print("  —— 极性覆盖 ——")
	for d in DIMS:
		var has_high := false
		var has_low := false
		for row in roster:
			var v := float(str(row[d]))
			if v > neutral:
				has_high = true
			elif v < neutral:
				has_low = true
		print("  %s  高:%s  低:%s" % [d.to_upper(), _check(has_high), _check(has_low)])

	print("")
	var core := SimCore.new(12345, 8, tables)
	var total := core.run_day()
	print("单日总 tick：%d（课间 100×3 + 上课 90×2 = 480）" % total)
	print("涓流结算点（settle_interval=%d）应触发 2 次（tick 240 / 480）" % int(kp_interval(tables)))
	print("")
	print(core.report())
	quit(0)


func _params(tables: Dictionary, name: String) -> Dictionary:
	var out := {}
	for row in tables[name]["rows"]:
		out[str(row["param"])] = float(str(row["value"]))
	return out


func kp_interval(tables: Dictionary) -> int:
	return int(_params(tables, "rules/transmission")["settle_interval"])


func _check(b: bool) -> String:
	return "✓" if b else "✗"
