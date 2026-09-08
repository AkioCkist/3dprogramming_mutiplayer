extends ConfigFile
class_name GameConfig

const PATH := "user://game_setup.cfg"
const VERSION := 2

const S_FILE := "File"
const S_SETTINGS := "Settings"

var settings_username: String:
	get: return get_value(S_SETTINGS, "username", "Player")
	set(value): set_value(S_SETTINGS, "username", value)

var settings_color: Color:
	get: return get_value(S_SETTINGS, "color", Color.WHITE)
	set(value): set_value(S_SETTINGS, "color", value)

var settings_address: String:
	get: return get_value(S_SETTINGS, "join_address", "")
	set(value): set_value(S_SETTINGS, "join_address", value)

var settings_maxplayers: int:
	get: return get_value(S_SETTINGS, "max_players", 4)
	set(value): set_value(S_SETTINGS, "max_players", value)

func load_defaults():
	set_value(S_FILE, "version", VERSION)	# schema version
	settings_address = ""
	settings_maxplayers = 4
	settings_username = "Player"
	settings_color = Color.WHITE

## Create (or load) game configuration
static func create() -> GameConfig:
	var game_config := GameConfig.new()
	if game_config.load(PATH) != OK or game_config.get_value(S_FILE, "version", VERSION) < VERSION:
		game_config.load_defaults()
		game_config.save(PATH)
	return game_config

## Save to user config path
func save_to_path():
	save(PATH)
