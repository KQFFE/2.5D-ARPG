extends CanvasLayer
## Modal input-bindings overlay: the content behind Settings -> Input, reached
## from the start screen and from the in-game pause menu.
##
## It is a passive overlay. Nothing opens it by itself any more - the menu that
## owns the Input category calls open(), and closes it with close(), its Close
## button or Escape. Escape is consumed here so closing the overlay never also
## steps the menu underneath up a level.
##
## It lists every rebindable action, shows the current binding for each, and lets
## the player click a row and then press a key, mouse button or joypad button to
## rebind it.
##
## The InputRemap autoload (res://scripts/input_remap.gd) is the single owner of
## bindings: this screen only reads and writes them through it and never touches
## InputMap or the save file itself. The singleton is resolved by node path and
## called dynamically so the scene loads in any project state (and can be opened
## in the editor) without depending on autoload identifier resolution.
##
## Swallowing gameplay input: while the overlay is open the scene tree is
## paused, so no pausable gameplay node polls Input or receives input events.
## The overlay itself keeps running because it is PROCESS_MODE_ALWAYS, and it
## consumes the events it handles so they cannot reach anything else.

## Raised by close(), so the menu that opened the overlay can take focus back.
signal closed

const IDLE_PROMPT := "Click a binding, then press the input you want to use."
const REBIND_PROMPT := "Press a key, mouse button or joypad button for this action. Esc cancels."

@onready var _row_list: VBoxContainer = %RowList
@onready var _prompt: Label = %PromptLabel
@onready var _close_button: Button = %CloseButton

var _remap: Object = null
var _row_buttons: Dictionary = {}
var _listening_action := ""
var _resume_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var twin := get_tree().root.get_node_or_null(^"SettingsScreen")
	if twin != null and twin != self:
		# Another copy is already mounted (for example a menu scene instanced
		# its own) - step aside so only one overlay listens for "settings".
		queue_free()
		return
	_remap = get_node_or_null(^"/root/InputRemap")
	if _remap == null:
		push_error("SettingsScreen: the InputRemap autoload is missing; bindings cannot be edited.")
		return
	_build_rows()
	_close_button.pressed.connect(close)
	_set_prompt(IDLE_PROMPT)


func _input(event: InputEvent) -> void:
	# The overlay no longer toggles itself on the "settings" action (Tab / gamepad
	# START): that key now belongs to the in-game menu, which opens and closes this
	# overlay through open() / close().
	if not visible:
		return
	if _listening_action != "":
		# While listening for a rebind, swallow everything so the pressed input
		# lands on the row being edited and nowhere else.
		_capture(event)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		# Escape closes the overlay only. The event is consumed here, so the menu
		# underneath does not also treat it as "go up one level".
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible or _remap == null:
		return
	_resume_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_listening_action = ""
	_refresh_all_rows()
	_set_prompt(IDLE_PROMPT)
	_close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	_listening_action = ""
	visible = false
	_refresh_all_rows()
	_set_prompt(IDLE_PROMPT)
	_close_button.release_focus()
	get_tree().paused = _resume_paused
	closed.emit()


func _capture(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_stop_listening()
		_set_prompt(IDLE_PROMPT)
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed():
		return
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		# Mouse motion and joypad axes cannot be bound from this screen.
		return
	var action := _listening_action
	var bound: bool = _remap.call("rebind_action", action, event)
	_listening_action = ""
	_refresh_row(action)
	if bound:
		_set_prompt("%s is now %s." % [
			_remap.call("action_label", action),
			_remap.call("binding_text", action),
		])
	else:
		_set_prompt("That input cannot be bound. Try another one.")
	get_viewport().set_input_as_handled()


func _start_listening(action: String) -> void:
	if _listening_action != "":
		_refresh_row(_listening_action)
	_listening_action = action
	var button: Button = _row_buttons.get(action)
	if button != null:
		button.text = "..."
	_set_prompt(REBIND_PROMPT)


func _stop_listening() -> void:
	if _listening_action != "":
		_refresh_row(_listening_action)
	_listening_action = ""


func _build_rows() -> void:
	for entry in _remap.call("action_entries"):
		var action := String(entry["action"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)

		var name_label := Label.new()
		name_label.text = String(entry["label"])
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)

		var button := Button.new()
		button.custom_minimum_size = Vector2(240, 0)
		button.clip_text = true
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = action
		button.pressed.connect(_start_listening.bind(action))
		row.add_child(button)

		_row_list.add_child(row)
		_row_buttons[action] = button
	_refresh_all_rows()


func _refresh_all_rows() -> void:
	for action in _row_buttons.keys():
		_refresh_row(String(action))


func _refresh_row(action: String) -> void:
	var button: Button = _row_buttons.get(action)
	if button != null:
		button.text = String(_remap.call("binding_text", action))


func _set_prompt(text: String) -> void:
	_prompt.text = text
