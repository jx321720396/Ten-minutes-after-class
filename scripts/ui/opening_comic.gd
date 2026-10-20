extends CanvasLayer
## 老师版开场漫画；只管理展示与时钟 hold，不写模拟状态。

signal finished

const CONFIG := "res://data/ui/opening_comic.json"
const SEEN := "user://teacher_opening_comic_v1.dat"
const STATE := preload("res://scripts/ui/opening_comic_state.gd")
const PANEL := preload("res://scripts/ui/opening_comic_panel.gd")
const FONTS := preload("res://scripts/ui/game_fonts.gd")

var seen_path := SEEN
var state := STATE.new()
var _cfg: Dictionary
var _clock: SimulationClock
var _root: Control
var _page: Control
var _panels: Array[Control] = []
var _tweens: Array[Tween] = []
var _hint: Label
var _title: Label
var _shown := 0
var _page_index := -1
var _closed := false


static func is_seen() -> bool:
	return FileAccess.file_exists(SEEN)


func _ready() -> void:
	layer = 46
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	_build()
	get_viewport().size_changed.connect(_resize)
	_resize()
	set_process(false)
	visible = false


func start(clock: SimulationClock) -> void:
	_clock = clock
	_closed = false
	_page_index = -1
	if _clock != null:
		_clock.hold(&"opening_comic")
	state.start(_cfg.pages.size(), _cfg.polygons.size(), float(_cfg.reveal_seconds))
	visible = true
	set_process(true)
	_sync()


func advance() -> void:
	if _closed:
		return
	state.tap()
	_sync()


func skip() -> void:
	state.skip()
	_close()


func _process(delta: float) -> void:
	state.advance_time(delta)
	_sync()


func _sync() -> void:
	if state.finished:
		_close()
		return
	if _page_index != state.page:
		_show_page()
	while _shown < state.revealed:
		_reveal(_shown)
		_shown += 1
	var key := "reveal_hint" if state.revealed < _panels.size() else "next_hint"
	if state.page == _cfg.pages.size() - 1 and state.revealed == _panels.size():
		key = "finish_hint"
	_hint.text = str(_cfg.copy[key])


func _show_page() -> void:
	for tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()
	for panel in _panels:
		panel.free()
	_panels.clear()
	_shown = 0
	_page_index = state.page
	var entry: Dictionary = _cfg.pages[state.page]
	_title.text = "%02d / %s" % [state.page + 1, entry.title]
	var texture := load(str(entry.image)) as Texture2D
	var polygons: Array = entry.get("polygons", _cfg.polygons)
	for i in polygons.size():
		var panel := PANEL.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.texture = texture
		for point in polygons[i]:
			var normalized := Vector2(float(point[0]), float(point[1]))
			panel.uv.append(normalized)
			panel.vertices.append(normalized * _design_size())
		panel.modulate.a = 0.0
		_page.add_child(panel)
		_panels.append(panel)


func _reveal(index: int) -> void:
	var panel := _panels[index]
	panel.position.x = float(_cfg.slide_pixels) * (-1.0 if index % 2 == 0 else 1.0)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, float(_cfg.animation_seconds))
	tween.tween_property(panel, "position:x", 0.0, float(_cfg.animation_seconds))
	_tweens.append(tween)
	SFX.play_one_shot("BookFlip")


func _close() -> void:
	if _closed:
		return
	_closed = true
	visible = false
	set_process(false)
	if _clock != null and is_instance_valid(_clock):
		_clock.release(&"opening_comic")
	var file := FileAccess.open(seen_path, FileAccess.WRITE)
	if file != null:
		file.store_string("seen")
	finished.emit()


func _exit_tree() -> void:
	if _clock != null and is_instance_valid(_clock):
		_clock.release(&"opening_comic")


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.gui_input.connect(_on_page_input)
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(_cfg.paper)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_page)
	_title = _label(_page, "", _cfg.title_rect, int(_cfg.title_font))
	_title.hide()
	_hint = _label(_page, "", _cfg.hint_rect, int(_cfg.hint_font))
	_hint.hide()
	# 页面插画后来加入，标题、操作提示始终位于最上层。
	_title.z_index = 2
	_hint.z_index = 2


func _label(parent: Node, text: String, rect: Array, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONTS.regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(_cfg.ink))
	if parent == _page:
		var paper := StyleBoxFlat.new()
		paper.bg_color = Color(_cfg.bubble)
		paper.set_corner_radius_all(int(_cfg.bubble_radius))
		paper.content_margin_left = float(_cfg.padding)
		paper.content_margin_right = float(_cfg.padding)
		label.add_theme_stylebox_override("normal", paper)
	if not rect.is_empty():
		label.position = Vector2(rect[0], rect[1])
		label.size = Vector2(rect[2], rect[3])
	parent.add_child(label)
	return label


func _design_size() -> Vector2:
	return Vector2(_cfg.design_size[0], _cfg.design_size[1])


func _resize() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var design := _design_size()
	var ratio := minf(viewport.x / design.x, viewport.y / design.y)
	_page.scale = Vector2.ONE * ratio
	_page.position = (viewport - design * ratio) * 0.5


func _on_page_input(event: InputEvent) -> void:
	var touch: bool = event is InputEventScreenTouch and not event.pressed
	var mouse: bool = (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and event.device != InputEvent.DEVICE_ID_EMULATION
	)
	if touch or mouse:
		advance()
		_root.accept_event()


func _input(event: InputEvent) -> void:
	if not visible or _closed:
		return
	if event.is_action_pressed("ui_cancel"):
		# 本页在 _input 阶段消费 ESC（早于 SFX 的全局判定），返回音须自己播。
		SFX.play_cancel()
		skip()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		advance()
		get_viewport().set_input_as_handled()
