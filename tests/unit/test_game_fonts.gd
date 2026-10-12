extends GutTest

const Fonts := preload("res://scripts/ui/game_fonts.gd")


func test_bundled_font_covers_game_labels_and_character_names() -> void:
	var font := Fonts.regular()
	assert_true(font is FontFile)
	var text := "下课十分钟行动当前对象查看资料亲近敌对信任？——0123456789"
	for row in ConfigLoader.new().get_table("characters/seeds").get("rows", []):
		text += str(row.get("alias", ""))
	for character in text:
		assert_true(font.has_char(character.unicode_at(0)), "字体缺字：" + character)


func test_license_is_included_in_both_export_presets() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	for section in ["preset.0", "preset.1"]:
		assert_string_contains(
			str(presets.get_value(section, "include_filter")), "assets/fonts/lxgw-wenkai/OFL.txt"
		)
