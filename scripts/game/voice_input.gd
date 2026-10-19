extends Node
## 声量输入适配器（2026-10-19）：麦克风 / 按住蓄力 / 校准。
##
## 只负责「在 2.5 秒窗口内产生声量强度，最后给出档位」，不写内核、不改数值。
## 办公室把档位交给 TeacherCommands.set_office_voice；设置开关关闭时整段旁路。
## 麦克风只在窗口/校准期间读取；不录音、不上传。

signal intensity_changed(value: float)
signal tier_locked(tier: int)
signal mic_failed(reason: String)
signal calibration_step(index: int)
signal calibration_level(rms: float)
signal calibration_finished(profile: Dictionary)
signal calibration_failed(reason: String)

const MIC_PERMISSION := "android.permission.RECORD_AUDIO"
const DEFAULT_FLOOR := 0.002
const DEFAULT_REF := 0.05
const DEFAULT_SHOUT := 0.12

var _rules: VoiceRules = VoiceRules.new()
var _settings: Node
var _active := false
var _hold_mode := false
var _sampling := false
var _prompt_left := 0.0
var _sample_left := 0.0
var _hold_seconds := 0.0
var _sample_sum := 0.0
var _recent_values: Array[float] = []
var _recent_times: Array[float] = []
var _sample_elapsed := 0.0
var _window_average := 0.0
var _intensity := 0.0
var _live_tier := 1
var _tier := 2
var _median_values: Array[float] = []
var _mic_active := false
var _calibrating := false
var _calibration_step := 0
var _calibration_left := 0.0
var _calibration_sum := 0.0
var _calibration_count := 0
var _calibration_values: Array[float] = []


func _ready() -> void:
	_settings = get_node_or_null("/root/VoiceSettings")


func configure(rules: VoiceRules) -> void:
	_rules = rules


func is_active() -> bool:
	return _active


func current_intensity() -> float:
	return _intensity if _hold_mode else _window_average


func current_tier() -> int:
	return _tier


## 实时档位（仅供声量条显示；最终档位由 tier_locked 给出）。
func live_tier() -> int:
	return _live_tier


## 提前结束窗口（上课打断 / 关闭模式 / 离开办公室）：按已采内容锁定档位。
func finish_now() -> void:
	if not _active:
		return
	if _hold_mode:
		_finish_hold()
	else:
		_finish_mic()


## 开始一次谈话的声量窗口。hold_mode = true 时等待按住/松手；否则自动采样麦克风。
## 返回 false = 麦克风不可用（调用方按平常档结算，不阻塞谈话）。
func begin_window(hold_mode: bool) -> bool:
	_hold_mode = hold_mode
	_active = true
	_sampling = false
	_prompt_left = _rules.prompt_seconds
	_sample_left = _rules.window_seconds
	_hold_seconds = 0.0
	_sample_sum = 0.0
	_recent_values.clear()
	_recent_times.clear()
	_sample_elapsed = 0.0
	_window_average = 0.0
	_median_values.clear()
	_intensity = 0.0
	_live_tier = 1
	_tier = 2
	if not hold_mode and not _ensure_mic():
		_active = false
		mic_failed.emit("麦克风不可用")
		return false
	return true


func end_hold() -> void:
	if _active and _hold_mode:
		_finish_hold()


func abort_window() -> void:
	_active = false
	_sampling = false
	_hold_seconds = 0.0
	_sample_sum = 0.0
	_recent_values.clear()
	_recent_times.clear()
	_sample_elapsed = 0.0
	_window_average = 0.0
	_release_mic()


func _process(delta: float) -> void:
	if _calibrating:
		_process_calibration(delta)
		return
	if not _active:
		return
	if _prompt_left > 0.0:
		_prompt_left -= delta
		if _prompt_left > 0.0:
			return
		_prompt_left = 0.0
		_sampling = true
		return
	if _hold_mode:
		_hold_seconds += delta
		_intensity = _rules.intensity_for_hold(_hold_seconds)
		_live_tier = _rules.tier_with_hysteresis(_intensity, _live_tier)
		intensity_changed.emit(_intensity)
		if _hold_seconds >= _rules.window_seconds:
			_finish_hold()
		return
	_sample_left -= delta
	var rms := _read_mic_rms()
	var profile := _profile_values()
	var raw := _rules.intensity_for_rms(rms, profile[0], profile[1], profile[2])
	_process_mic_sample(raw, delta)
	if _sample_left <= 0.0:
		_finish_mic()


## 麦克风强度平滑：中值滤波去单帧尖峰，再做非对称 EMA；实时档位带回差。
## 单独抽出来供无麦克风测试直接喂样本。
func _process_mic_sample(value: float, delta: float) -> void:
	_median_values.append(clampf(value, 0.0, 100.0))
	while _median_values.size() > _rules.mic_median_frames:
		_median_values.pop_front()
	var sorted_values := _median_values.duplicate()
	sorted_values.sort()
	var target := float(sorted_values[sorted_values.size() / 2])
	var tau := _rules.mic_attack_seconds if target > _intensity else _rules.mic_release_seconds
	var alpha := 1.0 - exp(-maxf(delta, 0.0) / maxf(tau, 0.001))
	_intensity = lerpf(_intensity, target, clampf(alpha, 0.0, 1.0))
	# 滑动窗口平均：只看最近 mic_average_seconds，避免整窗均值被前段安静拖住。
	_sample_elapsed += maxf(delta, 0.0)
	_recent_values.append(_intensity)
	_recent_times.append(_sample_elapsed)
	_sample_sum += _intensity
	var cutoff := _sample_elapsed - _rules.mic_average_seconds
	while not _recent_times.is_empty() and _recent_times[0] < cutoff:
		_sample_sum -= _recent_values.pop_front()
		_recent_times.pop_front()
	_window_average = _sample_sum / float(_recent_values.size())
	_live_tier = _rules.tier_with_hysteresis(_window_average, _live_tier)
	intensity_changed.emit(_window_average)


func _finish_hold() -> void:
	if not _active:
		return
	_tier = _live_tier
	_active = false
	_release_mic()
	tier_locked.emit(_tier)


func _finish_mic() -> void:
	if not _active:
		return
	# 取最近 mic_average_seconds 的平滑平均值定档：不看峰值，也不看最后一帧。
	if _recent_values.is_empty() or _window_average < 5.0:
		_tier = 2  # 没听到声音：按平常，不因设备故障惩罚
	else:
		_tier = _live_tier
	_active = false
	_release_mic()
	tier_locked.emit(_tier)


func _profile_values() -> Array[float]:
	var floor := DEFAULT_FLOOR
	var ref := DEFAULT_REF
	var shout := DEFAULT_SHOUT
	if _settings != null and _settings.has_method("calibration"):
		var data: Dictionary = _settings.calibration()
		floor = float(data.get("floor", floor))
		ref = float(data.get("ref", ref))
		shout = float(data.get("shout", shout))
	return [floor, ref, shout]


# ------------------------------------------------------------------ 麦克风
## Godot 4.7 的输入设备 API：直接读输入帧，不需要额外总线，也不会回授。
func _ensure_mic() -> bool:
	if _mic_active:
		return true
	if OS.get_name() == "Android" and not OS.get_granted_permissions().has(MIC_PERMISSION):
		return false
	var err := AudioServer.set_input_device_active(true)
	if err != OK:
		return false
	_mic_active = true
	# 丢掉设备刚启动时积压的旧帧，避免上一窗口的尾音被算进本次窗口。
	var stale := AudioServer.get_input_frames_available()
	if stale > 0:
		AudioServer.get_input_frames(stale)
	return true


func _release_mic() -> void:
	if not _mic_active:
		return
	AudioServer.set_input_device_active(false)
	_mic_active = false


func _read_mic_rms() -> float:
	if not _mic_active:
		return 0.0
	var frames := AudioServer.get_input_frames_available()
	if frames <= 0:
		return 0.0
	var cap := int(AudioServer.get_input_mix_rate() * 0.2)
	if frames > cap:
		frames = cap
	var buffer := AudioServer.get_input_frames(frames)
	if buffer.is_empty():
		return 0.0
	var total := 0.0
	for sample in buffer:
		total += sample.x * sample.x + sample.y * sample.y
	return sqrt(total / float(buffer.size() * 2))


# ------------------------------------------------------------------ 校准
## 三步：安静 / 平常音量 / 最大声。只累计 RMS，不保存音频。
func begin_calibration() -> bool:
	if not _ensure_mic():
		calibration_failed.emit("麦克风不可用或未授权")
		return false
	_calibrating = true
	_calibration_step = 0
	_calibration_values.clear()
	_start_calibration_step()
	return true


func cancel_calibration() -> void:
	_calibrating = false
	_release_mic()


func _start_calibration_step() -> void:
	_calibration_left = _rules.calib_seconds(_calibration_step)
	_calibration_sum = 0.0
	_calibration_count = 0
	calibration_step.emit(_calibration_step)


func _process_calibration(delta: float) -> void:
	var rms := _read_mic_rms()
	_calibration_sum += rms
	_calibration_count += 1
	calibration_level.emit(rms)
	_calibration_left -= delta
	if _calibration_left > 0.0:
		return
	_calibration_values.append(_calibration_sum / maxf(1.0, float(_calibration_count)))
	if _calibration_step < 2:
		_calibration_step += 1
		_start_calibration_step()
		return
	_calibrating = false
	_release_mic()
	var floor: float = maxf(_calibration_values[0], 0.0001)
	var ref: float = _calibration_values[1]
	var shout: float = _calibration_values[2]
	if ref <= floor * 1.2:
		ref = maxf(floor * 2.0, DEFAULT_REF)
	if shout <= ref * 1.2:
		shout = ref * 2.2
	(
		calibration_finished
		. emit(
			{
				"floor": floor,
				"ref": ref,
				"shout": shout,
				"device": OS.get_name(),
				"noisy": floor > ref * 0.5,
			}
		)
	)


func _exit_tree() -> void:
	_release_mic()
