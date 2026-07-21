extends Node
## GameState — THE SPINE.
##
## Two core states: TIME (minute-resolution clock) and LOCATION (where you are).
## Everything a character can do is an "action" gated by a shared requirement
## system (tags / time / stats / flags). The clock only moves through
## advance_time(); state only mutates through apply_effects().

signal state_changed
signal message(text: String)
signal time_advanced(minutes: int)  ## NPCs act on this
signal day_changed                  ## NPCs refill energy on this

# --- Calendar / time --------------------------------------------------------
const DAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const WEEKS_PER_SEMESTER := 4
const DAY_MINUTES := 1440
const START_MINUTES := 420          # 07:00
const WALK_MINUTES := 5             # cost of moving between adjacent locations
const SAVE_VERSION := 3

var semester: int = 1
var week: int = 1
var day_index: int = 0
var minutes_of_day: int = START_MINUTES

# --- Location ---------------------------------------------------------------
var location: String = "room"

# --- Player -----------------------------------------------------------------
var player_name: String = "Student"
var dev_mode: bool = false
var stats := {}
var tags: Array = []       # variables/tags that gate actions
var max_energy: int = 100
var energy: int = 100
var relationships := {}
var flags := {}
var fired_events := {}

func _ready() -> void:
	randomize()
	reset()

func reset() -> void:
	semester = 1
	week = 1
	day_index = 0
	minutes_of_day = START_MINUTES
	location = "room"
	player_name = "Student"
	dev_mode = false
	stats = {"magic": 0, "combat": 0, "knowledge": 0, "charisma": 0}
	tags = ["student", "enrolled"]
	max_energy = 100
	energy = 100
	relationships = {}
	flags = {}
	fired_events = {}
	state_changed.emit()

# --- Time helpers -----------------------------------------------------------
func day_name() -> String:
	return DAYS[day_index]

func time_string() -> String:
	return "%02d:%02d" % [minutes_of_day / 60, minutes_of_day % 60]

func date_string() -> String:
	return "Semester %d  ·  Week %d  ·  %s  ·  %s" % [semester, week, day_name(), time_string()]

## Player-facing date with no numbers (e.g. "Monday, Morning").
func brief_date() -> String:
	return "%s, %s" % [day_name(), time_of_day()]

func time_of_day() -> String:
	var h := minutes_of_day / 60
	if h < 5: return "Deep Night"
	elif h < 8: return "Dawn"
	elif h < 12: return "Morning"
	elif h < 14: return "Midday"
	elif h < 17: return "Afternoon"
	elif h < 21: return "Evening"
	else: return "Night"

# --- Qualitative descriptors (player mode shows these instead of numbers) ----
## Whether the UI should show raw numbers. Player mode = numberless.
func show_numbers() -> bool:
	return dev_mode

func energy_descriptor() -> String:
	if energy >= 80: return "Fresh"
	elif energy >= 55: return "Rested"
	elif energy >= 30: return "Tired"
	elif energy >= 10: return "Drowsy"
	else: return "Exhausted"

static func stat_descriptor(v: int) -> String:
	if v <= 1: return "Untrained"
	elif v <= 4: return "Novice"
	elif v <= 9: return "Apprentice"
	elif v <= 15: return "Adept"
	elif v <= 24: return "Skilled"
	else: return "Master"

static func hp_descriptor(hp: int, maxhp: int) -> String:
	if hp >= maxhp: return "Unhurt"
	var f := float(hp) / float(maxi(1, maxhp))
	if f >= 0.7: return "Grazed"
	elif f >= 0.4: return "Wounded"
	elif f >= 0.15: return "Bloodied"
	else: return "Near death"

static func relationship_descriptor(v: int) -> String:
	if v <= 0: return "Stranger"
	elif v <= 3: return "Acquaintance"
	elif v <= 7: return "Friend"
	elif v <= 12: return "Close"
	else: return "Inseparable"

## Parse "HH:MM" into minutes-of-day.
func _hm(s) -> int:
	var parts: PackedStringArray = str(s).split(":")
	var h := int(parts[0])
	var m := int(parts[1]) if parts.size() > 1 else 0
	return h * 60 + m

## Advance the clock by `mins` minutes. The ONLY place the clock moves.
func advance_time(mins: int) -> void:
	minutes_of_day += maxi(0, mins)
	while minutes_of_day >= DAY_MINUTES:
		minutes_of_day -= DAY_MINUTES
		_advance_day()
	time_advanced.emit(mins)
	_check_events()
	state_changed.emit()

func _advance_day() -> void:
	day_index += 1
	energy = max_energy
	day_changed.emit()
	if day_index >= DAYS.size():
		day_index = 0
		week += 1
		if week > WEEKS_PER_SEMESTER:
			week = 1
			semester += 1
			message.emit("A new semester begins. (Semester %d)" % semester)

## Sleep until 07:00 the next morning; fully rested.
func sleep() -> void:
	var delta := (DAY_MINUTES - minutes_of_day) + START_MINUTES
	advance_time(delta)
	energy = max_energy
	message.emit("[i]You sleep, and wake at %s.[/i]" % time_string())
	state_changed.emit()

func set_location(loc: String) -> void:
	location = loc
	state_changed.emit()

# --- Tags -------------------------------------------------------------------
func has_tag(t: String) -> bool:
	return t in tags

func add_tag(t: String) -> void:
	if not (t in tags):
		tags.append(t)
		state_changed.emit()

func remove_tag(t: String) -> void:
	tags.erase(t)
	state_changed.emit()

# --- Requirements (shared by location actions AND combat actions) -----------
## True if `req` is satisfied by an actor with `tags_in`/`stats_in`/`energy_in`.
## Time, day, and story flags are global (read from GameState).
func requirement_met(req: Dictionary, tags_in: Array, stats_in: Dictionary, energy_in: int) -> bool:
	if req.is_empty():
		return true
	if req.has("tags"):
		for t in req["tags"]:
			if not (t in tags_in):
				return false
	if req.has("without_tags"):
		for t in req["without_tags"]:
			if t in tags_in:
				return false
	if req.has("time_after") and minutes_of_day < _hm(req["time_after"]):
		return false
	if req.has("time_before") and minutes_of_day >= _hm(req["time_before"]):
		return false
	if req.has("days") and not (day_name() in req["days"]):
		return false
	if req.has("min_energy") and energy_in < int(req["min_energy"]):
		return false
	if req.has("min_stats"):
		for k in req["min_stats"]:
			if int(stats_in.get(k, 0)) < int(req["min_stats"][k]):
				return false
	if req.has("flags"):
		for f in req["flags"]:
			if flags.get(f, false) != req["flags"][f]:
				return false
	return true

# --- Locations & actions ----------------------------------------------------
func current_location() -> Dictionary:
	return GameData.locations.get(location, {})

## Actions the PLAYER can take here now: location actions whose requirements
## are met, plus a movement action for each connection.
func available_actions() -> Array:
	var loc := current_location()
	var out: Array = []
	for a in loc.get("actions", []):
		if requirement_met(a.get("requires", {}), tags, stats, energy):
			out.append(a)
	for conn in loc.get("connections", []):
		var dest: Dictionary = GameData.locations.get(conn, {})
		out.append({
			"id": "go_" + str(conn), "name": "Go to " + str(dest.get("name", conn)),
			"goto": conn, "duration": WALK_MINUTES, "move": true,
		})
	return out

# --- Resolution -------------------------------------------------------------
## Apply an effects dictionary. The single mutation gateway.
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
	if effects.has("tags"):
		for t in effects["tags"]:
			if not (t in tags):
				tags.append(t)
	if effects.has("remove_tags"):
		for t in effects["remove_tags"]:
			tags.erase(t)
	state_changed.emit()

## Merge effects `add` into `into` (accumulate a dialogue/combat result). Static.
static func merge_effects(into: Dictionary, add: Dictionary) -> void:
	for cat in ["stats", "relationships"]:
		if add.has(cat):
			if not into.has(cat):
				into[cat] = {}
			for k in add[cat]:
				into[cat][k] = int(into[cat].get(k, 0)) + int(add[cat][k])
	if add.has("energy"):
		into["energy"] = int(into.get("energy", 0)) + int(add["energy"])
	for listcat in ["tags", "remove_tags"]:
		if add.has(listcat):
			if not into.has(listcat):
				into[listcat] = []
			for t in add[listcat]:
				if not (t in into[listcat]):
					into[listcat].append(t)
	if add.has("flags"):
		if not into.has("flags"):
			into["flags"] = {}
		for k in add["flags"]:
			into["flags"][k] = add["flags"][k]

# --- Events -----------------------------------------------------------------
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
	if t.has("location") and str(t["location"]) != location:
		return false
	if t.has("time_after") and minutes_of_day < _hm(t["time_after"]):
		return false
	if t.has("time_before") and minutes_of_day >= _hm(t["time_before"]):
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

# --- Save / load ------------------------------------------------------------
func _students_node():
	return get_node_or_null("/root/Students")

func save_game(path := "user://savegame.json") -> bool:
	var data := {
		"version": SAVE_VERSION,
		"player_name": player_name, "dev_mode": dev_mode,
		"semester": semester, "week": week, "day_index": day_index,
		"minutes_of_day": minutes_of_day, "location": location,
		"stats": stats, "tags": tags, "energy": energy, "max_energy": max_energy,
		"relationships": relationships, "flags": flags, "fired_events": fired_events,
		"students": _students_node().serialize() if _students_node() else [],
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[GameState] could not open save file: %s" % path)
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
	player_name = str(d.get("player_name", "Student"))
	dev_mode = bool(d.get("dev_mode", false))
	semester = int(d.get("semester", 1))
	week = int(d.get("week", 1))
	day_index = int(d.get("day_index", 0))
	minutes_of_day = int(d.get("minutes_of_day", START_MINUTES))
	location = str(d.get("location", "room"))
	stats = d.get("stats", stats)
	tags = d.get("tags", [])
	energy = int(d.get("energy", 100))
	max_energy = int(d.get("max_energy", 100))
	relationships = d.get("relationships", {})
	flags = d.get("flags", {})
	fired_events = d.get("fired_events", {})
	var sn = _students_node()
	if sn:
		sn.deserialize(d.get("students", []))
	message.emit("[i]Game loaded.[/i]")
	state_changed.emit()
	return true
