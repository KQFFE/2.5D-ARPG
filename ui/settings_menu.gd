class_name SettingsMenu
extends Control
## Settings page: the Gameplay / Audio / Video / Input categories, plus a Back
## button in the bottom-left corner.
##
## Both the start screen and the in-game pause menu instance this scene, so it
## never changes scenes itself. Escape (or Back) closes an open category page,
## and from the category list it emits back_requested so the host menu can return
## to its own page (start screen, or the paused game).
##
## Input opens the existing rebind overlay - the SettingsScreen autoload - which
## keeps owning rebinding through the InputRemap singleton at /root/InputRemap.
## The overlay is resolved by node path and driven dynamically so this scene also
## opens inside the editor without depending on autoload identifier resolution.

signal back_requested

@onready var _list_page: Control = %ListPage
@onready var _category_page: SettingsCategory = %CategoryPage
@onready var _video_page: Control = %VideoPage
@onready var _gameplay_button: Button = %GameplayButton
@onready var _audio_button: Button = %AudioButton
@onready var _video_button: Button = %VideoButton
@onready var _input_button: Button = %InputButton
@onready var _back_button: Button = %BackButton

var _bindings_open := false
var _last_category_button: Button = null


func _ready() -> void:
	_gameplay_button.pressed.connect(_open_category.bind("Gameplay", _gameplay_button))
	_audio_button.pressed.connect(_open_category.bind("Audio", _audio_button))
	# Video is the one category with real options, so it opens its own page rather
	# than the generic placeholder that Gameplay and Audio still share.
	_video_button.pressed.connect(_open_video)
	_input_button.pressed.connect(_open_input_bindings)
	_back_button.pressed.connect(_go_up)
	_category_page.back_requested.connect(_close_category_page)
	_video_page.back_requested.connect(_close_category_page)
	visible = false


## Shown by the host menu: back on the category list, first row focused.
func open() -> void:
	if _bindings_open:
		return
	_close_category_page()
	visible = true
	_gameplay_button.grab_focus()


func close() -> void:
	visible = false
	_close_category_page()


func _unhandled_input(event: InputEvent) -> void:
	# While the rebind overlay is up it owns Escape and closes itself; while a
	# category page is up, that page owns Escape and comes back here.
	if not is_visible_in_tree() or _category_page.visible or _video_page.visible or _bindings_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_go_up()
		get_viewport().set_input_as_handled()


## Goes up one level: the host menu decides where that is.
func _go_up() -> void:
	back_requested.emit()


func _open_category(title: String, button: Button) -> void:
	if _bindings_open:
		return
	_last_category_button = button
	_list_page.visible = false
	_category_page.open(title)


## Video opens its own options page instead of the generic placeholder category.
func _open_video() -> void:
	if _bindings_open:
		return
	_last_category_button = _video_button
	_list_page.visible = false
	_video_page.open()


func _close_category_page() -> void:
	_category_page.close()
	_video_page.visible = false
	_list_page.visible = true
	if visible and _last_category_button != null:
		_last_category_button.grab_focus()


func _open_input_bindings() -> void:
	if _bindings_open:
		return
	var overlay := _overlay()
	if overlay == null:
		push_warning("SettingsMenu: the SettingsScreen overlay autoload is missing.")
		return
	_bindings_open = true
	overlay.connect("closed", _on_bindings_closed)
	overlay.call("open")


func _on_bindings_closed() -> void:
	_bindings_open = false
	var overlay := _overlay()
	if overlay != null and overlay.is_connected("closed", _on_bindings_closed):
		overlay.disconnect("closed", _on_bindings_closed)
	if is_visible_in_tree():
		_input_button.grab_focus()


func _overlay() -> CanvasLayer:
	return get_node_or_null(^"/root/SettingsScreen") as CanvasLayer
