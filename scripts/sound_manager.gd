extends Node
class_name SoundManagerClass

## Play sound once in the scene with an auto deleting source
func play_managed(stream: AudioStream, pos: Vector3, vol := 1.0, pitch := 1.0, maxdist := 10.0):
	var emitter = AudioStreamPlayer3D.new()
	emitter.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	emitter.stream = stream
	emitter.position = pos
	emitter.volume_db = linear_to_db(vol)
	emitter.pitch_scale = pitch
	emitter.bus = &"SFX"
	emitter.max_distance = maxdist
	get_tree().root.add_child(emitter)
	emitter.play()
	
	var dtimer = get_tree().create_timer(stream.get_length() * (1.0 / pitch))
	dtimer.timeout.connect(func(): emitter.queue_free())
	return emitter

func set_master_volume(vol_l: float):
	AudioServer.set_bus_volume_linear(0, vol_l)

func _ready() -> void:
	get_window().focus_entered.connect(set_master_volume.bind(1.0))
	get_window().focus_exited.connect(set_master_volume.bind(0.0))
