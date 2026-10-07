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
## WHICH WALL THE DOOR IS ON is decided by how the player came in, not by where
## the door happens to sit in the village. The doorway that let them in reports
## the direction they were moving; this room puts its door on the wall behind
## them, so walking on carries them deeper into the house and turning back takes
## them out the way they came. Come in from the right and the door is on the
## right, which is the wall they have to walk back towards to leave.
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
@export var camera_distance := 21.0
## The X of the side walls: the plane a doorway sits in.
@export var wall_x := 6.0
## How far inside the door an arriving player is placed, metres. Kept small, so
## the player steps in just past the doorway rather than appearing deep in the
## room. Landing near the door wall is safe now that the camera below is
## levelled: the whole room width stays on screen, door wall included.
@export var entry_inset := 1.0

@onready var _room_camera: Camera3D = $RoomCamera
@onready var _exit_door: Area3D = $ExitDoor
@onready var _door_hole: MeshInstance3D = $Room/ExitDoorHole
@onready var _door_light: OmniLight3D = $DoorLight


func _ready() -> void:
	_room_camera.make_current()
	_room_camera.make_current.call_deferred()
	# The view is levelled here, not only in the scene: an authored yaw swings the
	# whole view sideways, which shifts one side wall - and the doorway sitting in
	# it - clean off the screen, so the player had to walk into the middle of the
	# room before they were visible. Straight down -Z keeps the framing symmetric
	# and the whole room reads at once. The distance is applied too, so the pan
	# maths below always agrees with where the camera actually is.
	_room_camera.rotation = Vector3.ZERO
	_room_camera.position.z = camera_distance
	var payload := SceneRouter.consume()
	var dir: Vector3 = payload.get("dir", Vector3.ZERO)
	var side := _door_side(dir)
	_apply_door_side(side)
	_place_player.call_deferred(side)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var limit := maxf(0.0, room_half_width - _view_half_width())
	_room_camera.position.x = clampf(player.global_position.x, -limit, limit)


## Which wall the door belongs on. The player travelled `dir` to get in, so the
## door goes on the wall behind them: +1 means the right wall, -1 the left. A
## mostly vertical entry (a door in the house's own south wall) keeps the door on
## the left, which is how the room is authored.
func _door_side(dir: Vector3) -> int:
	if absf(dir.x) > absf(dir.z) and absf(dir.x) > 0.01:
		return 1 if dir.x < 0.0 else -1
	return -1


## Moves the doorway, its dark opening and its light onto the chosen wall.
func _apply_door_side(side: int) -> void:
	var wall := wall_x * float(side)
	_exit_door.position = Vector3(wall, 1.1, 0.0)
	# The way out of the room is straight through the wall the door is on, so the
	# doorway only lets the player leave while they are actually heading that way.
	_exit_door.set("outward", Vector3(float(side), 0.0, 0.0))
	_door_hole.position = Vector3(wall - 0.1 * float(side), 1.1, 0.0)
	_door_light.position = Vector3(wall - 1.4 * float(side), 2.6, 0.5)


## Drops the player just inside the door they came through.
func _place_player(side: int) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	player.global_position = Vector3(float(side) * (wall_x - entry_inset), 0.05, 0.0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


## Half the width, in metres, that the camera sees at the room's own depth.
func _view_half_width() -> float:
	var viewport := get_viewport().get_visible_rect().size
	if viewport.y <= 0.0:
		return 0.0
	var visible_height := 2.0 * camera_distance * tan(deg_to_rad(_room_camera.fov) * 0.5)
	return visible_height * (viewport.x / viewport.y) * 0.5
