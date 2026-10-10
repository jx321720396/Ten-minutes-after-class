class_name BehaviorContext
extends RefCounted
## 本局行为共享服务：不复制状态、不拥有 RNG，不依赖 UI/场景。
## 内核和注册表均弱引用，避免 RefCounted 所有权闭环。

var _core_ref: WeakRef
var _registry_ref: WeakRef


func _init(core: RefCounted) -> void:
	_core_ref = weakref(core)


func bind_registry(registry: RefCounted) -> void:
	_registry_ref = weakref(registry)


func is_bound() -> bool:
	return _core_ref != null and _core_ref.get_ref() != null


func affinity(i: int, j: int) -> float:
	return _core_ref.get_ref().affinity(i, j)


func hostility(i: int, j: int) -> float:
	return _core_ref.get_ref().hostility(i, j)


func trust(i: int, j: int) -> float:
	return _core_ref.get_ref().trust(i, j)


func stress(i: int) -> float:
	return _core_ref.get_ref().stress(i)


func dimension(i: int, dim: int) -> float:
	var core: Variant = _core_ref.get_ref()
	return core._dims[dim * core.node_count() + i]


func node_count() -> int:
	return _core_ref.get_ref().node_count()


func defer_for_player(kind: String, actor: int, target: int, options: Dictionary) -> bool:
	return _core_ref.get_ref()._player_invitations.intercept(kind, actor, target, options)


func player_choice(actor: int) -> Variant:
	return _core_ref.get_ref()._player_invitations.choice_for(actor)


func can_chat_in_space(i: int, j: int) -> bool:
	var core: Variant = _core_ref.get_ref()
	return not core.is_moving(i) and not core.is_moving(j) and core.chat_pair_in_range(i, j)


func threshold(key: String) -> float:
	return float(_core_ref.get_ref()._thresholds_lookup[key])


func apply_event(
	i: int, j: int, event_id: String, scale: float = 1.0, no_modulation: bool = false
) -> bool:
	return _core_ref.get_ref()._apply_event(i, j, event_id, scale, no_modulation)


func occupy(i: int, j: int, behavior: String, quiet: bool = false) -> void:
	_core_ref.get_ref()._occupy(i, j, behavior, quiet)


func observe(i: int, j: int, axis: String, weight: float = 1.0) -> void:
	_core_ref.get_ref()._observe(i, j, axis, weight)


func mark_hurt(perpetrator: int, victim: int) -> void:
	_core_ref.get_ref()._mark_hurt(perpetrator, victim)


func set_in_conversation(i: int, value: bool) -> void:
	_core_ref.get_ref()._in_conversation[i] = value


func random() -> float:
	return _core_ref.get_ref()._rng.random()


func global_tick() -> int:
	return int(_core_ref.get_ref().global_tick())


## 行为耗时（tick）—— 数值来自 behaviors.csv，组件不留常数。
func duration_of(behavior: String) -> int:
	return int(_core_ref.get_ref()._behaviors.get(behavior, {}).get("duration", 0))


## 某成员当前的「当前动作」（可能为 null；quiet 一方就是 null）。
func current_act_of(member: int) -> Variant:
	return _core_ref.get_ref()._current_act[member]


## 某成员的占用结束点（绝对 tick）。
func busy_until_of(member: int) -> int:
	return int(_core_ref.get_ref()._busy_until[member])


## 按成员列表占用：群聊用，全体占用与共同结束点对齐、声源只有一个。
func occupy_members(
	members: Array, behavior: String, until: int, sound_source: int, actor: int
) -> void:
	_core_ref.get_ref()._occupy_members(members, behavior, until, sound_source, actor)


## 真实共同活动：成立或并入（同一场活动只登记一次）。
func session_begin_or_join(kind: String, members: Array, end_tick: int) -> int:
	return int(_core_ref.get_ref()._sessions.begin_or_join(kind, members, end_tick))


func session_end_tick(session_id: int) -> int:
	return int(_core_ref.get_ref().session_end_tick(session_id))


func session_of(member: int) -> int:
	return int(_core_ref.get_ref().session_of(member))


func sessions_snapshot() -> Array:
	return _core_ref.get_ref().get_active_sessions()


func sigmoid(z: float) -> float:
	return _core_ref.get_ref()._sigmoid(z)


func join_probability(i: int, j: int) -> float:
	return _core_ref.get_ref()._join_probability(i, j)


func increment_stat(key: String) -> void:
	var stats: Dictionary = _core_ref.get_ref()._stats
	stats[key] = int(stats.get(key, 0)) + 1


func emit_event(type: String, payload: Dictionary) -> void:
	_core_ref.get_ref()._emit(type, payload)


func reduce_reporter_hostility(actor: int, target: int) -> void:
	# 保留旧举报回落的精确运算；集中数值迁移另行处理，不在结构重构中改公式。
	_core_ref.get_ref()._reduce_reporter_hostility(actor, target)


func execute_behavior(kind: StringName, actor: int, target: int, options: Dictionary = {}) -> bool:
	if _registry_ref == null or _registry_ref.get_ref() == null:
		push_warning("BehaviorContext：行为注册表已释放")
		return false
	return _registry_ref.get_ref().execute(kind, actor, target, options)


# ------------------------------------------------------------------ 纸条链（§8.6）共享服务
## 加权抽一个元素（转发内核 RNG 的 choices —— 与 Python 参考逐位一致的唯一入口）。
func weighted_pick(population: Array, weights: Array) -> int:
	return int(_core_ref.get_ref()._rng.choices(population, weights, 1)[0])


## [0, n) 均匀整数（CPython `_randbelow` 语义，与 Python 的 `randrange` 对齐）。
func rand_below(n: int) -> int:
	return int(_core_ref.get_ref()._rng.randbelow(n))


## 新建一张纸条，返回其编号（**不消耗 RNG**）。
func note_create(author: int, target: int, tone: int, template: int, holder: int) -> int:
	return int(_core_ref.get_ref()._note_create(author, target, tone, template, holder))


## 某张纸条的只读快照（不存在返回空字典）。
func note_row(note_id: int) -> Dictionary:
	return _core_ref.get_ref()._note_row(note_id)


## 纸条转手：`prev` 把纸条递给了 `new_holder`。
func note_pass_on(note_id: int, prev: int, new_holder: int) -> void:
	_core_ref.get_ref()._note_pass_on(note_id, prev, new_holder)


## 销毁一张纸条（看完撕掉 / 不看撕掉 / 走到头）。
func note_destroy(note_id: int) -> void:
	_core_ref.get_ref()._note_destroy(note_id)


## 座位邻居（§9.1 八邻域），只读。
func neighbors_of(i: int) -> Array:
	return _core_ref.get_ref()._neighbor_idx[i]


## 该角色此刻是否可被交互（未睡、未被占用）。
func can_interact_with(j: int) -> bool:
	return bool(_core_ref.get_ref()._can_interact_with(j))


## §4.5 选择侧统一公式：`p = σ((Σ w·d + w_stress·(Stress−50)/50 − θ)/scale)`。
## 未登记的 (event, option) 退回 0.5（与 Python 参考的兜底一致）。
func choice_prob(event: String, option: String, i: int) -> float:
	return float(_core_ref.get_ref()._choice_prob(event, option, i))


# ------------------------------------------------------------------ 只读读取（观察用，§10.3.1）
## 当前是第几天（信息里要记「记录于当时」）。
func day() -> int:
	return int(_core_ref.get_ref()._day)


## 目标自己的透明度 O（§7.2 的分档依据）。
func opacity(i: int) -> float:
	return float(_core_ref.get_ref().opacity(i))


## 信念：**i 眼中「j 对 i」**的那个轴（可能是错的，§7.4）。
func belief_axis(i: int, j: int, axis: String) -> float:
	var core: Variant = _core_ref.get_ref()
	var n := int(core.node_count())
	match axis:
		"hostility":
			return float(core._b_h[i * n + j])
		"trust":
			return float(core._b_t[i * n + j])
	return float(core._b_a[i * n + j])
