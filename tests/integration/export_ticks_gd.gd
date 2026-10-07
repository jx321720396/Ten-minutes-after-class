extends SceneTree
## GDScript 侧逐 tick 导出入口（骨架）—— 供 tests/integration/test_tick_parity.py 调用。
##
## 用法：
##   godot --headless --path . --script tests/integration/export_ticks_gd.gd \
##         -- --days=3 --seed=12345 --npc=8 --out=tools/out/ticks_gd.jsonl
##
## 输出格式必须与 Python 侧 tools/export_ticks.py **逐字段一致**（jsonl，每个 tick 一行）：
##   tick, day, phase, phase_index, tick_in_phase,
##   A_mean, H_mean, T_mean, O_mean, stress_mean,
##   A_hash, H_hash, T_hash, events, bursts, transmits
##
## 现状：`scripts/core/` 的 GDScript 内核尚未移植（冲刺计划 D8–D9），本入口明确跳过；
## 内核落地后在此接入同种子整局运行 + 逐 tick 采样。

const KERNEL_PATH := "res://scripts/core/term.gd"


func _initialize() -> void:
	var args := _parse_user_args()
	var days: int = int(args.get("days", "3"))
	var seed_value: int = int(args.get("seed", "12345"))
	var npc: int = int(args.get("npc", "8"))
	var out_path: String = args.get("out", "tools/out/ticks_gd.jsonl")

	if not ResourceLoader.exists(KERNEL_PATH):
		print("[parity] SKIP：scripts/core/term.gd 尚未落地（冲刺计划 D8–D9），不执行导出。")
		print("[parity] 参数已解析：days=%d seed=%d npc=%d out=%s" % [days, seed_value, npc, out_path])
		quit(0)
		return

	# 内核就位后在此接入：
	#   1) 用 seed_value 建立确定性 RNG，跑 days 天
	#   2) 每个 tick 采样一次（字段与 tools/export_ticks.py 完全一致）
	#   3) 写到 out_path（jsonl，UTF-8）
	print("[parity] 内核已就位，待接入逐 tick 导出（days=%d seed=%d npc=%d）" % [days, seed_value, npc])
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
