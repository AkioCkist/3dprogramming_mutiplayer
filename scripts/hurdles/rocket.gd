extends PathFollow3D
class_name HurdleRocket

@export var speed_us := 30.0
@export var lifetime := 5.0
@onready var path: Path3D = GameController.current_level.racetrack_path
@onready var curve := path.curve
@onready var rocket: Area3D = %RocketArea

var source_vehicle: TrackVehicle
var curve_offset := 0.0

static var explosion_tscn := preload("res://assets/scenes/explosion.tscn")

func explode():
	var explosion: Node3D = explosion_tscn.instantiate()
	GameController.current_level.add_to_replication(explosion)
	explosion.global_position = rocket.global_position
	queue_free()

## Initialize path data here
func _ready() -> void:
	if multiplayer.is_server():
		curve_offset = curve.get_closest_offset(source_vehicle.global_position)
		progress = curve_offset
		rocket.global_position = source_vehicle.global_position

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		lifetime -= delta
		if lifetime <= 0.0:
			explode()
			return
			
		# test for impacts
		for body in %RocketArea.get_overlapping_bodies():
			if body is TrackVehicle and body != source_vehicle:
				explode()
				return
		
		# or if it still has to continue
		var travel := speed_us * delta
		curve_offset = fmod(curve_offset + travel, curve.get_baked_length())
		var new_xform := curve.sample_baked_with_rotation(curve_offset, true, false)
		var offset := new_xform.origin - global_position
		global_basis = Basis.looking_at(offset)
		progress = curve_offset
