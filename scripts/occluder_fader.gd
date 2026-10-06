extends Node3D

## Drives the per-structure occluder fade for the village buildings
## (res://shaders/occluder_fade.gdshader). A structure may only fade when BOTH hold:
## (1) the player is genuinely BEHIND it - their depth along the camera's horizontal
## view direction is past that structure's far footprint edge by more than
## `behind_margin`, which is the per-structure `fade_active` gate written below; and
## (2) the shader's screen-space circle around the player's projected feet reaches the
## fragment and that fragment is nearer the camera than the player. Standing beside a
## house therefore leaves its gate at 0 and its camera-facing wall fully opaque.
##
## Structures shorter than the player are never registered: something the player can
## see over cannot hide them.
##
## Cost: player, camera, structures, their world AABBs and their duplicated material
## lists are resolved once in _ready. While neither the player nor the camera moved,
## _process returns immediately; on a moved frame it unprojects the feet once, runs
## four XZ dot products per structure and writes a gate only when that gate flipped.

## The node whose feet position drives the fade. Usually the Player.
@export var player_path: NodePath

## Structures that may fade while they hide the player: the five cottage instances and
## the gate in res://scenes/village.tscn. Kept as NodePaths because Godot's text scene
## parser refuses a NodePath element inside an Array of Objects, so a typed
## Array[Node3D] loads back empty. Resolved once in _ready.
@export var fade_objects: Array[NodePath] = []

## Radius of the screen-space reveal circle, as a fraction of viewport height.
@export var screen_radius := 0.18

## How opaque a fully revealed structure becomes (0 = invisible, 1 = solid).
@export var min_alpha := 0.25

## Softness of the reveal circle's edge, as a fraction of `screen_radius`.
@export var softness := 0.35

## Vertical offset applied to the player's feet when projecting the circle centre.
@export var center_offset_y := 0.0

## How far past a structure's far edge (along the camera's horizontal view direction,
## in metres) the player must be before that structure is allowed to fade.
@export var behind_margin := 0.35

const MOVE_EPSILON_SQ := 0.0001  # 0.01 m; below this nothing at all is recomputed
const DEFAULT_PLAYER_HEIGHT := 1.8  # used when the player has no measurable mesh
const FALLBACK_VIEW_DIR := Vector2(0.0, -1.0)  # camera aimed straight down

const P_ACTIVE := "fade_active"
const P_CENTER := "fade_center"
const P_SCREEN_CENTER := "fade_screen_center"
const P_SCREEN_RADIUS := "fade_screen_radius"
const P_SCREEN_ASPECT := "fade_screen_aspect"
const P_MIN_ALPHA := "fade_min_alpha"
const P_SOFTNESS := "fade_softness"

var _player: Node3D = null
var _camera: Camera3D = null
var _player_height := DEFAULT_PLAYER_HEIGHT
## Per registered structure, in registration order: owned materials, XZ footprint corners, gate.
var _mat_lists: Array[Array] = []
var _footprints: Array[PackedVector2Array] = []
var _active := PackedByteArray()
var _last_player_pos := Vector3(INF, INF, INF)
var _last_camera_xform := Transform3D()


func _ready() -> void:
	_resolve_player()
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		push_warning("OccluderFader: no active Camera3D in this viewport, the fade stays off.")
	_player_height = _measure_player_height()
	_register_structures()


func _process(_delta: float) -> void:
	if _player == null or _camera == null or _mat_lists.is_empty():
		return
	var feet := _player.global_position
	var camera_xform := _camera.global_transform
	# No projection, no dot product and no uniform write while nothing moved.
	if feet.distance_squared_to(_last_player_pos) < MOVE_EPSILON_SQ and camera_xform == _last_camera_xform:
		return
	_last_player_pos = feet
	_last_camera_xform = camera_xform

	var center := Vector3(feet.x, feet.y + center_offset_y, feet.z)
	var view_dir := _view_dir_2d(camera_xform)
	var player_depth := Vector2(feet.x, feet.z).dot(view_dir)

	# One unprojection per frame: the screen-space circle centre.
	var uv := Vector2(0.5, 0.5)
	var aspect := 1.777
	var vp := get_viewport().get_visible_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		var screen := _camera.unproject_position(center)
		uv = Vector2(screen.x / vp.x, screen.y / vp.y)
		aspect = vp.x / vp.y

	for i in _mat_lists.size():
		var far_depth := -INF  # far footprint edge along the camera's view direction
		for corner in _footprints[i]:
			far_depth = maxf(far_depth, corner.dot(view_dir))
		var active := 1 if player_depth > far_depth + behind_margin else 0
		var changed := active != _active[i]
		_active[i] = active
		for material in _mat_lists[i]:
			if changed:
				material.set_shader_parameter(P_ACTIVE, float(active))
			material.set_shader_parameter(P_CENTER, center)
			material.set_shader_parameter(P_SCREEN_CENTER, uv)
			material.set_shader_parameter(P_SCREEN_ASPECT, aspect)


func _resolve_player() -> void:
	if player_path.is_empty():
		push_warning("OccluderFader: player_path is empty, the fade stays off.")
		return
	var node := get_node_or_null(player_path)
	if node is Node3D:
		_player = node as Node3D
	else:
		push_warning("OccluderFader: player_path '%s' is not a Node3D." % player_path)


## Horizontal (XZ) forward of the camera, normalized.
func _view_dir_2d(camera_xform: Transform3D) -> Vector2:
	var flat := Vector2(-camera_xform.basis.z.x, -camera_xform.basis.z.z)
	return flat.normalized() if flat.length_squared() > 0.000001 else FALLBACK_VIEW_DIR


func _measure_player_height() -> float:
	var box: AABB = _world_aabb(_player) if _player != null else AABB()
	return box.size.y if box.size.y > 0.01 else DEFAULT_PLAYER_HEIGHT


func _register_structures() -> void:
	for path in fade_objects:
		var node := get_node_or_null(path) as Node3D
		if node == null:
			push_warning("OccluderFader: fade_objects entry '%s' is not a Node3D here." % path)
			continue
		var box := _world_aabb(node)
		if box.size.y <= 0.01:
			print("OccluderFader: '%s' has no mesh geometry, it will not fade." % node.name)
			continue
		# Automatic taller-than-the-player rule: what the player can see over cannot hide them.
		if box.size.y < _player_height:
			print("OccluderFader: '%s' is %.2f m tall, shorter than the %.2f m player - not fading it." % [node.name, box.size.y, _player_height])
			continue
		var materials := _duplicate_shader_materials(node)
		if materials.is_empty():
			print("OccluderFader: '%s' has no ShaderMaterial to fade, skipping it." % node.name)
			continue
		for material in materials:
			material.set_shader_parameter(P_ACTIVE, 0.0)
			material.set_shader_parameter(P_MIN_ALPHA, min_alpha)
			material.set_shader_parameter(P_SOFTNESS, softness)
			material.set_shader_parameter(P_SCREEN_RADIUS, screen_radius)
		print("OccluderFader: registered '%s' (%.2f m tall, %d material(s))." % [node.name, box.size.y, materials.size()])
		_mat_lists.append(materials)
		_footprints.append(_footprint_corners(box))
		_active.append(0)


## Gives each MeshInstance3D under `root` its own copy of its ShaderMaterial: the
## structure materials are shared between all five cottages, so without this copy one
## cottage's fade gate would fade the others too.
func _duplicate_shader_materials(root: Node3D) -> Array[ShaderMaterial]:
	var owned: Array[ShaderMaterial] = []
	var copies := {}
	for mesh_instance in _mesh_instances(root):
		var material := mesh_instance.material_override
		if not (material is ShaderMaterial):
			continue
		var source := material as ShaderMaterial
		var key := source.get_instance_id()
		var copy: ShaderMaterial
		if copies.has(key):
			copy = copies[key]
		else:
			copy = source.duplicate() as ShaderMaterial
			copies[key] = copy
			owned.append(copy)
		mesh_instance.material_override = copy
	return owned


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			stack.append(child)
			if child is MeshInstance3D:
				found.append(child as MeshInstance3D)
	return found


## World-space AABB of every MeshInstance3D under `root`, empty when there is none.
func _world_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var has_box := false
	for mesh_instance in _mesh_instances(root):
		var mesh_box := mesh_instance.get_aabb()
		if mesh_box.size == Vector3.ZERO:
			continue
		var world_box := mesh_instance.global_transform * mesh_box
		box = box.merge(world_box) if has_box else world_box
		has_box = true
	return box


func _footprint_corners(box: AABB) -> PackedVector2Array:
	var min_x := box.position.x
	var min_z := box.position.z
	var max_x := min_x + box.size.x
	var max_z := min_z + box.size.z
	return PackedVector2Array([Vector2(min_x, min_z), Vector2(max_x, min_z), Vector2(min_x, max_z), Vector2(max_x, max_z)])
