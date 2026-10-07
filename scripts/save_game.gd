extends Node
## SaveGame - the autoload that owns save slots, one file per playthrough.
##
## A slot is created by "New Game" and carries the character name (the
## placeholder "Unnamed" until a naming screen exists), when it was last written,
## and the point the player should come back to: the last lamp post they
## interacted with.
##
## Files live in user://saves/<id>.cfg, so any number of slots can exist and the
## Load screen only has to list the five newest by write time.
##
## The village respawn pipeline is reused rather than duplicated: a lamp post
## writes the recorded point into the active slot (set_checkpoint), and loading a
## slot writes that point back into user://checkpoint.cfg, which the village's
## checkpoint manager already restores and lights the matching lamp from.

const SAVE_DIR := "user://saves"
const SECTION := "save"
## How many saved characters the Load screen lists, newest first.
const MAX_LISTED := 5
const PLACEHOLDER_NAME := "Unnamed"

## The village checkpoint file, kept in step so the lamp lights and the player
## respawns at the loaded point without a second codepath.
const CHECKPOINT_PATH := "user://checkpoint.cfg"
const CHECKPOINT_SECTION := "checkpoint"

## The slot this session reads and writes. Empty until New Game or Load.
var active_slot_id := ""

## Set by load_slot() when the slot has a recorded point; consumed once by the
## village so it can drop the player at the lamp post they last saved at.
var _pending_spawn: Variant = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


# --- Session entry points ---------------------------------------------------

## Starts a brand new playthrough: the previous run's lamp-post checkpoint is
## erased and a fresh slot becomes active, so a New Game never inherits the last
## character's save state. The slot file itself is written on the first save.
func new_game() -> void:
	DirAccess.remove_absolute(CHECKPOINT_PATH)
	var now := int(Time.get_unix_time_from_system())
	var id := "slot_%d_%d" % [now, randi() % 10000]
	var config := ConfigFile.new()
	config.set_value(SECTION, "name", PLACEHOLDER_NAME)
	config.set_value(SECTION, "created", now)
	config.set_value(SECTION, "updated", now)
	config.set_value(SECTION, "checkpoint_id", "")
	config.set_value(SECTION, "position", Vector3.ZERO)
	config.set_value(SECTION, "has_spawn", false)
	var err := config.save(_slot_path(id))
	if err != OK:
		push_warning("SaveGame: could not create slot '%s' (error %d)" % [id, err])
	active_slot_id = id
	_pending_spawn = null


## Records the respawn point in the active slot. The village calls this whenever
## a lamp post is activated; the slot is stamped as saved on the next
## save_active(). Does nothing when no slot is active (a fresh game with no save).
func set_checkpoint(id: String, position: Vector3) -> void:
	if active_slot_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(_slot_path(active_slot_id))
	config.set_value(SECTION, "checkpoint_id", id)
	config.set_value(SECTION, "position", position)
	config.set_value(SECTION, "has_spawn", true)
	var err := config.save(_slot_path(active_slot_id))
	if err != OK:
		push_warning("SaveGame: could not write slot '%s' (error %d)" % [active_slot_id, err])


## The in-game "Save & Quit": stamps the active slot with the current time, so it
## sorts to the top of the Load screen. The respawn point was already mirrored in
## by set_checkpoint() when the player reached a lamp post.
func save_active() -> void:
	if active_slot_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(_slot_path(active_slot_id))
	config.set_value(SECTION, "updated", int(Time.get_unix_time_from_system()))
	var err := config.save(_slot_path(active_slot_id))
	if err != OK:
		push_warning("SaveGame: could not write slot '%s' (error %d)" % [active_slot_id, err])


## Makes `id` the active slot, restores its point into the village checkpoint file
## and arms the spawn the player should be dropped at.
func load_slot(id: String) -> void:
	active_slot_id = id
	_pending_spawn = null
	var config := ConfigFile.new()
	if config.load(_slot_path(id)) != OK:
		return
	if not bool(config.get_value(SECTION, "has_spawn", false)):
		return
	var position: Vector3 = config.get_value(SECTION, "position", Vector3.ZERO)
	var checkpoint_id := String(config.get_value(SECTION, "checkpoint_id", ""))
	_write_checkpoint_cfg(checkpoint_id, position)
	_pending_spawn = position


## Loads the newest slot there is, if any.
func load_latest() -> bool:
	var slots: Array = list_saves(1)
	if slots.is_empty():
		return false
	load_slot(String(slots[0]["id"]))
	return true


## The point to spawn the player at, returned once. Null when there is none.
func consume_pending_spawn() -> Variant:
	var value: Variant = _pending_spawn
	_pending_spawn = null
	return value


func has_active_slot() -> bool:
	return not active_slot_id.is_empty()


# --- Listing ----------------------------------------------------------------

## The saved characters, newest first, at most `max_count` of them. Each entry is
## {id, name, date}, where `date` is already formatted YYYY/MM/DD HH:MM:SS.
func list_saves(max_count: int = MAX_LISTED) -> Array:
	var slots: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return slots
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".cfg"):
			var config := ConfigFile.new()
			if config.load(SAVE_DIR.path_join(file)) == OK:
				slots.append({
					"id": file.get_basename(),
					"name": String(config.get_value(SECTION, "name", PLACEHOLDER_NAME)),
					"date": format_datetime(int(config.get_value(SECTION, "updated", 0))),
					"updated": int(config.get_value(SECTION, "updated", 0)),
				})
		file = dir.get_next()
	dir.list_dir_end()
	slots.sort_custom(_newest_first)
	if max_count > 0 and slots.size() > max_count:
		slots = slots.slice(0, max_count)
	return slots


## A unix timestamp as the save date and time, "YYYY/MM/DD HH:MM:SS", in the
## player's own time zone.
func format_datetime(unix: int) -> String:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var stamp := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%04d/%02d/%02d %02d:%02d:%02d" % [
		int(stamp["year"]), int(stamp["month"]), int(stamp["day"]),
		int(stamp["hour"]), int(stamp["minute"]), int(stamp["second"]),
	]


# --- Internals --------------------------------------------------------------

func _newest_first(a: Dictionary, b: Dictionary) -> bool:
	return int(a["updated"]) > int(b["updated"])


func _slot_path(id: String) -> String:
	return SAVE_DIR.path_join(id + ".cfg")


## Writes the point the village checkpoint manager restores on start, so the
## loaded lamp lights up and the player respawns there through the normal path.
func _write_checkpoint_cfg(id: String, position: Vector3) -> void:
	if id.is_empty():
		return
	var config := ConfigFile.new()
	config.set_value(CHECKPOINT_SECTION, "id", id)
	config.set_value(CHECKPOINT_SECTION, "position", position)
	var err := config.save(CHECKPOINT_PATH)
	if err != OK:
		push_warning("SaveGame: could not write %s (error %d)" % [CHECKPOINT_PATH, err])
