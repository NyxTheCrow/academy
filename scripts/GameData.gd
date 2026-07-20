extends Node
## GameData — the CONTENT layer.
##
## Loads all data-driven content from res://data/ as parsed tables. Nothing
## here is game logic. To add content — activities, events, dialogue scenes,
## combat encounters — you edit the JSON, not this file.

var activities: Array = []
var events: Array = []
var dialogue: Dictionary = {}    # scene_id -> { "lines": [...] }
var encounters: Dictionary = {}  # encounter_id -> { ... }
var students: Array = []         # NPC definitions
var backgrounds: Array = []      # character-creation backgrounds

func _ready() -> void:
	activities = _load_array("res://data/activities.json")
	events = _load_array("res://data/events.json")
	dialogue = _load_dict("res://data/dialogue.json")
	encounters = _load_dict("res://data/encounters.json")
	students = _load_array("res://data/students.json")
	backgrounds = _load_dict("res://data/backgrounds.json").get("backgrounds", [])
	print("[GameData] %d activities, %d events, %d dialogue, %d encounters, %d students, %d backgrounds"
		% [activities.size(), events.size(), dialogue.size(), encounters.size(), students.size(), backgrounds.size()])

func _load_array(path: String) -> Array:
	var v: Variant = _parse(path)
	return v if v is Array else []

func _load_dict(path: String) -> Dictionary:
	var v: Variant = _parse(path)
	return v if v is Dictionary else {}

func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[GameData] data file not found: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("[GameData] failed to parse JSON: %s" % path)
	return parsed

func get_activity(id: String) -> Dictionary:
	for a in activities:
		if a.get("id", "") == id:
			return a
	return {}

func get_dialogue(id: String) -> Dictionary:
	return dialogue.get(id, {})

func get_encounter(id: String) -> Dictionary:
	return encounters.get(id, {})
