extends Control

const SCENE_SETTINGS = preload("res://scenes/ui/settings_menu.tscn")
const SCENE_ABOUT = preload("res://scenes/ui/about_menu.tscn")
const SCENE_CONFIRM = preload("res://scenes/ui/confirm_dialog.tscn")

@onready var continue_btn: Button = $VBoxContainer/ContinueGame
@onready var new_game_btn: Button = $VBoxContainer/NewGame
@onready var setting_btn: Button = $VBoxContainer/Setting
@onready var about_btn: Button = $VBoxContainer/About
@onready var exit_btn: Button = $VBoxContainer/Exit

var settings_panel: Control
var about_panel: Control
var confirm_dialog: Control


func _ready():
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	setting_btn.pressed.connect(_on_settings)
	about_btn.pressed.connect(_on_about)
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


func _has_save() -> bool:
	return Save.has_save()


func _on_new_game():
	if _has_save():
		confirm_dialog.visible = true
	else:
		_start_new_game()


func _start_new_game():
	# TODO: 实现游戏场景
	pass


func _on_continue():
	if _has_save():
		# TODO: 实现游戏场景加载
		pass


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
	_start_new_game()


func _on_confirm_keep():
	confirm_dialog.visible = false
	_start_new_game()


func _on_cancel_confirm():
	confirm_dialog.visible = false
