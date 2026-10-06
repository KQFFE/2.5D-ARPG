extends "res://entities/npcs/wander_npc.gd"
## Pen sheep. All the behaviour is the shared drift in wander_npc.gd - speed and
## wander_radius are simply tuned small in sheep.tscn (and again per instance in
## village.tscn) so the flock grazes inside the pen instead of walking through
## the rails. The dialogue freeze comes along for free, so the sheep do not
## shuffle around while the player is talking.

func _ready() -> void:
	super._ready()
	add_to_group("sheep")
