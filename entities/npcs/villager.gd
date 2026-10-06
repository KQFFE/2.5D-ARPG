extends "res://entities/npcs/npc.gd"
## The fetch-quest giver, ported from the 2D prototype (res://scripts/
## quest_npc.gd). She asks for a moonleaf herb from the fields past the gate and
## thanks the player once the pickup has set the player's has_herb meta.
##
## Everything else (drift, proximity, interact prompt) comes from npc.gd, and
## her body/InteractionArea come from villager.tscn, so this file only owns the
## words and the has_herb check.

const ASK_LINES := [
	"Oh... a traveler, and armed too. Thank the stars.",
	"Monsters have been prowling the fields past the gate.",
	"Could you fetch me a moonleaf herb? It grows just beyond the fence.",
	"It would mean so much. My little ones are frightened.",
]

const THANKS_LINES := [
	"You found it! Bless you, stranger.",
	"The village sleeps easier tonight because of you.",
	"Come back any time - our gate is always open to you.",
]


func get_lines() -> Array:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var done := player != null and bool(player.get_meta(&"has_herb", false))
	return THANKS_LINES if done else ASK_LINES
