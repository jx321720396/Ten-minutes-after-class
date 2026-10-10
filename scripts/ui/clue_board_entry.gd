extends CanvasLayer
## 教室里的「黑板」入口（表现层）
##
## 位置：百科全书按钮正下方，样式与它同一套纸感按钮。
## 点开后黑板像弹窗盖住教室，教室压上一层半透明的黑，并把游戏暂停；
## 左上角「退出」或 Esc 关掉。
## 关掉只是藏起来，粉笔和放下的头像都留着。
## 清掉内容只有两处：本局学期结束，或玩家新开一局（新教室场景本身就是空板）。

const SCENE_BOARD := preload("res://scenes/game/clue_board_1.tscn")

const FONT_FAMILIES: Array[String] = [
	"Microsoft YaHei",
	"微软雅黑",
	"SimHei",
	"Noto Sans CJK SC",
	"PingFang SC",
	"sans-serif",
]
const COLOR_PAPER := Color(0.98, 0.96, 0.90, 0.92)
const COLOR_INK := Color(0.12, 0.16, 0.14)
const COLOR_ACCENT := Color(0.16, 0.38, 0.26)
## 百科全书按钮在 (16, 152)、高 38；这里隔 8px 排在它下面。
const BUTTON_POS := Vector2(16.0, 198.0)
const BUTTON_SIZE := Vector2(140.0, 38.0)
## 弹出后黑板略小于画面，四周露出变暗的教室。
const POP_FROM := 0.84
const POP_SCALE := 0.92
## 教室上的黑幕：够黑，又还透得见教室。
const SHADE_ALPHA := 0.75
const POP_TIME := 0.18

var _board: Control
var _shade: ColorRect
var _pop: Tween
var _paused_by_board := false
var _font_cache: Font


func _ready() -> void:
	layer = 3  # 盖过时间 HUD / 百科（层 2），仍在转场黑幕（层 10）下面
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_button()
	_shade = ColorRect.new()
	_shade.name = "Shade"
	_shade.color = Color(0, 0, 0, 0)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.visible = false
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board = SCENE_BOARD.instantiate()
	_board.visible = false
	_board.process_mode = Node.PROCESS_MODE_ALWAYS
	_board.close_requested.connect(_close)
	add_child(_board)


func is_open() -> bool:
	return _board != null and _board.visible


func open() -> void:
	_open()


func close() -> void:
	_close()


## 学期结束时由教室接上。参数是时钟信号带来的结束日，这里用不到。
func clear_board(_ended_day: int = 0) -> void:
	if _board != null and _board.has_method("clear_contents"):
		_board.clear_contents()


func _build_button() -> void:
	var btn := Button.new()
	btn.name = "BoardButton"
	btn.text = "黑板"
	btn.position = BUTTON_POS
	btn.size = BUTTON_SIZE
	btn.custom_minimum_size = BUTTON_SIZE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", _ui_font())
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COLOR_INK)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT)
	btn.add_theme_stylebox_override("normal", _button_style())
	btn.add_theme_stylebox_override("hover", _button_style())
	btn.add_theme_stylebox_override("pressed", _button_style())
	btn.pressed.connect(_open)
	add_child(btn)


func _button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PAPER
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _ui_font() -> Font:
	if _font_cache == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(FONT_FAMILIES)
		_font_cache = font
	return _font_cache


func _open() -> void:
	if _board == null or _board.visible:
		return
	_shade.color = Color(0, 0, 0, 0)
	_shade.visible = true
	_board.visible = true
	_board.input_enabled = false
	_board.modulate.a = 0.0
	_board.scale = Vector2(POP_FROM, POP_FROM)
	var view_size := get_viewport().get_visible_rect().size
	_board.pivot_offset = view_size * 0.5
	if _pop != null and _pop.is_valid():
		_pop.kill()
	_pop = create_tween()
	_pop.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pop.set_parallel(true)
	(
		_pop
		. tween_property(_board, "scale", Vector2(POP_SCALE, POP_SCALE), POP_TIME)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_pop.tween_property(_board, "modulate:a", 1.0, 0.12)
	_pop.tween_property(_shade, "color:a", SHADE_ALPHA, POP_TIME)
	_pop.chain().tween_callback(_enable_board_input)
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_board = true


func _enable_board_input() -> void:
	if _board != null and _board.visible:
		_board.input_enabled = true
		_board.scale = Vector2(POP_SCALE, POP_SCALE)


func _close() -> void:
	if _board == null or not _board.visible:
		return
	if _pop != null and _pop.is_valid():
		_pop.kill()
	_board.input_enabled = false
	if _board.has_method("release_editing"):
		_board.release_editing()
	_board.visible = false
	_board.scale = Vector2.ONE
	_board.modulate.a = 1.0
	_shade.visible = false
	_shade.color = Color(0, 0, 0, 0)
	if _paused_by_board:
		_paused_by_board = false
		if not _other_pause_open():
			get_tree().paused = false


func _other_pause_open() -> bool:
	var encyclopedia := get_node_or_null("../EncyclopediaEntry")
	if encyclopedia != null and encyclopedia.has_method("is_open") and encyclopedia.is_open():
		return true
	var pause_menu := get_node_or_null("../PauseMenu")
	return pause_menu != null and pause_menu.visible


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
