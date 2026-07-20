extends Control
## Main — the UI shell for the spine prototype.
##
## Deliberately built entirely in code so the whole game loop is readable in
## one place: a date/clock header, a stats sidebar, a scrolling journal, and a
## column of activity buttons for the current slot. It never touches game
## state directly — it reads from GameState and calls perform_activity(), then
## redraws whenever GameState emits state_changed.

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

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)

	var root_h := HBoxContainer.new()
	root_h.add_theme_constant_override("separation", 18)
	margin.add_child(root_h)

	# --- Sidebar: clock + stats + relationships ---
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(300, 0)
	sidebar.add_theme_constant_override("separation", 10)
	root_h.add_child(sidebar)

	date_label = Label.new()
	date_label.add_theme_font_size_override("font_size", 18)
	date_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(date_label)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_section_title("Stats"))
	stats_label = Label.new()
	sidebar.add_child(stats_label)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_section_title("Relationships"))
	relations_label = Label.new()
	sidebar.add_child(relations_label)

	# --- Main column: journal + activities ---
	var main_v := VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 10)
	root_h.add_child(main_v)

	main_v.add_child(_section_title("Journal"))
	log_box = RichTextLabel.new()
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	main_v.add_child(log_box)

	main_v.add_child(_section_title("What will you do?"))
	activity_container = VBoxContainer.new()
	activity_container.add_theme_constant_override("separation", 6)
	main_v.add_child(activity_container)

func _section_title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = "— %s —" % text
	lbl.add_theme_font_size_override("font_size", 15)
	return lbl

func _refresh() -> void:
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
		btn.text = a.get("name", "Activity")
		btn.tooltip_text = a.get("description", "")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_activity_pressed.bind(a))
		activity_container.add_child(btn)

func _on_activity_pressed(a: Dictionary) -> void:
	GameState.perform_activity(a)

func _on_message(text: String) -> void:
	log_box.append_text(text + "\n")
