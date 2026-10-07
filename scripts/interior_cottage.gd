extends Node3D
## The first interior: the room behind the enterable house's black doorhole.
##
## The room is real 3D, but the camera is fixed to the side - it sits far back on
## +Z and looks down -Z with a narrow field of view, so the depth of the room
## barely changes the scale of anything. What the player sees is a side view:
## left and right along X, up and down along Y, with the room's depth reading as
## backdrop. That is the side-view interior the vision describes, built in the
## same 3D world as the village.
##
## The player scene is the village's own, unchanged, and its follow camera
## switches itself on in its own _ready. This script takes the camera back, both
## immediately (so there is no one-frame flash of the wrong view) and once more a
## frame later, as a safety net against anything else claiming it.

## Half the room's usable width in metres. The camera pans along X to keep the
## player framed, but never far enough to look past a side wall - and when the
## whole room already fits on screen, it does not pan at all.
@export var room_half_width := 6.0
## How far in front of the room the camera sits, metres. Must match RoomCamera's
## own Z.
@export var camera_distance := 18.0

@onready var _room_camera: Camera3D = $RoomCamera


func _ready() -> void:
	_room_camera.make_current()
	_room_camera.make_current.call_deferred()


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var limit := maxf(0.0, room_half_width - _view_half_width())
	_room_camera.position.x = clampf(player.global_position.x, -limit, limit)


## Half the width, in metres, that the camera sees at the room's own depth.
func _view_half_width() -> float:
	var viewport := get_viewport().get_visible_rect().size
	if viewport.y <= 0.0:
		return 0.0
	var visible_height := 2.0 * camera_distance * tan(deg_to_rad(_room_camera.fov) * 0.5)
	return visible_height * (viewport.x / viewport.y) * 0.5
