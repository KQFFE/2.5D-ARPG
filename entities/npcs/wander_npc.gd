extends CharacterBody3D
## Reusable 3D "drift around my spawn point" locomotion, ported from the 2D
## prototype (res://scripts/wander_npc.gd).
##
## Freezes while a dialogue is running so nobody slides around mid-sentence.
## NPCs, sheep and goblins all inherit this - tune speed / wander_radius /
## pause_* from the Inspector instead of copying nodes.
##
## Convention: -Z is forward.

@export var speed := 1.4
@export var wander_radius := 3.0
@export var pause_min := 1.8
@export var pause_max := 3.6

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _timer := 0.0
var _locked := false


func _ready() -> void:
	_home = global_position
	_target = _home
	_pick_target()
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _on_dialogue_started() -> void:
	_locked = true


func _on_dialogue_ended() -> void:
	_locked = false


func _pick_target() -> void:
	var angle := randf() * TAU
	var dist := randf_range(wander_radius * 0.3, wander_radius)
	_target = _home + Vector3(cos(angle), 0.0, sin(angle)) * dist
	_timer = randf_range(pause_min, pause_max)


func _physics_process(delta: float) -> void:
	if _locked:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	_timer -= delta
	if _timer <= 0.0:
		_pick_target()
	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.15:
		velocity = Vector3.ZERO
	else:
		velocity = to_target.normalized() * speed
		face_dir(to_target)
	velocity.y = 0.0
	move_and_slide()


## Turns the "Visual" child so its front (-Z) looks along dir (XZ only).
##
## The VISUAL's WORLD yaw is set, not its local rotation, so the art faces `dir`
## no matter how the body node itself is rotated in the scene. A goblin, NPC or
## sheep turned in the editor therefore still looks where it is walking instead
## of off by that baked-in angle.
func face_dir(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	var visual := get_node_or_null("Visual")
	if visual is Node3D:
		(visual as Node3D).global_rotation = Vector3(0.0, atan2(-flat.x, -flat.z), 0.0)
