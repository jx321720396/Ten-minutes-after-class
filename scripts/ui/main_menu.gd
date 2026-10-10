extends Control

const SCENE_SETTINGS = preload("res://scenes/ui/settings_menu.tscn")
const SCENE_ABOUT = preload("res://scenes/ui/about_menu.tscn")
const SCENE_CONFIRM = preload("res://scenes/ui/confirm_dialog.tscn")
const SCENE_ENCYCLOPEDIA = preload("res://scenes/ui/encyclopedia.tscn")
const SCENE_CLASSROOM := "res://scenes/game/classroom3D.tscn"
const SCENE_GENDER_SELECT = preload("res://scenes/ui/gender_select.tscn")

@onready var continue_btn: Button = $VBoxContainer/ContinueGame
@onready var new_game_btn: Button = $VBoxContainer/NewGame
@onready var setting_btn: Button = $VBoxContainer/Setting
@onready var about_btn: Button = $VBoxContainer/About
@onready var encyclopedia_btn: Button = $VBoxContainer/Encyclopedia
@onready var exit_btn: Button = $VBoxContainer/Exit

var settings_panel: Control
var about_panel: Control
var confirm_dialog: Control
var encyclopedia_panel: Control
var gender_select_panel: Control


func _ready():
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	setting_btn.pressed.connect(_on_settings)
	about_btn.pressed.connect(_on_about)
	encyclopedia_btn.pressed.connect(_on_encyclopedia)
	exit_btn.pressed.connect(_on_quit)

	continue_btn.disabled = not _has_save()

	settings_panel = SCENE_SETTINGS.instantiate()
	settings_panel.visible = false
	settings_panel.closed.connect(_on_close_settings)
	add_child(settings_panel)

	about_panel = SCENE_ABOUT.instantiate()
	about_panel.visible = false
	about_panel.closed.connect(_on_close_about)
	add_child(about_panel)

	confirm_dialog = SCENE_CONFIRM.instantiate()
	confirm_dialog.visible = false
	confirm_dialog.confirmed_clear.connect(_on_confirm_clear)
	confirm_dialog.confirmed_keep.connect(_on_confirm_keep)
	confirm_dialog.cancelled.connect(_on_cancel_confirm)
	add_child(confirm_dialog)

	encyclopedia_panel = SCENE_ENCYCLOPEDIA.instantiate()
	encyclopedia_panel.visible = false
	encyclopedia_panel.closed.connect(_on_close_encyclopedia)
	add_child(encyclopedia_panel)

	gender_select_panel = SCENE_GENDER_SELECT.instantiate()
	gender_select_panel.visible = false
	gender_select_panel.chosen.connect(_on_gender_chosen)
	gender_select_panel.closed.connect(_on_close_gender_select)
	add_child(gender_select_panel)


func _has_save() -> bool:
	return Save.has_save()


func _on_new_game():
	if _has_save():
		confirm_dialog.visible = true
	else:
		_ask_gender()


## 进教室之前先问性别。每次新游戏都问；性别只在本局内有效（写 GameState，不落盘）。
func _ask_gender() -> void:
	gender_select_panel.visible = true


func _on_gender_chosen(gender: String) -> void:
	GameState.player_gender = gender
	gender_select_panel.visible = false
	_start_new_game()


func _on_close_gender_select() -> void:
	gender_select_panel.visible = false


func _start_new_game() -> void:
	# §4.1 契约：先建本局唯一的内核实例，再切课间空间——教室只读 GameState.sim_core
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	GameState.start_game(rng.randi(), _default_difficulty())
	var error := get_tree().change_scene_to_file(SCENE_CLASSROOM)
	if error != OK:
		push_error("无法进入教室：%s" % error_string(error))


## 默认难度：见 autoload/config.gd 的 default_difficulty()（读 data/rules/difficulty.csv）。
# 难度选择 UI 待做；当前先固定默认档（16 NPC + 玩家 = 17 节点）。
func _default_difficulty() -> int:
	return Config.default_difficulty()


func _on_continue():
	if _has_save():
		# TODO: 实现游戏场景加载
		pass


func _on_encyclopedia():
	encyclopedia_panel.visible = true


func _on_close_encyclopedia():
	encyclopedia_panel.visible = false


func _on_settings():
	settings_panel.visible = true


func _on_about():
	about_panel.visible = true


func _on_quit():
	get_tree().quit()


func _on_close_settings():
	settings_panel.visible = false


func _on_close_about():
	about_panel.visible = false


func _on_confirm_clear():
	confirm_dialog.visible = false
	Save.delete()
	_ask_gender()


func _on_confirm_keep():
	confirm_dialog.visible = false
	_ask_gender()


func _on_cancel_confirm():
	confirm_dialog.visible = false
