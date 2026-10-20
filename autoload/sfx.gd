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
## 返回音判定（2026-10-20）：_input 记下 ui_cancel，若 _unhandled_input 仍收到
## 说明没有任何页面消费这次返回（例如主菜单），此时不播。
var _cancel_pending := false
## 脚步声全局节流：多个人物同时走时按最小间隔重播（<=0 关闭节流）
var _footstep_gap_s := 0.0
var _footstep_last := -INF


func _ready() -> void:
	_volume = _load_volume()
	_apply_bus_volume()
	_footstep_gap_s = _load_audio_value("footstep_min_gap_s", 0.0)
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


## 学期最终结算（正常第 30 天结束或被辞退）：放学声收尾。
## 正常结束时与 day_settled 同帧到达 —— 已在播就不重播（重播会从头拍一下，听感是爆音）。
func on_term_finished(_ended_day: int) -> void:
	_stop_player("AmbClass")
	var player := get_node_or_null(^"AfterSchoolSettle") as AudioStreamPlayer
	if player != null and not player.playing:
		player.play()


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
	# 返回 / 取消音：先记下，本次事件派发结束后再结算（页面在 _unhandled_input 里消费 ESC）。
	if event.is_action_pressed("ui_cancel"):
		_cancel_pending = true
		call_deferred(&"_flush_cancel_sound")
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


## 本次 ui_cancel 是否真的被页面处理。autoload 的 _unhandled_input 排在场景节点之后：
## 仍然收到 = 没人消费（如主菜单），作废；被页面消费了则收不到，保留待播。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_pending = false


func _flush_cancel_sound() -> void:
	if not _cancel_pending:
		return
	_cancel_pending = false
	play_cancel()


func _play_button_click() -> void:
	_button_player.play()


## 脚步声：全局按 footstep_min_gap_s 节流（data/rules/audio.csv），多人同走不叠成噪音。
func play_footstep() -> void:
	if _footstep_gap_s > 0.0:
		var now := float(Time.get_ticks_msec()) / 1000.0
		if now - _footstep_last < _footstep_gap_s:
			return
		_footstep_last = now
	_footstep_player.play()


## 读 data/rules/audio.csv 的一个数值键；缺键时告警并用兜底值。
func _load_audio_value(key: String, fallback: float) -> float:
	for row in Config.get_table("rules/audio").get("rows", []):
		if str(row.get("key", "")) == key:
			return float(str(row["value"]))
	push_warning("SFX：data/rules/audio.csv 缺少 %s，用兜底值 %s。" % [key, fallback])
	return fallback


## 返回音：沿用普通按钮点击音（ui_light_hint.mp3，与 ButtonClick 同一资源），
## 不用 ui_cancel.mp3（试听为「取消／拒绝」音色）。ESC 由 _input 自动判定；
## 在 _input 阶段自行消费 ESC 的页面（背包 / 档案 / 开场漫画）直接调用本函数。
func play_cancel() -> void:
	play_one_shot("UiCancel")


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
