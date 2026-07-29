extends Node
## Game — the autoload that holds the live runtime for the NEW core. One Content
## (loaded once) and one World the UI reads and drives. This is deliberately thin:
## it is just the global handle so modes don't have to thread a World reference
## through every Director.run_mode call.
##
## Referenced by preload const (not a typed autoload field), matching the codebase
## convention that keeps autoloads safe to compile before the class_name registry
## is populated on a clean import.

const ContentC := preload("res://core/Content.gd")
const WorldC := preload("res://core/World.gd")

var content            # Content
var world              # World

func _ready() -> void:
	boot()

## (Re)load content and build a fresh world (a new game at defaults).
func boot() -> void:
	content = ContentC.new()
	content.load_all()
	world = WorldC.new()
	world.setup(content)

## Start a new game: fresh world, then apply character-creation choices.
func new_game(player_name := "", dev := false) -> void:
	boot()
	if world.player != null:
		if player_name.strip_edges() != "":
			world.player.name = player_name.strip_edges()
	world.dev_mode = dev

## Ensure a world exists (e.g. before loading into it).
func ensure_world() -> void:
	if world == null:
		boot()
