class_name TableBuilders
extends RefCounted
## 配置表 → 内核派生结构（从 SimCore 拆出，控制内核主文件行数；纯函数、无状态）。
## 2026-10-18：`_build_behaviors` / `_build_grade_bands` / `_build_behavior_probs` / `_build_thresholds`
## 迁到这里，控制内核主文件行数。


static func behaviors(tables: Dictionary) -> Dictionary:
	var out := {}
	for row in tables.get("rules/behaviors", {}).get("rows", []):
		out[str(row["behavior"])] = {
			"duration": int(float(str(row["duration"]))),
			"payoff": float(str(row["payoff"])),
			"kind": str(row["kind"]),
			"noise": float(str(row.get("noise", "0"))),
			"join_mode": str(row.get("join_mode", "none")).strip_edges(),
		}
	return out


static func grade_bands(tables: Dictionary) -> Array:
	var bands: Array = []
	for row in tables.get("rules/grade_table", {}).get("rows", []):
		bands.append([float(row["band_upper"]), float(row["ticks_per_point"])])
	bands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return bands


static func behavior_probs(tables: Dictionary) -> Dictionary:
	var out := {}
	for row in tables.get("rules/behavior_probs", {}).get("rows", []):
		out[str(row["behavior"])] = float(str(row["base_p"]))
	return out


static func thresholds(tables: Dictionary) -> Dictionary:
	var out := {}
	for row in tables.get("rules/behavior_thresholds", {}).get("rows", []):
		out["%s_%s" % [str(row["behavior"]), str(row["metric"])]] = float(str(row["value"]))
	return out
