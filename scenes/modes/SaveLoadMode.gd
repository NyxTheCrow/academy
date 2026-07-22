extends "res://scenes/modes/MenuMode.gd"
## Save / Load — multiple slots, each showing its metadata.

const SLOTS := 6

func _menu_title() -> String:
	return "Saves"

func _load_only() -> bool:
	return mode_context.get("load_only", false)

func _populate() -> void:
	var hint := "Pick a slot to load." if _load_only() else "Save writes the current game; Load replaces it."
	content.add_child(_rich("[color=gray]%s[/color]" % hint))
	content.add_child(HSeparator.new())
	for slot in range(1, SLOTS + 1):
		content.add_child(_slot_row(slot))

func _slot_row(slot: int) -> HBoxContainer:
	var info := GameState.slot_info(slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var text := "[b]Slot %d[/b]  " % slot
	if info.get("exists", false):
		text += "%s\n[color=gray]%s%s[/color]" % [
			info.get("name", "?"), info.get("when", ""), _ago(info.get("saved_at", 0.0))]
	else:
		text += "[color=dimgray](empty)[/color]"
	var lbl := _rich(text)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	if not _load_only():
		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.pressed.connect(_on_save.bind(slot))
		row.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.disabled = not info.get("exists", false)
	load_btn.pressed.connect(_on_load.bind(slot))
	row.add_child(load_btn)

	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.disabled = not info.get("exists", false)
	del_btn.pressed.connect(_on_delete.bind(slot))
	row.add_child(del_btn)

	return row

func _ago(saved_at: float) -> String:
	if saved_at <= 0.0:
		return ""
	var secs := int(Time.get_unix_time_from_system() - saved_at)
	if secs < 60:
		return "  ·  just now"
	elif secs < 3600:
		return "  ·  %d min ago" % (secs / 60)
	elif secs < 86400:
		return "  ·  %d h ago" % (secs / 3600)
	return "  ·  %d d ago" % (secs / 86400)

func _on_save(slot: int) -> void:
	GameState.save_slot(slot)
	_repopulate()

func _on_load(slot: int) -> void:
	if GameState.load_slot(slot):
		# In-game this just closes; from the main menu, {"loaded": true} tells
		# the app loop to start the academy on the loaded save.
		finished.emit({"loaded": true})

func _on_delete(slot: int) -> void:
	GameState.delete_slot(slot)
	_repopulate()
