extends Control

const SCENE_SETTINGS = preload("res://scenes/ui/settings_menu.tscn")
const SCENE_ABOUT = preload("res://scenes/ui/about_menu.tscn")
const SCENE_CONFIRM = preload("res://scenes/ui/confirm_dialog.tscn")
const SCENE_ENCYCLOPEDIA = preload("res://scenes/ui/encyclopedia.tscn")
const SCENE_CLASSROOM := "res://scenes/game/classroom3D.tscn"
const SCENE_TRANSITION = preload("res://scenes/ui/transition_overlay.tscn")
const CAMPUS_THEME = preload("res://scripts/ui/campus_theme.gd")
## 开幕黑幕最短停留（与日首黑幕 FLASH_HOLD_DAY 一致），加载更快也不一闪而过
const OPENING_MIN_SECONDS := 1.35
## 开幕期间等待场景 / 贴图的上限；超时仍切场景（贴图会继续后台加载）
const OPENING_LOAD_TIMEOUT_MSEC := 8000

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
## 开幕黑幕（与教室日首黑幕同一套视觉）：点新游戏立即盖上，加载完成后切场景。
var _opening: TransitionOverlay
## 开局只允许进一次（开幕黑幕已挡住鼠标，这里再防同帧连点）。
var _starting_new_game := false


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

	_opening = SCENE_TRANSITION.instantiate()
	add_child(_opening)
	_opening.visible = false

	if GameState.new_game_requested:
		GameState.new_game_requested = false
		_start_new_game.call_deferred()
	TouchBind.bind_tree(self)
	# 后台预加载：把进教室时约 2.2 秒的贴图读盘挪到主菜单停留期间。
	AssetPreloader.request_textures(AssetPreloader.pose_texture_paths())
	AssetPreloader.request_scene(SCENE_CLASSROOM)


## 开幕加载期间吞掉返回键：此时没有可返回的页面，也不应该直接退出。
func _unhandled_input(event: InputEvent) -> void:
	if _starting_new_game and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _has_save() -> bool:
	return Save.has_save()


func _on_new_game():
	# 2026-10-17：移除无存档时的「开始新游戏？」确认面板，点「新游戏」直接开局；
	# 有存档仍走「检测到存档」三键（清除 / 保留 / 取消），避免误覆盖存档。
	if _has_save():
		confirm_dialog.open(true)
	else:
		_start_new_game()


## 2026-10-18：先显示开幕（「第 N 天」黑幕），加载在后台进行，就绪后再切教室。
## 这样玩家点完新游戏立刻有画面，看不到菜单冻结 / 黑屏等待。
func _start_new_game() -> void:
	if _starting_new_game:
		return
	_starting_new_game = true
	_show_opening()
	# §4.1 契约：先建本局唯一的内核实例，再切课间空间——教室只读 GameState.sim_core
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	GameState.start_game(rng.randi(), _npc_count())
	# 教程由入口决定（28 章）：没看过、或设置里点了「重看」，这局进教室才弹。
	GameState.tutorial_pending = not TutorialOverlay.is_seen() or GameState.replay_tutorial
	GameState.replay_tutorial = false
	# 教室进场不再重复盖「第 N 天」：开幕已经显示过（由转场组件消费后清零）。
	GameState.opening_day_shown = true
	var packed := await _wait_until_loaded()
	var error: Error
	if packed != null:
		error = get_tree().change_scene_to_packed(packed)
	else:
		error = get_tree().change_scene_to_file(SCENE_CLASSROOM)
	if error != OK:
		push_error("无法进入教室：%s" % error_string(error))
		GameState.opening_day_shown = false
		_starting_new_game = false
		if _opening != null:
			_opening.visible = false


## 盖上开幕黑幕：标题 / 副题与日首黑幕同源（副题读 time_presentation 的 display_name）。
func _show_opening() -> void:
	if _opening == null:
		return
	_opening.show_opening("第 1 天", _opening_subtitle())


func _opening_subtitle() -> String:
	for row in Config.get_table("rules/time_presentation").get("rows", []):
		if str(row.get("phase_id", "")) == "morning_break":
			return str(row.get("display_name", ""))
	return ""


## 等教室场景与人物贴图都就绪（至少停留 OPENING_MIN_SECONDS，最多等 timeout）。
## 超时则返回已加载的场景（可能为 null，调用方回退同步切场景）。
func _wait_until_loaded() -> PackedScene:
	var paths := AssetPreloader.pose_texture_paths()
	var started := Time.get_ticks_msec()
	var deadline := started + OPENING_LOAD_TIMEOUT_MSEC
	while true:
		var packed := AssetPreloader.scene(SCENE_CLASSROOM)
		var elapsed := Time.get_ticks_msec() - started
		var ready_enough := packed != null and AssetPreloader.all_ready(paths)
		if ready_enough and elapsed >= int(OPENING_MIN_SECONDS * 1000.0):
			return packed
		if Time.get_ticks_msec() >= deadline:
			return packed
		await get_tree().process_frame
	return null


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
