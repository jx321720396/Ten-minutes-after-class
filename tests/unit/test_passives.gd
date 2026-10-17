extends GutTest
## 公开专属被动（主文档 §10.2 / §10.4）：分配、逐条效果与接入点的回归。
##
## 断言里的期望值一律从 `data/rules/passive_params.csv` / `rules/harm.csv` 读，
## 不在测试里再抄一份数值 —— 改表后这里只应暴露结构性行为（翻倍 / 累计 / 加法叠加）。
## 角色 → 被动的分配见 `data/rules/passives.csv`（本文件只用 passive_id 找节点，不按角色名判断）。

const SEED := 20261017
const NODES := 16

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.new(SEED, NODES, _tables)


## 拥有某条被动的节点索引（-1 = 本局没有）。
func _index_of(core: SimCore, passive_id: String) -> int:
	for i in range(core.node_count()):
		if core.passive_id_of(i) == passive_id:
			return i
	return -1


func _passives(core: SimCore) -> RefCounted:
	return core._passives


func _number(key: String) -> float:
	for row in _tables.get("rules/passive_params", {}).get("rows", []):
		if str(row.get("param", "")) == key:
			return float(str(row.get("value", "0")))
	return 0.0


func _harm(key: String) -> float:
	for row in _tables.get("rules/harm", {}).get("rows", []):
		if str(row.get("param", "")) == key:
			return float(str(row.get("value", "0")))
	return 0.0


func _act(key: String) -> float:
	for row in _tables.get("rules/activities", {}).get("rows", []):
		if str(row.get("param", "")) == key:
			return float(str(row.get("value", "0")))
	return 0.0


## 把 a、b 放到一对正交邻座（前后左右，不含对角），让 _seat_relation_between 返回 "orthogonal"。
func _seat_orthogonal(core: SimCore, a: int, b: int) -> void:
	for sa in core._seat_pos:
		var pa: Array = core._seat_pos[sa]
		for sb in core._seat_pos:
			if sa == sb:
				continue
			var pb: Array = core._seat_pos[sb]
			if absi(int(pa[0]) - int(pb[0])) + absi(int(pa[1]) - int(pb[1])) == 1:
				core._seat_of[a] = str(sa)
				core._seat_of[b] = str(sb)
				return


# ------------------------------------------------------------------ 分配
func test_every_student_has_one_distinct_passive() -> void:
	var core := _core()
	var seen := {}
	for i in range(core.node_count()):
		var passive_id := core.passive_id_of(i)
		assert_ne(passive_id, "", "%d 号学生应该有公开专属被动" % i)
		seen[passive_id] = true
	assert_eq(seen.size(), core.node_count(), "一局 16 名学生一人一条、互不重复")


func test_profile_snapshot_exposes_passive_id() -> void:
	var core := _core()
	for i in range(core.node_count()):
		var snapshot: Dictionary = core.teacher_student_snapshot(i)
		assert_eq(str(snapshot.get("passive_id", "")), core.passive_id_of(i), "档案快照给出公开被动 id")
		assert_false(core.teacher_student_snapshot(-1).size() > 0, "越界索引不给快照")


# ------------------------------------------------------------------ 学业收益 / 动力
func test_focus_doubles_gain_and_loss_but_not_vitality_cost() -> void:
	var core := _core()
	var passives := _passives(core)
	var i := _index_of(core, "focus")
	var multiplier := _number("focus_gain_multiplier")
	var unit: Dictionary = passives.study_unit(i, 1.0, 5.0)
	assert_almost_eq(float(unit["gain"]), 1.0 * multiplier, 1e-9, "专注：基础 +1 学业收益翻倍")
	assert_almost_eq(float(unit["cost"]), 5.0, 1e-9, "专注不翻倍动力消耗")
	assert_almost_eq(float(passives.play_gain(i, -1.0)), -1.0 * multiplier, 1e-9, "专注：游戏造成的损失同样翻倍")


func test_self_discipline_cuts_study_vitality_cost() -> void:
	var core := _core()
	var passives := _passives(core)
	var i := _index_of(core, "self_discipline")
	var unit: Dictionary = passives.study_unit(i, 1.0, 5.0)
	assert_almost_eq(
		float(unit["cost"]), 5.0 - _number("self_discipline_cost_cut"), 1e-9, "自律：动力消耗少 2 点"
	)
	assert_almost_eq(float(unit["gain"]), 1.0, 1e-9, "自律不改变学业收益")


func test_moderate_halves_losses_with_integer_carry() -> void:
	var core := _core()
	var passives := _passives(core)
	var i := _index_of(core, "moderate")
	assert_almost_eq(float(passives.play_gain(i, -1.0)), 0.0, 1e-9, "收放自如：第一次 1 分损失实际扣 0")
	assert_almost_eq(float(passives.play_gain(i, -1.0)), -1.0, 1e-9, "收放自如：第二次 1 分损失实际扣 1")
	assert_almost_eq(float(passives.play_gain(i, -2.0)), -1.0, 1e-9, "收放自如：一次 2 分损失实际扣 1")
	assert_almost_eq(float(passives.play_gain(i, 3.0)), 3.0, 1e-9, "收放自如不改变正收益")


# ------------------------------------------------------------------ 压力来源（加法叠加）
func test_studious_and_fragile_stack_additively_on_neighbor_drip() -> void:
	var core := _core()
	var passives := _passives(core)
	var studious := _index_of(core, "studious")
	var fragile := _index_of(core, "fragile")
	var plain := _index_of(core, "talkative")
	var drip := 5.0
	assert_almost_eq(
		float(passives.neighbor_drip(studious, plain, drip)), 10.0, 1e-9, "卷王：来源侧 +100%"
	)
	assert_almost_eq(
		float(passives.neighbor_drip(plain, fragile, drip)), 10.0, 1e-9, "玻璃心：目标侧 +100%"
	)
	assert_almost_eq(
		float(passives.neighbor_drip(studious, fragile, drip)),
		15.0,
		1e-9,
		"卷王 + 玻璃心：加法叠加（15，不是 20）"
	)


## 接线验证：真实涓流结算（_settle_neighbor_drip）按来源 + 目标一次算好，不双计。
func test_neighbor_drip_settles_both_sides_through_core() -> void:
	var core := _core()
	var studious := _index_of(core, "studious")
	var fragile := _index_of(core, "fragile")
	core._begin_phase_state()
	for i in range(core.node_count()):
		core._phase_state[i] = "free"
		core._current_act[i] = null
	core._current_act[studious] = "study"
	_seat_orthogonal(core, studious, fragile)  # 涓流只看固定座位前后左右：卷王、玻璃心必须是正交邻座
	core._neighbor_idx[studious] = [fragile]
	core._neighbor_idx[fragile] = [studious]
	core._stress[fragile] = 0.0
	core._settle_neighbor_drip()
	assert_almost_eq(core.stress(fragile), 15.0, 1e-9, "涓流接线：卷王来源 × 玻璃心目标 = 基础 5 的 3 倍")


## 接线验证：学习单位在真实结算循环里就吃到专注翻倍（不是只测 passives 单点）。
func test_study_units_settle_focus_gain_through_core() -> void:
	var core := _core()
	var i := _index_of(core, "focus")
	core._begin_phase_state()
	for k in range(core.node_count()):
		core._phase_state[k] = "free"
		core._current_act[k] = null
	core._current_act[i] = "study"
	core._gain_today[i] = 0.0
	for _tick in range(int(_act("study_settle_seconds"))):
		core._settle_units()
	assert_almost_eq(
		core.gain_today(i),
		_act("study_gain") * _number("focus_gain_multiplier"),
		1e-9,
		"专注学生在真实单位结算里翻倍学业收益"
	)


func test_fragile_amplifies_peer_stress_only() -> void:
	var core := _core()
	var i := _index_of(core, "fragile")
	var doubled := 5.0 * (1.0 + _number("fragile_stress_bonus_ratio"))
	core._stress[i] = 10.0
	core._add_peer_stress(i, 5.0)
	assert_almost_eq(core.stress(i), 10.0 + doubled, 1e-9, "玻璃心：从同学处获得的压力 +100%")
	core._stress[i] = 10.0
	core.add_stress(i, -5.0, false)
	assert_almost_eq(core.stress(i), 5.0, 1e-9, "减压不放大")


func test_spring_awards_vitality_per_accumulated_stress() -> void:
	var core := _core()
	var passives := _passives(core)
	var i := _index_of(core, "spring")
	var per := _number("spring_stress_per_vitality")
	var award := _number("spring_vitality_gain")
	assert_almost_eq(float(passives.spring(i, per - 1.0)), 0.0, 1e-9, "弹簧：不足一段不发动动力")
	assert_almost_eq(float(passives.spring(i, 1.0)), award, 1e-9, "弹簧：累计满一段发一次动力")


func test_spring_reads_gained_stress_through_add_stress() -> void:
	var core := _core()
	var i := _index_of(core, "spring")
	var per := _number("spring_stress_per_vitality")
	var award := _number("spring_vitality_gain")
	core._vitality[i] = 10.0
	core._stress[i] = 0.0
	core.add_stress(i, per)
	assert_almost_eq(core.vitality(i), 10.0 + per + award, 1e-9, "弹簧：一般加压照常联动动力，另按累计多 +2（不递归产生压力）")


# ------------------------------------------------------------------ 友善聊天
func test_forgiving_cuts_extra_hostility_on_friendly_chat() -> void:
	var core := _core()
	core._begin_phase_state()
	var i := _index_of(core, "forgiving")
	var other := _index_of(core, "talkative")
	core._start_conversation(i, other)
	core._h[i * core.node_count() + other] = 30.0
	core._h[other * core.node_count() + i] = 30.0
	core._busy_act[i] = "chat"
	core._busy_phase[i] = 0
	core._busy_until[i] = 0
	core._settle_finished_actions()
	var cut := _harm("friendly_chat_hostility_cut") + _number("forgiving_hostility_cut")
	assert_almost_eq(core.hostility(i, other), 30.0 - cut, 1e-9, "不记仇：本人对聊天对象额外 −2")
	assert_almost_eq(
		core.hostility(other, i), 30.0 - _harm("friendly_chat_hostility_cut"), 1e-9, "对方方向仍按基础 −2"
	)


func test_talkative_adds_owner_affinity_only() -> void:
	var core := _core()
	core._begin_phase_state()
	var i := _index_of(core, "talkative")
	var other := _index_of(core, "self_discipline")
	core._start_conversation(i, other)
	core._a[i * core.node_count() + other] = 40.0
	core._a[other * core.node_count() + i] = 40.0
	core._busy_act[i] = "chat"
	core._busy_phase[i] = 0
	core._busy_until[i] = 0
	core._settle_finished_actions()
	assert_almost_eq(
		core.affinity(i, other),
		40.0 + _number("talkative_affinity_gain"),
		1e-9,
		"健谈：本人对聊天对象好感额外 +2"
	)
	assert_almost_eq(core.affinity(other, i), 40.0, 1e-9, "健谈不改变对方对自己的好感")


func test_likable_adds_partner_affinity_only() -> void:
	var core := _core()
	core._begin_phase_state()
	var i := _index_of(core, "likable")
	var other := _index_of(core, "self_discipline")
	core._start_conversation(i, other)
	core._a[i * core.node_count() + other] = 40.0
	core._a[other * core.node_count() + i] = 40.0
	core._busy_act[i] = "chat"
	core._busy_phase[i] = 0
	core._busy_until[i] = 0
	core._settle_finished_actions()
	assert_almost_eq(
		core.affinity(other, i),
		40.0 + _number("likable_affinity_gain"),
		1e-9,
		"讨人喜欢：聊天对象对本人好感额外 +2"
	)
	assert_almost_eq(core.affinity(i, other), 40.0, 1e-9, "讨人喜欢不改变本人对对象的好感")


func test_empathetic_relieves_partner_stress_without_linking() -> void:
	var core := _core()
	core._begin_phase_state()
	var i := _index_of(core, "empathetic")
	var other := _index_of(core, "self_discipline")
	core._start_conversation(i, other)
	core._stress[other] = 50.0
	core._vitality[other] = 50.0
	core._busy_act[i] = "chat"
	core._busy_phase[i] = 0
	core._busy_until[i] = 0
	core._settle_finished_actions()
	assert_almost_eq(
		core.stress(other), 50.0 - _number("empathetic_stress_relief"), 1e-9, "善解人意：聊天对象压力额外 −5"
	)
	assert_almost_eq(core.vitality(other), 50.0, 1e-9, "善解人意的减压不联动动力")


# ------------------------------------------------------------------ 娱乐完成
func test_optimistic_relieves_stress_once_per_leisure() -> void:
	var core := _core()
	core._begin_phase_state()
	var i := _index_of(core, "optimistic")
	core._stress[i] = 50.0
	core._vitality[i] = 50.0
	core._current_act[i] = "listen_music"
	core._busy_act[i] = "listen_music"
	core._busy_phase[i] = 0
	core._busy_until[i] = 0
	core._settle_finished_actions()
	assert_almost_eq(
		core.stress(i), 50.0 - _number("optimistic_stress_relief"), 1e-9, "乐观：完成一次娱乐压力额外 −3"
	)
	assert_almost_eq(core.vitality(i), 50.0, 1e-9, "乐观的减压不联动动力")


# ------------------------------------------------------------------ 老师训斥
func test_receptive_adds_vitality_when_scolded() -> void:
	var core := _core()
	var i := _index_of(core, "receptive")
	core._vitality[i] = 50.0
	core._note_scolded(i)
	assert_almost_eq(
		core.vitality(i), 50.0 + _number("receptive_vitality_gain"), 1e-9, "听劝：训斥后动力额外 +10"
	)


func test_scold_class_calls_receptive_for_whole_class() -> void:
	var core := _core()
	var i := _index_of(core, "receptive")
	core._vitality[i] = 50.0
	core.teacher_commands().scold_class(core)
	assert_almost_eq(
		core.vitality(i),
		50.0 + _number("receptive_vitality_gain") + _act("class_scold_stress"),
		1e-9,
		"全班训斥：压力联动 +30，听劝再额外 +10 动力"
	)


# ------------------------------------------------------------------ 日结
func test_absorb_bonus_needs_positive_net_gain() -> void:
	var core := _core()
	var i := _index_of(core, "absorb")
	var bonus := _number("absorb_grade_bonus")
	core._gain_today[i] = 2.0
	var before := core.grade(i)
	core._settle_daily_gain(i)
	assert_almost_eq(core.grade(i), before + 2.0 + bonus, 1e-9, "善于吸收：净收益为正 → 成绩额外 +3")
	core._gain_today[i] = -2.0
	before = core.grade(i)
	core._settle_daily_gain(i)
	assert_almost_eq(core.grade(i), before - 2.0, 1e-9, "善于吸收：净收益为负不额外加分")


func test_positive_feedback_pays_vitality_per_grade_point() -> void:
	var core := _core()
	var i := _index_of(core, "positive_feedback")
	core._vitality[i] = 10.0
	core._gain_today[i] = 3.0
	core._settle_daily_gain(i)
	assert_almost_eq(
		core.vitality(i),
		10.0 + 3.0 * _number("positive_feedback_vitality_per_grade"),
		1e-9,
		"正反馈：成绩提高 3 → 动力 +3"
	)


func test_positive_feedback_ignores_grade_drops() -> void:
	var core := _core()
	var i := _index_of(core, "positive_feedback")
	core._vitality[i] = 10.0
	core._gain_today[i] = -3.0
	core._settle_daily_gain(i)
	assert_almost_eq(core.vitality(i), 10.0, 1e-9, "成绩没提高就不发动力")


func test_team_spirit_counts_strictly_above_threshold() -> void:
	var core := _core()
	var i := _index_of(core, "team_spirit")
	var threshold := _number("team_spirit_affinity_threshold")
	var gain := _number("team_spirit_gain")
	var n := core.node_count()
	for j in range(n):
		if j != i:
			core._a[j * n + i] = threshold
	core._gain_today[i] = 0.0
	var before := core.grade(i)
	core._settle_daily_gain(i)
	assert_almost_eq(core.grade(i), before, 1e-9, "恰好等于 60 不计入")
	var over := 0
	for j in range(n):
		if j != i and j % 2 == 0:
			core._a[j * n + i] = threshold + 1.0
			over += 1
	core._gain_today[i] = 0.0
	before = core.grade(i)
	core._settle_daily_gain(i)
	assert_almost_eq(core.grade(i), before + over * gain, 1e-9, "严格超过 60 的每名同学当天学业收益 +1")


func test_team_spirit_reveals_incoming_affinity() -> void:
	var core := _core()
	var i := _index_of(core, "team_spirit")
	var snapshot: Dictionary = core.teacher_student_snapshot(i)
	assert_true(bool(snapshot.get("reveals_incoming_affinity", false)), "群策群力：可见他人对本人好感")
	var other := _index_of(core, "talkative")
	assert_false(
		bool(core.teacher_student_snapshot(other).get("reveals_incoming_affinity", true)),
		"其他被动没有这项可见性"
	)


# ------------------------------------------------------------------ 百事通（只展示，不结算）
func test_well_informed_only_exposes_message_count() -> void:
	var core := _core()
	var i := _index_of(core, "well_informed")
	var snapshot: Dictionary = core.teacher_student_snapshot(i)
	assert_eq(
		int(snapshot.get("well_informed_messages", 0)),
		int(_number("well_informed_messages")),
		"百事通：档案展示一次打听可得 6 条消息"
	)
