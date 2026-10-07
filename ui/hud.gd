extends CanvasLayer
## The player's health and mana, drawn as two liquid-filled orbs (res://ui/orb.gd).
##
## Instanced in every gameplay scene - the village and both interiors - because a
## scene change replaces the whole tree, so the display has to come along with
## whichever scene is being played. It is a CanvasLayer on layer 2: above the
## world, below the pause menu (5) and the settings overlay (10).
##
## WHERE the orbs sit is a player option: GameSettings.hud_position() returns
## "bottom" (the default), "top", "left" or "right", picked in Settings -> Video.
## Bottom and top place the two orbs side by side; left and right stack them with
## HP above mana. The rect is computed here from one orb size rather than left to
## container growth, so every placement is the same simple arithmetic.
##
## The display hides itself while a dialogue is up. The dialogue box owns the
## bottom of the screen, and an orb row sitting behind it is worse than no orbs.
##
## HP comes from the player's shared Health component and mana from its Mana
## component. Both are POLLED - one comparison per orb per frame, and the orb
## only redraws when its ratio moves - which keeps this scene out of those two
## shared components entirely.

## Group the settings page uses to find live displays and move them.
const GROUP := "hud"
## Distance from the screen edge, pixels.
const MARGIN := 24.0
## Side of one orb, pixels. Square, so it is a circle.
const ORB_SIZE := 64.0
## Gap between the two orbs, pixels.
const GAP := 10.0
## The orb and mana scripts are referenced through explicit preloads rather than
## by the global class names their files declare. A brand-new `class_name` is not
## in the engine's class cache until the filesystem has been rescanned, and hud.gd
## failing to parse over one unresolved type name takes the whole display with it.
const OrbControl := preload("res://ui/orb.gd")
const ManaComponent := preload("res://scripts/mana.gd")

@onready var _orbs: GridContainer = $Orbs
@onready var _health_orb: OrbControl = $Orbs/HealthOrb
@onready var _mana_orb: OrbControl = $Orbs/ManaOrb

var _health: Health = null
var _mana: ManaComponent = null


func _ready() -> void:
	add_to_group(GROUP)
	for orb in [_health_orb, _mana_orb]:
		orb.custom_minimum_size = Vector2(ORB_SIZE, ORB_SIZE)
	apply_position()
	_bind_player.call_deferred()
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


## Re-reads the player option and places the orbs to match. Called on entry, and
## again by the Video settings page whenever the option changes, so picking a new
## spot from the pause menu moves the orbs without a scene reload.
func apply_position() -> void:
	var placement := GameSettings.hud_position()
	var side_by_side := placement == "top" or placement == "bottom"
	_orbs.columns = 2 if side_by_side else 1
	var width := (ORB_SIZE * 2.0 + GAP) if side_by_side else ORB_SIZE
	var height := ORB_SIZE if side_by_side else (ORB_SIZE * 2.0 + GAP)
	_orbs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_orbs.grow_vertical = Control.GROW_DIRECTION_BOTH
	match placement:
		"top":
			_anchor_at(0.5, 0.0, -width * 0.5, MARGIN, width, height)
		"left":
			_anchor_at(0.0, 0.5, MARGIN, -height * 0.5, width, height)
		"right":
			_anchor_at(1.0, 0.5, -(width + MARGIN), -height * 0.5, width, height)
		_:
			# "bottom", and anything unexpected, which normalize_* already turned
			# into the default.
			_anchor_at(0.5, 1.0, -width * 0.5, -(height + MARGIN), width, height)


## Pins the orb row so both its anchors coincide at (anchor_x, anchor_y) of the
## viewport and its rect is `width` x `height` at that offset from there. Setting
## the rect outright beats relying on container growth: the placement is then the
## same three lines whatever the option.
func _anchor_at(anchor_x: float, anchor_y: float, offset_x: float, offset_y: float, width: float, height: float) -> void:
	_orbs.anchor_left = anchor_x
	_orbs.anchor_right = anchor_x
	_orbs.anchor_top = anchor_y
	_orbs.anchor_bottom = anchor_y
	_orbs.offset_left = offset_x
	_orbs.offset_right = offset_x + width
	_orbs.offset_top = offset_y
	_orbs.offset_bottom = offset_y + height


func _on_dialogue_started() -> void:
	visible = false


func _on_dialogue_ended() -> void:
	visible = true


func _process(_delta: float) -> void:
	if _health == null or _mana == null:
		_bind_player()
	if _health != null:
		_health_orb.set_values(_health.current, _health.max_health)
	if _mana != null:
		_mana_orb.set_values(_mana.current, _mana.max_mana)


## Finds the player's two stat components. Called once on entry, and again from
## _process only while one of them is still missing - so a scene whose player
## arrives a frame late still ends up connected, at no cost once it has.
func _bind_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if _health == null:
		_health = player.get_node_or_null("Health") as Health
	if _mana == null:
		_mana = player.get_node_or_null("Mana") as Mana
