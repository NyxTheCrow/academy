extends "res://scenes/modes/MenuMode.gd"
## Inventory — the items you carry. Usable items can be consumed here.

func _menu_title() -> String:
	return "Inventory"

func _populate() -> void:
	if GameState.inventory.is_empty():
		content.add_child(_kv("", "(you are carrying nothing)"))
		return
	for id in GameState.inventory:
		var item := GameData.get_item(str(id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var text := "[b]%s[/b]\n[color=gray]%s[/color]" % [
			item.get("name", str(id)), item.get("description", "")]
		var lbl := _rich(text)
		row.add_child(lbl)
		if item.has("use"):
			var use_btn := Button.new()
			use_btn.text = "Use"
			use_btn.pressed.connect(_use.bind(str(id), item))
			row.add_child(use_btn)
		content.add_child(row)
		content.add_child(HSeparator.new())

func _use(id: String, item: Dictionary) -> void:
	GameState.apply_effects(item.get("use", {}))
	GameState.message.emit("You use the %s." % item.get("name", id))
	if item.get("consumable", false):
		GameState.remove_item(id)
	_repopulate()
