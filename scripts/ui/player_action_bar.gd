class_name PlayerActionBar

extends CanvasLayer
## 右侧常驻行为栏（§20.1.2，2026-10-10 定稿）：**先选行为、再点对象**。
##
## 依据：主文档 §10.2（三组分类）、§20.1.2（两步交互 + 三态不隐藏）。
##
## 交互（两步）：
##   ① 点一个行为按钮 → 该按钮选中（高亮），底部提示「现在点一个人」
##   ② 点一个人物 → 选对象；需要接近的行为先走过去，到位后自动结算
##
## 三条约束：
##   ① **点人物不再弹卡片** —— 点人只表示「选对象」，目标信息显示在本栏底部；
##   ② **三态都不隐藏按钮**：可用（正常）｜暂时不可用（橙色 + 原因）｜还没做（灰色 + 占位说明）——
##      隐藏会让玩家以为功能不存在（§20.1.2）；
##   ③ 本栏**只发意图、不改世界**：真正的裁决仍在内核（`player_action`）。
##
## 「对自己做的事」点按钮直接执行（不需要选对象）—— 已接通的项由内核决定可用状态。

signal behavior_armed(kind: StringName)
signal self_behavior_requested(kind: StringName)
signal cancel_requested
## 「看资料」：打开被选中同学的档案页（旧底部卡片的能力，不能因为换形态丢掉）
signal profile_requested(index: int)

## 公开活动的中文名（内核 activity_of 的返回值 → 玩家看得懂的说法）
const ACTIVITY_NAMES := {
	"chat": "正在闲聊",
	"pass_note": "正在传纸条",
	"tease": "正在起哄",
	"comfort": "正在安慰人",
	"apologize": "在道歉",
	"roughhouse": "在打闹",
	"exclude": "在排挤人",
	"report": "去了老师那儿",
	"move": "走动中",
	"sleep": "睡着了",
	"study": "在学习",
	"listen_music": "在听音乐",
	"eat_snack": "在吃零食",
	"read_book": "在看课外书",
	"leave_class": "你出去了",
}

const GameFonts := preload("res://scripts/ui/game_fonts.gd")
const BACKPACK_SCENE := preload("res://scenes/ui/backpack_panel.tscn")
const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const STYLE_TABLE := "ui/chat_feedback_style"
const COLOR_PAPER := Color(0.98, 0.96, 0.90, 0.94)
const COLOR_INK := Color(0.13, 0.16, 0.14)
const COLOR_SUB := Color(0.34, 0.38, 0.35)
const COLOR_ACCENT := Color(0.16, 0.38, 0.26)
const COLOR_LOCKED := Color(0.62, 0.34, 0.22)
const COLOR_PLACEHOLDER := Color(0.55, 0.55, 0.52)

## 行为栏内容：[kind, 分组, 显示名, 是否自指]
##   - 需要选对象的（target 组）：闲聊（含加入）/ 递纸条 / 举报 / 追逐打闹 / 排挤
##   - 对自己做的事（self）：观察 / 学习 / 睡觉 / 听音乐 / 吃零食 / 看课外书 / 出门
## 分组只用于排布与标题（§10.2 的三组口径），不改变任何判定。
const ROWS := [
	[&"chat", "talk", "闲聊", false],
	[&"ask_question", "talk", "提问", false],
	[&"teach_lesson", "talk", "讲题", false],
	[&"pass_note", "do", "递纸条", false],
	[&"report", "do", "举报", false],
	[&"roughhouse", "do", "追逐打闹", false],
	[&"exclude", "do", "排挤", false],
	# 观察属「不接触」类（§10.2.3），但它**需要点一个对象**（最后一列 false = 不是纯自指）
	[&"observe", "self", "观察", false],
	[&"study", "self", "学习", true],
	[&"sleep", "self", "睡觉", true],
	[&"listen_music", "self", "听音乐", true],
	[&"eat_snack", "self", "吃零食", true],
	[&"read_book", "self", "看课外书", true],
	[&"leave_class", "self", "出门", true],
]
const GROUP_TITLES := {"talk": "开口说话", "do": "动手做事", "self": "对自己做的事"}
## 占位原因（本批未实装的行为）
const PLACEHOLDER_REASON := "还没做"

const TOUCH_SCROLL_DEADZONE := 12.0

var backpack: CanvasLayer
var _panel: PanelContainer = null
var _rows_box: VBoxContainer = null
var _inventory_label: Label = null
var _target_label: Label = null
var _profile_button: Button = null
var _target_portrait: TextureRect
var _target_index := -1
var _button_of: Dictionary = {}
var _armed := StringName("")
var _width := 168.0
var _margin := 18.0

var _behavior_scroll: ScrollContainer = null
var _touch_scroll_active := false
var _touch_scroll_last := Vector2.ZERO
var _touch_scroll_distance := 0.0


func _ready() -> void:
	_load_style()
	_build_ui()
	CampusTheme.apply_tree(self)
	for child in _rows_box.get_children():
		if child is PanelContainer:
			var category_style := CampusTheme.box("teal", "teal")
			category_style.shadow_size = 0
			child.add_theme_stylebox_override("panel", category_style)
	_apply_paper_style()
	_update_highlight()
	_build_backpack()
	get_viewport().size_changed.connect(_layout_for_viewport)
	_layout_for_viewport()


func _layout_for_viewport() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var viewport := get_viewport().get_visible_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return
	var cfg := CampusTheme.settings()
	var margin := minf(_margin, maxf(8.0, viewport.x * 0.02))
	var width := minf(float(cfg.action_width), maxf(176.0, viewport.x * 0.30))
	var available_height := maxf(1.0, viewport.y - margin * 2.0)
	var height := minf(
		float(cfg.action_panel_height), maxf(minf(420.0, available_height), available_height)
	)
	_panel.custom_minimum_size = Vector2(width, height)
	_panel.size = Vector2(width, height)
	_panel.offset_left = -width - margin
	_panel.offset_right = -margin
	_panel.offset_top = minf(float(cfg.action_panel_top), margin)
	_panel.offset_bottom = _panel.offset_top + height


func _input(event: InputEvent) -> void:
	if _behavior_scroll == null or not is_visible() or not _panel.visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index != 0:
			return
		if touch.pressed and _behavior_scroll.get_global_rect().has_point(touch.position):
			_touch_scroll_active = true
			_touch_scroll_last = touch.position
			_touch_scroll_distance = 0.0
		elif not touch.pressed:
			_touch_scroll_active = false
			_touch_scroll_last = Vector2.ZERO
			_touch_scroll_distance = 0.0
		return
	if event is InputEventScreenDrag and _touch_scroll_active:
		var drag := event as InputEventScreenDrag
		var delta_y := drag.position.y - _touch_scroll_last.y
		_touch_scroll_last = drag.position
		_touch_scroll_distance += absf(delta_y)
		if _touch_scroll_distance >= TOUCH_SCROLL_DEADZONE:
			_behavior_scroll.scroll_vertical = clampi(
				_behavior_scroll.scroll_vertical - int(delta_y),
				0,
				int(_behavior_scroll.get_v_scroll_bar().max_value)
			)
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ 对外接口
## 刷新整栏：`states` 是 kind -> {"ok": bool, "reason": String}；`self_labels` 可覆盖自指项文案。
## 未给出的 kind 视为「占位」（灰置 + `还没做`）。
func refresh(states: Dictionary) -> void:
	if backpack != null:
		backpack.refresh(states)
	for kind in _button_of.keys():
		var button: Button = _button_of[kind]
		var state: Dictionary = states.get(kind, {})
		if state.is_empty():
			button.disabled = true
			button.tooltip_text = PLACEHOLDER_REASON
			button.add_theme_color_override("font_color", COLOR_PLACEHOLDER)
			continue
		if state.has("label"):
			button.set_meta("action_name", str(state["label"]))
			var title: Label = button.get_node("Content/Layout/Words/Name")
			title.text = str(state["label"])
		var ok := bool(state.get("ok", false))
		button.disabled = not ok
		button.tooltip_text = "" if ok else str(state.get("reason", ""))
		button.add_theme_color_override("font_color", COLOR_INK if ok else COLOR_LOCKED)
	if _inventory_label != null:
		var snack_label := str(states.get(&"eat_snack", {}).get("label", "吃零食（0）"))
		_inventory_label.text = (
			"持有物：%s · 课外书 %d"
			% [snack_label.replace("吃", ""), int(states.get(&"read_book", {}).get("books", 0))]
		)
		var books: Dictionary = states.get(&"read_book", {})
		var confiscated := int(books.get("confiscated_books", 0))
		var tokens := int(books.get("exemption_tokens", 0))
		if confiscated > 0:
			_inventory_label.text += " · 老师保管 %d 本（暂不能取回）" % confiscated
		if tokens > 0:
			_inventory_label.text += " · 免罚卷 %d" % tokens
	_update_highlight()


## 按钮点击：切换选中并通知控制器（再次点同一个 = 取消）。
func arm(kind: StringName) -> void:
	_armed = StringName("") if _armed == kind else kind
	_update_highlight()
	if _armed != StringName(""):
		behavior_armed.emit(_armed)


## 控制器驱动的选中（只改高亮，不反向通知 —— 避免与 `behavior_armed` 形成回路）。
func set_armed(kind: StringName) -> void:
	_armed = kind
	_update_highlight()


func armed_kind() -> StringName:
	return _armed


func clear_armed() -> void:
	if _armed == StringName(""):
		return
	_armed = StringName("")
	_update_highlight()


## 底部信息行：没选行为时给提示；选了行为后显示目标或等待提示。
func show_target(
	index: int, name_text: String, activity: String, portrait: Texture2D = null
) -> void:
	_target_portrait.texture = portrait
	_target_portrait.visible = true
	_target_index = index
	_target_label.text = (
		"%s · %s" % [name_text, str(ACTIVITY_NAMES.get(activity, activity))]
		if name_text != ""
		else _idle_hint()
	)
	if _profile_button != null:
		_profile_button.disabled = name_text == ""


func show_hint(text: String) -> void:
	_target_portrait.texture = null
	_target_label.text = text
	if _profile_button != null:
		_profile_button.disabled = true


func target_text() -> String:
	return _target_label.text


## 测试与调试：某个 kind 的按钮文案 / 是否灰置。
func button_text_of(kind: StringName) -> String:
	var button: Button = _button_of.get(kind, null)
	return "" if button == null else str(button.get_meta("action_name", button.text))


func button_disabled_of(kind: StringName) -> bool:
	var button: Button = _button_of.get(kind, null)
	return true if button == null else button.disabled


func button_count() -> int:
	return _button_of.size()


# ------------------------------------------------------------------ 内部
func _idle_hint() -> String:
	if _armed == StringName(""):
		return "先在右边点一个动作"
	return "现在点一个人"


func _update_highlight() -> void:
	for kind in _button_of.keys():
		var button: Button = _button_of[kind]
		var selected: bool = kind == _armed
		CampusTheme.button(button, selected)
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			var row_style := button.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
			row_style.shadow_size = 0
			row_style.set_content_margin_all(8)
			button.add_theme_stylebox_override(state_name, row_style)
		if button.disabled and button.tooltip_text != PLACEHOLDER_REASON:
			button.add_theme_stylebox_override(
				"disabled", CampusTheme.box("warning_fill", "warning")
			)
		button.add_theme_color_override(
			"font_color",
			(
				Color(CampusTheme.settings().paper)
				if selected
				else (COLOR_PLACEHOLDER if button.disabled else COLOR_INK)
			)
		)
		var description := str(CampusTheme.settings().action_descriptions.get(str(kind), ""))
		if button.disabled:
			description = "未开放" if button.tooltip_text == PLACEHOLDER_REASON else "暂不可用"
		button.text = ""
		var name_label: Label = button.get_node("Content/Layout/Words/Name")
		var detail_label: Label = button.get_node("Content/Layout/Words/Description")
		var ink := Color(CampusTheme.settings().paper) if selected else COLOR_INK
		if button.disabled:
			ink = COLOR_PLACEHOLDER if button.tooltip_text == PLACEHOLDER_REASON else COLOR_LOCKED
		name_label.add_theme_color_override("font_color", ink)
		detail_label.add_theme_color_override(
			"font_color", ink if selected or button.disabled else COLOR_SUB
		)
		detail_label.text = description
		button.add_theme_color_override(
			"font_disabled_color",
			COLOR_PLACEHOLDER if button.tooltip_text == PLACEHOLDER_REASON else COLOR_LOCKED
		)
	if _target_index < 0:
		_target_label.text = _idle_hint()


func _on_pressed(kind: StringName, self_only: bool) -> void:
	var button: Button = _button_of[kind]
	if button.disabled:
		return
	if self_only:
		if kind in [&"eat_snack", &"read_book", &"listen_music"]:
			open_backpack(kind)
			return
		self_behavior_requested.emit(kind)
		return
	arm(kind)


func open_backpack(kind: StringName = &"eat_snack") -> void:
	clear_armed()
	cancel_requested.emit()
	_panel.hide()
	backpack.open_item(kind)


func _build_backpack() -> void:
	backpack = BACKPACK_SCENE.instantiate()
	add_child(backpack)
	backpack.action_requested.connect(
		func(kind: StringName) -> void: self_behavior_requested.emit(kind)
	)
	backpack.closed.connect(func() -> void: _panel.show())
	var entry := CanvasLayer.new()
	entry.name = "BackpackEntry"
	entry.layer = int(CampusTheme.settings().utility_style.layer)
	add_child(entry)
	var launch := Button.new()
	launch.name = "BackpackButton"
	backpack.bind_touch(launch)
	launch.text = "书包"
	entry.add_child(launch)
	CampusTheme.utility_button(launch, 2)
	launch.pressed.connect(_toggle_backpack)


func _toggle_backpack() -> void:
	if backpack.is_open():
		backpack.close()
	else:
		open_backpack()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ActionBar"
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PAPER
	box.border_color = COLOR_ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10.0)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.custom_minimum_size = Vector2(_width, 0.0)
	# 右侧常驻：贴右边、垂直居中偏上（不挡讲台与黑板）
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -_width - _margin
	_panel.offset_right = -_margin
	_panel.offset_top = _margin * 3.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 4)
	var padding := MarginContainer.new()
	padding.name = "Padding"
	for edge in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override(
			"margin_" + edge, int(CampusTheme.settings()["action_content_" + edge])
		)
	_panel.add_child(padding)
	padding.add_child(column)
	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.add_theme_constant_override("separation", int(CampusTheme.settings().action_row_gap))
	_behavior_scroll = ScrollContainer.new()
	_behavior_scroll.name = "BehaviorScroll"
	_behavior_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_behavior_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_behavior_scroll)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_behavior_scroll.add_child(_rows_box)
	var heading := Label.new()
	heading.text = "行动"
	heading.add_theme_font_override("font", _font())
	heading.add_theme_font_size_override("font_size", int(CampusTheme.settings().action_title_size))
	heading.add_theme_color_override("font_color", Color(CampusTheme.settings().teal))
	column.add_child(heading)
	column.move_child(heading, 0)
	var last_group := ""
	for row in ROWS:
		var kind := StringName(row[0])
		var group := str(row[1])
		if group != last_group:
			var title := Label.new()
			title.name = "Group_" + group
			title.text = str(GROUP_TITLES.get(group, group))
			title.add_theme_font_size_override(
				"font_size", int(CampusTheme.settings().action_group_size)
			)
			title.add_theme_color_override("font_color", COLOR_SUB)
			title.add_theme_font_override("font", _font())
			var category := PanelContainer.new()
			category.name = "Category_" + group
			category.custom_minimum_size.y = CampusTheme.settings().action_group_height
			category.add_theme_stylebox_override("panel", CampusTheme.box("teal", "teal"))
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_color_override("font_color", Color(CampusTheme.settings().paper))
			category.add_child(title)
			_rows_box.add_child(category)
			last_group = group
		var button := Button.new()
		button.name = "Act_" + str(kind)
		button.set_meta("action_name", str(row[2]))
		button.custom_minimum_size.y = CampusTheme.settings().action_row_height
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_build_action_contents(button, kind, str(row[2]))
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", _font())
		button.pressed.connect(_on_pressed.bind(kind, bool(row[3])))
		_rows_box.add_child(button)
		_button_of[kind] = button
	_inventory_label = Label.new()
	_inventory_label.name = "InventoryLine"
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_label.add_theme_font_size_override("font_size", 12)
	_inventory_label.add_theme_color_override("font_color", COLOR_SUB)
	_inventory_label.add_theme_font_override("font", _font())
	column.add_child(_inventory_label)
	var target_heading := Label.new()
	target_heading.text = "当前对象"
	target_heading.add_theme_font_size_override(
		"font_size", int(CampusTheme.settings().action_target_heading_size)
	)
	target_heading.add_theme_color_override("font_color", Color(CampusTheme.settings().teal))
	target_heading.add_theme_font_override("font", _font())
	column.add_child(HSeparator.new())
	column.add_child(target_heading)
	_target_label = Label.new()
	_target_label.name = "TargetLine"
	_target_label.text = _idle_hint()
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_label.add_theme_font_size_override(
		"font_size", int(CampusTheme.settings().action_target_font_size)
	)
	_target_label.add_theme_color_override("font_color", COLOR_SUB)
	_target_label.add_theme_font_override("font", _font())
	var target_row := HBoxContainer.new()
	target_row.name = "TargetRow"
	target_row.add_theme_constant_override(
		"separation", int(CampusTheme.settings().action_row_padding)
	)
	column.add_child(target_row)
	_target_portrait = TextureRect.new()
	_target_portrait.name = "Portrait"
	_target_portrait.custom_minimum_size = Vector2.ONE * CampusTheme.settings().action_portrait_size
	_target_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_target_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	target_row.add_child(_target_portrait)
	_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(_target_label)
	_profile_button = Button.new()
	_profile_button.name = "ProfileButton"
	_profile_button.text = "查看资料"
	_profile_button.add_theme_font_size_override(
		"font_size", int(CampusTheme.settings().action_profile_font_size)
	)
	_profile_button.focus_mode = Control.FOCUS_NONE
	_profile_button.disabled = true
	_profile_button.add_theme_font_override("font", _font())
	_profile_button.pressed.connect(func() -> void: profile_requested.emit(_target_index))
	column.add_child(_profile_button)


func _font() -> Font:
	var font := GameFonts.regular()

	return font


func _load_style() -> void:
	for row in ConfigLoader.new().get_table(STYLE_TABLE).get("rows", []):
		var value := float(str(row.get("value", "0")))
		match str(row.get("param", "")):
			"menu_width_px":
				_width = value
			"menu_margin_px":
				_margin = value


func _apply_paper_style() -> void:
	var cfg := CampusTheme.settings()
	var paper := StyleBoxTexture.new()
	paper.texture = load("res://assets/textures/ui/paper/campus-action-paper-v1.png")
	paper.content_margin_top = 0
	paper.content_margin_bottom = 0
	paper.content_margin_left = 0
	paper.content_margin_right = 0
	_panel.add_theme_stylebox_override("panel", paper)
	_panel.custom_minimum_size = Vector2(cfg.action_width, cfg.action_panel_height)
	_panel.size = _panel.custom_minimum_size
	_panel.offset_top = cfg.action_panel_top
	_panel.offset_bottom = cfg.action_panel_top + cfg.action_panel_height
	_panel.offset_left = -cfg.action_width - _margin
	_panel.offset_right = -_margin


func _build_action_contents(button: Button, kind: StringName, label: String) -> void:
	var cfg := CampusTheme.settings()
	var inset := MarginContainer.new()
	inset.name = "Content"
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inset)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + edge, int(cfg.action_row_padding))
	var layout := HBoxContainer.new()
	layout.name = "Layout"
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", int(cfg.action_row_padding))
	inset.add_child(layout)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(cfg.action_icon_size, cfg.action_icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_path := "res://assets/icons/actions/%s.svg" % kind
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	layout.add_child(icon)
	var words := VBoxContainer.new()
	words.name = "Words"
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(words)
	for entry in [
		["Name", label, cfg.action_name_size],
		["Description", cfg.action_descriptions.get(str(kind), ""), cfg.action_description_size]
	]:
		var text := Label.new()
		text.name = entry[0]
		text.text = entry[1]
		if entry[0] == "Name":
			var heading_font := GameFonts.regular()

			text.add_theme_font_override("font", heading_font)
		else:
			text.add_theme_font_override("font", _font())
		text.add_theme_font_size_override("font_size", int(entry[2]))
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(text)
