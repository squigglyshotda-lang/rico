extends Node
## Push-to-talk voice input. Records the mic, converts to 16 kHz mono WAV and runs
## offline Whisper (whisper.cpp) in a background thread. Also speaks replies aloud.

signal started
signal transcribing
signal heard(text: String)
signal failed(message: String)

const MAX_SECONDS := 30.0

var recording := false
var busy := false
var _record: AudioEffectRecord
var _mic: AudioStreamPlayer
var _thread: Thread
var _elapsed := 0.0
var _dl_tick := 0.0


func _ready() -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Record")
	AudioServer.set_bus_volume_db(idx, -80.0)   # capture without hearing yourself
	_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(idx, _record)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Record"
	add_child(_mic)


func whisper_dir() -> String:
	return OS.get_executable_path().get_base_dir().path_join("whisper")


const MODEL_URL := "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
signal download_progress(text: String)
var downloading := false
var _dl: HTTPRequest


func model_path() -> String:
	var beside := whisper_dir().path_join("ggml-base.en.bin")
	if FileAccess.file_exists(beside):
		return beside
	return OS.get_user_data_dir().path_join("ggml-base.en.bin")


func available() -> bool:
	return FileAccess.file_exists(whisper_dir().path_join("whisper-cli.exe"))


func model_ready() -> bool:
	return FileAccess.file_exists(model_path())


## First-time download of the offline speech model (~148 MB).
func download_model() -> void:
	if downloading:
		return
	downloading = true
	_dl = HTTPRequest.new()
	add_child(_dl)
	var tmp := OS.get_user_data_dir().path_join("ggml-base.en.bin.part")
	_dl.download_file = tmp
	_dl.request_completed.connect(func(result, code, _h, _b):
		downloading = false
		_dl.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			DirAccess.rename_absolute(tmp, OS.get_user_data_dir().path_join("ggml-base.en.bin"))
			download_progress.emit("done")
		else:
			DirAccess.remove_absolute(tmp)
			failed.emit("Couldn't download my ears (HTTP %d). Check your internet and try again." % code))
	_dl.request(MODEL_URL)


func download_percent() -> int:
	if not _dl or _dl.get_body_size() <= 0:
		return 0
	return int(100.0 * _dl.get_downloaded_bytes() / _dl.get_body_size())


func toggle() -> void:
	if busy:
		return
	if recording:
		stop()
	else:
		start()


func start() -> void:
	if not available():
		failed.emit("My ears are missing. The whisper folder should sit next to Rico.exe.")
		return
	if not model_ready():
		download_model()
		download_progress.emit("start")
		return
	recording = true
	_elapsed = 0.0
	_mic.play()
	_record.set_recording_active(true)
	started.emit()


func stop() -> void:
	if not recording:
		return
	recording = false
	_record.set_recording_active(false)
	var wav := _record.get_recording()
	_mic.stop()
	if wav == null or wav.data.size() < 4000:
		failed.emit("I didn't catch anything. Mic muted?")
		return
	var path := OS.get_user_data_dir().path_join("voice.wav")
	_write_16k_mono(wav, path)
	busy = true
	transcribing.emit()
	_thread = Thread.new()
	_thread.start(_run_whisper.bind(path))


func _process(delta: float) -> void:
	if downloading:
		_dl_tick += delta
		if _dl_tick > 1.0:
			_dl_tick = 0.0
			download_progress.emit("%d" % download_percent())
	if recording:
		_elapsed += delta
		if _elapsed > MAX_SECONDS:
			stop()


func _run_whisper(path: String) -> void:
	var out := []
	var d := whisper_dir()
	var threads := clampi(OS.get_processor_count() - 1, 2, 8)
	var code := OS.execute(d.path_join("whisper-cli.exe"),
		["-m", model_path(), "-f", path, "-nt", "-np", "-l", "en", "-t", str(threads)],
		out, true)
	call_deferred("_whisper_done", code, "\n".join(out))


func _whisper_done(code: int, output: String) -> void:
	if _thread:
		_thread.wait_to_finish()
	busy = false
	var text := ""
	for line in output.split("\n"):
		var l := line.strip_edges()
		if l.is_empty() or l.begins_with("whisper_") or l.begins_with("main:") or l.begins_with("system_info") or l.begins_with("ggml_") or l.begins_with("load_backend"):
			continue
		text += l + " "
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]|\\([^)]*\\)")
	text = re.sub(text, "", true).strip_edges()
	if code != 0 and text.is_empty():
		failed.emit("Whisper fell over (code %d)." % code)
	elif text.is_empty():
		failed.emit("Heard nothing useful. Try again, louder and with more conviction.")
	else:
		heard.emit(text)


func _write_16k_mono(wav: AudioStreamWAV, path: String) -> void:
	var src := wav.data
	var rate := float(wav.mix_rate)
	var channels := 2 if wav.stereo else 1
	var frames := src.size() / (2 * channels)
	var mono := PackedFloat32Array()
	mono.resize(frames)
	for i in frames:
		var v := float(src.decode_s16(i * 2 * channels))
		if channels == 2:
			v = (v + float(src.decode_s16(i * 4 + 2))) * 0.5
		mono[i] = v
	var ratio := rate / 16000.0
	var out_frames := int(frames / ratio)
	var out := PackedByteArray()
	out.resize(out_frames * 2)
	var win := maxi(1, int(ratio))
	for j in out_frames:
		var start := int(j * ratio)
		var acc := 0.0
		var n := 0
		for k in win:
			if start + k < frames:
				acc += mono[start + k]
				n += 1
		out.encode_s16(j * 2, clampi(int(acc / maxi(n, 1)), -32768, 32767))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + out.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(16000)
	f.store_32(32000)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(out.size())
	f.store_buffer(out)
	f.close()


# ------------------------------------------------------------ text to speech

func voices() -> Array:
	return DisplayServer.tts_get_voices()


func speak(text: String) -> void:
	DisplayServer.tts_stop()
	var voice := String(Cfg.g("tts_voice", ""))
	if voice == "":
		var list := DisplayServer.tts_get_voices_for_language("en")
		if list.is_empty():
			return
		voice = list[0]
	DisplayServer.tts_speak(text, voice, int(Cfg.g("volume", 0.6) * 100), float(Cfg.g("tts_pitch", 1.2)), float(Cfg.g("tts_rate", 1.05)))


func stop_speaking() -> void:
	DisplayServer.tts_stop()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
