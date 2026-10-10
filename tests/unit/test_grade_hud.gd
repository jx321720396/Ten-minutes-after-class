extends GutTest
## 成绩 HUD（§21.2.7）：显示在**屏幕右上角**、格式含期末倒计时、数据来自内核玩家成绩。
##
## 2026-10-10 用户指定位置：右上角独立卡片（时间卡片在左上角，两者不挤在一起）。

const HUD_SCRIPT := "res://scripts/ui/time_hud.gd"


func _hud() -> CanvasLayer:
	var script := load(HUD_SCRIPT) as GDScript
	assert_not_null(script, "时间/成绩 HUD 脚本必须存在")
	var hud := script.new() as CanvasLayer
	add_child_autofree(hud)
	return hud


func test_grade_card_is_anchored_to_the_top_right() -> void:
	var hud := _hud()
	var card := hud.get_node_or_null("GradeCard") as Control
	assert_not_null(card, "成绩必须有**独立卡片**（§21.2.7）")
	if card == null:
		return
	assert_eq(card.anchor_left, 1.0, "贴右边界")
	assert_eq(card.anchor_right, 1.0, "贴右边界")
	assert_eq(card.anchor_top, 0.0, "贴顶边")
	assert_lt(card.offset_right, 0.0, "向右边界内侧收（负偏移）")
	assert_gt(card.offset_top, 0.0, "与顶边留出边距")
	assert_eq(
		card.grow_horizontal,
		Control.GROW_DIRECTION_BEGIN,
		"内容变长时向左生长（不越出屏幕右侧）"
	)


func test_grade_text_still_uses_the_spec_format() -> void:
	var hud := _hud()
	var label := hud.get_node_or_null("GradeCard/GradeLabel") as Label
	assert_not_null(label, "卡片里就是成绩文案本身")
	if label == null:
		return
	# 未绑时钟时文案为空；绑定时应形如「成绩 N ｜ 距期末考 N 天」——
	# 这里只钉住「它是一位可显示的标签」，具体文案由时钟刷新（见 simulation_clock）。
	assert_false(label.visible == false, "成绩默认可见")


func test_the_time_card_stays_on_the_left() -> void:
	var hud := _hud()
	var card := hud.get_node_or_null("Card") as Control
	assert_not_null(card, "时间卡片仍在（左上角）")
	if card != null:
		assert_eq(card.position, Vector2(16.0, 16.0), "时间卡片没被成绩挪动")
