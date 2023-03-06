extends Control

onready var player = $AudioStreamPlayer
onready var oscilloscope = $VBoxContainer/Oscilloscope
onready var debug = $DEBUG

var playback : AudioStreamPlayback = null

var sample_hz = 48000.0
var pulse_hz = 440.0
var phase = 0.0

var c_four = 440.0

var ratio = 1
var depth = 0.0

var amplitude = 1.0
var attack = 0.01
var release = 0.01
var amplitude_at_release = 1.0
var envelope_time = 0.0
var note_on = false

var lfo_depth = 0.0
var lfo_frequency = 1.0
var lfo_t = 0.0

enum DRAW_MODES {
	FREQUENCY,
	WAVE,
	AMPLITUDE
}
var draw_mode = 0
var frame_history = []
var amplitude_history = []

onready var spectrum : AudioEffectSpectrumAnalyzerInstance = AudioServer.get_bus_effect_instance(0,0)
onready var sample_length = 1.0 / sample_hz

const WIDTH = 128
const HEIGHT = 32
const VU_COUNT = 128
const FREQ_MAX = 11050.0
const MIN_DB = 60

func _fill_buffer():
	var increment = pulse_hz / sample_hz

	var to_fill = playback.get_frames_available()
	var output = 1

	while to_fill > 0:
		if note_on:
			if envelope_time < attack:
				amplitude = pow( envelope_time / attack, 2 ) # linear attack so far...
			else:
				amplitude = 1.0
			envelope_time += sample_length
		
		if not note_on:
			amplitude = amplitude_at_release * pow( envelope_time / release, 2 ) - 2 * ( envelope_time / release ) + 1
			envelope_time += sample_length
			if envelope_time > release:
				amplitude = 0.0
				amplitude_at_release = 0.0
				player.stop()
		
		lfo_t += sample_length * lfo_frequency
		output = sin( phase * TAU + depth * ( 1 + lfo_depth * sin( lfo_t ) ) * sin( ratio * phase * TAU ) )
		
		if to_fill % 1920 == 0:
			frame_history.push_back( output )
			if frame_history.size() > 128:
				frame_history.pop_front()

		if to_fill % 960 == 0:
			amplitude_history.push_back( amplitude )
			if amplitude_history.size() > 128:
				amplitude_history.pop_front()
			
		playback.push_frame( amplitude * Vector2.ONE * output )
		phase = fmod( phase + increment, 1.0 )
		to_fill -= 1

func _physics_process(delta):
	if player.playing:
		_fill_buffer()
	debug.text = str(Engine.get_frames_per_second())
	update()

func _draw():
	if draw_mode == DRAW_MODES.FREQUENCY:
		var w = WIDTH / VU_COUNT
		var prev_hz = 0
		for i in range(1, VU_COUNT + 1):
			var hz = i * FREQ_MAX  / VU_COUNT
			var magnitude : float = spectrum.get_magnitude_for_frequency_range( prev_hz, hz ).length()
			var energy = clamp((MIN_DB + linear2db( magnitude )) / MIN_DB, 0, 1 )
			var height = energy * HEIGHT
			draw_rect( Rect2( w * i, 96 + HEIGHT - height, w, height), Color.white )
			prev_hz = hz
	elif draw_mode == DRAW_MODES.AMPLITUDE:
		for i in range( 0, 128 ):
			if amplitude_history.size() > i:
				var height = amplitude_history[i] * 32
				draw_rect( Rect2( i, 128 - height, 1, height ), Color.white )
	elif draw_mode == DRAW_MODES.WAVE:
		for i in range( 0, 128 ):
			if frame_history.size() > i:
				var height = frame_history[i] * 32
				draw_rect( Rect2( i, 128 - height, 1, height ), Color.white )
	
func _ready():
	player.stream.mix_rate = sample_hz
	playback = player.get_stream_playback()
	OS.open_midi_inputs()

func _input( input_event ):
	if input_event is InputEventMIDI:
		if input_event.message == 9:
			note_start( input_event.pitch )
		elif input_event.message == 8:
			note_end()

func note_start( pitch : int ):
	set_pulse_hz( pitch )
	envelope_time = 0.0
	note_on = true
#	amplitude = 0.0
	player.stop()
	playback = player.get_stream_playback()
	_fill_buffer()
	player.play()
	
func note_end():
	envelope_time = 0.0
	amplitude_at_release = amplitude
	note_on = false

func set_pulse_hz( value : int  ):
	value = value - 48
	var octave = int( floor( value / 12 ) )
	var nt = value - 12 * floor( value / 12 )
	pulse_hz = 440 * pow( 2, octave ) * ( 1 + nt / 12 )

func _on_RatioSlider_value_changed(value):
	ratio = value

func _on_DepthSlider_value_changed(value):
	depth = value

func _on_NoteSlider_value_changed(value):
	set_pulse_hz( value )
	
func _on_LFO_Depth_value_changed(value):
	lfo_depth = value

func _on_LFO_Frequency_value_changed(value):
	lfo_frequency = value

func _on_Attack_value_changed(value):
	attack = value

func _on_Button_button_down():
	note_start( 48 )

func _on_Button_button_up():
	note_end()

func _on_Release_value_changed(value):
	release = value

func _on_Oscilloscope_gui_input(event):
	if event is InputEventMouseButton:
		draw_mode = ( draw_mode + 1 ) % 3
