class_name AssetPreloader
extends RefCounted
## 后台预加载（表现层）：人物坐姿贴图与教室场景走线程读盘。
##
## 背景（2026-10-17 进教室耗时 6.6 秒）：16 名学生各 2 张 1.5 MB 贴图，原先在
## `classroom_actors.build()` 里同步 `load()`，共阻塞约 2.2 秒。现在：
##   · 主菜单出现时就把 32 张贴图与教室场景丢给 ResourceLoader 线程；
##   · 人物构建只登记路径，不读盘；
##   · 贴图没就绪前人物保持站立（classroom_actors 保留原 Sprite），就绪后再切坐姿。
## 只是加载时机变化，不改玩法、数值与随机流。

const TEXTURE_TYPE := "Texture2D"
const SCENE_TYPE := "PackedScene"
const POSE_TABLE := "res://data/ui/student_poses.json"
const POSE_KEYS: Array[String] = ["study", "idle"]

static var _textures: Dictionary = {}
static var _texture_requests: Dictionary = {}
static var _failed: Dictionary = {}
static var _scenes: Dictionary = {}
static var _scene_requests: Dictionary = {}


## 全部人物坐姿贴图路径（去重）；读不到配置时返回空数组。
static func pose_texture_paths() -> Array:
	var paths := {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POSE_TABLE))
	if parsed is Dictionary:
		var bindings: Dictionary = parsed.get("bindings", {})
		for binding in bindings.values():
			if binding is not Dictionary:
				continue
			for key in POSE_KEYS:
				if binding.has(key):
					paths[str(binding[key])] = true
	return paths.keys()


## 发起贴图线程加载（重复调用无副作用）。
static func request_textures(paths: Array) -> void:
	for raw in paths:
		var path := str(raw)
		if path.is_empty() or _textures.has(path) or _failed.has(path):
			continue
		if _texture_requests.has(path):
			continue
		_texture_requests[path] = true
		ResourceLoader.load_threaded_request(path, TEXTURE_TYPE)


## 取贴图：已加载直接返回；仍在加载且 wait_for_load=false 返回 null（调用方下一帧再试）；
## wait_for_load=true（默认，单测 / 同步调用）则阻塞到加载完成，保持旧语义。
static func texture(path: String, wait_for_load: bool = true) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if _failed.has(path):
		return null
	if not _texture_requests.has(path):
		request_textures([path])
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var loaded: Resource = ResourceLoader.load_threaded_get(path)
		if loaded is Texture2D:
			_textures[path] = loaded
			return loaded
		_failed[path] = true
		return null
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not wait_for_load:
			return null
		var blocked: Resource = ResourceLoader.load_threaded_get(path)
		if blocked is Texture2D:
			_textures[path] = blocked
			return blocked
		_failed[path] = true
		return null
	# 请求失败（路径改动 / 导入缺失）：同步兜底一次并记住结果，避免每帧重试。
	var fallback := load(path) as Texture2D
	if fallback == null:
		_failed[path] = true
		return null
	_textures[path] = fallback
	return fallback


## 贴图是否已可用（失败也返回 true —— 调用方按“没有贴图”继续，不无限等待）。
static func is_ready(path: String) -> bool:
	if _textures.has(path) or _failed.has(path):
		return true
	if not _texture_requests.has(path):
		return false
	return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED


## 发起场景线程加载（重复调用无副作用）。
static func request_scene(path: String) -> void:
	if path.is_empty() or _scenes.has(path) or _scene_requests.has(path):
		return
	_scene_requests[path] = true
	ResourceLoader.load_threaded_request(path, SCENE_TYPE)


## 取场景：已加载返回；仍在加载返回 null（调用方回退到 change_scene_to_file）。
static func scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	if not _scene_requests.has(path):
		request_scene(path)
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	var loaded: Resource = ResourceLoader.load_threaded_get(path)
	if loaded is PackedScene:
		_scenes[path] = loaded
		return loaded
	return null
