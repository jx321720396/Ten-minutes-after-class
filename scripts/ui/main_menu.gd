extends Control

const SCENE_SETTINGS = preload("res://scenes/ui/settings_menu.tscn")
const SCENE_ABOUT = preload("res://scenes/ui/about_menu.tscn")
const SCENE_CONFIRM = preload("res://scenes/ui/confirm_dialog.tscn")
const SCENE_ENCYCLOPEDIA = preload("res://scenes/ui/encyclopedia.tscn")
const SCENE_CLASSROOM := "res://scenes/game/classroom3D.tscn"
const CAMPUS_THEME = preload("res://scripts/ui/campus_theme.gd")

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


func _ready():
	CAMPUS_THEME.main_menu(self)
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
	settings_panel.replay_requested.connect(_on_replay_tutorial)
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

	if GameState.new_game_requested:
		GameState.new_game_requested = false
		_start_new_game.call_deferred()


func _has_save() -> bool:
	return Save.has_save()


func _on_new_game():
	# 2026-10-13：点「新游戏」一律先过确认面板——
	# 有存档走「检测到存档」三键；无存档仅确认「开始新游戏？」。
	# 确认（清除 / 保留 / 确定）都直接开局；老师版不选角色，取消留在主菜单。
	confirm_dialog.open(_has_save())


func _start_new_game() -> void:
	# §4.1 契约：先建本局唯一的内核实例，再切课间空间——教室只读 GameState.sim_core
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	GameState.start_game(rng.randi(), _npc_count())
	# 教程由入口决定（28 章）：没看过、或设置里点了「重看」，这局进教室才弹。
	GameState.tutorial_pending = not TutorialOverlay.is_seen() or GameState.replay_tutorial
	GameState.replay_tutorial = false
	var error := get_tree().change_scene_to_file(SCENE_CLASSROOM)
	if error != OK:
		push_error("无法进入教室：%s" % error_string(error))


## 本局人数：见 autoload/config.gd 的 default_npc_count()（读 data/rules/roster.csv）。
## 一局固定 16 名 NPC（+ 玩家 = 17 个节点）—— 2026-10-12 起不再有难度选择。
func _npc_count() -> int:
	return Config.default_npc_count()


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


## 主菜单里没有教室可放教程：记一个标记，下一次新游戏进教室时重放。
func _on_replay_tutorial():
	GameState.replay_tutorial = true


func _on_close_about():
	about_panel.visible = false


func _on_confirm_clear():
	confirm_dialog.visible = false
	# 无存档口径的「确定」也走本信号：删除有 file_exists 守卫，但这里再挡一层。
	if Save.has_save():
		Save.delete()
	_start_new_game()


func _on_confirm_keep():
	confirm_dialog.visible = false
	_start_new_game()


func _on_cancel_confirm():
	confirm_dialog.visible = false
