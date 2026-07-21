extends Node
## GameData — the CONTENT layer.
##
## Loads all data-driven content from res://data/ as parsed tables. Nothing
## here is game logic. To add content — activities, events, dialogue scenes,
## combat encounters — you edit the JSON, not this file.

var locations: Dictionary = {}   # location_id -> { name, connections, actions }
var combat_actions: Array = []   # shared combat action list (tag-gated)
var events: Array = []
var dialogue: Dictionary = {}    # scene_id -> { "lines": [...] }
var encounters: Dictionary = {}  # encounter_id -> { ... }
var students: Array = []         # NPC definitions
var backgrounds: Array = []      # character-creation backgrounds
var spells: Array = []           # spell list
var items: Dictionary = {}       # item_id -> { name, description, use? }
var schedule: Array = []         # recurring timetable entries

func _ready() -> void:
	locations = _load_dict("res://data/locations.json")
	combat_actions = _load_array("res://data/combat_actions.json")
	events = _load_array("res://data/events.json")
	dialogue = _load_dict("res://data/dialogue.json")
	encounters = _load_dict("res://data/encounters.json")
	students = _load_array("res://data/students.json")
	backgrounds = _load_dict("res://data/backgrounds.json").get("backgrounds", [])
	spells = _load_array("res://data/spells.json")
	items = _load_dict("res://data/items.json")
	schedule = _load_array("res://data/schedule.json")
	print("[GameData] %d locations, %d combat actions, %d spells, %d items, %d schedule, %d students"
		% [locations.size(), combat_actions.size(), spells.size(), items.size(), schedule.size(), students.size()])

func get_item(id: String) -> Dictionary:
	return items.get(id, {})

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

func get_location(id: String) -> Dictionary:
	return locations.get(id, {})

func get_dialogue(id: String) -> Dictionary:
	return dialogue.get(id, {})

func get_encounter(id: String) -> Dictionary:
	return encounters.get(id, {})
