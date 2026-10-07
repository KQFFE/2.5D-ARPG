extends Node
## InputRemap - the autoload that owns every rebindable action in the game.
##
## Project rule: gameplay asks for actions by name only
## (Input.is_action_pressed("dash")) and never reads raw keycodes or mouse /
## joypad button numbers, so rebinding stays purely an InputMap concern.
##
## Bindings are stored PER SAVE SLOT, never in a global file: they live in the
## active slot's [bindings] section (res://scripts/save_game.gd), so rebinding
## Jump in one playthrough cannot change another, and a New Game starts from the
## project defaults because a fresh slot records no bindings at all.
##
## The active slot's bindings are applied whenever the slot changes - New Game or
## Load - which SaveGame announces through its active_slot_changed signal. Until a
## slot is active (the start screen) a rebind lives only for that session.
##
## Startup also cleans the project defaults in project.godot so one input never
## drives two actions.

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
	# Start from the project defaults, cleaned so one input never drives two
	# actions. Whatever the active slot holds is applied when the slot changes.
	_sanitize_defaults()
	var store := _store()
	if store != null and store.has_signal("active_slot_changed"):
		store.connect("active_slot_changed", _on_active_slot_changed)
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


## Snapshot of the current bindings, written into the ACTIVE SLOT. Called after
## every rebind, so the change survives even if the player never presses Save &
## Quit. Does nothing on the start screen, where there is no slot yet.
func save_bindings() -> void:
	var store := _store()
	if store == null:
		return
	var data: Dictionary = {}
	for entry in ACTIONS:
		var action := String(entry["action"])
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		for event in InputMap.action_get_events(action):
			events.append(_event_to_data(event))
		data[action] = events
	store.call("set_bindings", data)


## Puts the active slot's bindings into the InputMap. A slot with nothing
## recorded - a fresh New Game, or a save made before any key was changed - falls
## back to the project defaults, so the previous playthrough's keys can never
## leak into a new one.
func load_bindings() -> void:
	_reset_to_defaults()
	var store := _store()
	if store == null:
		return
	var data: Variant = store.call("get_bindings")
	if data is Dictionary:
		_apply_binding_data(data)


## SaveGame raised active_slot_changed: New Game or Load. Re-read the bindings so
## the keys follow the save the player is now in.
func _on_active_slot_changed() -> void:
	load_bindings()


## Back to exactly what project.godot defines, then re-cleaned, so the fixed rules
## (interact is E and gamepad Y, never Space) hold whatever the previous slot said.
func _reset_to_defaults() -> void:
	InputMap.load_from_project_settings()
	_sanitize_defaults()


## Applies one slot's stored bindings over the defaults. An action the slot has no
## entry for keeps its default; an action stored with an EMPTY array is left
## unbound, so a binding the player deliberately cleared stays cleared.
func _apply_binding_data(data: Dictionary) -> void:
	for entry in ACTIONS:
		var action := String(entry["action"])
		if not InputMap.has_action(action):
			continue
		var value: Variant = data.get(action, null)
		if not (value is Array):
			continue
		var stored: Array = value
		InputMap.action_erase_events(action)
		for item in stored:
			var event := _data_to_event(item)
			if event != null:
				InputMap.action_add_event(action, event)


## The SaveGame autoload. Resolved by path so this file stays loadable on its own.
func _store() -> Node:
	return get_node_or_null(^"/root/SaveGame")


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
	# The fixed defaults for `interact`, enforced outright instead of left to the
	# order of ACTIONS above: E on the keyboard and Y on the gamepad, and never
	# Space. Space is JUMP, and Space doubling as interact meant jumping next to a
	# villager started a dialogue. Pass 2 only happens to get the Space half right
	# because `jump` is listed before `interact`; this does not depend on that, and
	# it also puts the gamepad binding back if a future re-import loses it.
	_strip_key_from_action("interact", KEY_SPACE)
	_ensure_joy_button("interact", JOY_BUTTON_Y)


## Makes sure `action` has the joypad `button` bound, adding it only when the
## project defaults are missing it. Every other event is left untouched, so this
## asserts a default without trampling a deliberate rebind.
func _ensure_joy_button(action: String, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return
	var pad := InputEventJoypadButton.new()
	pad.button_index = button
	pad.pressed = false
	InputMap.action_add_event(action, pad)


## Removes every event bound to `keycode` from `action`, so a fixed rule holds
## whatever else the bindings happen to look like.
func _strip_key_from_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if not (event is InputEventKey):
			continue
		var key := event as InputEventKey
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == keycode:
			InputMap.action_erase_event(action, event)


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
