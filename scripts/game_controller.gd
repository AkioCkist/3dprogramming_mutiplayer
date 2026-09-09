extends Node
class_name GameControllerClass

# In-game signals
signal lap_change(num: int)
signal powerup_pickup(num: int)
signal position_update(pos: int)
signal race_ready()
signal race_finished()
signal race_wrapup()
signal race_restart()

# Lobby signals
signal player_joined(id: int, name: StringName, color: Color)
signal player_left(id: int)
signal player_list_update(list: Dictionary[int, Dictionary])

signal client_hurdle_request(id: int)

## Relay signal from server to client as controller signal
@rpc("authority", "call_local", "reliable")
func client_notify_lap_change(num: int):
	lap_change.emit(num)

## Relay signal from server to client as controller signal
@rpc("authority", "call_local", "reliable")
func client_notify_powerup_pickup(num: int):
	powerup_pickup.emit(num)

## Relay signal from server to client as controller signal
@rpc("authority", "call_local", "reliable")
func client_notify_race_finished():
	race_finished.emit()

## Relay signal from server to client as controller signal
@rpc("authority", "call_local", "reliable")
func client_notify_race_wrapup():
	race_wrapup.emit()
	
## Relay signal from server to client as controller signal
@rpc("authority", "call_local", "unreliable_ordered")
func client_notify_position(pos: int):
	position_update.emit(pos)

## Relay signal from server to client as controller signal
@rpc("authority", "call_remote", "unreliable_ordered")
func client_notify_race_ready():
	race_ready.emit()

## Request server to spawn a hurdle from this client
@rpc("any_peer", "call_local", "reliable")
func server_spawn_hurdle():
	client_hurdle_request.emit(multiplayer.get_remote_sender_id())

## Request server to add this peer with data
@rpc("any_peer", "call_local", "reliable")
func server_send_connect_args(username: String, color: Color):
	player_joined.emit(multiplayer.get_remote_sender_id(), username, color)

## Send data over to server
@rpc("authority", "call_local", "reliable")
func client_request_connect_args():
	server_send_connect_args.rpc_id(1, config.settings_username, config.settings_color)

## Inform client to restart scene (reloading the scene breaks replication)
@rpc("authority", "call_remote", "reliable")
func client_restart():
	race_restart.emit()

var current_level: RaceLevel
var players: Dictionary[int, Dictionary] = {}

## Get player list from server
@rpc("authority", "call_local", "reliable")
func client_send_player_list(dict: Dictionary[int, Dictionary]):
	if not multiplayer.is_server():
		players = dict	# do not let this signal overwrite players on server
	player_list_update.emit(dict)

# Game configuration
var server := false
var local_override := false
var autostart := false
var race_started := false

var config := GameConfig.create()

## Initialize persistent server peer in multiplayer ref
func init_server() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var peer_err := peer.create_server(7777, config.settings_maxplayers)
	if peer_err != OK:
		push_error("ENet error ", error_string(peer_err))
		return false
	multiplayer.multiplayer_peer = peer
	return true

## Initialize persistent client peer in multiplayer ref
func init_client() -> bool:
	var addr := "localhost" if local_override else config.settings_address
	var peer = ENetMultiplayerPeer.new()
	var peer_err := peer.create_client(addr, 7777)
	if peer_err != OK:
		push_error("ENet error ", error_string(peer_err))
		return false
	multiplayer.multiplayer_peer = peer
	return true

## Close whatever peer we initialized beforehand
func close_peer():
	var peer := multiplayer.multiplayer_peer
	if peer:
		peer.close()
		peer = null

## Check if the peer is alive
func has_peer():
	var peer := multiplayer.multiplayer_peer
	if peer is OfflineMultiplayerPeer:
		return false
	return peer and (peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED)

func _ready() -> void:
	server = OS.has_feature('server')
	
	# Listen to own events for bookkeeping
	player_joined.connect(func(id: int, username: String, color: Color):
		players.set(id, { "username": username, "color": color }))
	player_left.connect(func(id: int): players.erase(id))

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			config.save_to_path()
