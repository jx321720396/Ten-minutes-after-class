class_name ExamSettle
extends RefCounted
## 周考与期末考（§19.1）。挂在跨天结算上，不改平时成绩，不消耗内核主随机数。
##
## 考分噪声用独立哈希流（与 tools/core_sim.py 的 exam_unit / exam_score 逐式对齐），
## 避免 Box-Muller 吃掉主 RNG 后把同种子对拍带偏。

var _days: Array[int] = []
var _sigma := 12.0
var _penalty := 15.0
var _progress_delta := 50.0
var _top_rank := 3
var _top_tokens := 1
var _grade_max := 750.0
var _term_days := 30
var _seed := 0
var _last_score: PackedFloat64Array = PackedFloat64Array()
var _tokens: PackedInt32Array = PackedInt32Array()
var _rank: PackedInt32Array = PackedInt32Array()
var _reports: Dictionary = {}
## D05：目标均分／考前加压／考后减压／考试当天只有考试。
## 目标按次配置：`exam_target_mean_<次序>`（次序与 `exam_day_<次序>` 对应，2026-10-18 起 450/480/500/520）。
## 该次没配则回落到 `exam_target_mean`；超出已配次数（如期末考）沿用最后一次的目标。
var _target_mean := 450.0
var _target_means: Array[float] = []
var _pre_bonus := 20.0
var _post_cut := 30.0
var _only_day := 1
var _means: Dictionary = {}
var _passed: Dictionary = {}


func configure(tables: Dictionary, seed_value: int, count: int, grade_max: float) -> void:
	_seed = seed_value
	_grade_max = grade_max
	_days.clear()
	_target_means.clear()
	for row in tables.get("rules/exam", {}).get("rows", []):
		var key := str(row.get("param", ""))
		var raw := str(row.get("value", ""))
		if key.begins_with("exam_day_"):
			_days.append(int(float(raw)))
		elif key.begins_with("exam_target_mean_"):
			var order := int(key.trim_prefix("exam_target_mean_"))
			while _target_means.size() < order:
				_target_means.append(NAN)
			_target_means[order - 1] = float(raw)
		elif key == "exam_noise_sigma":
			_sigma = float(raw)
		elif key == "exam_target_mean":
			_target_mean = float(raw)
		elif key == "pre_exam_stress_bonus":
			_pre_bonus = float(raw)
		elif key == "post_exam_stress_cut":
			_post_cut = float(raw)
		elif key == "exam_only_day":
			_only_day = int(float(raw))
		elif key == "stress_exam_penalty":
			_penalty = float(raw)
		elif key == "progress_prize_delta":
			_progress_delta = float(raw)
		elif key == "top_prize_rank":
			_top_rank = int(float(raw))
		elif key == "top_prize_tokens":
			_top_tokens = int(float(raw))
	_days.sort()
	for row in tables.get("rules/time_runtime", {}).get("rows", []):
		if str(row.get("key", "")) == "term_days":
			_term_days = int(float(str(row.get("value", "30"))))
	_last_score.resize(count)
	_tokens.resize(count)
	_rank.resize(count)
	_reports.clear()


func capture_baseline(grade: PackedFloat64Array) -> void:
	for i in grade.size():
		_last_score[i] = grade[i]


## D05：是否是考试日（周考日或期末考日）。
func is_exam_day(day: int) -> bool:
	return day == _term_days or _days.has(day)


## D05：是否是考试前一天（第七天为第八天的考前日）。
func is_exam_eve(day: int) -> bool:
	return is_exam_day(day + 1)


## D05：考试当天只有考试 —— 不发生普通事件与相关结算。
func exam_only_day() -> bool:
	return _only_day == 1


## 从当天起（含当天）最近的一次考试日（周考或期末考）；都已考完返回 0。
## 表现层用它做「下次考试还有几天 · 该次目标均分」的倒计时，不再写死第一次。
func next_exam_day(day: int) -> int:
	var all: Array[int] = _days.duplicate()
	all.append(_term_days)
	all.sort()
	for d in all:
		if d >= day:
			return d
	return 0


## 某次考试的目标均分（按次配置；超出次数沿用最后一次）。
func target_mean_for(day: int) -> float:
	return _target_mean_at(_index_of(day))


## 最近一次已出分考试的目标均分；还没考过时返回第 1 次的目标。
func target_mean() -> float:
	var best_day := -1
	for key in _means.keys():
		best_day = maxi(best_day, int(key))
	if best_day < 0:
		best_day = _days[0] if not _days.is_empty() else 1
	return target_mean_for(best_day)


func _target_mean_at(index: int) -> float:
	var configured := _target_means.size()
	if configured == 0:
		return _target_mean
	var value := _target_means[clampi(index, 1, configured) - 1]
	return _target_mean if is_nan(value) else value


func pre_stress_bonus() -> float:
	return _pre_bonus


func post_stress_cut() -> float:
	return _post_cut


## 某次考试的班级均分（未考过返回 0）。
func mean_of(day: int) -> float:
	return float(_means.get(day, 0.0))


## 最近一次已出分考试的日次（没考过返回 0）。
func last_exam_day() -> int:
	var best_day := -1
	for key in _means.keys():
		best_day = maxi(best_day, int(key))
	return best_day


## 最近一次已出分考试的班级均分（没考过返回 0）。
func last_exam_mean() -> float:
	var best_day := last_exam_day()
	if best_day < 0:
		return 0.0
	return float(_means[best_day])


## 某次考试是否达到目标均分（未考过按达标处理，避免误报辞退）。
func passed_of(day: int) -> bool:
	return bool(_passed.get(day, true))


## 最近一次已出分考试的达标情况；没考过返回 true。
func last_passed() -> bool:
	var best_day := -1
	for key in _passed.keys():
		best_day = maxi(best_day, int(key))
	if best_day < 0:
		return true
	return bool(_passed[best_day])


func banner(day: int) -> String:
	if day == _term_days:
		return "今天期末考"
	if _days.has(day):
		return "今天周考"
	return ""


func report_text(day: int) -> String:
	return str(_reports.get(day, ""))


func tokens_of(i: int) -> int:
	if i < 0 or i >= _tokens.size():
		return 0
	return _tokens[i]


func rank_of(i: int) -> int:
	if i < 0 or i >= _rank.size():
		return 0
	return _rank[i]


func last_score_of(i: int) -> float:
	if i < 0 or i >= _last_score.size():
		return 0.0
	return _last_score[i]


## 考试日才结算。返回是否真的考了。grade 只读，不写回。
func settle(
	day: int, grade: PackedFloat64Array, stress: PackedFloat64Array, names: PackedStringArray
) -> bool:
	var final_exam := day == _term_days
	if not final_exam and not _days.has(day):
		return false
	var n := grade.size()
	var scores: PackedFloat64Array = PackedFloat64Array()
	scores.resize(n)
	var exam_index := _index_of(day)
	for i in n:
		scores[i] = _score(grade[i], stress[i], exam_index, i)
	var order: Array[int] = []
	for i in n:
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			if scores[a] != scores[b]:
				return scores[a] > scores[b]
			return a < b
	)
	# D05：全班均分与**该次**目标均分考核 —— 不达标老师被辞退（考核结果只读，不改成绩）。
	var total := 0.0
	for i in n:
		total += scores[i]
	var mean := (total / float(n)) if n > 0 else 0.0
	_means[day] = mean
	_passed[day] = mean >= target_mean_for(day)
	for place in order.size():
		_rank[order[place]] = place + 1
	var player := n - 1
	var delta := scores[player] - _last_score[player]
	var progress := (not final_exam) and delta >= _progress_delta
	var top := _rank[player] <= _top_rank
	if top:
		_tokens[player] += _top_tokens
	for i in n:
		_last_score[i] = scores[i]
	_reports[day] = _write_report(
		final_exam, order, names, player, scores[player], delta, progress, top
	)
	return true


func _index_of(day: int) -> int:
	var all: Array[int] = _days.duplicate()
	all.append(_term_days)
	all.sort()
	return all.find(day) + 1


func _score(grade_value: float, stress_value: float, exam_index: int, node: int) -> float:
	var z := _quantized_normal(_seed, exam_index, node)
	var raw := grade_value + _rint(_sigma * z - _penalty * stress_value / 100.0)
	return clampf(raw, 0.0, _grade_max)


func _write_report(
	final_exam: bool,
	order: Array[int],
	names: PackedStringArray,
	player: int,
	player_score: float,
	delta: float,
	progress: bool,
	top: bool
) -> String:
	var top_names: PackedStringArray = PackedStringArray()
	var shown := mini(_top_rank, order.size())
	for k in shown:
		top_names.append(_display_name(order[k], names, player))
	var title := "这次期末考" if final_exam else "这次周考"
	var move := "和上次一样"
	if delta > 0.0:
		move = "比上次高了 %d 分" % int(_rint(delta))
	elif delta < 0.0:
		move = "比上次少了 %d 分" % int(_rint(-delta))
	var text := (
		"%s，前三名是 %s。你考了第 %d 名，分数 %d，%s。"
		% [
			title,
			"、".join(top_names),
			_rank[player],
			int(_rint(player_score)),
			move,
		]
	)
	if progress:
		text += "你这次进步很大，老师当众夸了你。"
	if top:
		text += "你考进了前三名，拿到了免罚卷。现在还派不上用场，先收着。"
	return text


func _display_name(index: int, names: PackedStringArray, player: int) -> String:
	if index == player:
		return "你"
	if index >= 0 and index < names.size() and not names[index].is_empty():
		return names[index]
	return "某同学"


## 与 core_sim.exam_unit 相同的 32 位混合，再做 Box-Muller，最后量化到 1e-6。
static func _quantized_normal(seed_value: int, exam_index: int, node: int) -> float:
	var u1 := _unit(seed_value, exam_index, node, 1)
	var u2 := _unit(seed_value, exam_index, node, 2)
	var z := sqrt(-2.0 * log(u1)) * cos(TAU * u2)
	return _q6(z)


static func _unit(seed_value: int, exam_index: int, node: int, salt: int) -> float:
	var x := _u32(seed_value)
	x = _u32(x ^ _u32(exam_index * 0x9E3779B1))
	x = _u32(x ^ _u32(node * 0x85EBCA6B))
	x = _u32(x ^ _u32(salt))
	x = _u32(x ^ (x >> 16))
	x = _u32(x * 0x7FEB352D)
	x = _u32(x ^ (x >> 15))
	x = _u32(x * 0x846CA68B)
	x = _u32(x ^ (x >> 16))
	return float(x + 1) / 4294967297.0


static func _u32(x: int) -> int:
	return x & 0xFFFFFFFF


static func _q6(z: float) -> float:
	var scaled := z * 1000000.0
	if z >= 0.0:
		return floor(scaled + 0.5) / 1000000.0
	return ceil(scaled - 0.5) / 1000000.0


static func _rint(v: float) -> int:
	var flr: float = floor(v)
	var frac: float = v - flr
	if frac > 0.5:
		return int(flr + 1.0)
	if frac < 0.5:
		return int(flr)
	if fmod(flr, 2.0) == 0.0:
		return int(flr)
	return int(flr + 1.0)


# ------------------------------------------------------------------ 存档
## 导出考试结算运行时状态（成绩基准 / 免罚卷 / 名次 / 报告 / 均值 / 通过）。
## _days / _sigma / _penalty 等是配置，由 configure 重建。
func export_state() -> Dictionary:
	return {
		"last_score": Array(_last_score),
		"tokens": Array(_tokens),
		"rank": Array(_rank),
		"reports": _reports.duplicate(true),
		"means": _means.duplicate(true),
		"passed": _passed.duplicate(true),
	}


## 回填考试结算状态（读档用）。_reports / _means / _passed 的 day 键经 JSON 变字符串，还原为 int。
func restore_state(data: Dictionary) -> void:
	_last_score = PackedFloat64Array(data.get("last_score", []))
	_tokens = PackedInt32Array(data.get("tokens", []))
	_rank = PackedInt32Array(data.get("rank", []))
	_reports = {}
	for key in data.get("reports", {}):
		_reports[int(key)] = str(data["reports"][key])
	_means = {}
	for key in data.get("means", {}):
		_means[int(key)] = float(data["means"][key])
	_passed = {}
	for key in data.get("passed", {}):
		_passed[int(key)] = bool(data["passed"][key])
