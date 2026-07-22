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
	["Locations", "locations.json", "locations"],
	["Lexicon", "lexicon.json", "lexicon"],
	["Items", "items.json", "items"],
	["Spells", "spells.json", "spells"],
	["Schedule", "schedule.json", "schedule"],
	["Combat Actions", "combat_actions.json", "combat_actions"],
	["Backgrounds", "backgrounds.json", "backgrounds"],
	["Students", "students.json", "students"],
	["Events", "events.json", "events"],
	["Encounters", "encounters.json", "encounters"],
	["Dialogue", "dialogue.json", "dialogue"],
]

var _file := ""   # current filename
var _key := ""    # current runtime key
var editor: TextEdit
var header: Label
var status: Label

func enter(_context: Dictionary) -> void:
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
	close_btn.text = "Close"
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
	var apply_btn := Button.new()
	apply_btn.text = "Apply (live)"
	apply_btn.pressed.connect(_on_apply)
	buttons.add_child(apply_btn)
	var save_btn := Button.new()
	save_btn.text = "Save override"
	save_btn.pressed.connect(_on_save)
	buttons.add_child(save_btn)
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
		"combat_actions": return GameData.combat_actions
		"events": return GameData.events
		"dialogue": return GameData.dialogue
		"encounters": return GameData.encounters
		"students": return GameData.students
		"spells": return GameData.spells
		"items": return GameData.items
		"schedule": return GameData.schedule
		"backgrounds": return {"backgrounds": GameData.backgrounds}
		"lexicon": return Lexicon.entries
	return {}

func _apply_runtime(key: String, parsed: Variant) -> void:
	match key:
		"locations": GameData.locations = parsed
		"combat_actions": GameData.combat_actions = parsed
		"events": GameData.events = parsed
		"dialogue": GameData.dialogue = parsed
		"encounters": GameData.encounters = parsed
		"students": GameData.students = parsed
		"spells": GameData.spells = parsed
		"items": GameData.items = parsed
		"schedule": GameData.schedule = parsed
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

func _on_revert() -> void:
	GameData.clear_override(_file)
	GameData.reload()
	Lexicon.reload()
	_open(_file, _key)
	_ok("Reverted to the original res:// file.")
