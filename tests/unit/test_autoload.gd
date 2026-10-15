extends GutTest
## 单例层冒烟：EventBus 信号契约、Config 转发、GameState 状态持有。


func test_event_bus_has_contract_signals() -> void:
	for sig in ["event_happened", "day_settled", "tag_changed", "stress_burst"]:
		assert_true(EventBus.has_signal(sig), "EventBus 应有信号 %s" % sig)


func test_event_bus_emit_and_receive() -> void:
	var received: Array = []
	var cb := func(i: int) -> void: received.append(i)
	EventBus.stress_burst.connect(cb)
	EventBus.stress_burst.emit(3)
	EventBus.stress_burst.disconnect(cb)
	assert_eq(received.size(), 1, "应收到一次信号")
	assert_eq(received[0], 3, "载荷应为 3")


func test_config_get_table_known() -> void:
	var t := Config.get_table("rules/behaviors")
	assert_false(t.is_empty(), "Config 应能转发 rules/behaviors")
	assert_eq(t["rows"].size(), 5, "老师版行为表 5 行：study/move/chat/roughhouse/sleep")


func test_config_get_table_missing() -> void:
	assert_eq(Config.get_table("rules/not_exist"), {}, "缺失表返回空字典")


func test_game_state_start_and_end() -> void:
	GameState.start_game(12345, 16)
	assert_eq(GameState.seed, 12345, "seed")
	assert_eq(GameState.npc_count, 16, "npc_count")
	assert_eq(GameState.day, 0, "day 归零")
	GameState.end_game()
	assert_false(GameState.is_running(), "end 后未运行")


func test_game_state_wire_events_routes_to_event_bus() -> void:
	# D11 缺口④：GameState 把内核事件出口路由到 EventBus（内核不反向依赖 autoload）
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	var received: Array = []
	var cb := func(p: Dictionary) -> void: received.append(p)
	EventBus.event_happened.connect(cb)
	GameState.wire_events(core)
	core._emit("event_happened", {"kind": "probe", "i": 0})
	EventBus.event_happened.disconnect(cb)
	assert_gte(received.size(), 1, "内核事件应经 GameState 路由到 EventBus")
	assert_eq(str(received[0].get("kind")), "probe", "载荷透传")
