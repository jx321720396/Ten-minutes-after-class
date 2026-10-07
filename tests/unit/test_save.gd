extends GutTest
## Save 单例：存档往返、版本号字段、存在性/删除、元数据。

const TMP_PATH := "user://test_save.tmp"


func before_each() -> void:
	if Save.has_save(TMP_PATH):
		Save.delete(TMP_PATH)


func after_each() -> void:
	if Save.has_save(TMP_PATH):
		Save.delete(TMP_PATH)


func test_save_load_roundtrip() -> void:
	Save.save({"day": 3, "seed": 42}, TMP_PATH)
	assert_true(Save.has_save(TMP_PATH), "存档文件应存在")
	var payload := Save.read(TMP_PATH)
	# JSON 往返后数值统一为 float
	assert_eq(payload.get("data", {}).get("day"), 3.0, "data.day 往返")
	assert_eq(payload.get("data", {}).get("seed"), 42.0, "data.seed 往返")


func test_save_contains_version() -> void:
	Save.save({"day": 1}, TMP_PATH)
	var payload := Save.read(TMP_PATH)
	assert_eq(payload.get("version"), float(Save.SAVE_VERSION), "版本号字段应一致")


func test_load_missing_returns_empty() -> void:
	assert_eq(Save.read("user://definitely_missing.tmp"), {}, "缺失存档返回空字典")


func test_read_meta() -> void:
	Save.save({"day": 12}, TMP_PATH)
	var meta := Save.read_meta(TMP_PATH)
	assert_eq(meta.get("version"), Save.SAVE_VERSION, "meta.version")
	assert_eq(meta.get("day"), 12, "meta.day")


func test_delete() -> void:
	Save.save({}, TMP_PATH)
	Save.delete(TMP_PATH)
	assert_false(Save.has_save(TMP_PATH), "删除后存档不存在")
