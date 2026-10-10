extends GutTest
## 纸条链（§8.6）内核侧：组件注册 / 纸条实体 / 玩家分步 API / 段末销毁 / §4.5 判定。
##
## 分步 API 的由来：UI（§21.2.9）的「看不看」与「去向」是**两次**决策，
## 所以内核提供 read_note() + finish_note()，而 respond_note() 只是两者的组合。

const NODES := 16


func _core(seed_num: int = 12345) -> SimCore:
	return SimCore.from_npc(seed_num, NODES, ConfigLoader.new().load_all())


## 玩家是最后一个节点（NPC 数另计：16 NPC -> 17 个节点）
func _player(c: SimCore) -> int:
	return int(c.node_count()) - 1


func test_pass_note_component_is_registered() -> void:
	var c := _core()
	assert_true(c._behavior_registry.has_behavior(&"pass_note"), "纸条组件已注册")
	assert_not_null(c._behavior_registry.component(&"pass_note"), "可取出组件实例")


func test_new_core_has_no_notes_and_zeroed_stats() -> void:
	var c := _core()
	assert_eq(c._notes.size(), 0, "开局没有活跃纸条")
	assert_eq(int(c._stats["notes_written"]), 0)
	assert_eq(int(c._stats["notes_read"]), 0)
	assert_eq(int(c._stats["notes_destroyed"]), 0)


func test_note_row_is_a_snapshot_not_a_live_reference() -> void:
	var c := _core()
	var note_id := c._note_create(0, 1, -1, 2, _player(c))
	var row := c._note_row(note_id)
	assert_eq(int(row["author"]), 0)
	assert_eq(int(row["target"]), 1)
	assert_eq(int(row["tone"]), -1)
	assert_eq(int(row["tpl"]), 2)
	assert_eq(int(row["holder"]), _player(c))
	assert_eq(int(row["prev"]), 0, "第一手是写纸条的人")
	assert_false(bool(row["read"]), "新纸条还没被读")
	var seen: Array = row["seen"]
	seen.append(99)
	assert_eq(c._note_row(note_id)["seen"].size(), 2, "快照可改，不影响内核")
	assert_true(c._note_row(123456).is_empty(), "不存在的纸条返回空字典")


func test_missing_note_id_is_safe() -> void:
	var c := _core()
	assert_true(c._note_row(999).is_empty())
	c._note_destroy(999)
	assert_eq(c._notes.size(), 0, "销毁不存在的纸条不报错")


func test_player_holding_note_is_reported_to_ui() -> void:
	var c := _core()
	assert_true(c.note_pending_for_player().is_empty(), "手上没有纸条")
	c._note_create(0, 1, 1, 0, _player(c))
	var pending := c.note_pending_for_player()
	assert_false(pending.is_empty(), "手上有一张纸条")
	assert_eq(int(pending["holder"]), _player(c))


func test_read_note_settles_once_and_marks_read() -> void:
	var c := _core()
	c._note_create(0, 1, -1, 0, _player(c))
	var affinity_before := c.affinity(_player(c), 1)
	assert_true(c.read_note(), "看纸条成功")
	assert_eq(int(c._stats["notes_read"]), 1, "记一次读过")
	assert_ne(c.affinity(_player(c), 1), affinity_before, "看纸条改了收件人对被说者的态度")
	assert_true(bool(c.note_pending_for_player()["read"]), "纸条仍在手上、标记为已读")
	assert_false(c.read_note(), "同一张纸条不重复结算")
	assert_eq(int(c._stats["notes_read"]), 1, "仍只有一次")


func test_read_note_without_note_is_refused() -> void:
	var c := _core()
	assert_false(c.read_note(), "手上没纸条时看不了")


func test_report_requires_having_read_it() -> void:
	var c := _core()
	c._note_create(3, 1, -1, 0, _player(c))
	var witness_before = c._witness_day[_player(c) * int(c.node_count()) + 3]
	assert_false(c.finish_note(false, true), "没看过不能举报")
	assert_eq(c._witness_day[_player(c) * int(c.node_count()) + 3], witness_before, "没看过不留把柄")
	assert_true(c.read_note(), "先看")
	assert_true(c.finish_note(false, true), "看完可以当场举报")
	assert_ne(c._witness_day[_player(c) * int(c.node_count()) + 3], witness_before, "把柄记给上一个递纸条的人")
	assert_eq(c._notes.size(), 0, "举报后纸条不再往下传")
	assert_eq(int(c._stats["notes_destroyed"]), 1)


func test_skip_and_destroy_needs_no_read() -> void:
	var c := _core()
	c._note_create(0, 1, -1, 0, _player(c))
	assert_true(c.finish_note(false, false), "不看也能直接撕掉")
	assert_eq(c._notes.size(), 0)
	assert_eq(int(c._stats["notes_read"]), 0, "没看不计数")


func test_finish_note_forward_hands_the_note_over() -> void:
	var c := _core()
	var note_id := c._note_create(0, 1, 1, 0, _player(c))
	assert_true(c.finish_note(true, false), "继续传")
	var row := c._note_row(note_id)
	assert_false(row.is_empty(), "纸条还在传递中")
	assert_eq(int(row["prev"]), _player(c), "上一手变成玩家")
	assert_ne(int(row["holder"]), _player(c), "已经不在玩家手上")
	assert_true((row["seen"] as Array).has(int(row["holder"])), "接手的人进入已经手集合")
	assert_eq(int(c._stats["notes_destroyed"]), 0)


func test_respond_note_is_the_composed_shortcut() -> void:
	var c := _core()
	c._note_create(0, 1, -1, 0, _player(c))
	assert_true(c.respond_note(true, false, false), "看 + 撕掉")
	assert_eq(int(c._stats["notes_read"]), 1)
	assert_eq(int(c._stats["notes_destroyed"]), 1)


func test_notes_do_not_survive_the_phase_boundary() -> void:
	var c := _core()
	c._note_create(0, 1, -1, 0, _player(c))
	assert_eq(c._notes.size(), 1)
	c.advance_phase()
	assert_eq(c._notes.size(), 0, "纸条只在当前时间段存活（§8.6）")


func test_choice_prob_reads_the_weight_table() -> void:
	var c := _core()
	var p := c._choice_prob("pass_note", "read", 0)
	assert_between(p, 0.0, 1.0, "选择侧公式给出概率")
	assert_eq(c._choice_prob("pass_note", "not_a_row", 0), 0.5, "未登记的选择退回 0.5")
	# 压力越高越不想看（表里 w_stress 为负）
	c._stress[0] = 0.0
	var low_stress := c._choice_prob("pass_note", "read", 0)
	c._stress[0] = 100.0
	assert_lt(c._choice_prob("pass_note", "read", 0), low_stress, "压力高更不想看纸条")


func test_same_seed_writes_the_same_notes() -> void:
	var a := _core(2026)
	var b := _core(2026)
	for _i in range(30):
		a.advance_tick()
		b.advance_tick()
	assert_eq(a._note_next_id, b._note_next_id, "同种子写出的纸条数一致")
	assert_eq(a._notes.size(), b._notes.size(), "同种子活跃纸条一致")
	for i in range(a._notes.size()):
		assert_eq(int(a._notes[i]["target"]), int(b._notes[i]["target"]), "被说的人一致")
		assert_eq(int(a._notes[i]["tone"]), int(b._notes[i]["tone"]), "话术方向一致")
