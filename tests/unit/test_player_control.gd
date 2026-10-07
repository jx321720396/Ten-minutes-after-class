extends GutTest
## 玩家控制边界单测（内核策划符合性审查 P1-01 / P1-02）。
##
## 依据：主文档 §12.1（玩家决策来源为人的主动选择）、§3.3（上课禁令）、§10.8（睡眠排除）；
##      docs/qa/2026-10-07-内核策划符合性审查.md P1-01 / P1-02。

const SEED := 12345
const NPC := 8
const TICKS_BREAK := 100


func _core() -> SimCore:
	return SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())


func _last(core: SimCore) -> int:
	return int(core.node_count()) - 1


## 跑完一个课间段，让内核进入上午上课（§3.3 禁止主动社交）。
func _enter_class(core: SimCore) -> void:
	for _i in range(TICKS_BREAK):
		core.advance_tick()
	core.finish_time_boundary()
	assert_eq(str(core.time_snapshot()["kind"]), "class", "应已进入上课段")


func test_player_never_acts_on_its_own() -> void:
	# P1-01：玩家（末位节点）不得参与 NPC 自主决策。
	# 口径与审查报告一致：统计 event_happened 里「发起者 = 玩家」的次数。
	var core := _core()
	var from_player: Array = []
	core.event_sink = func(e: Dictionary) -> void:
		if e["type"] != "event_happened":
			return
		var payload: Dictionary = e["payload"]
		if payload.has("i") and int(payload["i"]) == _last(core):
			from_player.append(payload.get("kind", ""))

	for _i in range(TICKS_BREAK):
		core.advance_tick()

	assert_eq(from_player.size(), 0, "玩家不应自主发起任何行为：%s" % str(from_player))


func test_player_cannot_act_during_class() -> void:
	# P1-02：上课段玩家的行动入口必须**自己拒绝**，不能只靠 UI 隐藏按钮。
	var core := _core()
	_enter_class(core)

	var result: Dictionary = core.player_action("chat", 0)
	assert_false(result["ok"], "上课段不能发起社交")
	assert_eq(str(result["error"]), "phase_not_allowed", "拒绝理由应是相位权限")


func test_player_cannot_act_on_sleeping_target() -> void:
	# P1-02：目标在睡觉时不能交互（§10.8）。
	var core := _core()
	var sleeping: Array = core._sleeping
	sleeping[0] = true
	core._sleeping = sleeping

	var result: Dictionary = core.player_action("chat", 0)
	assert_false(result["ok"], "目标在睡觉 → 不能交互")
	assert_eq(str(result["error"]), "target_unavailable")


func test_unknown_kind_is_rejected_before_anything_else() -> void:
	# 玩家入口目前只接了 behaviors.csv 里的七项；未接的行为（如安慰 / 求助 / 道歉）应
	# 明确报 unknown_kind，而不是静默执行成别的东西（审查报告 §3 的缺失项）。
	var core := _core()
	var result: Dictionary = core.player_action("comfort", 0)
	assert_false(result["ok"])
	assert_eq(str(result["error"]), "unknown_kind")


func test_invalid_target_is_rejected() -> void:
	var core := _core()
	var me := _last(core)
	assert_eq(str(core.player_action("chat", me)["error"]), "invalid_target", "不能对自己发起")
	assert_eq(str(core.player_action("chat", -1)["error"]), "invalid_target", "越界索引被拒")
