extends Control
## Office portrait and controls only read command snapshots; actions are emitted to OfficeHub.

signal action_requested(action: String)
signal voice_hold_started(action: String)
signal voice_hold_ended(action: String)

const FONTS := preload("res://scripts/ui/game_fonts.gd")

@onready var _clip: Control = $Clip
@onready var _portrait: TextureRect = $Clip/Portrait
@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Rows/Title
@onready var _status: Label = $Panel/Rows/Status
@onready var _cancel: Button = $Panel/Rows/Cancel
@onready var _scroll: ScrollContainer = $Panel/Rows/Scroll

var _config: Dictionary
var _buttons: Dictionary = {}
var _identity := -1
var _sprites: Dictionary
var _appearance: Dictionary = {}
var _voice_meter: Control
var _voice_live_active := false
var _voice_live_intensity := 0.0
var _voice_live_tier := 2


func setup(view: Control) -> void:
	_config = view.config.meeting
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(_clip, _config.clip_rect)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = true
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_set_rect(_portrait, _config.portrait_rect)
	_set_rect(_panel, _config.panel_rect)
	_panel.add_theme_stylebox_override("panel", view.paper_style())
	var rows := _panel.get_node("Rows") as VBoxContainer
	rows.add_theme_constant_override("separation", int(view.config.gap))
	for label in [_title, _status]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font", FONTS.regular())
		label.add_theme_color_override("font_color", Color(view.config.ink))
		label.add_theme_font_size_override("font_size", int(_config.font_size))
	_status.custom_minimum_size.y = float(_config.status_height)
	_voice_meter = preload("res://scripts/ui/voice_meter.gd").new()
	rows.add_child(_voice_meter)
	rows.move_child(_voice_meter, _title.get_index() + 1)
	_voice_meter.setup(
		_config,
		FONTS.regular(),
		Color(view.config.ink),
		Color(view.config.paper),
		Color(view.config.accent)
	)
	_cancel.text = _config.cancel_chat
	view.style_button(_cancel)
	_cancel.custom_minimum_size.y = float(_config.button_height)
	_cancel.add_theme_font_size_override("font_size", int(_config.small_size))
	_cancel.visible = false
	_cancel.pressed.connect(func() -> void: action_requested.emit("cancel_chat"))
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var actions := _scroll.get_node("Actions") as VBoxContainer
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", int(view.config.gap))
	for key in ["comfort", "praise", "scold", "send_back", "ask", "encourage"]:
		var button := actions.get_node(_button_name(key)) as Button
		button.text = _config.send_back_label if key == "send_back" else _config[key]
		view.style_button(button)
		button.custom_minimum_size.y = float(_config.button_height)
		button.add_theme_font_size_override("font_size", int(_config.small_size))
		button.add_theme_color_override(
			"font_disabled_color", Color(view.config.ink).lerp(Color(view.config.paper), 0.45)
		)
		button.pressed.connect(func() -> void: action_requested.emit(key))
		button.button_down.connect(func() -> void: voice_hold_started.emit(key))
		button.button_up.connect(func() -> void: voice_hold_ended.emit(key))
		if key in ["comfort", "praise", "scold", "encourage"]:
			button.set_meta("emit_hold", true)
		_buttons[key] = button
		if key == "encourage":
			button.tooltip_text = _config.pending
	_sprites = (
		JSON
		. parse_string(FileAccess.get_file_as_string("res://data/ui/student_poses.json"))
		. bindings
	)
	for row in ConfigLoader.new().get_table("characters/appearance").get("rows", []):
		_appearance[str(row.id)] = str(row.sprite)
	_portrait.hide()
	refresh(null, {})


func _button_name(key: String) -> String:
	return "SendBack" if key == "send_back" else key.capitalize()


func refresh(core: Variant, snapshot: Dictionary) -> void:
	var called := int(snapshot.get("called", -1))
	var command := str(snapshot.get("command", ""))
	var held := bool(snapshot.get("held_by_class", false))
	_panel.visible = called >= 0 or not command.is_empty()
	var arrived := called >= 0 and command not in ["summon", "send_back"] and not held
	_portrait.visible = arrived
	if arrived:
		show_student(core, called)
	_title.text = _config.empty if called < 0 else _config.student % str(core.alias(called))
	_status.text = status_text(snapshot)
	if called >= 0:
		_status.text += (
			"\n"
			+ (
				_config.metrics
				% [core.stress(called), core.vitality(called), core.gain_today(called)]
			)
		)
	for key in _buttons:
		_buttons[key].disabled = not arrived or command != ""
	_update_voice_meter(core, snapshot)
	_cancel.visible = command == "office_chat"


func status_text(snapshot: Dictionary) -> String:
	if (
		bool(snapshot.get("held_by_class", false))
		and (
			int(snapshot.get("called", -1)) >= 0 or not str(snapshot.get("command", "")).is_empty()
		)
	):
		return str(_config.held)
	var command := str(snapshot.get("command", ""))
	if not command.is_empty():
		var label := str(_config.get(command, command))
		if command == "office_chat":
			label = str(_config.get("%s_status" % str(snapshot.get("chat_kind", "")), label))
		return label
	return str(_config.waiting if int(snapshot.get("called", -1)) >= 0 else _config.idle_status)


func show_student(core: Variant, index: int) -> void:
	if index == _identity:
		return
	var sprite := str(_appearance.get(str(core.character_id(index)), ""))
	_portrait.texture = load(str(_sprites[sprite].idle)) as Texture2D
	_identity = index


## 办公室 hub 每帧写入实时强度/档位；无窗口时 active=false。
func set_voice_live(active: bool, intensity: float, tier: int) -> void:
	_voice_live_active = active
	_voice_live_intensity = intensity
	_voice_live_tier = tier


func _update_voice_meter(core: Variant, snapshot: Dictionary) -> void:
	var state := voice_state(core, snapshot)
	_voice_meter.set_state(
		bool(state.get("active", false)),
		int(state.get("tier", 2)),
		float(state.get("intensity", 0.0)),
		str(state.get("preview", "")),
		str(state.get("warning", ""))
	)


## 声量条完整展示状态；演出弹窗复用同一份数据，避免两处口径漂移。
## active=false 时其余字段无意义（弹窗据此隐藏声量条）。
func voice_state(core: Variant, snapshot: Dictionary) -> Dictionary:
	var enabled := false
	var settings := get_node_or_null("/root/VoiceSettings")
	if settings != null:
		enabled = bool(settings.is_enabled())
	var kind := str(snapshot.get("chat_kind", ""))
	var active := (
		enabled
		and str(snapshot.get("command", "")) == "office_chat"
		and kind in ["comfort", "praise", "scold", "encourage"]
		and not bool(snapshot.get("held_by_class", false))
	)
	if not active:
		return {}
	var called := int(snapshot.get("called", -1))
	if called < 0:
		return {}
	var tier := _voice_live_tier if _voice_live_active else int(snapshot.get("chat_tier", 2))
	var effect: Dictionary = core.teacher_commands().voice_effect(kind, tier)
	var tiers: Array = _config.get("voice_tiers", ["轻声", "平常", "提高", "吼"])
	var tier_name := str(tiers[clampi(tier, 1, 4) - 1]) if tiers.size() >= 4 else str(tier)
	var preview := ""
	var warning := ""
	if kind == "encourage":
		var target_key := "voice_encourage_affinity"
		if tier <= 1:
			target_key = "voice_encourage_neighbors"
		elif tier == 2:
			target_key = "voice_encourage_nearest"
		preview = (
			str(_config.get("voice_encourage", "%s · %s → 目标：%s"))
			% [
				str(_config.get("encourage", "鼓励")),
				tier_name,
				str(_config.get(target_key, "最近")),
			]
		)
	elif kind == "praise":
		# 表扬只加动力，不涉及压力与崩溃预警。
		preview = (
			str(_config.get("voice_praise", "%s · %s → 动力 %+.0f"))
			% [
				str(_config.get("praise", "表扬")),
				tier_name,
				float(effect.get("vitality", 0.0)),
			]
		)
	else:
		preview = (
			str(_config.get("voice_preview", "%s · %s → 压力 %+.0f · 动力 %+.0f"))
			% [
				str(_config.get(kind, kind)),
				tier_name,
				float(effect.get("stress", 0.0)),
				float(effect.get("vitality", 0.0)),
			]
		)
		var stress_now := float(core.stress(called))
		var after := stress_now + float(effect.get("stress", 0.0))
		if core.is_broken(called):
			warning = str(_config.get("voice_broken", "已崩溃"))
		elif after > 90.0:
			warning = str(_config.get("voice_breakdown", "预计压力 %.0f · 会崩溃")) % after
		else:
			warning = str(_config.get("voice_safe", "预计压力 %.0f · 安全")) % after
	return {
		"active": true,
		"tier": tier,
		"intensity": _voice_live_intensity if _voice_live_active else 0.0,
		"preview": preview,
		"warning": warning,
	}


func meeting_visible() -> bool:
	return _portrait.visible


func meeting_texture() -> Texture2D:
	return _portrait.texture


func fit_background(
	view_size: Vector2, design_scale: float, design_origin: Vector2, design_size: Vector2
) -> void:
	# Match the background's COVERED scaling on wide mobile displays; controls keep their existing layout.
	var cover := maxf(view_size.x / design_size.x, view_size.y / design_size.y)
	_clip.scale = Vector2.ONE * cover / design_scale
	_clip.position = ((view_size - design_size * cover) * 0.5 - design_origin) / design_scale


func _set_rect(node: Control, values: Array) -> void:
	node.position = Vector2(values[0], values[1])
	node.size = Vector2(values[2], values[3])
