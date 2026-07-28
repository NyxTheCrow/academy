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

## A single pointy-top hexagon cell. It draws itself as a real hexagon (filled +
## outlined) and only registers clicks that land INSIDE the hex, so the board
## reads and behaves as a hex grid rather than a sheared grid of squares.
class HexCell extends Control:
	signal clicked
	var _poly: PackedVector2Array   # hexagon centred on the control's origin
	var _center: Vector2
	var glyph := "·"
	var fill := Color(0.13, 0.12, 0.18)
	var edge := Color(0.30, 0.30, 0.40)
	var ink := Color(0.55, 0.58, 0.68)
	var disabled := true
	var _hover := false

	func _init(radius: float) -> void:
		var hw := sqrt(3.0) / 2.0 * radius       # half of a pointy-top hex's width
		_poly = PackedVector2Array([
			Vector2(0, -radius), Vector2(hw, -radius / 2.0), Vector2(hw, radius / 2.0),
			Vector2(0, radius), Vector2(-hw, radius / 2.0), Vector2(-hw, -radius / 2.0),
		])
		_center = Vector2(hw, radius)
		custom_minimum_size = Vector2(hw * 2.0, radius * 2.0)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	# Restrict input (and hover) to the actual hexagon, not its bounding box, so
	# neighbouring hexes never both claim a click in the shared corner region.
	func _has_point(point: Vector2) -> bool:
		return Geometry2D.is_point_in_polygon(point - _center, _poly)

	func _gui_input(event: InputEvent) -> void:
		if disabled:
			return
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()

	func _draw() -> void:
		var pts := PackedVector2Array()
		for p in _poly:
			pts.append(p + _center)
		var f := fill.lightened(0.18) if (not disabled and _hover) else fill
		draw_colored_polygon(pts, f)
		var outline := pts
		outline.append(pts[0])
		draw_polyline(outline, edge, 1.5, true)
		var font := ThemeDB.fallback_font
		var fs := 20
		var ts := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, _center + Vector2(-ts.x / 2.0, fs * 0.34), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

# Untyped on purpose: the engine's own methods aren't visible through a
# RefCounted-typed handle, so we call them dynamically (as Director does modes).
var _engine
var _reason := ""
var _pending := ""          # action id awaiting a target tile
var _cells: Array = []      # grid cell buttons
var _finished_flag := false

# Hex board: cells are manually placed (sheared axial layout), so the board is
# a plain Control, not a GridContainer.
const CELL := 56
var grid_box: Control
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

	grid_box = Control.new()
	grid_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(grid_box)
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

## Lay the axial hex board out with interlocking pointy-top hexagons: each row r
## is nudged right by half a cell and packed vertically by 3/4 of a hex height,
## so the cells tessellate like a real hex map. Index order (r outer, q inner)
## matches _redraw's flat indexing.
func _build_grid() -> void:
	var g: Vector2i = _engine.grid
	_cells.clear()
	for c in grid_box.get_children():
		c.queue_free()
	var radius := CELL / sqrt(3.0)     # circumradius of a pointy-top hex of width CELL
	var row_h := 1.5 * radius          # vertical step so rows interlock
	var full_w := (g.x + g.y * 0.5) * CELL + CELL
	var full_h := (g.y - 1) * row_h + radius * 2.0 + 4.0
	grid_box.custom_minimum_size = Vector2(full_w, full_h)
	for r in g.y:
		for q in g.x:
			var cell := HexCell.new(radius)
			cell.position = Vector2((q + r * 0.5) * CELL, r * row_h)
			cell.clicked.connect(_on_cell.bind(Vector2i(q, r)))
			grid_box.add_child(cell)
			_cells.append(cell)

func _build_action_bar() -> void:
	for child in action_bar.get_children():
		child.queue_free()
	var lbl := Label.new()
	lbl.text = "Act:"
	action_bar.add_child(lbl)
	var ids: Array = _engine.actions.keys()
	ids.sort()
	for id in ids:
		# "wait" is offered through the dedicated single-tick Hold button below;
		# don't also list it as an action (queuing it would fast-forward).
		if str(id) == "wait":
			continue
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
## Advance the engine to the next decision point and render it. Used after the
## player commits a real action (WEGO: fine time internally, coarse control).
func _pump() -> void:
	var res: Dictionary = _engine.advance()
	while res.get("reason", "") == "hit":
		res = _engine.advance()
	_apply(res)

## Render a decision state (from advance() or peek()) and set the banner.
func _apply(res: Dictionary) -> void:
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
		"watch":
			var tw: Dictionary = res.get("threat", {})
			if tw.is_empty():
				banner.text = "Your action is underway. Hold to let a tick pass."
			else:
				banner.text = "Committed — %s's %s resolves in %d. Hold to watch it out." % [
					str(tw.get("by", "?")), str(tw.get("action", "?")),
					int(tw.get("resolves_in", 0))]
		"plan":
			banner.text = "Your move. Pick an action, then a target tile."

func _redraw() -> void:
	var g: Vector2i = _engine.grid
	for i in _cells.size():
		_style_cell(_cells[i], Vector2i(i % g.x, i / g.x))
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

## Paint one hex cell for the tile at `pos`: base look, then any trap, then any
## occupant (player/enemy/downed) on top.
func _style_cell(cell, pos: Vector2i) -> void:
	cell.glyph = "·"
	cell.fill = Color(0.13, 0.12, 0.18)
	cell.edge = Color(0.30, 0.30, 0.40)
	cell.ink = Color(0.42, 0.45, 0.55)
	for t in _engine.traps:
		if t["pos"] == pos:
			cell.glyph = "^"
			cell.ink = Color(0.90, 0.60, 0.35)
	for u in _engine.units:
		if u["pos"] == pos:
			if u["down"]:
				cell.glyph = "x"
				cell.fill = Color(0.16, 0.13, 0.15)
				cell.ink = Color(0.55, 0.45, 0.47)
			elif u["team"] == "player":
				cell.glyph = "@" + ("+" if int(u["ward"]) > 0 else "")
				cell.fill = Color(0.12, 0.20, 0.30)
				cell.edge = Color(0.40, 0.62, 0.85)
				cell.ink = Color(0.72, 0.86, 1.0)
			else:
				cell.glyph = "E" + ("+" if int(u["ward"]) > 0 else "")
				cell.fill = Color(0.28, 0.13, 0.15)
				cell.edge = Color(0.85, 0.42, 0.42)
				cell.ink = Color(1.0, 0.74, 0.72)
	# Tiles are only pickable while targeting; highlight them when they are.
	cell.disabled = _pending == ""
	if not cell.disabled:
		cell.edge = cell.edge.lightened(0.20)
	cell.queue_redraw()

# --- Input ------------------------------------------------------------------
func _on_action(id: String) -> void:
	# Act whenever the engine would allow it (plan, react, or interrupt a
	# still-preparing action) — queue_action does the real gating.
	if _reason == "over":
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
	# Pass exactly ONE tick, then hand control straight back — never fast-forward
	# to a resolution. hold() lets an idle enemy press first, then advances a
	# single tick; peek() reports the resulting decision without moving time.
	_engine.hold()
	_apply(_engine.peek())

# --- End --------------------------------------------------------------------
func _on_over(win: String) -> void:
	_pending = ""
	for cell in _cells:
		cell.disabled = true
		cell.queue_redraw()
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
