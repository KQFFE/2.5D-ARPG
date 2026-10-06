extends Node
## Global (autoload) dialogue driver.
## Keeps a simple queue of lines and broadcasts them to the UI.
## The quest flag itself lives as metadata on the player, not here.

signal dialogue_started
signal dialogue_ended
signal line_shown(text: String)

var active := false

var _lines: Array = []
var _index := 0
var _speaker: Node = null


func start(lines: Array, speaker: Node = null) -> void:
	_lines = []
	for line in lines:
		_lines.append(str(line))
	if _lines.is_empty():
		return
	_index = 0
	_speaker = speaker
	active = true
	dialogue_started.emit()
	line_shown.emit(_lines[_index])


func advance() -> void:
	if not active:
		return
	_index += 1
	if _index >= _lines.size():
		_close()
	else:
		line_shown.emit(_lines[_index])


## Name of the NPC currently talking, if it exposes a `speaker_name` export.
## The 3D dialogue box uses this for its name plate; speakers without the
## property simply show nothing.
func current_speaker_name() -> String:
	if _speaker == null:
		return ""
	var name_value: Variant = _speaker.get("speaker_name")
	return "" if name_value == null else str(name_value)


func _close() -> void:
	active = false
	_lines = []
	_index = 0
	_speaker = null
	dialogue_ended.emit()
