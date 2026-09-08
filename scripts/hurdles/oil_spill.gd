extends Area3D
class_name OilSpillArea

## Long timeout so it persists a bit
const TIMEOUT := 20.0

## Implicit hurdle interface
var source_vehicle: TrackVehicle

func _despawn():
	var tween := create_tween()
	tween.tween_property(%Decal, "scale", Vector3.ONE * 0.001, 0.5).finished.connect(func():
		if is_multiplayer_authority():
			queue_free()
		)

## Initialize path data here
func _ready() -> void:
	%SpillPlayer.play()
	if multiplayer.is_server():
		global_position = source_vehicle.global_position
	
	get_tree().create_timer(TIMEOUT).timeout.connect(_despawn)

## Vehicle entered
func _on_body_entered(body: Node3D) -> void:
	if (body is TrackVehicle) and (body != source_vehicle) and is_multiplayer_authority():
		body.remote_drift.rpc_id(body.get_multiplayer_authority(), 1.5)
		queue_free()

## Revoke source vehicle
func _on_body_exited(body: Node3D) -> void:
	if is_multiplayer_authority() and (source_vehicle == body):
		source_vehicle = null
