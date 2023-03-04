extends Control

onready var player = $AudioStreamPlayer
onready var oscilloscope = $VBoxContainer/Oscilloscope

var playback : AudioStreamPlayback = null

var sample_hz = 24000.0
var pulse_hz = 440.0
var phase = 0.0

var c_four = 440.0

var ratio = 1
var depth = 0.0

var amplitude = 1.0
var attack = 0.01
var release = 0.01
var envelope_time = 0.0
var note_on = false

var lfo_depth = 0.0
var lfo_frequency = 1.0
var lfo_t = 0.0

onready var spectrum : AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(0,0)

const WIDTH = 128
const HEIGHT = 32
const VU_COUNT = 128
const FREQ_MAX = 11050.0
const MIN_DB = 60

func _fill_buffer():
	var increment = pulse_hz / sample_hz
	
	var to_fill = playback.get_frames_available()
	while to_fill > 0:
		playback.push_frame( amplitude * Vector2.ONE * sin( phase * TAU + depth * ( 1 + lfo_depth * sin( lfo_t ) ) * sin( ratio * phase * TAU ) ) )
		phase = fmod( phase + increment, 1.0 )
		to_fill -= 1

func _physics_process(delta):
	lfo_t += delta * lfo_frequency

	if note_on:
		envelope_time += delta
		if envelope_time <= attack:
			amplitude = envelope_time / attack # linear attack so far...
		else:
			amplitude = 1.0
	
	if player.playing:
		update()
		if not note_on:
			envelope_time += delta
			if envelope_time > release:
				player.stop()
			amplitude = 1 - ( envelope_time / release )
	
	_fill_buffer()

func _draw():
	var w = WIDTH / VU_COUNT
	var prev_hz = 0
	for i in range(1, VU_COUNT + 1):
		var hz = i * FREQ_MAX  / VU_COUNT
		var magnitude : float = spectrum.get_magnitude_for_frequency_range( prev_hz, hz ).length()
		var energy = clamp((MIN_DB + linear2db( magnitude )) / MIN_DB, 0, 1 )
		var height = energy * HEIGHT
		draw_rect( Rect2( w * i, 96 + HEIGHT - height, w, height), Color.white )
		prev_hz = hz
	
func _ready():
	player.stream.mix_rate = sample_hz
	playback = player.get_stream_playback()
	_fill_buffer()
#	player.play()

func _on_RatioSlider_value_changed(value):
	ratio = value

func _on_DepthSlider_value_changed(value):
	depth = value

func _on_NoteSlider_value_changed(value):
	var octave = int( floor( value / 12 ) )
	var nt = value - 12 * floor( value / 12 )
	pulse_hz = 440 * pow( 2, octave ) * ( 1 + nt / 12 )

func _on_LFO_Depth_value_changed(value):
	lfo_depth = value

func _on_LFO_Frequency_value_changed(value):
	lfo_frequency = value

func _on_Button_toggled(button_pressed):
	if button_pressed:
		player.play()
	else:
		player.stop()

func _on_Attack_value_changed(value):
	attack = value

func _on_Button_button_down():
	envelope_time = 0.0
	note_on = true
	amplitude = 0.0
	player.play()

func _on_Button_button_up():
	envelope_time = 0.0
	note_on = false

func _on_Release_value_changed(value):
	release = value
