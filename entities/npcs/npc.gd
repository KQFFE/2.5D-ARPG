extends "res://entities/npcs/wander_npc.gd"
## Base village NPC for the 3D village. Drifts around its spawn point
## (wander_npc.gd), freezes during dialogue, and starts a conversation when the
## player is inside its InteractionArea and presses interact.
##
## One npc.tscn covers every villager: variants are made by overriding the
## exported values per instance (speaker_name, body_color, body_scale, lines) or
## by overriding get_lines() in a small subclass - see villager.gd, the
## fetch-quest giver.

@export var speaker_name := "Villager"
@export var body_color := Color(0.48, 0.58, 0.68, 1.0)
@export var body_scale := 1.0
@export var lines: PackedStringArray = PackedStringArray()
@export var face_player_when_talking := true

var _player_near := false

@onready var _visual: Node3D = get_node_or_null("Visual") as Node3D
@onready var _body: MeshInstance3D = get_node_or_null("Visual/Body") as MeshInstance3D
@onready var _interaction: Area3D = get_node_or_null("InteractionArea") as Area3D


func _ready() -> void:
	super._ready()
	if _visual != null:
		_visual.scale = Vector3.ONE * body_scale
	if _body != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color
		mat.roughness = 0.92
		_body.material_override = mat
	if _interaction != null:
		_interaction.body_entered.connect(_on_body_entered)
		_interaction.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = false


func _unhandled_input(event: InputEvent) -> void:
	if not _player_near or DialogueManager.active:
		return
	if event.is_action_pressed("interact"):
		interact()
		get_viewport().set_input_as_handled()


func interact() -> void:
	var spoken := get_lines()
	if spoken.is_empty():
		return
	if face_player_when_talking:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player != null:
			face_dir(player.global_position - global_position)
	DialogueManager.start(spoken, self)


## Override in a subclass to change what this NPC says (see villager.gd).
func get_lines() -> Array:
	return Array(lines)
