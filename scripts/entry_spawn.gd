extends Node
## Puts the player where the previous scene said they should arrive.
##
## A doorway hands over a position through res://scripts/scene_router.gd when it
## changes scenes. This node consumes it one frame later, which is late enough
## that the player's own _ready and the village's checkpoint manager have
## finished moving the player to their default spot.
##
## Lives in the village, which is where a trip out of a building lands. An
## interior does not need one: it places the player itself, because where it puts
## them depends on which wall its door ended up on. Does nothing on a normal
## start, when the payload carries no position.

func _ready() -> void:
	var payload := SceneRouter.consume()
	var spawn: Variant = payload.get("spawn")
	if spawn == null:
		return
	# The direction the player was going when they left the building travels with
	# them, so they arrive facing the way they walked out instead of snapping back
	# to the player scene's default facing.
	var dir: Vector3 = payload.get("dir", Vector3.ZERO)
	_place_player.call_deferred(spawn as Vector3, dir)


func _place_player(spawn: Vector3, dir: Vector3) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	player.global_position = spawn
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if player.has_method("set_facing"):
		player.call("set_facing", dir)
