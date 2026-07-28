extends "res://scenes/modes/MenuMode.gd"
## Character sheet — a read-only summary of the player.

func _menu_title() -> String:
	return "Character"

func _populate() -> void:
	var g := GameState
	content.add_child(_h(g.player_name))
	content.add_child(_kv("When", g.date_string()))
	content.add_child(_kv("Where", str(g.current_location().get("name", g.location))))
	var focus := int(g.stats.get("focus", 0))
	content.add_child(_kv("Focus", str(focus) if g.dev_mode else g.focus_descriptor(focus)))
	content.add_child(_kv("Energy",
		("%d / %d" % [g.energy, g.max_energy]) if g.dev_mode else g.energy_descriptor()))
	content.add_child(HSeparator.new())
	content.add_child(_h("Condition"))
	for nk in ["hunger", "thirst", "bladder", "hygiene", "calm", "mana"]:
		var nv := int(g.needs.get(nk, 0))
		var label: String = "Mana Reserves" if nk == "mana" else str(nk).capitalize()
		content.add_child(_kv(label, str(nv) if g.dev_mode else g.need_descriptor(nk, nv)))
	content.add_child(HSeparator.new())
	# The MC carries the same aptitude stat sheet as every NPC and grows it
	# through the same class-learning path; dev sees the full sheet (class levels
	# included) here, exactly as on an NPC's page. Hidden from normal players.
	if g.dev_mode:
		content.add_child(_h("Stats (dev)"))
		_stat_sheet(g.stats)
		content.add_child(HSeparator.new())
		content.add_child(_kv("Tags", ", ".join(PackedStringArray(g.tags)) if not g.tags.is_empty() else "none"))
	content.add_child(_kv("Items carried", str(g.inventory.size())))
	content.add_child(_kv("Favourites", str(g.favorites.size())))
	var known := 0
	for sp in GameData.spells:
		if g.requirement_met(sp.get("requires", {}), g.tags, g.stats, g.energy):
			known += 1
	content.add_child(_kv("Spells known", str(known)))
