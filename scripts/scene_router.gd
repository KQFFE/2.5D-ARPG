class_name SceneRouter
extends RefCounted
## The one hand-off between scenes that need to remember how the player got there.
##
## A doorway calls travel() with the scene to enter and a small payload: the
## direction the player was MOVING when they touched it, and - when the trip is
## a return - the position to arrive at. The scene being entered asks for the
## payload once, through consume(), and arranges itself around it.
##
## The other memory here is the doorway the player last entered a building
## through. Its outside spot is remembered so the matching exit can put the
## player back on the street rather than at the scene's default spawn point.
##
## Static state rather than an autoload: it only has to survive one scene change,
## nothing else in the game needs to own it, and this keeps project.godot
## untouched.

static var _payload: Dictionary = {}
static var _door_position := Vector3.ZERO
static var _door_outward := Vector3.ZERO
static var _has_door := false


## Changes to `scene_path`, carrying `payload` to whatever loads next.
static func travel(scene_path: String, payload: Dictionary) -> void:
	_payload = payload
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("SceneRouter: no SceneTree to change scene with.")
		return
	# Deferred, because a doorway is entered from a physics callback.
	tree.change_scene_to_file.call_deferred(scene_path)


## The payload handed over by the previous travel(), returned once. Empty when a
## scene was opened directly - the editor, or a fresh New Game.
static func consume() -> Dictionary:
	var carried: Dictionary = _payload
	_payload = {}
	return carried


## Remembers the doorway the player is entering a building through, and the
## outward direction of its walkable side. The building's exit uses it to place
## the player back outside this doorway.
static func remember_door(position: Vector3, outward: Vector3) -> void:
	_door_position = position
	_door_outward = outward.normalized()
	_has_door = true


## The remembered doorway as {position, outward}, or null when the player did not
## come in through a building door (a fresh start, or a direct scene open).
static func remembered_door() -> Variant:
	if not _has_door:
		return null
	return {"position": _door_position, "outward": _door_outward}
