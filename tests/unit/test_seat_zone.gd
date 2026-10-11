extends GutTest
## 座位范围（§8.23 / §20.1.1）：只有**在自己座位范围内**才能做需要座位的行为（如学习）。
##
## 三条口径：
##   · 未注入座位坐标时**保守放行**（离线 / 无场景不该卡住行为）；
##   · 站在自己座位上算「在范围内」，走远就不算；
##   · 离座时学习被明确拒绝，并给出原因（不静默失败）。

const NODES := 8


func _core(seed_num: int = 12345) -> SimCore:
	return SimCore.from_npc(seed_num, NODES, ConfigLoader.new().load_all())


func _player(c: SimCore) -> int:
	return int(c.node_count()) - 1


func _pin_to_own_seat(c: SimCore) -> int:
	var me := _player(c)
	c.set_seat_zones({me: Vector2(c._pos_x[me], c._pos_z[me])})
	return me


func test_without_injection_the_zone_is_permissive() -> void:
	var c := _core()
	assert_true(c.in_own_seat(0), "没注入座位坐标时不拦行为")


func test_standing_on_your_seat_counts_as_in_zone() -> void:
	var c := _core()
	var me := _pin_to_own_seat(c)
	assert_true(c.in_own_seat(me), "站在自己座位上 = 在范围内")


func test_walking_away_leaves_the_zone() -> void:
	var c := _core()
	var me := _pin_to_own_seat(c)
	c._pos_x[me] += 5.0
	assert_false(c.in_own_seat(me), "走出范围就不算在自己的座位上")


func test_study_is_refused_away_from_your_seat() -> void:
	var c := _core()
	var me := _pin_to_own_seat(c)
	c._pos_x[me] += 5.0
	var result: Dictionary = c.player_action("study", -1)
	assert_false(bool(result.get("ok", false)), "离座不能开始学习")
	assert_eq(str(result.get("error", "")), "not_in_seat", "原因要说清（§8.23）")


func test_study_works_back_on_your_seat() -> void:
	var c := _core()
	var me := _pin_to_own_seat(c)
	var result: Dictionary = c.player_action("study", -1)
	assert_true(bool(result.get("ok", false)), "回到座位就能学")
	assert_eq(str(c._current_act[me]), "study")


func test_sleep_does_not_require_the_seat() -> void:
	var c := _core()
	var me := _pin_to_own_seat(c)
	c._pos_x[me] += 5.0
	assert_true(
		bool(c.player_action("sleep", -1).get("ok", false)), "睡觉不受座位范围限制（§8.8）"
	)

func test_the_zone_is_a_square_not_a_circle() -> void:
	var c := _core()
	var me := _pin_to_own_seat(c)
	# 对角方向偏移 (0.45, 0.45)：直线距离 0.64 > 0.5 但两个轴都 ≤ 0.5
	# —— 圆会判「不在」，方会判「在」（与地面格线对齐）
	c._pos_x[me] += 0.45
	c._pos_z[me] += 0.45
	assert_true(c.in_own_seat(me), "范围是按格子的方块，不是圆")
