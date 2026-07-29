extends Control
## HexGrid — draws an axial hex board (pointy-top) and reports axial clicks.
##
## Pure presentation: the mode supplies a glyph (and optional fill colour) for
## each (q, r) cell, and receives cell_clicked(Vector2i) when a hex is picked.
## Geometry is the standard Red-Blob axial pointy-top layout, so rows interlock
## like a real hex map (½-cell horizontal shear + ¾-height vertical spacing)
## instead of the old sheared grid of squares. Pixel→axial hit-testing uses
## cube rounding, so a click lands on whichever hex it is actually inside.

signal cell_clicked(pos: Vector2i)

const SQRT3 := 1.7320508075688772

var cols: int = 7
var rows: int = 5
var radius: float = 30.0       # hex circumradius (centre -> vertex)
var enabled: bool = false      # tiles are only pickable while the mode is targeting
var glyph_provider: Callable   # (Vector2i) -> String  ("" / "." = empty cell)
var color_provider: Callable   # (Vector2i) -> Color   (alpha 0 = use default fill)

var _margin: float = 32.0

func configure(_cols: int, _rows: int) -> void:
	cols = maxi(1, _cols)
	rows = maxi(1, _rows)
	_update_size()
	queue_redraw()

func _ready() -> void:
	_update_size()

func _update_size() -> void:
	_margin = radius + 2.0
	# Widest row is the bottom one (largest r shears furthest right).
	var w := SQRT3 * radius * (cols + (rows - 1) * 0.5) + _margin
	var h := 1.5 * radius * (rows - 1) + 2.0 * radius + 4.0
	custom_minimum_size = Vector2(w, h)

# --- Axial <-> pixel (pointy-top, size = radius) ----------------------------
func _center(q: int, r: int) -> Vector2:
	return Vector2(
		SQRT3 * radius * (q + r * 0.5) + _margin,
		1.5 * radius * r + _margin)

func _hex_points(c: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i - 30.0)   # pointy top/bottom vertices
		pts.append(c + Vector2(cos(ang), sin(ang)) * radius)
	return pts

func _pixel_to_hex(p: Vector2) -> Vector2i:
	var px := p.x - _margin
	var py := p.y - _margin
	var qf := (SQRT3 / 3.0 * px - 1.0 / 3.0 * py) / radius
	var rf := (2.0 / 3.0 * py) / radius
	return _axial_round(qf, rf)

## Round fractional axial coords to the nearest hex via cube rounding.
func _axial_round(qf: float, rf: float) -> Vector2i:
	var xf := qf
	var zf := rf
	var yf := -xf - zf
	var rx := roundf(xf)
	var ry := roundf(yf)
	var rz := roundf(zf)
	var dx := absf(rx - xf)
	var dy := absf(ry - yf)
	var dz := absf(rz - zf)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))

# --- Drawing ----------------------------------------------------------------
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var fsize := 20
	for r in rows:
		for q in cols:
			var pos := Vector2i(q, r)
			var c := _center(q, r)
			var pts := _hex_points(c)
			var fill := Color(0.12, 0.11, 0.16)
			if color_provider.is_valid():
				var cp: Color = color_provider.call(pos)
				if cp.a > 0.0:
					fill = cp
			draw_colored_polygon(pts, fill)
			var outline := pts
			outline.append(pts[0])
			draw_polyline(outline, Color(0.32, 0.34, 0.42), 1.5, true)
			var g := ""
			if glyph_provider.is_valid():
				g = str(glyph_provider.call(pos))
			if g != "" and g != ".":
				var tw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
				draw_string(font, c + Vector2(-tw.x * 0.5, fsize * 0.35), g,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.88, 0.90, 0.98))
			else:
				draw_circle(c, 2.0, Color(0.30, 0.32, 0.40))

# --- Input ------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := _pixel_to_hex(event.position)
		if pos.x >= 0 and pos.x < cols and pos.y >= 0 and pos.y < rows:
			cell_clicked.emit(pos)
			accept_event()
