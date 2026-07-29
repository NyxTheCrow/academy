extends RefCounted
class_name Actor
## Actor — the unified character. The player and every NPC are the SAME kind of
## thing: one class, one set of fields, one behaviour. This is the single most
## important structural change from the old build, where the player was a pile of
## fields on a global singleton and NPCs were loose Dictionaries with a separate,
## divergent code path. Here the player is just `is_player == true`; the simulation
## treats all actors identically.
##
## An actor is defined entirely by numbers + labels:
##   skills     — floating-point competencies (the stat tree; some hidden)
##   needs      — hunger/thirst/… , 0..100, self-assessed conditions
##   resources  — energy/focus/mana, each 0..max, spent and restored
##   tags       — boolean facts ("enrolled", "pyromancer")
##   traits     — character traits that MODIFY behaviour (e.g. learn faster)
##   relationships / flags / inventory / favorites
##
## All behaviour delegates to the shared statics (Effects / Requirements /
## Descriptions) so there is exactly one implementation of each rule.

var id: String = "actor"
var name: String = "Someone"
var kind: String = "student"          # student | faculty | player | …
var is_player: bool = false
var location: String = "dormitories"

var tags: Array = []
var traits: Array = []
var skills: Dictionary = {}            # id -> float
var needs: Dictionary = {}             # id -> float (0..100)
var resources: Dictionary = {}         # id -> float
var resource_max: Dictionary = {}      # id -> float
var relationships: Dictionary = {}     # actor_id -> int
var flags: Dictionary = {}
var inventory: Array = []
var favorites: Array = []
var learn_rates: Dictionary = {}       # skill_id -> multiplier, folded from traits
var weights: Dictionary = {}           # AI: interaction_id -> bias

var current_action: String = "Idle"    # runtime-only, for the roster UI

# --- Behaviour (single source of truth) -------------------------------------
func has_tag(t: String) -> bool: return t in tags
func add_tag(t: String) -> void:
	if not (t in tags): tags.append(t)
func remove_tag(t: String) -> void: tags.erase(t)

func get_skill(sid: String) -> float: return float(skills.get(sid, 0.0))
func get_need(nid: String) -> float: return float(needs.get(nid, 0.0))
func get_resource(rid: String) -> float: return float(resources.get(rid, 0.0))
func resource_ratio(rid: String) -> float:
	return get_resource(rid) / maxf(1.0, float(resource_max.get(rid, 100.0)))

func apply(fx: Dictionary) -> void:
	Effects.apply(self, fx)

func meets(req: Dictionary, world = null) -> bool:
	return Requirements.met(self, req, world)

func describe(variants: Variant, world = null) -> String:
	return Descriptions.resolve(variants, self, world)

## How fast this actor learns a given skill, given its traits. Traits contribute
## a multiplier (data-driven, see content/traits.json); the default is 1.0. This
## is the "some characters learn certain things faster" hook you asked for.
func learn_multiplier(sid: String) -> float:
	return float(learn_rates.get(sid, 1.0))

## Grant a fractional amount of a skill, scaled by this actor's learning rate for
## it. THE single learning path — identical for the player and every NPC.
func learn(sid: String, base_amount: float) -> void:
	if sid == "":
		return
	skills[sid] = get_skill(sid) + base_amount * learn_multiplier(sid)

# --- Serialization ----------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "kind": kind, "is_player": is_player,
		"location": location, "tags": tags.duplicate(), "traits": traits.duplicate(),
		"skills": skills.duplicate(), "needs": needs.duplicate(),
		"resources": resources.duplicate(), "resource_max": resource_max.duplicate(),
		"relationships": relationships.duplicate(true), "flags": flags.duplicate(true),
		"inventory": inventory.duplicate(), "favorites": favorites.duplicate(),
		"learn_rates": learn_rates.duplicate(), "weights": weights.duplicate(true),
		"current_action": current_action,
	}

func from_dict(d: Dictionary) -> void:
	id = str(d.get("id", id))
	name = str(d.get("name", name))
	kind = str(d.get("kind", kind))
	is_player = bool(d.get("is_player", is_player))
	location = str(d.get("location", location))
	tags = (d.get("tags", []) as Array).duplicate()
	traits = (d.get("traits", []) as Array).duplicate()
	skills = (d.get("skills", {}) as Dictionary).duplicate()
	needs = (d.get("needs", {}) as Dictionary).duplicate()
	resources = (d.get("resources", {}) as Dictionary).duplicate()
	resource_max = (d.get("resource_max", {}) as Dictionary).duplicate()
	relationships = (d.get("relationships", {}) as Dictionary).duplicate(true)
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	inventory = (d.get("inventory", []) as Array).duplicate()
	favorites = (d.get("favorites", []) as Array).duplicate()
	learn_rates = (d.get("learn_rates", {}) as Dictionary).duplicate()
	weights = (d.get("weights", {}) as Dictionary).duplicate(true)
	current_action = str(d.get("current_action", current_action))

static func from_json(d: Dictionary) -> Actor:
	var a := Actor.new()
	a.from_dict(d)
	return a
