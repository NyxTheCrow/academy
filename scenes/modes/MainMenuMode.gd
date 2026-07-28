extends "res://scripts/GameMode.gd"
## MainMenuMode — the title screen. Returns an {"action": ...} result that the
## Root loop acts on: new_game, load_game, editor. Quit exits directly.

func enter(_context: Dictionary) -> void:
	_build_ui()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(360, 0)
	center.add_child(v)

	var title := Label.new()
	title.text = "Magical Academy"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "a prototype"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.65, 0.68, 0.78))
	v.add_child(sub)
	v.add_child(HSeparator.new())

	v.add_child(_menu_button("New Game", func(): finished.emit({"action": "new_game"})))
	v.add_child(_menu_button("Load Game", func(): finished.emit({"action": "load_game"})))
	v.add_child(_menu_button("Editor (data)", func(): finished.emit({"action": "editor"})))
	v.add_child(_menu_button("Quit", func(): get_tree().quit()))

func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	return b
