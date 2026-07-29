extends RefCounted
class_name World
## World — the runtime simulation loop, built on the core primitives. This is the
## replacement for the old GameState/Students split: it owns the clock and the
## full roster of Actors, and it is the ONE place time moves and the ONE place the
## world ticks. The player is just the actor with is_player == true; every other
## actor is driven by the SAME interaction + requirement machinery, so "make the
## simulation easy" holds — there is no separate NPC code path.
##
## Responsibilities:
##   * advance_time() — steps the clock, drifts needs/resources, refills on the
##     day boundary, runs every NPC's turn, and fires due one-time occurrences.
##   * available_interactions(actor) — what an actor can do here and now (shared
##     by the player UI and the NPC AI).
##   * resolve_interaction(actor, i) — apply one interaction's effects / movement /
##     class-learning, and (for the player) surface any attached one-time sub-event.
##
## It emits signals a UI can bind to, and serializes to a save dict.

signal state_changed
signal message(text: String)
signal time_advanced(minutes: int)
signal day_changed

const BASELINE_DRIFT := 0.08     # per-minute easing of a baselined need (e.g. calm)
const COMMUTE_LEAD := 60         # minutes early an actor sets off for a class

var content: Content
var clock: Clock
var actors: Array = []           # of Actor
var player: Actor = null
var fired: Dictionary = {}       # occurrence id -> true (world fire-once ledger)
var dev_mode: bool = false       # player-facing: show numbers instead of words

var _time_step := 20
var _max_steps := 200
var _walk_minutes := 5

# --- Setup ------------------------------------------------------------------
func setup(c: Content) -> void:
	content = c
	var clock_cfg: Dictionary = content.tuning.get("clock", {})
	clock = Clock.new(clock_cfg)
	var world_cfg: Dictionary = content.tuning.get("world", {})
	_time_step = int(world_cfg.get("time_step", 20))
	_max_steps = int(world_cfg.get("max_steps", 200))
	_walk_minutes = int(clock_cfg.get("walk_minutes", 5))
	fired = {}
	_build_roster()

func _build_roster() -> void:
	actors.clear()
	player = null
	for aid in content.actors:
		var a := content.build_actor(str(aid))
		if a == null:
			continue
		actors.append(a)
		if a.is_player:
			player = a
	if player == null and not actors.is_empty():
		player = actors[0]
		player.is_player = true

func actor_by_id(aid: String) -> Actor:
	for a in actors:
		if a.id == aid:
			return a
	return null

func actors_at(loc: String) -> Array:
	return actors.filter(func(a): return a.location == loc and not a.is_player)

# --- The clock (the ONLY time mover) ----------------------------------------
## Advance `mins`, processing the world in fixed steps so NPC turns, needs drift
## and events update at a steady granularity with the correct intermediate clock.
## Huge jumps fast-forward the remainder past a cap so this stays cheap.
func advance_time(mins: int) -> void:
	var remaining := maxi(0, mins)
	if remaining == 0:
		_fire_occurrences()
		state_changed.emit()
		return
	var steps := 0
	while remaining > 0 and steps < _max_steps:
		steps += 1
		var step := mini(remaining, _time_step)
		remaining -= step
		_tick(step)
	if remaining > 0:
		_tick(remaining)
	state_changed.emit()

func _tick(step: int) -> void:
	var rolled := clock.advance(step)
	for _i in rolled:
		_on_day()
	for a in actors:
		_drift(a, step)
	for a in actors:
		if not a.is_player:
			_act(a)
	time_advanced.emit(step)
	_fire_occurrences()

func _on_day() -> void:
	for a in actors:
		for r in content.resources_registry:
			if bool(r.get("daily_refill", false)):
				var rid := str(r.get("id", ""))
				a.resources[rid] = float(a.resource_max.get(rid, 100.0))
	day_changed.emit()

## Sleep until the next 07:00; the day rollover refills daily resources.
func sleep() -> void:
	advance_time(clock.minutes_until(clock.time_string() if false else "07:00"))
	message.emit("[i]You sleep, and wake at %s.[/i]" % clock.time_string())
	state_changed.emit()

# --- Needs / resources drift ------------------------------------------------
func _drift(a: Actor, minutes: int) -> void:
	var m := float(minutes)
	for n in content.needs_registry:
		var id := str(n.get("id", ""))
		if n.has("baseline"):
			var base := float(n["baseline"])
			var cur := a.get_need(id)
			if cur < base:
				a.needs[id] = minf(base, cur + m * BASELINE_DRIFT)
			elif cur > base:
				a.needs[id] = maxf(base, cur - m * BASELINE_DRIFT)
		else:
			var rate := float(n.get("decay_per_min", 0.0))
			a.needs[id] = clampf(a.get_need(id) + m * rate, 0.0, 100.0)
	for r in content.resources_registry:
		var rid := str(r.get("id", ""))
		var regen := float(r.get("regen_per_min", 0.0))
		if regen != 0.0:
			a.resources[rid] = clampf(a.get_resource(rid) + m * regen, 0.0, float(a.resource_max.get(rid, 100.0)))

# --- Classes (recurring events over the schedule) ---------------------------
func _class_templates() -> Array:
	return content.schedule.filter(func(e): return str(e.get("kind", "")) == "class")

func class_in_session(loc: String) -> Dictionary:
	for c in _class_templates():
		if str(c.get("room", "")) == loc and Events.in_session(c, clock):
			return c
	return {}

func next_class_at(loc: String) -> Dictionary:
	var best := {}
	var best_start := 1 << 30
	for c in _class_templates():
		if str(c.get("room", "")) != loc:
			continue
		var s := Events.next_start_today(c, clock)
		if s >= 0 and s < best_start:
			best_start = s
			best = c
	return best

## How much of a class's skill one in-class action grants, tuned so a full week
## yields the target level (focus_per_week / attend_per_week from tuning).
func class_learn_amount(cls: Dictionary, mode: String, minutes: int) -> float:
	var learn: Dictionary = content.tuning.get("learning", {})
	var target := float(learn.get("focus_per_week", 0.5)) if mode == "focus" else float(learn.get("attend_per_week", 0.25))
	var sessions := (cls.get("days", []) as Array).size()
	var slots := int((Clock.hm(cls.get("end", "00:00")) - Clock.hm(cls.get("start", "00:00"))) / maxi(1, minutes))
	if sessions <= 0 or slots <= 0:
		return 0.0
	return target / float(sessions * slots)

# --- Interactions -----------------------------------------------------------
## Everything `actor` can do here and now: location interactions it qualifies for,
## plus movement to each connected location. In-class ("learn_mode") interactions
## only appear while a class is in session at the actor's location.
func available_interactions(actor: Actor) -> Array:
	var out: Array = []
	var in_class := not class_in_session(actor.location).is_empty()
	for iid in content.interactions:
		var i: Dictionary = content.interactions[iid].duplicate(true)
		i["id"] = str(iid)
		if not _here(i, actor.location):
			continue
		if str(i.get("learn_mode", "")) != "" and not in_class:
			continue
		if not actor.meets(i.get("requires", {}), clock):
			continue
		out.append(i)
	for conn in _location(actor.location).get("connections", []):
		var dest: Dictionary = _location(str(conn))
		out.append({
			"id": "go_" + str(conn), "name": "Go to " + str(dest.get("name", conn)),
			"goto": str(conn), "duration": _walk_minutes, "move": true,
		})
	return out

func _here(interaction: Dictionary, loc: String) -> bool:
	if str(loc) in interaction.get("where", []):
		return true
	var loc_tags: Array = _location(loc).get("tags", [])
	for t in interaction.get("where_tags", []):
		if t in loc_tags:
			return true
	return false

## Apply one interaction to `actor` (no time cost — the caller advances the clock
## for the player). Returns { description, dialogue, one_time_id }.
func resolve_interaction(actor: Actor, interaction: Dictionary) -> Dictionary:
	var res := {"description": "", "dialogue": "", "one_time_id": ""}
	if interaction.has("goto"):
		actor.location = str(interaction["goto"])
		return res
	if interaction.has("dialogue"):
		res["dialogue"] = str(interaction["dialogue"])
		# effects still apply; the UI runs the conversation and merges its result.
	actor.apply(interaction.get("effects", {}))

	var learn_mode := str(interaction.get("learn_mode", ""))
	var cls := class_in_session(actor.location)
	if learn_mode != "" and not cls.is_empty():
		var skill := str(cls.get("skill", ""))
		if skill != "":
			actor.learn(skill, class_learn_amount(cls, learn_mode, int(interaction.get("duration", _time_step))))
		# One-time sub-events are the PLAYER's story beats; NPCs never consume them.
		if actor.is_player:
			var session := Events.resolve_session(cls, content.occurrences, clock, actor, fired)
			res["description"] = str(session.get("description", ""))
			if str(session.get("one_time_id", "")) != "":
				actor.apply(session.get("effects", {}))
				res["one_time_id"] = str(session["one_time_id"])
		else:
			res["description"] = actor.describe(interaction.get("description", ""))
	else:
		res["description"] = actor.describe(interaction.get("description", ""))
	return res

## The player takes an interaction: resolve it, log it, and advance the clock by
## its duration (which also drifts the world and fires events).
func player_take(interaction: Dictionary) -> Dictionary:
	var res := resolve_interaction(player, interaction)
	if str(res.get("description", "")) != "":
		message.emit(str(res["description"]))
	if str(res.get("one_time_id", "")) != "":
		var occ := _occurrence(str(res["one_time_id"]))
		if not occ.is_empty():
			message.emit("[color=gold]★ %s[/color]" % str(res["description"]))
	advance_time(int(interaction.get("duration", _walk_minutes)))
	return res

# --- One-time occurrences (free-standing) -----------------------------------
func _fire_occurrences() -> void:
	if player == null:
		return
	var free: Array = content.occurrences.filter(func(o): return str(o.get("attach_to", "")) == "")
	for occ in Events.due_occurrences(free, clock, player, fired):
		var txt := player.describe(occ.get("description", ""))
		if txt != "":
			message.emit("[color=gold]★ %s[/color]" % txt)
		player.apply(occ.get("effects", {}))

func _occurrence(oid: String) -> Dictionary:
	for o in content.occurrences:
		if str(o.get("id", "")) == oid:
			return o
	return {}

# --- NPC turn (the SAME interactions the player uses) -----------------------
func _act(actor: Actor) -> void:
	var target := _class_to_attend(actor)
	if not target.is_empty():
		var room := str(target.get("room", ""))
		if actor.location != room:
			var hop := _next_hop(actor.location, room)
			if hop != "":
				actor.location = hop
				actor.current_action = "heading to class"
				return
		# In the room: do a weighted in-class action if class is live, else wait.
		if not class_in_session(actor.location).is_empty():
			var seated := available_interactions(actor).filter(func(i): return str(i.get("learn_mode", "")) != "")
			if not seated.is_empty():
				var pick: Dictionary = _pick_weighted(seated, actor)
				actor.current_action = str(pick.get("name", "in class"))
				resolve_interaction(actor, pick)
				return
		actor.current_action = "waiting for class"
		return

	var options: Array = available_interactions(actor).filter(func(i):
		return not i.has("dialogue") and not i.get("sleep", false))
	if options.is_empty():
		actor.current_action = "idling in " + str(_location(actor.location).get("name", actor.location))
		return
	var chosen: Dictionary = _pick_weighted(options, actor)
	if chosen.has("goto"):
		actor.location = str(chosen["goto"])
		actor.current_action = str(chosen.get("name", "wandering"))
	else:
		actor.current_action = str(chosen.get("name", "…"))
		resolve_interaction(actor, chosen)

## The class this actor should be at now (or heading to): enrolled students attend
## any imminent/in-session class; a teacher attends the class they teach.
func _class_to_attend(actor: Actor) -> Dictionary:
	for c in _class_templates():
		var mine := actor.has_tag("enrolled") or str(c.get("teacher", "")) == actor.id
		if not mine:
			continue
		if Events.in_session(c, clock):
			return c
		var s := Events.next_start_today(c, clock)
		if s >= 0 and s - clock.minutes_of_day <= COMMUTE_LEAD:
			return c
	return {}

func _pick_weighted(options: Array, actor: Actor) -> Dictionary:
	var total := 0.0
	for o in options:
		total += maxf(0.0, float(actor.weights.get(str(o.get("id", "")), 1.0)))
	if total <= 0.0:
		return options[randi() % options.size()]
	var r := randf() * total
	for o in options:
		r -= maxf(0.0, float(actor.weights.get(str(o.get("id", "")), 1.0)))
		if r <= 0.0:
			return o
	return options.back()

## First step from `here` toward `goal` across the location graph (BFS).
func _next_hop(here: String, goal: String) -> String:
	if here == goal:
		return ""
	var visited := {here: true}
	var queue: Array = [[here]]
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		for conn in _location(str(path.back())).get("connections", []):
			var c := str(conn)
			if visited.has(c):
				continue
			visited[c] = true
			var np: Array = path + [c]
			if c == goal:
				return str(np[1])
			queue.append(np)
	return ""

# --- Small helpers ----------------------------------------------------------
func _location(loc: String) -> Dictionary:
	return content.locations.get(loc, {})

func location_name(loc: String) -> String:
	return str(_location(loc).get("name", loc))

# --- Save / load ------------------------------------------------------------
func to_dict() -> Dictionary:
	var actor_dicts: Array = []
	for a in actors:
		actor_dicts.append(a.to_dict())
	return {"clock": clock.to_dict(), "fired": fired.duplicate(true), "dev_mode": dev_mode, "actors": actor_dicts}

func from_dict(d: Dictionary) -> void:
	clock.from_dict(d.get("clock", {}))
	fired = (d.get("fired", {}) as Dictionary).duplicate(true)
	dev_mode = bool(d.get("dev_mode", dev_mode))
	var saved: Array = d.get("actors", [])
	if saved.is_empty():
		return
	actors.clear()
	player = null
	for ad in saved:
		var a := Actor.from_json(ad)
		actors.append(a)
		if a.is_player:
			player = a
	if player == null and not actors.is_empty():
		player = actors[0]
