extends "res://scripts/GameMode.gd"
## AcademyMode — the planning UI and the base mode of the game.
##
## Reads GameState, shows the clock / stats / journal / activity buttons, and
## on a button press either resolves a plain activity or launches a sub-mode
## (dialogue or combat) via the Director, applying the result when it returns.

var date_label: Label
var stats_label: Label
var relations_label: Label
var log_box: RichTextLabel
var activity_container: VBoxContainer

func _ready() -> void:
	_build_ui()
	GameState.state_changed.connect(_refresh)
	GameState.message.connect(_on_message)
	_refresh()
	_on_message("[i]Welcome to the Academy. Plan your time wisely — every slot counts.[/i]")

func on_resumed() -> void:
	_refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)

	var root_h := HBoxContainer.new()
	root_h.add_theme_constant_override("separation", 18)
	margin.add_child(root_h)

	# --- Sidebar: clock + stats + relationships + save/load ---
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(300, 0)
	sidebar.add_theme_constant_override("separation", 10)
	root_h.add_child(sidebar)

	date_label = Label.new()
	date_label.add_theme_font_size_override("font_size", 18)
	date_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(date_label)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_title("Stats"))
	stats_label = Label.new()
	sidebar.add_child(stats_label)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_title("Relationships"))
	relations_label = Label.new()
	sidebar.add_child(relations_label)

	sidebar.add_child(HSeparator.new())
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(func(): GameState.save_game())
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(func(): GameState.load_game())
	save_row.add_child(save_btn)
	save_row.add_child(load_btn)
	sidebar.add_child(save_row)

	# --- Main column: journal + activities ---
	var main_v := VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 10)
	root_h.add_child(main_v)

	main_v.add_child(_title("Journal"))
	log_box = RichTextLabel.new()
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	main_v.add_child(log_box)

	main_v.add_child(_title("What will you do?"))
	activity_container = VBoxContainer.new()
	activity_container.add_theme_constant_override("separation", 6)
	main_v.add_child(activity_container)

func _title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = "— %s —" % text
	lbl.add_theme_font_size_override("font_size", 15)
	return lbl

func _refresh() -> void:
	if date_label == null:
		return
	date_label.text = GameState.date_string()

	var s := "Energy:  %d / %d\n\n" % [GameState.energy, GameState.max_energy]
	for k in GameState.stats:
		s += "%s:  %d\n" % [str(k).capitalize(), GameState.stats[k]]
	stats_label.text = s

	if GameState.relationships.is_empty():
		relations_label.text = "(no bonds yet)"
	else:
		var r := ""
		for npc in GameState.relationships:
			r += "%s:  %d\n" % [str(npc).capitalize(), GameState.relationships[npc]]
		relations_label.text = r

	_rebuild_activities()

func _rebuild_activities() -> void:
	for c in activity_container.get_children():
		c.queue_free()

	var acts := GameState.available_activities()
	if acts.is_empty():
		var lbl := Label.new()
		lbl.text = "(Nothing available right now.)"
		activity_container.add_child(lbl)
		return

	for a in acts:
		var btn := Button.new()
		var label: String = a.get("name", "Activity")
		if a.has("dialogue"):
			label += "  [scene]"
		elif a.has("combat"):
			label += "  [fight]"
		btn.text = label
		btn.tooltip_text = a.get("description", "")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_activity_pressed.bind(a))
		activity_container.add_child(btn)

func _on_activity_pressed(a: Dictionary) -> void:
	# Mode-triggering activities: run the sub-mode, then apply everything and
	# advance one slot once it returns. Plain activities go straight through
	# the spine's perform_activity().
	if a.has("dialogue"):
		var res: Dictionary = await Director.run_mode("dialogue", {"scene_id": a["dialogue"]})
		GameState.apply_effects(a.get("effects", {}))
		GameState.apply_effects(res.get("effects", {}))
		GameState.advance_time()
	elif a.has("combat"):
		var res2: Dictionary = await Director.run_mode("combat", {"encounter_id": a["combat"]})
		GameState.apply_effects(a.get("effects", {}))
		GameState.apply_effects(res2.get("effects", {}))
		GameState.advance_time()
	else:
		GameState.perform_activity(a)

func _on_message(text: String) -> void:
	if log_box != null:
		log_box.append_text(text + "\n")
