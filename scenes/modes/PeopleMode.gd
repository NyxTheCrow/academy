extends "res://scenes/modes/MenuMode.gd"
## People — a roster of characters, each clickable to open their page. Opens in
## two scopes: the global "Characters" list, or "People Here" (context.here)
## filtered to the player's current location. Favourites pin to the top.

func _menu_title() -> String:
	return "People Here" if mode_context.get("here", false) else "Characters"

func _populate() -> void:
	var here: bool = mode_context.get("here", false)
	var roster: Array = []
	for npc in Students.npcs:
		if here and str(npc["location"]) != GameState.location:
			continue
		roster.append(npc)

	if roster.is_empty():
		content.add_child(_h("No one else is here." if here else "No one to show."))
		return

	# Favourites first, then the rest.
	var ordered: Array = []
	for npc in roster:
		if GameState.is_favorite(str(npc["id"])):
			ordered.append(npc)
	for npc in roster:
		if not GameState.is_favorite(str(npc["id"])):
			ordered.append(npc)

	for npc in ordered:
		var id: String = str(npc["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var star := Button.new()
		star.text = "★" if GameState.is_favorite(id) else "☆"
		star.tooltip_text = "Toggle favourite"
		star.pressed.connect(_toggle.bind(id))
		row.add_child(star)

		var v := int(GameState.relationships.get(id, 0))
		var bond := str(v) if GameState.dev_mode else GameState.relationship_descriptor(v)
		var label := "%s  —  %s   ·   %s" % [npc["name"], bond, npc["current_action"]]
		if not here:
			label += "   @ " + Students.location_name(str(npc["location"]))
		var btn := Button.new()
		btn.text = label
		btn.tooltip_text = "Open %s's page" % str(npc["name"])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.pressed.connect(_open_detail.bind(id))
		row.add_child(btn)

		content.add_child(row)

func _open_detail(id: String) -> void:
	await Director.run_mode("character_detail", {"npc_id": id})
	_repopulate()

func _toggle(id: String) -> void:
	GameState.toggle_favorite(id)
	_repopulate()
