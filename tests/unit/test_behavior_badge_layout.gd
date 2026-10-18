extends GutTest


class HeadActors:
	extends Node3D
	var head := Vector3(0, 1, 0)

	func head_position_of(_index: int) -> Vector3:
		return head


func test_badge_centers_on_current_head_for_each_text_width() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1, 6)
	camera.current = true
	var actors := HeadActors.new()
	world.add_child(actors)
	var presenter := BehaviorBadgePresenter.new()
	add_child_autofree(presenter)
	presenter.set_process(false)
	presenter.bind_actors(actors)
	var badge := Label.new()
	presenter.add_child(badge)
	presenter._activity_badges[0] = badge
	for text in ["在听音乐", "在看课外书"]:
		badge.text = text
		for head in [Vector3(0, 1, 0), Vector3(1, 0.7, -2)]:
			actors.head = head
			presenter._layout()
			var projected := camera.unproject_position(head)
			var center := badge.position.x + badge.size.x * badge.scale.x * 0.5
			assert_almost_eq(center, projected.x, 0.01, "文字中心跟随人物头顶")
			assert_lt(badge.position.y + badge.size.y * badge.scale.y, projected.y)
	actors.head = Vector3(0, 1, 10)
	presenter._layout()
	assert_false(badge.visible, "相机后方状态不显示")


func test_head_anchor_switches_between_actual_seated_and_standing_sprites() -> void:
	var actors = autofree(load("res://scripts/game/classroom_actors.gd").new())
	var actor := Node3D.new()
	add_child_autofree(actor)
	actor.position = Vector3(2, 0, -3)
	actors._actor_by_index.append(actor)
	var image := Image.create(10, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var standing := Sprite3D.new()
	standing.name = "Sprite"
	standing.texture = texture
	standing.pixel_size = 0.1
	standing.position.y = 1.0
	actor.add_child(standing)
	var pose := Node3D.new()
	actor.add_child(pose)
	actors._seated_poses[0] = pose
	var upper := Sprite3D.new()
	upper.name = "Upper"
	upper.texture = texture
	upper.pixel_size = 0.05
	upper.position = Vector3(0.2, 0.8, 0.4)
	pose.add_child(upper)
	assert_almost_eq(actors.head_position_of(0), Vector3(2, 2, -3), Vector3.ONE * 0.001)
	standing.hide()
	assert_almost_eq(actors.head_position_of(0), Vector3(2.2, 1.3, -2.6), Vector3.ONE * 0.001)
	actor.position.x += 1.0
	assert_almost_eq(actors.head_position_of(0), Vector3(3.2, 1.3, -2.6), Vector3.ONE * 0.001)
