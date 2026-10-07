class_name Mana
extends Node
## Reusable mana pool, the sibling of res://scripts/health.gd and deliberately
## the same shape: add this as a "Mana" child node, set max_mana in the
## Inspector, read `current`.
##
## Nothing spends mana yet - no spell or ability has a cost - so the orb it feeds
## (res://ui/orb.gd, through res://ui/hud.tscn) simply sits full. The pool exists
## so the display has something real to show and so the first ability that needs
## it only has to call spend().
##
## Note: spend() refuses a cost the pool cannot cover and returns false, so a
## caller can never push mana negative.

@export var max_mana := 100.0

var current: float


func _ready() -> void:
	current = max_mana


func ratio() -> float:
	if max_mana <= 0.0:
		return 0.0
	return current / max_mana


func is_empty() -> bool:
	return current <= 0.0


## Pays a cost. Returns false - and changes nothing - when the pool is short, so
## the caller can use the return value to refuse the ability.
func spend(amount: float) -> bool:
	if amount <= 0.0 or amount > current:
		return false
	current -= amount
	return true


func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	current = minf(max_mana, current + amount)


## Back to full, the mana equivalent of Health.revive().
func fill() -> void:
	current = max_mana
