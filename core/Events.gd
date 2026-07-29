extends RefCounted
class_name Events
## Events — the two kinds of "things that happen", cleanly separated from
## locations (which are now just places) and from each other:
##
##  * RECURRING events (the timetable skeleton): classes, meals, curfew. Defined
##    by a cadence (days + start/end) and a location. Every occurrence of a
##    recurring event shares the same skeleton — its base description and effects.
##
##  * ONE-TIME occurrences: story beats that fire once. Crucially, an occurrence
##    can be ATTACHED to a recurring event (`attach_to: "law"`), which makes it a
##    one-time SUB-EVENT hosted inside a specific session of that class — "the day
##    the professor calls on you". This is exactly the "recurring skeleton with
##    one-time inserts, because every class isn't the same" model you asked for.
##
## resolve_session() folds the two together: it returns the skeleton unless a
## pending attached sub-event matches this session, in which case the sub-event's
## description overrides and its effects merge on top — then it's consumed.

# --- Recurring cadence ------------------------------------------------------
## Is this recurring template in session right now (right weekday, inside its
## [start, end) window)? Optionally require a matching room/location.
static func in_session(template: Dictionary, world) -> bool:
	if not (world.day_name() in template.get("days", [])):
		return false
	var s := Clock.hm(template.get("start", "00:00"))
	var e := Clock.hm(template.get("end", "00:00"))
	return world.minutes_of_day >= s and world.minutes_of_day < e

## The next start-minute of this template later today, or -1 if none.
static func next_start_today(template: Dictionary, world) -> int:
	if not (world.day_name() in template.get("days", [])):
		return -1
	var s := Clock.hm(template.get("start", "00:00"))
	return s if s >= world.minutes_of_day else -1

## Templates in session at a location right now.
static func sessions_here(templates: Array, world, location: String) -> Array:
	var out: Array = []
	for t in templates:
		if str(t.get("room", t.get("location", ""))) == location and in_session(t, world):
			out.append(t)
	return out

# --- Session resolution (skeleton + one-time inserts) -----------------------
## Resolve the concrete content of the current session of `template` for `actor`.
## `occurrences` is the full one-time list; `fired` is the fire-once ledger
## (mutated). Returns { description, effects, one_time_id }.
static func resolve_session(template: Dictionary, occurrences: Array, world, actor, fired: Dictionary) -> Dictionary:
	var tid := str(template.get("id", ""))
	# A pending sub-event attached to this class that matches this session wins.
	for occ in occurrences:
		if str(occ.get("attach_to", "")) != tid:
			continue
		if bool(occ.get("once", true)) and fired.has(str(occ.get("id", ""))):
			continue
		if _trigger_matches(occ.get("trigger", {}), world, actor):
			if bool(occ.get("once", true)):
				fired[str(occ.get("id", ""))] = true
			var fx := (template.get("effects", {}) as Dictionary).duplicate(true)
			Effects.merge(fx, occ.get("effects", {}))
			return {
				"description": Descriptions.resolve(occ.get("description", template.get("description", "")), actor, world),
				"effects": fx,
				"one_time_id": str(occ.get("id", "")),
			}
	# Otherwise the recurring skeleton.
	return {
		"description": Descriptions.resolve(template.get("description", ""), actor, world),
		"effects": (template.get("effects", {}) as Dictionary).duplicate(true),
		"one_time_id": "",
	}

## Free-standing one-time occurrences (no attach_to) that are due now for `actor`.
## Marks fire-once ones as fired. Returns the list that fired, in order.
static func due_occurrences(occurrences: Array, world, actor, fired: Dictionary) -> Array:
	var out: Array = []
	for occ in occurrences:
		if str(occ.get("attach_to", "")) != "":
			continue
		if bool(occ.get("once", true)) and fired.has(str(occ.get("id", ""))):
			continue
		if _trigger_matches(occ.get("trigger", {}), world, actor):
			if bool(occ.get("once", true)):
				fired[str(occ.get("id", ""))] = true
			out.append(occ)
	return out

## A trigger mixes calendar keys (week/date/day, evaluated against the clock) with
## ordinary state keys (flags/tags/min_skills/…), which reuse Requirements.met so
## there is still one predicate language across the whole game.
static func _trigger_matches(trigger: Dictionary, world, actor) -> bool:
	if trigger == null or trigger.is_empty():
		return true
	if trigger.has("week") and world.week_of_year() != int(trigger["week"]):
		return false
	if trigger.has("date") and world.day_count != int(trigger["date"]):
		return false
	if trigger.has("day") and world.day_name() != str(trigger["day"]):
		return false
	var state := {}
	for k in trigger:
		if not (k in ["week", "date", "day"]):
			state[k] = trigger[k]
	return Requirements.met(actor, state, world)
