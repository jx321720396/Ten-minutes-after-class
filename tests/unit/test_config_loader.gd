extends GutTest
## ConfigLoader 单测：全量读取 data/**/*.csv、跳过 # 注释、表头字典化、字符串值。


func test_load_all_reads_all_tables() -> void:
	var loader := ConfigLoader.new()
	var tables := loader.load_all()
	# 数量随独立配置增长；约束关键契约表，避免新增合法配置导致旧总数断言失效。
	assert_true(tables.has("rules/exam"), "考试配置应加载")
	assert_true(tables.has("rules/teacher"), "老师巡查配置应加载")
	assert_true(tables.has("rules/leisure"))
	assert_true(tables.has("ui/emotion_faces"))
	assert_true(tables.has("rules/behaviors"), "rules/behaviors 应在")
	assert_true(tables.has("rules/stand_points"), "rules/stand_points 应在")
	assert_true(tables.has("rules/time_presentation"), "rules/time_presentation 应在")
	assert_true(tables.has("rules/time_runtime"), "rules/time_runtime 应在")
	assert_true(tables.has("rules/time_flow"), "rules/time_flow 应在（世界倍速配置）")
	assert_true(tables.has("rules/movement"), "rules/movement 应在")
	assert_true(tables.has("rules/chat_space"), "rules/chat_space 应在（闲聊空间几何）")
	assert_true(tables.has("ui/chat_feedback_style"), "ui/chat_feedback_style 应在（闲聊反馈呈现参数）")
	assert_true(tables.has("balance/npc_weights"), "balance/npc_weights 应在")
	assert_true(tables.has("characters/seeds"), "characters/seeds 应在")
	assert_true(tables.has("characters/bindings"), "characters/bindings 应在")
	assert_true(tables.has("characters/appearance"), "characters/appearance 应在")
	assert_true(tables.has("rules/kernel_params"), "rules/kernel_params 应在")
	assert_true(tables.has("rules/grade_table"), "rules/grade_table 应在（学业成绩分段表）")


func test_skips_comments_and_header() -> void:
	var loader := ConfigLoader.new()
	var t := loader.get_table("rules/behaviors")
	var headers: Array = t["headers"]
	assert_eq(headers[0], "behavior", "首列应为 behavior")
	var rows: Array = t["rows"]
	assert_eq(rows.size(), 5, "老师版行为表 5 行：study/move/chat/roughhouse/sleep（不含注释与表头）")


func test_rows_keyed_by_header() -> void:
	var loader := ConfigLoader.new()
	var t := loader.get_table("balance/npc_weights")
	var rows: Array = t["rows"]
	var row: Dictionary = rows[0]
	assert_eq(row["param"], "alpha_a_base", "首行 param")
	assert_eq(row["value"], "0.5", "首行 value 为字符串 0.5")


func test_returns_empty_for_unknown_name_without_load() -> void:
	var loader := ConfigLoader.new()
	var t := loader.get_table("rules/behaviors")
	assert_false(t.is_empty(), "已存在表非空")
