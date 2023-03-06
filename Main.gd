extends Control

onready var player = $AudioStreamPlayer
onready var oscilloscope = $VBoxContainer/Oscilloscope
onready var debug = $DEBUG

var notes = [
	27.50,
	29.14,
	30.87,
	32.70,
	34.65,
	36.71,
	38.89,
	41.20,
	43.65,
	46.25,
	49.00,
	51.91,
	55.00,
	58.27,
	61.74,
	65.41,
	69.30,
	73.42,
	77.78,
	82.41,
	87.31,
	92.50,
	98.00,
	103.83,
	110.00,
	116.54,
	123.47,
	130.81,
	138.59,
	146.83,
	155.56,
	164.81,
	174.61,
	185.00,
	196.00,
	207.65,
	220.00,
	233.08,
	246.94,
	261.63,
	277.18,
	293.66,
	311.13,
	329.63,
	349.23,
	369.99,
	392.00,
	415.30,
	440.00,
	466.16,
	493.88,
	523.25,
	554.37,
	587.33,
	622.25,
	659.26,
	698.46,
	739.99,
	783.99,
	830.61,
	880.00,
	932.33,
	987.77,
	1046.50,
	1108.73,
	1174.66,
	1244.51,
	1318.51,
	1396.91,
	1479.98,
	1567.98,
	1661.22,
	1760.00,
	1864.66,
	1975.53,
	2093.00,
	2217.46,
	2349.32,
	2489.02,
	2637.02,
	2793.83,
	2959.96,
	3135.96,
	3322.44,
	3520.00,
	3729.31,
	3951.07,
	4186.01,
	4434.92,
	4698.64,
	4978.03
]

var playback : AudioStreamPlayback = null

var sample_hz = 48000.0
var time_domain_hz = int( floor( sample_hz / 128 ) ) # refresh once per second?
var time_domain_pointer = 0
var pulse_hz = 440.0
var phase = 0.0

var c_four = 440.0

var ratio = 1
var depth = 0.0

var amplitude = 1.0
var attack = 0.01
var release = 0.5
var amplitude_at_release = 1.0
var envelope_time = 0.0
var note_on = false

var filter_cutoff = 0.9
var filter_resonance = 0.1
var filter_previous_sample = 0.0

var filter_omega = 0.0
var filter_cos = 0.0
var filter_sin = 0.0
var filter_alpha = 0.0
var filter_a0 = 0.0

var filter_a1 = 0.0
var filter_a2 = 0.0
var filter_b0 = 1.0
var filter_b1 = 1.0
var filter_b2 = 2.0
var filter_gain = 1.0

var filter_ha1 = 0.0
var filter_ha2 = 0.0
var filter_hb1 = 0.0
var filter_hb2 = 0.0

var filter_pole_one = 0.0
var filter_pole_two = 0.0

var lfo_depth = 0.0
var lfo_frequency = 1.0
var lfo_t = 0.0

var history = ""
var history2 = ""

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
				amplitude = pow( envelope_time / attack, 2 )
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

		output = filter( output )

		time_domain_pointer += 1
		if time_domain_pointer % time_domain_hz == 0:
			if time_domain_pointer >= 128 * time_domain_hz:
				time_domain_pointer = 0
			frame_history[ int( time_domain_pointer / time_domain_hz ) ] = output
			amplitude_history[ int( time_domain_pointer / time_domain_hz ) ] = amplitude
			
		playback.push_frame( amplitude * Vector2.ONE * output )
		phase = fmod( phase + increment, 1.0 )
		to_fill -= 1

func set_filter_coefficients():
	filter_omega = TAU * filter_cutoff
	filter_cos = cos( filter_omega )
	filter_sin = sin( filter_omega )
	filter_alpha = filter_sin / ( 2 * filter_resonance )
	filter_a0 = 1.0 + filter_alpha
	
	filter_b0 = ( (1.0 - filter_cos) / 2.0 ) / filter_a0
	filter_b1 = ( 1.0 - filter_cos ) / filter_a0
	filter_b2 = ( (1.0 - filter_cos) / 2.0 ) / filter_a0
	filter_a1 = ( -2.0 * filter_cos ) / filter_a0
	filter_a2 = ( 1.0 - filter_alpha ) / filter_a0
	
##	"PEAK" filter ??
#	var tmpgain = 1.5
#	filter_b0 = (1.0 + filter_alpha * tmpgain);
#	filter_b1 = (-2.0 * filter_cos);
#	filter_b2 = (1.0 - filter_alpha * tmpgain);
#	filter_a1 = -2 * filter_cos;
#	filter_a2 = (1 - filter_alpha / tmpgain);

func filter( value ):
	var pre = value
	value = clamp( value * filter_b0 + filter_hb1 * filter_b1 + filter_hb2 * filter_b2 + filter_a1 * filter_ha1 + filter_a2 * filter_ha2, -1, 1 )
	filter_ha2 = filter_ha1
	filter_hb2 = filter_hb1
	filter_hb1 = pre
	filter_ha1 = value
	return value

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
	for i in range(0, 128):
		frame_history.push_back(0.0)
		amplitude_history.push_back(0.0)
	set_filter_coefficients()

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
	pulse_hz = notes[ value - 21 ]

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

func _on_Cutoff_value_changed(value):
	var sr_limit = sample_hz / 2 + 512
	if value > sr_limit:
		value = sr_limit
	if value < 1:
		value = 1
	filter_cutoff = value / sample_hz
	set_filter_coefficients()

func _on_Resonance_value_changed(value):
	filter_resonance = value
	set_filter_coefficients()
