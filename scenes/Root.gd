extends Control
## Root — the main scene. Wires the Director to a host container and boots the
## academy as the base mode, then layers the debug overlay on top of everything.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var host := Control.new()
	host.name = "ModeHost"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)

	Director.register_host(host)
	Director.set_base_mode("academy")

	# Debug overlay sits above all modes (its own CanvasLayer), toggled with F3.
	var overlay := preload("res://scenes/DebugOverlay.tscn").instantiate()
	add_child(overlay)
