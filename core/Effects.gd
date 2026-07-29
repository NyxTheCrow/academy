extends RefCounted
class_name Effects
## Effects — the ONE way state mutates.
##
## The old build applied effects in three divergent places (GameState.apply_effects
## for the player, Students._apply for NPCs — which silently dropped needs, flags
## and relationships — and merge_effects for accumulation, which truncated floats).
## This is the single implementation used for EVERY actor, player or NPC, so the
## "one effect shape everywhere" promise actually holds.
##
## An effect bundle is a dictionary; every category is optional:
##   { "skills": {id: delta}, "needs": {id: delta}, "resources": {id: delta},
##     "energy"/"focus"/"mana": delta,        # shorthands for resources.*
##     "relationships": {actor_id: delta},
##     "flags": {k: v},                        # set (not add)
##     "tags": [...], "remove_tags": [...],
##     "traits": [...], "remove_traits": [...],
##     "add_items": [...], "remove_items": [...] }

const RESOURCE_SHORTHANDS := ["energy", "focus", "mana"]

## Apply `fx` to `actor` in place. Skills stay floating-point (class learning is
## fractional); needs clamp to 0..100; resources clamp to 0..their max.
static func apply(actor, fx: Dictionary) -> void:
	if fx == null or fx.is_empty():
		return

	for id in fx.get("skills", {}):
		actor.skills[id] = float(actor.skills.get(id, 0.0)) + float(fx["skills"][id])

	for id in fx.get("needs", {}):
		actor.needs[id] = clampf(float(actor.needs.get(id, 0.0)) + float(fx["needs"][id]), 0.0, 100.0)

	var res: Dictionary = fx.get("resources", {}).duplicate()
	for sh in RESOURCE_SHORTHANDS:
		if fx.has(sh):
			res[sh] = float(res.get(sh, 0.0)) + float(fx[sh])
	for id in res:
		var maxv := float(actor.resource_max.get(id, 100.0))
		actor.resources[id] = clampf(float(actor.resources.get(id, 0.0)) + float(res[id]), 0.0, maxv)

	for aid in fx.get("relationships", {}):
		actor.relationships[aid] = int(actor.relationships.get(aid, 0)) + int(fx["relationships"][aid])

	for k in fx.get("flags", {}):
		actor.flags[k] = fx["flags"][k]

	for t in fx.get("tags", []):
		actor.add_tag(str(t))
	for t in fx.get("remove_tags", []):
		actor.remove_tag(str(t))

	for tr in fx.get("traits", []):
		if not (str(tr) in actor.traits):
			actor.traits.append(str(tr))
	for tr in fx.get("remove_traits", []):
		actor.traits.erase(str(tr))

	for it in fx.get("add_items", []):
		actor.inventory.append(str(it))
	for it in fx.get("remove_items", []):
		actor.inventory.erase(str(it))

## Accumulate `add` into `into` (used to fold up a dialogue's chosen effects into
## one bundle before applying). Preserves floats and merges every category.
static func merge(into: Dictionary, add: Dictionary) -> void:
	if add == null:
		return
	for cat in ["skills", "needs", "resources", "relationships"]:
		if add.has(cat):
			var dst: Dictionary = into.get(cat, {})
			for k in add[cat]:
				dst[k] = float(dst.get(k, 0.0)) + float(add[cat][k])
			into[cat] = dst
	for sh in RESOURCE_SHORTHANDS:
		if add.has(sh):
			into[sh] = float(into.get(sh, 0.0)) + float(add[sh])
	for listcat in ["tags", "remove_tags", "traits", "remove_traits", "add_items", "remove_items"]:
		if add.has(listcat):
			var lst: Array = into.get(listcat, [])
			for v in add[listcat]:
				if not (v in lst):
					lst.append(v)
			into[listcat] = lst
	if add.has("flags"):
		var f: Dictionary = into.get("flags", {})
		for k in add["flags"]:
			f[k] = add["flags"][k]
		into["flags"] = f
