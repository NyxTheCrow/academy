extends "res://scenes/modes/MenuMode.gd"
## Schedule — the recurring weekly timetable, today's entries highlighted.

func _menu_title() -> String:
	return "Schedule — %s" % GameState.day_name()

func _populate() -> void:
	var today := GameState.day_name()
	if GameData.schedule.is_empty():
		content.add_child(_kv("", "(nothing scheduled)"))
		return
	for entry in GameData.schedule:
		var days: Array = entry.get("days", [])
		var is_today: bool = (today in days) or ("Every day" in days)
		var head := "%s  ·  %s" % [entry.get("name", "?"), entry.get("time", "")]
		if is_today:
			head = "[color=lightgreen]● %s[/color]" % head
		content.add_child(_rich("[b]%s[/b]" % head))
		content.add_child(_kv("   Where", str(entry.get("location", "—"))))
		content.add_child(_kv("   Days", ", ".join(PackedStringArray(days))))
		if entry.has("note"):
			content.add_child(_kv("   Note", str(entry["note"])))
		content.add_child(HSeparator.new())
