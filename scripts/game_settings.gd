class_name GameSettings
extends RefCounted
## Player-facing options - how the game looks and behaves, rather than what the
## player has done. Stored PER SAVE SLOT, not globally.
##
## The slot owns them (res://scripts/save_game.gd, its `[options]` section), so
## the choices a player makes belong to that playthrough: loading a saved game
## brings its options back with it, and New Game starts on the defaults because a
## fresh slot has none recorded. Changing one is not progress, so SaveGame leaves
## the slot's "updated" stamp alone and an option change never bumps a save up the
## Load list.
##
## The respawn point, the character name and the options therefore all travel
## together in one file, which is what keeps a save self-contained.
##
## Static on purpose: there is one set of options per playthrough and no node of
## its own, so nothing needs an instance and nothing has to be autoloaded.
##
## EVERY future setting belongs here the same way: add a const for its key, a
## typed getter/setter pair like the one below, and store it through option() /
## set_option(). Nothing else has to change - SaveGame already carries an
## arbitrary key/value section per slot.

const HUD_POSITION_KEY := "hud_position"
## Where the HP / mana display can sit. "bottom" and "top" put the two orbs side
## by side; "left" and "right" stack them, HP above mana.
const HUD_POSITIONS := ["bottom", "top", "left", "right"]
const HUD_POSITION_DEFAULT := "bottom"


## The stored HP / mana display position, always one of HUD_POSITIONS.
static func hud_position() -> String:
	return normalize_hud_position(String(option(HUD_POSITION_KEY, HUD_POSITION_DEFAULT)))


static func set_hud_position(placement: String) -> void:
	set_option(HUD_POSITION_KEY, normalize_hud_position(placement))


## Anything unrecognised - a slot written by an older build, an option removed
## later - falls back to the default instead of leaving the HUD with nowhere to go.
static func normalize_hud_position(placement: String) -> String:
	var key := placement.strip_edges().to_lower()
	if HUD_POSITIONS.has(key):
		return key
	return HUD_POSITION_DEFAULT


## The stored value for a setting key, from the active save slot. `default_value`
## comes back when this playthrough has never set it - which includes the start
## screen, where there is no slot at all.
static func option(key: String, default_value: Variant) -> Variant:
	var store := _store()
	if store == null:
		return default_value
	return store.call("get_option", key, default_value)


static func set_option(key: String, value: Variant) -> void:
	var store := _store()
	if store == null:
		return
	store.call("set_option", key, value)


## The SaveGame autoload. Looked up through the main loop because these are static
## functions and have no node of their own to get_node() from.
static func _store() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(^"SaveGame")
