extends Node
## Puts the player where the previous scene said they should arrive.
##
## A door hands over a position through res://scripts/scene_router.gd when it
## changes scenes. This node consumes it one frame later, which is late enough
## that the player's own _ready and the village's checkpoint manager have
## finished moving the player to their default spot.
##
## Lives in both the village and the interior, so either direction of a doorway
## transition works with the same node. Does nothing on a normal start.

func _ready() -> void:
	var spawn: Variant = SceneRouter.consume_spawn()
	if spawn == null:
		return
	_place_player.call_deferred(spawn as Vector3)


func _place_player(spawn: Vector3) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	player.global_position = spawn
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
