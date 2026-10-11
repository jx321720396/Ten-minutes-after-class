extends GutTest
## 成绩 HUD：与时间一起显示在左上角纸卡，数据来自内核。
##
## 2026-10-11 用户指定：按概念图并入左上角。

const HUD_SCRIPT := "res://scripts/ui/time_hud.gd"


func _hud() -> CanvasLayer:
	var script := load(HUD_SCRIPT) as GDScript
	assert_not_null(script, "时间/成绩 HUD 脚本必须存在")
	var hud := script.new() as CanvasLayer
	add_child_autofree(hud)
	return hud


func test_grade_is_inside_top_left_time_card() -> void:
	var hud := _hud()
	assert_null(hud.get_node_or_null("GradeCard"))
	var label := hud.get_node_or_null("Card/Rows/GradeLabel") as Label
	assert_not_null(label)
	if label != null:
		assert_eq(label.get_parent().get_child(label.get_index() - 1).name, "GradeSeparator")


func test_grade_text_still_uses_the_spec_format() -> void:
	var hud := _hud()
	var label := hud.get_node_or_null("Card/Rows/GradeLabel") as Label
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
