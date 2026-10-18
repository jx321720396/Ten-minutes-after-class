extends RefCounted
## 档案使用同一份画像映射及上半身裁切，不依赖教室演员。

static var _cache: Dictionary = {}


static func texture_for(character_id: String, config: Dictionary) -> Texture2D:
	var entry: Dictionary = config.get("portraits", {}).get(character_id, {})
	var path := str(entry.get("path", ""))
	var coordinates: Array = entry.get("region", [])
	if path.is_empty() or coordinates.size() != 4 or not ResourceLoader.exists(path):
		return null
	var region := Rect2(coordinates[0], coordinates[1], coordinates[2], coordinates[3])
	var key := path + str(region)
	if _cache.has(key):
		return _cache[key]
	var source := load(path) as Texture2D
	if source == null or not Rect2(Vector2.ZERO, source.get_size()).encloses(region):
		return null
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return null
	var portrait := AtlasTexture.new()
	portrait.atlas = source
	portrait.region = region
	portrait.filter_clip = true
	_cache[key] = portrait
	return portrait
