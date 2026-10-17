extends GutTest

const AttentionCard := preload("res://scripts/ui/attention_card.gd")
const ClassOverviewCard := preload("res://scripts/ui/class_overview_card.gd")


func test_transition_skip_button_is_touch_bound() -> void:
	var overlay := TransitionOverlay.new()
	add_child_autofree(overlay)
	await wait_process_frames(2)
	var skip := overlay.find_child("SkipButton", true, false) as Button
	assert_not_null(skip, "转场跳过按钮应存在")
	if skip != null:
		assert_true(skip.has_meta(TouchBind.META_BOUND), "转场跳过按钮应接入触摸")


func test_attention_card_buttons_are_touch_bound() -> void:
	var card: Control = AttentionCard.new()
	add_child_autofree(card)
	await wait_process_frames(2)
	var button := card.find_child("RiskDetailsButton", true, false) as Button
	assert_not_null(button, "风险详情按钮应存在")
	if button != null:
		assert_true(button.has_meta(TouchBind.META_BOUND), "风险详情按钮应接入触摸")


func test_class_overview_button_is_touch_bound() -> void:
	var card: Control = ClassOverviewCard.new()
	add_child_autofree(card)
	await wait_process_frames(2)
	var button := card.find_child("OverviewButton", true, false) as Button
	assert_not_null(button, "全班概况按钮应存在")
	if button != null:
		assert_true(button.has_meta(TouchBind.META_BOUND), "全班概况按钮应接入触摸")
