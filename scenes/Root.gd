extends Control
## Root — the main scene. Wires the Director to a host container and runs the
## top-level application loop: main menu → (new game / load / editor) → back to
## menu. The debug overlay is layered above everything.

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
	await _app_loop()

## The application never leaves this loop except by quitting.
func _app_loop() -> void:
	while true:
		var choice: Dictionary = await Director.run_mode("mainmenu", {})
		match str(choice.get("action", "")):
			"new_game":
				var made: Dictionary = await Director.run_mode("charcreation", {})
				if made.get("started", false):
					await Director.run_mode("academy", {})
			"load_game":
				var loaded: Dictionary = await Director.run_mode("saves", {"load_only": true})
				if loaded.get("loaded", false):
					await Director.run_mode("academy", {})
			"editor":
				await Director.run_mode("editor", {"standalone": true})
			"simulation":
				# Ghost mode: a fresh clock and roster to watch, no player character.
				GameState.reset()
				Students.reset()
				await Director.run_mode("simulation", {})
			_:
				pass  # unknown/closed — show the menu again
