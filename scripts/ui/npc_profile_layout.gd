extends RefCounted
## 原生容器模板；文本与尺寸来自档案配置，保留触摸滚动。

const STYLE = preload("res://scripts/ui/npc_profile_theme.gd")
const SCROLL = preload("res://scripts/ui/touch_scroll_container.gd")


static func build(view: Node, config: Dictionary) -> void:
	var frame: Panel = view.get_node("%Frame")
	var margin := MarginContainer.new()
	frame.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, int(config.layout.margin))
	var content := column(margin)
	var header := row(content)
	label(view, header, "Title", "同学档案", 52)
	var subtitle := label(view, header, "Subtitle", "了解状态，记录关系。", 26)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(view, header, "Previous", "‹", 64)
	label(view, header, "RosterCount", "", 26)
	button(view, header, "Next", "›", 64)
	button(view, header, "Close", "×", 64)
	content.add_child(HSeparator.new())
	var body := row(content)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var identity := column(body)
	identity.custom_minimum_size.x = float(config.layout.sidebar_width)
	var portrait_frame := card(view, identity, "PortraitFrame")
	var art := Control.new()
	art.custom_minimum_size.y = float(config.portrait_art_height)
	portrait_frame.add_child(art)
	var portrait := TextureRect.new()
	add(view, art, portrait, "Portrait")
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var missing := label(view, art, "MissingPortrait", "暂无画像", 26)
	missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label(view, identity, "PersonName", "", 44).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(view, identity, "Seat", "", 24).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var activity := column(card(view, identity, "ActivityCard"))
	label(view, activity, "Activity", "当前活动：—", 26)
	var passive := column(card(view, identity, "PassiveCard"))
	label(view, passive, "PassiveHeading", "公开被动", 30)
	label(view, passive, "Passive", "—\n暂无公开被动记录", 25)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	identity.add_child(spacer)
	button(view, identity, "Chat", "叫来办公室", 64)
	body.add_child(VSeparator.new())
	var details := column(body)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var metrics := row(details)
	for metric in config.metrics:
		var panel := card(view, metrics, str(metric.node) + "Card")
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size.y = float(config.layout.metric_height)
		var values := column(panel)
		label(view, values, str(metric.node) + "Heading", str(metric.label), 28)
		label(view, values, str(metric.node) + "Value", "—", 48)
		if str(metric.node) in ["Pressure", "Motivation"]:
			var bar := ProgressBar.new()
			add(view, values, bar, str(metric.node) + "Bar")
			bar.show_percentage = false
			bar.max_value = float(config.state_max)
			bar.custom_minimum_size.y = 12
			bar.add_theme_stylebox_override(
				"background", STYLE.box(Color("e7e0c9"), Color.TRANSPARENT, 6, 0)
			)
			bar.add_theme_stylebox_override(
				"fill",
				STYLE.box(
					STYLE.GOLD if str(metric.node) == "Pressure" else STYLE.INK,
					Color.TRANSPARENT,
					6,
					0
				)
			)
	label(view, details, "Settlement", "今日收益次日结算，当前成绩不含未结算收益。", 22)
	var tabs := row(details)
	button(view, tabs, "RelationsTab", "人际关系", 52).toggle_mode = true
	button(view, tabs, "StatusTab", "状态与记录", 52).toggle_mode = true
	var relations := column(details)
	add_name(view, relations, "RelationsPage")
	relations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rel := column(card(view, relations, "RelationCard"))
	var selector := row(rel)
	label(view, selector, "KnownTitle", "人际关系", 32).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(view, selector, "TargetHeading", "关系对象", 24)
	var targets := OptionButton.new()
	add(view, selector, targets, "Targets")
	targets.custom_minimum_size = Vector2(220, 54)
	targets.fit_to_longest_item = false
	var direction := row(rel)
	label(view, direction, "RelationTitle", "", 30).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(view, direction, "Reverse", "查看反向 ⇄", 50)
	var axes := row(rel)
	for axis in ["Affinity", "Hostility"]:
		var cells := column(card(view, axes, axis + "Panel"))
		cells.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label(view, cells, axis + "Heading", "好感" if axis == "Affinity" else "敌对", 30)
		var value := label(view, cells, axis + "Value", "未判断", 28)
		value.visible = false
		label(view, cells, axis + "Time", "未判断", 22)
		var choices := row(cells)
		choices.add_theme_constant_override("separation", 6)
		for band in config.judgment_bands:
			var choice := button(
				view, choices, axis + str(band).to_pascal_case(), view.words(str(band)), 56
			)
			choice.toggle_mode = true
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choice.add_theme_font_size_override("font_size", 23)
	label(view, rel, "StaleNote", "已获知为当时记录，不会实时更新；未判断不等于中立。", 22)
	var bottom := row(relations)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var history := column(card(view, bottom, "HistoryCard"))
	history.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.get_parent().size_flags_stretch_ratio = 1.4
	label(view, history, "HistoryTitle", "最近记录", 30)
	var history_scroll := scroll(view, history, "HistoryScroll")
	var history_rows := column(history_scroll)
	history_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_name(view, history_rows, "HistoryRows")
	var goal := column(card(view, bottom, "GoalCard"))
	goal.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(view, goal, "GoalHeading", "交流目标", 30)
	label(view, goal, "Goal", "—\n暂无交流目标记录", 26)
	var status_scroll := scroll(view, details, "StatusPage")
	status_scroll.hide()
	var status := column(status_scroll)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(view, status, "StatusHeading", "状态与记录", 32)
	label(view, status, "StatusDetails", "", 26)
	var footer := row(content)
	label(view, footer, "Footer", "未判断不等于中立 · Esc 返回", 22).size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	button(view, footer, "OpenBoard", "推理板", 56)
	button(view, footer, "OpenEncyclopedia", "百科全书", 56)
	var picker := Control.new()
	add(view, view.get_node("%Design"), picker, "TargetPicker")
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	picker.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.10, 0.08, 0.5)
	var center := CenterContainer.new()
	picker.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var picker_panel := card(view, center, "TargetPickerCard")
	picker_panel.custom_minimum_size.x = float(config.target_picker.width)
	picker_panel.add_theme_stylebox_override("panel", STYLE.box(STYLE.PAPER, STYLE.INK, 12, 2))
	var picker_content := column(picker_panel)
	var picker_header := row(picker_content)
	label(view, picker_header, "PickerTitle", "选择关系对象", 32).size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	button(view, picker_header, "ClosePicker", "×", 56)
	var grid := GridContainer.new()
	picker_content.add_child(grid)
	grid.columns = int(config.target_picker.columns)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for index in range(int(config.target_picker.capacity)):
		var slot := button(
			view, grid, "TargetSlot%d" % index, "", int(config.target_picker.button_height)
		)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.hide()


static func add(view: Node, parent: Node, node: Node, key: String) -> void:
	parent.add_child(node)
	add_name(view, node, key)


static func add_name(view: Node, node: Node, key: String) -> void:
	node.name = key
	node.owner = view
	node.unique_name_in_owner = true


static func column(parent: Node) -> VBoxContainer:
	var node := VBoxContainer.new()
	parent.add_child(node)
	node.add_theme_constant_override("separation", 14)
	return node


static func row(parent: Node) -> HBoxContainer:
	var node := HBoxContainer.new()
	parent.add_child(node)
	node.add_theme_constant_override("separation", 18)
	return node


static func label(view: Node, parent: Node, key: String, text: String, size: int) -> Label:
	var node := Label.new()
	add(view, parent, node, key)
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
		if (
			key
			in ["Subtitle", "Settlement", "StaleNote", "Passive", "Goal", "StatusDetails", "Footer"]
		)
		else TextServer.AUTOWRAP_OFF
	)
	return node


static func button(view: Node, parent: Node, key: String, text: String, height: int) -> Button:
	var node := Button.new()
	add(view, parent, node, key)
	node.text = text
	node.custom_minimum_size = Vector2(64, height)
	return node


static func card(view: Node, parent: Node, key: String) -> PanelContainer:
	var node := PanelContainer.new()
	add(view, parent, node, key)
	node.add_theme_stylebox_override(
		"panel", STYLE.box(Color(1, 0.98, 0.91, 0.4), STYLE.LINE, 12, 1)
	)
	return node


static func scroll(view: Node, parent: Node, key: String) -> ScrollContainer:
	var node := ScrollContainer.new()
	add(view, parent, node, key)
	node.set_script(SCROLL)
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return node
