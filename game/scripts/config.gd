extends Node
## Settings store (autoload "Cfg"). Saved as JSON in the user folder
## (%APPDATA%/Rico on Windows).

signal changed(key: String)

const PATH := "user://settings.json"

var data := {
	"api_key": "",
	"model": "claude-haiku-5-5",
	"speak_replies": 1,        # 0 off, 1 when I talk, 2 always
	"tts_voice": "",
	"tts_rate": 1.05,
	"tts_pitch": 1.2,
	"talk_blips": true,
	"volume": 0.6,
	"size": 1,                 # 0 small, 1 medium, 2 large
	"wander": true,
	"chattiness": 1,           # 0 quiet, 1 normal, 2 chatty
	"app_tips": true,
	"break_minutes": 60,       # 0 = off
	"start_with_windows": false,
	"projects": [],            # [{name, path}]
	"rico_x": -1.0,
	"dodge": true,
	"app_spots": {},           # exe name -> x position
	"pc_tools": true,
	"weekly_report": true,
	"last_report": 0.0,
	"perf_apps": [],
	"perf_state": {},
	"routines": [],
	"last_undo": {},
	"daily_cap_gbp": 0.0,
	"auto_update": true,
	"welcomed": false,
	"mini_brain": true,
	"brain_offered": false,
}


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in parsed.keys():
			data[k] = parsed[k]


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func g(key: String, default = null):
	return data.get(key, default)


func s(key: String, value) -> void:
	data[key] = value
	save()
	changed.emit(key)


func size_scale() -> float:
	return [0.75, 1.0, 1.35][clampi(int(data.size), 0, 2)]
