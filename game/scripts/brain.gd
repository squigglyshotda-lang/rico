extends Node
## Rico's offline mini-brain: a small Llama 3.2 3B model run locally by llama.cpp's
## llama-server. Free and private; used for chat and simple questions.

signal reply(text: String)
signal failed(message: String)
signal download_progress(percent: int)
signal download_done(ok: bool)

const MODEL_FILE := "Llama-3.2-3B-Instruct-Q4_K_M.gguf"
const MODEL_URL := "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
const MODEL_BYTES := 2019377696
const PORT := 8766

var busy := false
var downloading := false
var _pid := -1
var _ready_ok := false
var _http: HTTPRequest
var _dl: HTTPRequest
var _health: HTTPRequest
var _pending: Array = []


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 120
	add_child(_http)
	_http.request_completed.connect(_on_reply)
	_health = HTTPRequest.new()
	_health.timeout = 3
	add_child(_health)


func model_path() -> String:
	return OS.get_user_data_dir().path_join("brain").path_join(MODEL_FILE)


func server_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join("brain/llama-server.exe")


func installed() -> bool:
	return FileAccess.file_exists(model_path()) and FileAccess.file_exists(server_path())


func enabled() -> bool:
	return installed() and bool(Cfg.g("mini_brain", true))


# ------------------------------------------------------------------ download

func download() -> void:
	if downloading or installed():
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
		download_done.emit(ok))
	_dl.request(MODEL_URL)


func download_percent() -> int:
	if _dl == null:
		return 0
	var total := _dl.get_body_size()
	if total <= 0: total = MODEL_BYTES
	return int(100.0 * _dl.get_downloaded_bytes() / total)


func cancel_download() -> void:
	if _dl:
		_dl.cancel_request()
		_dl.queue_free()
		_dl = null
		downloading = false
		DirAccess.remove_absolute(model_path() + ".part")


func uninstall() -> void:
	stop_server()
	DirAccess.remove_absolute(model_path())


var _tick := 0.0
func _process(delta: float) -> void:
	if downloading:
		_tick += delta
		if _tick > 1.0:
			_tick = 0.0
			download_progress.emit(download_percent())


# ------------------------------------------------------------------ server

func _start_server() -> bool:
	if _pid > 0 and OS.is_process_running(_pid):
		return true
	var threads := clampi(OS.get_processor_count() - 2, 2, 12)
	_pid = OS.create_process(server_path(), ["-m", model_path(), "--host", "127.0.0.1", "--port", str(PORT), "-c", "4096", "-t", str(threads)])
	_ready_ok = false
	return _pid > 0


func stop_server() -> void:
	if _pid > 0:
		OS.kill(_pid)
	_pid = -1
	_ready_ok = false


func _wait_ready() -> bool:
	if _ready_ok:
		return true
	for i in 90:   # up to ~90 s for the model to load the first time
		if _health.request("http://127.0.0.1:%d/health" % PORT) == OK:
			var r: Array = await _health.request_completed
			if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200:
				_ready_ok = true
				return true
		await get_tree().create_timer(1.0).timeout
		if _pid <= 0 or not OS.is_process_running(_pid):
			return false
	return false


## messages: OpenAI-style [{role, content}]
func chat(messages: Array, max_tokens := 220) -> void:
	if busy:
		return
	busy = true
	if not _start_server():
		busy = false
		failed.emit("My offline brain wouldn't start.")
		return
	if not await _wait_ready():
		busy = false
		failed.emit("My offline brain is taking forever to wake up.")
		return
	var body := {"messages": messages, "max_tokens": max_tokens, "temperature": 0.8, "top_p": 0.9, "stream": false}
	var err := _http.request("http://127.0.0.1:%d/v1/chat/completions" % PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		failed.emit("Couldn't talk to my offline brain.")


func _on_reply(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var d = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not (d is Dictionary):
		failed.emit("My offline brain mumbled something unreadable.")
		return
	var text := ""
	var choices: Array = d.get("choices", [])
	if not choices.is_empty():
		text = String(choices[0].get("message", {}).get("content", "")).strip_edges()
	if text == "":
		failed.emit("My offline brain went blank.")
	else:
		reply.emit(text)


func _exit_tree() -> void:
	stop_server()
