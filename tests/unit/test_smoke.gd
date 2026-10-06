extends GutTest
## 冒烟测试：验证 GUT 接入可用、工程资源可加载。
## 正式单测随内核（scripts/core）与各规则实现落位后补。


func test_smoke_engine_context() -> void:
	assert_eq(Engine.get_version_info().major, 4, "测试应在 Godot 4 引擎内运行")


func test_smoke_main_scene_loadable() -> void:
	var scene: Resource = load("res://scenes/ui/main_menu.tscn")
	assert_not_null(scene, "main_menu.tscn 应可被加载（不实例化，避免 _ready 副作用）")
