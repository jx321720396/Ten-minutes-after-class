extends GutTest
## 纸条提示框（§21.2.9）：两步决策的文案与按钮，以及「只发意图、不改状态」。
##
## 关键约束：纸条到手**不打断**玩家正在做的事 —— 所以组件只提示、只发意图，
## 真正的结算与时间占用由内核（read_note / finish_note）负责。

const EXPECTED_OFFER := ["不看，传下去", "不看，撕掉", "看看写的什么"]
const EXPECTED_AFTER_READ := ["撕掉", "继续传给别人", "去告诉老师"]


func _prompt() -> NotePrompt:
	var prompt := NotePrompt.new()
	add_child_autofree(prompt)
	return prompt


func test_starts_closed() -> void:
	var p := _prompt()
	assert_false(p.is_open(), "开局不显示")
	assert_eq(p.step(), "idle")


func test_offer_offers_three_choices_without_revealing_anything() -> void:
	var p := _prompt()
	p.show_offer()
	assert_true(p.is_open())
	assert_eq(p.step(), "offer")
	assert_eq(p.body_text(), NotePrompt.TEXT_HINT, "到手提示不暴露写者、也不暴露内容")
	assert_eq(p.button_labels(), EXPECTED_OFFER)


func test_after_read_bad_note() -> void:
	var p := _prompt()
	p.show_after_read(-1)
	assert_eq(p.step(), "after_read")
	assert_eq(p.body_text(), NotePrompt.TEXT_BAD, "坏话只给方向性短句，不给数字")
	assert_eq(p.button_labels(), EXPECTED_AFTER_READ)


func test_after_read_good_note() -> void:
	var p := _prompt()
	p.show_after_read(1)
	assert_eq(p.body_text(), NotePrompt.TEXT_GOOD)


func test_repeated_offer_keeps_the_step() -> void:
	var p := _prompt()
	p.show_offer()
	p.show_offer()
	assert_eq(p.step(), "offer", "重复提示不把玩家已进入的步骤退回")


func test_choice_emits_intent_only() -> void:
	var p := _prompt()
	var seen: Array = []
	p.choice_made.connect(func(action: StringName) -> void: seen.append(action))
	p.show_offer()
	var first := p._buttons.get_child(0) as Button
	first.pressed.emit()
	assert_eq(seen, [&"skip_forward"], "按钮只发意图")
	assert_true(p.is_open(), "组件自己不关 —— 下一步由控制器与内核决定")

	p.show_after_read(-1)
	var report_button := p._buttons.get_child(2) as Button
	report_button.pressed.emit()
	assert_eq(seen, [&"skip_forward", &"report"])


func test_close_resets_state() -> void:
	var p := _prompt()
	p.show_after_read(1)
	p.close()
	assert_false(p.is_open())
	assert_eq(p.step(), "idle")


func test_buttons_are_rebuilt_between_steps() -> void:
	var p := _prompt()
	p.show_offer()
	assert_eq(p._buttons.get_child_count(), 3)
	p.show_after_read(-1)
	assert_eq(p._buttons.get_child_count(), 3, "两步都是三个按钮，旧按钮被清掉")
	assert_eq(p.button_labels(), EXPECTED_AFTER_READ)
