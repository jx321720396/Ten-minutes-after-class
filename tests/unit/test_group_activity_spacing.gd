extends GutTest

const SPACING = preload("res://scripts/game/group_activity_spacing.gd")


func test_far_pair_closes_to_configured_distance_without_moving_anchor() -> void:
	var anchor := Vector2(1, 1)
	var position := Vector2(1, 2.2)
	var target := SPACING.closer_target(position, anchor, 0.82)
	assert_almost_eq(target.distance_to(anchor), 0.82, 0.0001)
	assert_eq(anchor, Vector2(1, 1))
	assert_almost_eq(target.x, position.x, 0.0001)


func test_close_pair_does_not_expand_or_divide_by_zero() -> void:
	assert_eq(SPACING.closer_target(Vector2(0, 0.75), Vector2.ZERO, 0.82), Vector2(0, 0.75))
	assert_eq(SPACING.closer_target(Vector2.ZERO, Vector2.ZERO, 0.82), Vector2.ZERO)


func test_three_person_group_reserves_inflight_destinations() -> void:
	var target := Vector2(0.482, 0.6634)
	var occupied: Array[Vector2] = [Vector2.ZERO, Vector2(0, 1.2)]
	var empty: Array[Vector2] = []
	var reserved: Array[Vector2] = [Vector2(0, 0.82)]
	assert_true(SPACING.has_clearance(target, occupied, empty, 0.72))
	assert_false(SPACING.has_clearance(target, occupied, reserved, 0.72), "多人不能走向互相冲突的目标")
