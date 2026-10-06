extends CharacterBody3D
## Four-direction 3D player for the 2.5D village: movement (walk / run / jump /
## dash) and combat (arc attack / parry).
##
## Movement is on the XZ plane: -Z is forward / screen-up, matching the
## convention used by res://scenes/village.tscn. The body never rotates - only
## the "Visual" child turns to face the walk direction - so the follow camera
## rig on "CameraRig" keeps its fixed lowered 3/4 angle and never yaws with
## movement. Tune that rig in res://scripts/follow_camera_3d.gd
## (pitch_degrees, distance, height, follow_smoothing are exported there).
##
## Every input query here is by ACTION NAME only - never a raw keycode or mouse
## /joypad button number - so all of these abilities stay rebindable from the
## settings screen (res://ui/settings_screen.tscn via res://scripts/input_remap.gd).
##
## Health lives on the "Health" child (res://scripts/health.gd), the same
## component the goblins use. At zero health the player dies: after a short pause
## (respawn_delay) they wake at the last checkpoint they walked past (see
## res://scripts/checkpoint.gd and res://scripts/checkpoint_manager.gd), or back
## at their starting spot in the village when no checkpoint has been reached yet.
##
## If an AnimatedSprite3D named "AnimatedSprite3D" is dropped in later with the
## usual four-direction clip names (walk_down/up/left/right, idle_down/up/
## left/right) this controller drives it with no code changes.

@export_group("Movement")
## Normal ground speed, metres per second.
@export var speed := 4.2
@export var turn_speed := 14.0
## Speed multiplier applied while the "run" action is held.
@export var run_multiplier := 1.8
@export var gravity := 24.0
@export var jump_velocity := 7.0

@export_group("Dash")
@export var dash_speed := 16.0
@export var dash_duration := 0.18
## Hard cooldown between dashes, seconds.
@export var dash_cooldown := 3.0
## While true the player cannot be hurt for the WHOLE dash - the entire burst is
## invulnerable, so dashing through an attack is a real option.
@export var invulnerable_while_dashing := true

@export_group("Attack")
@export var attack_damage := 12.0
@export var attack_cooldown := 0.5
## How far in front of the player the arc reaches, metres.
@export var arc_reach := 2.0
## Half-angle of the attack arc, degrees either side of the facing direction.
@export var arc_half_angle_deg := 60.0
## How long the swing indicator stays on screen.
@export var attack_visual_time := 0.18

@export_group("Parry")
## How long the parry window stays open, seconds.
@export var parry_window := 0.4
@export var parry_cooldown := 0.7
## How far a successful parry shoves the player back, in metres.
@export var parry_knockback_distance := 0.5
## How long that shove lasts, seconds.
@export var parry_knockback_time := 0.15

@export_group("Respawn")
## How long the player is frozen after dying, before waking up at the last
## checkpoint. Gives a death half a beat instead of an instant teleport.
@export var respawn_delay := 0.4

const ATTACK_COLOR := Color(0.95, 0.85, 0.45)
const PARRY_COLOR := Color(0.45, 0.70, 1.00)
const PARRY_SUCCESS_COLOR := Color(0.50, 1.00, 0.55)
const DASH_IFRAME_COLOR := Color(0.88, 0.94, 1.00)
const ARC_ALPHA := 0.55

var _visual: Node3D = null
var _sprite: AnimatedSprite3D = null
var _health: Health = null
var _arc: MeshInstance3D = null
var _arc_mat: StandardMaterial3D = null

var _facing := "up"
var _locked := false
var _yaw := 0.0

var _dash_time := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3(0.0, 0.0, -1.0)

var _attack_cd := 0.0
var _attack_visual := 0.0

var _parry_time := 0.0
var _parry_cd := 0.0
## Parry shove: direction (away from the attacker) and how long it lasts.
var _parry_knock_dir := Vector3.ZERO
var _parry_knock_time := 0.0

## Counts down the death pause. While it runs the player is frozen at 0 health.
var _respawn_timer := 0.0
## Where the village placed the player; the fallback respawn point used until a
## checkpoint lamp post has been reached.
var _start_position := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	_visual = get_node_or_null("Visual") as Node3D
	var node := get_node_or_null("AnimatedSprite3D")
	if node is AnimatedSprite3D:
		_sprite = node
	if _visual != null:
		_yaw = _visual.rotation.y
	_health = get_node_or_null("Health") as Health
	if _health != null:
		_health.died.connect(_on_died)
	_start_position = global_position
	_build_attack_arc()
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _on_dialogue_started() -> void:
	_locked = true


func _on_dialogue_ended() -> void:
	_locked = false


## True once the moonleaf herb has been picked up (see herb_pickup.gd).
func has_herb() -> bool:
	return bool(get_meta(&"has_herb", false))


## Single entry point for anything that wants to hurt the player. Three things are
## checked here, in order, before any damage lands:
##   1. dash i-frames - the whole dash is invulnerable (invulnerable_while_dashing),
##      so a dash can be used to pass straight through an attack;
##   2. an open parry window - the hit is negated and the player is shoved back;
##   3. otherwise the damage goes to the Health child.
## Goblins (and any future hazard) should call this rather than reaching into
## Health directly.
func apply_damage(amount: float, source: Node = null) -> void:
	if invulnerable_while_dashing and _dash_time > 0.0:
		_on_dash_iframe()
		return
	if _parry_time > 0.0:
		# Direction away from whatever swung at us - the player is shoved back
		# along this by parry_knockback_distance.
		var away := -facing_dir()
		if source is Node3D:
			away = global_position - (source as Node3D).global_position
			away.y = 0.0
		if away.length_squared() < 0.0001:
			away = -facing_dir()
		_on_parry_success(away.normalized())
		return
	if _health != null:
		_health.take_damage(amount, source)


func is_alive() -> bool:
	return _health == null or _health.is_alive()


## Health reached zero. Freeze for respawn_delay, then wake at the last
## checkpoint (or where the village placed us, if none was ever reached).
func _on_died() -> void:
	_respawn_timer = maxf(respawn_delay, 0.01)
	velocity = Vector3.ZERO
	_dash_time = 0.0
	_attack_cd = 0.0
	_attack_visual = 0.0
	_parry_time = 0.0
	_parry_knock_time = 0.0
	_set_arc_color(ATTACK_COLOR)


## Wakes the player at the saved checkpoint and restores full health. The
## Checkpoints node in the village owns that position; without one we simply
## return to the spot the player started from.
func _finish_respawn() -> void:
	var target := _start_position
	var manager := get_tree().get_first_node_in_group("checkpoint_manager")
	if manager != null and manager.has_method("respawn_position"):
		target = manager.respawn_position(_start_position)
	global_position = target
	velocity = Vector3.ZERO
	if _health != null:
		_health.revive()


## Facing direction on the XZ plane. The Visual turns so its front marker (-Z)
## looks along the walk direction, so forward is that same rotated -Z.
func facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	# Dead: frozen at zero health until the pause elapses, then wake up.
	if _respawn_timer > 0.0:
		_respawn_timer = maxf(0.0, _respawn_timer - delta)
		velocity = Vector3.ZERO
		move_and_slide()
		if _respawn_timer <= 0.0:
			_finish_respawn()
		return
	if _locked:
		velocity = Vector3.ZERO
		move_and_slide()
		_update_animation(false)
		return

	# Jump and gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Combat intent.
	if Input.is_action_just_pressed("attack") and _attack_cd <= 0.0:
		_do_attack()
	if Input.is_action_just_pressed("parry") and _parry_cd <= 0.0:
		_do_parry()
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0 and _dash_time <= 0.0:
		_start_dash()

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0.0, input.y)

	if _dash_time > 0.0:
		velocity.x = _dash_dir.x * dash_speed
		velocity.z = _dash_dir.z * dash_speed
	else:
		var spd := speed
		if Input.is_action_pressed("run"):
			spd *= run_multiplier
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd

	var moving := dir.length_squared() > 0.0001
	if moving:
		_facing = _dir_to_name(dir)
		_aim(dir, delta)
	# A successful parry shoves the player back off the attacker.
	if _parry_knock_time > 0.0:
		var shove := parry_knockback_distance / maxf(parry_knockback_time, 0.001)
		velocity.x = _parry_knock_dir.x * shove
		velocity.z = _parry_knock_dir.z * shove
	move_and_slide()
	_update_animation(moving and _dash_time <= 0.0)


func _tick_timers(delta: float) -> void:
	_dash_time = maxf(0.0, _dash_time - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_parry_cd = maxf(0.0, _parry_cd - delta)
	_attack_visual = maxf(0.0, _attack_visual - delta)
	_parry_knock_time = maxf(0.0, _parry_knock_time - delta)
	if _parry_time > 0.0:
		_parry_time = maxf(0.0, _parry_time - delta)
	if _parry_time <= 0.0 and _attack_visual <= 0.0:
		_set_arc_color(ATTACK_COLOR)
	if _arc != null:
		_arc.visible = _attack_visual > 0.0 or _parry_time > 0.0


func _start_dash() -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0.0, input.y)
	if dir.length_squared() < 0.0001:
		dir = facing_dir()
	_dash_dir = dir.normalized()
	_dash_time = dash_duration
	_dash_cd = dash_cooldown
	_aim(_dash_dir, 1.0)


func _do_attack() -> void:
	_attack_cd = attack_cooldown
	_attack_visual = attack_visual_time
	_set_arc_color(ATTACK_COLOR)
	var facing := facing_dir()
	var origin := global_position
	var cos_limit := cos(deg_to_rad(arc_half_angle_deg))
	# Enemies register themselves in the "goblin" group, so this is an explicit
	# group query on the swing - not a per-frame walk of the whole scene tree.
	for node in get_tree().get_nodes_in_group("goblin"):
		var target := node as Node3D
		if target == null:
			continue
		var to_target := target.global_position - origin
		to_target.y = 0.0
		var dist := to_target.length()
		if dist < 0.001 or dist > arc_reach:
			continue
		# Inside the arc: within arc_half_angle_deg either side of facing.
		if facing.dot(to_target / dist) < cos_limit:
			continue
		if target.has_method("take_damage"):
			target.take_damage(attack_damage, self)


func _do_parry() -> void:
	_parry_time = parry_window
	_parry_cd = parry_cooldown
	_set_arc_color(PARRY_COLOR)


func _on_parry_success(away: Vector3) -> void:
	# A hit was negated: make the successful timing obvious, and shove the
	# player back off the attacker.
	_set_arc_color(PARRY_SUCCESS_COLOR)
	_attack_visual = maxf(_attack_visual, 0.25)
	_parry_knock_dir = away
	_parry_knock_time = parry_knockback_time
	_parry_time = 0.0


## A hit arrived while dashing: shrugged off. Flashes the wedge pale so the player
## can SEE that the dash ate the hit - a working i-frame with no feedback reads as
## a broken enemy.
func _on_dash_iframe() -> void:
	_set_arc_color(DASH_IFRAME_COLOR)
	_attack_visual = maxf(_attack_visual, 0.15)


## A filled arc (a pie slice) in front of the player, parented to Visual so it
## rotates with the facing direction for free. It spans exactly the same reach
## and half-angle the damage test below uses, so what you see is what you hit.
func _build_attack_arc() -> void:
	if _visual == null:
		return
	_arc = MeshInstance3D.new()
	_arc.name = "AttackArc"
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc.mesh = _build_arc_mesh()
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_mat.albedo_color = Color(ATTACK_COLOR.r, ATTACK_COLOR.g, ATTACK_COLOR.b, ARC_ALPHA)
	_arc.material_override = _arc_mat
	_arc.position = Vector3(0.0, 0.06, 0.0)
	_arc.visible = false
	_visual.add_child(_arc)


## Triangular fan filling the attack arc on the XZ plane, opening toward -Z
## (the player's forward). Vertex 0 sits at the player's feet and the rest trace
## the arc edge, so the wedge covers exactly arc_reach at arc_half_angle_deg
## either side of forward - the same region _do_attack() damages.
func _build_arc_mesh() -> ArrayMesh:
	var segments := 18
	var half := deg_to_rad(arc_half_angle_deg)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	norms.append(Vector3.UP)
	for i in segments + 1:
		var t := -half + (2.0 * half) * (float(i) / float(segments))
		verts.append(Vector3(sin(t) * arc_reach, 0.0, -cos(t) * arc_reach))
		norms.append(Vector3.UP)
	for i in segments:
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _set_arc_color(color: Color) -> void:
	if _arc_mat == null:
		return
	_arc_mat.albedo_color = Color(color.r, color.g, color.b, ARC_ALPHA)


func _aim(dir: Vector3, delta: float) -> void:
	if _visual == null:
		return
	# Facing -Z is "forward", so the yaw that points the front marker at dir is
	# atan2(-x, -z).
	var target_yaw := atan2(-dir.x, -dir.z)
	_yaw = lerp_angle(_yaw, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	_visual.rotation.y = _yaw


func _dir_to_name(dir: Vector3) -> String:
	if absf(dir.x) > absf(dir.z):
		return "right" if dir.x > 0.0 else "left"
	return "up" if dir.z < 0.0 else "down"


func _update_animation(moving: bool) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var anim := ("walk_" if moving else "idle_") + _facing
	if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)
