extends Node
## GameState — THE SPINE.
##
## Owns the canonical clock and the entire player game state. Two rules keep the
## whole game coherent, and everything (activities, events, dialogue, combat,
## NPCs) routes through them:
##   1. The clock only ever moves through advance_time().
##   2. State only ever mutates through apply_effects().

signal state_changed             ## clock or player state changed; UI should refresh
signal message(text: String)     ## narrative / journal line for the UI
signal hour_ticked(hour: int)    ## emitted once per in-game hour advanced (NPCs listen)

# --- Time configuration -----------------------------------------------------
const DAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const WEEKS_PER_SEMESTER := 4
const DAY_START_HOUR := 8   # the day begins at 08:00
const DAY_END_HOUR := 22    # at 22:00 the student sleeps; clock rolls to next day
const SAVE_VERSION := 2

# --- The clock --------------------------------------------------------------
var semester: int = 1
var week: int = 1        # 1-based
var day_index: int = 0   # 0-based index into DAYS
var hour: int = DAY_START_HOUR

# --- Player state -----------------------------------------------------------
var player_name: String = "Student"
var dev_mode: bool = false
var stats := {}
var max_energy: int = 100
var energy: int = 100
var relationships := {}   # npc_id -> affinity (int)
var flags := {}           # arbitrary story flags
var fired_events := {}    # event_id -> true, so "once" events fire once

func _ready() -> void:
	randomize()
	reset()

## Reset core player state to a fresh new game. Does not touch NPCs (Students
## has its own reset) or the chosen name/dev_mode, which character creation sets.
func reset() -> void:
	semester = 1
	week = 1
	day_index = 0
	hour = DAY_START_HOUR
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

func time_string() -> String:
	return "%02d:00" % hour

func is_school_day() -> bool:
	return day_index < 5  # Monday..Friday

func date_string() -> String:
	return "Semester %d  ·  Week %d  ·  %s  ·  %s" % [semester, week, day_name(), time_string()]

## Advance the clock by `hours` in-game hours (default 1). The ONLY place the
## clock moves. Emits hour_ticked for each hour so NPCs can act, checks events.
func advance_time(hours := 1) -> void:
	for _i in range(max(1, hours)):
		hour += 1
		if hour >= DAY_END_HOUR:
			hour = DAY_START_HOUR
			_advance_day()
		hour_ticked.emit(hour)
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
## Perform a plain activity: optional skill check, apply effects, then advance
## by the activity's duration (hours). Mode-triggering activities (dialogue /
## combat) are driven by AcademyMode so their sub-scene can resolve first.
func perform_activity(activity: Dictionary) -> void:
	var act_name: String = activity.get("name", "Activity")
	var check: Variant = activity.get("skill_check", null)
	if check != null and check is Dictionary:
		_resolve_skill_check(act_name, check)
	else:
		apply_effects(activity.get("effects", {}))
		message.emit("You spent %d hour(s): %s." % [duration_of(activity), act_name])
	advance_time(duration_of(activity))

func duration_of(activity: Dictionary) -> int:
	return maxi(1, int(activity.get("duration", 1)))

func _resolve_skill_check(act_name: String, check: Dictionary) -> void:
	var stat_id: String = check.get("stat", "")
	var difficulty: int = int(check.get("difficulty", 5))
	var roll: int = randi_range(1, 6)
	var stat_value: int = int(stats.get(stat_id, 0))
	var total: int = stat_value + roll
	var ok := total >= difficulty
	if ok:
		apply_effects(check.get("success", {}))
	else:
		apply_effects(check.get("failure", {}))
	# The dice math is a "dev" detail; players just see the outcome.
	if dev_mode:
		message.emit("%s — %s (%s %d + roll %d = %d vs %d)" % [
			act_name, ("[color=lightgreen]Success![/color]" if ok else "[color=salmon]Failed.[/color]"),
			stat_id, stat_value, roll, total, difficulty])
	else:
		message.emit("%s — %s" % [act_name, ("[color=lightgreen]it goes well.[/color]" if ok else "[color=salmon]it doesn't click.[/color]")])

## Apply an effects dictionary to game state. The single mutation gateway.
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
	if t.has("hour") and int(t["hour"]) != hour:
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

# --- Availability (shared by the player and NPCs) ---------------------------
## True if activity `a` can be started at `hour_now` given `energy_now`/`flags_now`.
## day_index is always "now" (the whole world shares the calendar).
func availability_ok(a: Dictionary, hour_now: int, energy_now: int, flags_now: Dictionary) -> bool:
	var days: Variant = a.get("days", null)
	if days != null and not (day_name() in days):
		return false
	if a.has("hour_range"):
		var r: Array = a["hour_range"]
		if hour_now < int(r[0]) or hour_now > int(r[1]):
			return false
	elif a.has("hours"):
		if not (hour_now in a["hours"]):
			return false
	var req: Dictionary = a.get("requirements", {})
	if req.has("min_energy") and energy_now < int(req["min_energy"]):
		return false
	# Stat gates are player-only (stats are per-actor); available_activities()
	# applies them. NPCs share this time/energy/flag availability check.
	if req.has("flags"):
		for fl in req["flags"]:
			if flags_now.get(fl, false) != req["flags"][fl]:
				return false
	return true

## Activities the PLAYER can start right now.
func available_activities() -> Array:
	var out: Array = []
	for a in GameData.activities:
		if not availability_ok(a, hour, energy, flags):
			continue
		if a.has("requirements") and a["requirements"].has("min_stats"):
			var ok := true
			for k in a["requirements"]["min_stats"]:
				if int(stats.get(k, 0)) < int(a["requirements"]["min_stats"][k]):
					ok = false
			if not ok:
				continue
		out.append(a)
	return out

# --- Save / load ------------------------------------------------------------
# Resolve the Students autoload at runtime (it registers after GameState, so we
# must not reference it by its global name here — that would fail to compile).
func _students_node():
	return get_node_or_null("/root/Students")

func save_game(path := "user://savegame.json") -> bool:
	var data := {
		"version": SAVE_VERSION,
		"player_name": player_name, "dev_mode": dev_mode,
		"semester": semester, "week": week, "day_index": day_index, "hour": hour,
		"stats": stats, "energy": energy, "max_energy": max_energy,
		"relationships": relationships, "flags": flags, "fired_events": fired_events,
		"students": _students_node().serialize() if _students_node() else [],
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
	player_name = str(d.get("player_name", "Student"))
	dev_mode = bool(d.get("dev_mode", false))
	semester = int(d.get("semester", 1))
	week = int(d.get("week", 1))
	day_index = int(d.get("day_index", 0))
	hour = int(d.get("hour", DAY_START_HOUR))
	stats = d.get("stats", stats)
	energy = int(d.get("energy", 100))
	max_energy = int(d.get("max_energy", 100))
	relationships = d.get("relationships", {})
	flags = d.get("flags", {})
	fired_events = d.get("fired_events", {})
	var sn := _students_node()
	if sn:
		sn.deserialize(d.get("students", []))
	message.emit("[i]Game loaded.[/i]")
	state_changed.emit()
	return true
