extends GutTest
## ConfigLoader 单测：全量读取 data/**/*.csv、跳过 # 注释、表头字典化、字符串值。


func test_load_all_reads_all_tables() -> void:
	var loader := ConfigLoader.new()
	var tables := loader.load_all()
	# 新增独立世界倍速表与学业成绩分段表；其余既有表继续全部加载。
	assert_eq(tables.size(), 29, "应读到 29 张表（含玩家邀请类型、世界倍速与学业成绩分段表）")
	assert_true(tables.has("rules/behaviors"), "rules/behaviors 应在")
	assert_true(tables.has("rules/stand_points"), "rules/stand_points 应在")
	assert_true(tables.has("rules/time_presentation"), "rules/time_presentation 应在")
	assert_true(tables.has("rules/time_runtime"), "rules/time_runtime 应在")
	assert_true(tables.has("rules/time_flow"), "rules/time_flow 应在（世界倍速配置）")
	assert_true(tables.has("rules/movement"), "rules/movement 应在")
	assert_true(tables.has("rules/player_interaction"), "rules/player_interaction 应在（玩家交互几何与线索参数）")
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
	assert_eq(rows.size(), 18, "behaviors 应有 18 个行为（不含注释与表头）")


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
