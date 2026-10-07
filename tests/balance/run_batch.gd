extends SceneTree
## 批量标定运行器（骨架）
##
## 用法：
##   godot --headless --path . --script tests/balance/run_batch.gd -- --runs=100 --days=30 --seed=1
##
## 现状：`scripts/core/` 的 GDScript 内核尚未移植（冲刺计划 D8–D9），本入口明确跳过。
## 离线标定请先用 Python 侧：`python tools/check_metrics.py`（默认 100 局）。

const KERNEL_PATH := "res://scripts/core/term.gd"
const DEFAULT_RUNS := 100
const DEFAULT_DAYS := 30
const DEFAULT_SEED := 1


func _initialize() -> void:
	var args := _parse_user_args()
	var runs: int = int(args.get("runs", str(DEFAULT_RUNS)))
	var days: int = int(args.get("days", str(DEFAULT_DAYS)))
	var seed_value: int = int(args.get("seed", str(DEFAULT_SEED)))

	if not ResourceLoader.exists(KERNEL_PATH):
		print("[balance] SKIP：scripts/core/term.gd 尚未落地，不执行批量标定。")
		print("[balance] 参数已解析：runs=%d days=%d seed=%d" % [runs, days, seed_value])
		print("[balance] 离线替代：python tools/check_metrics.py（默认 100 局，与 docs/qa/测试策略.md §4 同判据）")
		quit(0)
		return

	# 内核就位后在此接入：runs 局 × days 天的统计（均值 / 饱和率 / 分化度 / 爆发频率）
	print("[balance] 内核已就位，待接入批量统计（runs=%d days=%d seed=%d）" % [runs, days, seed_value])
	quit(0)


func _parse_user_args() -> Dictionary:
	var out := {}
	for item in OS.get_cmdline_user_args():
		var text := String(item)
		if not text.begins_with("--") or not text.contains("="):
			continue
		var parts := text.substr(2).split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out
