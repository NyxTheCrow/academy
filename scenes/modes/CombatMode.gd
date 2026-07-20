extends GameMode
## CombatMode — the tactical-combat spine.
##
## A deliberately small but complete turn-based grid fight: units with HP/attack
## on a grid, a player turn (one move + one attack), a simple enemy AI, and
## win/lose resolution. The player unit is derived from GameState stats, and the
## outcome is handed back as a result dictionary — so combat writes to the world
## through the exact same `effects` boundary as everything else.
##
## This is the skeleton to grow the "in-depth tactical" layer into (terrain,
## abilities, statuses, multiple party members). None of that touches the spine.

const GRID_W := 6
const GRID_H := 5
const CELL := 64

var _units: Array = []          # each: {name, team, hp, max_hp, atk, move, pos:Vector2i, glyph}
var _player: Dictionary = {}
var _reward: Dictionary = {}
var _penalty: Dictionary = {}
var _player_turn := true
var _has_moved := false
var _has_attacked := false

var _cells: Array = []          # Button grid, index = y * GRID_W + x
var info_label: Label
var log_box: RichTextLabel
var end_turn_btn: Button

func enter(context: Dictionary) -> void:
	var enc := GameData.get_encounter(str(context.get("encounter_id", "")))
	_reward = enc.get("reward", {"effects": {"stats": {"combat": 2}}})
	_penalty = enc.get("penalty", {"effects": {"energy": -30}})
	_build_ui(enc.get("name", "Battle"))
	_spawn_units(enc)
	_redraw()
	_log("A battle begins! Move onto a tile in range, then strike an adjacent foe.")

# --- Setup ------------------------------------------------------------------
func _spawn_units(enc: Dictionary) -> void:
	_units.clear()
	var combat_stat: int = int(GameState.stats.get("combat", 0))
	var magic_stat: int = int(GameState.stats.get("magic", 0))
	_player = {
		"name": "You", "team": "player", "glyph": "@",
		"max_hp": 20 + combat_stat * 2, "hp": 20 + combat_stat * 2,
		"atk": 4 + combat_stat + int(magic_stat / 2.0), "move": 3,
		"pos": Vector2i(0, GRID_H / 2),
	}
	_units.append(_player)

	var enemies: Array = enc.get("enemies", [
		{"name": "Rival", "hp": 22, "atk": 5, "move": 3},
	])
	var slot := 0
	for e in enemies:
		_units.append({
			"name": e.get("name", "Foe"), "team": "enemy", "glyph": "E",
			"max_hp": int(e.get("hp", 20)), "hp": int(e.get("hp", 20)),
			"atk": int(e.get("atk", 5)), "move": int(e.get("move", 3)),
			"pos": Vector2i(GRID_W - 1, clampi(1 + slot, 0, GRID_H - 1)),
		})
		slot += 2

# --- UI ---------------------------------------------------------------------
func _build_ui(title: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var title_lbl := Label.new()
	title_lbl.text = "⚔  %s" % title
	title_lbl.add_theme_font_size_override("font_size", 22)
	v.add_child(title_lbl)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)

	var grid := GridContainer.new()
	grid.columns = GRID_W
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	h.add_child(grid)
	_cells.clear()
	for i in GRID_W * GRID_H:
		var b := Button.new()
		b.custom_minimum_size = Vector2(CELL, CELL)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(b)
		_cells.append(b)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(280, 0)
	side.add_theme_constant_override("separation", 10)
	h.add_child(side)

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info_label)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(log_box)

	end_turn_btn = Button.new()
	end_turn_btn.text = "End Turn"
	end_turn_btn.pressed.connect(_end_player_turn)
	v.add_child(end_turn_btn)

# --- Rendering --------------------------------------------------------------
func _unit_at(pos: Vector2i) -> Dictionary:
	for u in _units:
		if u["pos"] == pos:
			return u
	return {}

func _redraw() -> void:
	for y in GRID_H:
		for x in GRID_W:
			var b: Button = _cells[y * GRID_W + x]
			var pos := Vector2i(x, y)
			var u := _unit_at(pos)
			if u.is_empty():
				b.text = ""
				b.modulate = Color.WHITE
				# highlight reachable tiles during the player's turn
				if _player_turn and not _has_moved and _reachable(_player["pos"], pos, _player["move"]):
					b.modulate = Color(0.6, 0.9, 1.0)
			else:
				b.text = u["glyph"]
				b.modulate = (Color(0.7, 1.0, 0.7) if u["team"] == "player" else Color(1.0, 0.7, 0.7))

	var s := ""
	for u in _units:
		s += "%s  HP %d/%d  ATK %d\n" % [u["name"], u["hp"], u["max_hp"], u["atk"]]
	s += "\n" + ("Your turn" if _player_turn else "Enemy turn")
	if _player_turn:
		s += "  (moved: %s, attacked: %s)" % [str(_has_moved), str(_has_attacked)]
	info_label.text = s
	end_turn_btn.disabled = not _player_turn

func _log(text: String) -> void:
	log_box.append_text(text + "\n")

# --- Rules ------------------------------------------------------------------
func _dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _reachable(from: Vector2i, to: Vector2i, move: int) -> bool:
	return _dist(from, to) <= move and _unit_at(to).is_empty()

func _on_cell_pressed(index: int) -> void:
	if not _player_turn:
		return
	var pos := Vector2i(index % GRID_W, index / GRID_W)
	var target := _unit_at(pos)

	if not target.is_empty() and target["team"] == "enemy":
		if not _has_attacked and _dist(_player["pos"], pos) <= 1:
			_attack(_player, target)
			_has_attacked = true
			_after_action()
		else:
			_log("[color=gray]Too far to strike — move adjacent first.[/color]")
		return

	if target.is_empty() and not _has_moved and _reachable(_player["pos"], pos, _player["move"]):
		_player["pos"] = pos
		_has_moved = true
		_redraw()

func _attack(attacker: Dictionary, defender: Dictionary) -> void:
	var dmg: int = maxi(1, int(attacker["atk"]) - randi_range(0, 2))
	defender["hp"] = int(defender["hp"]) - dmg
	_log("%s hits %s for [color=orange]%d[/color]." % [attacker["name"], defender["name"], dmg])
	if defender["hp"] <= 0:
		_log("[color=yellow]%s is defeated![/color]" % defender["name"])
		_units.erase(defender)

func _after_action() -> void:
	_redraw()
	if _check_end():
		return
	# If the player has both moved and attacked, auto-pass the turn.
	if _has_moved and _has_attacked:
		_end_player_turn()

func _end_player_turn() -> void:
	if _check_end():
		return
	_player_turn = false
	_redraw()
	_enemy_turn()

func _enemy_turn() -> void:
	for u in _units.duplicate():
		if u["team"] != "enemy" or not _units.has(u):
			continue
		# Step toward the player, then attack if adjacent.
		var steps: int = int(u["move"])
		while steps > 0 and _dist(u["pos"], _player["pos"]) > 1:
			u["pos"] = _step_toward(u["pos"], _player["pos"])
			steps -= 1
		if _dist(u["pos"], _player["pos"]) <= 1:
			_attack(u, _player)
			if _check_end():
				return
	_player_turn = true
	_has_moved = false
	_has_attacked = false
	_redraw()

func _step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var next := from
	if from.x != to.x:
		next.x += signi(to.x - from.x)
	elif from.y != to.y:
		next.y += signi(to.y - from.y)
	# Don't step onto an occupied tile.
	if not _unit_at(next).is_empty():
		return from
	return next

func _check_end() -> bool:
	if _player["hp"] <= 0:
		_log("[color=salmon]You have fallen...[/color]")
		var r := _penalty.duplicate(true)
		r["outcome"] = "lose"
		_finish(r)
		return true
	var enemies_left := false
	for u in _units:
		if u["team"] == "enemy":
			enemies_left = true
			break
	if not enemies_left:
		_log("[color=lightgreen]Victory![/color]")
		var r2 := _reward.duplicate(true)
		r2["outcome"] = "win"
		_finish(r2)
		return true
	return false

var _finished := false
func _finish(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	end_turn_btn.disabled = true
	# Brief pause so the player can read the final log line.
	await get_tree().create_timer(1.2).timeout
	finished.emit(result)
