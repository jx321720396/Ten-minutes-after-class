extends GutTest
## 学习（§8.23）与睡觉（§8.8）的**玩家侧**：自指行为、成绩累积条件、睡眠保护。
##
## 两条关键口径：
##   · 学习改为**主动行为**后，玩家「什么都不做」**不涨成绩**（这是与旧「默认状态」的分界）；
##   · 睡觉与 NPC 同规则：占用剩余课间段、段末一次性减压、期间不被任何人交互。

const NODES := 8


func _core(seed_num: int = 12345) -> SimCore:
	return SimCore.from_npc(seed_num, NODES, ConfigLoader.new().load_all())


func _player(c: SimCore) -> int:
	return int(c.node_count()) - 1


func test_both_are_player_kinds() -> void:
	var c := _core()
	assert_true(SimCore.PLAYER_KINDS.has("study"), "玩家能学习")
	assert_true(SimCore.PLAYER_KINDS.has("sleep"), "玩家能睡觉")
	assert_true(SimCore.PLAYER_SELF_KINDS.has("study"), "学习是自指行为")


func test_study_enters_the_state_without_taking_a_time_slot() -> void:
	var c := _core()
	var me := _player(c)
	var result: Dictionary = c.player_action("study", -1)
	assert_true(bool(result.get("ok", false)), "能开始学习")
	assert_eq(str(c._current_act[me]), "study", "进入学习态")
	assert_eq(int(c._busy_until[me]), 0, "学习不占时间槽（照 §8.23 是持续型）")


func test_player_only_accumulates_grade_while_actively_studying() -> void:
	var c := _core()
	var me := _player(c)
	var before := float(c._grade[me])
	for _i in range(60):
		c._study_accumulate()
	assert_eq(float(c._grade[me]), before, "什么都不做时不涨成绩（主动行为的分界）")
	assert_true(bool(c.player_action("study", -1).get("ok", false)))
	for _i in range(400):
		c._study_accumulate()
	assert_gt(float(c._grade[me]), before, "学习态下成绩会涨")


func test_player_can_sleep_and_becomes_untouchable() -> void:
	var c := _core()
	var me := _player(c)
	assert_true(bool(c.player_action("sleep", -1).get("ok", false)), "能主动睡觉")
	assert_true(bool(c._sleeping[me]), "进入睡眠")
	assert_eq(str(c._current_act[me]), "sleep", "占用表达为 sleep")
	assert_false(bool(c._can_interact_with(me)), "睡着的人不被任何人交互")


func test_self_behavior_refuses_when_the_player_is_busy() -> void:
	var c := _core()
	var me := _player(c)
	c._busy_until[me] = int(c._global_tick) + 30
	var result: Dictionary = c.player_action("study", -1)
	assert_false(bool(result.get("ok", false)), "忙的时候不能开始学习")
	assert_eq(str(result.get("error", "")), "player_busy", "原因要说清")
