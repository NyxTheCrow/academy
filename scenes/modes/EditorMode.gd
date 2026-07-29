extends "res://scripts/GameMode.gd"
## EditorMode — a dev-only live data editor.
##
## Pick a data file on the left; its JSON appears in the editor on the right.
## Apply   → parse and swap it into the running game immediately (not saved).
## Save    → also write it as a user:// override so it persists across runs.
## Revert  → delete the override and reload the original res:// file.
##
## Overrides live in user://data_overrides/ and win over res://data/ at startup.

# [label, filename, runtime key]
const FILES := [
	["Tuning (balance)", "tuning.json", "tuning"],
	["Locations", "locations.json", "locations"],
	["Activities", "activities.json", "activities"],
	["Faculty", "faculty.json", "faculty"],
	["Lexicon", "lexicon.json", "lexicon"],
	["Items", "items.json", "items"],
	["Spells", "spells.json", "spells"],
	["Schedule", "schedule.json", "schedule"],
	["Class Sessions", "class_sessions.json", "class_sessions"],
	["Combat Actions", "combat_actions.json", "combat_actions"],
	["Timeline Actions (proto)", "tick_actions.json", "tick_actions"],
	["Backgrounds", "backgrounds.json", "backgrounds"],
	["Characters (NPCs)", "students.json", "students"],
	["Tags", "tags.json", "tags"],
	["Stats", "stats.json", "stats"],
	["Events", "events.json", "events"],
	["Encounters", "encounters.json", "encounters"],
	["Dialogue", "dialogue.json", "dialogue"],
]

# Blank templates the "New entry" button appends, per file. kind is how to
# insert: array append / dict new-key / backgrounds-array append.
const TEMPLATES := {
	"locations": {"kind": "dict", "label": "location", "prefix": "new_location",
		"tpl": {"name": "New Location", "description": "", "connections": [], "activities": []}},
	"activities": {"kind": "dict", "label": "activity", "prefix": "new_activity",
		"tpl": {"name": "New Activity", "duration": 10, "effects": {}, "requires": {}}},
	"faculty": {"kind": "dict", "label": "teacher", "prefix": "new_teacher",
		"tpl": {"name": "New Teacher", "title": "", "teaches": ""}},
	"class_sessions": {"kind": "dict", "label": "class's in-class events", "prefix": "new_class_id",
		"tpl": {"events": [
			{"id": "new_event", "name": "New in-class action", "learn": "attend", "effects": {},
				"descriptions": [
					{"requires": {"min_stats": {}}, "text": "Shown when the requirement is met (author higher-level variants first)."},
					{"text": "Default description, shown when nothing above matched."}
				]}]}},
	"items": {"kind": "dict", "label": "item", "prefix": "new_item",
		"tpl": {"name": "New Item", "description": "", "use": {}, "consumable": false}},
	"encounters": {"kind": "dict", "label": "encounter", "prefix": "new_encounter",
		"tpl": {"name": "New Encounter", "enemies": [{"name": "Foe", "hp": 20, "atk": 5, "move": 3}], "reward": {"effects": {}}, "penalty": {"effects": {}}}},
	"dialogue": {"kind": "dict", "label": "dialogue scene", "prefix": "new_scene",
		"tpl": {"lines": [{"speaker": "?", "text": "..."}]}},
	"spells": {"kind": "array", "label": "spell",
		"tpl": {"id": "new_spell", "name": "New Spell", "element": "", "requires": {}, "description": ""}},
	"students": {"kind": "array", "label": "character",
		"tpl": {"id": "new_student", "name": "New Student", "location": "dormitories", "tags": ["student", "enrolled"], "stats": {"focus": 5}}},
	"combat_actions": {"kind": "array", "label": "combat action",
		"tpl": {"id": "new_action", "name": "New Action", "kind": "self", "requires": {}, "description": ""}},
	"events": {"kind": "array", "label": "event",
		"tpl": {"id": "new_event", "trigger": {}, "once": true, "text": "", "effects": {}}},
	"lexicon": {"kind": "array", "label": "lexicon entry",
		"tpl": {"term": "New Term", "category": "", "aliases": [], "definition": ""}},
	"tags": {"kind": "array", "label": "tag",
		"tpl": {"id": "new_tag", "name": "New Tag", "description": ""}},
	"stats": {"kind": "array", "label": "stat",
		"tpl": {"id": "new_stat", "name": "New Stat", "parent": "", "description": ""}},
	"backgrounds": {"kind": "backgrounds", "label": "background",
		"tpl": {"id": "new_background", "name": "New Background", "description": "", "effects": {"tags": []}}},
}

var _file := ""   # current filename
var _key := ""    # current runtime key
var _standalone := false
var editor: TextEdit
var header: Label
var status: Label

func enter(context: Dictionary) -> void:
	_standalone = context.get("standalone", false)
	_build_ui()
	_open(FILES[0][1], FILES[0][2])

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var title := Label.new()
	title.text = "Data Editor  (dev)"
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var close_btn := Button.new()
	close_btn.text = "Return to Main Menu" if _standalone else "Close"
	close_btn.pressed.connect(func(): finished.emit({}))
	top.add_child(close_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	# File list (left)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(190, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	list_scroll.add_child(list)
	for entry in FILES:
		var b := Button.new()
		b.text = entry[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_open.bind(entry[1], entry[2]))
		list.add_child(b)

	# Editor (right)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	header = Label.new()
	right.add_child(header)
	editor = TextEdit.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(editor)
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	right.add_child(status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right.add_child(buttons)
	var new_btn := Button.new()
	new_btn.text = "+ New entry"
	new_btn.tooltip_text = "Append a blank template for this file's type (character, spell, item, location, tag, …)."
	new_btn.pressed.connect(_on_new_entry)
	buttons.add_child(new_btn)
	var apply_btn := Button.new()
	apply_btn.text = "Apply (live)"
	apply_btn.pressed.connect(_on_apply)
	buttons.add_child(apply_btn)
	var save_btn := Button.new()
	save_btn.text = "Save override"
	save_btn.tooltip_text = "Persist as a user:// override (works everywhere; survives exported builds)."
	save_btn.pressed.connect(_on_save)
	buttons.add_child(save_btn)
	var project_btn := Button.new()
	project_btn.text = "Write to project"
	project_btn.tooltip_text = "Write straight into res://data/ (only works when running from the Godot editor)."
	project_btn.pressed.connect(_on_write_project)
	buttons.add_child(project_btn)
	var revert_btn := Button.new()
	revert_btn.text = "Revert to original"
	revert_btn.pressed.connect(_on_revert)
	buttons.add_child(revert_btn)

func _open(filename: String, key: String) -> void:
	_file = filename
	_key = key
	editor.text = JSON.stringify(_runtime_data(key), "\t")
	_update_header()
	status.text = ""

func _update_header() -> void:
	var tag := "  [OVERRIDE ACTIVE]" if GameData.has_override(_file) else ""
	header.text = "%s%s" % [_file, tag]

# --- Runtime data get / apply ----------------------------------------------
func _runtime_data(key: String) -> Variant:
	match key:
		"locations": return GameData.locations
		"activities": return GameData.activities
		"faculty": return GameData.faculty
		"combat_actions": return GameData.combat_actions
		"events": return GameData.events
		"dialogue": return GameData.dialogue
		"encounters": return GameData.encounters
		"students": return GameData.students
		"spells": return GameData.spells
		"items": return GameData.items
		"schedule": return GameData.schedule
		"class_sessions": return GameData.class_sessions
		"tags": return GameData.tags_registry
		"stats": return GameData.stats_registry
		"tuning": return GameData.tuning
		"tick_actions": return GameData.tick_actions
		"backgrounds": return {"backgrounds": GameData.backgrounds}
		"lexicon": return Lexicon.entries
	return {}

# --- New-entry templates ----------------------------------------------------
func _on_new_entry() -> void:
	var spec: Dictionary = TEMPLATES.get(_key, {})
	if spec.is_empty():
		status.text = "(no template for this file)"
		return
	var parsed: Variant = _parse_text()
	if parsed == null:
		return
	match spec["kind"]:
		"array":
			if parsed is Array:
				parsed.append(spec["tpl"].duplicate(true))
		"backgrounds":
			if parsed is Dictionary and parsed.has("backgrounds"):
				parsed["backgrounds"].append(spec["tpl"].duplicate(true))
		"dict":
			if parsed is Dictionary:
				parsed[_free_key(parsed, spec["prefix"])] = spec["tpl"].duplicate(true)
	editor.text = JSON.stringify(parsed, "\t")
	_ok("Added a new %s template — edit it, then Apply or Save." % spec["label"])

func _free_key(d: Dictionary, prefix: String) -> String:
	if not d.has(prefix):
		return prefix
	var i := 2
	while d.has("%s_%d" % [prefix, i]):
		i += 1
	return "%s_%d" % [prefix, i]

func _apply_runtime(key: String, parsed: Variant) -> void:
	match key:
		"locations": GameData.locations = parsed
		"activities": GameData.activities = parsed
		"faculty": GameData.faculty = parsed
		"combat_actions": GameData.combat_actions = parsed
		"events": GameData.events = parsed
		"dialogue": GameData.dialogue = parsed
		"encounters": GameData.encounters = parsed
		"students": GameData.students = parsed
		"spells": GameData.spells = parsed
		"items": GameData.items = parsed
		"schedule": GameData.schedule = parsed
		"class_sessions": GameData.class_sessions = parsed
		"tags": GameData.tags_registry = parsed
		"stats": GameData.stats_registry = parsed
		"tuning": GameData.tuning = parsed
		"tick_actions": GameData.tick_actions = parsed
		"backgrounds": GameData.backgrounds = (parsed.get("backgrounds", []) if parsed is Dictionary else parsed)
		"lexicon": Lexicon.entries = parsed
	GameState.state_changed.emit()

## Parse the editor text; on error show it and return null.
func _parse_text() -> Variant:
	var json := JSON.new()
	var err := json.parse(editor.text)
	if err != OK:
		status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		status.text = "Parse error (line %d): %s" % [json.get_error_line(), json.get_error_message()]
		return null
	return json.data

func _ok(msg: String) -> void:
	status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	status.text = msg

func _on_apply() -> void:
	var parsed: Variant = _parse_text()
	if parsed == null:
		return
	_apply_runtime(_key, parsed)
	_ok("Applied live (not saved to disk).")

func _on_save() -> void:
	var parsed: Variant = _parse_text()
	if parsed == null:
		return
	_apply_runtime(_key, parsed)
	var werr := GameData.write_override(_file, editor.text)
	if werr != "":
		status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		status.text = "Applied, but save failed: " + werr
	else:
		_ok("Saved override + applied.")
	_update_header()

func _on_write_project() -> void:
	var parsed: Variant = _parse_text()
	if parsed == null:
		return
	_apply_runtime(_key, parsed)
	var werr := GameData.write_project(_file, editor.text)
	if werr != "":
		status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		status.text = "Applied live, but project write failed: " + werr
		return
	# The project file is now the source of truth; drop any redundant override.
	GameData.clear_override(_file)
	_ok("Written to res://data/%s (project file updated)." % _file)
	_update_header()

func _on_revert() -> void:
	GameData.clear_override(_file)
	GameData.reload()
	Lexicon.reload()
	_open(_file, _key)
	_ok("Reverted to the original res:// file.")
