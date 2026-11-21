extends Node
## Rico's real voice: an expressive offline speech model (Orpheus 3B, run by llama.cpp
## on the graphics card via Vulkan) streams sound codes, which rico_voice.exe turns
## into audio, pitches into his cartoon voice and sends back. Everything is local.

signal download_progress(percent: int)
signal download_done(ok: bool)
signal state_changed

const MODEL_FILE := "orpheus-3b-0.1-ft-Q4_K_M.gguf"
const MODEL_URL := "https://huggingface.co/unsloth/orpheus-3b-0.1-ft-GGUF/resolve/main/orpheus-3b-0.1-ft-Q4_K_M.gguf"
const MODEL_BYTES := 2092569120
const LLM_PORT := 8767
const DEC_PORT := 8768
const SPEAKER := "dan"
const RATE := 24000.0
const TAGS := ["laugh", "chuckle", "sigh", "groan", "yawn", "gasp", "cough", "sniffle"]

var downloading := false
var playing := false          # sound is coming out right now
var in_game := Callable()     # set by main: returns true while a game/fullscreen app is up

var _llm_pid := -1
var _dec_pid := -1
var _llm_ok := false
var _dl: HTTPRequest
var _health: HTTPRequest
var _dec := StreamPeerTCP.new()
var _dec_buf := PackedByteArray()
var _http := HTTPClient.new()
var _http_state := 0          # 0 idle, 1 connecting, 2 requesting, 3 reading
var _sse := ""
var _tok_count := 0
var _frame: Array[int] = []
var _queue: Array = []        # pending chunks: {text, temp}
var _cur := {}
var _utter := {}              # current utterance settings
var _player: AudioStreamPlayer
var _gen: AudioStreamGeneratorPlayback
var _pending_audio := PackedVector2Array()
var _pushed := 0              # frames pushed to the generator
var _levels := PackedFloat32Array()   # one loudness value per 480 frames pushed
var _dec_waiting := 0         # utterances sent to the decoder but not finished
var _drop_count := 0          # finished-utterance marks to wait for while discarding stale audio
var _cap := 0                 # generator buffer size in frames
var _noise: AudioStreamPlayer
var _idle := 0.0
var _starting := false
var _dump = null   # PackedVector2Array when RICO_VOICE_DUMP is set (dev testing)


func _ready() -> void:
	_health = HTTPRequest.new()
	_health.timeout = 3
	add_child(_health)
	_setup_bus()
	_player = AudioStreamPlayer.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 30.0
	_player.stream = g
	_player.bus = "RicoVoice"
	add_child(_player)
	_noise = AudioStreamPlayer.new()
	_noise.bus = "RicoVoice"
	add_child(_noise)
	if OS.has_environment("RICO_VOICE_DUMP"):
		_dump = PackedVector2Array()


func save_dump(path: String) -> void:
	if _dump == null:
		return
	var pcm := PackedByteArray()
	pcm.resize(_dump.size() * 2)
	for i in _dump.size():
		pcm.encode_s16(i * 2, int(clampf(_dump[i].x, -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + pcm.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer()); f.store_32(16); f.store_16(1); f.store_16(1)
	f.store_32(24000); f.store_32(48000); f.store_16(2); f.store_16(16)
	f.store_buffer("data".to_ascii_buffer()); f.store_32(pcm.size()); f.store_buffer(pcm)
	f.close()


func _setup_bus() -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "RicoVoice")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 80
	AudioServer.add_bus_effect(idx, hp)
	var shelf := AudioEffectHighShelfFilter.new()
	shelf.cutoff_hz = 6000
	AudioServer.add_bus_effect(idx, shelf)
	var echo := AudioEffectDelay.new()
	echo.dry = 1.0
	echo.tap1_active = true
	echo.tap1_delay_ms = 40
	echo.tap2_active = true
	echo.tap2_delay_ms = 95
	echo.feedback_active = false
	AudioServer.add_bus_effect(idx, echo)
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(idx, lim)
	apply_settings()


## Shimmer amount and volume from settings.
func apply_settings() -> void:
	var idx := AudioServer.get_bus_index("RicoVoice")
	if idx < 0:
		return
	var s := clampf(float(Cfg.g("voice_shimmer", 0.5)), 0.0, 1.0)
	var shelf: AudioEffectHighShelfFilter = AudioServer.get_bus_effect(idx, 1)
	shelf.gain = 1.0 + s * 0.5          # up to about +3.5 dB of sparkle
	var echo: AudioEffectDelay = AudioServer.get_bus_effect(idx, 2)
	echo.tap1_level_db = lerpf(-60.0, -18.0, s)
	echo.tap2_level_db = lerpf(-60.0, -25.0, s)
	var vol := clampf(float(Cfg.g("volume", 0.6)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.001, vol * 1.6)))


# ------------------------------------------------------------------ install

func base_dir() -> String:
	if OS.has_environment("RICO_VOICE_DIR"):   # dev testing
		return OS.get_environment("RICO_VOICE_DIR")
	return OS.get_executable_path().get_base_dir().path_join("voice")


func _bin(name: String) -> String:
	return base_dir().path_join(name + (".exe" if OS.get_name() == "Windows" else ""))


func model_path() -> String:
	if OS.has_environment("RICO_VOICE_MODEL"):
		return OS.get_environment("RICO_VOICE_MODEL")
	return OS.get_user_data_dir().path_join("voice").path_join(MODEL_FILE)


func installed() -> bool:
	return FileAccess.file_exists(model_path()) and FileAccess.file_exists(_bin("llama-server"))


func wanted() -> bool:
	return String(Cfg.g("voice_engine", "rico")) == "rico"


## True when the new voice should be used for this line.
func can_speak() -> bool:
	if not (wanted() and installed()):
		return false
	if in_game.is_valid() and bool(in_game.call()):
		return false
	return true


func download() -> void:
	if downloading or FileAccess.file_exists(model_path()):
		return
	DirAccess.make_dir_recursive_absolute(model_path().get_base_dir())
	downloading = true
	_dl = HTTPRequest.new()
	_dl.download_file = model_path() + ".part"
	_dl.download_chunk_size = 1 << 20
	add_child(_dl)
	_dl.request_completed.connect(func(result, code, _h, _b):
		downloading = false
		var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200
		if ok:
			DirAccess.rename_absolute(model_path() + ".part", model_path())
		else:
			DirAccess.remove_absolute(model_path() + ".part")
		_dl.queue_free()
		_dl = null
		download_done.emit(ok)
		state_changed.emit()
		if ok:
			warm_up())
	_dl.request(MODEL_URL)
	state_changed.emit()


func download_percent() -> int:
	if _dl == null:
		return 0
	var total := _dl.get_body_size()
	if total <= 0:
		total = MODEL_BYTES
	return int(100.0 * _dl.get_downloaded_bytes() / total)


func cancel_download() -> void:
	if _dl:
		_dl.cancel_request()
		_dl.queue_free()
		_dl = null
		downloading = false
		DirAccess.remove_absolute(model_path() + ".part")
		state_changed.emit()


func uninstall() -> void:
	stop_servers()
	DirAccess.remove_absolute(model_path())
	state_changed.emit()


# ------------------------------------------------------------------ servers

## Load the model ahead of time so his first line isn't slow.
func warm_up() -> void:
	if can_speak():
		_ensure_running()


func _ensure_running() -> void:
	if _starting:
		return
	_starting = true
	var dir := base_dir()
	if _dec_pid <= 0 or not OS.is_process_running(_dec_pid):
		_dec_pid = OS.create_process(_bin("rico_voice"), [dir.path_join("snac_decoder.onnx"), str(DEC_PORT)])
	if _llm_pid <= 0 or not OS.is_process_running(_llm_pid):
		_llm_ok = false
		var threads := clampi(OS.get_processor_count() - 2, 2, 12)
		var args := ["-m", model_path(), "--host", "127.0.0.1", "--port", str(LLM_PORT), "-c", "2048", "-t", str(threads)]
		if String(Cfg.g("voice_device", "gpu")) == "gpu":
			args += ["-ngl", "99"]
		else:
			args += ["-ngl", "0"]
		_llm_pid = OS.create_process(_bin("llama-server"), args)
	for i in 120:
		if _llm_ok and _dec.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		if not _llm_ok and _health.request("http://127.0.0.1:%d/health" % LLM_PORT) == OK:
			var r: Array = await _health.request_completed
			_llm_ok = r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200
		if _dec.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			if _dec.get_status() != StreamPeerTCP.STATUS_CONNECTING:
				_dec.disconnect_from_host()
				_dec.connect_to_host("127.0.0.1", DEC_PORT)
			_dec.poll()
		await get_tree().create_timer(0.5).timeout
		_dbg("start %d: llm_ok=%s dec=%d llm_pid=%d running=%s" % [i, _llm_ok, _dec.get_status(), _llm_pid, OS.is_process_running(_llm_pid)])
		if not _llm_ok and (_llm_pid <= 0 or not OS.is_process_running(_llm_pid)):
			break   # the speech server crashed (a leftover one that answers is fine too)
	_starting = false
	state_changed.emit()


func ready_now() -> bool:
	return _llm_ok and _dec.get_status() == StreamPeerTCP.STATUS_CONNECTED


## Free the graphics card (e.g. when a game starts).
func stop_servers() -> void:
	stop()
	if _dec.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_dec.put_data("Q".to_ascii_buffer())
	_dec.disconnect_from_host()
	for pid in [_llm_pid, _dec_pid]:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_llm_pid = -1
	_dec_pid = -1
	_llm_ok = false
	state_changed.emit()


func _exit_tree() -> void:
	stop_servers()


# ------------------------------------------------------------------ speaking

static func strip_tags(text: String) -> String:
	var re := RegEx.create_from_string("\\s*<(%s)>\\s*" % "|".join(TAGS))
	return re.sub(text, " ", true).strip_edges().replace("  ", " ")


## mood: Rico's face mood ("smug", "happy", "shock", "annoyed", "worried", "think", "sleep").
func speak(text: String, mood := "smug", glitch := false) -> void:
	stop()
	text = _clean(text)
	if text == "":
		return
	var d := _delivery(mood)
	if glitch and randf() < 0.6 and not "<" in text:
		text = "<sigh> " + text
	elif d.tag != "" and randf() < d.tag_chance and not "<" in text:
		text = d.tag + " " + text
	for c in _chunks(text):
		_queue.append({"text": c, "temp": d.temp, "tempo": d.tempo, "glitch": glitch})
	_dbg("speak: %d chunks, ready=%s starting=%s" % [_queue.size(), ready_now(), _starting])
	_idle = 0.0
	while _starting:
		await get_tree().create_timer(0.25).timeout
	if not ready_now():
		await _ensure_running()
		if not ready_now():
			_dbg("speak: servers not ready, giving up")
			_queue.clear()
			return
	_dbg("speak: go, queue=%d" % _queue.size())
	_next_chunk()


func _dbg(t: String) -> void:
	if _dump != null:
		print("VOICE " + t)


func stop() -> void:
	_queue.clear()
	if not _cur.is_empty() and _dec.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_dec.put_data(PackedByteArray([69]))   # close the open utterance
	_cur = {}
	if _http_state != 0:
		_http.close()
		_http_state = 0
	_drop_count = _dec_waiting   # throw away anything still on its way
	_pending_audio = PackedVector2Array()
	_player.stop()
	_gen = null
	_pushed = 0
	_levels = PackedFloat32Array()
	playing = false



## Short pre-made noises: hmm, pfft, heh, oi...
func noise(name: String) -> void:
	if playing or not wanted():
		return
	var path := "res://assets/noises/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	_noise.stream = load(path)
	_noise.play()


func level() -> float:
	if not playing or _gen == null:
		return -1.0
	var buffered := _cap - _gen.get_frames_available()
	var played := maxi(0, _pushed - buffered)
	var i := played / 480
	if i >= _levels.size():
		return 0.0
	return _levels[i]


func _delivery(mood: String) -> Dictionary:
	match mood:
		"happy":
			return {"temp": 0.75, "tempo": 1.07, "tag": "<laugh>", "tag_chance": 0.2}
		"shock":
			return {"temp": 0.75, "tempo": 1.1, "tag": "<gasp>", "tag_chance": 0.35}
		"annoyed":
			return {"temp": 0.65, "tempo": 1.02, "tag": "<groan>", "tag_chance": 0.3}
		"worried":
			return {"temp": 0.65, "tempo": 1.05, "tag": "<sigh>", "tag_chance": 0.2}
		"think":
			return {"temp": 0.6, "tempo": 0.96, "tag": "", "tag_chance": 0.0}
		"sleep":
			return {"temp": 0.6, "tempo": 0.9, "tag": "<yawn>", "tag_chance": 0.5}
		_:   # smug: dry and a touch slower
			return {"temp": 0.7, "tempo": 0.97, "tag": "<chuckle>", "tag_chance": 0.25}


func _clean(text: String) -> String:
	text = text.replace("\n", " ").replace("&", " and ")
	var re := RegEx.create_from_string("https?://\\S+")
	text = re.sub(text, "that link", true)
	re = RegEx.create_from_string("£\\s?(\\d+(?:\\.\\d+)?)")
	text = re.sub(text, "$1 pounds", true)
	re = RegEx.create_from_string("[*_`#]+")
	text = re.sub(text, "", true)
	return text.strip_edges()


## Sentences, merged so each chunk is a natural phrase of up to ~25 words.
func _chunks(text: String) -> Array:
	var re := RegEx.create_from_string("[^.!?]+[.!?]*")
	var out: Array = []
	var cur := ""
	for m in re.search_all(text):
		var s := m.get_string().strip_edges()
		if s == "":
			continue
		if cur != "" and (cur + " " + s).split(" ").size() > 25:
			out.append(cur)
			cur = s
		else:
			cur = s if cur == "" else cur + " " + s
	if cur != "":
		out.append(cur)
	return out


func _next_chunk() -> void:
	if _queue.is_empty() or _http_state != 0:
		return
	if _dec.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_queue.clear()
		return
	_cur = _queue.pop_front()
	_chunk_start = Time.get_ticks_msec()
	_tok_count = 0
	_frame.clear()
	_sse = ""
	var hdr := PackedByteArray([66])   # 'B'
	var b := StreamPeerBuffer.new()
	b.put_float(float(Cfg.g("voice_pitch", 1.22)))
	b.put_float(float(_cur.tempo))
	b.put_u8(1 if _cur.glitch else 0)
	hdr.append_array(b.data_array)
	_dec.put_data(hdr)
	_dec_waiting += 1
	_http.connect_to_host("127.0.0.1", LLM_PORT)
	_http_state = 1


func _process(delta: float) -> void:
	if downloading:
		_idle += delta
		if _idle > 1.0:
			_idle = 0.0
			download_progress.emit(download_percent())
		return
	_poll_http()
	_poll_decoder()
	_feed_player()
	if not playing and _queue.is_empty() and _http_state == 0 and _llm_pid > 0:
		_idle += delta
		if _idle > 1800.0:   # unload after 30 quiet minutes
			stop_servers()
			_idle = 0.0


func _poll_http() -> void:
	if _http_state == 0:
		return
	_http.poll()
	var st := _http.get_status()
	if _http_state == 1:
		if st == HTTPClient.STATUS_CONNECTED:
			var body := JSON.stringify({"prompt": "<|audio|>%s: %s<|eot_id|>" % [SPEAKER, _cur.text], "n_predict": 1400,
				"temperature": _cur.temp, "top_p": 0.9, "repeat_penalty": 1.1, "stream": true})
			_http.request(HTTPClient.METHOD_POST, "/completion", ["Content-Type: application/json"], body)
			_http_state = 2
		elif st in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR]:
			_finish_chunk()
		return
	if st == HTTPClient.STATUS_BODY:
		var chunk := _http.read_response_body_chunk()
		if chunk.size() > 0:
			_sse += chunk.get_string_from_utf8().replace("\\u003c", "<").replace("\\u003e", ">")
			_parse_sse()
	elif st != HTTPClient.STATUS_REQUESTING:
		_finish_chunk()


var _tok_re := RegEx.create_from_string("<custom_token_(\\d+)>")


func _parse_sse() -> void:
	var nl := _sse.rfind("\n")
	if nl < 0:
		return
	var done_part := _sse.substr(0, nl)
	_sse = _sse.substr(nl + 1)
	var finished := done_part.contains("\"stop\":true") or done_part.contains("\"stop\": true")
	for m in _tok_re.search_all(done_part):
		var v := int(m.get_string(1)) - 10 - ((_tok_count % 7) * 4096)
		if v < 0 or v > 4096:
			continue
		_tok_count += 1
		_frame.append(v)
		if _frame.size() == 7:
			var b := StreamPeerBuffer.new()
			b.put_u8(70)   # 'F'
			for x in _frame:
				b.put_32(x)
			_dec.put_data(b.data_array)
			_frame.clear()
	if _dump != null:
		print("VOICE sse part len=%d tokens=%d finished=%s" % [done_part.length(), _tok_count, finished])
	if finished:
		_finish_chunk()


func _finish_chunk() -> void:
	var secs := (Time.get_ticks_msec() - _chunk_start) / 1000.0
	if _tok_count > 50 and secs > 0.2:
		var rate := _tok_count / secs
		_tok_rate = rate if _tok_rate <= 0.0 else lerpf(_tok_rate, rate, 0.5)
	if _dump != null:
		print("VOICE finish chunk: http status %d, tokens %d" % [_http.get_status(), _tok_count])
	_http.close()
	_http_state = 0
	if _tok_count == 0 and not _cur.is_empty() and not _cur.get("retried", false):
		# the speech server hiccupped before saying anything: try that bit once more
		_cur.retried = true
		_queue.push_front(_cur)
		_dec_waiting -= 1   # the decoder will get a fresh start
		_dec.put_data(PackedByteArray([69]))
		_drop_count += 1
		_dec_waiting += 1
		_cur = {}
		_next_chunk()
		return
	if _dec.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_dec.put_data(PackedByteArray([69]))   # 'E'
	_cur = {}
	_next_chunk()


func _poll_decoder() -> void:
	if _dec.get_status() == StreamPeerTCP.STATUS_NONE:
		return
	_dec.poll()
	if _dec.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if _dec.get_status() == StreamPeerTCP.STATUS_ERROR:
			_dec.disconnect_from_host()
			_dec_waiting = 0
		return
	var n := _dec.get_available_bytes()
	if n > 0:
		var r := _dec.get_partial_data(n)
		if r[0] == OK:
			_dec_buf.append_array(r[1])
	while _dec_buf.size() > 0:
		var t := _dec_buf[0]
		if t == 68:   # 'D'
			_dec_buf = _dec_buf.slice(1)
			_dec_waiting = maxi(0, _dec_waiting - 1)
			_drop_count = maxi(0, _drop_count - 1)
			continue
		if t != 65 or _dec_buf.size() < 5:
			if t != 65:
				_dec_buf = _dec_buf.slice(1)
				continue
			break
		var count := _dec_buf.decode_u32(1)
		if _dec_buf.size() < 5 + count * 2:
			break
		if _drop_count == 0:
			var frames := PackedVector2Array()
			frames.resize(count)
			var sum := 0.0
			var block := 0
			for i in count:
				var s := _dec_buf.decode_s16(5 + i * 2) / 32768.0
				frames[i] = Vector2(s, s)
				sum += s * s
				block += 1
				if block == 480:
					_levels.append(sqrt(sum / 480.0))
					sum = 0.0
					block = 0
			if block > 0:
				_levels.append(sqrt(sum / block))
			_pending_audio.append_array(frames)
		_dec_buf = _dec_buf.slice(5 + count * 2)


var _tok_rate := 0.0          # measured speech-model speed, tokens per second
var _chunk_start := 0
const REALTIME_TOKENS := 82.0  # tokens per second of audio


## How much audio to hold back before starting, so a slow PC doesn't stutter.
func _prebuffer_seconds() -> float:
	if _tok_rate <= 0.0:
		return 0.5
	var r := _tok_rate / REALTIME_TOKENS
	if r >= 1.15:
		return 0.25
	var words := String(_cur.get("text", "")).split(" ").size()
	return clampf(words * 0.33 * (1.0 - r) + 0.3, 0.3, 12.0)


func _feed_player() -> void:
	if _pending_audio.size() > 0:
		if _gen == null:
			var done_gen := _http_state == 0
			if not done_gen and _pending_audio.size() < int(_prebuffer_seconds() * RATE):
				return
			_player.play()
			_gen = _player.get_stream_playback()
			_cap = _gen.get_frames_available()
			_pushed = 0
		var room := _gen.get_frames_available()
		var n := mini(room, _pending_audio.size())
		if n > 0:
			if _dump != null:
				_dump.append_array(_pending_audio.slice(0, n))
			_gen.push_buffer(_pending_audio.slice(0, n))
			_pending_audio = _pending_audio.slice(n)
			_pushed += n
		playing = true
	elif playing and _gen:
		var buffered := _cap - _gen.get_frames_available()
		if buffered <= 0 and _queue.is_empty() and _http_state == 0 and _dec_waiting == 0:
			playing = false
			_player.stop()
			_gen = null
			_levels = PackedFloat32Array()
			_pushed = 0
