extends RefCounted


static func read() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/clue_board.json"))
