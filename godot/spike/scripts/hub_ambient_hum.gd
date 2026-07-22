## Fill AudioStreamGenerator with a soft hangar hum (procedural, no asset file).
extends Node

var player: AudioStreamPlayer = null
var _phase := 0.0
var _phase2 := 0.0


func _process(_delta: float) -> void:
	"""Push stereo frames while the generator buffer has room."""
	if player == null or not player.playing:
		return
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var rate := 22050.0
	var to_fill := playback.get_frames_available()
	if to_fill <= 0:
		return
	for _i in range(to_fill):
		_phase += 55.0 * TAU / rate
		_phase2 += 110.0 * TAU / rate
		if _phase > TAU:
			_phase -= TAU
		if _phase2 > TAU:
			_phase2 -= TAU
		var s := 0.045 * sin(_phase) + 0.025 * sin(_phase2)
		playback.push_frame(Vector2(s, s))
