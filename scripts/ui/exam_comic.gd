extends CanvasLayer
## 考试日漫画，只负责展示；完成后由时钟调用内核已有结算。
const SETTINGS := "res://data/ui/exam_comic.json"
const FONTS := preload("res://scripts/ui/game_fonts.gd")
const HOLD := &"exam_comic"

var _cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
var _clock: SimulationClock
var _root: Control
var _page: Control
var _panels: Array[TextureRect] = []
var _title: Label
var _caption: Label
var _index := 0
var _elapsed := 0.0
var _active := false
var _day := 0
var _tween: Tween


func _ready() -> void:
	layer = int(_cfg.layer)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_input)
	add_child(_root)
	var paper := ColorRect.new()
	paper.color = Color(_cfg.paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(paper)
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_page)
	var texture := load(str(_cfg.image)) as Texture2D
	var design := Vector2(_cfg.design_size[0], _cfg.design_size[1])
	for i in _cfg.captions.size():
		var panel := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		var left := float(_cfg.panel_edges[i])
		var width := float(_cfg.panel_edges[i + 1]) - left
		atlas.region = Rect2(
			left * texture.get_width(), 0, width * texture.get_width(), texture.get_height()
		)
		panel.texture = atlas
		panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		panel.stretch_mode = TextureRect.STRETCH_SCALE
		panel.position = Vector2(design.x * left, 0)
		panel.size = Vector2(design.x * width, design.y)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(panel)
		_panels.append(panel)
	_title = _label(str(_cfg.title), _cfg.title_rect, int(_cfg.font_size))
	_caption = _label("", _cfg.caption_rect, int(_cfg.font_size))
	_label(str(_cfg.hint), _cfg.hint_rect, int(_cfg.hint_font))
	_root.resized.connect(_resize)
	_resize()
	hide()
	set_process(false)


func bind_sources(_core: Variant, clock: SimulationClock) -> void:
	if is_instance_valid(_clock):
		_clock.time_updated.disconnect(_sync)
		_clock.release(HOLD)
	_clock = clock
	_clock.time_updated.connect(_sync)
	_sync(_clock.snapshot())


func _sync(snapshot_data: Dictionary) -> void:
	if _active or not bool(snapshot_data.get("is_exam_day", false)):
		return
	_day = int(snapshot_data.day)
	_active = true
	_index = 0
	_elapsed = 0.0
	_clock.hold(HOLD)
	_title.text = str(_cfg.title) % _day
	for panel in _panels:
		panel.modulate.a = 0.0
	_reveal()
	show()
	set_process(true)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	while _active and _elapsed >= float(_cfg.panel_seconds):
		_elapsed -= float(_cfg.panel_seconds)
		advance()


func advance() -> void:
	if not _active:
		return
	_index += 1
	if _index >= _panels.size():
		_finish()
	else:
		_reveal()


func _reveal() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _index > 0:
		_panels[_index - 1].modulate.a = 1.0
	_caption.text = str(_cfg.captions[_index])
	_tween = create_tween()
	_tween.tween_property(_panels[_index], "modulate:a", 1.0, float(_cfg.fade_seconds))


func _finish() -> void:
	# 先结算并打开成绩页，再移除遮罩；_active 阻止同步信号重入。
	set_process(false)
	_clock.complete_exam_day()
	_clock.release(HOLD)
	_active = false
	hide()


func _exit_tree() -> void:
	if is_instance_valid(_clock):
		_clock.release(HOLD)


func _resize() -> void:
	var design := Vector2(_cfg.design_size[0], _cfg.design_size[1])
	var factor := minf(_root.size.x / design.x, _root.size.y / design.y)
	_page.scale = Vector2.ONE * factor
	_page.position = (_root.size - design * factor) / 2.0


func _label(text: String, rect: Array, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(rect[0], rect[1])
	label.size = Vector2(rect[2], rect[3])
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONTS.regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(_cfg.ink))
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(_cfg.paper)
	label.add_theme_stylebox_override("normal", paper)
	_page.add_child(label)
	return label


func _on_input(event: InputEvent) -> void:
	var touch: bool = event is InputEventScreenTouch and not event.pressed
	var mouse: bool = (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and event.device != InputEvent.DEVICE_ID_EMULATION
	)
	if _active and (touch or mouse):
		_elapsed = 0.0
		advance()
		_root.accept_event()


func _input(event: InputEvent) -> void:
	if _active and event.is_action_pressed("ui_accept") and not event.is_echo():
		_elapsed = 0.0
		advance()
		get_viewport().set_input_as_handled()
