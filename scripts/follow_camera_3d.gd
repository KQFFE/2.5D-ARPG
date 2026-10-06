extends Node3D
## Fixed 3/4 follow camera rig for the 2.5D village.
##
## The rig only ever PITCHES - it never yaws with the player and its roll is
## hard-locked to 0 - so the world stays locked to the screen the way a 2D view
## would, while the scene itself is real 3D.
##
## The Camera3D sits straight behind the rig on local +Z. With Godot's -Z
## forward convention that means it looks north (-Z, screen-up) and down by
## `pitch_degrees`. The rig is meant to be a child of whatever it follows.
##
## Inspector tunables:
##   target_path      leave empty to follow the parent node
##   pitch_degrees    -40 is the cozy "lowered" 3/4 angle (-50 reads as a flat
##                    top-down; -30 sits almost behind the player)
##   distance         metres back along the rig's own tilted axis
##   height           how far above the followed node's origin the rig floats
##   follow_smoothing higher = tighter follow, 0 = snap instantly

@export var target_path: NodePath
@export var pitch_degrees := -40.0
@export var distance := 12.0
@export var height := 1.0
@export var follow_smoothing := 8.0

@onready var _camera: Camera3D = $Camera3D

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		_target = get_parent() as Node3D
	_apply_rig()
	if _target != null:
		global_position = _desired_position()
	_camera.current = true


func _process(delta: float) -> void:
	if _target == null:
		return
	var desired := _desired_position()
	if follow_smoothing > 0.0:
		global_position = global_position.lerp(desired, 1.0 - exp(-follow_smoothing * delta))
	else:
		global_position = desired
	_apply_rig()


## Locked pitch/roll and camera offset. Safe to call every frame.
func _apply_rig() -> void:
	rotation = Vector3(deg_to_rad(pitch_degrees), 0.0, 0.0)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.rotation = Vector3.ZERO


func _desired_position() -> Vector3:
	if _target == null:
		return global_position
	return _target.global_position + Vector3(0.0, height, 0.0)


func target_node() -> Node3D:
	return _target


func set_target(node: Node3D) -> void:
	_target = node
	global_position = _desired_position()
