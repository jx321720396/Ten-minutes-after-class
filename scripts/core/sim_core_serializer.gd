class_name SimCoreSerializer
extends RefCounted
## SimCore 序列化：导出 / 恢复内核完整运行时状态（存档最小闭环）。
##
## 拆出独立类的原因：`sim_core.gd` 已触 gdlint 的 max-file-lines / max-public-methods 上限，
## 序列化与模拟本体解耦。本类只读 / 只写 SimCore 字段（GDScript 无真私有，下划线成员可见），
## 不引用 UI / autoload；配置指纹只读 data/（由调用方传入 tables）。
##
## 恢复路径契约：先 `SimCore.new(seed, n, tables)` 确定性重建初始态，再 `restore_state`
## 覆盖全部可变运行时态；版本 / 配置指纹 / seed / 人数不一致则拒绝。JSON 往返把 int 变
## float、Vector2i 变字符串，恢复时逐个还原。

const CONTENT_VERSION := 1


## 配置指纹：对本局消费的全部 CSV 表做「表名排序 + 行内字段排序」的 sha256 摘要。
## 恢复时与导出时比对，不一致说明数据表已变、旧档不兼容，拒绝恢复。
static func config_fingerprint(tables: Dictionary) -> String:
	var names: Array = tables.keys()
	names.sort()
	var parts := PackedStringArray()
	for name in names:
		var table: Variant = tables[name]
		if not (table is Dictionary):
			continue
		parts.append("[" + str(name) + "]")
		for row in table.get("rows", []):
			if not (row is Dictionary):
				continue
			var fields: Array = row.keys()
			fields.sort()
			var line := ""
			for field in fields:
				line += "%s=%s;" % [str(field), str(row[field])]
			parts.append(line)
	return "\n".join(parts).sha256_text()


## 导出内核完整运行时状态（存档用）。配置 / 派生索引 / 表现层瞬态不存（由构造 + seed 重建）。
static func export_state(core: SimCore) -> Dictionary:
	return {
		"version": CONTENT_VERSION,
		"seed": core._seed,
		"n": core._n,
		"config_fingerprint": core._config_fingerprint,
		"rng": core._rng.export_state(),
		# 关系 / 个体状态（float64 平铺）
		"a": Array(core._a),
		"h": Array(core._h),
		"stress": Array(core._stress),
		"grade": Array(core._grade),
		"study_acc": Array(core._study_acc),
		"vitality": Array(core._vitality),
		"gain_today": Array(core._gain_today),
		"volume": core._volume,
		# 时间游标
		"day": core._day,
		"phase": core._phase,
		"tick_in_phase": core._tick_in_phase,
		"phase_index": core._phase_index,
		"global_tick": core._global_tick,
		"phase_setup_done": core._phase_setup_done,
		"settled_boundary": [core._settled_boundary.x, core._settled_boundary.y],
		# 运行态（每节点 / 组）
		"seat_of": core._seat_of.duplicate(),
		"current_act": core._current_act.duplicate(),
		"sleeping": core._sleeping.duplicate(),
		"in_conversation": core._in_conversation.duplicate(),
		"conversations": core._conversations.duplicate(true),
		"conv_of": _ref_indices(core._conv_of, core._conversations),
		"rough_groups": core._rough_groups.duplicate(true),
		"rough_of": _ref_indices(core._rough_of, core._rough_groups),
		"study_groups": core._study_groups.duplicate(true),
		"study_of": _ref_indices(core._study_of, core._study_groups),
		"snack_groups": core._snack_groups.duplicate(true),
		"snack_of": _ref_indices(core._snack_of, core._snack_groups),
		"snack_provider": core._snack_provider.duplicate(),
		"share_units": _share_units_to_array(core._share_units),
		"joined_tick": core._joined_tick.duplicate(),
		"study_start_tick": core._study_start_tick.duplicate(),
		"busy_until": core._busy_until.duplicate(),
		"busy_phase": core._busy_phase.duplicate(),
		"busy_act": core._busy_act.duplicate(),
		"knot_days": core._knot_days.duplicate(),
		"resting": core._resting.duplicate(),
		"book": core._book.duplicate(),
		"broken": core._broken.duplicate(),
		"phase_state": core._phase_state.duplicate(),
		"settle_acc": core._settle_acc.duplicate(),
		"phase_stopped": core._phase_stopped.duplicate(),
		"stats": core._stats.duplicate(true),
		"settled": core._settled.duplicate(true),
		# 子组件
		"teacher": core._teacher.export_state(),
		"passives": core._passives.export_state(),
		"teacher_commands": core._teacher_commands.export_state(),
		"harm_events": core._harm_events.export_state(),
		"risk": core._risk.export_state(),
		"exam": core._exam.export_state(),
		"term_record": core._term_record.export_state(),
		"sessions": core._sessions.export_state(),
	}


## 回填内核运行时状态（读档用）。版本 / 配置指纹 / seed / 人数不一致则拒绝。
static func restore_state(core: SimCore, data: Dictionary) -> bool:
	if int(data.get("version", 0)) != CONTENT_VERSION:
		push_warning("SimCore：内核存档版本不一致，拒绝恢复。")
		return false
	if str(data.get("config_fingerprint", "")) != core._config_fingerprint:
		push_warning("SimCore：配置指纹不一致（数据表已变），拒绝恢复。")
		return false
	if int(data.get("n", -1)) != core._n or int(data.get("seed", -1)) != core._seed:
		push_warning("SimCore：seed / 人数与存档不符，拒绝恢复。")
		return false
	core._rng.restore_state(data.get("rng", {}))
	core._a = PackedFloat64Array(data.get("a", []))
	core._h = PackedFloat64Array(data.get("h", []))
	core._stress = PackedFloat64Array(data.get("stress", []))
	core._grade = PackedFloat64Array(data.get("grade", []))
	core._study_acc = PackedFloat64Array(data.get("study_acc", []))
	core._vitality = PackedFloat64Array(data.get("vitality", []))
	core._gain_today = PackedFloat64Array(data.get("gain_today", []))
	core._volume = float(data.get("volume", 0.0))
	core._day = int(data.get("day", 1))
	core._phase = str(data.get("phase", "break"))
	core._tick_in_phase = int(data.get("tick_in_phase", 0))
	core._phase_index = int(data.get("phase_index", 0))
	core._global_tick = int(data.get("global_tick", 0))
	core._phase_setup_done = bool(data.get("phase_setup_done", false))
	var sb: Array = data.get("settled_boundary", [-1, -1])
	core._settled_boundary = Vector2i(int(sb[0]), int(sb[1]))
	core._seat_of = _strs(data.get("seat_of", []))
	core._current_act = _nullable_strs(data.get("current_act", []))
	core._sleeping = _bools(data.get("sleeping", []))
	core._in_conversation = _bools(data.get("in_conversation", []))
	core._conversations = _groups_from(data.get("conversations", []))
	core._conv_of = _relink(data.get("conv_of", []), core._conversations)
	core._rough_groups = _groups_from(data.get("rough_groups", []))
	core._rough_of = _relink(data.get("rough_of", []), core._rough_groups)
	core._study_groups = _groups_from(data.get("study_groups", []))
	core._study_of = _relink(data.get("study_of", []), core._study_groups)
	core._snack_groups = _groups_from(data.get("snack_groups", []))
	core._snack_of = _relink(data.get("snack_of", []), core._snack_groups)
	core._snack_provider = _nullable_ints(data.get("snack_provider", []))
	core._share_units = _share_units_from(data.get("share_units", {}))
	core._joined_tick = _ints(data.get("joined_tick", []))
	core._study_start_tick = _ints(data.get("study_start_tick", []))
	core._busy_until = _ints(data.get("busy_until", []))
	core._busy_phase = _ints(data.get("busy_phase", []))
	core._busy_act = _nullable_strs(data.get("busy_act", []))
	core._knot_days = _ints(data.get("knot_days", []))
	core._resting = _bools(data.get("resting", []))
	core._book = _ints(data.get("book", []))
	core._broken = _bools(data.get("broken", []))
	core._phase_state = _strs(data.get("phase_state", []))
	core._settle_acc = _floats(data.get("settle_acc", []))
	core._phase_stopped = _bools(data.get("phase_stopped", []))
	core._stats = {}
	for key in data.get("stats", {}):
		core._stats[str(key)] = int(data["stats"][key])
	core._settled = data.get("settled", {}).duplicate(true)
	core._teacher.restore_state(data.get("teacher", {}))
	core._passives.restore_state(data.get("passives", {}))
	core._teacher_commands.restore_state(data.get("teacher_commands", {}))
	core._harm_events.restore_state(data.get("harm_events", {}))
	core._risk.restore_state(data.get("risk", {}))
	core._exam.restore_state(data.get("exam", {}))
	core._term_record.restore_state(data.get("term_record", {}))
	core._sessions.restore_state(data.get("sessions", {}))
	core._build_neighbor_idx()
	return true


## 组引用 → 组下标（身份比较；null / 不在组内 → -1）。存档不直接存 dict 引用，存下标再重建。
static func _ref_indices(of: Array, groups: Array) -> Array:
	var out: Array = []
	for ref in of:
		out.append(_index_of_ref(groups, ref))
	return out


static func _index_of_ref(groups: Array, target: Variant) -> int:
	for idx in range(groups.size()):
		if is_same(groups[idx], target):
			return idx
	return -1


## 组下标 → 组引用（读档时把 dict 引用重新接回组列表）。
static func _relink(indices: Array, groups: Array) -> Array:
	var out: Array = []
	for idx in indices:
		var i := int(idx)
		out.append(groups[i] if i >= 0 and i < groups.size() else null)
	return out


static func _groups_from(raw: Array) -> Array:
	var out: Array = []
	for group in raw:
		if not (group is Dictionary):
			out.append(group)
			continue
		var g: Dictionary = {}
		for key in group:
			if key == "members":
				g[key] = _ints(group[key])
			elif key == "provider":
				g[key] = int(group[key])
			else:
				g[key] = group[key]
		out.append(g)
	return out


static func _share_units_to_array(share_units: Dictionary) -> Dictionary:
	var out := {}
	for key in share_units:
		out["%d,%d" % [int(key.x), int(key.y)]] = int(share_units[key])
	return out


static func _share_units_from(raw: Dictionary) -> Dictionary:
	var out := {}
	for key in raw:
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() != 2:
			continue
		out[Vector2i(int(parts[0]), int(parts[1]))] = int(raw[key])
	return out


static func _ints(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(int(v))
	return out


static func _floats(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(float(v))
	return out


static func _bools(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(bool(v))
	return out


static func _strs(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(str(v))
	return out


static func _nullable_strs(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(null if v == null else str(v))
	return out


static func _nullable_ints(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(null if v == null else int(v))
	return out
