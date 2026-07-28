extends "res://scripts/GameMode.gd"
## TickCombatMode — a rough playable front-end for the prototype timeline
## combat engine (scripts/combat/TickEngine.gd). This is a design toy, not the
## shipping combat: numbers are always visible and the framing is deliberately
## bare so the mechanics are legible.
##
## Loop: the engine advances to a decision point; we render the board and hand
## control back to the player to PLAN (when idle) or REACT (when the enemy has
## telegraphed something the player can still answer). Pick an action, then a
## target tile; "Hold" lets a tick pass so the enemy commits.

const TickEngine := preload("res://scripts/combat/TickEngine.gd")
const HexGrid := preload("res://scenes/modes/HexGrid.gd")

# Untyped on purpose: the engine's own methods aren't visible through a
# RefCounted-typed handle, so we call them dynamically (as Director does modes).
var _engine
var _reason := ""
var _pending := ""          # action id awaiting a target tile
var _finished_flag := false

# The board is drawn as real pointy-top hexagons by HexGrid, which also reports
# clicks back in axial coordinates.
var hex: HexGrid
var log_box: RichTextLabel
var banner: Label
var status: Label
var action_bar: HBoxContainer
var hint: Label

func enter(context: Dictionary) -> void:
	_engine = TickEngine.new()
	var cfg: Dictionary = context.get("config", {})
	_engine.setup(cfg)
	_build_ui()
	_pump()

# --- UI ---------------------------------------------------------------------
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var title := Label.new()
	title.text = "Timeline Duel  (prototype)"
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var quit := Button.new()
	quit.text = "Leave"
	quit.pressed.connect(_bail)
	top.add_child(quit)

	banner = Label.new()
	banner.add_theme_font_size_override("font_size", 16)
	banner.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	v.add_child(banner)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	hex = HexGrid.new()
	hex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hex.glyph_provider = Callable(self, "_glyph")
	hex.color_provider = Callable(self, "_cell_color")
	hex.cell_clicked.connect(_on_cell)
	body.add_child(hex)
	_build_grid()

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(log_box)

	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	v.add_child(status)
	hint = Label.new()
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	v.add_child(hint)

	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 6)
	v.add_child(action_bar)
	_build_action_bar()

## Size the hex board to the engine's grid.
func _build_grid() -> void:
	var g: Vector2i = _engine.grid
	hex.configure(g.x, g.y)

func _build_action_bar() -> void:
	for child in action_bar.get_children():
		child.queue_free()
	var lbl := Label.new()
	lbl.text = "Act:"
	action_bar.add_child(lbl)
	var ids: Array = _engine.actions.keys()
	ids.sort()
	for id in ids:
		var a: Dictionary = _engine.actions[id]
		var b := Button.new()
		b.text = "%s  (%dr)" % [str(a.get("name", id)), int(a.get("readiness_cost", 1))]
		b.tooltip_text = "%s\nstartup %d · commit %d · recovery %d\n%s" % [
			str(a.get("name", id)), int(a.get("startup", 1)), int(a.get("commit", 1)),
			int(a.get("recovery", 1)), str(a.get("description", ""))]
		b.pressed.connect(_on_action.bind(str(id)))
		action_bar.add_child(b)
	var hold := Button.new()
	hold.text = "Hold (pass tick)"
	hold.pressed.connect(_on_hold)
	action_bar.add_child(hold)

# --- Engine driving ---------------------------------------------------------
## Advance the engine to the next decision point and render it.
func _pump() -> void:
	var res: Dictionary = _engine.advance()
	while res.get("reason", "") == "hit":
		res = _engine.advance()
	_reason = str(res.get("reason", ""))
	_redraw()
	match _reason:
		"over":
			_on_over(str(res.get("winner", "")))
		"reaction":
			var t: Dictionary = res.get("threat", {})
			banner.text = "REACT — %s casts %s at %s (resolves in %d). Interrupt, or Hold." % [
				str(t.get("by", "?")), str(t.get("action", "?")),
				str(t.get("target", "")), int(t.get("resolves_in", 0))]
		"plan":
			banner.text = "Your move. Pick an action, then a target tile."

func _redraw() -> void:
	hex.enabled = _pending != ""   # tiles are only pickable while targeting
	hex.queue_redraw()
	# Log tail.
	var lines: Array = _engine.log
	var tail: Array = lines.slice(maxi(0, lines.size() - 14), lines.size())
	log_box.text = "\n".join(tail)
	# Status: readiness + phase of each unit.
	var parts: Array = []
	for u in _engine.units:
		var st := "down" if u["down"] else "idle"
		if not u["down"] and not u["plan"].is_empty():
			st = "%s" % str(u["plan"]["name"])
		parts.append("%s: rdy %d · %s" % [str(u["name"]), int(u["readiness"]), st])
	status.text = "   |   ".join(parts)
	hint.text = ("Targeting %s — click a tile." % _pending) if _pending != "" else str(_engine.last_error)

func _glyph(pos: Vector2i) -> String:
	for u in _engine.units:
		if u["pos"] == pos:
			if u["down"]:
				return "x"
			var mark := "@" if u["team"] == "player" else "E"
			if int(u["ward"]) > 0:
				mark += "+"
			return mark
	for t in _engine.traps:
		if t["pos"] == pos:
			return "^"
	return "."

## Fill tint for a hex. Alpha 0 lets HexGrid use its default empty-cell colour.
func _cell_color(pos: Vector2i) -> Color:
	for u in _engine.units:
		if u["pos"] == pos:
			if u["down"]:
				return Color(0.14, 0.14, 0.16)
			return Color(0.16, 0.20, 0.34) if u["team"] == "player" else Color(0.30, 0.14, 0.16)
	for t in _engine.traps:
		if t["pos"] == pos:
			return Color(0.28, 0.22, 0.10)
	return Color(0, 0, 0, 0)

# --- Input ------------------------------------------------------------------
func _on_action(id: String) -> void:
	if _reason != "plan" and _reason != "reaction":
		return
	var a: Dictionary = _engine.actions.get(id, {})
	# Self actions need no target tile — queue them immediately.
	if str(a.get("kind", "self")) == "self":
		if _engine.queue_action(_engine.player()["id"], id, _engine.player()["pos"]):
			_pending = ""
			_pump()
		else:
			_redraw()
		return
	_pending = id
	_redraw()

func _on_cell(pos: Vector2i) -> void:
	if _pending == "":
		return
	if _engine.queue_action(_engine.player()["id"], _pending, pos):
		_pending = ""
		_pump()
	else:
		_redraw()   # show the error (e.g. not ready / committed)

func _on_hold() -> void:
	if _reason == "over":
		return
	_pending = ""
	var p = _engine.player()
	if _engine.is_idle(p):
		# Idle: a brief free "wait" so time passes and the enemy gets to press,
		# rather than the player keeping the initiative forever.
		if _engine.actions.has("wait"):
			_engine.queue_action(p["id"], "wait", p["pos"])
		else:
			_engine.step()
	else:
		# Mid-action: just let a tick pass so the CURRENT plan continues — do not
		# interrupt it.
		_engine.step()
	_pump()

# --- End --------------------------------------------------------------------
func _on_over(win: String) -> void:
	_pending = ""
	hex.enabled = false
	hex.queue_redraw()
	if win == "player":
		banner.text = "You win the duel."
	else:
		banner.text = "You are struck down."
	var done := Button.new()
	done.text = "Continue"
	var effects := {"needs": {"calm": 8}} if win == "player" else {"energy": -20, "needs": {"calm": -10}}
	done.pressed.connect(func(): _emit({"effects": effects, "winner": win}))
	action_bar.add_child(done)

func _bail() -> void:
	_emit({"effects": {}, "winner": "bail"})

func _emit(result: Dictionary) -> void:
	if _finished_flag:
		return
	_finished_flag = true
	finished.emit(result)
