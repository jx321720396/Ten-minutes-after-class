extends GutTest

const FACING = preload("res://scripts/game/group_facing_presenter.gd")
const STYLE := {"min_depth_m": 0.25, "hysteresis_m": 0.08, "depth_to_side_ratio": 0.65}


func test_front_member_turns_back_and_rear_stays_front() -> void:
	var positions := {0: Vector2(0, 2), 1: Vector2(0, 1)}
	var sessions := [{"members": [0, 1]}]
	var result := FACING.back_members(sessions, positions, Vector2.UP, STYLE)
	assert_true(result.has(0))
	assert_false(result.has(1))
	assert_eq(positions, {0: Vector2(0, 2), 1: Vector2(0, 1)}, "只读站位")
	assert_eq(sessions, [{"members": [0, 1]}], "只读会话")


func test_side_by_side_and_separate_sessions_do_not_turn() -> void:
	var positions := {0: Vector2(-1, 0), 1: Vector2(1, 0), 2: Vector2(0, -3)}
	assert_eq(FACING.back_members([{"members": [0, 1]}], positions, Vector2.UP, STYLE), {})
	assert_eq(FACING.back_members([], positions, Vector2.UP, STYLE, {0: true}), {})


func test_view_direction_and_group_center_decide_facing() -> void:
	var positions := {0: Vector2(0, 2), 1: Vector2(-0.2, 1), 2: Vector2(0.2, 1)}
	var sessions := [{"members": [0, 1, 2]}]
	assert_eq(FACING.back_members(sessions, positions, Vector2.UP, STYLE), {0: true})
	assert_eq(FACING.back_members(sessions, positions, Vector2.DOWN, STYLE), {1: true, 2: true})


func test_small_position_changes_do_not_flicker() -> void:
	var sessions := [{"members": [0, 1]}]
	var positions := {0: Vector2(0, 0.2), 1: Vector2.ZERO}
	assert_eq(FACING.back_members(sessions, positions, Vector2.UP, STYLE), {})
	assert_eq(FACING.back_members(sessions, positions, Vector2.UP, STYLE, {0: true}), {0: true})
	positions[0] = Vector2(0, 0.1)
	assert_eq(FACING.back_members(sessions, positions, Vector2.UP, STYLE, {0: true}), {})


func test_missing_or_excluded_partner_does_not_turn() -> void:
	assert_eq(FACING.back_members([{"members": [0, 1]}], {0: Vector2.ZERO}, Vector2.UP, STYLE), {})
