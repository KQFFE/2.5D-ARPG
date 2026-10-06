extends CanvasLayer
## Bottom-of-screen dialogue box with a typewriter reveal - ported unchanged
## from the 2D prototype, since it is UI and stays Control/CanvasLayer in the
## 3D village.
##
## Press interact once to finish the line early, again to advance. The
## DialogueManager autoload (res://scripts/dialogue_manager.gd) drives it.

const CHARS_PER_SECOND := 45.0

@onready var _label: RichTextLabel = $Panel/Text
@onready var _speaker: Label = $Panel/Speaker

var _typing := false
var _shown := 0.0
var _full := ""


func _ready() -> void:
	visible = false
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	DialogueManager.line_shown.connect(_on_line_shown)


func _on_dialogue_started() -> void:
	visible = true
	_speaker.text = DialogueManager.current_speaker_name()


func _on_dialogue_ended() -> void:
	visible = false
	_typing = false


func _on_line_shown(text: String) -> void:
	_full = text
	_label.text = text
	_label.visible_characters = 0
	_shown = 0.0
	_typing = true


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * CHARS_PER_SECOND
	_label.visible_characters = int(_shown)
	if _label.visible_characters >= _full.length():
		_label.visible_characters = -1
		_typing = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact"):
		if _typing:
			_label.visible_characters = -1
			_typing = false
		else:
			DialogueManager.advance()
		get_viewport().set_input_as_handled()
