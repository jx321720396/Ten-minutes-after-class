extends GutTest


func test_scroll_keeps_target_and_profile_fixed() -> void:
	var bar := PlayerActionBar.new()
	add_child_autofree(bar)
	await wait_frames(3)
	var panel: PanelContainer = bar.get_node("ActionBar")
	var scroll: ScrollContainer = panel.get_node("Padding/Column/BehaviorScroll")
	var profile: Button = panel.get_node("Padding/Column/ProfileButton")
	var target: Label = panel.get_node("Padding/Column/TargetRow/TargetLine")
	var footer_y := profile.global_position.y
	var target_y := target.global_position.y
	assert_gt(scroll.get_v_scroll_bar().max_value, scroll.size.y)
	assert_eq(bar.button_count(), 14)
	assert_eq(bar.button_text_of(&"ask_question"), "提问")
	assert_eq(bar.button_text_of(&"teach_lesson"), "讲题")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await wait_frames(3)
	assert_eq(profile.global_position.y, footer_y)
	assert_eq(target.global_position.y, target_y)
	assert_lte(
		panel.size.y,
		float(preload("res://scripts/ui/campus_theme.gd").settings().action_panel_height)
	)


func test_target_portrait_updates_and_clears():
	var bar := PlayerActionBar.new()
	add_child_autofree(bar)
	var texture := GradientTexture2D.new()
	bar.show_target(1, "同学", "闲聊", texture)
	var portrait: TextureRect = bar.get_node("ActionBar/Padding/Column/TargetRow/Portrait")
	assert_eq(portrait.texture, texture)
	bar.show_hint("请选择对象")
	assert_null(portrait.texture)
