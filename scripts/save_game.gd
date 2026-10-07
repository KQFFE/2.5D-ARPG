extends Node
## SaveGame - the autoload that owns save slots, one file per playthrough.
##
## A slot is created by "New Game" and carries everything that belongs to that
## playthrough: the character name (the placeholder "Unnamed" until a naming
## screen exists), when it was last written, the point the player should come back
## to (the last lamp post they interacted with), and the player's OPTIONS - the
## settings chosen in the menus, which therefore come back with the save instead
## of being global to the installation.
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
## Player options live in the SLOT, not in a global file, so a playthrough's
## choices travel with it (see res://scripts/game_settings.gd). Keys are
## arbitrary; an option this slot never set just reads back as its default.
const OPTIONS_SECTION := "options"
## Input bindings live in the slot too, for the same reason: a rebinding belongs
## to the playthrough that made it, so changing Jump in one save never touches
## another. Stored as one entry - action -> Array of event-data dictionaries, the
## shape InputRemap builds. A slot that never rebound anything has no entry, which
## reads back as the project defaults.
const BINDINGS_SECTION := "bindings"
const BINDINGS_KEY := "events"
## How many saved characters the Load screen lists, newest first.
const MAX_LISTED := 5
const PLACEHOLDER_NAME := "Unnamed"

## The village checkpoint file, kept in step so the lamp lights and the player
## respawns at the loaded point without a second codepath.
const CHECKPOINT_PATH := "user://checkpoint.cfg"
const CHECKPOINT_SECTION := "checkpoint"

## Raised whenever the active slot changes - New Game or Load. InputRemap listens
## and applies that playthrough's bindings, so the keys follow the save the player
## is in instead of being global to the installation.
signal active_slot_changed

## The slot this session reads and writes. Empty until New Game or Load.
var active_slot_id := ""

## Set by load_slot() when the slot has a recorded point; consumed once by the
## village so it can drop the player at the lamp post they last saved at.
var _pending_spawn: Variant = null

## The player options currently in effect, key -> value. load_slot() fills it from
## a slot's [options] section; while no playthrough is active - which is the case
## on the start screen's Settings page - it just holds the choices made this
## session. new_game() clears it, so a new playthrough starts on the defaults even
## after the player changed something from the start menu. One map serves both
## cases so get_option() has a single place to read.
var _options_cache: Dictionary = {}


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
	# A new playthrough starts on the defaults: nothing carries over from the
	# previous character, including the options and the keys. The fresh slot
	# records neither, and InputRemap re-reads the (empty) bindings when it hears
	# active_slot_changed, which puts the game back on the project defaults.
	_options_cache.clear()
	active_slot_changed.emit()


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


## The in-game "Save & Quit": writes the options the player has chosen into the
## slot, then stamps it with the current time so it sorts to the top of the Load
## screen. The respawn point was already mirrored in by set_checkpoint() when the
## player reached a lamp post.
func save_active() -> void:
	if active_slot_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(_slot_path(active_slot_id))
	_write_options_section(config)
	config.set_value(SECTION, "updated", int(Time.get_unix_time_from_system()))
	var err := config.save(_slot_path(active_slot_id))
	if err != OK:
		push_warning("SaveGame: could not write slot '%s' (error %d)" % [active_slot_id, err])


## Makes `id` the active slot, restores its OPTIONS and its point, and arms the
## spawn the player should be dropped at.
##
## The options are read BEFORE the has_spawn early-return below, because they have
## nothing to do with the respawn point: a save made before the player ever
## reached a lamp post still has options, and returning early would silently lose
## them.
## active_slot_changed is emitted on EVERY path out, including a slot file that
## will not load: InputRemap re-reads the bindings from whichever slot is active,
## and an unreadable slot has to reset the keys to the defaults rather than leave
## the previous playthrough's bindings in place.
func load_slot(id: String) -> void:
	active_slot_id = id
	_pending_spawn = null
	var config := ConfigFile.new()
	if config.load(_slot_path(id)) == OK:
		_load_options_section(config)
		if bool(config.get_value(SECTION, "has_spawn", false)):
			var position: Vector3 = config.get_value(SECTION, "position", Vector3.ZERO)
			var checkpoint_id := String(config.get_value(SECTION, "checkpoint_id", ""))
			_write_checkpoint_cfg(checkpoint_id, position)
			_pending_spawn = position
	active_slot_changed.emit()


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


# --- Player options (stored in the slot) ------------------------------------

## The stored value for `key`, or `default_value` when this playthrough has never
## set it. The cache is the single source of truth: set_option() keeps it current
## and load_slot() refills it, so a choice made in the menus and a choice read
## back from a loaded save go through exactly the same path. With no active slot -
## the start screen's Settings page - the cache simply holds this session's
## choices.
func get_option(key: String, default_value: Variant) -> Variant:
	return _options_cache.get(key, default_value)


## Stores `key` for the active playthrough. Deliberately does NOT touch
## "updated": changing an option is not saving progress, so it must not bump the
## slot to the top of the Load list.
##
## With a slot active the value is written straight into the slot's [options]
## section, so it survives even if the player never presses Save & Quit. With no
## slot it lives in the cache until New Game or Load, which is what lets the start
## screen's Settings page still show what was chosen.
func set_option(key: String, value: Variant) -> void:
	_options_cache[key] = value
	if active_slot_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(_slot_path(active_slot_id))
	config.set_value(OPTIONS_SECTION, key, value)
	var err := config.save(_slot_path(active_slot_id))
	if err != OK:
		push_warning("SaveGame: could not write option '%s' to slot '%s' (error %d)" % [key, active_slot_id, err])


# --- Input bindings (stored in the slot) ------------------------------------

## The input bindings this playthrough has rebound, as action -> Array of
## event-data dictionaries. Empty means "nothing rebound here", which is the
## project defaults - a brand new game, or a save made before any key was changed.
func get_bindings() -> Dictionary:
	if active_slot_id.is_empty():
		return {}
	var config := ConfigFile.new()
	if config.load(_slot_path(active_slot_id)) != OK:
		return {}
	var stored: Variant = config.get_value(BINDINGS_SECTION, BINDINGS_KEY, {})
	if stored is Dictionary:
		return stored
	return {}


## Stores the bindings of the current session in the active slot. Called by
## InputRemap after every rebind.
##
## Like set_option(), this deliberately does NOT touch "updated": rebinding a key
## is not progress, so it must not reorder the Load list.
func set_bindings(data: Dictionary) -> void:
	if active_slot_id.is_empty():
		return
	var config := ConfigFile.new()
	config.load(_slot_path(active_slot_id))
	config.set_value(BINDINGS_SECTION, BINDINGS_KEY, data)
	var err := config.save(_slot_path(active_slot_id))
	if err != OK:
		push_warning("SaveGame: could not write bindings to slot '%s' (error %d)" % [active_slot_id, err])


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


## Copies every value of the in-memory cache into the slot's [options] section, so
## a Save & Quit cannot leave a choice behind that set_option() had not already
## written. Kept on the config being saved rather than writing the file itself,
## so the caller saves once.
func _write_options_section(config: ConfigFile) -> void:
	for key in _options_cache:
		config.set_value(OPTIONS_SECTION, String(key), _options_cache[key])


## Refills the cache from a slot's [options] section. Replaces the whole cache,
## so loading a save cannot leave the previous playthrough's choices behind.
func _load_options_section(config: ConfigFile) -> void:
	_options_cache.clear()
	if not config.has_section(OPTIONS_SECTION):
		return
	for key in config.get_section_keys(OPTIONS_SECTION):
		_options_cache[String(key)] = config.get_value(OPTIONS_SECTION, key)


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
