extends "res://scripts/GameMode.gd"
## LexiconMode — the searchable term glossary.
##
## A search box filters the lexicon live; the results list on the left updates
## as you type, and selecting an entry shows its full definition on the right.
## Opened from anywhere via Director.run_mode("lexicon", {"focus": "<term>"}).

var search_edit: LineEdit
var results_box: VBoxContainer
var detail_title: Label
var detail_cat: Label
var detail_body: RichTextLabel

func enter(context: Dictionary) -> void:
	_build_ui()
	_refilter("")
	var focus := str(context.get("focus", ""))
	if focus != "":
		var e := Lexicon.lookup(focus)
		if not e.is_empty():
			_show_detail(e)
	search_edit.grab_focus()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var title := Label.new()
	title.text = "Lexicon"
	title.add_theme_font_size_override("font_size", 24)
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): finished.emit({}))
	top.add_child(close_btn)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search terms, categories, definitions…"
	search_edit.clear_button_enabled = true
	search_edit.text_changed.connect(_refilter)
	v.add_child(search_edit)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	# Results list (left).
	var results_scroll := ScrollContainer.new()
	results_scroll.custom_minimum_size = Vector2(300, 0)
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(results_scroll)
	results_box = VBoxContainer.new()
	results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_box.add_theme_constant_override("separation", 4)
	results_scroll.add_child(results_box)

	# Detail (right).
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)
	var dmargin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		dmargin.add_theme_constant_override(side, 14)
	detail_panel.add_child(dmargin)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dmargin.add_child(dv)
	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 22)
	dv.add_child(detail_title)
	detail_cat = Label.new()
	detail_cat.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	dv.add_child(detail_cat)
	dv.add_child(HSeparator.new())
	detail_body = RichTextLabel.new()
	detail_body.bbcode_enabled = true
	detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(detail_body)

func _refilter(query: String) -> void:
	for c in results_box.get_children():
		c.queue_free()
	var results := Lexicon.search(query)
	if results.is_empty():
		var lbl := Label.new()
		lbl.text = "(no matches)"
		results_box.add_child(lbl)
		return
	for e in results:
		var btn := Button.new()
		btn.text = "%s  ·  %s" % [e.get("term", "?"), e.get("category", "")]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.pressed.connect(_show_detail.bind(e))
		results_box.add_child(btn)

func _show_detail(e: Dictionary) -> void:
	detail_title.text = str(e.get("term", ""))
	detail_cat.text = str(e.get("category", ""))
	detail_body.text = str(e.get("definition", ""))
