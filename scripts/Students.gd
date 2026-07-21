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
		var stats := {"magic": 0, "combat": 0, "knowledge": 0, "charisma": 0}
		for k in data.get("stats", {}):
			stats[k] = int(data["stats"][k])
		npcs.append({
			"id": data.get("id", ""),
			"name": data.get("name", "Student"),
			"location": str(data.get("location", "room")),
			"tags": (data.get("tags", []) as Array).duplicate(),
			"stats": stats,
			"energy": 100,
			"current_action": "Waiting",
		})

func _on_day_changed() -> void:
	for npc in npcs:
		npc["energy"] = 100

func _on_time_advanced(_minutes: int) -> void:
	for npc in npcs:
		_npc_act(npc)

func location_name(loc: String) -> String:
	return str(GameData.get_location(loc).get("name", loc))

func _npc_act(npc: Dictionary) -> void:
	var loc := GameData.get_location(npc["location"])
	var options: Array = []
	for a in loc.get("actions", []):
		if a.has("dialogue") or a.has("combat") or a.get("sleep", false):
			continue  # player-only actions
		if GameState.requirement_met(a.get("requires", {}), npc["tags"], npc["stats"], npc["energy"]):
			options.append(a)
	# Movement options (NPCs wander).
	for conn in loc.get("connections", []):
		options.append({"name": "heading to " + location_name(conn), "goto": conn})
	if options.is_empty():
		npc["current_action"] = "idling in " + location_name(npc["location"])
		return
	var chosen: Dictionary = options[randi() % options.size()]
	if chosen.has("goto"):
		npc["location"] = str(chosen["goto"])
		npc["current_action"] = str(chosen["name"])
	else:
		npc["current_action"] = str(chosen.get("name", "…"))
		_apply(npc, chosen.get("effects", {}))

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
