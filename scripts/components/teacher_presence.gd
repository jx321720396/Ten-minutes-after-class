extends Node3D
## Stationary scenery only: no student index, navigation or core writes.

const SETTINGS := "res://data/ui/teacher_presence.json"


func _ready() -> void:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	var location: Array = settings["position"]
	position = Vector3(location[0], location[1], location[2])
	var sprite := $Sprite as Sprite3D
	sprite.texture = load(str(settings["texture"])) as Texture2D
	sprite.pixel_size = float(settings["height"]) / float(settings["visible_height_pixels"])
	sprite.position.y = (
		(float(settings["floor_pixel"]) - sprite.texture.get_height() * 0.5) * sprite.pixel_size
	)
	visible = false


func set_view_mode(mode: String) -> void:
	visible = mode == "classroom"
