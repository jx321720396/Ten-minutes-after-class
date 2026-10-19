extends Node
## 声量可选挑战模式设置（2026-10-19）。
##
## 全局偏好：存在 user://settings.cfg 的 voice 段；缺失键一律按「关闭」处理，
## 因此旧存档与现有玩家默认不会进入声量模式。校准数据只存本地，不录音、不上传。
## 只负责读写开关 / 输入方式 / 校准；不引用办公室或内核。

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "voice"
const KEY_ENABLED := "enabled"
const KEY_INPUT := "input_mode"
const KEY_CALIBRATION := "calibration"

var _enabled := false
var _input_mode := "mic"
var _calibration: Dictionary = {}


func _ready() -> void:
	_load()


func is_enabled() -> bool:
	return _enabled


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	_persist()
	changed.emit()


func input_mode() -> String:
	return _input_mode


func set_input_mode(mode: String) -> void:
	if mode not in ["mic", "hold"] or _input_mode == mode:
		return
	_input_mode = mode
	_persist()
	changed.emit()


func calibration() -> Dictionary:
	return _calibration.duplicate(true)


func has_calibration() -> bool:
	return float(_calibration.get("ref", 0.0)) > 0.0


func set_calibration(data: Dictionary) -> void:
	_calibration = data.duplicate(true)
	_persist()
	changed.emit()


func clear_calibration() -> void:
	if _calibration.is_empty():
		return
	_calibration = {}
	_persist()
	changed.emit()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_enabled = bool(cfg.get_value(SECTION, KEY_ENABLED, false))
	var mode := str(cfg.get_value(SECTION, KEY_INPUT, "mic"))
	_input_mode = mode if mode in ["mic", "hold"] else "mic"
	var raw: Variant = cfg.get_value(SECTION, KEY_CALIBRATION, {})
	_calibration = raw.duplicate(true) if raw is Dictionary else {}


func _persist() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, KEY_ENABLED, _enabled)
	cfg.set_value(SECTION, KEY_INPUT, _input_mode)
	cfg.set_value(SECTION, KEY_CALIBRATION, _calibration)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("VoiceSettings：设置持久化失败（%s）" % error_string(err))
