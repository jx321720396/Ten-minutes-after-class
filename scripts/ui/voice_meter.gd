extends Control
## 办公室谈话的声量四段条（2026-10-19）。
## 只读展示：档位、实时强度、预计压力/动力、崩溃预警；不改内核。
## 文案与颜色来自 office_hub.json / office view；模式关闭时整个控件隐藏。

const TIER_FALLBACK := ["轻声", "平常", "提高", "吼"]

var _config: Dictionary = {}
var _font: Font
var _ink := Color(0.15, 0.16, 0.22)
var _paper := Color(1.0, 0.97, 0.91)
var _accent := Color(0.78, 0.65, 0.42)
var _active := false
var _tier := 2
var _intensity := 0.0
var _preview := ""
var _warning := ""


func setup(config: Dictionary, font: Font, ink: Color, paper: Color, accent: Color) -> void:
	_config = config
	_font = font
	_ink = ink
	_paper = paper
	_accent = accent
	custom_minimum_size = Vector2(0, 108)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func set_state(active: bool, tier: int, intensity: float, preview: String, warning: String) -> void:
	_active = active
	_tier = clampi(tier, 1, 4)
	_intensity = clampf(intensity, 0.0, 100.0)
	_preview = preview
	_warning = warning
	visible = active
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var width := size.x
	var tiers: Array = _config.get("voice_tiers", TIER_FALLBACK)
	var title := str(_config.get("voice_title", "声量"))
	draw_string(_font, Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _ink)
	var top := 24.0
	var gap := 4.0
	var seg := (width - gap * 3.0) / 4.0
	for i in range(4):
		var rect := Rect2(i * (seg + gap), top, seg, 22.0)
		var selected := i + 1 == _tier
		draw_rect(rect, _accent if selected else _paper, true)
		draw_rect(rect, _ink, false, 1.0)
		var label := str(tiers[i]) if i < tiers.size() else ""
		draw_string(
			_font,
			Vector2(rect.position.x + 5, rect.position.y + 16),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(1, 1, 1) if selected else _ink
		)
	var bar_y := top + 28.0
	draw_rect(Rect2(0, bar_y, width, 4.0), _paper, true)
	draw_rect(Rect2(0, bar_y, width * _intensity / 100.0, 4.0), _accent, true)
	draw_string(_font, Vector2(0, bar_y + 26), _preview, HORIZONTAL_ALIGNMENT_LEFT, width, 15, _ink)
	if _warning != "":
		draw_string(
			_font,
			Vector2(0, bar_y + 48),
			_warning,
			HORIZONTAL_ALIGNMENT_LEFT,
			width,
			15,
			Color(0.72, 0.2, 0.16)
		)
