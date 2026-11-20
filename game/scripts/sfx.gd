extends Node
## Tiny synthesised sound effects, so Rico needs no audio files.

const RATE := 22050

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_sounds["ping"] = _make(0.32, func(i, tt):
		var f: float = 2300.0 - 900.0 * tt / 0.32
		var env: float = exp(-tt * 14.0)
		return (sin(TAU * f * tt) * 0.6 + sin(TAU * f * 2.01 * tt) * 0.25) * env + (randf() * 2 - 1) * exp(-tt * 120.0) * 0.5)
	_sounds["thud"] = _make(0.18, func(i, tt):
		return sin(TAU * (120.0 - 300 * tt) * tt) * exp(-tt * 22.0) * 0.9)
	_sounds["pop"] = _make(0.09, func(i, tt):
		return sin(TAU * (500.0 + 2400.0 * tt) * tt) * exp(-tt * 40.0) * 0.6)
	_sounds["alert"] = _make(0.5, func(i, tt):
		var f: float = 880.0 if tt < 0.12 else (1175.0 if tt < 0.24 else 1568.0)
		return signf(sin(TAU * f * tt)) * 0.18 * exp(-fmod(tt, 0.12) * 10.0))
	_sounds["start"] = _make(0.16, func(i, tt):
		return sin(TAU * (600.0 + 900.0 * tt / 0.16) * tt) * 0.4 * exp(-tt * 10.0))
	_sounds["stop"] = _make(0.16, func(i, tt):
		return sin(TAU * (1500.0 - 900.0 * tt / 0.16) * tt) * 0.4 * exp(-tt * 10.0))
	for i in 3:
		var bl := 0.05
		var pitch := 380.0 + i * 120.0
		_sounds["blip%d" % i] = _make(bl, func(_i, tt):
			return (1.0 if sin(TAU * pitch * tt) > 0 else -1.0) * 0.12 * (1.0 - tt / bl))
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _make(length: float, fn: Callable) -> AudioStreamWAV:
	var n := int(length * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := clampf(fn.call(i, float(i) / RATE), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32000))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s


func play(name: String, pitch := 1.0, vol := 1.0) -> void:
	var master := float(Cfg.g("volume", 0.6))
	if master <= 0.01 or not _sounds.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sounds[name]
			p.pitch_scale = pitch
			p.volume_db = linear_to_db(master * vol)
			p.play()
			return
