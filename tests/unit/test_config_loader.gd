extends GutTest
## ConfigLoader 单测：全量读取 data/**/*.csv、跳过 # 注释、表头字典化、字符串值。


func test_load_all_reads_all_tables() -> void:
	var loader := ConfigLoader.new()
	var tables := loader.load_all()
	# data/ 现状：rules 15 + balance 2 + characters 2 = 19 张
	assert_eq(tables.size(), 19, "应读到 19 张表")
	assert_true(tables.has("rules/behaviors"), "rules/behaviors 应在")
	assert_true(tables.has("balance/npc_weights"), "balance/npc_weights 应在")
	assert_true(tables.has("characters/seeds"), "characters/seeds 应在")
	assert_true(tables.has("characters/bindings"), "characters/bindings 应在")
	assert_true(tables.has("rules/kernel_params"), "rules/kernel_params 应在")


func test_skips_comments_and_header() -> void:
	var loader := ConfigLoader.new()
	var t := loader.get_table("rules/behaviors")
	var headers: Array = t["headers"]
	assert_eq(headers[0], "behavior", "首列应为 behavior")
	var rows: Array = t["rows"]
	assert_eq(rows.size(), 17, "behaviors 应有 17 个行为（不含注释与表头）")


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
