extends "res://scenes/modes/MenuMode.gd"
## Spell list — every spell, marked known or locked by your tags.

func _menu_title() -> String:
	return "Spells"

func _populate() -> void:
	for sp in GameData.spells:
		var known: bool = GameState.requirement_met(
			sp.get("requires", {}), GameState.tags, GameState.stats, GameState.energy)
		var head := ""
		if known:
			head = "[color=lightgreen][known][/color]  %s  [color=gray](%s)[/color]" % [
				sp.get("name", "?"), sp.get("element", "")]
		else:
			var need: Array = sp.get("requires", {}).get("tags", [])
			head = "[color=gray][locked] %s — needs: %s[/color]" % [
				sp.get("name", "?"), ", ".join(PackedStringArray(need))]
		content.add_child(_rich("[b]%s[/b]" % head))
		content.add_child(_rich("[color=%s]%s[/color]" % [
			"white" if known else "gray", sp.get("description", "")]))
		content.add_child(HSeparator.new())
