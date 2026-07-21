extends CanvasLayer
## DebugOverlay — a bug-testing panel that floats above every mode.
##
## Toggle with F3. Shows live game state and gives dev shortcuts: bump stats,
## skip time, save/load, and force-launch a dialogue or combat encounter so you
## can exercise those modes without grinding to their triggers.

var panel: PanelContainer
var state_label: RichTextLabel

func _ready() -> void:
	layer = 100
	_build_ui()
	panel.visible = false
	GameState.state_changed.connect(_refresh)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			panel.visible = not panel.visible
			if panel.visible:
				_refresh()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			GameState.dev_mode = not GameState.dev_mode
			GameState.state_changed.emit()
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-360, 10)
	panel.custom_minimum_size = Vector2(350, 0)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	var title := Label.new()
	title.text = "DEBUG  (F3 hide · F2 dev toggle)"
	title.add_theme_font_size_override("font_size", 14)
	v.add_child(title)

	state_label = RichTextLabel.new()
	state_label.bbcode_enabled = true
	state_label.fit_content = true
	state_label.custom_minimum_size = Vector2(330, 150)
	v.add_child(state_label)

	v.add_child(HSeparator.new())
	v.add_child(_row([
		_btn("+5 all stats", _bump_stats),
		_btn("Sleep→AM", _skip_day),
		_btn("+1 hour", func(): GameState.advance_time(60)),
	]))
	v.add_child(_row([
		_btn("Save", func(): GameState.save_game()),
		_btn("Load", func(): GameState.load_game()),
		_btn("Reset", func(): GameState.reset()),
	]))
	v.add_child(_row([
		_btn("Toggle Dev", _toggle_dev),
		_btn("→ Dialogue", _force_dialogue),
		_btn("→ Combat", _force_combat),
	]))

func _row(buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for b in buttons:
		h.add_child(b)
	return h

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _skip_day() -> void:
	GameState.sleep()

func _refill_energy() -> void:
	GameState.apply_effects({"energy": 100})

func _toggle_dev() -> void:
	GameState.dev_mode = not GameState.dev_mode
	GameState.state_changed.emit()

func _bump_stats() -> void:
	var e := {"stats": {}}
	for k in GameState.stats:
		e["stats"][k] = 5
	GameState.apply_effects(e)

func _force_dialogue() -> void:
	var res: Dictionary = await Director.run_mode("dialogue", {"scene_id": "elara_evening"})
	GameState.apply_effects(res.get("effects", {}))

func _force_combat() -> void:
	var res: Dictionary = await Director.run_mode("combat", {"encounter_id": "duel_rival"})
	GameState.apply_effects(res.get("effects", {}))

func _refresh() -> void:
	if state_label == null:
		return
	var s := "[b]%s[/b]  %s\n" % [GameState.player_name, "[color=orange]DEV[/color]" if GameState.dev_mode else "normal"]
	s += "%s\n" % GameState.date_string()
	s += "Location: %s\n" % GameState.location
	s += "Energy %d/%d\n" % [GameState.energy, GameState.max_energy]
	s += "Stats: %s\n" % str(GameState.stats)
	s += "Tags: %s\n" % str(GameState.tags)
	s += "Flags: %s\n" % str(GameState.flags)
	state_label.text = s
