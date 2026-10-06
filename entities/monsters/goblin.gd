extends "res://entities/npcs/wander_npc.gd"
## Goblin for the fields beyond the gate.
##
## States:
##   WANDER  - drifts around its patch at the slow wander `speed` (base class).
##   CHASE   - spotted the player (within watch_radius): closes in at chase_speed.
##   ATTACK  - a one-second swiping animation. Damage can only land INSIDE that
##             animation's hit window, and only on a target inside the swipe arc.
##   RETREAT - runs a few metres after the swipe.
##   STUNNED - hit by the player: the swipe is CANCELLED, the goblin is shoved and
##             held still for stun_time. A goblin that was just hit cannot attack.
##
## A goblin only starts a swipe when the player is within attack_range AND either
## it chased them there (CHASE), or it is already facing them (WANDER).
##
## Health is the shared res://scripts/health.gd component, same as the player's.
## The player's arc calls take_damage() here, so the arc never has to know about
## the Health node.
##
## Input-free: goblins never read input. Every number is exported below.

enum State { WANDER, CHASE, ATTACK, RETREAT, STUNNED }

## A peaceful goblin only wanders and stares. True is the normal field goblin.
@export var hostile := true
## How close the player must be to be spotted, metres.
@export var watch_radius := 6.0
## How far the player must get before a chase is abandoned, metres.
@export var lose_radius := 9.0

@export_group("Chase")
## Closing speed while hunting the player. The wander `speed` above stays slow.
@export var chase_speed := 1.8

@export_group("Attack")
## Distance at which the goblin commits to a swipe, metres.
@export var attack_range := 1.2
## How far off its facing the player may be and still count as "facing" them,
## degrees. This is the second way a swipe may begin (see _should_attack).
@export var facing_angle_deg := 50.0
## Total length of the swipe animation, seconds.
@export var attack_duration := 1.0
## The swipe can only hurt the player between these two moments of the
## animation, seconds measured from its start. Outside the window it is only
## animation, never damage.
@export var hit_window_start := 0.2
@export var hit_window_end := 0.85
## Half-angle of the swipe arc, degrees either side of facing. This is what the
## damage test uses.
@export var swipe_half_angle_deg := 60.0
## Width of the visible blade, half-angle in degrees - cosmetic only.
@export var blade_half_angle_deg := 16.0
## Extra reach allowed at the moment of the swipe.
@export var swing_grace := 0.35
@export var swing_damage := 1.0

@export_group("Retreat")
## How far it runs after a swipe, metres.
@export var retreat_distance := 4.0
@export var retreat_speed := 2.8

@export_group("Stun")
## How long a hit holds the goblin still, seconds.
@export var stun_time := 0.35
## Push applied by the hit that stunned it.
@export var knockback_speed := 4.0
## How long that shove lasts, seconds. Kept well under stun_time so the goblin
## does not slide out of the player's reach while it is still stunned.
@export var knockback_time := 0.12

const SWIPE_COLOR := Color(0.95, 0.5, 0.3)
const SWIPE_ALPHA := 0.55

var _state: int = State.WANDER
var _state_timer := 0.0
## Seconds into the current swipe animation.
var _swing_time := 0.0
## True once this swipe has already landed its one hit.
var _hit_done := false
var _retreat_dir := Vector3(0.0, 0.0, 1.0)
var _knock_dir := Vector3(0.0, 0.0, 1.0)
var _knock_timer := 0.0
var _swipe: MeshInstance3D = null
var _swipe_mat: StandardMaterial3D = null
var _health: Health = null


func _ready() -> void:
	super._ready()
	add_to_group("goblin")
	_health = get_node_or_null("Health") as Health
	if _health != null:
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
	_build_swipe()


func _physics_process(delta: float) -> void:
	# Frozen mid-sentence while a dialogue runs (same convention as every NPC).
	if _locked:
		_set_swipe_visible(false)
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var player := _player_node()
	var to_player := Vector3.ZERO
	var dist := INF
	if player != null:
		to_player = player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()

	# A peaceful goblin does nothing but pace and watch.
	if not hostile:
		super._physics_process(delta)
		_stare_at_player()
		return

	match _state:
		State.WANDER:
			super._physics_process(delta)
			if _should_attack(dist, to_player):
				_enter_attack(to_player)
			elif dist <= watch_radius:
				_state = State.CHASE

		State.CHASE:
			if player == null or dist > lose_radius:
				_state = State.WANDER
				_home = global_position
				return
			if dist <= attack_range:
				_enter_attack(to_player)
				return
			var dir := to_player / maxf(dist, 0.001)
			velocity.x = dir.x * chase_speed
			velocity.z = dir.z * chase_speed
			velocity.y = 0.0
			face_dir(dir)
			move_and_slide()

		State.ATTACK:
			_attack_tick(delta, player, to_player, dist)

		State.RETREAT:
			_state_timer -= delta
			velocity.x = _retreat_dir.x * retreat_speed
			velocity.z = _retreat_dir.z * retreat_speed
			velocity.y = 0.0
			face_dir(_retreat_dir)
			move_and_slide()
			if _state_timer <= 0.0:
				_state = State.WANDER
				_home = global_position

		State.STUNNED:
			_state_timer -= delta
			if _knock_timer > 0.0:
				_knock_timer -= delta
				velocity.x = _knock_dir.x * knockback_speed
				velocity.z = _knock_dir.z * knockback_speed
			else:
				velocity.x = 0.0
				velocity.z = 0.0
			velocity.y = 0.0
			move_and_slide()
			if _state_timer <= 0.0:
				_enter_retreat(player)


## The two ways a swipe may begin: the goblin just chased the player into range,
## or it is simply standing in range already facing them.
func _should_attack(dist: float, to_player: Vector3) -> bool:
	if dist > attack_range:
		return false
	if _state == State.CHASE:
		return true
	return _is_facing_player(to_player, dist)


## True when the goblin's front (-Z) is pointed within facing_angle_deg of the
## direction to the player.
func _is_facing_player(to_player: Vector3, dist: float) -> bool:
	if dist < 0.001:
		return true
	var limit := cos(deg_to_rad(facing_angle_deg))
	return _facing_dir().dot(to_player / dist) >= limit


## Forward on the XZ plane, taken from the Visual's yaw. -Z is forward.
func _facing_dir() -> Vector3:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		return Vector3(0.0, 0.0, -1.0)
	return Vector3(-sin(visual.rotation.y), 0.0, -cos(visual.rotation.y))


func _enter_attack(to_player: Vector3) -> void:
	# Turn to face the target first, so the swipe arc is centred on it.
	if to_player.length_squared() > 0.0001:
		face_dir(to_player)
	_state = State.ATTACK
	_swing_time = 0.0
	_hit_done = false
	velocity = Vector3.ZERO
	_set_swipe_visible(true)
	_update_swipe()


## The swipe animation. Damage can only land inside the hit window, and only
## once per swipe.
func _attack_tick(delta: float, player: Node3D, to_player: Vector3, dist: float) -> void:
	_swing_time += delta
	velocity = Vector3.ZERO
	move_and_slide()
	_update_swipe()

	if not _hit_done and _swing_time >= hit_window_start and _swing_time <= hit_window_end:
		if player != null and dist <= attack_range + swing_grace and _in_swipe_arc(to_player, dist):
			_hit_done = true
			if player.has_method("apply_damage"):
				player.apply_damage(swing_damage, self)

	if _swing_time >= attack_duration:
		_set_swipe_visible(false)
		_enter_retreat(player)


func _in_swipe_arc(to_player: Vector3, dist: float) -> bool:
	if dist < 0.001:
		return true
	return _facing_dir().dot(to_player / dist) >= cos(deg_to_rad(swipe_half_angle_deg))


func _enter_retreat(player: Node3D) -> void:
	_set_swipe_visible(false)
	var away := Vector3(0.0, 0.0, 1.0)
	if player != null:
		away = global_position - player.global_position
		away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(0.0, 0.0, 1.0)
	_retreat_dir = away.normalized()
	_state = State.RETREAT
	_state_timer = retreat_distance / maxf(retreat_speed, 0.001)


func _player_node() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


## The player's attack arc calls this.
func take_damage(amount: float, source: Node = null) -> void:
	if _health != null:
		_health.take_damage(amount, source)


func is_alive() -> bool:
	return _health == null or _health.is_alive()


## A hit cancels whatever this goblin was doing - INCLUDING a swipe in progress -
## and stuns it. A goblin that has just been hit cannot attack.
func _on_damaged(_amount: float, source: Node) -> void:
	var origin := global_position + Vector3(0.0, 0.0, 1.0)
	if source is Node3D:
		origin = (source as Node3D).global_position
	var away := global_position - origin
	away.y = 0.0
	_knock_dir = away.normalized() if away.length_squared() > 0.0001 else Vector3(0.0, 0.0, 1.0)
	_knock_timer = knockback_time
	_cancel_attack()
	_state = State.STUNNED
	_state_timer = stun_time


func _cancel_attack() -> void:
	_swing_time = 0.0
	_hit_done = false
	_set_swipe_visible(false)


func _on_died() -> void:
	queue_free()


func _stare_at_player() -> void:
	var player := _player_node()
	if player == null:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() <= watch_radius:
		face_dir(to_player)


# --- Swipe visual -----------------------------------------------------------
# A narrow blade parented to Visual, so it inherits the goblin's facing for
# free. It sweeps from one edge of the swipe arc to the other across the
# animation. The damage test uses the whole arc (_in_swipe_arc), not the blade.

func _build_swipe() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	_swipe = MeshInstance3D.new()
	_swipe.name = "Swipe"
	_swipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swipe.mesh = _build_blade_mesh()
	_swipe_mat = StandardMaterial3D.new()
	_swipe_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_swipe_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_swipe_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_swipe_mat.albedo_color = Color(SWIPE_COLOR.r, SWIPE_COLOR.g, SWIPE_COLOR.b, SWIPE_ALPHA)
	_swipe.material_override = _swipe_mat
	_swipe.position = Vector3(0.0, 0.45, 0.0)
	_swipe.visible = false
	visual.add_child(_swipe)


## Flat triangular fan on the XZ plane, apex at the goblin's feet, opening
## toward -Z (its forward).
func _build_blade_mesh() -> ArrayMesh:
	var segments := 8
	var half := deg_to_rad(blade_half_angle_deg)
	var reach := attack_range + swing_grace
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	norms.append(Vector3.UP)
	for i in segments + 1:
		var t := -half + (2.0 * half) * (float(i) / float(segments))
		verts.append(Vector3(sin(t) * reach, 0.0, -cos(t) * reach))
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


## Sweeps the blade across the swipe arc as the animation runs.
func _update_swipe() -> void:
	if _swipe == null:
		return
	var t := clampf(_swing_time / maxf(attack_duration, 0.001), 0.0, 1.0)
	_swipe.rotation.y = deg_to_rad(lerpf(swipe_half_angle_deg, -swipe_half_angle_deg, t))
	if _swipe_mat != null:
		# Brightest through the hit window, so the damaging part reads clearly.
		var in_window := _swing_time >= hit_window_start and _swing_time <= hit_window_end
		var alpha := SWIPE_ALPHA if in_window else SWIPE_ALPHA * 0.5
		_swipe_mat.albedo_color = Color(SWIPE_COLOR.r, SWIPE_COLOR.g, SWIPE_COLOR.b, alpha)


func _set_swipe_visible(value: bool) -> void:
	if _swipe != null:
		_swipe.visible = value
