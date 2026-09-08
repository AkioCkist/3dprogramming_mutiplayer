extends Node3D
## A powerup provides a player with a "hurdle" they can place down (or fire).
class_name Powerup

var powerup_array := preload("res://assets/textures/powerup_array.png")

enum TYPE {
	OIL_SPILL,
	ROCKET
}

static var powerup_scenes: Array[String] = [
	"res://assets/scenes/oil_spill_area.tscn",
	"res://assets/scenes/hurdle_rocket.tscn"]

static func get_powerup_tscn(id: int) -> String:
	if id >= powerup_scenes.size() or id < 0:
		return ""
	return powerup_scenes[id]

@export var powerup_id := 0:
	set(pid):
		assert(pid < powerup_array.get_layers(), "Power-up must be a valid image in sheet.")
		%Sprite.set_instance_shader_parameter(&"sprite_index", pid)
		powerup_id = pid

## Timeout before reappearing
@export var timeout_sec := 8.0

## Emitted on the server when a powerup was picked up
signal picked_up(vehicle: TrackVehicle, type: TYPE)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func respawn():
	visible = true

# Cosmetic rotation effect of container.
func _process(delta: float) -> void:
	if visible:
		%Container.rotate_y(delta * 2.0)

## Should be a server signal
func _on_powerup_area_body_entered(body: Node3D) -> void:
	if multiplayer.is_server() and (body is TrackVehicle) and visible:
		body.powerup_id = powerup_id
		visible = false
		picked_up.emit(body, powerup_id)
		get_tree().create_timer(timeout_sec).timeout.connect(respawn)

## Not visible means someone picked it up
func _on_visibility_changed() -> void:
	if not visible:
		%PickupPlayer.play()
