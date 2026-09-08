extends Area3D
class_name ExplosionArea

@export var FORCE_NEWTONS := 6000.0

func ready_callback():
	#set_multiplayer_authority(multiplayer.get_unique_id())
	if is_multiplayer_authority():
		%AudioStreamPlayer3D.finished.connect(queue_free)
	%ParticlesExp.restart()
	
	# Animate shockwave
	%ShockwaveMesh.scale = Vector3(0.01, 0.01, 0.01)
	var tween := create_tween()
	tween.tween_property(%ShockwaveMesh, "scale", Vector3.ONE, 1.0)
	tween.parallel().tween_property(%ShockwaveMesh, "instance_shader_parameters/alpha_mod", 0.0, 1.0)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	ready.connect(ready_callback)

## applies an explosion with a quadratic function where the roots are controlled
## by pow(radius, 2.0) such that they are always placed at -radius and radius.
## basically 1 - (x*x)/(r*r) where x is linear distance and r is sphere radius.
func _physics_process(delta: float) -> void:
	if monitoring:
		var sphere: SphereShape3D = %CollisionShape3D.shape
		var radius := sphere.radius
		
		for body in get_overlapping_bodies():
			if body is TrackVehicle:
				var vec := body.global_position - global_position
				var vlen := clampf(1.0 - (vec.length_squared() / pow(radius, 2.0)), 0.0, INF)
				body.remote_center_impulse.rpc_id(body.name.to_int(), vec.normalized() * vlen * FORCE_NEWTONS)
		monitoring = false
