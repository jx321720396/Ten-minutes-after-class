extends GutTest
## 第 0 天报到日教程回归：配置、步骤机、说明卡、跳过、状态重置与存档拦截。

const CFG_PATH := "res://data/ui/tutorial.json"
const OVERLAY = preload("res://scenes/ui/tutorial_overlay.tscn")
const SEEN_TMP := "user://test_report_day_seen_tmp.dat"
const TUTORIAL_SEED := 20261019


func before_each() -> void:
	_cleanup_seen()
	GameState.tutorial_mode = false
	GameState.start_game(TUTORIAL_SEED, 16)


func after_each() -> void:
	GameState.tutorial_mode = false
	GameState.end_game()
	_cleanup_seen()


func _cleanup_seen() -> void:
	if FileAccess.file_exists(SEEN_TMP):
		DirAccess.remove_absolute(SEEN_TMP)


func _overlay() -> TutorialOverlay:
	var d: TutorialOverlay = OVERLAY.instantiate()
	d.seen_path = SEEN_TMP
	add_child_autofree(d)
	d.set_process(false)
	return d


func _close_intro(overlay: TutorialOverlay) -> void:
	for _i in range(3):
		overlay._on_next_pressed()


func test_config_has_report_day_shape() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	assert_eq(int(parsed.get("seed", 0)), TUTORIAL_SEED)
	assert_eq((parsed.get("intro_cards", []) as Array).size(), 3)
	assert_eq((parsed.get("steps", []) as Array).size(), 15)
	var info: Dictionary = parsed.get("info_cards", {})
	assert_eq(info.keys().size(), 2)
	assert_true(info.has("office_actions"))
	assert_true(info.has("class_actions"))


func test_tutorial_seed_is_fixed() -> void:
	assert_eq(TutorialOverlay.tutorial_seed(), TUTORIAL_SEED)


func test_intro_cards_close_and_emit() -> void:
	var overlay := _overlay()
	var closed := [false]
	overlay.intro_closed.connect(func(): closed[0] = true)
	overlay.start_first_run()
	assert_true(overlay.is_intro_open())
	_close_intro(overlay)
	assert_false(overlay.is_intro_open())
	assert_true(closed[0])
	assert_eq(str(overlay._current_step().get("id", "")), "t1_time")


func test_done_event_advances_only_matching_step() -> void:
	var overlay := _overlay()
	overlay.start_first_run()
	_close_intro(overlay)
	overlay.notify_event(&"profile_opened")  # t1 不匹配，不推进
	assert_eq(str(overlay._current_step().get("id", "")), "t1_time")
	overlay._advance()  # 进入 t2_profile
	assert_eq(str(overlay._current_step().get("id", "")), "t2_profile")
	overlay.notify_event(&"profile_opened")
	assert_eq(str(overlay._current_step().get("id", "")), "t3_stress")


func test_info_card_opens_and_closes() -> void:
	var overlay := _overlay()
	overlay.start_first_run()
	_close_intro(overlay)
	overlay._step_index = 10  # t11_office_info
	overlay._apply_step()
	assert_true(overlay.is_info_open())
	overlay._on_info_close()
	assert_false(overlay.is_info_open())
	assert_eq(str(overlay._current_step().get("id", "")), "t12_seat")


func test_skip_writes_seen_and_finishes() -> void:
	var overlay := _overlay()
	var finished := [false]
	overlay.tutorial_finished.connect(func(): finished[0] = true)
	overlay.start_first_run()
	overlay.skip()
	assert_false(overlay.is_running())
	assert_true(finished[0])
	assert_true(FileAccess.file_exists(SEEN_TMP))


func test_save_snapshot_blocked_in_tutorial_mode() -> void:
	GameState.tutorial_mode = true
	assert_false(GameState.save_snapshot())
	assert_true(GameState.tutorial_mode)


func test_finish_tutorial_resets_state() -> void:
	GameState.tutorial_mode = true
	var old_core: Variant = GameState.sim_core
	old_core._stress[0] = 80.0
	GameState.profile_notebook = {"current": {"dirty": 1}, "history": [], "seen": {}}
	GameState.finish_tutorial()
	assert_false(GameState.tutorial_mode)
	assert_eq(GameState.seed, TUTORIAL_SEED)
	assert_ne(GameState.sim_core, old_core)
	assert_lt(GameState.sim_core.stress(0), 80.0)
	assert_true(GameState.profile_notebook.current.is_empty())
