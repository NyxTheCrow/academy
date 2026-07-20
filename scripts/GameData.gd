extends Node
## GameData — the CONTENT layer.
##
## Loads all data-driven content (activities, events) from JSON files in res://data/.
## Nothing here is game logic; it is just parsed tables. To add hundreds of
## activities or events you edit the JSON, not this file. This is the pattern
## that lets a game like Academagia carry an enormous amount of content without
## a matching pile of code.

var activities: Array = []
var events: Array = []

func _ready() -> void:
	activities = _load_json_array("res://data/activities.json")
	events = _load_json_array("res://data/events.json")
	print("[GameData] loaded %d activities, %d events" % [activities.size(), events.size()])

func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("[GameData] data file not found: %s" % path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Array):
		push_error("[GameData] failed to parse (expected a JSON array): %s" % path)
		return []
	return parsed as Array

## Look up an activity by its id. Returns an empty Dictionary if not found.
func get_activity(id: String) -> Dictionary:
	for a in activities:
		if a.get("id", "") == id:
			return a
	return {}
