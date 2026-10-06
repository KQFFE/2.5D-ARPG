extends StaticBody3D
## A reusable checkpoint marker. Put this on a res://structures/lamppost.tscn
## instance and give it a unique `checkpoint_id`.
##
## When the player walks inside the "CheckpointArea" child (a 4 m sphere by
## default) this becomes the active respawn point: it tells the "checkpoint_manager"
## in the scene to record it and save, so dying puts the player back here.
##
## One scene, many instances: everything is exported, nothing is hard-coded to a
## particular post. Drop another lamp post anywhere and give it a new id - the
## most recently reached post is the one the player wakes up at.

## Unique name for this checkpoint, e.g. "field_gate". Shown in the save print.
@export var checkpoint_id := "field_gate"
## Where the player is put back, relative to this post's origin. The default
## drops them just south (+Z) of the post so they are not standing inside it.
@export var respawn_offset := Vector3(0.0, 0.0, 1.6)

@onready var _area: Area3D = get_node_or_null("CheckpointArea")


func _ready() -> void:
	add_to_group("checkpoint")
	if _area == null:
		push_warning("Checkpoint '%s' has no CheckpointArea child." % checkpoint_id)
		return
	_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	var manager := get_tree().get_first_node_in_group("checkpoint_manager")
	if manager == null:
		push_warning("Checkpoint '%s': no checkpoint_manager in this scene." % checkpoint_id)
		return
	# Nothing to do if this post is already the active respawn point, so walking
	# back and forth across the area does not re-save every time.
	if String(manager.current_id()) == checkpoint_id:
		return
	if manager.has_method("activate"):
		manager.activate(checkpoint_id, global_position + respawn_offset)


## Where this post would put the player back, without activating it.
func respawn_position() -> Vector3:
	return global_position + respawn_offset
