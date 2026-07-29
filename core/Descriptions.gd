extends RefCounted
class_name Descriptions
## Descriptions — the graded-reveal resolver.
##
## The design's core thesis (design/01): the same underlying fact is rendered at
## N levels of clarity depending on the relevant skill. "Sensing your own mana"
## reads as fuzzy nonsense to a novice and a precise band to an adept. That is a
## content pattern used EVERYWHERE — locations, interactions, class sessions,
## spells, occurrences — so it is a first-class shared primitive here, not a
## bespoke method buried in the class system (as resolve_class_event_text was).
##
## A "description" is an ordered list of variants:
##   [ { "requires": {min_skills:{self_mana_awareness: 6}}, "text": "precise…" },
##     { "requires": {min_skills:{self_mana_awareness: 2}}, "text": "fuzzy…" },
##     { "text": "you feel nothing at all…" } ]     # bare default, listed LAST
##
## resolve() returns the FIRST variant whose `requires` the actor meets, so
## authors list sharper/higher-skill variants first and a no-requires fallback
## last. Requirements are evaluated through the same Requirements.met() as
## everything else, so a variant can branch on ANY state (skills, tags, flags…).

## Resolve a variant list to a single string for `actor`. Returns "" if nothing
## matches (author-error: no fallback variant).
static func resolve(variants: Variant, actor, world = null) -> String:
	for v in _as_list(variants):
		if v is String:
			return v
		if v is Dictionary and Requirements.met(actor, v.get("requires", {}), world):
			return str(v.get("text", ""))
	return ""

## How many distinct clarity levels a description offers (useful for the editor /
## validation — a graded-reveal field authored with a single variant is a smell).
static func level_count(variants: Variant) -> int:
	return _as_list(variants).size()

## A plain string, a single variant dict, or a list all normalise to a list.
static func _as_list(variants: Variant) -> Array:
	if variants is Array:
		return variants
	if variants is String:
		return [variants]
	if variants is Dictionary:
		return [variants]
	return []
