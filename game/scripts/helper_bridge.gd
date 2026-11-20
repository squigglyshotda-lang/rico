extends Node
## Starts rico_helper.exe (global hotkeys + which app is in front) and relays its events.

signal hotkey(name: String)
signal foreground_changed(title: String)

var _pipe: FileAccess
var _pid := -1
var _thread: Thread
var _running := false
var available := false


func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	var path := OS.get_executable_path().get_base_dir().path_join("rico_helper.exe")
	if not FileAccess.file_exists(path):
		push_warning("rico_helper.exe not found next to Rico.exe")
		return
	var info := OS.execute_with_pipe(path, [str(OS.get_process_id())], false)
	if info.is_empty():
		return
	_pipe = info.stdio
	_pid = info.pid
	_running = true
	available = true
	_thread = Thread.new()
	_thread.start(_read_loop)


func _read_loop() -> void:
	while _running and _pipe and _pipe.is_open():
		var line := _pipe.get_line()
		if line == "" and _pipe.get_error() != OK:
			break
		line = line.strip_edges()
		if line.is_empty():
			OS.delay_msec(30)
			continue
		call_deferred("_handle", line)


func _handle(line: String) -> void:
	if line.begins_with("HOTKEY "):
		hotkey.emit(line.substr(7))
	elif line.begins_with("FG "):
		foreground_changed.emit(line.substr(3))


func _exit_tree() -> void:
	_running = false
	if _pid > 0:
		OS.kill(_pid)
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
