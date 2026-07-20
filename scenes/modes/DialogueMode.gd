extends "res://scripts/GameMode.gd"
## DialogueMode — the VN spine.
##
## Plays a data-driven dialogue scene (from data/dialogue.json). A scene is a
## list of nodes:
##   { "speaker": "Name", "text": "..." }              a spoken line
##   { "label": "some_id" }                            a jump target
##   { "choices": [ { "text": "...", "effects": {...}, "goto": "label" } ] }
##
## Effects from chosen options accumulate into a single result dictionary that
## is handed back to whoever launched the mode when the scene ends.

var _nodes: Array = []
var _labels: Dictionary = {}   # label -> index
var _index: int = 0
var _result: Dictionary = {}

var portrait_label: Label
var speaker_label: Label
var text_label: RichTextLabel
var continue_btn: Button
var choices_scroll: ScrollContainer
var choices_box: VBoxContainer

func enter(context: Dictionary) -> void:
	_build_ui()
	var scene := GameData.get_dialogue(str(context.get("scene_id", "")))
	_nodes = scene.get("lines", [])
	_index = 0
	_result = {}
	_labels.clear()
	for i in _nodes.size():
		if _nodes[i].has("label"):
			_labels[str(_nodes[i]["label"])] = i
	_play()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.10)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Portrait placeholder (left).
	var portrait_panel := PanelContainer.new()
	portrait_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	portrait_panel.position = Vector2(60, 120)
	portrait_panel.custom_minimum_size = Vector2(240, 320)
	add_child(portrait_panel)
	portrait_label = Label.new()
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_label.add_theme_font_size_override("font_size", 96)
	portrait_panel.add_child(portrait_label)

	# Dialogue box (bottom). Fixed height; its text and choices scroll inside so
	# long passages or many options never overflow the box.
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = -360
	box.offset_bottom = -30
	add_child(box)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	box.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	speaker_label = Label.new()
	speaker_label.add_theme_font_size_override("font_size", 20)
	v.add_child(speaker_label)

	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.scroll_active = true
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.custom_minimum_size = Vector2(0, 60)
	v.add_child(text_label)

	# Choices scroll independently; shown instead of the Continue button.
	choices_scroll = ScrollContainer.new()
	choices_scroll.custom_minimum_size = Vector2(0, 140)
	choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices_scroll.visible = false
	v.add_child(choices_scroll)
	choices_box = VBoxContainer.new()
	choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_box.add_theme_constant_override("separation", 6)
	choices_scroll.add_child(choices_box)

	continue_btn = Button.new()
	continue_btn.text = "Continue  ▸"
	continue_btn.pressed.connect(_on_continue)
	v.add_child(continue_btn)

func _play() -> void:
	# Skip label markers.
	while _index < _nodes.size() and _nodes[_index].has("label"):
		_index += 1
	if _index >= _nodes.size():
		finished.emit(_result)
		return

	var node: Dictionary = _nodes[_index]
	if node.has("choices"):
		_show_choices(node["choices"])
	else:
		_show_line(node)

func _show_line(node: Dictionary) -> void:
	_clear_choices()
	choices_scroll.visible = false
	continue_btn.visible = true
	var speaker: String = node.get("speaker", "")
	speaker_label.text = speaker
	portrait_label.text = (speaker.substr(0, 1) if speaker != "" else "?")
	text_label.text = node.get("text", "")

func _show_choices(choices: Array) -> void:
	continue_btn.visible = false
	choices_scroll.visible = true
	_clear_choices()
	for choice in choices:
		var btn := Button.new()
		btn.text = choice.get("text", "...")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.pressed.connect(_on_choice.bind(choice))
		choices_box.add_child(btn)

func _clear_choices() -> void:
	for c in choices_box.get_children():
		c.queue_free()

func _on_continue() -> void:
	_index += 1
	_play()

func _on_choice(choice: Dictionary) -> void:
	if choice.has("effects"):
		GameState.merge_effects(_result, choice["effects"])
	if choice.has("goto") and _labels.has(str(choice["goto"])):
		_index = _labels[str(choice["goto"])]
	else:
		_index += 1
	_play()
