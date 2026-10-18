extends SceneTree
## 一天收支与过程记录（三策略同种子对照，**参数不变**）。
##
## 三策略（对应体验目标：放任付成绩代价；适度督学有可达路径；过度督学同时付压力与关系代价）：
##   A idle     —— 自动巡查、**无主动操作**（基线；不是「老师完全不参与」）
##   B limited  —— 有限督学 + 请教／座位安排：每课间 1 次换座 + 2 人次表扬
##   C intense  —— 集中持续督学：课间时间尽量用满，全用训斥
##
## 记录过程而非只看日末：压力峰值与 >70 持续、学习与同组请教人数、敌对总量、伤害与拒绝、
## 老师操作占用的 tick（真实时间成本）。
##
## 运行：`godot --headless --path . --script res://tools/headless_day_book.gd -- [days] [seed] [npc]`
## 参数：days 默认 8（含首次考核）、seed 默认 12345、npc 默认 16。只读 `data/`，不改数值。

const STRATEGIES := ["idle", "limited", "intense"]
const LIMITED_CHATS := 2
const HIGH_STRESS := 70.0
const FULL_AFFINITY := 95.0


## 探针内核：记录加压／减压、伤害加压次数与单日单对子事件次数。
class ProbeCore:
	extends "res://scripts/core/sim_core.gd"
	var stress_added := 0.0
	var stress_removed := 0.0
	var harm_calls := 0
	var harm_total := 0.0
	var pair_events: Dictionary = {}
	var pair_event_max := 0

	func add_stress(i: int, delta: float, linked: bool = true) -> void:
		if delta > 0.0:
			stress_added += delta
		elif delta < 0.0:
			stress_removed += -delta
		super.add_stress(i, delta, linked)

	func _add_peer_stress(target: int, base: float) -> void:
		harm_calls += 1
		harm_total += base
		super._add_peer_stress(target, base)

	func _apply_event(i: int, j: int, event_id: String, scale: float = 1.0) -> bool:
		var ok := super._apply_event(i, j, event_id, scale)
		if ok:
			var key := "%d,%d" % [i, j]
			var count := int(pair_events.get(key, 0)) + 1
			pair_events[key] = count
			if count > pair_event_max:
				pair_event_max = count
		return ok

	func reset_pair_events() -> void:
		pair_events = {}
		pair_event_max = 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var days := 8
	var seed_value := 12345
	var npc := 16
	if args.size() >= 1:
		days = int(args[0])
	if args.size() >= 2:
		seed_value = int(args[1])
	if args.size() >= 3:
		npc = int(args[2])

	var tables := ConfigLoader.new().load_all()
	print("=== 三策略对照（参数不变｜seed=%d｜%d 人｜%d 天）===" % [seed_value, npc, days])
	print("")
	var rows: Array = []
	for strategy in STRATEGIES:
		rows.append(_run(tables, strategy, days, seed_value, npc))
	_print_compare(rows)
	print("")
	_print_structure(tables, seed_value, npc)
	quit(0)


func _run(tables: Dictionary, strategy: String, days: int, seed_value: int, npc: int) -> Dictionary:
	var core := ProbeCore.new(seed_value, npc, tables)
	var tc: TeacherCommands = core.teacher_commands()
	var timing := _params(tables, "rules/teacher_commands")
	var exam_params := _params(tables, "rules/exam")
	var pre_bonus := float(exam_params.get("pre_exam_stress_bonus", "0"))
	var post_cut := float(exam_params.get("post_exam_stress_cut", "0"))
	var chat_seconds := maxf(1.0, float(timing["office_chat_seconds"]))
	var break_ticks := _break_ticks(tables)
	var quota := 0
	var do_seat := false
	var chat_kind := "praise"
	if strategy == "limited":
		quota = LIMITED_CHATS
		do_seat = true
	elif strategy == "intense":
		quota = int(break_ticks / chat_seconds)
		chat_kind = "scold"

	print(
		"--- 策略 %s（每课间会面上限 %d 人次，换座 %s）---" % [_name_of(strategy), quota, "是" if do_seat else "否"]
	)
	var totals := {"busy": 0, "served": 0, "harm": 0, "rejects": 0, "peak": 0.0, "high": 0}
	totals["study"] = 0.0
	totals["help"] = 0.0
	totals["broken"] = 0
	var last_phase := -1
	var quota_left := 0
	var chat_started := false
	var seat_done := false
	var served: Dictionary = {}
	for d in range(days):
		var stats := {
			"stress": 0.0,
			"vitality": 0.0,
			"grade": 0.0,
			"peak": 0.0,
			"high": 0,
			"study": 0,
			"help": 0,
			"play": 0,
			"broken": 0,
		}
		var harm_before := core.harm_calls
		var rejects_before := int(core._stats.get("join_rejects", 0))
		var busy_before := int(totals["busy"])
		core.reset_pair_events()
		served = {}
		var ticks := 0
		var exam_day: bool = core._exam.is_exam_day(d + 1)
		for _t in range(2000):
			if core.day() != d + 1:
				break
			ticks += 1
			if core.phase_index() != last_phase:
				last_phase = core.phase_index()
				quota_left = quota if core.phase() == "break" else 0
				chat_started = false
				seat_done = false
				if strategy != "idle" and core.phase() == "break" and not exam_day:
					tc.enter_classroom(core)
			if strategy != "idle" and not exam_day:
				var step := _supervise(
					core, tc, strategy, chat_kind, quota_left, chat_started, seat_done, served
				)
				quota_left = int(step[0])
				chat_started = bool(step[1])
				seat_done = bool(step[2])
				if tc.current_command() != "":
					totals["busy"] = int(totals["busy"]) + 1
			core.advance_tick()
			var stress_sum := 0.0
			var vitality_sum := 0.0
			var grade_sum := 0.0
			var study := 0
			var help := 0
			var play := 0
			for i in range(npc):
				var s: float = core.stress(i)
				stress_sum += s
				vitality_sum += core.vitality(i)
				grade_sum += core.grade(i)
				if s > stats["peak"]:
					stats["peak"] = s
				if s > HIGH_STRESS:
					stats["high"] = int(stats["high"]) + 1
				var kind := str(core._unit_kind(i))
				if kind == "study":
					study += 1
					if core._study_of[i] != null:
						help += 1
				elif kind == "play":
					play += 1
				if core.is_broken(i):
					stats["broken"] = int(stats["broken"]) + 1
			stats["stress"] = float(stats["stress"]) + stress_sum / float(npc)
			stats["vitality"] = float(stats["vitality"]) + vitality_sum / float(npc)
			stats["grade"] = float(stats["grade"]) + grade_sum / float(npc)
			stats["study"] = int(stats["study"]) + study
			stats["help"] = int(stats["help"]) + help
			stats["play"] = int(stats["play"]) + play
		var day_harm: int = core.harm_calls - harm_before
		var day_rejects: int = int(core._stats.get("join_rejects", 0)) - rejects_before
		var day_busy: int = int(totals["busy"]) - busy_before
		var hostility_sum := 0.0
		var hostility_max := 0.0
		for i in range(npc):
			for j in range(npc):
				if i == j:
					continue
				var h: float = core.hostility(i, j)
				hostility_sum += h
				hostility_max = maxf(hostility_max, h)
		totals["peak"] = maxf(float(totals["peak"]), float(stats["peak"]))
		totals["high"] = int(totals["high"]) + int(stats["high"])
		totals["harm"] = int(totals["harm"]) + day_harm
		totals["rejects"] = int(totals["rejects"]) + day_rejects
		totals["broken"] = int(totals["broken"]) + int(stats["broken"])
		totals["study"] = float(totals["study"]) + float(stats["study"]) / float(maxi(1, ticks))
		totals["help"] = float(totals["help"]) + float(stats["help"]) / float(maxi(1, ticks))
		totals["served"] = int(totals["served"]) + served.size()
		var tag := ""
		if core._exam.is_exam_eve(d + 1):
			tag = "｜当日末：考前全班 +%.0f 压力" % pre_bonus
		if exam_day:
			tag = "｜考试日：考后全班 −%.0f 压力｜当日不做老师操作" % post_cut
		print(
			(
				"  日 %d｜成绩 %.1f 动力 %.1f 压力 %.1f（峰 %.1f，>70 共 %d tick）%s"
				% [
					d + 1,
					float(stats["grade"]) / float(maxi(1, ticks)),
					float(stats["vitality"]) / float(maxi(1, ticks)),
					float(stats["stress"]) / float(maxi(1, ticks)),
					float(stats["peak"]),
					int(stats["high"]),
					tag,
				]
			)
		)
		print(
			(
				"      学习 %.1f 人（共同学习组 %.1f）游戏 %.1f 人｜敌对 Σ%.0f max %.1f"
				% [
					float(stats["study"]) / float(maxi(1, ticks)),
					float(stats["help"]) / float(maxi(1, ticks)),
					float(stats["play"]) / float(maxi(1, ticks)),
					hostility_sum,
					hostility_max,
				]
			)
		)
		print(
			(
				"      伤害 %d 拒绝 %d 崩溃人·tick %d｜老师占用 %d tick"
				% [day_harm, day_rejects, int(stats["broken"]), day_busy]
			)
		)
	var exam_mean: float = core._exam.last_exam_mean()
	var passed: bool = core._exam.last_passed()
	print(
		(
			"  汇总：最高压力 %.1f｜>70 累计 %d tick｜伤害 %d 次｜加入被拒 %d 次｜崩溃人·tick %d｜会面 %d 人次"
			% [
				float(totals["peak"]),
				int(totals["high"]),
				int(totals["harm"]),
				int(totals["rejects"]),
				int(totals["broken"]),
				int(totals["served"]),
			]
		)
	)
	return {
		"strategy": strategy,
		"grade": _avg(core, npc, "grade"),
		"exam": exam_mean,
		"passed": passed,
		"affinity": _affinity_mean(core, npc),
		"stress": _avg(core, npc, "stress"),
		"vitality": _avg(core, npc, "vitality"),
		"peak": float(totals["peak"]),
		"high": int(totals["high"]),
		"harm": int(totals["harm"]),
		"rejects": int(totals["rejects"]),
		"broken": int(totals["broken"]),
		"study": float(totals["study"]) / float(days),
		"help": float(totals["help"]) / float(days),
		"busy": int(totals["busy"]) / days,
	}


## 老师代理：可选换座（每课间 1 次）→ 召唤 → 办公室聊天 → 送回。返回 [配额, 已聊天, 已换座]。
func _supervise(
	core: ProbeCore,
	tc: TeacherCommands,
	strategy: String,
	kind: String,
	quota_left: int,
	chat_started: bool,
	seat_done: bool,
	served: Dictionary
) -> Array:
	if tc.called_index() < 0 and tc.current_command() == "":
		if strategy == "limited" and not seat_done:
			var pair := _pick_seat_swap(core)
			if pair.size() == 2 and tc.start_seat_change(core, int(pair[0]), int(pair[1])):
				return [quota_left, false, true]
		if quota_left <= 0:
			return [quota_left, false, seat_done]
		var target := _pick_target(core, served)
		if target >= 0 and tc.summon(core, target):
			served[str(target)] = true
			return [quota_left - 1, false, seat_done]
		return [quota_left, false, seat_done]
	if tc.current_command() != "":
		return [quota_left, chat_started, seat_done]
	if tc.called_index() < 0:
		return [quota_left, false, seat_done]
	if not chat_started:
		return [quota_left, tc.office_chat(core, kind), seat_done]
	tc.send_back(core)
	return [quota_left, false, seat_done]


## 座位安排：把动力最低的学生换到「当前动力最高的学习者」的正交邻座上。
func _pick_seat_swap(core: ProbeCore) -> Array:
	var anchor := -1
	var anchor_v := -1.0
	for i in range(core.node_count()):
		if str(core._unit_kind(i)) != "study" or not core.in_own_seat(i):
			continue
		var v: float = core.vitality(i)
		if v > anchor_v:
			anchor = i
			anchor_v = v
	if anchor < 0:
		return []
	var worst := -1
	var worst_v := 1e9
	for i in range(core.node_count()):
		if i == anchor or core._are_neighbors(i, anchor) or not core.is_present(i):
			continue
		var v: float = core.vitality(i)
		if v < worst_v:
			worst = i
			worst_v = v
	var mate := -1
	var mate_v := 1e9
	for j in range(core.node_count()):
		if j == anchor or not core._are_neighbors(j, anchor) or j == worst:
			continue
		var v: float = core.vitality(j)
		if v < mate_v:
			mate = j
			mate_v = v
	if worst < 0 or mate < 0:
		return []
	return [worst, mate]


func _pick_target(core: ProbeCore, served: Dictionary) -> int:
	var best := -1
	var best_v := 1e9
	for i in range(core.node_count()):
		if not core.is_present(i) or served.has(str(i)):
			continue
		var v: float = core.vitality(i)
		if v < best_v:
			best = i
			best_v = v
	return best


func _print_compare(rows: Array) -> void:
	print("=== 对照（同 seed，参数不变）===")
	print("  策略      成绩  考分  通过  好感  压力  动力  压力峰  >70t  伤害  拒绝  崩溃  学习/天  同组/天  占用/天")
	for row in rows:
		print(
			(
				"  %-10s %5.1f %5.1f %-5s %5.1f %5.1f %5.1f %6.1f %5d %5d %5d %5d %8.1f %8.1f %8d"
				% [
					_name_of(str(row["strategy"])),
					float(row["grade"]),
					float(row["exam"]),
					str(row["passed"]),
					float(row["affinity"]),
					float(row["stress"]),
					float(row["vitality"]),
					float(row["peak"]),
					int(row["high"]),
					int(row["harm"]),
					int(row["rejects"]),
					int(row["broken"]),
					float(row["study"]),
					float(row["help"]),
					int(row["busy"]),
				]
			)
		)


func _print_structure(tables: Dictionary, seed_value: int, npc: int) -> void:
	print("=== 满格好感结构（30 天，有限督学：换座 + 表扬 2 人次）===")
	var core := ProbeCore.new(seed_value, npc, tables)
	var tc: TeacherCommands = core.teacher_commands()
	var quota := LIMITED_CHATS
	var last_phase := -1
	var quota_left := 0
	var chat_started := false
	var seat_done := false
	var served: Dictionary = {}
	for _d in range(30):
		served = {}
		core.reset_pair_events()
		for _t in range(2000):
			if core.day() != _d + 1:
				break
			if core.phase_index() != last_phase:
				last_phase = core.phase_index()
				quota_left = quota if core.phase() == "break" else 0
				chat_started = false
				seat_done = false
				if core.phase() == "break":
					tc.enter_classroom(core)
			var step := _supervise(
				core, tc, "limited", "praise", quota_left, chat_started, seat_done, served
			)
			quota_left = int(step[0])
			chat_started = bool(step[1])
			seat_done = bool(step[2])
			core.advance_tick()
	var full := 0
	var full_mutual := 0
	var full_neighbor := 0
	var pairs := npc * (npc - 1)
	var near_sum := 0.0
	var near_n := 0
	var far_sum := 0.0
	var far_n := 0
	for i in range(npc):
		for j in range(npc):
			if i == j:
				continue
			var a: float = core.affinity(i, j)
			if core._are_neighbors(i, j):
				near_sum += a
				near_n += 1
			else:
				far_sum += a
				far_n += 1
			if a >= FULL_AFFINITY:
				full += 1
				if float(core.affinity(j, i)) >= FULL_AFFINITY:
					full_mutual += 1
				if core._are_neighbors(i, j):
					full_neighbor += 1
	print(
		(
			"  满格(≥%.0f) %d/%d（%.1f%%）｜双向 %d｜邻座 %d｜邻座均值 %.1f vs 非邻座 %.1f"
			% [
				FULL_AFFINITY,
				full,
				pairs,
				100.0 * float(full) / float(pairs),
				full_mutual,
				full_neighbor,
				near_sum / float(maxi(1, near_n)),
				far_sum / float(maxi(1, far_n)),
			]
		)
	)


func _name_of(strategy: String) -> String:
	match strategy:
		"idle":
			return "无主动操作"
		"limited":
			return "有限督学"
		"intense":
			return "集中督学"
	return strategy


func _avg(core: ProbeCore, npc: int, key: String) -> float:
	var total := 0.0
	for i in range(npc):
		match key:
			"grade":
				total += core.grade(i)
			"stress":
				total += core.stress(i)
			"vitality":
				total += core.vitality(i)
	return total / float(npc)


func _affinity_mean(core: ProbeCore, npc: int) -> float:
	var total := 0.0
	for i in range(npc):
		for j in range(npc):
			if i != j:
				total += core.affinity(i, j)
	return total / float(npc * (npc - 1))


func _break_ticks(tables: Dictionary) -> int:
	var total := 0
	for row in tables.get("rules/phases", {}).get("rows", []):
		if str(row.get("kind", "")) == "break":
			total += int(str(row.get("tick_count", "0")))
	return total


func _params(tables: Dictionary, name: String) -> Dictionary:
	var rows: Array = tables.get(name, {}).get("rows", [])
	var out := {}
	for row in rows:
		out[str(row.get("param", ""))] = str(row.get("value", "0"))
	return out
