extends SceneTree
## 无头整局运行器（骨架）
##
## 用法：
##   godot --headless --path . --script tests/integration/run_term.gd -- --days=30 --seed=12345
##
## 现状：`scripts/core/` 的 GDScript 内核尚未移植（冲刺计划 D8–D9），
## 因此本入口只解析参数并**明确跳过**，绝不假装通过。
## 内核落地后在此接入整局推进、快照哈希与存档往返断言（见同目录 README.md）。

const KERNEL_PATH := "res://scripts/core/term.gd"
const DEFAULT_DAYS := 30
const DEFAULT_SEED := 12345


func _initialize() -> void:
	var args := _parse_user_args()
	var days: int = int(args.get("days", str(DEFAULT_DAYS)))
	var seed_value: int = int(args.get("seed", str(DEFAULT_SEED)))

	if not ResourceLoader.exists(KERNEL_PATH):
		print("[integration] SKIP：scripts/core/term.gd 尚未落地（冲刺计划 D8–D9），不执行整局。")
		print("[integration] 参数已解析：days=%d seed=%d" % [days, seed_value])
		quit(0)
		return

	# 内核就位后在此接入：
	#   1) 用 seed_value 建立确定性 RNG → 跑 days 天
	#   2) 输出关系矩阵快照哈希，与基线比对
	#   3) 存档往返：每日存档 → 读档 → 继续推进，结果须一致
	print("[integration] 内核已就位，待接入整局逻辑（days=%d seed=%d）" % [days, seed_value])
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
