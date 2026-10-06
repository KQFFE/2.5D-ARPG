class_name Health
extends Node
## Reusable health component, shared by the player and every enemy.
##
## One implementation instead of one per entity: add this as a "Health" child
## node, set max_health in the Inspector, and connect to `damaged` / `died`.
## Nothing in this file knows about input, camera or movement.
##
## The owning body is responsible for what happens on death (the goblin frees
## itself; the player respawns at its last checkpoint).
##
## Note: take_damage() ignores hits once health is at zero, so a dead body stops
## taking further damage until revive() is called.

signal damaged(amount: float, source: Node)
signal died

@export var max_health := 100.0
## When true, take_damage() is ignored. Useful for spawn protection / cutscenes.
@export var invulnerable := false

var current: float


func _ready() -> void:
	current = max_health


func is_alive() -> bool:
	return current > 0.0


## Returns true when the hit actually landed (it was not ignored and the target
## was still alive).
func take_damage(amount: float, source: Node = null) -> bool:
	if invulnerable or amount <= 0.0 or not is_alive():
		return false
	current = maxf(0.0, current - amount)
	damaged.emit(amount, source)
	if current <= 0.0:
		died.emit()
	return true


## Puts the target back to full health. Used on respawn after dying - without it
## a body that reached zero could never be hurt again.
func revive() -> void:
	current = max_health


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	current = minf(max_health, current + amount)


## Fraction of max health remaining, 0..1 (handy for a future health bar).
func ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return current / max_health
