class_name SceneRouter
extends RefCounted
## The one hand-off between scenes that need to remember where the player goes.
##
## A door calls travel() with the scene to enter and the world position the
## player should stand at in it. The scene being entered asks for that position
## once, through consume_spawn(), and places the player itself.
##
## Static state rather than an autoload: the value only has to survive one scene
## change, nothing else in the game needs to own it, and this keeps
## project.godot untouched.

static var _pending_spawn: Variant = null


## Changes to `scene_path`, with the player placed at `spawn_position` there.
static func travel(scene_path: String, spawn_position: Vector3) -> void:
	_pending_spawn = spawn_position
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("SceneRouter: no SceneTree to change scene with.")
		return
	# Deferred, because a doorway is entered from a physics callback.
	tree.change_scene_to_file.call_deferred(scene_path)


## The position handed over by travel(), returned once. Null when no scene
## handed one over - for example when a scene is opened directly.
static func consume_spawn() -> Variant:
	var value: Variant = _pending_spawn
	_pending_spawn = null
	return value
