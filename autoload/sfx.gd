extends Node
## SFX 全局单例：按钮点击（自动挂接所有 BaseButton）与脚步声，统一走 SFX 总线。
## 默认音量取自 data/rules/audio.csv（铁律 4：数值不落脚本）。

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "audio"
const SETTINGS_KEY := "sfx_volume_linear"

@onready var _button_player: AudioStreamPlayer = $ButtonClick
@onready var _disabled_player: AudioStreamPlayer = $DisabledClick
@onready var _footstep_player: AudioStreamPlayer = $Footsteps

var _volume := 1.0
var _buttons: Array[BaseButton] = []
var _pointer_pos := Vector2.INF


func _ready() -> void:
	_volume = _load_volume()
	_apply_bus_volume()
	# 场景树里**之后与已存在**的每个按钮都挂 pressed：
	# 鼠标、触屏、键盘激活与代码 emit 都会响，动态生成的面板同样覆盖。
	get_tree().node_added.connect(_on_node_added)
	EventBus.event_happened.connect(_on_event_happened)
	EventBus.day_settled.connect(_on_day_settled)
	Save.saved.connect(_on_game_saved)


## 时钟相位快照 → 环境声（由教室场景把 phase_changed 接过来）：
## 上课起 amb_class 循环、下课停；每天**上午课间**（morning_break）开始时一声 morning_birds。
func on_phase_changed(snapshot: Dictionary) -> void:
	if str(snapshot.get("kind", "")) == "class":
		start_loop("AmbClass")
	else:
		_stop_player("AmbClass")
	if str(snapshot.get("phase_id", "")) == "morning_break":
		play_one_shot("MorningBirds")


## 内核事件 → 一次性音效：只有**活动真的发生**才响（加入被拒不算开始聊天）。
func _on_event_happened(payload: Dictionary) -> void:
	match str(payload.get("kind", "")):
		"pass_note":
			play_one_shot("NotePass")
		"roughhouse":
			play_one_shot("ChaseRuckus")
		"chat":
			if not payload.has("mode") or bool(payload.get("accepted", false)):
				play_one_shot("ActChatStart")


## 一天结算 = 放学：收掉教室环境声，播散场声。
func _on_day_settled(_summary: Dictionary) -> void:
	_stop_player("AmbClass")
	play_one_shot("AfterSchoolSettle")


func _on_game_saved() -> void:
	play_one_shot("SaveComplete")


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	if not button.pressed.is_connected(_play_button_click):
		button.pressed.connect(_play_button_click)
	_buttons.append(button)


## 禁用按钮不会收到 GUI 输入（不 emit pressed），用指针位置手动命中判定：
## 点到禁用按钮 = 无响应点击，播 ui_button_click 作反馈。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_pos = event.position
		return
	var clicked := false
	if event is InputEventMouseButton:
		clicked = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		clicked = event.pressed
	if not clicked:
		return
	_pointer_pos = event.position
	var index := _buttons.size()
	while index > 0:
		index -= 1
		var button := _buttons[index]
		if not is_instance_valid(button):
			_buttons.remove_at(index)
			continue
		if button.disabled and button.is_visible_in_tree():
			if button.get_global_rect().has_point(_pointer_pos):
				_disabled_player.play()
				return


func _play_button_click() -> void:
	_button_player.play()


func play_footstep() -> void:
	_footstep_player.play()


## 播一次子播放器（节点名见 sfx.tscn），缺失时静默（场景未接入音频时不报错）。
func play_one_shot(player_name: String) -> void:
	var player := get_node_or_null(NodePath(player_name)) as AudioStreamPlayer
	if player != null:
		player.play()


## 循环播放（滑动摩擦声）：已在播则不重起来避免爆音。
func start_loop(player_name: String) -> void:
	var player := get_node_or_null(NodePath(player_name)) as AudioStreamPlayer
	if player == null or player.playing:
		return
	var stream := player.stream as AudioStreamMP3
	if stream != null:
		stream.loop = true
	player.play()


## 松手时停掉滑动循环（画过哪个工具就停哪个）。
func stop_board_loops() -> void:
	for player_name in ["ChalkWrite", "EraserWipe"]:
		_stop_player(player_name)


## 停掉指定播放器（不在播就什么都不做）。
func _stop_player(player_name: String) -> void:
	var player := get_node_or_null(NodePath(player_name)) as AudioStreamPlayer
	if player != null and player.playing:
		player.stop()


func get_sfx_volume() -> float:
	return _volume


func set_sfx_volume(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume()
	_persist()


func _apply_bus_volume() -> void:
	var bus := AudioServer.get_bus_index("SFX")
	if bus < 0:
		push_warning("SFX：找不到 SFX 总线，音量设置不生效。")
		return
	AudioServer.set_bus_mute(bus, _volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(_volume, 0.0001)))


func _load_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved := float(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, -1.0))
		if saved >= 0.0:
			return clampf(saved, 0.0, 1.0)
	for row in Config.get_table("rules/audio").get("rows", []):
		if str(row.get("key", "")) == "sfx_default_volume":
			return clampf(float(str(row["value"])), 0.0, 1.0)
	push_warning("SFX：data/rules/audio.csv 缺少 sfx_default_volume，按满音量兜底。")
	return 1.0


func _persist() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 已有其他设置时合并写入
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, _volume)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("SFX：音量设置持久化失败（%s）。" % error_string(err))
