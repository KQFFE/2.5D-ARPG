class_name Orb
extends Control
## One liquid-filled glass gauge: a circle of glass with the fill colour standing
## inside it, so the height of the liquid IS the value and an empty orb reads as
## empty at a glance. Drawn in _draw() - no texture and no shader - so it stays
## crisp at any size and any window.
##
## The liquid is a real chord of the circle, not a rectangle clipped to it: the
## boundary of the circle below the fill line, closed by a straight surface
## across the top. The rim is drawn over the polygon edge, which is what hides
## the fact that the fill has no anti-aliasing of its own.
##
## Feed it with set_values(current, maximum). It redraws only when the ratio
## actually changes, so a HUD may call it every frame and pay nothing.

@export_group("Look")
## The liquid. Red for health, blue for mana - set per instance.
@export var fill_color := Color(0.78, 0.17, 0.19, 1.0)
## The unlit inside of the orb, visible wherever the liquid is not.
@export var glass_color := Color(0.07, 0.08, 0.10, 0.92)
@export var rim_color := Color(0.74, 0.70, 0.62, 1.0)
@export var sheen_color := Color(1.0, 1.0, 1.0, 0.14)
@export var rim_width := 3.0
## How far the liquid is pushed towards white for a moment when the value DROPS,
## so a hit is visible even in a small HUD orb.
@export var flash_strength := 0.55
## How long that flash lasts, seconds.
@export var flash_time := 0.35

## Points around the circle edge used for the liquid. Enough that the flat facets
## are under the rim's thickness.
const SEGMENTS := 64

var _ratio := 1.0
var _has_value := false
var _flash := 0.0


func _ready() -> void:
	resized.connect(queue_redraw)
	set_process(false)


## current / maximum, clamped to 0..1. Redraws only when the ratio changes.
func set_values(current: float, maximum: float) -> void:
	var top := maxf(maximum, 0.0001)
	var ratio := clampf(current / top, 0.0, 1.0)
	if _has_value and is_equal_approx(ratio, _ratio):
		return
	# A drop flashes; a rise just moves. Only a fall needs pointing out.
	if _has_value and ratio < _ratio - 0.0005:
		_flash = flash_time
		set_process(true)
	_ratio = ratio
	_has_value = true
	queue_redraw()


func value_ratio() -> float:
	return _ratio


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if _flash <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - rim_width * 0.5
	if radius <= 1.0:
		return
	var centre := size * 0.5
	draw_circle(centre, radius, glass_color)
	if _ratio >= 0.999:
		# A full orb is a plain disc; the polygon would come out degenerate here.
		draw_circle(centre, radius, _tinted_fill())
	elif _ratio > 0.001:
		var points := _liquid_polygon(centre, radius, _ratio)
		if points.size() >= 3:
			draw_colored_polygon(points, _tinted_fill())
	# One soft highlight up and to the left, so the disc reads as glass.
	draw_circle(centre + Vector2(-radius * 0.34, -radius * 0.36), radius * 0.2, sheen_color)
	draw_arc(centre, radius, 0.0, TAU, SEGMENTS, rim_color, rim_width, true)


func _tinted_fill() -> Color:
	if _flash <= 0.0:
		return fill_color
	var t := clampf(_flash / maxf(flash_time, 0.001), 0.0, 1.0) * flash_strength
	return fill_color.lerp(Color(1.0, 1.0, 1.0, fill_color.a), t)


## The part of the circle below the fill line: the edge swept from the fill line
## round the bottom and back up, which closes as a straight chord across the top.
## The region is convex, so it always triangulates cleanly.
func _liquid_polygon(centre: Vector2, radius: float, ratio: float) -> PackedVector2Array:
	var surface_y := centre.y + radius - 2.0 * radius * ratio
	var dy := clampf((surface_y - centre.y) / radius, -1.0, 1.0)
	var from := asin(dy)
	var to := PI - from
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var angle := lerpf(from, to, float(i) / float(SEGMENTS))
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
