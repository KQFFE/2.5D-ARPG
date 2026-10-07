extends Node3D
## Holds the active respawn checkpoint for the village and keeps it saved.
##
## Lives in res://scenes/village.tscn as the "Checkpoints" node, so the lamp
## posts find it through the "checkpoint_manager" group and the player asks it
## where to wake up after dying. Nothing else needs a reference to it.
##
## Persistence: the active checkpoint id and its respawn position are written to
## user://checkpoint.cfg, so the recorded point survives a restart.
##
## One manager per scene. A second scene that wants checkpoints just instances
## its own, or reuses res://structures/lamppost.tscn and this node.
##
## It also announces checkpoint_activated for every change of the active point,
## which is how exactly one lamp post stays lit.

const SAVE_PATH := "user://checkpoint.cfg"
const SECTION := "checkpoint"

## Emitted whenever the active checkpoint changes, so a lamp post can light up
## only while it is the one. It also fires at startup for the point restored from
## user://checkpoint.cfg - the posts are already listening by then, because a
## child's _ready runs before its parent's.
signal checkpoint_activated(id: String)

var _id := ""
var _position := Vector3.ZERO
var _has_checkpoint := false


func _ready() -> void:
	add_to_group("checkpoint_manager")
	_load()
	# A post restored from the save file lights up on a fresh start through this,
	# exactly as it would if the player had just walked into it.
	if _has_checkpoint:
		checkpoint_activated.emit(_id)


## Called by a checkpoint post when the player walks into it. Records the point
## and saves immediately.
func activate(id: String, position: Vector3) -> void:
	_id = id
	_position = position
	_has_checkpoint = true
	_save()
	checkpoint_activated.emit(_id)
	print("Checkpoint saved: '%s' at %s" % [_id, str(_position)])


## Id of the active checkpoint, empty when none has been reached yet.
func current_id() -> String:
	return _id


func has_checkpoint() -> bool:
	return _has_checkpoint


## Where the player should wake up after dying. Returns `fallback` (the spot the
## village placed the player in) until a checkpoint has actually been reached.
func respawn_position(fallback: Vector3) -> Vector3:
	return _position if _has_checkpoint else fallback


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "id", _id)
	config.set_value(SECTION, "position", _position)
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("Checkpoints: could not save to %s (error %d)" % [SAVE_PATH, err])


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var id := String(config.get_value(SECTION, "id", ""))
	if id.is_empty():
		return
	_id = id
	_position = config.get_value(SECTION, "position", Vector3.ZERO)
	_has_checkpoint = true
