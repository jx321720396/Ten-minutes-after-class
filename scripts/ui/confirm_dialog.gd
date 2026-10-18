extends Control

signal confirmed_clear
signal confirmed_keep
signal cancelled

## 两种口径的文案与颜色。2026-10-17 起主菜单只在有存档时打开本面板（三键口径）；
## 无存档口径 open(false) 保留给组件单测与后续复用，主菜单不再调用。
## 文案集中在这几个常量里，不在别处再写一份。
const FRESH_TITLE := "开始新游戏？"
const FRESH_MSG := "本学期共 30 天。确认后从转学第一天开始。"
const FRESH_OK := "确定"
const COLOR_INK := Color(0.15, 0.16, 0.22, 1)

@onready var clear_btn: Button = $CenterContainer/Panel/VBox/ClearBtn
@onready var keep_btn: Button = $CenterContainer/Panel/VBox/KeepBtn
@onready var cancel_btn: Button = $CenterContainer/Panel/VBox/CancelBtn
@onready var title_label: Label = $CenterContainer/Panel/VBox/Title
@onready var msg_label: Label = $CenterContainer/Panel/VBox/Msg


func _ready():
	get_viewport().size_changed.connect(_fit_fullscreen)
	_fit_fullscreen()
	clear_btn.pressed.connect(_on_clear)
	keep_btn.pressed.connect(_on_keep)
	cancel_btn.pressed.connect(_on_cancel)
	TouchBind.bind_tree(self)


func _fit_fullscreen() -> void:
	preload("res://scripts/ui/fullscreen_panel.gd").fit(
		$CenterContainer, $CenterContainer/Panel, Vector2(1280, 720)
	)


## 打开确认面板并按「有无存档」切口径：
## · has_save = true：三键（清除重开 / 保留开始 / 取消），按钮维持场景里的警示红；
## · has_save = false：两键（确定 / 取消），隐藏「保留存档」，确定键用墨色。
func open(has_save: bool) -> void:
	if has_save:
		title_label.text = "检测到存档"
		msg_label.text = "检测到本地存档，请选择：\n· 清除存档并开始新游戏\n· 保留存档并开始新游戏"
		clear_btn.text = "清除存档并开始"
		clear_btn.remove_theme_color_override("font_color")
		keep_btn.visible = true
	else:
		title_label.text = FRESH_TITLE
		msg_label.text = FRESH_MSG
		clear_btn.text = FRESH_OK
		clear_btn.add_theme_color_override("font_color", COLOR_INK)
		keep_btn.visible = false
	visible = true


func _on_clear():
	emit_signal("confirmed_clear")


func _on_keep():
	emit_signal("confirmed_keep")


func _on_cancel():
	emit_signal("cancelled")


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_cancel()
		get_viewport().set_input_as_handled()
