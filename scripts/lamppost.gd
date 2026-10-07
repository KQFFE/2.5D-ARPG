extends "res://scripts/checkpoint.gd"
## Lantern look for a checkpoint lamp post. It narrows the marker script rather
## than replacing it: res://structures/lamppost.tscn carries only this one
## script, and everything generic (walk-in detection, id, respawn position,
## manager lookup) still comes from res://scripts/checkpoint.gd.
##
## Only the ACTIVE checkpoint burns. On _ready the post goes dark and listens
## for the manager's `checkpoint_activated`, so exactly one lamp in the village
## is lit - the one the player most recently saved at - and every other post is
## dark.
##
## Tune the look from the Inspector (lit_color, lit_emission, dark_factor).

## Emission colour of the lantern glass while this post is active.
@export var lit_color := Color(1.0, 0.72, 0.34, 1.0)
## Emission strength while lit. 0 turns the glow off entirely on a dark post.
@export var lit_emission := 1.6
## How dark the glass goes when the post is NOT the active one. 0.22 keeps a
## faint tint so the lantern still reads as glass rather than a flat black box.
@export var dark_factor := 0.22

var _lantern: MeshInstance3D = null
var _glow: OmniLight3D = null
var _glass: StandardMaterial3D = null
var _lit := false


func _ready() -> void:
	super._ready()
	_lantern = get_node_or_null("Lantern") as MeshInstance3D
	_glow = get_node_or_null("Glow") as OmniLight3D
	if _lantern == null or _glow == null:
		push_warning("LampPost: needs both a 'Lantern' MeshInstance3D and a 'Glow' OmniLight3D.")


## Lit look. checkpoint.gd calls this on _ready (dark) and whenever the manager
## announces the active checkpoint changed.
func set_lit(value: bool) -> void:
	_lit = value
	if _glow != null:
		_glow.visible = value
	if _lantern == null:
		return
	if _glass == null:
		var source := _lantern.get_active_material(0)
		if source is StandardMaterial3D:
			_glass = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
			_lantern.material_override = _glass
	if _glass == null:
		return
	_glass.emission_enabled = true
	_glass.emission = lit_color
	_glass.emission_energy_multiplier = lit_emission if value else 0.0
	_glass.albedo_color = lit_color if value else Color(lit_color.r * dark_factor, lit_color.g * dark_factor, lit_color.b * dark_factor, 1.0)


func is_lit() -> bool:
	return _lit
