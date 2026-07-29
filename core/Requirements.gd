extends RefCounted
class_name Requirements
## Requirements — the ONE predicate evaluator.
##
## The old build had two forked evaluators (requirement_met for actions,
## _event_triggers for events) plus ad-hoc gating inside description variants.
## This unifies all of them: actions, events/occurrences, dialogue choices, and
## stat-gated description variants ALL gate through Requirements.met(actor, req).
##
## An `actor` supplies character state (tags, skills, needs, resources, traits,
## flags, relationships, location). A `world` (optional) supplies the clock, so
## purely stat-gated checks — like a description that sharpens with mana-sense —
## can pass `null` for the world and still evaluate.
##
## Supported keys (all optional; an empty req always passes):
##   tags / without_tags            — Array[String] the actor must / must not have
##   traits / without_traits        — Array[String]
##   min_skills / max_skills        — { skill_id: value }
##   min_needs / max_needs          — { need_id: value }
##   min_resources / max_resources  — { resource_id: value }
##   flags                          — { flag: expected_value }
##   relationships                  — { actor_id: min_bond }
##   has_items                      — Array[String]
##   at_location / location         — String (single) or Array (any-of)
##   time_after / time_before       — "HH:MM"  (needs world)
##   days                           — Array[String] of weekday names (needs world)

static func met(actor, req: Dictionary, world = null) -> bool:
	if req == null or req.is_empty():
		return true

	if req.has("tags"):
		for t in req["tags"]:
			if not actor.has_tag(str(t)):
				return false
	if req.has("without_tags"):
		for t in req["without_tags"]:
			if actor.has_tag(str(t)):
				return false

	if req.has("traits"):
		for tr in req["traits"]:
			if not (str(tr) in actor.traits):
				return false
	if req.has("without_traits"):
		for tr in req["without_traits"]:
			if str(tr) in actor.traits:
				return false

	if not _cmp(req.get("min_skills", {}), actor.skills, true): return false
	if not _cmp(req.get("max_skills", {}), actor.skills, false): return false
	if not _cmp(req.get("min_needs", {}), actor.needs, true): return false
	if not _cmp(req.get("max_needs", {}), actor.needs, false): return false
	if not _cmp(req.get("min_resources", {}), actor.resources, true): return false
	if not _cmp(req.get("max_resources", {}), actor.resources, false): return false

	if req.has("flags"):
		for f in req["flags"]:
			if actor.flags.get(f, false) != req["flags"][f]:
				return false

	if req.has("relationships"):
		for aid in req["relationships"]:
			if int(actor.relationships.get(aid, 0)) < int(req["relationships"][aid]):
				return false

	if req.has("has_items"):
		for it in req["has_items"]:
			if not (str(it) in actor.inventory):
				return false

	if req.has("at_location") or req.has("location"):
		var want: Variant = req.get("at_location", req.get("location"))
		var ok: bool = (actor.location == str(want)) if want is String else (actor.location in want)
		if not ok:
			return false

	# --- Time / day gates (need a world clock) ---
	if world != null:
		if req.has("time_after") and world.minutes_of_day < Clock.hm(req["time_after"]):
			return false
		if req.has("time_before") and world.minutes_of_day >= Clock.hm(req["time_before"]):
			return false
		if req.has("days") and not (world.day_name() in req["days"]):
			return false

	return true

## `>=` for every key when `at_least`, else `<=`. Missing values read as 0.
static func _cmp(reqs: Dictionary, have: Dictionary, at_least: bool) -> bool:
	for k in reqs:
		var v := float(have.get(k, 0.0))
		var threshold := float(reqs[k])
		if at_least and v < threshold:
			return false
		if not at_least and v > threshold:
			return false
	return true
