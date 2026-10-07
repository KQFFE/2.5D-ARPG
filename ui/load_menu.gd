class_name LoadMenu
extends Control
## Load page of the start screen.
##
## Lists the saved characters from the SaveGame autoload, newest first, up to
## MAX_SLOTS of them. Each slot is one row: the character name on top ("Unnamed"
## until a naming screen exists) and the save's date and time on the line below,
## formatted YYYY/MM/DD HH:MM:SS by SaveGame.
##
## Loading a save enters the village and restores the newest lamp-post checkpoint
## inside that slot, so the player wakes where they last saved.
##
## Escape or the Back button in the bottom-left corner emits back_requested, and
## the start screen returns to its main button list.

signal back_requested

const GAMEPLAY_SCENE := "res://main.tscn"
const MAX_SLOTS := 5

@onready var _slot_list: VBoxContainer = %SlotList
@onready var _slot_button: Button = %SlotButton
@onready var _empty_label: Label = %EmptyLabel
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(_request_back)
	_slot_button.pressed.connect(_load_latest)
	visible = false


func open() -> void:
	_rebuild()
	visible = true
	if _slot_button.visible:
		_slot_button.grab_focus()
	else:
		_back_button.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child in _slot_list.get_children():
		child.queue_free()
	_slot_list.visible = false
	if _slot_button != null:
		_slot_button.visible = false
	_empty_label.visible = true

	var store := _store()
	if store == null:
		return
	var slots: Array = store.call("list_saves", MAX_SLOTS)
	if slots.is_empty():
		return
	_empty_label.visible = false
	for data in slots:
		_slot_list.add_child(_make_slot_row(data))
	_slot_list.visible = true
	if _slot_button != null:
		_slot_button.visible = true


func _make_slot_row(data: Dictionary) -> Button:
	var name_text := String(data.get("name", "Unnamed"))
	var date_text := String(data.get("date", ""))
	var button := Button.new()
	button.custom_minimum_size = Vector2(420, 56)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 18)
	# Two lines: the character name on top, the save date and time underneath.
	button.text = "%s\n%s" % [name_text, date_text]
	button.pressed.connect(_load_slot.bind(String(data.get("id", ""))))
	return button


func _load_latest() -> void:
	var store := _store()
	if store == null:
		return
	store.call("load_latest")
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


func _load_slot(id: String) -> void:
	if id.is_empty():
		return
	var store := _store()
	if store == null:
		return
	store.call("load_slot", id)
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


func _store() -> Node:
	var store := get_node_or_null(^"/root/SaveGame")
	if store == null:
		push_warning("LoadMenu: the SaveGame autoload is missing; no saves can be listed.")
	return store


func _request_back() -> void:
	back_requested.emit()
