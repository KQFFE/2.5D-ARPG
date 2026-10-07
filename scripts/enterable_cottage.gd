extends StaticBody3D
## One cottage scene covers every cottage in the village.
##
## Most of them are shut: a brown door that decorates the wall and nothing more.
## A few can be walked into, and each of those leads to its own interior. Which is
## which is set PER INSTANCE - `enterable` and `interior_scene` - exactly the way a
## lamp post carries its own `checkpoint_id`, so the village keeps one reusable
## cottage scene instead of five near-copies.
##
## On a shut cottage the doorway trigger is switched OFF (not merely hidden), so
## bumping the wall can never pull the player into another scene.
##
## The work happens in the ROOT's _ready, which runs after the trigger's own
## _ready, so the target is in place before anything can fire.

## True when this cottage can be entered. Leave it false for a shut house.
@export var enterable := false
## The interior this cottage leads to. Required when `enterable` is true.
@export_file("*.tscn") var interior_scene := ""

@onready var _brown_door: MeshInstance3D = get_node_or_null("Door") as MeshInstance3D
@onready var _door_hole: MeshInstance3D = get_node_or_null("DoorHole") as MeshInstance3D
@onready var _trigger: Area3D = get_node_or_null("DoorTrigger") as Area3D


func _ready() -> void:
	var can_enter := enterable and not interior_scene.is_empty()
	# A shut house shows the wooden door; an enterable one shows the black
	# opening instead, and only the opening.
	if _brown_door != null:
		_brown_door.visible = not can_enter
	if _door_hole != null:
		_door_hole.visible = can_enter
	if _trigger == null:
		return
	_trigger.set("target_scene", interior_scene if can_enter else "")
	_trigger.monitoring = can_enter


## True when this instance is actually a way in, as the scene was configured.
func is_enterable() -> bool:
	return enterable and not interior_scene.is_empty()
