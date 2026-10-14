extends AudioStreamPlayer
## BGM 全局单例：整局循环播放；音量挂在 Music 总线上，由设置界面调节并持久化。
## 默认音量取自 data/rules/audio.csv（铁律 4：数值不落脚本）。
## 方法名避开原生 AudioStreamPlayer.set_volume_linear（覆写原生名会被引擎当作错误）。

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "audio"
const SETTINGS_KEY := "bgm_volume_linear"

var _volume := 1.0


func _ready() -> void:
	_volume = _load_volume()
	_apply_bus_volume()
	if not playing:
		play()


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
	for row in Config.get_table("rules/audio").get("rows", []):
		if str(row.get("key", "")) == "bgm_default_volume":
			return clampf(float(str(row["value"])), 0.0, 1.0)
	push_warning("BGM：data/rules/audio.csv 缺少 bgm_default_volume，按满音量兜底。")
	return 1.0


func _persist() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 已有其他设置时合并写入
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, _volume)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("BGM：音量设置持久化失败（%s）。" % error_string(err))
