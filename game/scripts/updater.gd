extends Node
## Automatic updates from GitHub Releases: quietly downloads a newer installer,
## then installs it the next time Rico starts (or when you've been away a while).

signal status(text: String)
signal update_ready(version: String)

const REPO := "squigglyshotda-lang/rico"
const API := "https://api.github.com/repos/%s/releases/latest" % REPO
const CHECK_EVERY := 6 * 3600.0

var current := ""
var _http: HTTPRequest
var _dl: HTTPRequest
var _timer := 25.0
var checking := false


func _ready() -> void:
	current = String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_http = HTTPRequest.new()
	_http.timeout = 30
	add_child(_http)
	_http.request_completed.connect(_on_release)


func updates_dir() -> String:
	return OS.get_user_data_dir().path_join("updates")


static func newer(a: String, b: String) -> bool:
	## true if version a > b ("1.10.0" > "1.9.2")
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func pending() -> Dictionary:
	var p := updates_dir().path_join("pending.json")
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if d is Dictionary and FileAccess.file_exists(String(d.get("file", ""))) and newer(String(d.get("version", "")), current):
		return d
	return {}


## Runs the downloaded installer silently and quits; the installer relaunches Rico.
func install_pending() -> bool:
	var p := pending()
	if p.is_empty() or OS.get_name() != "Windows":
		return false
	var f := FileAccess.open(OS.get_user_data_dir().path_join("just_updated.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"from": current, "to": p.version, "notes": p.get("notes", "")}))
	f.close()
	DirAccess.remove_absolute(updates_dir().path_join("pending.json"))
	OS.create_process(String(p.file), ["/S", "/RELAUNCH"])
	Cfg.save()
	get_tree().quit()
	return true


## After an update: {from, to, notes} once, else {}.
func take_update_notes() -> Dictionary:
	var p := OS.get_user_data_dir().path_join("just_updated.json")
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	DirAccess.remove_absolute(p)
	# tidy old installers
	var dir := DirAccess.open(updates_dir())
	if dir:
		for fn in dir.get_files():
			if fn.ends_with(".exe"):
				dir.remove(fn)
	return d if d is Dictionary else {}


func check_now() -> void:
	if checking or OS.get_name() != "Windows":
		return
	checking = true
	status.emit("Checking for updates...")
	_http.request(API, ["User-Agent: Rico-Updater", "Accept: application/vnd.github+json"])


func _process(delta: float) -> void:
	if not Cfg.g("auto_update", true):
		return
	_timer -= delta
	if _timer <= 0:
		_timer = CHECK_EVERY
		check_now()


func _on_release(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	checking = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.emit("Couldn't check for updates right now." if code != 404 else "No releases published yet.")
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary):
		return
	var tag := String(d.get("tag_name", "")).trim_prefix("v")
	if not newer(tag, current):
		status.emit("Rico is up to date (v%s)." % current)
		return
	var url := ""
	var asset_name := ""
	for a in d.get("assets", []):
		var n := String(a.get("name", ""))
		if n.begins_with("Rico-Setup") and n.ends_with(".exe"):
			url = String(a.get("browser_download_url", ""))
			asset_name = n
	if url == "":
		return
	var p := pending()
	if not p.is_empty() and String(p.version) == tag:
		status.emit("v%s is downloaded and installs next time Rico starts." % tag)
		update_ready.emit(tag)
		return
	DirAccess.make_dir_recursive_absolute(updates_dir())
	var dest := updates_dir().path_join(asset_name)
	status.emit("Downloading v%s..." % tag)
	_dl = HTTPRequest.new()
	_dl.download_file = dest + ".part"
	_dl.timeout = 600
	add_child(_dl)
	var notes := String(d.get("body", "")).left(1500)
	_dl.request_completed.connect(func(r2, c2, _h2, _b2):
		_dl.queue_free()
		if r2 == HTTPRequest.RESULT_SUCCESS and c2 == 200:
			DirAccess.rename_absolute(dest + ".part", dest)
			var f := FileAccess.open(updates_dir().path_join("pending.json"), FileAccess.WRITE)
			f.store_string(JSON.stringify({"version": tag, "file": dest, "notes": notes}))
			f.close()
			status.emit("v%s downloaded. It installs next time Rico starts." % tag)
			update_ready.emit(tag)
		else:
			DirAccess.remove_absolute(dest + ".part")
			status.emit("Update download failed; I'll try again later."))
	_dl.request(url)
