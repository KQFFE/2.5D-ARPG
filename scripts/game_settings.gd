class_name GameSettings
extends RefCounted
## Player-facing options that belong to the installation, not to a save slot:
## how the game looks and behaves, rather than what the player has done. They
## live in user://settings.cfg beside the save slots and the checkpoint file.
##
## Static on purpose: there is one set of options for the whole game, so nothing
## needs an instance and nothing has to be autoloaded. The file is read once and
## then cached; set_* writes straight back out, so a choice survives a restart
## without any "apply" step.
##
## Only the HP / mana display position lives here so far. Anything else that
## should not be per-save - volume, window mode - belongs in here too, as its own
## section, rather than in one of the save slots.

const CONFIG_PATH := "user://settings.cfg"

const VIDEO_SECTION := "video"
const HUD_POSITION_KEY := "hud_position"
## Where the HP / mana display can sit. "bottom" and "top" put the two orbs side
## by side; "left" and "right" stack them, HP above mana.
const HUD_POSITIONS := ["bottom", "top", "left", "right"]
const HUD_POSITION_DEFAULT := "bottom"

static var _config: ConfigFile = null


## The stored HP / mana display position, always one of HUD_POSITIONS.
static func hud_position() -> String:
	var stored: Variant = _file().get_value(VIDEO_SECTION, HUD_POSITION_KEY, HUD_POSITION_DEFAULT)
	return normalize_hud_position(String(stored))


static func set_hud_position(placement: String) -> void:
	var config := _file()
	config.set_value(VIDEO_SECTION, HUD_POSITION_KEY, normalize_hud_position(placement))
	config.save(CONFIG_PATH)


## Anything unrecognised - a hand-edited file, an option removed later - falls
## back to the default instead of leaving the HUD with nowhere to go.
static func normalize_hud_position(placement: String) -> String:
	var key := placement.strip_edges().to_lower()
	if HUD_POSITIONS.has(key):
		return key
	return HUD_POSITION_DEFAULT


## The cached settings file, loaded on first use. A missing file is not an error:
## it just means every option is still on its default.
static func _file() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		_config.load(CONFIG_PATH)
	return _config
