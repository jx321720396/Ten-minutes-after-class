extends GutTest

const PROFILE = preload("res://scenes/ui/npc_profile.tscn")
const BOARD = preload("res://scenes/ui/clue_board.tscn")


func test_all_students_share_manifest_portraits_without_classroom_actors() -> void:
	var manifest: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/textures/characters/identity_v3/manifest.json")
	)
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/npc_profile.json")
	)
	assert_eq(config.portraits.size(), 16, "全班16人均须配置画像")
	var core := SimCore.new(12345, 16)
	var profile = PROFILE.instantiate()
	var board = BOARD.instantiate()
	add_child_autofree(profile)
	add_child_autofree(board)
	profile.bind_sources(core, null, null)
	board._core = core
	for entry in manifest:
		var index := -1
		for candidate in range(core.node_count()):
			if core.character_id(candidate) == entry.id:
				index = candidate
		assert_gte(index, 0, str(entry.name))
		if index < 0:
			continue
		assert_eq(core.alias(index), str(entry.name), "按当前16人ID与姓名映射")
		var portrait: Texture2D = profile._texture_for(index)
		var board_portrait: Texture2D = board._portrait(index)
		assert_true(portrait is AtlasTexture, "%s 须使用上半身裁切" % entry.name)
		assert_true(board_portrait is AtlasTexture, "%s 推理板须独立取图" % entry.name)
		if not portrait is AtlasTexture or not board_portrait is AtlasTexture:
			continue
		assert_eq(portrait.atlas.resource_path, str(entry.reference))
		assert_eq(board_portrait.atlas.resource_path, portrait.atlas.resource_path)
		assert_eq(board_portrait.region, portrait.region)
		var bounds := Rect2(Vector2.ZERO, portrait.atlas.get_size())
		assert_true(bounds.encloses(portrait.region), "裁切不出源图边界")
		assert_gt(portrait.region.size.x, 0.0)
		assert_gt(portrait.region.size.y, 0.0)
		assert_lt(portrait.region.size.y, portrait.atlas.get_height() * 0.6, "上半身画像不能缩放整张全身图")


func after_each() -> void:
	get_tree().paused = false


func test_missing_portrait_and_invalid_regions_return_no_texture() -> void:
	var portraits = load("res://scripts/ui/student_portraits.gd")
	assert_null(portraits.texture_for("missing", {}))
	var path := "res://assets/textures/characters/fullbody_v1/char_01_body_base_v1.webp"
	for region in [[0, 0, 0, 700], [-1, 0, 400, 700], [0, 0, 1025, 700], [0, 0]]:
		assert_null(
			portraits.texture_for("01", {"portraits": {"01": {"path": path, "region": region}}})
		)
