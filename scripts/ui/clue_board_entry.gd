extends CanvasLayer
## 原生场景入口；按日收集可见事件、日末归档，不创建任何界面节点。

const DATA = preload("res://scripts/ui/clue_board_data.gd")
var _model: RefCounted = DATA.new()
var _core: Variant
var _actors: Node
var _clock: Node
var _students: Array = []
var _owns_pause := false
var _shown_day := 1
var _latest_day := 1
var _daily_report := false


func _ready() -> void:
	$Board.close_requested.connect(close)
	$Board.day_requested.connect(show_day)
	$BoardButton.pressed.connect(open)
	EventBus.event_happened.connect(_on_event)
	EventBus.day_settled.connect(_on_settled)


func bind_sources(core: Variant, clock: Node, actors: Node) -> void:
	if is_instance_valid(_clock):
		if _clock.report_ready.is_connected(_on_report):
			_clock.report_ready.disconnect(_on_report)
		if _clock.term_finished.is_connected(_on_report):
			_clock.term_finished.disconnect(_on_report)
	_core = core
	_clock = clock
	_actors = actors
	_students.clear()
	if core == null:
		return
	for index in range(core.node_count()):
		_students.append(index)
	_model = DATA.new()
	if GameState.sim_core == core:
		_model.state = GameState.clue_board_journal
	_latest_day = maxi(1, int(core.time_snapshot().day))
	if is_instance_valid(_clock):
		_clock.report_ready.connect(_on_report)
		_clock.term_finished.connect(_on_report)


func record_observed_event(payload: Dictionary, stamp: Dictionary = {}) -> void:
	if _core == null:
		return
	var time: Dictionary = stamp if not stamp.is_empty() else _core.time_snapshot()
	_latest_day = maxi(_latest_day, int(time.get("day", 1)))
	_model.record_event(payload, time, _students)


func _on_event(payload: Dictionary) -> void:
	if _core == null or GameState.sim_core != _core:
		return
	# 未观察办公室外的活动不补录；不把秘密行为、后台矩阵变化当作目击。
	var room := get_parent().get_parent()
	var hub := room.get_node_or_null("OfficeHub")
	if hub == null or hub.mode_name() not in ["monitor", "classroom"]:
		return
	record_observed_event(payload)


func _on_settled(summary: Dictionary) -> void:
	if _core == null or GameState.sim_core != _core:
		return
	var ended := int(summary.get("day", 0))
	if ended > 0:
		_model.seal(ended, GameState.profile_notebook, _students)


func _on_report(ended: int) -> void:
	_model.seal(ended, GameState.profile_notebook, _students)
	_latest_day = maxi(_latest_day, ended)
	# 考试／终局由 OutcomeScreen 接管。推理板只归档，不能盖住结算或持有全树暂停。
	var has_outcome: bool = (
		is_instance_valid(_clock)
		and (
			str(_clock.snapshot().mode) == "finished"
			or (_core._exam.is_exam_day(ended) and not _core.exam_report(ended).is_empty())
		)
	)
	if has_outcome:
		_daily_report = false
		if is_open():
			close()
		return
	_daily_report = true
	var room := get_parent().get_parent()
	var transition := room.get_node_or_null("TransitionOverlay") if room != null else null
	if transition != null:
		transition.force_hide()
		transition.hide()
	if is_instance_valid(_clock) and str(_clock.snapshot().mode) == "finished":
		layer = int($Board.config.final_report_layer)
	_close_other_overlays()
	_open_day(ended)


## 日末接管：先收起其它可能盖在推理板之上的弹层，再打开推理板。
## 风险详情在 layer 31、档案 / 百科各自独立图层；若日末仍开着会压住推理板，
## 且世界被 pause 后表现为「卡死」。
func _close_other_overlays() -> void:
	var room := get_parent().get_parent()
	if room == null:
		return
	var profile := room.get_node_or_null("UI/NpcProfile")
	if profile != null and profile.has_method("is_open") and profile.is_open():
		profile.close()
	var encyclopedia := room.get_node_or_null("UI/EncyclopediaEntry")
	if encyclopedia != null and encyclopedia.has_method("is_open") and encyclopedia.is_open():
		encyclopedia.close()
	var hud := room.get_node_or_null("TimeHUD")
	if hud != null and hud.has_method("close_attention_details"):
		hud.close_attention_details()
	var hub := room.get_node_or_null("OfficeHub")
	if hub != null and hub.has_method("picker_visible") and hub.picker_visible():
		hub.close_picker()


func open() -> void:
	if _core == null:
		return
	if not _daily_report:
		_latest_day = maxi(_latest_day, int(_core.time_snapshot().day))
	_open_day(_shown_day if _daily_report else _latest_day)


func _open_day(day: int) -> void:
	if not is_open():
		_owns_pause = not get_tree().paused
		get_tree().paused = true
	$Board.show()
	show_day(day)


func show_day(day: int) -> void:
	_shown_day = clampi(day, 1, _latest_day)
	var page: Dictionary = _model.page(_shown_day, GameState.profile_notebook, _students)
	page["sealed"] = _model.state.sealed.has(str(_shown_day))
	$Board.show_page(page, _core, _actors, _latest_day)
	$Board.get_node("%Done").text = "继续下一天" if _daily_report else "收起手记"
	if _daily_report and is_instance_valid(_clock) and str(_clock.snapshot().mode) == "finished":
		$Board.get_node("%Done").text = "查看学期报告"
	for name in ["OpenProfile", "OpenEncyclopedia"]:
		$Board.get_node("Design/" + name).disabled = _daily_report


func is_open() -> bool:
	return is_inside_tree() and $Board.visible


func close() -> void:
	if not is_open():
		return
	$Board.hide()
	layer = 6
	_release_pause()
	if _daily_report:
		_daily_report = false
		var room := get_parent().get_parent()
		if (
			room != null
			and room.has_method("_on_continue_requested")
			and str(_clock.snapshot().mode) != "finished"
		):
			room._on_continue_requested()


func clear_board(_ended_day: int = 0) -> void:
	_model.state = {"days": {}, "sealed": {}}
	if _core == GameState.sim_core:
		GameState.clue_board_journal = _model.state


func _release_pause() -> void:
	if not _owns_pause:
		return
	_owns_pause = false
	for sibling in get_parent().get_children():
		if sibling != self and sibling.has_method("is_open") and sibling.is_open():
			return
		if sibling.name == "PauseMenu" and sibling is Control and sibling.visible:
			return
	get_tree().paused = false


func _exit_tree() -> void:
	_release_pause()


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
