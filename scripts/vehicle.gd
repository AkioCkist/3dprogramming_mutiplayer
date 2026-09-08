extends VehicleBody3D
class_name TrackVehicle

@export_group("Vehicle settings")
@export var TOP_SPEED := 3000.0		## Top speed achievable by the vehicle engine
@export var TRIP_TIME := 3.5		## Time before getting placed back to a past checkpoint
@export var username := "Player":
	set(val):
		if is_node_ready(): %UsernameLabel.text = val
		username = val

@export var color := Color.WHITE:
	set(val):
		if is_node_ready():
			var mat: StandardMaterial3D = $CollisionShape3D/vehicle_hull/hull_mesh.get_surface_override_material(0)
			mat.albedo_color = val
			%UsernameLabel.modulate = val
		color = val

@export_group("Level Configuration")
@export var level: RaceLevel
@export var camera_rig: SpringArm3D = null
@export var camera_height := 1.5

# Variables managed by SERVER ONLY
var lap_count := 1
var checkpoint_last := 0
var powerup_id := -1

var trip_timer := 0.0
var input_steering := 0.0
var input_torque := 0.0
var reference_fov := 80.0
var physics_damp: float = ProjectSettings.get_setting("physics/3d/default_linear_damp")

var correct_camera := true	# arbitrarily disallow camera fixing, namely when the car spins
var input_allowed := false
var wheels: Array[Node] = []

## Vehicle has authority, so the server must *ask* the remote vehicle to flip and replicate...
@rpc("any_peer", "call_local", "reliable")
func remote_restore_vehicle(at: Transform3D):
	global_transform = at
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

## Again, but for impulse
@rpc("any_peer", "call_local", "reliable")
func remote_center_impulse(at: Vector3):
	apply_central_impulse(at)
	apply_torque_impulse(at)

## Again, but for drifting for a small amount of time
@rpc("any_peer", "call_local", "reliable")
func remote_drift(disabled_secs: float):
	var saved_friction: Dictionary[String, float] = {}
	for wheel in wheels:
		saved_friction.set(str(wheel.get_instance_id()), wheel.wheel_friction_slip)
	for wheel in wheels:
		wheel.wheel_friction_slip = 0.1
	correct_camera = false
	input_allowed = false
	apply_torque_impulse(Vector3.UP * 2000.0)
	%SquealPlayer.play()
	get_tree().create_timer(disabled_secs).timeout.connect(func():
		for wheel in wheels:
			wheel.wheel_friction_slip = saved_friction[str(wheel.get_instance_id())]
		correct_camera = true
		input_allowed = true
	)

## Again, but for input requests
@rpc("any_peer", "call_local", "reliable")
func remote_allow_input(allow: bool):
	input_allowed = allow

## Again, but to remove the vehicle during intermissions
@rpc("any_peer", "call_local", "reliable")
func remote_remove():
	queue_free()

## Test if the vehicle is flying
func is_flying() -> bool:
	return wheels.all(func(wheel: VehicleWheel3D): return !wheel.is_in_contact())

## Follow car and let speed affect FOV
func fix_camera(delta: float):
	if is_multiplayer_authority():
		# stabilize camera
		if correct_camera:
			camera_rig.rotation.x = PI * -0.1
			camera_rig.global_rotation.y = lerp_angle(camera_rig.global_rotation.y, global_rotation.y, delta * 10.0)
		camera_rig.global_position = global_position + Vector3(0, camera_height, 0)
		var camera := get_viewport().get_camera_3d()
		
		# FOV
		var top_velocity := (TOP_SPEED / physics_damp) * 0.001
		camera.fov = lerpf(reference_fov, reference_fov + 20.0, linear_velocity.length() / top_velocity)

func _post_ready():
	if is_multiplayer_authority():
		%UsernameLabel.visible = false
		GameController.race_finished.connect(func():
			remote_allow_input(false)
		)
	else:
		%UsernameLabel.text = username
	color = color

var collision_sound := preload("res://assets/sounds/veh_hardimpact.wav")

## For now just play an impact noise
func _colliding(_body: Node):
	if linear_velocity.length_squared() > 2.0:
		var vol := clampf(linear_velocity.length() * 0.005, 0.0, 1.0)
		var pitch := clampf(1.0 - absf(linear_velocity.normalized().dot(Vector3.UP)), 0.1, 2.0)
		SoundManager.play_managed(collision_sound, global_position, vol, pitch)

func _ready() -> void:
	body_entered.connect(_colliding)
	
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = %CenterOfMassDummy.position
	reference_fov = get_viewport().get_camera_3d().fov
	
	var search_wheels := get_children()
	wheels = search_wheels.filter(func(child): return child is VehicleWheel3D)
	
	# pre-simulate camera
	for tick in range(10):
		fix_camera(0.1)
	
	_post_ready.call_deferred()

func _process(_delta: float) -> void:
	%EnginePlayer.pitch_scale = clampf(linear_velocity.length() / ((TOP_SPEED / physics_damp) * 0.0005), 0.1, 2.0)
	%EnginePlayer.volume_linear = clampf(engine_force / TOP_SPEED, 0.2, 1.0)

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var vec := Input.get_vector(&"ui_left", &"ui_right", &"ui_down_vehicle", &"ui_up_vehicle") if input_allowed else Vector2.ZERO
		if is_flying():
			var projection := Projection(global_transform)
			var local_vec := (projection * Vector4(vec.y, 0.0, vec.x, 0.0)) * 2.0
			angular_velocity.x += local_vec.x * delta
			angular_velocity.y += local_vec.y * delta
			angular_velocity.z += local_vec.z * delta
		else:
			if abs(vec.x) > 0.0:
				input_steering = lerpf(input_steering, 1.0 * vec.x, delta)
			else:
				input_steering = move_toward(input_steering, 0.0, delta)
			input_torque = move_toward(input_torque, vec.y * (TOP_SPEED if (abs(vec.y) > 0.0) else 0.0), delta * 8000.0)
			engine_force = input_torque
			steering = -input_steering
			
		if Input.is_action_just_pressed(&"ui_accept"):
			GameController.server_spawn_hurdle.rpc_id(1)
		
	# stabilisation cam
	fix_camera(delta)
	
	# trip detection and rollback
	if multiplayer.is_server():
		if position.y < -5.0:
			trip_timer = -1.0	# simulate trip recovery if the vehicle fell out of the track
		if global_basis.y.dot(Vector3.UP) < 0.1:
			trip_timer -= delta
		else:
			trip_timer = TRIP_TIME
		if trip_timer < 0.0:
			var checkpoint := level.find_checkoint_area(checkpoint_last)
			trip_timer = TRIP_TIME
			remote_restore_vehicle.rpc_id(name.to_int(), checkpoint.global_transform)
	
	# debug
	#var path := level.racetrack_path
	#print("Offset: ", path.curve.get_closest_offset(global_position))
