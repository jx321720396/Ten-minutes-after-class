extends Control
## 开局前的性别选择界面 —— 从主菜单「新游戏」进入。
##
## 交互（按 2026-10-10 的需求）：
##   · 两张立绘各占一个纸感框，鼠标移上去**稍微放大 + 边缘高亮**；
##   · 点一下即选中，选中态**保持**（边框加粗着色、保持放大），不随鼠标移开而消失；
##   · 两张卡互斥，只能选一个；没选之前「开始游戏」是灰的；
##   · 点「开始游戏」→ 发 `chosen(gender)`；点「返回」→ 发 `closed`。
##
## 性别只在本局内有效（写进 `GameState.player_gender`，不落盘），由调用方负责。
## 文案一律不进代码之外的地方；这里只有「男 / 女」两个词，已在场景里。

signal chosen(gender: String)
signal closed

## 悬停 / 选中时的放大比例（“稍微”放大，不做夸张动画）
const SCALE_IDLE := 1.0
const SCALE_HOVER := 1.045
const SCALE_SELECTED := 1.045
## 缩放动画时长（秒）
const SCALE_TIME := 0.09

## 选中态的边框（在场景的基础纸感样式上只改这两处）
const SELECTED_BORDER_COLOR := Color(0.78, 0.65, 0.42)
const SELECTED_BORDER_WIDTH := 5
const HOVER_BORDER_COLOR := Color(0.72, 0.6, 0.38)
const HOVER_BORDER_WIDTH := 3

@onready var _male: PanelContainer = $CenterContainer/Panel/Margin/VBox/Row/MaleCard
@onready var _female: PanelContainer = $CenterContainer/Panel/Margin/VBox/Row/FemaleCard
@onready var _start: Button = $CenterContainer/Panel/Margin/VBox/Footer/StartBtn
@onready var _back: Button = $CenterContainer/Panel/Margin/VBox/Footer/BackBtn

## "" = 还没选
var _selected := ""
var _hovered := ""
## 各卡片的原始（未选中）样式，_ready 时从场景取一份
var _base_style: Dictionary = {}


func _ready() -> void:
	_base_style[_male] = _male.get_theme_stylebox("panel")
	_base_style[_female] = _female.get_theme_stylebox("panel")

	for card in [_male, _female] as Array:
		var c: PanelContainer = card
		var g := _gender_of(c)
		c.mouse_entered.connect(_on_card_hover.bind(g))
		c.mouse_exited.connect(_on_card_exit.bind(g))
		c.gui_input.connect(_on_card_input.bind(g))
		# 缩放以卡片中心为原点
		c.resized.connect(_sync_pivot.bind(c))

	_start.pressed.connect(_on_start)
	_back.pressed.connect(_on_back)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()


# ------------------------------------------------------------------ 对外

## 当前选中的性别（"" = 还没选）。
func selected_gender() -> String:
	return _selected


## 供测试与外部程序化选中。
func select_gender(gender: String) -> void:
	if gender != "male" and gender != "female":
		return
	_selected = gender
	_refresh()


func can_start() -> bool:
	return not _selected.is_empty()


# ------------------------------------------------------------------ 交互

func _on_card_hover(gender: String) -> void:
	_hovered = gender
	_refresh()


func _on_card_exit(gender: String) -> void:
	if _hovered == gender:
		_hovered = ""
	_refresh()


func _on_card_input(event: InputEvent, gender: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	select_gender(gender)


func _on_start() -> void:
	if _selected.is_empty():
		return
	emit_signal("chosen", _selected)


func _on_back() -> void:
	emit_signal("closed")


# ------------------------------------------------------------------ 呈现

func _refresh() -> void:
	_start.disabled = _selected.is_empty()
	for card in [_male, _female] as Array:
		_update_card(card as PanelContainer)


func _update_card(card: PanelContainer) -> void:
	var g := _gender_of(card)
	var is_selected := (g == _selected)
	var is_hovered := (g == _hovered)

	var style: StyleBoxFlat = (_base_style[card] as StyleBoxFlat).duplicate()
	if is_selected:
		style.border_color = SELECTED_BORDER_COLOR
		style.border_width_left = SELECTED_BORDER_WIDTH
		style.border_width_top = SELECTED_BORDER_WIDTH
		style.border_width_right = SELECTED_BORDER_WIDTH
		style.border_width_bottom = SELECTED_BORDER_WIDTH
	elif is_hovered:
		style.border_color = HOVER_BORDER_COLOR
		style.border_width_left = HOVER_BORDER_WIDTH
		style.border_width_top = HOVER_BORDER_WIDTH
		style.border_width_right = HOVER_BORDER_WIDTH
		style.border_width_bottom = HOVER_BORDER_WIDTH
	card.add_theme_stylebox_override("panel", style)

	var target := SCALE_SELECTED if is_selected else (SCALE_HOVER if is_hovered else SCALE_IDLE)
	_scale_card(card, target)


## 以卡片中心为原点缩放（否则会从左上角涨出去）。
func _sync_pivot(card: Control) -> void:
	card.pivot_offset = card.size * 0.5


func _scale_card(card: Control, target: float) -> void:
	_sync_pivot(card)
	if is_equal_approx(card.scale.x, target):
		return
	var tween := card.create_tween()
	tween.tween_property(card, "scale", Vector2(target, target), SCALE_TIME)


func _gender_of(card: Control) -> String:
	return "male" if card == _male else "female"
