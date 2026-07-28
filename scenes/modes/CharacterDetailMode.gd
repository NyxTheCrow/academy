extends "res://scenes/modes/MenuMode.gd"
## Character detail — one person's page. Reached by clicking someone in the
## "People Here" / "Characters" lists or in the Relationships panel.

func _menu_title() -> String:
	var npc := _npc()
	return str(npc.get("name", "Character")) if not npc.is_empty() else "Character"

func _npc() -> Dictionary:
	var id := str(mode_context.get("npc_id", ""))
	for n in Students.npcs:
		if str(n["id"]) == id:
			return n
	return {}

func _populate() -> void:
	var npc := _npc()
	if npc.is_empty():
		content.add_child(_h("(No such person.)"))
		return
	var id := str(npc["id"])

	var star := Button.new()
	star.text = "★  Favourited" if GameState.is_favorite(id) else "☆  Add to favourites"
	star.pressed.connect(func():
		GameState.toggle_favorite(id)
		_repopulate())
	content.add_child(star)
	content.add_child(HSeparator.new())

	content.add_child(_kv("Where", Students.location_name(str(npc["location"]))))
	content.add_child(_kv("Right now", str(npc["current_action"])))
	var v := int(GameState.relationships.get(id, 0))
	content.add_child(_kv("Bond", str(v) if GameState.dev_mode else GameState.relationship_descriptor(v)))

	var def := Lexicon.define(str(npc["name"]))
	if def != "":
		content.add_child(HSeparator.new())
		content.add_child(_rich(def))

	# Aptitude stats stay hidden from players; dev sees the full sheet (class
	# levels included). Same renderer as the player's own character sheet.
	if GameState.dev_mode:
		content.add_child(HSeparator.new())
		content.add_child(_h("Stats (dev)"))
		_stat_sheet(npc["stats"])
		content.add_child(HSeparator.new())
		content.add_child(_kv("Tags", ", ".join(PackedStringArray(npc["tags"]))))
