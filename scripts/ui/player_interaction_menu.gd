class_name PlayerInteractionMenu
extends CanvasLayer
## 选中人物后的底部行为卡片（表现层，只读）：名字 / 公开活动 / **唯一一个聊天操作** / 不可用原因。
##
## 依据：主文档 §12.2.1（菜单项）、§10.7（加入闲聊）、§10.31；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §2.1。
##
## 三条约束：
##   ① **只有一个聊天操作**：空闲对象显示「闲聊」，聊天中的成员显示「加入 · 加入闲聊」——
##      不是把两个旧行为换名并排展示（旧 join_chat 不再作为独立菜单项暴露）；
##   ② 公开活动只来自**当前行为 / 真实会话 / 睡眠与移动状态**，不显示压力、真实好感、敌对或信任；
##   ③ 菜单**不暂停全班**，状态随世界变化 —— 所以每次刷新都要重新取预览。

signal chat_requested
signal closed

const STYLE_TABLE := "ui/chat_feedback_style"
const COLOR_PAPER := Color(0.98, 0.96, 0.90, 0.94)
const COLOR_INK := Color(0.13, 0.16, 0.14)
const COLOR_SUB := Color(0.34, 0.38, 0.35)
const COLOR_ACCENT := Color(0.16, 0.38, 0.26)
const COLOR_LOCKED := Color(0.62, 0.34, 0.22)

## 公开活动的中文名（只描述「看得见的行为」，不含隐藏状态）
const ACTIVITY_NAMES := {
	"chat": "正在闲聊",
	"join_chat": "正在插话",
	"tease": "正在起哄",
	"comfort": "正在安慰人",
	"ask_help": "在请人帮忙",
	"apologize": "在道歉",
	"roughhouse": "在打闹",
	"exclude": "在排挤人",
	"report": "去了老师那儿",
	"rumor": "在传闲话",
	"move": "走动中",
	"sleep": "睡着了",
}

var _panel: PanelContainer = null
var _name_label: Label = null
var _activity_label: Label = null
var _action: Button = null
var _reason_label: Label = null
var _eta_label: Label = null
var _open := false
var _index := -1
var _info: Dictionary = {}
var _width := 320.0
var _margin := 24.0


func _ready() -> void:
	_load_style()
	_build_ui()
	_panel.visible = false


# ------------------------------------------------------------------ 对外接口


## 打开（或刷新）某个人物的卡片。info 由交互控制器按内核预览组装。
func open(index: int, info: Dictionary) -> void:
	_index = index
	_info = info
	_open = true
	_panel.visible = true
	_name_label.text = str(info.get("name", "同学"))
	_activity_label.text = activity_text(
		str(info.get("activity", "")), bool(info.get("moving", false))
	)
	var eligible := bool(info.get("eligible", false))
	var in_range := bool(info.get("in_range", false))
	var mode := str(info.get("mode", "start"))
	_action.text = "加入 · 加入闲聊" if mode == "join" else "闲聊"
	_action.disabled = not (eligible and bool(info.get("phase_ok", true)))
	_action.tooltip_text = "" if _action.disabled else hint_text(mode, in_range)
	_reason_label.text = (
		"" if _action.disabled == false else reason_text(str(info.get("reason", "")))
	)
	_eta_label.text = eta_text(bool(info.get("in_range", true)))
	_reason_label.visible = not _reason_label.text.is_empty()


func close() -> void:
	if not _open:
		return
	_open = false
	_index = -1
	_info = {}
	_panel.visible = false
	closed.emit()


func is_open() -> bool:
	return _open


func selected_index() -> int:
	return _index


func action_text() -> String:
	return _action.text


func reason_text_visible() -> String:
	return _reason_label.text


func info_text() -> String:
	return _eta_label.text


func button_disabled() -> bool:
	return _action.disabled


func hint_text(mode: String, in_range: bool) -> String:
	if in_range:
		return "就在旁边，直接聊" if mode == "start" else "就在旁边，直接加入"
	return "走过去闲聊" if mode == "start" else "走过去加入闲聊"


## 公开活动文案：只描述看得见的行为（睡觉 / 走动优先于行为名）。
func activity_text(activity: String, moving: bool) -> String:
	if moving:
		return "走动中"
	if activity.is_empty():
		return "空闲"
	return str(ACTIVITY_NAMES.get(activity, "在忙"))


## 不可用原因（只来自真实状态，不替 UI 猜）。
func reason_text(reason: String) -> String:
	match reason:
		"player_busy":
			return "你正忙着"
		"phase_not_allowed":
			return "上课期间不能聊天"
		"player_moving":
			return "先停下再聊"
		"target_sleeping":
			return "对方睡着了"
		"target_busy":
			return "对方正忙别的事"
		"target_moving":
			return "等对方停下再聊"
		"geometry_missing":
			return "场景空间数据未就绪"
		"out_of_range":
			return "离得太远"
		"group_layout_invalid":
			return "他们不在一块儿了"
		"target_unavailable":
			return "现在没法聊"
	return "现在没法聊" if reason.is_empty() else reason


## 预计用时：移动 + 聊天；剩余课间不足时提示可能被铃声打断（本版允许尝试）。
func eta_text(in_range: bool) -> String:
	var chat_seconds := float(_info.get("chat_seconds", 0.0))
	var travel := 0.0 if in_range else float(_info.get("travel_seconds", 0.0))
	var remaining := float(_info.get("remaining_seconds", 99999.0))
	var total := travel + chat_seconds
	var text := "预计 %.0f 秒（走动 %.0f + 聊天 %.0f）" % [total, travel, chat_seconds]
	if remaining < total:
		text += " · 可能被铃声打断"
	return text


# ------------------------------------------------------------------ 内部


func _on_action_pressed() -> void:
	if _action.disabled:
		return
	chat_requested.emit()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Card"
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PAPER
	box.border_color = COLOR_ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(12.0)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.custom_minimum_size = Vector2(_width, 0.0)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_name_label = _make_label(22, COLOR_INK)
	_activity_label = _make_label(16, COLOR_SUB)
	_action = Button.new()
	_action.name = "ChatAction"
	_action.focus_mode = Control.FOCUS_NONE
	_action.pressed.connect(_on_action_pressed)
	_reason_label = _make_label(15, COLOR_LOCKED)
	_eta_label = _make_label(14, COLOR_SUB)
	column.add_child(_name_label)
	column.add_child(_activity_label)
	column.add_child(_action)
	column.add_child(_reason_label)
	column.add_child(_eta_label)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = _margin
	_panel.offset_bottom = -_margin
	# 卡片高度随文案变化：贴着底边向上长，不遮挡下半间教室之外的视野
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.grow_horizontal = Control.GROW_DIRECTION_END


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", _font())
	return label


func _font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"]
	)
	return font


func _load_style() -> void:
	for row in ConfigLoader.new().get_table(STYLE_TABLE).get("rows", []):
		var value := float(str(row.get("value", "0")))
		match str(row.get("param", "")):
			"menu_width_px":
				_width = value
			"menu_margin_px":
				_margin = value
