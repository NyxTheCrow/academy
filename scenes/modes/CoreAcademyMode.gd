extends "res://scripts/GameMode.gd"
## CoreAcademyMode — the Academy screen, running entirely on the NEW core
## (Game.world / Actor / World), not on GameState/Students. This is the proof
## that the UI works on the restructured foundation.
##
## Everything it shows comes from the player Actor and the World: the location
## description is graded prose resolved against the player's skills, the condition
## row is Descriptor words (or numbers in dev mode), the action list is
## World.available_interactions(player), and taking an action is
## World.player_take(i) — which advances the clock, ticks every NPC through the
## same interactions, drifts needs, and fires events. F2 toggles dev mode.

const DescriptorC := preload("res://core/Descriptor.gd")

var header_label: Label
var date_label: Label
var cond_box: VBoxContainer
var skills_title: Label
var skills_box: VBoxContainer
var rel_box: VBoxContainer
var people_box: VBoxContainer
var place_label: Label
var place_desc: Label
var class_label: Label
var log_box: RichTextLabel
var action_container: VBoxContainer

func _world():
	return Game.world

func _ready() -> void:
	_build_ui()
	var w = _world()
	w.state_changed.connect(_refresh)
	w.message.connect(_on_message)
	_refresh()
	_on_message("[i]Another morning at the Academy. Where will you go, and what will you do?[/i]")

func on_resumed() -> void:
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		var w = _world()
		w.dev_mode = not w.dev_mode
		w.state_changed.emit()
		get_viewport().set_input_as_handled()

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

	# --- Sidebar ---
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.custom_minimum_size = Vector2(320, 0)
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_h.add_child(sidebar_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 10)
	sidebar_scroll.add_child(sidebar)

	header_label = Label.new()
	header_label.add_theme_font_size_override("font_size", 20)
	sidebar.add_child(header_label)
	date_label = Label.new()
	date_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(date_label)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_title("Condition"))
	cond_box = VBoxContainer.new()
	cond_box.add_theme_constant_override("separation", 2)
	sidebar.add_child(cond_box)

	skills_title = _title("Skills (dev)")
	sidebar.add_child(skills_title)
	skills_box = VBoxContainer.new()
	skills_box.add_theme_constant_override("separation", 2)
	sidebar.add_child(skills_box)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_title("Relationships"))
	rel_box = VBoxContainer.new()
	rel_box.add_theme_constant_override("separation", 2)
	sidebar.add_child(rel_box)

	sidebar.add_child(HSeparator.new())
	sidebar.add_child(_title("People here"))
	people_box = VBoxContainer.new()
	people_box.add_theme_constant_override("separation", 2)
	sidebar.add_child(people_box)

	sidebar.add_child(HSeparator.new())
	var saves_btn := Button.new()
	saves_btn.text = "Save / Load"
	saves_btn.pressed.connect(func(): await Director.run_mode("core_saves", {}))
	sidebar.add_child(saves_btn)
	var menu_btn := Button.new()
	menu_btn.text = "Return to Main Menu"
	menu_btn.pressed.connect(func(): finished.emit({"action": "main_menu"}))
	sidebar.add_child(menu_btn)
	var hint := Label.new()
	hint.text = "F2 — toggle dev numbers"
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	sidebar.add_child(hint)

	# --- Main column ---
	var main_v := VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 10)
	root_h.add_child(main_v)

	place_label = Label.new()
	place_label.add_theme_font_size_override("font_size", 24)
	main_v.add_child(place_label)
	place_desc = Label.new()
	place_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	place_desc.add_theme_color_override("font_color", Color(0.78, 0.81, 0.88))
	main_v.add_child(place_desc)
	class_label = Label.new()
	class_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.5))
	main_v.add_child(class_label)

	main_v.add_child(_title("Journal"))
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.custom_minimum_size = Vector2(0, 150)
	main_v.add_child(log_box)

	main_v.add_child(_title("Actions"))
	var act_scroll := ScrollContainer.new()
	act_scroll.custom_minimum_size = Vector2(0, 220)
	act_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_v.add_child(act_scroll)
	action_container = VBoxContainer.new()
	action_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_container.add_theme_constant_override("separation", 6)
	act_scroll.add_child(action_container)

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % text
	l.add_theme_font_size_override("font_size", 15)
	return l

# --- Refresh ----------------------------------------------------------------
func _refresh() -> void:
	if date_label == null:
		return
	var w = _world()
	var p = w.player
	header_label.text = p.name + ("   [DEV]" if w.dev_mode else "")
	date_label.text = w.clock.date_string()

	var loc: Dictionary = w.content.locations.get(p.location, {})
	place_label.text = str(loc.get("name", p.location))
	place_desc.text = p.describe(loc.get("description", ""))
	_refresh_class_line()
	_rebuild_condition()
	_rebuild_skills()
	_rebuild_relations()
	_rebuild_people()
	_rebuild_actions()

func _refresh_class_line() -> void:
	var w = _world()
	var cn: Dictionary = w.class_in_session(w.player.location)
	if not cn.is_empty():
		class_label.text = "In session: %s" % str(cn.get("name", ""))
		class_label.visible = true
		return
	var nx: Dictionary = w.next_class_at(w.player.location)
	if not nx.is_empty():
		class_label.text = "Next class here: %s at %s" % [str(nx.get("name", "")), str(nx.get("start", ""))]
		class_label.visible = true
	else:
		class_label.visible = false

func _rebuild_condition() -> void:
	for c in cond_box.get_children():
		c.queue_free()
	var w = _world()
	var p = w.player
	for r in w.content.resources_registry:
		var rid := str(r.get("id", ""))
		cond_box.add_child(_kv(str(r.get("name", rid)),
			DescriptorC.value(w.dev_mode, "resource", rid, p.get_resource(rid))))
	for n in w.content.needs_registry:
		var nid := str(n.get("id", ""))
		cond_box.add_child(_kv(str(n.get("name", nid)),
			DescriptorC.value(w.dev_mode, "need", nid, p.get_need(nid))))

func _rebuild_skills() -> void:
	# Skills are hidden aptitudes — shown only in dev mode, with raw numbers.
	var w = _world()
	skills_title.visible = w.dev_mode
	skills_box.visible = w.dev_mode
	for c in skills_box.get_children():
		c.queue_free()
	if not w.dev_mode:
		return
	for s in w.content.skills_registry:
		var sid := str(s.get("id", ""))
		skills_box.add_child(_kv(str(s.get("name", sid)), "%.2f" % w.player.get_skill(sid)))

func _rebuild_relations() -> void:
	for c in rel_box.get_children():
		c.queue_free()
	var w = _world()
	if w.player.relationships.is_empty():
		var l := Label.new()
		l.text = "(no bonds yet)"
		l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		rel_box.add_child(l)
		return
	for aid in w.player.relationships:
		var v := int(w.player.relationships[aid])
		rel_box.add_child(_kv(str(aid).capitalize(),
			DescriptorC.value(w.dev_mode, "relationship", str(aid), float(v))))

func _rebuild_people() -> void:
	for c in people_box.get_children():
		c.queue_free()
	var w = _world()
	var here: Array = w.actors_at(w.player.location)
	if here.is_empty():
		var l := Label.new()
		l.text = "(no one else here)"
		l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		people_box.add_child(l)
		return
	for a in here:
		people_box.add_child(_kv(str(a.name), str(a.current_action)))

func _kv(key: String, value: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size = Vector2(130, 0)
	k.add_theme_color_override("font_color", Color(0.72, 0.76, 0.85))
	h.add_child(k)
	var val := Label.new()
	val.text = value
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(val)
	return h

func _rebuild_actions() -> void:
	for c in action_container.get_children():
		c.queue_free()
	var w = _world()
	var actions: Array = w.available_interactions(w.player)
	if actions.is_empty():
		var lbl := Label.new()
		lbl.text = "(Nothing to do here.)"
		action_container.add_child(lbl)
		return
	for a in actions:
		var btn := Button.new()
		btn.text = _action_label(a)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.pressed.connect(_on_action.bind(a))
		action_container.add_child(btn)

func _action_label(a: Dictionary) -> String:
	var label: String = str(a.get("name", "Action"))
	if a.has("goto"):
		label = "→ " + label
	var dur := int(a.get("duration", 0))
	if dur > 0:
		label += "   (%d min)" % dur
	if a.has("dialogue"):
		label += "  [talk]"
	return label

func _on_action(a: Dictionary) -> void:
	var w = _world()
	if a.get("sleep", false):
		w.sleep()
		return
	if a.has("dialogue"):
		# Dialogue UI is not yet ported to the core; apply effects + time and note it.
		w.player_take(a)
		w.message.emit("[i](A conversation would play here — the VN screen isn't on the core yet.)[/i]")
		return
	w.player_take(a)

func _on_message(text: String) -> void:
	if log_box != null:
		log_box.append_text(text + "\n")
