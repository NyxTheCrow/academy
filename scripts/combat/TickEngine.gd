extends RefCounted
## TickEngine — a rough prototype of Nyx's interrupt-driven, deterministic,
## timeline ("WEGO") combat. Pure logic, no UI, fully deterministic so it can
## be exercised headlessly in the test runner.
##
## Framework pieces this implements (deliberately the "tiny toy" the design doc
## recommends building first — no hidden spell identity, no theory checks yet):
##   * time is a stream of discrete TICKS; both sides queue actions that span
##     several ticks rather than resolving instantly;
##   * every action has PHASES: startup -> commit point -> active (resolve) ->
##     recovery. Before the commit point a plan can be interrupted to react;
##     after it, the action must resolve;
##   * REACTING is just queuing an action after seeing new information. A small
##     READINESS pool (regenerates when idle) is the concrete resource that
##     stops a unit from reacting perfectly to everything;
##   * attacks resolve DETERMINISTICALLY. Survivability is layered: a directional
##     ward absorbs one hit, otherwise the unit goes down (high lethality);
##   * the HEX GRID (axial coords, six neighbours) decides which attacks and
##     escapes are geometrically possible;
##   * a simple deterministic enemy can aim at your PROJECTED destination, so
##     "it predicted my move and put a ray there" actually happens.
##
## Everything numeric lives in data/tick_actions.json, so it stays editable.

const MAX_READINESS := 3
const WARD_TTL := 4          # how many ticks a raised ward lasts

var actions: Dictionary = {}   # action_id -> definition
var grid: Vector2i = Vector2i(7, 5)
var tick: int = 0
var units: Array = []          # array of unit dictionaries (see _make_unit)
var traps: Array = []          # { "pos": Vector2i, "damage": int, "owner": String }
var log: Array = []            # human-readable event strings, newest last
var last_error := ""

# --- Setup ------------------------------------------------------------------
func setup(cfg: Dictionary) -> void:
	actions = cfg.get("actions", {})
	if actions.is_empty() and GameData.tick_actions is Dictionary:
		actions = GameData.tick_actions
	grid = cfg.get("grid", Vector2i(7, 5))
	tick = 0
	traps.clear()
	log.clear()
	units.clear()
	for u in cfg.get("units", []):
		units.append(_make_unit(u))
	if units.is_empty():
		# A default duel: you on the left, a rival on the right.
		units.append(_make_unit({"id": "player", "team": "player", "name": "You",
			"pos": Vector2i(0, grid.y / 2)}))
		units.append(_make_unit({"id": "rival", "team": "enemy", "name": "Rival",
			"pos": Vector2i(grid.x - 1, grid.y / 2)}))
	_say("The duel begins.")

func _make_unit(u: Dictionary) -> Dictionary:
	return {
		"id": str(u.get("id", "unit")),
		"team": str(u.get("team", "enemy")),
		"name": str(u.get("name", "Unit")),
		"pos": u.get("pos", Vector2i.ZERO),
		"hp": int(u.get("hp", 1)),
		"ward": 0,
		"ward_dir": Vector2i.ZERO,
		"ward_ttl": 0,
		"down": false,
		"readiness": int(u.get("readiness", MAX_READINESS)),
		"plan": {},   # empty = idle
	}

# --- Queries ----------------------------------------------------------------
func unit_by_id(id: String) -> Dictionary:
	for u in units:
		if u["id"] == id:
			return u
	return {}

func player() -> Dictionary:
	for u in units:
		if u["team"] == "player":
			return u
	return {}

func enemies() -> Array:
	return units.filter(func(u): return u["team"] == "enemy" and not u["down"])

func is_over() -> bool:
	var live_players := units.filter(func(u): return u["team"] == "player" and not u["down"])
	return live_players.is_empty() or enemies().is_empty()

func winner() -> String:
	if not is_over():
		return ""
	var live_players := units.filter(func(u): return u["team"] == "player" and not u["down"])
	return "player" if not live_players.is_empty() else "enemy"

func unit_at(pos: Vector2i) -> Dictionary:
	for u in units:
		if not u["down"] and u["pos"] == pos:
			return u
	return {}

# Phase helpers on a unit's current plan (relative to the global tick).
func _elapsed(u: Dictionary) -> int:
	return tick - int(u["plan"].get("start", tick))

func is_idle(u: Dictionary) -> bool:
	return u["plan"].is_empty()

func is_preparing(u: Dictionary) -> bool:
	return not is_idle(u) and _elapsed(u) < int(u["plan"]["startup"])

func is_committed(u: Dictionary) -> bool:
	return not is_idle(u) and _elapsed(u) >= int(u["plan"]["commit"])

## A unit may start (or interrupt into) a new action only while idle or still
## preparing AND not yet past its commit point.
func can_act(u: Dictionary) -> bool:
	if u["down"]:
		return false
	return is_idle(u) or (is_preparing(u) and not is_committed(u))

func resolves_at(u: Dictionary) -> int:
	return int(u["plan"].get("start", tick)) + int(u["plan"].get("startup", 0))

## A unit refills readiness while it is NOT actively winding up or executing an
## attack: i.e. idle, holding (a "self"/wait action), or in the recovery tail of
## a finished action. This is the "catch your breath" model.
func _recovers_readiness(u: Dictionary) -> bool:
	if is_idle(u):
		return true
	if str(u["plan"]["kind"]) == "self":
		return true
	return tick > resolves_at(u)   # past the active tick -> recovering

# --- Commands ---------------------------------------------------------------
## Queue (or react with) an action. Returns false + sets last_error on failure.
func queue_action(unit_id: String, action_id: String, target: Vector2i) -> bool:
	var u := unit_by_id(unit_id)
	if u.is_empty():
		last_error = "no such unit"
		return false
	if not actions.has(action_id):
		last_error = "unknown action"
		return false
	if not can_act(u):
		last_error = "committed — cannot change action yet"
		return false
	var a: Dictionary = actions[action_id]
	var cost := int(a.get("readiness_cost", 1))
	if u["readiness"] < cost:
		last_error = "not ready (needs %d readiness)" % cost
		return false
	var interrupted := not is_idle(u)
	u["readiness"] -= cost
	u["plan"] = {
		"action": action_id,
		"name": str(a.get("name", action_id)),
		"kind": str(a.get("kind", "self")),
		"target": target,
		"start": tick,
		"startup": int(a.get("startup", 1)),
		"commit": int(a.get("commit", 1)),
		"recovery": int(a.get("recovery", 1)),
	}
	if interrupted:
		_say("%s interrupts and begins %s." % [u["name"], u["plan"]["name"]])
	else:
		_say("%s begins %s." % [u["name"], u["plan"]["name"]])
	return true

# --- The clock --------------------------------------------------------------
## Advance exactly one tick, resolving anything that fires on it. Returns an
## event dictionary describing anything notable that happened.
func step() -> Dictionary:
	tick += 1
	var ev := {"tick": tick, "resolved": [], "down": false}
	# Readiness regenerates while a unit isn't winding up or executing an attack.
	for u in units:
		if not u["down"] and u["readiness"] < MAX_READINESS and _recovers_readiness(u):
			u["readiness"] += 1
	# Wards decay.
	for u in units:
		if u["ward_ttl"] > 0:
			u["ward_ttl"] -= 1
			if u["ward_ttl"] == 0:
				u["ward"] = 0
	# Resolve any action whose active tick is now.
	for u in units:
		if u["down"] or is_idle(u):
			continue
		if tick == resolves_at(u):
			_resolve(u)
			ev["resolved"].append(u["id"])
	# Clear finished plans (past their recovery tail).
	for u in units:
		if is_idle(u):
			continue
		var done_at := resolves_at(u) + int(u["plan"]["recovery"])
		if tick > done_at:
			u["plan"] = {}
	ev["down"] = units.any(func(x): return x["down"])
	return ev

## Advance until the player needs to make a decision (plan or react), or the
## fight ends. This is the normal driver: fine-grained time internally, coarse
## control for the player.
func advance() -> Dictionary:
	var guard := 0
	while guard < 1000:
		guard += 1
		if is_over():
			return {"reason": "over", "winner": winner()}
		# The player gets the planning initiative while idle...
		if is_idle(player()) and not player()["down"]:
			return {"reason": "plan"}
		# ...then idle enemies form an intent. A fresh telegraph the player can
		# still act on (they haven't committed) is a reaction window.
		var telegraphed := _enemy_intents()
		if telegraphed and can_act(player()) and not player()["down"]:
			return {"reason": "reaction", "threat": _incoming_threat()}
		var ev := step()
		if ev["down"]:
			return {"reason": "hit", "event": ev}
	return {"reason": "over", "winner": winner()}

## Read the current decision state WITHOUT advancing time. Mirrors advance()'s
## branching, but takes no step, so a caller can pass a single tick with hold()
## and then re-read the situation instead of fast-forwarding to a resolution.
func peek() -> Dictionary:
	if is_over():
		return {"reason": "over", "winner": winner()}
	if is_idle(player()) and not player()["down"]:
		return {"reason": "plan"}
	# Idle enemies form an intent; a fresh telegraph the player can still answer
	# is a reaction window.
	var telegraphed := _enemy_intents()
	if telegraphed and can_act(player()) and not player()["down"]:
		return {"reason": "reaction", "threat": _incoming_threat()}
	# Mid-action with nothing new to react to: the player watches it out a tick
	# at a time rather than skipping to the resolution.
	return {"reason": "watch", "threat": _incoming_threat()}

## Pass exactly one tick on the player's behalf. Idle enemies get to press first
## (so a stand-off isn't the player keeping initiative forever), then time moves
## forward by a single tick — unlike advance(), which fast-forwards through
## resolutions. The player is left free to plan/react on the next tick.
func hold() -> Dictionary:
	_enemy_intents()
	return step()

# --- Resolution -------------------------------------------------------------
func _resolve(u: Dictionary) -> void:
	var plan: Dictionary = u["plan"]
	var a: Dictionary = actions.get(plan["action"], {})
	match str(plan["kind"]):
		"move":
			_do_move(u, plan["target"], int(a.get("distance", 1)))
		"ray":
			_do_ray(u, plan["target"], int(a.get("damage", 1)))
		"area":
			_do_area(u, plan["target"], int(a.get("radius", 1)), int(a.get("damage", 1)))
		"shield":
			_do_shield(u, plan["target"], int(a.get("ward", 1)))
		"trap":
			_do_trap(u, plan["target"], int(a.get("damage", 1)))
		_:
			pass  # a pure "self"/wait action just burns time

func _do_move(u: Dictionary, target: Vector2i, distance: int) -> void:
	var dest: Vector2i = u["pos"]
	for _i in distance:
		var stepv := _step_dir(dest, target)
		if stepv == Vector2i.ZERO:
			break
		var nxt := dest + stepv
		if not _in_bounds(nxt) or not unit_at(nxt).is_empty():
			break
		dest = nxt
	if dest != u["pos"]:
		u["pos"] = dest
		_say("%s moves to %s." % [u["name"], str(dest)])
		_check_trap(u)

func _do_ray(u: Dictionary, target: Vector2i, dmg: int) -> void:
	_say("%s's ray strikes %s." % [u["name"], str(target)])
	var victim := unit_at(target)
	if not victim.is_empty():
		_apply_hit(victim, dmg, u["pos"])

func _do_area(u: Dictionary, target: Vector2i, radius: int, dmg: int) -> void:
	_say("%s's burst erupts around %s." % [u["name"], str(target)])
	for other in units:
		if other["down"]:
			continue
		if _hex_distance(other["pos"], target) <= radius:
			_apply_hit(other, dmg, u["pos"])

func _do_shield(u: Dictionary, target: Vector2i, amount: int) -> void:
	u["ward"] = amount
	u["ward_dir"] = _step_dir(u["pos"], target)
	u["ward_ttl"] = WARD_TTL
	_say("%s raises a ward toward %s." % [u["name"], str(target)])

func _do_trap(u: Dictionary, target: Vector2i, dmg: int) -> void:
	traps.append({"pos": target, "damage": dmg, "owner": u["id"]})
	_say("%s sets a rune on %s." % [u["name"], str(target)])
	# A unit already standing on the rune triggers it at once.
	var standing := unit_at(target)
	if not standing.is_empty():
		_check_trap(standing)

func _apply_hit(victim: Dictionary, dmg: int, source: Vector2i) -> void:
	var from_dir := _step_dir(victim["pos"], source)
	if victim["ward"] > 0 and victim["ward_dir"] == from_dir:
		victim["ward"] = 0
		victim["ward_ttl"] = 0
		_say("%s's ward absorbs the blow." % victim["name"])
		return
	victim["hp"] -= dmg
	if victim["hp"] <= 0:
		victim["down"] = true
		_say("%s is struck down!" % victim["name"])
	else:
		_say("%s is hit (%d hp left)." % [victim["name"], victim["hp"]])

func _check_trap(u: Dictionary) -> void:
	for i in range(traps.size() - 1, -1, -1):
		if traps[i]["pos"] == u["pos"]:
			_say("%s triggers a rune!" % u["name"])
			_apply_hit(u, int(traps[i]["damage"]), u["pos"])
			traps.remove_at(i)

# --- A very small deterministic enemy ---------------------------------------
## Idle enemies form an intent. Returns true if any enemy started a NEW action
## this call (i.e. a fresh telegraph the player might react to).
func _enemy_intents() -> bool:
	var started := false
	var target := player()
	if target.is_empty() or target["down"]:
		return false
	for e in enemies():
		if not is_idle(e):
			continue
		# Predict where the player will be: their queued destination if moving,
		# else where they stand now.
		var predicted: Vector2i = _projected_dest(target)
		var ray_id := _first_of_kind("ray")
		if ray_id != "" and e["readiness"] >= int(actions[ray_id].get("readiness_cost", 1)):
			if queue_action(e["id"], ray_id, predicted):
				started = true
				continue
		# Otherwise close the distance.
		var move_id := _first_of_kind("move")
		if move_id != "" and e["readiness"] >= int(actions[move_id].get("readiness_cost", 1)):
			if queue_action(e["id"], move_id, target["pos"]):
				started = true
	return started

func _projected_dest(u: Dictionary) -> Vector2i:
	if not is_idle(u) and str(u["plan"]["kind"]) == "move":
		var dest: Vector2i = u["pos"]
		var a: Dictionary = actions.get(u["plan"]["action"], {})
		for _i in int(a.get("distance", 1)):
			var stepv := _step_dir(dest, u["plan"]["target"])
			if stepv == Vector2i.ZERO:
				break
			dest += stepv
		return dest
	return u["pos"]

func _incoming_threat() -> Dictionary:
	# The most imminent enemy action bearing down on the player, for the UI.
	var best := {}
	var soonest := 1 << 30
	for e in enemies():
		if is_idle(e):
			continue
		var when := resolves_at(e)
		if when < soonest:
			soonest = when
			best = {"by": e["name"], "action": e["plan"]["name"],
				"target": e["plan"]["target"], "resolves_in": when - tick}
	return best

# --- Small helpers ----------------------------------------------------------
func _first_of_kind(kind: String) -> String:
	for id in actions:
		if str(actions[id].get("kind", "")) == kind:
			return str(id)
	return ""

# --- Hex geometry (axial coords: pos = Vector2i(q, r)) ----------------------
## The board is a hex grid in axial coordinates. Six neighbours, no diagonals;
## the board is a rhombus of grid.x columns by grid.y rows.
const HEX_DIRS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < grid.x and p.y >= 0 and p.y < grid.y

## Axial (cube) hex distance.
func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	return (abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2

## The single hex-neighbour step from `from` that gets closest to `to` (or ZERO
## if already there). Used for movement, facing, and threat projection.
func _step_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	if from == to:
		return Vector2i.ZERO
	var best := Vector2i.ZERO
	var best_d := 1 << 30
	for d in HEX_DIRS:
		var nd := _hex_distance(from + d, to)
		if nd < best_d:
			best_d = nd
			best = d
	return best

func _say(msg: String) -> void:
	log.append("[t%d] %s" % [tick, msg])
