extends Node
class_name DemoRecorderClass

## Filename being recorded or empty
var is_recording := ""

## Filename being played back or empty
var is_playing := ""

## Recording or playback frame
var frame := 0

## Total frames recorded or imported for playback
var input_frames := []

func _ready() -> void:
	pass

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("demo_input"):
		# Movie mode: we want playback
		#if OS.has_feature("movie"):
		var args := OS.get_cmdline_user_args()
		if args.size():
			frame = 0
			is_playing = "user://" + args.get(0)
			var fa := FileAccess.open(is_playing, FileAccess.READ)
			if FileAccess.get_open_error() == OK:
				input_frames = fa.get_var(true)
				fa.close()
			print("Playing back file %s." % is_playing)
		if is_playing == "": # no cmdline path, so no playback
			if is_recording == "":
				frame = 0
				is_recording = "user://demo_" + Time.get_datetime_string_from_system().replace(":", "") + ".rec"
				print("Recording in %s..." % is_recording)
			else:
				if is_recording != "":
					var fa := FileAccess.open(is_recording, FileAccess.WRITE)
					if FileAccess.get_open_error() == OK:
						fa.store_var(input_frames, true)
						fa.close()
					print("Dumped recording in %s." % is_recording)
					is_recording = ""
		get_viewport().set_input_as_handled()
	
	if is_recording != "":
		if input_frames.size() <= frame:
			input_frames.resize(frame + 1)
			input_frames[frame] = []
		var frame_array: Array = input_frames[frame]
		frame_array.push_back(event)

func _physics_process(_delta: float) -> void:
	if is_recording != "":
		frame += 1
		
	if (is_playing != "") and (frame < input_frames.size()):
		if input_frames[frame]:
			for input_frame in input_frames[frame]:
				Input.parse_input_event(input_frame)
		frame += 1
