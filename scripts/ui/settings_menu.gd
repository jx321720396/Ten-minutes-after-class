extends Control

signal closed

@onready var back_btn: Button = $Overlay/CenterContainer/Panel/VBox/BackBtn
@onready var bgm_slider: HSlider = $Overlay/CenterContainer/Panel/VBox/BGMRow/BGMSlider
@onready var sfx_slider: HSlider = $Overlay/CenterContainer/Panel/VBox/SFXRow/SFXSlider


func _ready():
	back_btn.pressed.connect(_on_back)
	bgm_slider.value = BGM.get_bgm_volume() * 100.0
	bgm_slider.value_changed.connect(_on_bgm_volume_changed)
	sfx_slider.value = SFX.get_sfx_volume() * 100.0
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)


func _on_bgm_volume_changed(value: float) -> void:
	BGM.set_bgm_volume(value / 100.0)


func _on_sfx_volume_changed(value: float) -> void:
	SFX.set_sfx_volume(value / 100.0)


func _on_back():
	emit_signal("closed")


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()
		get_viewport().set_input_as_handled()
