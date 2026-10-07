extends CanvasLayer
## In-game menu: "Save & Quit" then "Settings", opened while playing.
##
## It is instanced by res://main.tscn, so it only exists in the gameplay scene and
## never on the start screen.
##
## Opening it pauses the scene tree and closing it puts back whatever paused state
## was in place before. The menu itself is PROCESS_MODE_ALWAYS so it keeps
## receiving input and its buttons stay clickable while paused.
##
## It opens on the ui_cancel action (Escape) and on the existing "settings" action
## (Tab, gamepad START). ONE press opens or closes it and it then STAYS in that
## state until every bound key of both actions has been released - without that
## release lock the same held key (and its echo events) reaches _unhandled_input
## again and the menu flickers shut while the player is still holding the button.
##
## Save & Quit writes the active save slot (name "Unnamed", current date/time, and
## the latest lamp-post checkpoint) through the SaveGame autoload, then returns to
## the start screen.
##
## Keybindings are rebindable, so the physical keys come from the two InputMap
## actions rather than being hard-coded.

const START_MENU_SCENE := "res://ui/main_menu.tscn"
const MENU_ACTIONS := [&"ui_cancel", &"settings"]

@onready var _main_page: Control = %MainPage
@onready var _settings_page: SettingsMenu = %SettingsPage
@onready var _save_quit_button: Button = %SaveQuitButton
@onready var _settings_button: Button = %SettingsButton

var _resume_paused := false
## True while a menu key is still held after it opened or closed the menu. The
## menu ignores the actions until all of them are released.
var _keys_held := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_quit_button.pressed.connect(_on_save_and_quit_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_page.back_requested.connect(_show_main_page)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	# The rebind overlay closes itself on Escape and must not also close this
	# menu, so while it is up the pause menu ignores the menu keys entirely.
	if _bindings_overlay_open():
		return

	# Release the lock once every menu key is up again.
	if _keys_held and not _any_menu_key_pressed():
		_keys_held = false

	if _keys_held:
		return

	var pressed_key := false
	for action in MENU_ACTIONS:
		if event.is_action_pressed(action):
			pressed_key = true
			break
	if not pressed_key:
		return

	_keys_held = true
	get_viewport().set_input_as_handled()

	if not visible:
		open()
		return
	# A subpage owns the key: it goes up one level instead of resuming the game.
	if not _main_page.visible:
		return
	close()


## True while any key bound to ui_cancel or settings is physically held.
func _any_menu_key_pressed() -> bool:
	for action in MENU_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


## Opens the menu and pauses the game, remembering the paused state it found.
func open() -> void:
	if visible:
		return
	_resume_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_show_main_page()


## Closes the menu and restores the paused state recorded by open().
func close() -> void:
	if not visible:
		return
	_settings_page.close()
	visible = false
	get_tree().paused = _resume_paused


func _show_main_page() -> void:
	_settings_page.close()
	_main_page.visible = true
	_save_quit_button.grab_focus()


func _on_settings_pressed() -> void:
	_main_page.visible = false
	_settings_page.open()


## Writes the active save slot and returns to the start screen.
func _on_save_and_quit_pressed() -> void:
	var save := get_node_or_null(^"/root/SaveGame")
	if save != null:
		save.call("save_active")
	_resume_paused = false
	close()
	get_tree().change_scene_to_file(START_MENU_SCENE)


func _bindings_overlay_open() -> bool:
	var overlay := get_node_or_null(^"/root/SettingsScreen") as CanvasLayer
	return overlay != null and overlay.visible
