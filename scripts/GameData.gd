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
var tags_registry: Array = []    # documented tags (editable reference list)
var tuning: Dictionary = {}      # editable numeric knobs (decay, baselines, ...)
var tick_actions: Dictionary = {} # prototype timeline-combat action defs

## Editable data files live in res://data/. The in-game editor writes overrides
## to user://data_overrides/, which take precedence when present.
const OVERRIDE_DIR := "user://data_overrides/"

func _ready() -> void:
	reload()

## (Re)load every data table (override file wins over the res:// original).
func reload() -> void:
	locations = _load_dict(src_path("locations.json"))
	combat_actions = _load_array(src_path("combat_actions.json"))
	events = _load_array(src_path("events.json"))
	dialogue = _load_dict(src_path("dialogue.json"))
	encounters = _load_dict(src_path("encounters.json"))
	students = _load_array(src_path("students.json"))
	backgrounds = _load_dict(src_path("backgrounds.json")).get("backgrounds", [])
	spells = _load_array(src_path("spells.json"))
	items = _load_dict(src_path("items.json"))
	schedule = _load_array(src_path("schedule.json"))
	tags_registry = _load_array(src_path("tags.json"))
	tuning = _load_dict(src_path("tuning.json"))
	tick_actions = _load_dict(src_path("tick_actions.json"))
	print("[GameData] %d locations, %d combat actions, %d spells, %d items, %d schedule, %d students"
		% [locations.size(), combat_actions.size(), spells.size(), items.size(), schedule.size(), students.size()])

# --- Override files (for the in-game editor) --------------------------------
## Path a file should load from: the user override if it exists, else res://.
func src_path(filename: String) -> String:
	var o := OVERRIDE_DIR + filename
	return o if FileAccess.file_exists(o) else "res://data/" + filename

func has_override(filename: String) -> bool:
	return FileAccess.file_exists(OVERRIDE_DIR + filename)

## Read the current on-disk source text for a file (override or original).
func read_source(filename: String) -> String:
	var f := FileAccess.open(src_path(filename), FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

## Write an override file. Returns "" on success or an error message.
func write_override(filename: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(OVERRIDE_DIR)
	var f := FileAccess.open(OVERRIDE_DIR + filename, FileAccess.WRITE)
	if f == null:
		return "could not open override for writing"
	f.store_string(text)
	f.close()
	return ""

func clear_override(filename: String) -> void:
	var p := OVERRIDE_DIR + filename
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

## Write straight to the project's res://data/ file. Only works when running
## from the Godot editor (res:// is read-only in an exported build). Returns ""
## on success or an error message.
func write_project(filename: String, text: String) -> String:
	var f := FileAccess.open("res://data/" + filename, FileAccess.WRITE)
	if f == null:
		return "res:// is read-only here (this only works when running from the Godot editor)"
	f.store_string(text)
	f.close()
	return ""

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
