extends Node
## Students — the NPC manager (autoload).
##
## Four other students share the player's world: they each have a location and
## a set of tags, and they act through the very same location-action + tag
## requirement system the player uses. Each time the clock advances, every NPC
## takes one available action in its current location (possibly moving on).

var npcs: Array = []  # {id, name, location, tags, stats, energy, current_action}

func _ready() -> void:
	reset()
	GameState.time_advanced.connect(_on_time_advanced)
	GameState.day_changed.connect(_on_day_changed)

func reset() -> void:
	npcs.clear()
	for data in GameData.students:
		npcs.append(_make_npc(data))
	# Teachers are full NPCs too (promoted from the faculty registry).
	for tid in GameData.faculty:
		var f: Dictionary = (GameData.faculty[tid] as Dictionary).duplicate(true)
		f["id"] = tid
		if not f.has("tags"):
			f["tags"] = ["faculty"]
		if not f.has("location"):
			f["location"] = "classroom"
		npcs.append(_make_npc(f))

## Build a runtime NPC from a character definition (student or teacher). Every
## NPC carries the full stat sheet; any json stat values overlay it.
func _make_npc(data: Dictionary) -> Dictionary:
	var stats: Dictionary = GameState.default_stats()
	for k in data.get("stats", {}):
		stats[k] = int(data["stats"][k])
	return {
		"id": data.get("id", ""),
		"name": data.get("name", "Student"),
		"location": str(data.get("location", "room")),
		"tags": (data.get("tags", []) as Array).duplicate(),
		"stats": stats,
		"weights": (data.get("weights", {}) as Dictionary).duplicate(),
		"energy": 100,
		"current_action": "Waiting",
	}

func _on_day_changed() -> void:
	for npc in npcs:
		npc["energy"] = 100

func _on_time_advanced(_minutes: int) -> void:
	for npc in npcs:
		_npc_act(npc)

func location_name(loc: String) -> String:
	return str(GameData.get_location(loc).get("name", loc))

const CLASSROOM := "classroom"

func _npc_act(npc: Dictionary) -> void:
	# Attend the timetable: when a class this NPC belongs in is running, head to
	# the classroom and stay, doing a (weighted) in-class action. For now every
	# enrolled student shares the same schedule — all first-year classes.
	if _should_attend(npc):
		if str(npc["location"]) != CLASSROOM:
			var hop := _next_hop(str(npc["location"]), CLASSROOM)
			if hop != "":
				npc["location"] = hop
				npc["current_action"] = "heading to class"
				return
		else:
			# In the classroom: do a weighted in-class action if class is running,
			# otherwise wait for it to start (arrived early during the break) —
			# either way, stay put rather than wandering off.
			var seated := _class_options(npc)
			if not seated.is_empty():
				var pick: Dictionary = _pick_weighted(seated, npc)
				npc["current_action"] = str(pick.get("name", "in class"))
				_apply(npc, pick.get("effects", {}))
				# Same shared learning path as the player.
				GameState.apply_class_learning(npc["stats"], str(npc["location"]), pick)
			elif not GameState.class_in_session(CLASSROOM).is_empty() and "teacher" in npc["tags"]:
				npc["current_action"] = "teaching the class"
			else:
				npc["current_action"] = "waiting for class"
			return

	var loc := GameData.get_location(npc["location"])
	var options: Array = []
	for aid in loc.get("activities", []):
		var a := GameData.get_activity(str(aid))
		if a.is_empty():
			continue
		if a.has("dialogue") or a.has("combat") or a.has("tactical") or a.get("sleep", false) or a.get("wait_for_class", false) or a.has("goto"):
			continue  # player-only or navigation actions
		if GameState.requirement_met(a.get("requires", {}), npc["tags"], npc["stats"], npc["energy"], str(npc["location"])):
			options.append(a)
	# Movement options (NPCs wander).
	for conn in loc.get("connections", []):
		options.append({"name": "heading to " + location_name(conn), "goto": conn})
	if options.is_empty():
		npc["current_action"] = "idling in " + location_name(npc["location"])
		return
	var chosen: Dictionary = _pick_weighted(options, npc)
	if chosen.has("goto"):
		npc["location"] = str(chosen["goto"])
		npc["current_action"] = str(chosen["name"])
	else:
		npc["current_action"] = str(chosen.get("name", "…"))
		_apply(npc, chosen.get("effects", {}))
		# Class learning goes through the exact same path as the player.
		GameState.apply_class_learning(npc["stats"], str(npc["location"]), chosen)

## Weighted random choice among available options. A student's per-activity
## weights (data) bias which class action they lean toward; anything unlisted
## has weight 1. Movement options (no id) also default to 1.
func _pick_weighted(options: Array, npc: Dictionary) -> Dictionary:
	var weights: Dictionary = npc.get("weights", {})
	var total := 0.0
	for o in options:
		total += maxf(0.0, float(weights.get(str(o.get("id", "")), 1.0)))
	if total <= 0.0:
		return options[randi() % options.size()]
	var r := randf() * total
	for o in options:
		r -= maxf(0.0, float(weights.get(str(o.get("id", "")), 1.0)))
		if r <= 0.0:
			return o
	return options.back()

## Minutes before a class starts that students set off for it, so they can
## commute across the passing period and be seated in time (covers the map's
## worst-case two-hop walk).
const COMMUTE_LEAD := 40

## Should this NPC be heading to / in class right now? Enrolled students attend
## any class in session on the shared timetable — and leave a little early for
## the next one; the day's teacher attends the class they teach.
func _should_attend(npc: Dictionary) -> bool:
	var cls := GameState.class_in_session(CLASSROOM)
	if cls.is_empty():
		var nxt := GameState.next_class_at(CLASSROOM)
		if nxt.is_empty():
			return false
		if GameState._hm(nxt.get("start", "00:00")) - GameState.minutes_of_day > COMMUTE_LEAD:
			return false
		cls = nxt   # a class is imminent — head over during the break
	if "enrolled" in npc["tags"]:
		return true
	return str(npc["id"]) == str(cls.get("teacher_id", ""))

## Just the in-class learning actions available to this NPC (no wandering off).
func _class_options(npc: Dictionary) -> Array:
	var out: Array = []
	for aid in GameData.get_location(CLASSROOM).get("activities", []):
		var a := GameData.get_activity(str(aid))
		if a.is_empty() or str(a.get("class_learn", "")) == "":
			continue
		if GameState.requirement_met(a.get("requires", {}), npc["tags"], npc["stats"], npc["energy"], str(npc["location"])):
			out.append(a)
	return out

## First step from `here` toward `goal` across the location graph (BFS).
func _next_hop(here: String, goal: String) -> String:
	if here == goal:
		return ""
	var visited: Dictionary = {here: true}
	var queue: Array = [[here]]
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		for conn in GameData.get_location(str(path.back())).get("connections", []):
			var c := str(conn)
			if visited.has(c):
				continue
			visited[c] = true
			var np: Array = path + [c]
			if c == goal:
				return str(np[1])
			queue.append(np)
	return ""

func _apply(npc: Dictionary, effects: Dictionary) -> void:
	if effects.has("stats"):
		for k in effects["stats"]:
			npc["stats"][k] = int(npc["stats"].get(k, 0)) + int(effects["stats"][k])
	if effects.has("energy"):
		npc["energy"] = clampi(int(npc["energy"]) + int(effects["energy"]), 0, 100)
	if effects.has("tags"):
		for t in effects["tags"]:
			if not (t in npc["tags"]):
				npc["tags"].append(t)
	if effects.has("remove_tags"):
		for t in effects["remove_tags"]:
			npc["tags"].erase(t)

# --- Save / load ------------------------------------------------------------
func serialize() -> Array:
	return npcs.duplicate(true)

func deserialize(data: Variant) -> void:
	if data is Array and not (data as Array).is_empty():
		npcs = (data as Array).duplicate(true)
	else:
		reset()
