extends AudioStreamPlayer
## BGM 全局单例：整局循环播放；音量挂在 Music 总线上，由设置界面调节并持久化。
## 默认音量取自 data/rules/audio.csv（铁律 4：数值不落脚本）。
## 方法名避开原生 AudioStreamPlayer.set_volume_linear（覆写原生名会被引擎当作错误）。
##
## 压力换轨（2026-10-18）：观察班级平均压力（与 classroom_art.gd 灯光同一信号、同一平滑常数），
## 达到 data/rules/audio.csv 的阈值时用交叉淡入淡出切到对应曲目：
##   · >= bgm_lofi_pressure（≈灯光 #f4ddd2）→ BgmLofi（bgm_lofi_classroom.mp3）
##   · >= bgm_urgent_pressure（≈灯光 #edafa1）→ BgmUrgent（urgent.ogg）
##   · 回落则切回默认 BGM；阈值以下保持 bgm_classroom.ogg。

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "audio"
const SETTINGS_KEY := "bgm_volume_linear"
const SILENT_DB := -80.0
## 平滑值与目标差不到 0.5 时直接贴住目标：指数平滑永远逼近不到 100，不贴就无法触发 urgent 档。
const PRESSURE_SNAP := 0.5

var _volume := 1.0
var _tracks: Dictionary = {}
var _lofi_pressure := 0.0
var _urgent_pressure := 0.0
var _fade_seconds := 1.0
var _base_db := 0.0
var _active: AudioStreamPlayer = null
var _fading_out: AudioStreamPlayer = null
var _fade_elapsed := 0.0
var _band := &"default"
var _display_pressure := 0.0
var _pressure_ready := false


func _ready() -> void:
	_volume = _load_volume()
	_apply_bus_volume()
	_lofi_pressure = _load_audio_value("bgm_lofi_pressure", 50.0)
	_urgent_pressure = _load_audio_value("bgm_urgent_pressure", 100.0)
	_fade_seconds = maxf(_load_audio_value("bgm_fade_seconds", 3.0), 0.05)
	_base_db = volume_db
	_tracks = {
		&"default": self,
		&"lofi": get_node(^"BgmLofi"),
		&"urgent": get_node(^"BgmUrgent"),
	}
	for player in _tracks.values():
		var mp3 := player.stream as AudioStreamMP3
		if mp3 != null:
			mp3.loop = true
	_active = self
	if not playing:
		play()


func _process(delta: float) -> void:
	_update_fade(delta)
	var target := _class_average_pressure()
	if target < 0.0:
		# GameState / 内核还没就绪（主菜单等）：保持当前曲目不动。
		return
	if not _pressure_ready:
		_display_pressure = target
		_pressure_ready = true
	_display_pressure = lerpf(_display_pressure, target, 1.0 - exp(-delta / _fade_seconds))
	if absf(_display_pressure - target) <= PRESSURE_SNAP:
		_display_pressure = target
	var next := &"default"
	if _display_pressure >= _urgent_pressure:
		next = &"urgent"
	elif _display_pressure >= _lofi_pressure:
		next = &"lofi"
	if next != _band:
		_switch_to(next)


## 切到某条轨道：新轨从静音淡入，旧轨淡出后停止（淡入淡出中再切轨则立刻掐掉上一段淡出）。
func _switch_to(band: StringName) -> void:
	var new_track: AudioStreamPlayer = _tracks[band]
	if new_track == _active:
		_band = band
		return
	if _fading_out != null:
		_fading_out.stop()
		_fading_out.volume_db = _base_db
	_fading_out = _active
	_active = new_track
	_band = band
	_fade_elapsed = 0.0
	_active.volume_db = SILENT_DB
	_active.play(0.0)


func _update_fade(delta: float) -> void:
	if _fading_out == null:
		return
	_fade_elapsed += delta
	var w := clampf(_fade_elapsed / _fade_seconds, 0.0, 1.0)
	_fading_out.volume_db = lerpf(_base_db, SILENT_DB, w)
	_active.volume_db = lerpf(SILENT_DB, _base_db, w)
	if w >= 1.0:
		_fading_out.stop()
		_fading_out.volume_db = _base_db
		_fading_out = null


## 班级平均压力（0–100）；内核未就绪或无节点时返回 -1 表示「本帧不可判定」。
func _class_average_pressure() -> float:
	var state := get_node_or_null(^"/root/GameState")
	if state == null or state.sim_core == null:
		return -1.0
	var core = state.sim_core
	var total := 0.0
	var count := 0
	for index in range(core.node_count()):
		total += core.stress(index)
		count += 1
	if count == 0:
		return -1.0
	return total / count


func get_bgm_volume() -> float:
	return _volume


func set_bgm_volume(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume()
	_persist()


func _apply_bus_volume() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		push_warning("BGM：找不到 Music 总线，音量设置不生效。")
		return
	AudioServer.set_bus_mute(bus, _volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(_volume, 0.0001)))


func _load_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved := float(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, -1.0))
		if saved >= 0.0:
			return clampf(saved, 0.0, 1.0)
	return clampf(_load_audio_value("bgm_default_volume", 1.0), 0.0, 1.0)


## 从 data/rules/audio.csv 读一个浮点参数（铁律 4）；缺行时告警并用兜底值。
func _load_audio_value(key: String, fallback: float) -> float:
	for row in Config.get_table("rules/audio").get("rows", []):
		if str(row.get("key", "")) == key:
			return float(str(row["value"]))
	push_warning("BGM：data/rules/audio.csv 缺少 %s，用兜底值 %s。" % [key, fallback])
	return fallback


func _persist() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 已有其他设置时合并写入
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, _volume)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("BGM：音量设置持久化失败（%s）。" % error_string(err))
