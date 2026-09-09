extends Node3D
class_name RaceLevel


@export_group("Settings")
@export var vehicle_spawn_group_name: StringName = &""
@export var level_nodes_root: Node3D = null
@export var racetrack_path: Path3D = null
@export var camera_rig: Node3D = null

@export_group("Multiplayer")
@export var spawner: MultiplayerSpawner = null
@export var replication_bin: Node = null

@export_group("Gameplay")
@export var lap_count := 1
@export var music: AudioStreamPlayer

var checkpoint_tscn := preload("res://assets/scenes/checkpoint.tscn")
var checkpoint_size := 0
var checkpoint_areas: Array[Area3D] = []
var winners: Array[TrackVehicle] = [] # sorted by finish position

var vehicle_tscn := preload("res://assets/scenes/vehicle.tscn")

## Find area tied to checkpoint ID
func find_checkoint_area(id: int) -> Area3D:
	return checkpoint_areas[id] if id < checkpoint_areas.size() else null

## Checkpoint listener on server
func checkpoint_listener(vehicle: TrackVehicle, id: int):
	if winners.find(vehicle) >= 0:
		return	# do not keep laps/checkpoints of winner cars updated
	if id == 0 and vehicle.checkpoint_last == (checkpoint_size - 1):
		vehicle.lap_count += 1
		vehicle.checkpoint_last = id
		# send update to vehicle peer
		if vehicle.lap_count - 1 == lap_count:
			winners.push_back(vehicle)
			if winners.size() == min(3, GameController.players.size()):
				GameController.client_notify_race_wrapup.rpc()
			GameController.client_notify_race_finished.rpc_id(vehicle.get_multiplayer_authority())
		else:
			GameController.client_notify_lap_change.rpc_id(vehicle.get_multiplayer_authority(), vehicle.lap_count)
	if (id == (vehicle.checkpoint_last + 1)) or (id < vehicle.checkpoint_last):
		vehicle.checkpoint_last = id

## Powerup listener to change UI of powerup user
func powerup_listener(vehicle: TrackVehicle, type: Powerup.TYPE):
	GameController.client_notify_powerup_pickup.rpc_id(vehicle.get_multiplayer_authority(), type)

## Checkpoints
## stride: Distance entre deux checkpoints sur la courbe
func place_checkpoints(curve: Curve3D, c_stride: float) -> int:
	var walk: float = 0.0
	var id := 0
	while walk < curve.get_baked_length():
		var c_xform := curve.sample_baked_with_rotation(walk, true, true)
		var checkpoint: CheckpointArea = checkpoint_tscn.instantiate()
		level_nodes_root.add_child(checkpoint)
		checkpoint.level = self
		checkpoint.global_transform = c_xform * Transform3D(Basis(), Vector3.UP * 2.0)
		checkpoint.id = id
		checkpoint.checkpoint_reached.connect(checkpoint_listener)
		checkpoint_areas.push_back(checkpoint)
		walk += c_stride
		id += 1
	return id

## Inform clients of their position
func update_positions():
	var vehicles := get_tree().get_nodes_in_group(&"VehicleGroup")
	vehicles.sort_custom(func(a: TrackVehicle, b: TrackVehicle):
		return ((a.lap_count * checkpoint_size) + a.checkpoint_last) > ((b.lap_count * checkpoint_size) + b.checkpoint_last))
	for i in range(vehicles.size()):
		var v := vehicles[i] as TrackVehicle
		GameController.client_notify_position.rpc_id(v.get_multiplayer_authority(), i + 1)

func place_powerups():
	var powerup_tscn := preload("res://assets/scenes/powerup.tscn")
	for spawner in get_tree().get_nodes_in_group(&"PowerupSpawnNode"):
		var spawn_point := spawner as RayCast3D
		if spawn_point:
			spawn_point.force_raycast_update()
			if spawn_point.is_colliding():
				var powerup: Powerup = powerup_tscn.instantiate()
				powerup.powerup_id = spawn_point.get_meta("powerup_id", 0)
				replication_bin.add_child(powerup, true)
				powerup.global_position = spawn_point.get_collision_point()
				powerup.picked_up.connect(powerup_listener)

func add_to_replication(node: Node):
	replication_bin.add_child(node, true)

func vehicle_spawned(node: Node):
	if node is TrackVehicle:
		node.level = self
		node.camera_rig = camera_rig
		if multiplayer.is_server():
			var spawn_point: Node3D = get_tree().get_first_node_in_group(&"VehicleSpawnNode")
			if spawn_point:
				node.global_transform = spawn_point.global_transform
				spawn_point.remove_from_group(&"VehicleSpawnNode")
			replication_bin.add_child(node)
			node.add_to_group(&"VehicleGroup")
		node.set_multiplayer_authority(node.name.to_int())

func vehicle_spawns_hurdle(id: int):
	var veh: TrackVehicle = replication_bin.find_child(str(id), false, false)
	var path := Powerup.get_powerup_tscn(veh.powerup_id)
	if path == "":
		push_error("Player ", id, " tried to spawn invalid hurdle ", veh.powerup_id)
		return
	var hurdle_tscn := load(path)
	var hurdle: Node3D = hurdle_tscn.instantiate()
	hurdle.set("source_vehicle", veh)	# TODO: Godot needs interfaces!!!
	if hurdle is PathFollow3D:
		racetrack_path.add_child(hurdle, true)	# Path is a replicated tree
	else:
		replication_bin.add_child(hurdle, true)		# Replicated is the default replication root
	veh.powerup_id = -1	# revoke used powerup
	GameController.client_notify_powerup_pickup.rpc_id(veh.get_multiplayer_authority(), veh.powerup_id)

func setup_race():
	GameController.client_notify_race_ready.rpc()
	for k_id in GameController.players:
		var data := GameController.players[k_id]
		var veh: TrackVehicle = vehicle_tscn.instantiate()
		veh.name = str(k_id)
		veh.username = data["username"]
		veh.color = data["color"]
		vehicle_spawned(veh)
		# wait for clients to finish their countdown
		get_tree().create_timer(4.2).timeout.connect(func():
			veh.remote_allow_input.rpc_id(k_id, true)
		)

func peer_connected(id: int):
	GameController.client_request_connect_args.rpc_id(id)

## Response to signal GameController.player_joined on server
func peer_validated(id: int, username: String, color: Color):
	GameController.client_send_player_list.rpc(GameController.players)

func peer_disconnected(id: int):
	GameController.player_left.emit(id)
	var veh: TrackVehicle = replication_bin.find_child(str(id), false, false)
	if veh:
		veh.set_multiplayer_authority(multiplayer.get_unique_id())
		veh.queue_free()
	GameController.client_send_player_list.rpc(GameController.players)

## End race 20 seconds after placing the first 3 players.
var wrap_up_timer := 20.0

func _ready_music():
	if music:
		music.play()

## Restart the scene for everyone, hopefully not breaking everything...
func _restart():
	GameController.client_restart.rpc()
	get_tree().reload_current_scene()

func _ready() -> void:
	GameController.current_level = self
	GameController.race_ready.connect(_ready_music)
	
	if GameController.server:
		if not GameController.has_peer(): #< Only thing that can persist between loads
			# Initialize server
			if not GameController.init_server():
				return
		
		if racetrack_path:
			checkpoint_size = place_checkpoints(racetrack_path.curve, 40.0)
		place_powerups.call_deferred()
		
		multiplayer.peer_connected.connect(peer_connected)
		multiplayer.peer_disconnected.connect(peer_disconnected)
		
		GameController.client_hurdle_request.connect(vehicle_spawns_hurdle)
		GameController.player_joined.connect(peer_validated)
		GameController.race_ready.connect(setup_race, CONNECT_ONE_SHOT)
		
		# Force server to do its own initialization
		multiplayer.peer_connected.emit(1)
	else:
		#await get_tree().create_timer(1).timeout
		spawner.spawned.connect(vehicle_spawned)
		
		if not GameController.has_peer(): #< Only thing that can persist between loads
			GameController.init_client()

## Race message loop
func _physics_process(delta: float) -> void:
	if GameController.server:
		update_positions()
	
		if GameController.players.size() and (winners.size() >= min(3, GameController.players.size())):
			wrap_up_timer -= delta
			if wrap_up_timer <= 0:
				_restart()
