class_name Passives
extends RefCounted
## 公开专属被动（主文档 §10.2 / §10.4）。
##
## 只做两件事：知道「谁有哪条被动」（分配读 `data/rules/passives.csv`），
## 以及对一次结算算出被动修正（数值读 `data/rules/passive_params.csv`）。
## 名称与效果说明是表现层文案（`data/localization/passives.json`），由 UI 自己读 —— 内核不碰文案。
##
## 铁律：
##   · 角色编号只用于查分配表；本类不出现任何「按角色名 / 角色编号分支」的写法（主文档 §10.1）。
##   · 不消耗随机数：修正全是确定性的，不影响同种子可复现。
##   · 按真实完成事件结算（单位结算 / 自然完成 / 日结 / 训斥），不按画面帧或按钮点击。

const ASSIGN_TABLE := "rules/passives"
const PARAMS_TABLE := "rules/passive_params"

## 被动 id（与 data/rules/passives.csv 的 passive_id 一致）。
const FOCUS := "focus"
const ABSORB := "absorb"
const TALKATIVE := "talkative"
const SELF_DISCIPLINE := "self_discipline"
const OPTIMISTIC := "optimistic"
const MODERATE := "moderate"
const LIKABLE := "likable"
const FORGIVING := "forgiving"
const EMPATHETIC := "empathetic"
const RECEPTIVE := "receptive"
const STUDIOUS := "studious"
const TEAM_SPIRIT := "team_spirit"
const POSITIVE_FEEDBACK := "positive_feedback"
const SPRING := "spring"
const FRAGILE := "fragile"
const WELL_INFORMED := "well_informed"

var _params: Dictionary = {}
var _by_index: Array[String] = []
## 收放自如：累计原始损失 / 已实际扣除（跨行为中断与跨天保留，新局由 configure 清零）。
var _loss_total: Array[float] = []
var _loss_paid: Array[float] = []
## 弹簧：累计获得的压力 / 已兑换的动力次数（余量跨天保留，新局清零）。
var _spring_total: Array[float] = []
var _spring_paid: Array[float] = []


## character_ids 的顺序 = 内核节点索引顺序（SimCore 的 _chars）。
func configure(tables: Dictionary, character_ids: Array) -> void:
	_params.clear()
	for row in _rows(tables, PARAMS_TABLE):
		_params[str(row.get("param", ""))] = float(str(row.get("value", "0")))
	var assign: Dictionary = {}
	for row in _rows(tables, ASSIGN_TABLE):
		assign[str(row.get("character_id", ""))] = str(row.get("passive_id", ""))
	_by_index.clear()
	for index in range(character_ids.size()):
		_by_index.append(str(assign.get(str(character_ids[index]), "")))
	var count := character_ids.size()
	_loss_total = _zeros(count)
	_loss_paid = _zeros(count)
	_spring_total = _zeros(count)
	_spring_paid = _zeros(count)


## 该学生的被动 id（空串 = 本局没有分配到被动）。
func id_of(i: int) -> String:
	if i < 0 or i >= _by_index.size():
		return ""
	return _by_index[i]


func has(i: int, passive_id: String) -> bool:
	if i < 0 or i >= _by_index.size():
		return false
	return _by_index[i] == passive_id


# ------------------------------------------------------------------ 学习 / 游戏单位结算
## 学习单位：返回 {gain 学业收益, cost 动力消耗}。
## 专注翻倍收益增减 → 收放自如按累计整数减半损失 → 自律少耗动力（不改正收益）。
func study_unit(i: int, gain: float, vitality_cost: float) -> Dictionary:
	return {"gain": _gain(i, gain), "cost": _vitality_cost(i, vitality_cost)}


## 游戏状态单位：只需要修正学业收益（负收益同样受专注 / 收放自如影响）。
func play_gain(i: int, gain: float) -> float:
	return _gain(i, gain)


## 乐观：完成一次娱乐，压力单独额外 −3（返回负值；无被动返回 0.0）。
func leisure_completed(i: int) -> float:
	if not has(i, OPTIMISTIC):
		return 0.0
	return -_number("optimistic_stress_relief", 0.0)


# ------------------------------------------------------------------ 友善聊天完成
## 一次友善聊天完成时，`owner` 的被动对「owner → 对象」这一对子产生的增量。
## 返回 owner_affinity（本人对对象）/ other_affinity（对象对本人）/
## owner_hostility（负值：追加敌对修复）/ other_stress（负值：追加减压）。
func chat_completed(owner: int) -> Dictionary:
	var result := {
		"owner_affinity": 0.0, "other_affinity": 0.0, "owner_hostility": 0.0, "other_stress": 0.0
	}
	if has(owner, TALKATIVE):
		result.owner_affinity = _number("talkative_affinity_gain", 0.0)
	if has(owner, LIKABLE):
		result.other_affinity = _number("likable_affinity_gain", 0.0)
	if has(owner, FORGIVING):
		result.owner_hostility = -_number("forgiving_hostility_cut", 0.0)
	if has(owner, EMPATHETIC):
		result.other_stress = -_number("empathetic_stress_relief", 0.0)
	return result


# ------------------------------------------------------------------ 老师训斥
## 听劝：每受到一次老师训斥，动力额外 +10（压力仍按原有规则结算）。
func scolded(i: int) -> float:
	if not has(i, RECEPTIVE):
		return 0.0
	return _number("receptive_vitality_gain", 0.0)


# ------------------------------------------------------------------ 压力来源修正
## 邻座学习涓流：`source` 学习中 → `target` 加压。
## 卷王（来源）与玻璃心（目标）各自 +100%，**加法叠加**（5 点基础值双项 = 15，不是 20）。
func neighbor_drip(source: int, target: int, base: float) -> float:
	var ratio := 0.0
	if has(source, STUDIOUS):
		ratio += _number("studious_drip_bonus_ratio", 0.0)
	if has(target, FRAGILE):
		ratio += _number("fragile_stress_bonus_ratio", 0.0)
	return base * (1.0 + ratio)


## 同学来源的加压（伤害事件等）：目标有玻璃心时 +100%。只修正正向加压，不扩大到减压。
func peer_stress(target: int, base: float) -> float:
	if not has(target, FRAGILE):
		return base
	return base * (1.0 + _number("fragile_stress_bonus_ratio", 0.0))


## 弹簧：累计获得的压力每满一段（默认 5 点），动力额外 +2。返回本次应发放的动力。
func spring(i: int, gained: float) -> float:
	if not has(i, SPRING) or gained <= 0.0 or i >= _spring_total.size():
		return 0.0
	var per := maxf(1.0, _number("spring_stress_per_vitality", 1.0))
	_spring_total[i] += gained
	var target := floorf(_spring_total[i] / per)
	var award := target - _spring_paid[i]
	_spring_paid[i] = target
	if award <= 0.0:
		return 0.0
	return award * _number("spring_vitality_gain", 0.0)


# ------------------------------------------------------------------ 跨天结算
## 群策群力：日末一次，每有一名对本人好感严格超过阈值的同学，当天学业收益 +1。
func team_spirit_gain(i: int, teammates: int) -> float:
	if not has(i, TEAM_SPIRIT) or teammates <= 0:
		return 0.0
	return float(teammates) * _number("team_spirit_gain", 0.0)


func team_spirit_threshold() -> float:
	return _number("team_spirit_affinity_threshold", 0.0)


## 善于吸收：日结把净收益转为成绩时，净收益为正才额外加（每天一次 = 日结一处调用）。
func absorb_bonus(i: int, net_gain: float) -> float:
	if not has(i, ABSORB) or net_gain <= 0.0:
		return 0.0
	return _number("absorb_grade_bonus", 0.0)


## 正反馈：成绩实际提高时，每提高 1 点动力 +1（按提高量的整数部分；初始赋值不算提高）。
func grade_raised(i: int, raised: float) -> float:
	if not has(i, POSITIVE_FEEDBACK) or raised <= 0.0:
		return 0.0
	return floorf(raised) * _number("positive_feedback_vitality_per_grade", 0.0)


# ------------------------------------------------------------------ 只读展示
## 群策群力：可以看到所有其他同学对本人好感（档案只读展示，不写任何矩阵）。
func reveals_incoming_affinity(i: int) -> bool:
	return has(i, TEAM_SPIRIT)


## 百事通：一次打听提供的有向单轴关系信息条数上限（D10；普通打听上限见 teacher_commands.csv 的 ask_relation_max）。
func well_informed_messages(i: int) -> int:
	if not has(i, WELL_INFORMED):
		return 0
	return int(_number("well_informed_messages", 0.0))


# ------------------------------------------------------------------ 内部
func _gain(i: int, base: float) -> float:
	var value := base
	if has(i, FOCUS):
		value *= _number("focus_gain_multiplier", 1.0)
	if value < 0.0 and has(i, MODERATE):
		value = -_moderated_loss(i, -value)
	return value


## 收放自如：把本次原始损失并入累计，返回本次实际应扣的整数损失（不出现 0.5）。
## 累计口径：原本两次各损失 1 → 实际依次扣 0、1；原本一次损失 2 → 实际扣 1。
func _moderated_loss(i: int, loss: float) -> float:
	if loss <= 0.0 or i < 0 or i >= _loss_total.size():
		return loss
	var divisor := maxf(1.0, _number("moderate_loss_divisor", 1.0))
	_loss_total[i] += loss
	var target := floorf(_loss_total[i] / divisor)
	var delta := target - _loss_paid[i]
	_loss_paid[i] = target
	return delta


func _vitality_cost(i: int, cost: float) -> float:
	if not has(i, SELF_DISCIPLINE):
		return cost
	return maxf(0.0, cost - _number("self_discipline_cost_cut", 0.0))


func _number(key: String, fallback: float) -> float:
	return float(_params.get(key, fallback))


func _zeros(count: int) -> Array[float]:
	var values: Array[float] = []
	for _index in range(count):
		values.append(0.0)
	return values


func _rows(tables: Dictionary, name: String) -> Array:
	return tables.get(name, {}).get("rows", [])
