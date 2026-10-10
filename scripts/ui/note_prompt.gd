class_name NotePrompt
extends CanvasLayer
## 收到纸条的提示与两次决策（表现层，只读 + 只发意图）。
##
## 依据：主文档 §8.6（纸条链）、§21.2.9（传纸条的 UI 规格）。
##
## 与规格对齐的四点：
##   ① **纸条到达不打断当前动作** —— 只在界面角落提示，玩家不点就一直在；
##   ② **两次决策**：先「看不看」，看完之后再决定「撕掉 / 继续传 / 去告诉老师」；
##   ③ **不显示纸条内容，也不显示是谁写的** —— 只给一句方向性短句；
##   ④ 举报只能**当场**做（撕掉之后不能再举）。
##
## 本组件**只发意图、不改内核状态**：由交互控制器调用内核的
## `read_note()` / `finish_note()` 落地 —— 内核是唯一事实源。
## 降级路径（§21.2.9）：砍掉持有者头顶徽标后，纸条的存在感就靠这个提示框。

signal choice_made(action: StringName)

const STYLE_TABLE := "ui/chat_feedback_style"
const COLOR_PAPER := Color(0.98, 0.96, 0.90, 0.94)
const COLOR_INK := Color(0.13, 0.16, 0.14)
const COLOR_ACCENT := Color(0.16, 0.38, 0.26)

## 到手提示（看不出是谁、更看不出写了什么）
const TEXT_HINT := "有人塞给你一张纸条。"
## 看完之后的方向性短句：好话 / 坏话两档（§21.2.9「结算」）
const TEXT_GOOD := "纸条上写着句好话。"
const TEXT_BAD := "纸条上写着不太中听的话。"

## 两步各自的可选项（顺序即界面顺序，也要能被测试断言）。
const OFFER_CHOICES := [
	["不看，传下去", &"skip_forward"],
	["不看，撕掉", &"skip_destroy"],
	["看看写的什么", &"read"],
]
const AFTER_READ_CHOICES := [
	["撕掉", &"destroy"],
	["继续传给别人", &"forward"],
	["去告诉老师", &"report"],
]

var _card: PanelContainer = null
var _text: Label = null
var _buttons: HBoxContainer = null
var _margin := 24.0
var _open := false
var _step := "idle"


func _ready() -> void:
	_load_style()
	_build_ui()
	_card.visible = false


# ------------------------------------------------------------------ 对外接口
## 第一步：纸条到手。可重复调用（刷新用），不重置玩家已做的选择。
func show_offer() -> void:
	if _open and _step == "offer":
		return
	_step = "offer"
	_open = true
	_text.text = TEXT_HINT
	_set_buttons(OFFER_CHOICES)
	_card.visible = true


## 第二步：看完之后的去向。tone < 0 是坏话，其余是好话（不显示内容与写者）。
func show_after_read(tone: int) -> void:
	_step = "after_read"
	_open = true
	_text.text = TEXT_BAD if tone < 0 else TEXT_GOOD
	_set_buttons(AFTER_READ_CHOICES)
	_card.visible = true


## 收掉提示（纸条已做出去向决策 / 换场景）。
func close() -> void:
	_open = false
	_step = "idle"
	_card.visible = false


func is_open() -> bool:
	return _open


func step() -> String:
	return _step


func body_text() -> String:
	return "" if _text == null else _text.text


## 当前可见的按钮文案（测试与调试用）。
func button_labels() -> Array[String]:
	var labels: Array[String] = []
	if _buttons == null:
		return labels
	for child in _buttons.get_children():
		labels.append(str((child as Button).text))
	return labels


# ------------------------------------------------------------------ 内部
func _set_buttons(choices: Array) -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for choice in choices:
		var button := Button.new()
		button.text = str(choice[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", _font())
		button.pressed.connect(_on_choice.bind(StringName(choice[1])))
		_buttons.add_child(button)


func _on_choice(action: StringName) -> void:
	choice_made.emit(action)


func _build_ui() -> void:
	_card = PanelContainer.new()
	_card.name = "NoteCard"
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PAPER
	box.border_color = COLOR_ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(12.0)
	_card.add_theme_stylebox_override("panel", box)
	# 右下角、贴边向上长：不遮住讲台与黑板（与邀请框同一角落约定）
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_right = -_margin
	_card.offset_bottom = -_margin
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_card)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	_card.add_child(column)
	_text = Label.new()
	_text.name = "NoteText"
	_text.add_theme_font_size_override("font_size", 16)
	_text.add_theme_color_override("font_color", COLOR_INK)
	_text.add_theme_font_override("font", _font())
	column.add_child(_text)
	_buttons = HBoxContainer.new()
	_buttons.name = "Buttons"
	column.add_child(_buttons)


func _font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"]
	)
	return font


func _load_style() -> void:
	for row in ConfigLoader.new().get_table(STYLE_TABLE).get("rows", []):
		if str(row.get("param", "")) == "menu_margin_px":
			_margin = float(str(row.get("value", "0")))
