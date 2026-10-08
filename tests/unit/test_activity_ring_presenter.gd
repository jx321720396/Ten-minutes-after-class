extends GutTest
## 脚下活动圈呈现单测：个人圈同色、真实会话才融合、未揭晓不进融合、两组分开、结束还原。
##
## 依据：主文档 §10.31.4（只读查询）、§15.1；
##      docs/superpowers/plans/2026-10-07-activity-foot-rings.md、
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §8.2。
##
## ⚠️ 只验证**结构与只读性**，不断言像素：颜色与 shader 效果要人工看（计划 §10 已把
##    「逻辑通过」与「素材完整」分开验收）。

const SEED := 12345
const NPC := 8


## 呈现器必须进树（Node3D 的 global_position 只在树里有效）。
func _presenter(core: Variant) -> ActivityRingPresenter:
	var presenter: ActivityRingPresenter = add_child_autofree(ActivityRingPresenter.new())
	await get_tree().process_frame
	presenter.bind_core(core)
	return presenter


func _core() -> SimCore:
	return SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())


func _digest(core: SimCore) -> PackedByteArray:
	var values: Array = [core.get_active_sessions(), core._a, core._h, core._t]
	values.append(core.get_player_intel())
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(values))
	return hashing.finish()


func test_everyone_gets_a_personal_ring() -> void:
	var core := _core()
	var presenter: ActivityRingPresenter = await _presenter(core)
	presenter.refresh()
	assert_eq(presenter.personal_ring_count(), int(core.node_count()), "每个人一个个人圈")
	assert_eq(presenter.merged_region_count(), 0, "没有活动时没有融合区域")
	assert_false(presenter.is_merged(0), "不在会话里就不是融合区块")


func test_real_chat_becomes_one_merged_region() -> void:
	var core := _core()
	var presenter: ActivityRingPresenter = await _presenter(core)
	core._do_chat(0, 1)
	presenter.refresh()
	assert_true(presenter.is_merged(0), "0 号进了融合区域")
	assert_true(presenter.is_merged(1), "1 号也在同一块里")
	assert_false(presenter.is_merged(2), "旁观者不并入")
	assert_eq(presenter.merged_region_count(), 1, "一场活动一块连续区域（不是每人一个圈）")


func test_two_chat_pairs_are_two_separate_regions() -> void:
	var core := _core()
	var presenter: ActivityRingPresenter = await _presenter(core)
	core._do_chat(0, 1)
	core._do_chat(4, 5)
	presenter.refresh()
	assert_eq(presenter.merged_region_count(), 2, "两场闲聊必须分开画（不能按行为名并成一个圈）")
	assert_false(presenter.is_merged(2), "没参与的人不算在内")


func test_unrevealed_member_stays_a_personal_ring() -> void:
	var core := _core()
	var presenter: ActivityRingPresenter = await _presenter(core)
	core._do_chat(0, 1)
	core._do_chat(1, 2)
	assert_eq(core._sessions.snapshot(int(core.session_of(0)))["members"], [0, 1, 2], "三人一场")
	presenter.hide_member(2)
	presenter.refresh()
	assert_false(presenter.is_merged(2), "未揭晓的成员不进融合区域（不泄露结果）")
	assert_true(presenter.is_merged(0), "原组成员照旧可见")
	assert_true(presenter.is_merged(1), "原组成员照旧可见")
	presenter.show_member(2)
	presenter.refresh()
	assert_true(presenter.is_merged(2), "揭晓后进入同一块区域")


func test_session_end_restores_personal_rings() -> void:
	var core := _core()
	var presenter: ActivityRingPresenter = await _presenter(core)
	core._do_chat(0, 1)
	var session_id := int(core.session_of(0))
	presenter.refresh()
	assert_eq(presenter.merged_region_count(), 1)
	core._sessions.end(session_id)
	presenter.refresh()
	assert_eq(presenter.merged_region_count(), 0, "会话结束 → 融合区域收掉")
	assert_false(presenter.is_merged(0), "恢复个人圈")
	assert_eq(presenter.personal_ring_count(), int(core.node_count()), "个人圈一直在")


func test_merged_members_lose_their_personal_ring() -> void:
	var core := _core()
	var presenter: ActivityRingPresenter = await _presenter(core)
	core._do_chat(0, 1)
	presenter.refresh()
	assert_false(_ring_node(presenter, 0).visible, "融合后 0 号的个人圈取消（切换而非叠加）")
	assert_false(_ring_node(presenter, 1).visible, "融合后 1 号的个人圈取消")
	assert_true(_ring_node(presenter, 2).visible, "旁观者仍保留个人圈")
	var session_id := int(core.session_of(0))
	core._sessions.end(session_id)
	presenter.refresh()
	assert_true(_ring_node(presenter, 0).visible, "活动结束后个人圈恢复")


func _ring_node(presenter: ActivityRingPresenter, index: int) -> MeshInstance3D:
	var node := presenter.get_node_or_null("PersonalRing_%d" % index)
	assert_not_null(node, "个人圈节点 PersonalRing_%d 应存在" % index)
	return node as MeshInstance3D


func test_refresh_is_read_only() -> void:
	var core := _core()
	var presenter: ActivityRingPresenter = await _presenter(core)
	core._do_chat(0, 1)
	var before := _digest(core)
	presenter.refresh()
	presenter.hide_member(0)
	presenter.refresh()
	presenter.clear_hidden()
	assert_eq(_digest(core), before, "圈只读：不改会话、矩阵与线索日志")
	assert_false(presenter.is_hidden(0), "clear_hidden 后恢复可见")
