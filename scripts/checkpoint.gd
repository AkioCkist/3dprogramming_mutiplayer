extends Area3D
class_name CheckpointArea

## ID du checkpoint pour déterminer l'ordre
@export var id := 0

## Manager
@export var level: RaceLevel

signal checkpoint_reached(vehicle: TrackVehicle, id: int)

## Should be a server signal (no need to check, checkpoints only exist on the serverside!)
func vehicle_entered(body: Node3D):
	if body is TrackVehicle:
		checkpoint_reached.emit(body, id)

func _ready() -> void:
	body_entered.connect(vehicle_entered)
