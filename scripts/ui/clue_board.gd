extends Control
## 所有界面节点预置于 clue_board.tscn；这里只绑定数据和更新表现。

signal close_requested
signal day_requested(day: int)
signal person_selected(index: int)

const PORTRAITS = preload("res://scripts/ui/student_portraits.gd")
const SETTINGS = preload("res://scripts/ui/clue_board_settings.gd")
const DASH = preload("res://assets/textures/ui/clue_board/pencil-dash.svg")
var config: Dictionary = SETTINGS.read()
var _page: Dictionary = {}
var _core: Variant
var _actors: Node
var _event_offset := 0
var _filter_person := -1
var _positions: Dictionary = {}
var _pairs: Array = []
var _selected_pair := ""
var _selected_entry: Dictionary = {}
var _focused_students: Array = []
var _latest_day := 1
var _touches: Dictionary = {}
var _profile_config: Dictionary = {}


func _ready() -> void:
	_profile_config = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/npc_profile.json")
	)
	%Close.pressed.connect(func() -> void: close_requested.emit())
	%Done.pressed.connect(func() -> void: close_requested.emit())
	%PreviousDay.pressed.connect(func() -> void: day_requested.emit(int(_page.day) - 1))
	%NextDay.pressed.connect(func() -> void: day_requested.emit(int(_page.day) + 1))
	%PreviousEvent.pressed.connect(_step_events.bind(-1))
	%NextEvent.pressed.connect(_step_events.bind(1))
	%ShowAll.pressed.connect(_show_all)
	for slot in range($Design/Graph/Cards.get_child_count()):
		$Design/Graph/Cards.get_child(slot).pressed.connect(_select_person.bind(slot))
		$Design/Roster.get_child(slot).pressed.connect(_select_person.bind(slot))
	for slot in range($Design/Events.get_child_count()):
		$Design/Events.get_child(slot).pressed.connect(_select_event.bind(slot))
	_bind_touch(self)
	get_viewport().size_changed.connect(_fit)
	_fit()


func show_page(page: Dictionary, core: Variant, actors: Node, latest_day: int) -> void:
	_page = page.duplicate(true)
	_core = core
	_actors = actors
	_latest_day = latest_day
	_event_offset = 0
	_filter_person = -1
	_selected_pair = ""
	_selected_entry = {}
	_focused_students = []
	%Date.text = "第 %d 天 · %s" % [int(page.day), "放学记录" if page.get("sealed", false) else "今日记录"]
	%PreviousDay.disabled = int(page.day) <= 1
	%NextDay.disabled = int(page.day) >= latest_day
	%Summary.text = (
		"%d 位学生 · %d 条互动 · %d 条关系标注｜每天独立整理，往日记录不混入今天"
		% [page.people.size(), page.events.size(), page.judgments.size()]
	)
	%Detail.text = "点击人物或事件，查看当天的观察依据。"
	_render_cards()
	_build_pairs()
	_render_edges()
	_render_events()


func displayed_page() -> Dictionary:
	return _page.duplicate(true)


func _render_cards() -> void:
	_positions.clear()
	%Empty.visible = _page.people.is_empty()
	var center := Vector2(float(config.graph_center[0]), float(config.graph_center[1]))
	var radius := Vector2(float(config.graph_radius[0]), float(config.graph_radius[1]))
	var card_size := Vector2(float(config.card_size[0]), float(config.card_size[1]))
	for slot in range($Design/Graph/Cards.get_child_count()):
		var card: Button = $Design/Graph/Cards.get_child(slot)
		var roster: Button = $Design/Roster.get_child(slot)
		card.visible = slot < _page.people.size()
		roster.visible = card.visible
		if not card.visible:
			continue
		var index := int(_page.people[slot])
		var angle: float = (
			deg_to_rad(float(config.graph_start_angle)) + TAU * slot / _page.people.size()
		)
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		var dense: bool = _page.people.size() > int(config.grid_threshold)
		var actual_size := card_size
		if dense:
			point = Vector2(
				(
					float(config.grid_origin[0])
					+ (slot % int(config.grid_columns)) * float(config.grid_step[0])
				),
				(
					float(config.grid_origin[1])
					+ (slot / int(config.grid_columns)) * float(config.grid_step[1])
				)
			)
			actual_size = Vector2(float(config.grid_card_size[0]), float(config.grid_card_size[1]))
		if _page.people.size() == 1:
			point = center
		_positions[index] = point
		card.size = actual_size
		card.position = point - actual_size / 2.0
		var portrait: TextureRect = card.get_node("Portrait")
		portrait.size.y = float(config.grid_portrait_height) if dense else 127.0
		card.get_node("Initial").size.y = portrait.size.y
		card.get_node("Name").position.y = float(config.grid_name_top) if dense else 138.0
		card.modulate.a = 1.0
		var person_name := _name(index)
		card.get_node("Name").text = person_name
		roster.text = person_name
		roster.size = Vector2(80, 72) if dense else Vector2(160, 68)
		roster.position = (
			Vector2((slot % 2) * 80, (slot / 2) * 78) if dense else Vector2(0, slot * 78)
		)
		roster.add_theme_font_size_override("font_size", 22 if dense else 26)
		card.get_node("Portrait").texture = _portrait(index)
		card.get_node("Initial").visible = card.get_node("Portrait").texture == null
		card.get_node("Initial").text = person_name.left(1)
		card.tooltip_text = "查看 %s 的当天记录" % person_name


func _build_pairs() -> void:
	_pairs.clear()
	var pairs := {}
	for event in _page.events:
		_add_pair(pairs, int(event.i), int(event.j), event, false)
	for entry in _page.judgments:
		_add_pair(pairs, int(entry.source), int(entry.subject), entry, true)
	_pairs = pairs.values()


func _add_pair(pairs: Dictionary, a: int, b: int, entry: Dictionary, judgment: bool) -> void:
	var key := _pair_key(a, b)
	if not pairs.has(key):
		pairs[key] = {"key": key, "a": mini(a, b), "b": maxi(a, b), "events": [], "judgments": []}
	pairs[key]["judgments" if judgment else "events"].append(entry)


func _render_edges() -> void:
	for slot in range($Design/Graph/Edges.get_child_count()):
		var edge: Node2D = $Design/Graph/Edges.get_child(slot)
		edge.visible = slot < _pairs.size()
		if not edge.visible:
			continue
		var pair: Dictionary = _pairs[slot]
		var chosen := str(pair.key) == _selected_pair
		var line: Line2D = edge.get_node("Line")
		var color_key := "event"
		if pair.events.is_empty():
			color_key = "known" if pair.judgments[0].get("origin", "guess") == "known" else "guess"
		if chosen and _selected_entry.has("axis"):
			color_key = "known" if _selected_entry.get("origin", "guess") == "known" else "guess"
		var color := Color(
			str(
				(
					config.colors.selected
					if chosen and not _selected_entry.has("axis")
					else config.colors[color_key]
				)
			)
		)
		line.default_color = color
		var focused: bool = _focused_students.has(int(pair.a)) or _focused_students.has(int(pair.b))
		edge.modulate.a = (
			1.0
			if _pairs.size() <= int(config.dense_link_limit) or chosen or focused
			else float(config.dense_link_opacity)
		)
		line.width = float(config.edge_width) * (2.0 if chosen else 1.0)
		line.texture = DASH if color_key == "guess" else null
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		var from: Vector2 = _positions[pair.a]
		var to: Vector2 = _positions[pair.b]
		var direction := (to - from).normalized()
		var inset := minf(float(config.edge_inset), from.distance_to(to) * 0.45)
		from += direction * inset
		to -= direction * inset
		var control := (from + to) / 2.0 + direction.orthogonal() * float(config.edge_bend)
		var points := PackedVector2Array()
		for sample in range(int(config.edge_samples) + 1):
			var t := float(sample) / float(config.edge_samples)
			points.append(from.bezier_interpolate(control, control, to, t))
		line.points = points
		var caption: Label = edge.get_node("Caption")
		caption.visible = chosen
		caption.position = control - caption.size / 2.0
		caption.text = _pair_caption(pair)
		caption.add_theme_color_override("font_color", color)
		var arrow: Polygon2D = edge.get_node("Arrow")
		arrow.visible = chosen and _selected_entry.has("axis")
		if arrow.visible:
			var forward := int(_selected_entry.source) == int(pair.a)
			arrow.position = to if forward else from
			arrow.rotation = direction.angle() if forward else (-direction).angle()
			arrow.color = color
			var length := float(config.arrow_size)
			arrow.polygon = PackedVector2Array(
				[Vector2.ZERO, Vector2(-length, -length / 2), Vector2(-length, length / 2)]
			)


func _pair_caption(pair: Dictionary) -> String:
	if _selected_entry.has("axis"):
		return (
			"%s → %s\n%s · %s"
			% [
				_name(int(_selected_entry.source)),
				_name(int(_selected_entry.subject)),
				config.axes[_selected_entry.axis],
				"已获知" if _selected_entry.get("origin", "guess") == "known" else "老师推测"
			]
		)
	if not pair.events.is_empty():
		return str(config.public_events[pair.events[0].kind]) + " · 观察记录"
	return "关系标注 · 点击人物查看方向与依据"


func _render_events() -> void:
	var entries := _entries()
	var capacity := int(config.event_page_size)
	for slot in range($Design/Events.get_child_count()):
		var button: Button = $Design/Events.get_child(slot)
		var index := _event_offset + slot
		button.visible = index < entries.size()
		if button.visible:
			var entry: Dictionary = entries[index]
			button.text = _entry_title(entry)
			button.tooltip_text = _entry_detail(entry)
	%PreviousEvent.disabled = _event_offset <= 0
	%NextEvent.disabled = _event_offset + capacity >= entries.size()
	%EventCount.text = (
		"%d / %d 页"
		% [_event_offset / capacity + 1, maxi(1, ceili(float(entries.size()) / capacity))]
	)


func _entries() -> Array:
	var entries: Array = _page.get("events", []) + _page.get("judgments", [])
	if _filter_person < 0:
		return entries
	return entries.filter(
		func(entry: Dictionary) -> bool:
			return (
				_filter_person
				in [
					int(entry.get("source", entry.get("i", -1))),
					int(entry.get("subject", entry.get("j", -1)))
				]
			)
	)


func _entry_title(entry: Dictionary) -> String:
	if entry.has("axis"):
		return (
			"%s → %s\n%s · %s"
			% [
				_name(int(entry.source)),
				_name(int(entry.subject)),
				config.axes[entry.axis],
				"已获知" if entry.get("origin", "guess") == "known" else "老师推测"
			]
		)
	return (
		"%s · %s\n%s、%s"
		% [
			config.public_events[entry.kind],
			"未接受" if not bool(entry.accepted) else "观察记录",
			_name(int(entry.i)),
			_name(int(entry.j))
		]
	)


func _entry_detail(entry: Dictionary) -> String:
	if entry.has("axis"):
		var value := str(config.bands.get(str(entry.get("band", "")), entry.get("value", "未判断")))
		var origin := "已获知消息" if entry.get("origin", "guess") == "known" else "老师推测，尚未验证"
		return (
			"%s → %s｜%s：%s｜%s\n来源：%s · 第 %d 天 %s"
			% [
				_name(int(entry.source)),
				_name(int(entry.subject)),
				config.axes[entry.axis],
				value,
				origin,
				str(entry.get("speaker", entry.get("provider", "同学档案记录"))),
				int(entry.day),
				config.phase_names.get(str(entry.get("phase_id", "")), "")
			]
		)
	return (
		"%s、%s：%s%s。只记录观察到的事件，不据此确认友谊或敌对。\n第 %d 天 %s"
		% [
			_name(int(entry.i)),
			_name(int(entry.j)),
			config.public_events[entry.kind],
			"（未接受）" if not bool(entry.accepted) else "",
			int(entry.day),
			config.phase_names.get(str(entry.get("phase_id", "")), "")
		]
	)


func _select_event(slot: int) -> void:
	var entry: Dictionary = _entries()[_event_offset + slot]
	_selected_entry = entry
	var a := int(entry.get("source", entry.get("i", -1)))
	var b := int(entry.get("subject", entry.get("j", -1)))
	_selected_pair = _pair_key(a, b)
	%Detail.text = _entry_detail(entry)
	_render_edges()
	_highlight([a, b])


func _select_person(slot: int) -> void:
	var index := int(_page.people[slot])
	person_selected.emit(index)
	_filter_person = index
	_event_offset = 0
	_selected_pair = ""
	_selected_entry = {}
	_render_events()
	var descriptions: Array[String] = []
	for entry in _entries():
		if (
			index
			in [
				int(entry.get("source", entry.get("i", -1))),
				int(entry.get("subject", entry.get("j", -1)))
			]
		):
			descriptions.append(_entry_title(entry).replace("\n", " · "))
	%Detail.text = (
		"%s｜当天相关记录 %d 条，右侧已筛选。\n%s"
		% [
			_name(index),
			descriptions.size(),
			"；".join(descriptions.slice(0, int(config.detail_preview_entries)))
		]
	)
	%Detail.tooltip_text = %Detail.text
	_highlight([index])


func _highlight(indices: Array) -> void:
	_focused_students = indices
	_render_edges()
	for slot in range(_page.people.size()):
		var card: Button = $Design/Graph/Cards.get_child(slot)
		card.modulate.a = 1.0 if indices.has(int(_page.people[slot])) else 0.5


func _show_all() -> void:
	_filter_person = -1
	_event_offset = 0
	_selected_pair = ""
	_selected_entry = {}
	_focused_students.clear()
	_render_events()
	_render_edges()
	for card in $Design/Graph/Cards.get_children():
		card.modulate.a = 1.0
	%Detail.text = "点击人物或事件，查看当天的观察依据。"


func _step_events(direction: int) -> void:
	_event_offset += direction * int(config.event_page_size)
	_render_events()


func _name(index: int) -> String:
	return str(_core.alias(index)) if _core != null else "学生 %d" % (index + 1)


func _portrait(index: int) -> Texture2D:
	if _core == null:
		return null
	return PORTRAITS.texture_for(str(_core.character_id(index)), _profile_config)


func _pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func _fit() -> void:
	var base := Vector2(float(config.design_size[0]), float(config.design_size[1]))
	var view := get_viewport_rect().size
	var factor := minf(view.x / base.x, view.y / base.y)
	%Design.scale = Vector2.ONE * factor
	%Design.position = (view - base * factor) / 2.0


func _bind_touch(node: Node) -> void:
	if node is Button and not node.has_meta(TouchBind.META_BOUND):
		node.set_meta(TouchBind.META_BOUND, true)
		node.gui_input.connect(_touch_button.bind(node))
	for child in node.get_children():
		_bind_touch(child)


func _touch_button(event: InputEvent, button: Button) -> void:
	if Input.emulate_mouse_from_touch:
		return
	if event is InputEventScreenTouch:
		if event.pressed and not button.disabled:
			_touches[button] = {"index": event.index, "point": event.position}
		elif not event.pressed and _touches.has(button):
			var press: Dictionary = _touches[button]
			_touches.erase(button)
			if event.index == press.index and not event.canceled and not button.disabled:
				if Rect2(Vector2.ZERO, button.size).has_point(event.position):
					button.pressed.emit()
		button.accept_event()
	elif event is InputEventScreenDrag and _touches.has(button):
		if event.position.distance_to(_touches[button].point) > float(config.touch_deadzone):
			_touches.erase(button)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_touches.clear()
