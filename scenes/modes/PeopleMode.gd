extends "res://scenes/modes/MenuMode.gd"
## Other People — the roster of students, with a favourite (★) toggle.
## Favourites are pinned to the top and saved with the game.

func _menu_title() -> String:
	return "Other People"

func _populate() -> void:
	# Favourites first, then the rest.
	var ordered: Array = []
	for npc in Students.npcs:
		if GameState.is_favorite(str(npc["id"])):
			ordered.append(npc)
	for npc in Students.npcs:
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
		var line := "[b]%s[/b]  —  %s\n[color=gray]At %s · %s[/color]" % [
			npc["name"], bond, Students.location_name(npc["location"]), npc["current_action"]]
		if GameState.dev_mode:
			line += "\n[color=dimgray]focus %d · tags: %s[/color]" % [
				int(npc["stats"].get("focus", 0)), ", ".join(PackedStringArray(npc["tags"]))]
		row.add_child(_rich(line))
		content.add_child(row)
		content.add_child(HSeparator.new())

func _toggle(id: String) -> void:
	GameState.toggle_favorite(id)
	_repopulate()
