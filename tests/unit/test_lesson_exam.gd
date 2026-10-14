extends GutTest
## 周考（§19.1）。
## 考分噪声必须和 Python exam_quantized_normal 一致，这里只锁门槛和「不改平时成绩」。

const NODES := 8


func _core(seed_num: int = 7) -> SimCore:
	return SimCore.new(seed_num, NODES, ConfigLoader.new().load_all())


func _player(c: SimCore) -> int:
	return int(c.node_count()) - 1


func test_weekly_exam_does_not_rewrite_grade() -> void:
	var c := _core(99)
	var me := _player(c)
	for i in me:
		c._grade[i] = 100.0
	c._grade[me] = 400.0
	c._exam.capture_baseline(c._grade)
	for i in c.node_count():
		c._exam._last_score[i] = 0.0
	assert_false(c._exam.settle(6, c._grade, c._stress, c._alias_list()), "非考试日不考")
	var before := float(c._grade[me])
	assert_true(c._exam.settle(7, c._grade, c._stress, c._alias_list()), "第 7 天周考")
	assert_almost_eq(float(c._grade[me]), before, 0.001, "周考不改平时成绩")
	assert_lte(c._exam.rank_of(me), 3, "高分进前三")
	assert_eq(c._exam.tokens_of(me), 1, "特等奖一张免罚卷")
	var report := c.exam_report(7)
	assert_true(report.contains("前三名"), "简报有名次")
	assert_false(report.contains("100"), "简报不写别人的分数")
