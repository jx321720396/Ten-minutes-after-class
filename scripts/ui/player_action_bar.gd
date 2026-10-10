class_name PlayerActionBar
extends CanvasLayer
## 右侧常驻行为栏（§20.1.2，2026-10-10 定稿）：**先选行为、再点对象**。
##
## 依据：主文档 §10.2（三组分类）、§20.1.2（两步交互 + 三态不隐藏）。
##
## 交互（两步）：
##   ① 点一个行为按钮 → 该按钮选中（高亮），底部提示「现在点一个人」
##   ② 点一个人物 → 选对象；需要接近的行为先走过去，到位后自动结算
##
## 三条约束：
##   ① **点人物不再弹卡片** —— 点人只表示「选对象」，目标信息显示在本栏底部；
##   ② **三态都不隐藏按钮**：可用（正常）｜暂时不可用（橙色 + 原因）｜还没做（灰色 + 占位说明）——
##      隐藏会让玩家以为功能不存在（§20.1.2）；
##   ③ 本栏**只发意图、不改世界**：真正的裁决仍在内核（`player_action`）。
##
## 「对自己做的事」点按钮直接执行（不需要选对象）—— 本批这些项都还是灰置占位。

signal behavior_armed(kind: StringName)
signal self_behavior_requested(kind: StringName)
signal cancel_requested
## 「看资料」：打开被选中同学的档案页（旧底部卡片的能力，不能因为换形态丢掉）
signal profile_requested(index: int)

## 公开活动的中文名（内核 activity_of 的返回值 → 玩家看得懂的说法）
const ACTIVITY_NAMES := {
	"chat": "正在闲聊",
	"pass_note": "正在传纸条",
	"tease": "正在起哄",
	"comfort": "正在安慰人",
	"apologize": "在道歉",
	"roughhouse": "在打闹",
	"exclude": "在排挤人",
	"report": "去了老师那儿",
	"move": "走动中",
	"sleep": "睡着了",
	"study": "在学习",
}

const STYLE_TABLE := "ui/chat_feedback_style"
const COLOR_PAPER := Color(0.98, 0.96, 0.90, 0.94)
const COLOR_INK := Color(0.13, 0.16, 0.14)
const COLOR_SUB := Color(0.34, 0.38, 0.35)
const COLOR_ACCENT := Color(0.16, 0.38, 0.26)
const COLOR_LOCKED := Color(0.62, 0.34, 0.22)
const COLOR_PLACEHOLDER := Color(0.55, 0.55, 0.52)

## 行为栏内容：[kind, 分组, 显示名, 是否自指]
##   - 需要选对象的（target 组）：闲聊（含加入）/ 递纸条 / 举报 / 追逐打闹 / 排挤
##   - 对自己做的事（self）：观察 / 学习 / 睡觉 / 听音乐 / 吃零食 / 看课外书 / 出门
## 分组只用于排布与标题（§10.2 的三组口径），不改变任何判定。
const ROWS := [
	[&"chat", "talk", "闲聊", false],
	[&"pass_note", "do", "递纸条", false],
	[&"report", "do", "举报", false],
	[&"roughhouse", "do", "追逐打闹", false],
	[&"exclude", "do", "排挤", false],
	# 观察属「不接触」类（§10.2.3），但它**需要点一个对象**（最后一列 false = 不是纯自指）
	[&"observe", "self", "观察", false],
	[&"study", "self", "学习", true],
	[&"sleep", "self", "睡觉", true],
	[&"listen_music", "self", "听音乐", true],
	[&"eat_snack", "self", "吃零食", true],
	[&"read_book", "self", "看课外书", true],
	[&"leave_class", "self", "出门", true],
]
const GROUP_TITLES := {"talk": "开口说话", "do": "动手做事", "self": "对自己做的事"}
## 占位原因（本批未实装的行为）
const PLACEHOLDER_REASON := "还没做"

var _panel: PanelContainer = null
var _rows_box: VBoxContainer = null
var _target_label: Label = null
var _profile_button: Button = null
var _target_index := -1
var _button_of: Dictionary = {}
var _armed := StringName("")
var _width := 168.0
var _margin := 18.0


func _ready() -> void:
	_load_style()
	_build_ui()


# ------------------------------------------------------------------ 对外接口
## 刷新整栏：`states` 是 kind -> {"ok": bool, "reason": String}；`self_labels` 可覆盖自指项文案。
## 未给出的 kind 视为「占位」（灰置 + `还没做`）。
func refresh(states: Dictionary) -> void:
	for kind in _button_of.keys():
		var button: Button = _button_of[kind]
		var state: Dictionary = states.get(kind, {})
		if state.is_empty():
			button.disabled = true
			button.tooltip_text = PLACEHOLDER_REASON
			button.add_theme_color_override("font_color", COLOR_PLACEHOLDER)
			continue
		var ok := bool(state.get("ok", false))
		button.disabled = not ok
		button.tooltip_text = "" if ok else str(state.get("reason", ""))
		button.add_theme_color_override("font_color", COLOR_INK if ok else COLOR_LOCKED)
	_update_highlight()


## 按钮点击：切换选中并通知控制器（再次点同一个 = 取消）。
func arm(kind: StringName) -> void:
	_armed = StringName("") if _armed == kind else kind
	_update_highlight()
	if _armed != StringName(""):
		behavior_armed.emit(_armed)


## 控制器驱动的选中（只改高亮，不反向通知 —— 避免与 `behavior_armed` 形成回路）。
func set_armed(kind: StringName) -> void:
	_armed = kind
	_update_highlight()


func armed_kind() -> StringName:
	return _armed


func clear_armed() -> void:
	if _armed == StringName(""):
		return
	_armed = StringName("")
	_update_highlight()


## 底部信息行：没选行为时给提示；选了行为后显示目标或等待提示。
func show_target(index: int, name_text: String, activity: String) -> void:
	_target_index = index
	_target_label.text = "%s · %s" % [name_text, activity] if name_text != "" else _idle_hint()
	if _profile_button != null:
		_profile_button.disabled = name_text == ""


func show_hint(text: String) -> void:
	_target_label.text = text
	if _profile_button != null:
		_profile_button.disabled = true


func target_text() -> String:
	return _target_label.text


## 测试与调试：某个 kind 的按钮文案 / 是否灰置。
func button_text_of(kind: StringName) -> String:
	var button: Button = _button_of.get(kind, null)
	return "" if button == null else button.text


func button_disabled_of(kind: StringName) -> bool:
	var button: Button = _button_of.get(kind, null)
	return true if button == null else button.disabled


func button_count() -> int:
	return _button_of.size()


# ------------------------------------------------------------------ 内部
func _idle_hint() -> String:
	if _armed == StringName(""):
		return "先在右边点一个动作"
	return "现在点一个人"


func _update_highlight() -> void:
	for kind in _button_of.keys():
		var button: Button = _button_of[kind]
		var selected: bool = kind == _armed
		button.add_theme_color_override(
			"font_color",
			COLOR_ACCENT if selected else (COLOR_PLACEHOLDER if button.disabled else COLOR_INK)
		)
	_target_label.text = _idle_hint()


func _on_pressed(kind: StringName, self_only: bool) -> void:
	var button: Button = _button_of[kind]
	if button.disabled:
		return
	if self_only:
		self_behavior_requested.emit(kind)
		return
	arm(kind)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ActionBar"
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PAPER
	box.border_color = COLOR_ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10.0)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.custom_minimum_size = Vector2(_width, 0.0)
	# 右侧常驻：贴右边、垂直居中偏上（不挡讲台与黑板）
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -_width - _margin
	_panel.offset_right = -_margin
	_panel.offset_top = _margin * 3.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_panel)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 4)
	_panel.add_child(column)
	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.add_theme_constant_override("separation", 3)
	column.add_child(_rows_box)
	var last_group := ""
	for row in ROWS:
		var kind := StringName(row[0])
		var group := str(row[1])
		if group != last_group:
			var title := Label.new()
			title.name = "Group_" + group
			title.text = str(GROUP_TITLES.get(group, group))
			title.add_theme_font_size_override("font_size", 13)
			title.add_theme_color_override("font_color", COLOR_SUB)
			title.add_theme_font_override("font", _font())
			_rows_box.add_child(title)
			last_group = group
		var button := Button.new()
		button.name = "Act_" + str(kind)
		button.text = str(row[2])
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", _font())
		button.pressed.connect(_on_pressed.bind(kind, bool(row[3])))
		_rows_box.add_child(button)
		_button_of[kind] = button
	_target_label = Label.new()
	_target_label.name = "TargetLine"
	_target_label.text = _idle_hint()
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_label.add_theme_font_size_override("font_size", 13)
	_target_label.add_theme_color_override("font_color", COLOR_SUB)
	_target_label.add_theme_font_override("font", _font())
	column.add_child(_target_label)
	_profile_button = Button.new()
	_profile_button.name = "ProfileButton"
	_profile_button.text = "看资料"
	_profile_button.focus_mode = Control.FOCUS_NONE
	_profile_button.disabled = true
	_profile_button.add_theme_font_override("font", _font())
	_profile_button.pressed.connect(func() -> void: profile_requested.emit(_target_index))
	column.add_child(_profile_button)


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
