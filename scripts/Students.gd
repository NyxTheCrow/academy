extends Node
## Students — the NPC manager (autoload).
##
## Four other students share the player's stat model, hours, and action list.
## Each in-game hour every NPC picks an action by a weighted random roll (their
## own bias) among the actions available at that hour, and applies its effects
## to their own stats — so they grow in parallel with the player. NPCs skip
## player-only actions (dialogue/combat scenes) and skip stat-gated ones.

var npcs: Array = []  # runtime state: {id, name, stats, energy, weights, current_action}

func _ready() -> void:
	reset()
	GameState.hour_ticked.connect(_on_hour_ticked)

## (Re)build NPC runtime state from the data definitions.
func reset() -> void:
	npcs.clear()
	for data in GameData.students:
		var stats := {"magic": 0, "combat": 0, "knowledge": 0, "charisma": 0}
		for k in data.get("stats", {}):
			stats[k] = int(data["stats"][k])
		npcs.append({
			"id": data.get("id", ""),
			"name": data.get("name", "Student"),
			"stats": stats,
			"energy": 100,
			"weights": data.get("action_weights", {}),
			"current_action": "Settling in",
		})

func _on_hour_ticked(hour: int) -> void:
	if hour == GameState.DAY_START_HOUR:
		for npc in npcs:
			npc["energy"] = 100  # a night's rest
	for npc in npcs:
		_npc_act(npc, hour)

func _npc_act(npc: Dictionary, hour: int) -> void:
	var options: Array = []
	for a in GameData.activities:
		if a.has("dialogue") or a.has("combat"):
			continue  # player-only scenes
		if a.has("requirements") and a["requirements"].has("flags"):
			continue  # skip flag-gated content for NPCs
		if GameState.availability_ok(a, hour, npc["energy"], {}):
			options.append(a)
	if options.is_empty():
		npc["current_action"] = "Idle"
		return
	var chosen: Dictionary = _weighted_pick(options, npc["weights"])
	npc["current_action"] = chosen.get("name", "…")
	_apply(npc, chosen)

func _weighted_pick(options: Array, weights: Dictionary) -> Dictionary:
	var total := 0.0
	for a in options:
		total += float(weights.get(a.get("id", ""), 1))
	var roll := randf() * total
	for a in options:
		roll -= float(weights.get(a.get("id", ""), 1))
		if roll <= 0.0:
			return a
	return options.back()

func _apply(npc: Dictionary, activity: Dictionary) -> void:
	var effects: Dictionary
	var check: Variant = activity.get("skill_check", null)
	if check != null and check is Dictionary:
		var stat_id: String = check.get("stat", "")
		var total: int = int(npc["stats"].get(stat_id, 0)) + randi_range(1, 6)
		effects = check.get("success", {}) if total >= int(check.get("difficulty", 5)) else check.get("failure", {})
	else:
		effects = activity.get("effects", {})
	if effects.has("stats"):
		for k in effects["stats"]:
			npc["stats"][k] = int(npc["stats"].get(k, 0)) + int(effects["stats"][k])
	if effects.has("energy"):
		npc["energy"] = clampi(int(npc["energy"]) + int(effects["energy"]), 0, 100)

# --- Save / load ------------------------------------------------------------
func serialize() -> Array:
	return npcs.duplicate(true)

func deserialize(data: Variant) -> void:
	if data is Array and not (data as Array).is_empty():
		npcs = (data as Array).duplicate(true)
	else:
		reset()
