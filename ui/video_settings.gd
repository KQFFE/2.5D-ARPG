extends Control
## The Video options page: a real page with real options, unlike the generic
## SettingsCategory placeholder that Gameplay and Audio still use.
##
## It holds one option so far - where the HP / mana display sits - because that is
## the only display choice the game has. The choice is stored by
## res://scripts/game_settings.gd in the active SAVE SLOT (see save_game.gd), so it
## belongs to that playthrough and comes back with it on Load, and it is pushed to
## any HUD that is already live, so changing it from the pause menu moves the orbs
## immediately instead of on the next scene load.
##
## Escape or Back emit back_requested, which SettingsMenu turns into "up one
## level", exactly as the generic category page does. This page handles Escape
## first because a child gets unhandled input before its parent, so the settings
## list never sees the event and cannot close the whole menu.

signal back_requested

@onready var _back_button: Button = $BackButton
@onready var _left_button: Button = $Center/Panel/Content/Positions/LeftButton
@onready var _right_button: Button = $Center/Panel/Content/Positions/RightButton
@onready var _top_button: Button = $Center/Panel/Content/Positions/TopButton
@onready var _bottom_button: Button = $Center/Panel/Content/Positions/BottomButton

## Placement key (the same strings GameSettings stores) -> its toggle button.
var _buttons: Dictionary = {}


func _ready() -> void:
	_buttons = {
		"left": _left_button,
		"right": _right_button,
		"top": _top_button,
		"bottom": _bottom_button,
	}
	for key in _buttons:
		(_buttons[key] as Button).pressed.connect(_choose.bind(key))
	_back_button.pressed.connect(_request_back)
	visible = false


func open() -> void:
	_sync()
	visible = true
	var current := _buttons.get(GameSettings.hud_position(), null) as Button
	if current != null:
		current.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()


func _request_back() -> void:
	back_requested.emit()


## Stores the choice, then tells every live HUD to re-place itself. Found through
## the "hud" group rather than a hard path, because there is one display per
## gameplay scene and none at all in the menus.
func _choose(placement: String) -> void:
	GameSettings.set_hud_position(placement)
	_sync()
	for node in get_tree().get_nodes_in_group("hud"):
		if node.has_method("apply_position"):
			node.call("apply_position")


## Pushes the stored value onto the toggle buttons, so the pressed one always
## shows what the game is actually using - including on the first open after a
## restart. Setting button_pressed emits toggled, not pressed, so this cannot
## loop back into _choose.
func _sync() -> void:
	var placement := GameSettings.hud_position()
	for key in _buttons:
		(_buttons[key] as Button).button_pressed = (key == placement)
