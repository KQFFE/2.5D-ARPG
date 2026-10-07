class_name SettingsCategory
extends Control
## Generic options page for one settings category: a heading plus a Back button
## in the bottom-left corner.
##
## Gameplay, Audio and Video are minimal for this milestone: the page exists and
## navigates back to the category list. Their real options arrive later, and they
## only need to fill the content column of this scene when they do.
##
## Escape or Back both emit back_requested, which the parent SettingsMenu turns
## into "go up one level" (back to the Gameplay / Audio / Video / Input list).

signal back_requested

@export var heading: String = "Category":
	set(value):
		heading = value
		if is_node_ready():
			_heading_label.text = value

@onready var _heading_label: Label = %Heading
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(_request_back)
	_heading_label.text = heading
	visible = false


func open(title: String) -> void:
	heading = title
	visible = true
	_back_button.grab_focus()


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
