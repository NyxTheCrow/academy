extends Node
## GameState — THE SPINE.
##
## Two core states: TIME (minute clock over an absolute day count) and LOCATION.
## The clock only moves through advance_time(); state only mutates through
## apply_effects(). Player-facing state is numberless (words); dev mode shows
## the numbers.

signal state_changed
signal message(text: String)
signal time_advanced(minutes: int)
signal day_changed

# --- Calendar ---------------------------------------------------------------
const DAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const DAY_MINUTES := 1440
const START_MINUTES := 420          # 07:00
const WALK_MINUTES := 5
const SAVE_VERSION := 4

# Calendar hierarchy (all display-derived from day_count):
const WEEKS_PER_MONTH := 4
const MONTHS_PER_TRIMESTER := 3
const TRIMESTERS_PER_YEAR := 3
const DAYS_PER_MONTH := 28          # 4 weeks
const DAYS_PER_TRIMESTER := 84      # 3 months
const DAYS_PER_YEAR := 252          # 3 trimesters

var day_count: int = 0              # absolute days since the game began
var minutes_of_day: int = START_MINUTES

# --- Location ---------------------------------------------------------------
var location: String = "room"

# --- Player -----------------------------------------------------------------
var player_name: String = "Student"
var dev_mode: bool = false
var stats := {}                     # focus (the day's mental bandwidth)
var needs := {}                     # visible self-assessed conditions
var tags: Array = []
var max_energy: int = 100
var energy: int = 100
var relationships := {}
var flags := {}
var fired_events := {}
var inventory: Array = []
var favorites: Array = []

func _ready() -> void:
	randomize()
	reset()

func reset() -> void:
	day_count = 0
	minutes_of_day = START_MINUTES
	location = "room"
	player_name = "Student"
	dev_mode = false
	# focus = the day's mental bandwidth for learning; refills each morning.
	stats = {"focus": 100}
	needs = {"hunger": 75.0, "thirst": 75.0, "bladder": 85.0, "hygiene": 85.0, "calm": 50.0, "mana": 100.0}
	tags = ["student", "enrolled"]
	max_energy = 100
	energy = 100
	relationships = {}
	flags = {}
	fired_events = {}
	inventory = ["textbook", "bread"]
	favorites = []
	state_changed.emit()

# --- Calendar helpers (display-derived) -------------------------------------
func weekday_index() -> int:
	return day_count % 7

func day_name() -> String:
	return DAYS[weekday_index()]

func is_school_day() -> bool:
	return weekday_index() < 5

func week_of_year() -> int:
	return day_count / 7                       # 0-based

func week_of_month() -> int:
	return (day_count / 7) % WEEKS_PER_MONTH    # 0-based

func month_of_trimester() -> int:
	return (day_count / DAYS_PER_MONTH) % MONTHS_PER_TRIMESTER

func trimester_of_year() -> int:
	return (day_count / DAYS_PER_TRIMESTER) % TRIMESTERS_PER_YEAR

func year_index() -> int:
	return day_count / DAYS_PER_YEAR

func time_string() -> String:
	return "%02d:%02d" % [minutes_of_day / 60, minutes_of_day % 60]

func date_string() -> String:
	return "Trimester %d · Month %d · Week %d · %s · %s" % [
		trimester_of_year() + 1, month_of_trimester() + 1, week_of_month() + 1, day_name(), time_string()]

func _hm(s) -> int:
	var parts: PackedStringArray = str(s).split(":")
	var h := int(parts[0])
	var m := int(parts[1]) if parts.size() > 1 else 0
	return h * 60 + m

## Advance the clock by `mins`. The ONLY place the clock moves.
func advance_time(mins: int) -> void:
	minutes_of_day += maxi(0, mins)
	while minutes_of_day >= DAY_MINUTES:
		minutes_of_day -= DAY_MINUTES
		_advance_day()
	_drift_needs(maxi(0, mins))
	time_advanced.emit(mins)
	_check_events()
	state_changed.emit()

func _advance_day() -> void:
	day_count += 1
	energy = max_energy
	stats["focus"] = 100   # a fresh day's mental bandwidth
	day_changed.emit()

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

# --- Needs drift ------------------------------------------------------------
## Needs drift per minute (stored as floats so small steps accumulate).
## Rates are tuned so a waking day taxes you but a night's sleep doesn't zero
## you out. Mana is excluded (it recovers instead); calm eases toward a normal
## baseline from either direction; focus is a stat (daily reset), not a need.
func _drift_needs(minutes: int) -> void:
	var m := float(minutes)
	needs["hunger"] = clampf(float(needs.get("hunger", 0)) - m * 0.08, 0, 100)
	needs["thirst"] = clampf(float(needs.get("thirst", 0)) - m * 0.12, 0, 100)
	needs["bladder"] = clampf(float(needs.get("bladder", 0)) - m * 0.10, 0, 100)
	needs["hygiene"] = clampf(float(needs.get("hygiene", 0)) - m * 0.04, 0, 100)
	needs["mana"] = clampf(float(needs.get("mana", 0)) + m * 0.08, 0, 100)  # recovers
	# Calm (stress/fear) settles toward a normal baseline of 50, up or down.
	var calm := float(needs.get("calm", 50))
	var baseline := 50.0
	var step := m * 0.08
	if calm < baseline:
		needs["calm"] = minf(baseline, calm + step)
	elif calm > baseline:
		needs["calm"] = maxf(baseline, calm - step)

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

# --- Requirements -----------------------------------------------------------
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
func apply_effects(effects: Dictionary) -> void:
	if effects.has("stats"):
		for k in effects["stats"]:
			stats[k] = int(stats.get(k, 0)) + int(effects["stats"][k])
		if stats.has("focus"):
			stats["focus"] = clampi(int(stats["focus"]), 0, 100)
	if effects.has("needs"):
		for k in effects["needs"]:
			needs[k] = clampf(float(needs.get(k, 0)) + float(effects["needs"][k]), 0, 100)
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

static func merge_effects(into: Dictionary, add: Dictionary) -> void:
	for cat in ["stats", "needs", "relationships"]:
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

# --- Qualitative descriptors ------------------------------------------------
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

## Focus = the day's remaining mental bandwidth for learning (0–100).
static func focus_descriptor(v: int) -> String:
	if v >= 85: return "Sharp"
	elif v >= 60: return "Clear"
	elif v >= 35: return "Foggy"
	elif v >= 15: return "Frazzled"
	else: return "Burnt out"

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

## Self-assessment word for a need (higher value = better/fuller).
static func need_descriptor(key: String, v: int) -> String:
	match key:
		"hunger":
			if v >= 85: return "Full"
			elif v >= 60: return "Satisfied"
			elif v >= 35: return "Peckish"
			elif v >= 15: return "Hungry"
			else: return "Starving"
		"thirst":
			if v >= 85: return "Slaked"
			elif v >= 60: return "Fine"
			elif v >= 35: return "Thirsty"
			elif v >= 15: return "Parched"
			else: return "Dry as dust"
		"bladder":
			if v >= 80: return "Empty"
			elif v >= 55: return "Comfortable"
			elif v >= 30: return "Need to go"
			elif v >= 12: return "Bursting"
			else: return "Desperate"
		"hygiene":
			if v >= 85: return "Fresh"
			elif v >= 60: return "Clean"
			elif v >= 35: return "Grubby"
			elif v >= 15: return "Filthy"
			else: return "Reeking"
		"calm":
			if v >= 85: return "Serene"
			elif v >= 60: return "Composed"
			elif v >= 40: return "Tense"
			elif v >= 20: return "Anxious"
			else: return "Panicked"
		"mana":
			if v >= 85: return "Brimming"
			elif v >= 60: return "Ample"
			elif v >= 35: return "Low"
			elif v >= 15: return "Nearly spent"
			else: return "Empty"
	return str(v)

func stat_word(key: String) -> String:
	var v := int(stats.get(key, 0))
	return focus_descriptor(v) if key == "focus" else stat_descriptor(v)

# --- Favourites & inventory -------------------------------------------------
func is_favorite(id: String) -> bool:
	return id in favorites

func toggle_favorite(id: String) -> void:
	if id in favorites:
		favorites.erase(id)
	else:
		favorites.append(id)
	state_changed.emit()

func has_item(id: String) -> bool:
	return id in inventory

func add_item(id: String) -> void:
	inventory.append(id)
	state_changed.emit()

func remove_item(id: String) -> void:
	inventory.erase(id)
	state_changed.emit()

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

const SAVE_DIR := "user://saves/"

func slot_path(slot: int) -> String:
	return "%sslot_%d.json" % [SAVE_DIR, slot]

func save_slot(slot: int) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	return save_game(slot_path(slot))

func load_slot(slot: int) -> bool:
	return load_game(slot_path(slot))

func delete_slot(slot: int) -> void:
	var p := slot_path(slot)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	state_changed.emit()

## Metadata for a save slot without loading it: {exists, name, when, saved_at}.
func slot_info(slot: int) -> Dictionary:
	var p := slot_path(slot)
	if not FileAccess.file_exists(p):
		return {"exists": false}
	var f := FileAccess.open(p, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {"exists": true, "name": "(corrupt)", "when": "", "saved_at": 0.0}
	var d: Dictionary = parsed
	return {
		"exists": true,
		"name": str(d.get("player_name", "?")),
		"when": str(d.get("save_label", "")),
		"saved_at": float(d.get("saved_at", 0.0)),
	}

func save_game(path := "user://savegame.json") -> bool:
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"save_label": "%s · %s" % [player_name, date_string()],
		"player_name": player_name, "dev_mode": dev_mode,
		"day_count": day_count, "minutes_of_day": minutes_of_day, "location": location,
		"stats": stats, "needs": needs, "tags": tags, "energy": energy, "max_energy": max_energy,
		"relationships": relationships, "flags": flags, "fired_events": fired_events,
		"inventory": inventory, "favorites": favorites,
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
	day_count = int(d.get("day_count", 0))
	minutes_of_day = int(d.get("minutes_of_day", START_MINUTES))
	location = str(d.get("location", "room"))
	stats = d.get("stats", stats)
	needs = d.get("needs", needs)
	tags = d.get("tags", [])
	energy = int(d.get("energy", 100))
	max_energy = int(d.get("max_energy", 100))
	relationships = d.get("relationships", {})
	flags = d.get("flags", {})
	fired_events = d.get("fired_events", {})
	inventory = d.get("inventory", [])
	favorites = d.get("favorites", [])
	var sn = _students_node()
	if sn:
		sn.deserialize(d.get("students", []))
	message.emit("[i]Game loaded.[/i]")
	state_changed.emit()
	return true
