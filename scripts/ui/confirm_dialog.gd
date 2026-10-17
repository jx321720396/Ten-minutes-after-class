extends Control

signal confirmed_clear
signal confirmed_keep
signal cancelled

## 「检测到存档」确认面板 —— 只在**有存档**时由「新游戏」触发。
##
## 2026-10-18：**无存档口径已删除**。原先无存档会弹一道「开始新游戏？」+
## 「本学期共 30 天。确认后从转学第一天开始。」的确认（确定 / 取消），
## 但那是旧的转校生设定，与现在的实习老师版不符；且玩家只会点「确定」，
## 没有决策价值。现改为无存档直接开局，不再经过本面板。
const TITLE := "检测到存档"
const MSG := "检测到本地存档，请选择：\n· 清除存档并开始新游戏\n· 保留存档并开始新游戏"
const CLEAR_TEXT := "清除存档并开始"

@onready var clear_btn: Button = $CenterContainer/Panel/VBox/ClearBtn
@onready var keep_btn: Button = $CenterContainer/Panel/VBox/KeepBtn
@onready var cancel_btn: Button = $CenterContainer/Panel/VBox/CancelBtn
@onready var title_label: Label = $CenterContainer/Panel/VBox/Title
@onready var msg_label: Label = $CenterContainer/Panel/VBox/Msg


func _ready():
	clear_btn.pressed.connect(_on_clear)
	keep_btn.pressed.connect(_on_keep)
	cancel_btn.pressed.connect(_on_cancel)


## 打开面板：三键（清除重开 / 保留开始 / 取消），按钮维持场景里的警示红。
func open() -> void:
	title_label.text = TITLE
	msg_label.text = MSG
	clear_btn.text = CLEAR_TEXT
	keep_btn.visible = true
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
