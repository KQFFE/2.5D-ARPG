extends Area3D
## A doorway the player walks into: the black doorhole on the outside of a
## house, or the doorway on the inside of that house. One script drives both
## directions; only the exported values differ.
##
## WHICH WAY THE PLAYER LEAVES COMES FROM THE DIRECTION THEY ARE MOVING when they
## touch the trigger - never from where the trigger sits in the scene. That
## direction travels with them to the scene being entered, which arranges itself
## around it: the interior puts its door on the wall the player came in through,
## so walking on carries them deeper into the house and turning back takes them
## out again the way they came.
##
## leads_inside separates the two jobs:
##   true  - the outside door of a building. It fires as soon as the player
##           touches it (the building wall stops them at the door anyway) and
##           remembers the spot just outside, so the matching exit can put the
##           player back on the street instead of at a scene spawn point.
##   false - the doorway inside a building. It fires only when the player is
##           HEADING OUT (moving along `outward`), so brushing past the doorway
##           on the way deeper in does not throw them back outside. It needs no
##           run-up and no distance past the trigger, because the room's own wall
##           is what the player is walking into.
##
## An arriving player is placed `exit_clearance` beyond the remembered outside
## doorway - and, when they left sideways, `lateral_clearance` to the opposite
## side of it - so they land clear of the trigger instead of standing inside it.

## The scene to enter when the player walks through this doorway.
@export_file("*.tscn") var target_scene := ""
## True when this trigger takes the player INTO a building (see the notes above).
@export var leads_inside := true
## For a doorway inside a building: the direction out of the room, in world
## space. The player must be moving roughly this way to leave. Unused when
## leads_inside is true.
@export var outward := Vector3(0.0, 0.0, 1.0)
## How closely the player's movement has to follow `outward` to count as leaving.
## 0.25 is about 75 degrees either side.
@export var outward_tolerance := 0.25
## How far beyond the remembered outside doorway an arriving player is placed,
## metres, so they come out clear of the trigger rather than inside it.
@export var exit_clearance := 1.2
## Sideways offset applied when the player leaves sideways, metres, so they come
## out on the opposite side of the doorway from the way they walked.
@export var lateral_clearance := 1.2

## Ground height for an arrival, so a doorway whose trigger sits at door height
## still puts the player on the floor.
const GROUND_Y := 0.05

var _fired := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _fired or body == null or not body.is_in_group("player"):
		return
	var dir := _travel_dir(body)
	if not leads_inside and not _heading_out(dir):
		return
	_leave(dir)


## True when the player's movement is roughly along the way out of the room.
func _heading_out(dir: Vector3) -> bool:
	var out := Vector3(outward.x, 0.0, outward.z)
	if out.length_squared() < 0.0001:
		return true
	return dir.dot(out.normalized()) >= outward_tolerance


## The direction the player is actually moving: that is what says which side of
## the doorway they used. Falls back to the way they face when standing still.
func _travel_dir(body: Node3D) -> Vector3:
	var dir := Vector3.ZERO
	if body is CharacterBody3D:
		dir = (body as CharacterBody3D).velocity
	dir.y = 0.0
	if dir.length_squared() < 0.0004 and body.has_method("facing_dir"):
		var facing: Variant = body.call("facing_dir")
		if facing is Vector3:
			var faced: Vector3 = facing
			faced.y = 0.0
			dir = faced
	if dir.length_squared() < 0.0004:
		return Vector3(0.0, 0.0, -1.0)
	return dir.normalized()


func _leave(dir: Vector3) -> void:
	if _fired or target_scene.is_empty():
		return
	_fired = true
	var payload := {"dir": dir}
	if leads_inside:
		# The player steps into the building moving `dir`, so the way back out is
		# the other way round; that is what the building's exit sends them to.
		SceneRouter.remember_door(global_position, -dir)
	else:
		var door: Variant = SceneRouter.remembered_door()
		if door != null:
			payload["spawn"] = _arrival_position(dir, door as Dictionary)
	SceneRouter.travel(target_scene, payload)


## Where the player comes out: just beyond the doorway they went in through, and
## - when they left sideways - shifted to the opposite side of it, so they are
## standing clear of the trigger rather than back inside it.
func _arrival_position(dir: Vector3, door: Dictionary) -> Vector3:
	var position: Vector3 = door["position"]
	var out: Vector3 = door["outward"]
	var arrival := position + out * exit_clearance
	var horizontal := absf(dir.x) > absf(dir.z)
	# Only for a doorway the player crosses sideways, and only when the outward
	# step is not already along X, so the two offsets cannot cancel out.
	if horizontal and absf(out.x) < 0.5:
		arrival.x += (-1.0 if dir.x > 0.0 else 1.0) * lateral_clearance
	arrival.y = GROUND_Y
	return arrival
