extends CanvasLayer
## Start screen: the "Skadoosh!" title plus New Game / Load / Settings / Quit.
##
## This scene is application/run/main_scene, so Play opens it. New Game loads
## res://main.tscn, the gameplay entry point, which stays a thin wrapper around
## the village scene.
##
## Load and Settings are subpages of this screen: only one page is visible at a
## time, and each subpage asks to be closed with its own back_requested signal
## (raised by its Back button or by Escape), which returns to the button list.

const GAMEPLAY_SCENE := "res://main.tscn"

@onready var _main_page: Control = %MainPage
@onready var _load_page: LoadMenu = %LoadPage
@onready var _settings_page: SettingsMenu = %SettingsPage
@onready var _new_game_button: Button = %NewGameButton
@onready var _load_button: Button = %LoadButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_load_page.back_requested.connect(_show_main_page)
	_settings_page.back_requested.connect(_show_main_page)
	_show_main_page()


func _show_main_page() -> void:
	_load_page.close()
	_settings_page.close()
	_main_page.visible = true
	_new_game_button.grab_focus()


## A brand new game starts from a clean slate: the recorded lamp-post checkpoint
## and the slot that the next save will write into are both reset, so the player
## never wakes at a checkpoint from an earlier character.
func _on_new_game_pressed() -> void:
	var save := get_node_or_null(^"/root/SaveGame")
	if save != null:
		save.call("new_game")
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


func _on_load_pressed() -> void:
	_main_page.visible = false
	_load_page.open()


func _on_settings_pressed() -> void:
	_main_page.visible = false
	_settings_page.open()


func _on_quit_pressed() -> void:
	get_tree().quit()
