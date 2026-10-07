extends Node
## InputRemap - the autoload that owns every rebindable action in the game.
##
## Project rule: gameplay asks for actions by name only
## (Input.is_action_pressed("dash")) and never reads raw keycodes or mouse /
## joypad button numbers, so rebinding stays purely an InputMap concern.
##
## At startup _ready() cleans the project defaults in project.godot so one input
## never drives two actions. In-game rebinds are NOT restored yet: the game
## always comes up on the defaults, and save_bindings() / load_bindings() are ready
## for the later "apply" button that will persist and restore them.

const CONFIG_PATH := "user://input_bindings.cfg"
const CONFIG_SECTION := "bindings"

## Every rebindable action, in the order the settings screen lists them.
const ACTIONS := [
	{"action": "move_up", "label": "Move Up"},
	{"action": "move_down", "label": "Move Down"},
	{"action": "move_left", "label": "Move Left"},
	{"action": "move_right", "label": "Move Right"},
	{"action": "jump", "label": "Jump"},
	{"action": "run", "label": "Run"},
	{"action": "dash", "label": "Dash"},
	{"action": "attack", "label": "Attack"},
	{"action": "parry", "label": "Parry"},
	{"action": "interact", "label": "Interact"},
	{"action": "settings", "label": "Settings"},
]

const JOY_BUTTON_LABELS := {
	JOY_BUTTON_A: "Joypad A",
	JOY_BUTTON_B: "Joypad B",
	JOY_BUTTON_X: "Joypad X",
	JOY_BUTTON_Y: "Joypad Y",
	JOY_BUTTON_BACK: "Joypad Back",
	JOY_BUTTON_START: "Joypad Start",
	JOY_BUTTON_LEFT_SHOULDER: "Joypad LB",
	JOY_BUTTON_RIGHT_SHOULDER: "Joypad RB",
}


func _ready() -> void:
	# Bindings always start from the project defaults in project.godot. In-game
	# rebinds are deliberately NOT restored on startup yet: a saved-bindings
	# "apply" flow is coming later, and load_bindings() is already there for it.
	_sanitize_defaults()


## The action list the settings screen builds its rows from, in display order.
func action_entries() -> Array:
	return ACTIONS.duplicate()


## True when `action` is one of the rebindable game actions.
func is_game_action(action: String) -> bool:
	for entry in ACTIONS:
		if String(entry["action"]) == action:
			return true
	return false


func action_label(action: String) -> String:
	for entry in ACTIONS:
		if String(entry["action"]) == action:
			return String(entry["label"])
	return action


## Human-readable summary of everything currently bound to `action`.
func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "--"
	var parts := PackedStringArray()
	for event in InputMap.action_get_events(action):
		parts.append(event_to_text(event))
	if parts.is_empty():
		return "-- unbound --"
	return " / ".join(parts)


func event_to_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		var index: int = (event as InputEventMouseButton).button_index
		var names := {MOUSE_BUTTON_LEFT: "Mouse Left", MOUSE_BUTTON_RIGHT: "Mouse Right"}
		names[MOUSE_BUTTON_MIDDLE] = "Mouse Middle"
		return String(names.get(index, "Mouse %d" % index))
	if event is InputEventJoypadButton:
		var button: int = (event as InputEventJoypadButton).button_index
		return String(JOY_BUTTON_LABELS.get(button, "Joypad %d" % button))
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "Joypad axis %d %s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	return "Unknown input"


## Replaces every event bound to `action` with `event` and saves all bindings.
##
## CONFLICT POLICY (chosen deliberately): the newest binding wins. When the
## pressed input is already bound to another rebindable game action, it is
## removed from that other action first, so one input never drives two game
## actions and the rebind always takes effect. Built-in ui_* actions are never
## touched, so menus keep their own defaults.
##
## Returns false when the event is not something we can bind.
func rebind_action(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		push_warning("InputRemap: no action named '%s'" % action)
		return false
	var fresh := _bindable_copy(event)
	if fresh == null:
		return false
	for other in InputMap.get_actions():
		var other_name := String(other)
		if other_name == action or not is_game_action(other_name):
			continue
		for existing in InputMap.action_get_events(other_name):
			if existing.is_match(fresh):
				InputMap.action_erase_event(other_name, existing)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, fresh)
	save_bindings()
	return true


## Writes every rebindable action's events to user://input_bindings.cfg.
func save_bindings() -> void:
	var config := ConfigFile.new()
	for entry in ACTIONS:
		var action := String(entry["action"])
		if not InputMap.has_action(action):
			continue
		var stored: Array = []
		for event in InputMap.action_get_events(action):
			stored.append(_event_to_data(event))
		config.set_value(CONFIG_SECTION, action, stored)
	var err := config.save(CONFIG_PATH)
	if err != OK:
		push_warning("InputRemap: could not save bindings to %s (error %d)" % [CONFIG_PATH, err])


## Reapplies the player's saved bindings. Until a save file exists the project
## defaults from project.godot stay in place untouched.
func load_bindings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	for entry in ACTIONS:
		var action := String(entry["action"])
		if not InputMap.has_action(action):
			continue
		var value: Variant = config.get_value(CONFIG_SECTION, action, null)
		if not (value is Array):
			continue
		var stored: Array = value
		if stored.is_empty():
			continue
		var events: Array[InputEvent] = []
		for data in stored:
			var event := _data_to_event(data)
			if event != null:
				events.append(event)
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for event in events:
			InputMap.action_add_event(action, event)


## Cleans up the project defaults before any saved bindings are applied, so that
## one input never drives two different actions.
##
## Two passes, both on the defaults in project.godot:
##   1. drop duplicate events INSIDE a single action (a leftover of binding the
##      same action twice), and
##   2. drop an event already claimed by an action listed EARLIER in ACTIONS.
##
## Pass 2 is what unpicks the Space clash: Space sits on both `jump` and
## `interact`, and `jump` is listed first, so `jump` keeps Space while `interact`
## keeps only E - which is why pressing jump next to a villager no longer starts
## a conversation.
##
## This runs BEFORE load_bindings(), so a deliberate rebind by the player still
## wins over the clean-up.
func _sanitize_defaults() -> void:
	var claimed: Array[InputEvent] = []
	for entry in ACTIONS:
		var action := String(entry["action"])
		if not InputMap.has_action(action):
			continue
		var kept: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			if _pool_matches(event, kept) or _pool_matches(event, claimed):
				InputMap.action_erase_event(action, event)
				continue
			kept.append(event)
			claimed.append(event)


## True when `event` is already represented in `pool`.
func _pool_matches(event: InputEvent, pool: Array[InputEvent]) -> bool:
	for other in pool:
		if other.is_match(event):
			return true
	return false


## Returns a copy of `event` that is safe to store in the InputMap, or null when
## the event cannot be used as a binding.
func _bindable_copy(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var src_key := event as InputEventKey
		if src_key.echo:
			return null
		# Keycode only, and no modifier flags baked in, so the binding follows
		# the player's keyboard layout and stays predictable.
		var key := InputEventKey.new()
		key.keycode = src_key.keycode
		key.pressed = false
		return key
	if event is InputEventMouseButton:
		var src_mouse := event as InputEventMouseButton
		var mouse := InputEventMouseButton.new()
		mouse.button_index = src_mouse.button_index
		mouse.pressed = false
		return mouse
	if event is InputEventJoypadButton:
		var src_pad := event as InputEventJoypadButton
		var pad := InputEventJoypadButton.new()
		pad.button_index = src_pad.button_index
		pad.pressed = false
		return pad
	return null


func _event_to_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"kind": "key",
			"keycode": int(key.keycode),
			"physical_keycode": int(key.physical_keycode),
			"mods": key.get_modifiers_mask(),
		}
	if event is InputEventMouseButton:
		return {"kind": "mouse_button", "button": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"kind": "joypad_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"kind": "joypad_motion", "axis": motion.axis, "axis_value": motion.axis_value}
	return {}


func _data_to_event(data: Variant) -> InputEvent:
	if not (data is Dictionary):
		return null
	var info: Dictionary = data
	match String(info.get("kind", "")):
		"key":
			var code: Key = info.get("keycode", 0)
			var physical: Key = info.get("physical_keycode", 0)
			var key := InputEventKey.new()
			key.keycode = code
			key.physical_keycode = physical
			# InputEventWithModifiers exposes only get_modifiers_mask(); the mask
			# is restored through the individual flag properties.
			var mods := int(info.get("mods", 0))
			key.shift_pressed = (mods & KEY_MASK_SHIFT) != 0
			key.ctrl_pressed = (mods & KEY_MASK_CTRL) != 0
			key.alt_pressed = (mods & KEY_MASK_ALT) != 0
			key.meta_pressed = (mods & KEY_MASK_META) != 0
			key.pressed = false
			return key
		"mouse_button":
			var mouse_button: MouseButton = info.get("button", 0)
			var mouse := InputEventMouseButton.new()
			mouse.button_index = mouse_button
			mouse.pressed = false
			return mouse
		"joypad_button":
			var joy_button: JoyButton = info.get("button", 0)
			var pad := InputEventJoypadButton.new()
			pad.button_index = joy_button
			pad.pressed = false
			return pad
		"joypad_motion":
			var axis: JoyAxis = info.get("axis", 0)
			var motion := InputEventJoypadMotion.new()
			motion.axis = axis
			motion.axis_value = float(info.get("axis_value", 0.0))
			return motion
	return null
