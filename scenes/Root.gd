extends Control
## Root — the main scene. Wires the Director to a host container, runs character
## creation, then boots the academy as the base mode. The debug overlay is
## layered on top of everything.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var host := Control.new()
	host.name = "ModeHost"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)

	# Debug overlay sits above all modes (its own CanvasLayer), toggled with F3.
	var overlay := preload("res://scenes/DebugOverlay.tscn").instantiate()
	add_child(overlay)

	Director.register_host(host)
	# Character creation first; it applies the player's choices to GameState.
	await Director.run_mode("charcreation", {})
	Director.set_base_mode("academy")
