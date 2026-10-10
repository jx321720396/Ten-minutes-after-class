extends GutTest
## 头顶行为徽标（§20.1.4 / §21.2.9）：只反映**看得见的公开状态**，不做动画、不给自己推断。
##
## 重点是最后一条**反例测试**：压力高 / 好感高 / 被排挤这类隐藏状态**永远不该得到徽标** ——
## 那是把隐藏状态搬到脸上（§20.0.1 第 2 条）。


func _core(seed_num: int = 12345) -> SimCore:
	return SimCore.from_npc(seed_num, 8, ConfigLoader.new().load_all())


func _presenter(core: Variant = null) -> BehaviorBadgePresenter:
	var presenter := BehaviorBadgePresenter.new()
	add_child_autofree(presenter)
	if core != null:
		presenter.bind_core(core)
	return presenter


## 驱动一帧（引擎每帧会调 `_process`；测试里显式调，保证与帧率无关）。
func _tick(presenter: BehaviorBadgePresenter) -> void:
	presenter._process(1.0 / 60.0)


func test_starts_without_badges() -> void:
	var presenter := _presenter()
	assert_eq(presenter.badge_count(), 0)
	assert_eq(presenter.badge_holders(), [])


func test_note_holder_gets_a_badge() -> void:
	var core := _core()
	var presenter := _presenter(core)
	_tick(presenter)
	assert_eq(presenter.badge_count(), 0, "开局没人拿着纸条")
	core._note_create(0, 1, -1, 0, 2)
	_tick(presenter)
	assert_true(presenter.has_badge(2), "手里拿着纸条的人挂徽标")
	assert_false(presenter.has_badge(0), "写纸条的人不一定拿着")
	assert_eq(presenter.badge_holders(), [2])


func test_player_can_carry_a_badge_too() -> void:
	var core := _core()
	var presenter := _presenter(core)
	var me := int(core.node_count()) - 1
	core._note_create(0, 1, 1, 0, me)
	_tick(presenter)
	assert_true(presenter.has_badge(me), "玩家手里拿着纸条也要看得见（§21.2.9）")


func test_badge_is_removed_when_the_note_leaves_the_hand() -> void:
	var core := _core()
	var presenter := _presenter(core)
	var note_id := core._note_create(0, 1, -1, 0, 2)
	_tick(presenter)
	assert_true(presenter.has_badge(2))
	core._note_destroy(note_id)
	_tick(presenter)
	assert_eq(presenter.badge_count(), 0, "纸条没了徽标就得收")


func test_two_holders_get_two_badges() -> void:
	var core := _core()
	var presenter := _presenter(core)
	core._note_create(0, 1, -1, 0, 2)
	core._note_create(3, 4, 1, 0, 5)
	_tick(presenter)
	assert_eq(presenter.badge_holders(), [2, 5], "两张纸条两个人的徽标")


func test_badge_is_a_slip_of_paper_and_does_not_animate() -> void:
	var core := _core()
	var presenter := _presenter(core)
	core._note_create(0, 1, -1, 0, 2)
	_tick(presenter)
	var badge: Control = presenter._badges[2]
	assert_not_null(badge.get_node_or_null("Paper"), "纸片底")
	assert_not_null(badge.get_node_or_null("Line0"), "第一道线")
	assert_not_null(badge.get_node_or_null("Line1"), "第二道线")
	assert_true(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "徽标不吃鼠标事件")
	assert_eq(badge.find_children("*", "AnimationPlayer", true, false).size(), 0, "徽标不做动画")


func test_hidden_states_never_get_a_badge() -> void:
	var core := _core()
	var presenter := _presenter(core)
	# 把所有人的隐藏状态拉到极端：压力拉满、相互好感拉满、强行制造「被排挤」
	for i in range(int(core.node_count())):
		core._stress[i] = 100.0
		for j in range(int(core.node_count())):
			core._a[i * int(core.node_count()) + j] = 100.0
	_tick(presenter)
	assert_eq(presenter.badge_count(), 0, "隐藏状态不上脸（§20.1.4 反例）")


func test_clear_removes_every_badge() -> void:
	var core := _core()
	var presenter := _presenter(core)
	core._note_create(0, 1, -1, 0, 2)
	_tick(presenter)
	presenter.clear()
	assert_eq(presenter.badge_count(), 0)


func test_unbound_presenter_is_safe() -> void:
	var presenter := _presenter()
	_tick(presenter)
	assert_eq(presenter.badge_count(), 0, "没绑内核时不报错也不乱画")
