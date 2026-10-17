extends GutTest

const ROAM = preload("res://scripts/game/classroom_roam.gd")


class NeutralCore:
	extends RefCounted

	func affinity(_i: int, _j: int) -> float:
		return 0.0

	func hostility(_i: int, _j: int) -> float:
		return 0.0


func test_different_point_cannot_overlap_a_student() -> void:
	var roam = ROAM.new()
	roam.enabled = false
	roam._minimum_gap = 0.72
	add_child_autofree(roam)
	var actor := Node3D.new()
	add_child_autofree(actor)
	roam._actors.append(actor)
	roam._actor_count = 1
	roam._core = NeutralCore.new()
	roam._point_positions = {"near": Vector3(0.3, 0, 0)}
	# The candidate belongs to student 1; student 0 is physically beside it.
	assert_eq(roam._pick_point(1), "", "Separate point IDs must still respect body width")
	assert_false(
		roam._step_clear(Vector3(-2, 0, 0), Vector3(3, 0, 0), 1), "Large steps cannot tunnel"
	)
	assert_true(roam._step_clear(Vector3(0.2, 0, 0), Vector3(1, 0, 0), 1), "Allow separating")
	assert_false(
		roam._step_clear(Vector3(0.2, 0, 0), Vector3(0.1, 0, 0), 1), "Never squeeze closer"
	)
	actor.position = Vector3(5, 0, 0)
	roam._point_positions["reserved"] = Vector3.ZERO
	roam._occupant["reserved"] = 0
	assert_false(roam._point_clear(1, "near"), "Incoming students reserve surrounding space")
	roam._occupant.clear()
	assert_true(roam._point_clear(1, "near"), "Free points remain available")


func test_navigation_waits_without_advancing_through_a_student() -> void:
	var actor := Node3D.new()
	add_child_autofree(actor)
	var walker := ActorWalker.new()
	actor.add_child(walker)
	walker.set_process(false)
	walker.set("step_allowed", func(_from: Vector3, _to: Vector3) -> bool: return false)
	walker._start_path(PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0)]), 1.6)
	walker._advance_path(1.0)
	assert_almost_eq(actor.position.x, 0.0, 0.001, "Blocked path must wait")
	assert_true(walker.is_moving(), "Waiting retains its path and movement state")
	walker.set("step_allowed", Callable())
	walker._advance_path(2.0)
	assert_almost_eq(actor.position.x, 2.0, 0.001, "Clear path resumes to original destination")
