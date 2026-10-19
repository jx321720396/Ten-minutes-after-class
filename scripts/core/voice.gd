class_name VoiceRules
extends RefCounted
## 声量规则（可选挑战模式，2026-10-19）。
##
## 纯规则：只负责「声量强度 → 四档」「档位 → 倍率」「鼓励目标池 / 选人方式」。
## 不引用 UI、音频、场景或自动加载；麦克风 / 按住 / 设置开关都在表现层。
## 数据来自 `data/rules/voice.csv`；关闭声量模式时本类仍存在，但不会被结算使用。

const TIER_COUNT := 4

var window_seconds := 5.0
var prompt_seconds := 0.3
var voice_chat_seconds := 10.0
var mic_floor_ratio := 1.5
var mic_median_frames := 7
var mic_attack_seconds := 0.12
var mic_release_seconds := 0.35
var mic_average_seconds := 2.5
var tier_hysteresis := 4.0
var mic_gate_ratio := 0.15
var mic_shout_min_ratio := 2.2
var mic_shout_max_ratio := 4.0
var hold_curve_exp := 1.2
var duck_db := -12.0
var calib_floor_seconds := 1.5
var calib_ref_seconds := 2.0
var calib_shout_seconds := 1.5

var _tier_min: Array[float] = [0.0, 25.0, 50.0, 75.0]
var _tier_mult: Array[float] = [0.6, 1.0, 1.4, 1.7]
var _encourage_pool: Array[String] = ["neighbors", "all", "nearest3", "all"]
var _encourage_pick: Array[String] = ["nearest", "nearest", "affinity", "affinity"]


## 从 `rules/voice` 的原始表（含 param / value 行）读取；缺失或非法键回落默认值。
func configure_table(table: Dictionary) -> void:
	var values := {}
	for row in table.get("rows", []):
		var key := str(row.get("param", "")).strip_edges()
		if key != "":
			values[key] = str(row.get("value", "")).strip_edges()
	window_seconds = _num(values, "window_seconds", window_seconds)
	prompt_seconds = _num(values, "prompt_seconds", prompt_seconds)
	voice_chat_seconds = _num(values, "voice_chat_seconds", voice_chat_seconds)
	mic_floor_ratio = _num(values, "mic_floor_ratio", mic_floor_ratio)
	mic_median_frames = int(_num(values, "mic_median_frames", mic_median_frames))
	mic_attack_seconds = _num(values, "mic_attack_seconds", mic_attack_seconds)
	mic_release_seconds = _num(values, "mic_release_seconds", mic_release_seconds)
	mic_average_seconds = _num(values, "mic_average_seconds", mic_average_seconds)
	tier_hysteresis = _num(values, "tier_hysteresis", tier_hysteresis)
	mic_gate_ratio = _num(values, "mic_gate_ratio", mic_gate_ratio)
	mic_shout_min_ratio = _num(values, "mic_shout_min_ratio", mic_shout_min_ratio)
	mic_shout_max_ratio = _num(values, "mic_shout_max_ratio", mic_shout_max_ratio)
	hold_curve_exp = _num(values, "hold_curve_exp", hold_curve_exp)
	duck_db = _num(values, "duck_db", duck_db)
	calib_floor_seconds = _num(values, "calib_floor_seconds", calib_floor_seconds)
	calib_ref_seconds = _num(values, "calib_ref_seconds", calib_ref_seconds)
	calib_shout_seconds = _num(values, "calib_shout_seconds", calib_shout_seconds)
	for i in range(TIER_COUNT):
		var n := i + 1
		_tier_min[i] = _num(values, "tier%d_min" % n, _tier_min[i])
		_tier_mult[i] = _num(values, "tier%d_mult" % n, _tier_mult[i])
		_encourage_pool[i] = _str(values, "encourage_tier%d_pool" % n, _encourage_pool[i])
		_encourage_pick[i] = _str(values, "encourage_tier%d_pick" % n, _encourage_pick[i])
	_validate()


func _num(values: Dictionary, key: String, fallback: float) -> float:
	if not values.has(key):
		return fallback
	var text := str(values[key])
	if not text.is_valid_float():
		push_warning("VoiceRules：%s 不是数字（%s），使用 %.3f" % [key, text, fallback])
		return fallback
	return float(text)


func _str(values: Dictionary, key: String, fallback: String) -> String:
	if not values.has(key):
		return fallback
	var text := str(values[key])
	return text if text != "" else fallback


func _validate() -> void:
	if window_seconds <= 0.0:
		push_warning("VoiceRules：window_seconds 必须 > 0，使用 5.0")
		window_seconds = 5.0
	if prompt_seconds < 0.0:
		prompt_seconds = 0.0
	var min_chat := window_seconds + prompt_seconds
	if voice_chat_seconds <= min_chat:
		push_warning("VoiceRules：voice_chat_seconds 必须大于提示+采样窗口，使用 %.1f" % (min_chat + 1.0))
		voice_chat_seconds = min_chat + 1.0
	mic_floor_ratio = maxf(mic_floor_ratio, 0.0)
	mic_median_frames = maxi(1, mic_median_frames)
	if mic_median_frames % 2 == 0:
		mic_median_frames += 1
	mic_attack_seconds = maxf(mic_attack_seconds, 0.001)
	mic_release_seconds = maxf(mic_release_seconds, mic_attack_seconds)
	if mic_average_seconds < 0.5 or mic_average_seconds > window_seconds:
		push_warning("VoiceRules：mic_average_seconds 必须在 [0.5, window_seconds]，按区间修正")
		mic_average_seconds = clampf(mic_average_seconds, 0.5, window_seconds)
	tier_hysteresis = clampf(tier_hysteresis, 0.0, 12.4)
	mic_gate_ratio = clampf(mic_gate_ratio, 0.0, 1.0)
	mic_shout_min_ratio = maxf(mic_shout_min_ratio, 1.01)
	mic_shout_max_ratio = maxf(mic_shout_max_ratio, mic_shout_min_ratio)
	hold_curve_exp = maxf(hold_curve_exp, 0.01)
	for i in range(1, TIER_COUNT):
		if _tier_min[i] <= _tier_min[i - 1]:
			push_warning("VoiceRules：档位下限必须递增，修正 tier%d_min" % (i + 1))
			_tier_min[i] = _tier_min[i - 1] + 1.0
		if _tier_mult[i] < _tier_mult[i - 1]:
			push_warning("VoiceRules：档位倍率必须非递减，修正 tier%d_mult" % (i + 1))
			_tier_mult[i] = _tier_mult[i - 1]
	for i in range(TIER_COUNT):
		if _encourage_pool[i] not in ["neighbors", "all", "nearest3"]:
			push_warning("VoiceRules：未知鼓励目标池 %s，回落 all" % _encourage_pool[i])
			_encourage_pool[i] = "all"
		if _encourage_pick[i] not in ["nearest", "affinity"]:
			push_warning("VoiceRules：未知鼓励选人方式 %s，回落 nearest" % _encourage_pick[i])
			_encourage_pick[i] = "nearest"


## 连续声量 → 档位（1–4）。边界含在下限：24 → 1，25 → 2。
func tier_for_intensity(value: float) -> int:
	var tier := 1
	for i in range(TIER_COUNT):
		if value >= _tier_min[i]:
			tier = i + 1
	return tier


## 按住蓄力：t 秒 → 声量强度（0–100）。
func intensity_for_hold(seconds: float) -> float:
	var t := clampf(seconds / window_seconds, 0.0, 1.0)
	return 100.0 * pow(t, hold_curve_exp)


## 按住蓄力：t 秒 → 档位。
func tier_for_hold(seconds: float) -> int:
	return tier_for_intensity(intensity_for_hold(seconds))


## 麦克风 RMS → 声量强度（0–100），按校准得到的 floor / ref / shout 归一化。
func intensity_for_rms(rms: float, floor: float, ref: float, shout: float) -> float:
	if ref <= 0.0:
		return 0.0
	var gate := maxf(floor * mic_floor_ratio, ref * mic_gate_ratio)
	var sh := shout
	if sh <= 0.0:
		sh = ref * mic_shout_min_ratio
	sh = clampf(sh, ref * mic_shout_min_ratio, ref * mic_shout_max_ratio)
	if sh <= gate:
		return 0.0
	return clampf(100.0 * (rms - gate) / (sh - gate), 0.0, 100.0)


func tier_with_hysteresis(value: float, current: int, margin: float = -1.0) -> int:
	var h := tier_hysteresis if margin < 0.0 else margin
	var cur := clampi(current, 1, TIER_COUNT)
	var target := tier_for_intensity(value)
	if target > cur:
		return target if value >= tier_min(target) + h else cur
	if target < cur:
		return target if value < tier_min(cur) - h else cur
	return cur


func office_chat_seconds() -> int:
	return maxi(1, int(round(voice_chat_seconds)))


func mult_for(tier: int) -> float:
	return _tier_mult[clampi(tier, 1, TIER_COUNT) - 1]


func tier_min(tier: int) -> float:
	return _tier_min[clampi(tier, 1, TIER_COUNT) - 1]


func pool_for(tier: int) -> String:
	return _encourage_pool[clampi(tier, 1, TIER_COUNT) - 1]


func pick_for(tier: int) -> String:
	return _encourage_pick[clampi(tier, 1, TIER_COUNT) - 1]


func calib_seconds(step: int) -> float:
	match step:
		0:
			return calib_floor_seconds
		1:
			return calib_ref_seconds
		_:
			return calib_shout_seconds
