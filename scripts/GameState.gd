extends Node
## GameState — THE SPINE.
##
## Owns the canonical clock and the entire player game state. Two rules keep
## the whole game coherent, and everything (activities, events, dialogue,
## combat) routes through them:
##   1. The clock only ever moves through advance_time().
##   2. State only ever mutates through apply_effects().
## Because every system speaks the same `effects` dictionary, adding a new
## system never means a new mutation path — it just emits effects.

signal state_changed          ## the clock or player state changed; UI should refresh
signal message(text: String)  ## narrative / journal line for the UI to display

# --- Time configuration -----------------------------------------------------
const SLOTS := ["Morning", "Afternoon", "Evening"]
const DAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const WEEKS_PER_SEMESTER := 4
const SAVE_VERSION := 1

# --- The clock --------------------------------------------------------------
var semester: int = 1
var week: int = 1        # 1-based
var day_index: int = 0   # 0-based index into DAYS
var slot_index: int = 0  # 0-based index into SLOTS

# --- Player state -----------------------------------------------------------
var stats := {}
var max_energy: int = 100
var energy: int = 100
var relationships := {}   # npc_id -> affinity (int)
var flags := {}           # arbitrary story flags (string -> Variant)
var fired_events := {}    # event_id -> true, so "once" events fire once

func _ready() -> void:
	randomize()
	reset()

## Reset all state to a fresh new game. Also used by the test runner.
func reset() -> void:
	semester = 1
	week = 1
	day_index = 0
	slot_index = 0
	stats = {"magic": 0, "combat": 0, "knowledge": 0, "charisma": 0}
	max_energy = 100
	energy = 100
	relationships = {}
	flags = {}
	fired_events = {}
	state_changed.emit()

# --- Time helpers -----------------------------------------------------------
func day_name() -> String:
	return DAYS[day_index]

func slot_name() -> String:
	return SLOTS[slot_index]

func is_school_day() -> bool:
	return day_index < 5  # Monday..Friday

func date_string() -> String:
	return "Semester %d  ·  Week %d  ·  %s  ·  %s" % [semester, week, day_name(), slot_name()]

## Advance exactly one time slot. This is the ONLY place the clock moves.
func advance_time() -> void:
	slot_index += 1
	if slot_index >= SLOTS.size():
		slot_index = 0
		_advance_day()
	_check_events()
	state_changed.emit()

func _advance_day() -> void:
	day_index += 1
	energy = max_energy  # a night's sleep restores energy
	if day_index >= DAYS.size():
		day_index = 0
		_advance_week()

func _advance_week() -> void:
	week += 1
	if week > WEEKS_PER_SEMESTER:
		week = 1
		semester += 1
		message.emit("A new semester begins. (Semester %d)" % semester)

# --- Resolution -------------------------------------------------------------
## Perform a plain activity dictionary: optional skill check, apply effects,
## then advance one slot. Mode-triggering activities (dialogue/combat) are
## driven by AcademyMode instead, so their sub-scene can resolve first.
func perform_activity(activity: Dictionary) -> void:
	var act_name: String = activity.get("name", "Activity")
	var check: Variant = activity.get("skill_check", null)
	if check != null and check is Dictionary:
		_resolve_skill_check(act_name, check)
	else:
		apply_effects(activity.get("effects", {}))
		message.emit("You spent the %s: %s." % [slot_name().to_lower(), act_name])
	advance_time()

func _resolve_skill_check(act_name: String, check: Dictionary) -> void:
	var stat_id: String = check.get("stat", "")
	var difficulty: int = int(check.get("difficulty", 5))
	var roll: int = randi_range(1, 6)
	var stat_value: int = int(stats.get(stat_id, 0))
	var total: int = stat_value + roll
	if total >= difficulty:
		message.emit("%s — [color=lightgreen]Success![/color] (%s %d + roll %d = %d vs %d)"
			% [act_name, stat_id, stat_value, roll, total, difficulty])
		apply_effects(check.get("success", {}))
	else:
		message.emit("%s — [color=salmon]Failed.[/color] (%s %d + roll %d = %d vs %d)"
			% [act_name, stat_id, stat_value, roll, total, difficulty])
		apply_effects(check.get("failure", {}))

## Apply an effects dictionary to game state. The single mutation gateway.
## Supported keys: "stats", "energy", "relationships", "flags".
func apply_effects(effects: Dictionary) -> void:
	if effects.has("stats"):
		for k in effects["stats"]:
			stats[k] = int(stats.get(k, 0)) + int(effects["stats"][k])
	if effects.has("energy"):
		energy = clampi(energy + int(effects["energy"]), 0, max_energy)
	if effects.has("relationships"):
		for npc in effects["relationships"]:
			relationships[npc] = int(relationships.get(npc, 0)) + int(effects["relationships"][npc])
	if effects.has("flags"):
		for fl in effects["flags"]:
			flags[fl] = effects["flags"][fl]
	state_changed.emit()

## Merge effects dictionary `add` into `into` (used to accumulate results from
## a dialogue or combat scene before handing one dictionary back). Pure/static.
static func merge_effects(into: Dictionary, add: Dictionary) -> void:
	for cat in ["stats", "relationships"]:
		if add.has(cat):
			if not into.has(cat):
				into[cat] = {}
			for k in add[cat]:
				into[cat][k] = int(into[cat].get(k, 0)) + int(add[cat][k])
	if add.has("energy"):
		into["energy"] = int(into.get("energy", 0)) + int(add["energy"])
	if add.has("flags"):
		if not into.has("flags"):
			into["flags"] = {}
		for k in add["flags"]:
			into["flags"][k] = add["flags"][k]

# --- Events -----------------------------------------------------------------
## Checked after every time advance. Fires any event whose trigger conditions
## are all met (date and/or stat and/or flag conditions).
func _check_events() -> void:
	for ev in GameData.events:
		var id: String = ev.get("id", "")
		if ev.get("once", true) and fired_events.has(id):
			continue
		if _event_triggers(ev):
			fired_events[id] = true
			if ev.has("text"):
				message.emit("[color=gold]★ %s[/color]" % ev["text"])
			apply_effects(ev.get("effects", {}))

func _event_triggers(ev: Dictionary) -> bool:
	var t: Dictionary = ev.get("trigger", {})
	if t.has("semester") and int(t["semester"]) != semester:
		return false
	if t.has("week") and int(t["week"]) != week:
		return false
	if t.has("day") and str(t["day"]) != day_name():
		return false
	if t.has("slot") and str(t["slot"]) != slot_name():
		return false
	if t.has("min_stats"):
		for k in t["min_stats"]:
			if int(stats.get(k, 0)) < int(t["min_stats"][k]):
				return false
	if t.has("flags"):
		for fl in t["flags"]:
			if flags.get(fl, false) != t["flags"][fl]:
				return false
	return true

# --- Queries for the UI -----------------------------------------------------
## Activities available in the current day/slot given their requirements.
func available_activities() -> Array:
	var out: Array = []
	for a in GameData.activities:
		if _activity_available(a):
			out.append(a)
	return out

func _activity_available(a: Dictionary) -> bool:
	var slots: Variant = a.get("slots", null)
	if slots != null and not (slot_name() in slots):
		return false
	var days: Variant = a.get("days", null)
	if days != null and not (day_name() in days):
		return false
	var req: Dictionary = a.get("requirements", {})
	if req.has("min_energy") and energy < int(req["min_energy"]):
		return false
	if req.has("min_stats"):
		for k in req["min_stats"]:
			if int(stats.get(k, 0)) < int(req["min_stats"][k]):
				return false
	if req.has("flags"):
		for fl in req["flags"]:
			if flags.get(fl, false) != req["flags"][fl]:
				return false
	return true

# --- Save / load ------------------------------------------------------------
func save_game(path := "user://savegame.json") -> bool:
	var data := {
		"version": SAVE_VERSION,
		"semester": semester, "week": week,
		"day_index": day_index, "slot_index": slot_index,
		"stats": stats, "energy": energy, "max_energy": max_energy,
		"relationships": relationships, "flags": flags, "fired_events": fired_events,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[GameState] could not open save file for writing: %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	message.emit("[i]Game saved.[/i]")
	return true

func load_game(path := "user://savegame.json") -> bool:
	if not FileAccess.file_exists(path):
		message.emit("[i]No save file found.[/i]")
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("[GameState] save file is corrupt: %s" % path)
		return false
	var d: Dictionary = parsed
	semester = int(d.get("semester", 1))
	week = int(d.get("week", 1))
	day_index = int(d.get("day_index", 0))
	slot_index = int(d.get("slot_index", 0))
	stats = d.get("stats", stats)
	energy = int(d.get("energy", 100))
	max_energy = int(d.get("max_energy", 100))
	relationships = d.get("relationships", {})
	flags = d.get("flags", {})
	fired_events = d.get("fired_events", {})
	message.emit("[i]Game loaded.[/i]")
	state_changed.emit()
	return true
