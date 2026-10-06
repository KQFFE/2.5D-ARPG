extends Area3D
## The quest item, ported from the 2D prototype (res://scripts/herb_pickup.gd).
## Walking into it flags the player's has_herb meta - which villager.gd reads -
## and removes the pickup.
##
## The quest flag deliberately stays on the player, not in this node, so the
## dialogue loop survives the pickup being freed.

@export var herb_meta := "has_herb"
@export var spin_speed := 1.6

@onready var _visual: Node3D = get_node_or_null("Visual") as Node3D


func _ready() -> void:
	add_to_group("herb")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _visual != null:
		_visual.rotate_y(spin_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.set_meta(StringName(herb_meta), true)
		queue_free()
