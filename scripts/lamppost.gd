extends "res://scripts/checkpoint.gd"
## The lamp look for a checkpoint lamp post - lit only while THIS post is the
## active save point.
##
## All the saving behaviour is inherited from res://scripts/checkpoint.gd; this
## script adds nothing but the lantern. The base post calls set_lit(true) when the
## player reaches it, and set_lit(false) when another post takes over (the manager
## announces every change, including the point it restores from the save file at
## startup), so exactly one lamp in the village burns and it is always the one the
## player would respawn at.
##
## Nothing needs wiring on an instance: the "Lantern" MeshInstance3D and the
## "Glow" OmniLight3D child are found by name, and the lantern's own material is
## duplicated before it is touched so the three posts never share one material.
##
## Exports:
##   lit_color      colour the lantern glass glows with
##   lit_emission   emission strength while lit
##   dark_factor    how far the glass is darkened while unlit

## Colour the lantern glass glows with when the post is lit.
@export var lit_color := Color(1.0, 0.72, 0.34, 1.0)
## Emission strength while lit.
@export var lit_emission := 1.6
## How far the glass is darkened while unlit (1.0 = unchanged, 0.0 = black).
@export var dark_factor := 0.22

var _glass: StandardMaterial3D = null
var _glow: OmniLight3D = null
var _lit_albedo := Color(1.0, 1.0, 1.0, 1.0)
var _dark_albedo := Color(0.0, 0.0, 0.0, 1.0)
var _lit := false


## Cache the lantern pieces BEFORE the base class runs, because the base calls
## set_lit(false) as its first act.
func _ready() -> void:
	var lantern := get_node_or_null("Lantern") as MeshInstance3D
	if lantern != null:
		var source := lantern.material_override as StandardMaterial3D
		if source == null:
			source = lantern.get_active_material(0) as StandardMaterial3D
		if source != null:
			_glass = source.duplicate() as StandardMaterial3D
			_lit_albedo = _glass.albedo_color
			_dark_albedo = Color(
				_lit_albedo.r * dark_factor,
				_lit_albedo.g * dark_factor,
				_lit_albedo.b * dark_factor,
				_lit_albedo.a
			)
			lantern.material_override = _glass
	_glow = get_node_or_null("Glow") as OmniLight3D
	super._ready()


## Lit: the glass glows and the OmniLight3D shines. Unlit: dark glass, no light.
func set_lit(value: bool) -> void:
	_lit = value
	if _glass != null:
		if value:
			_glass.albedo_color = _lit_albedo
			_glass.emission_enabled = true
			_glass.emission = lit_color
			_glass.emission_energy_multiplier = lit_emission
		else:
			_glass.albedo_color = _dark_albedo
			_glass.emission_enabled = false
	if _glow != null:
		_glow.visible = value


func is_lit() -> bool:
	return _lit
