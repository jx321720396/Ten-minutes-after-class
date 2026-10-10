extends CanvasLayer
## 教室里的「百科全书」入口（表现层）
##
## 位置：天数 HUD 卡片（`scripts/ui/time_hud.gd`，左上角 `CARD_MARGIN = (16,16)`、宽 340）
## 的**下方**；样式与 HUD 同一套（纸色底 + 深绿描边 + 圆角 6 + 同一中文字族）。
##
## 交互：点开 → 弹出百科全书面板，**并把游戏暂停**（`get_tree().paused = true`，时间停止）；
## 关掉（面板的「返回」或 Esc）→ 恢复。
##
## 注意事项：
##   · 本节点与面板都设 `process_mode`，否则暂停后按钮/目录点不动；
##   · 面板复用主菜单那套 `scenes/ui/encyclopedia.tscn`，内容来自 `data/localization/encyclopedia.json`。

const SCENE_ENCYCLOPEDIA := preload("res://scenes/ui/encyclopedia.tscn")

## 与 time_hud.gd / classroom_actors.gd 同一套族名（中文字族优先，末位 sans-serif 兜底）
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
## 天数 HUD 卡片正下方的位置（卡片约 80px 高 + 其下方有 toast/action 两个临时元素）
const BUTTON_POS := Vector2(16.0, 152.0)
const BUTTON_SIZE := Vector2(140.0, 38.0)

var _panel: Control = null
var _font_cache: Font = null


func _ready() -> void:
	layer = 2  # 与时间 HUD 同层
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时本节点仍要能响应
	_build_button()

	_panel = SCENE_ENCYCLOPEDIA.instantiate()
	_panel.visible = false
	# 面板要在暂停状态下仍可交互，否则打开后按钮/目录全点不动
	_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_panel.closed.connect(_close)
	add_child(_panel)


## 供测试与调试读取。
func is_open() -> bool:
	return _panel != null and _panel.visible


func open() -> void:
	_open()


func close() -> void:
	_close()


func _build_button() -> void:
	var btn := Button.new()
	btn.name = "EncyclopediaButton"
	btn.text = "百科全书"
	btn.position = BUTTON_POS
	btn.size = BUTTON_SIZE
	btn.custom_minimum_size = BUTTON_SIZE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
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
	if _panel == null:
		return
	_panel.visible = true
	get_tree().paused = true  # 看百科全书时，游戏时间停止


func _close() -> void:
	if _panel != null:
		_panel.visible = false
	# 黑板还开着时，不要把游戏一起恢复
	var board := get_node_or_null("../ClueBoardEntry")
	if board != null and board.has_method("is_open") and board.is_open():
		return
	var pause_menu := get_node_or_null("../PauseMenu")
	if pause_menu != null and pause_menu.visible:
		return
	get_tree().paused = false
