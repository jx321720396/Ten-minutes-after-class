extends GutTest
## 座位范围（§8.23）：范围 = **该座位的桌椅占位矩形**（由表现层从 `NavBlocker` 注入）。
##
## 三条口径：
##   · 未注入时不拦行为（离线 / 无场景）；
##   · 落在自己那张桌椅的占位矩形内 = 「在自己的座位上」；
##   · 离座时学习被明确拒绝并给原因；睡觉不受此限。

const NODES := 8
## 测试用的占位矩形半边长（对应场景里桌椅的尺度）
const HALF := 0.5


func _core(seed_num: int = 12345) -> SimCore:
	return SimCore.from_npc(seed_num, NODES, ConfigLoader.new().load_all())


func _player(c: SimCore) -> int:
	return int(c.node_count()) - 1


## 给玩家注入一个以他当前位置为中心的占位矩形
func _pin(c: SimCore) -> int:
	var me := _player(c)
	c.set_seat_zones({me: Rect2(c._pos_x[me] - HALF, c._pos_z[me] - HALF, HALF * 2.0, HALF * 2.0)})
	return me


func test_without_injection_the_zone_is_permissive() -> void:
	var c := _core()
	assert_true(c.in_own_seat(0), "没注入占位矩形时不拦行为")


func test_inside_the_desk_rect_counts_as_on_seat() -> void:
	var c := _core()
	var me := _pin(c)
	assert_true(c.in_own_seat(me), "站在自己那张桌椅的范围内 = 在座位上")


func test_outside_the_desk_rect_counts_as_away() -> void:
	var c := _core()
	var me := _pin(c)
	c._pos_x[me] += 5.0
	assert_false(c.in_own_seat(me), "走出桌椅范围就不算在自己的座位上")


func test_the_zone_is_a_rect_not_a_circle() -> void:
	var c := _core()
	var me := _pin(c)
	# 角落方向 (0.45, 0.45)：直线距离 0.64 > 0.5，但两轴都在半边长内 —— 矩形内、圆外
	c._pos_x[me] += 0.45
	c._pos_z[me] += 0.45
	assert_true(c.in_own_seat(me), "范围是桌椅的占位矩形，不是圆")


func test_study_is_refused_away_from_your_seat() -> void:
	var c := _core()
	var me := _pin(c)
	c._pos_x[me] += 5.0
	var result: Dictionary = c.player_action("study", -1)
	assert_false(bool(result.get("ok", false)), "离座不能开始学习")
	assert_eq(str(result.get("error", "")), "not_in_seat", "原因要说清（§8.23）")


func test_study_works_back_on_your_seat() -> void:
	var c := _core()
	var me := _pin(c)
	assert_true(bool(c.player_action("study", -1).get("ok", false)), "回到座位就能学")
	assert_eq(str(c._current_act[me]), "study")


func test_sleep_does_not_require_the_seat() -> void:
	var c := _core()
	var me := _pin(c)
	c._pos_x[me] += 5.0
	assert_true(bool(c.player_action("sleep", -1).get("ok", false)), "睡觉不受座位范围限制（§8.8）")
