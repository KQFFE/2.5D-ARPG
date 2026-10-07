extends Area3D
## A doorway the player walks into.
##
## On entry the game changes to `target_scene` and the player is placed at
## `target_spawn` there (see res://scripts/scene_router.gd). The village house
## door and the doorway inside that house are the same node with different
## exports, so the trip works in both directions.
##
## The trigger sits in the doorway itself, not in the street in front of it, so
## the player has to actually reach the opening. A scene that returns the player
## must therefore place them clear of the trigger, or they bounce straight back.

## The scene to enter when the player touches this doorway.
@export_file("*.tscn") var target_scene := ""
## Where the player appears in that scene, in that scene's own coordinates.
@export var target_spawn := Vector3.ZERO

var _traveling := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _traveling or body == null or not body.is_in_group("player"):
		return
	if target_scene.is_empty():
		push_warning("DoorTrigger '%s': no target_scene set." % name)
		return
	_traveling = true
	SceneRouter.travel(target_scene, target_spawn)
