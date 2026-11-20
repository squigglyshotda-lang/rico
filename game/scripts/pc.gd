extends Node
## Rico's hands: runs PowerShell jobs (normally or with admin rights), asks for
## approval before anything that changes the PC, and logs everything it does.
## Every public tool returns a short text result for Claude / the bubble.

signal _job_done(id: int, result: Dictionary)

const PRELUDE := """$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
function Done($o) { $o | ConvertTo-Json -Depth 6 -Compress | Out-File -Encoding utf8 -FilePath $Out }
"""
const LOG_PATH := "user://activity.log"

## Set by main: async func(summary: String, details: String, checklist: Array, admin: bool) -> Dictionary {allowed, checked}
var approve: Callable
var _seq := 0
var _threads := {}


func enabled() -> bool:
	return bool(Cfg.g("pc_tools", true)) and OS.get_name() == "Windows"


# ------------------------------------------------------------------ runner
# Jobs run as in-memory script blocks (-EncodedCommand loading the job text), not as
# .ps1 files, so Windows' script execution policy can't block them.

static func ps_exe() -> String:
	var root := OS.get_environment("SystemRoot")
	var p := (root if root != "" else "C:\\Windows").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	return p if FileAccess.file_exists(p) else "powershell.exe"


static func encode(cmd: String) -> String:
	return Marshalls.raw_to_base64(cmd.to_utf16_buffer())


static func loader(path: String) -> String:
	return "& ([ScriptBlock]::Create([IO.File]::ReadAllText('%s', [Text.Encoding]::UTF8)))" % path.replace("'", "''")


func run(script: String, args := {}, admin := false) -> Dictionary:
	if OS.get_name() != "Windows":
		return {"error": "PC tools only work on Windows."}
	_seq += 1
	var id := _seq
	var dir := OS.get_user_data_dir().path_join("ps")
	DirAccess.make_dir_recursive_absolute(dir)
	var job := dir.path_join("job_%d.txt" % id).replace("/", "\\")
	var out := dir.path_join("job_%d.json" % id).replace("/", "\\")
	var body := FileAccess.get_file_as_string("res://ps/%s.ps1" % script)
	if body == "":
		return {"error": "Rico's %s script is missing from this build." % script}
	var text := "$Out = '%s'\n" % out.replace("'", "''") + PRELUDE + "$A = @'\n" + JSON.stringify(args) + "\n'@ | ConvertFrom-Json\n" + body + "\n"
	var f := FileAccess.open(job, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	var th := Thread.new()
	_threads[id] = th
	th.start(_exec.bind(id, script, job, out, admin))
	while true:
		var r: Array = await _job_done
		if r[0] == id:
			return r[1]
	return {}


func _exec(id: int, script: String, job: String, out: String, admin: bool) -> void:
	var o := []
	var cmd := loader(job)
	if admin:
		var inner := encode(cmd)
		cmd = "try { Start-Process -FilePath '%s' -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand %s' -ErrorAction Stop } catch { '{\"error\":\"Admin permission was declined.\"}' | Out-File -Encoding utf8 -FilePath '%s' }" % [ps_exe(), inner, out.replace("'", "''")]
	var code := OS.execute(ps_exe(), ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-EncodedCommand", encode(cmd)], o, true)
	var result := {}
	var raw := "\n".join(o).strip_edges()
	if FileAccess.file_exists(out):
		var txt := FileAccess.get_file_as_string(out).strip_edges()
		if txt.begins_with("\ufeff"):
			txt = txt.substr(1)
		var parsed = JSON.parse_string(txt)
		result = parsed if parsed is Dictionary else {"error": "Couldn't read the result.", "raw": txt.left(500)}
		DirAccess.remove_absolute(out)
	else:
		result = {"error": "The %s job didn't finish (code %d). %s" % [script, code, raw.left(300)]}
	if result.has("error"):
		_log_error(script, code, raw, String(result.error))
	DirAccess.remove_absolute(job)
	call_deferred("_finish", id, result)


func _log_error(script: String, code: int, output: String, err: String) -> void:
	var dir := OS.get_user_data_dir().path_join("logs")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("pc_errors.log")
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	f.store_line("==== %s  job=%s  exit=%d  powershell=%s" % [Time.get_datetime_string_from_system(), script, code, ps_exe()])
	f.store_line("error: " + err)
	f.store_line("output: " + output.left(3000))
	f.close()


func _finish(id: int, result: Dictionary) -> void:
	if _threads.has(id):
		_threads[id].wait_to_finish()
		_threads.erase(id)
	_job_done.emit(id, result)


func log_action(text: String) -> void:
	var f: FileAccess
	if FileAccess.file_exists(LOG_PATH):
		f = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	var d := Time.get_datetime_dict_from_system()
	f.store_line("%04d-%02d-%02d %02d:%02d  %s" % [d.year, d.month, d.day, d.hour, d.minute, text])
	f.close()


func read_log(lines := 200) -> String:
	if not FileAccess.file_exists(LOG_PATH):
		return "Nothing yet."
	var all := FileAccess.get_file_as_string(LOG_PATH).strip_edges().split("\n")
	var start := maxi(0, all.size() - lines)
	var out := all.slice(start)
	out.reverse()
	return "\n".join(out)


func _ask(summary: String, details := "", checklist: Array = [], admin := false) -> Dictionary:
	if not approve.is_valid():
		return {"allowed": false, "checked": []}
	return await approve.call(summary, details, checklist, admin)


func _err(r: Dictionary) -> String:
	return "Error: " + str(r.get("error", "unknown"))


# ------------------------------------------------------------------ read-only tools (run freely)

func top_processes(sort := "cpu", count := 8) -> Dictionary:
	return await run("top", {"sort": sort, "count": count})


func top_processes_text(sort := "cpu", count := 8) -> String:
	var r := await top_processes(sort, count)
	if r.has("error"):
		return _err(r)
	var lines := ["CPU total %s%%, RAM %s%% used of %s GB." % [r.get("total_cpu_percent", "?"), r.get("ram_used_percent", "?"), r.get("ram_total_gb", "?")]]
	for p in r.get("processes", []):
		lines.append("%s%s: CPU %s%%, RAM %s MB, GPU %s%%%s" % [p.name, " (x%d)" % int(p.count) if int(p.count) > 1 else "", p.cpu, p.mem_mb, p.gpu, " [system, don't close]" if p.protected else ""])
	return "\n".join(lines)


func junk_scan() -> Dictionary:
	return await run("junk", {"mode": "scan"})


func startup_list() -> Dictionary:
	return await run("startup", {"mode": "list"})


func power_list() -> Dictionary:
	return await run("power", {"mode": "list"})


func health(updates := true, admin_temps := false) -> Dictionary:
	var lhm := OS.get_executable_path().get_base_dir().path_join("tools/lhm/LibreHardwareMonitorLib.dll")
	if admin_temps:
		var a := await _ask("Read CPU temperatures? That needs admin rights, so Windows will ask too.", "", [], true)
		if not a.allowed:
			return {"error": "Declined."}
	var r := await run("health", {"updates": updates, "lhm": lhm}, admin_temps)
	return r


func find_files(folder: String, kind := "big", min_mb := 50.0, limit := 15) -> Dictionary:
	return await run("files", {"mode": "find", "folder": folder, "kind": kind, "min_mb": min_mb, "limit": limit})


# ------------------------------------------------------------------ changing tools (need Allow)

func close_apps(names: Array, force := false, reason := "") -> String:
	if names.is_empty():
		return "Nothing to close."
	var summary := "Close %s?%s" % [", ".join(names), ("\n" + reason) if reason != "" else ""]
	if force:
		summary += "\nForce close is on: unsaved work in these apps will be lost."
	var a := await _ask(summary, "Apps are asked to close normally first, so they can prompt you to save.")
	if not a.allowed:
		return "User denied closing the apps."
	var r := await run("close", {"names": names, "force": force})
	if r.has("error"):
		return _err(r)
	var parts := []
	for x in r.get("results", []):
		parts.append("%s: %s" % [x.name, x.status])
	log_action("Closed apps: " + "; ".join(parts))
	return "\n".join(parts)


func junk_clean(categories: Array = []) -> String:
	var scan := await junk_scan()
	if scan.has("error"):
		return _err(scan)
	var checklist := []
	var total := 0
	for c in scan.get("categories", []):
		if int(c.mb) <= 0:
			continue
		var pre: bool = categories.is_empty() or c.id in categories
		checklist.append([c.id, "%s: %s MB%s" % [c.label, int(c.mb), " (admin)" if c.needs_admin else ""], pre])
		total += int(c.mb)
	if checklist.is_empty():
		return "Nothing worth cleaning: the junk folders are basically empty."
	var a := await _ask("Clean up junk? Up to %s MB can be freed. Untick anything you want to keep." % total, "Temp files used in the last 24 hours are skipped, and the Recycle Bin is emptied only if ticked.", checklist)
	if not a.allowed:
		return "User denied the cleanup."
	var chosen := []
	var admin_needed := false
	for i in checklist.size():
		if a.checked.size() > i and a.checked[i]:
			chosen.append(checklist[i][0])
			if "(admin)" in checklist[i][1]:
				admin_needed = true
	if chosen.is_empty():
		return "User unticked everything, so nothing was cleaned."
	var r := await run("junk", {"mode": "clean", "categories": chosen}, admin_needed)
	if r.has("error"):
		return _err(r)
	var freed := 0
	for c in r.get("cleaned", []):
		freed += int(c.freed_mb)
	log_action("Junk cleanup (%s): freed %d MB" % [", ".join(chosen), freed])
	return "Freed %d MB (%s)." % [freed, ", ".join(chosen)]


func startup_set(name: String, on: bool) -> String:
	var lst := await startup_list()
	var item := {}
	for it in lst.get("items", []):
		if String(it.name).to_lower() == name.to_lower():
			item = it
	if item.is_empty():
		for it in lst.get("items", []):
			if name.to_lower() in String(it.name).to_lower():
				item = it
				break
	if item.is_empty():
		return "No startup item called '%s'." % name
	var a := await _ask("%s \"%s\" when Windows starts?" % ["Turn ON" if on else "Stop", item.name], String(item.command), [], bool(item.needs_admin))
	if not a.allowed:
		return "User denied changing startup apps."
	var r := await run("startup", {"mode": "set", "name": item.name, "scope": item.scope, "enabled": on}, bool(item.needs_admin))
	if r.has("error"):
		return _err(r)
	log_action("Startup: %s %s" % [item.name, "enabled" if on else "disabled"])
	return "%s will %s with Windows. It's a switch, not a delete, so it can be turned back on any time." % [item.name, "start" if on else "no longer start"]


func power_set(plan: String, ask := true) -> String:
	if ask:
		var a := await _ask("Switch the power plan to %s?" % plan)
		if not a.allowed:
			return "User denied the power plan change."
	var r := await run("power", {"mode": "set", "plan": plan})
	if r.has("error"):
		return _err(r)
	log_action("Power plan: %s -> %s" % [r.get("previous_name", "?"), r.get("now", "?")])
	return "Power plan is now %s (was %s)." % [r.get("now"), r.get("previous_name")]


## Game/Render mode: close a list of apps, switch to high performance, remember it all for later.
func perf_mode_on(suggested: Array = []) -> String:
	if Cfg.g("perf_state", {}).get("on", false):
		return "Performance mode is already on."
	var running := await top_processes("memory", 40)
	var names := {}
	for p in running.get("processes", []):
		names[String(p.name).to_lower()] = p
	var checklist := []
	var seen := {}
	for n in Cfg.g("perf_apps", []):
		var key := String(n).to_lower().trim_suffix(".exe")
		if names.has(key) and not seen.has(key):
			checklist.append([names[key].name, "%s (your list, %s MB)" % [names[key].name, names[key].mem_mb], true])
			seen[key] = true
	for n in suggested:
		var key := String(n).to_lower().trim_suffix(".exe")
		if names.has(key) and not seen.has(key) and not names[key].protected:
			checklist.append([names[key].name, "%s (Rico's suggestion, %s MB)" % [names[key].name, names[key].mem_mb], false])
			seen[key] = true
	var a := await _ask("Game/Render mode: switch to High performance%s? Tick what to close. I'll reopen them when you turn the mode off." % (" and close apps" if not checklist.is_empty() else ""), "", checklist)
	if not a.allowed:
		return "User denied performance mode."
	var to_close := []
	for i in checklist.size():
		if a.checked.size() > i and a.checked[i]:
			to_close.append(checklist[i][0])
	var reopened := []
	if not to_close.is_empty():
		var r := await run("close", {"names": to_close, "force": false})
		for x in r.get("results", []):
			if x.status == "closed":
				for p in x.get("paths", []):
					if not p in reopened:
						reopened.append(p)
	var pr := await run("power", {"mode": "set", "plan": "high"})
	Cfg.s("perf_state", {"on": true, "previous_plan": pr.get("previous", ""), "reopen": reopened})
	log_action("Performance mode ON: closed %s; plan %s" % [", ".join(to_close) if not to_close.is_empty() else "nothing", pr.get("now", "?")])
	return "Performance mode on. Closed: %s. Power plan: %s." % [", ".join(to_close) if not to_close.is_empty() else "nothing", pr.get("now", pr.get("error", "?"))]


func perf_mode_off() -> String:
	var st: Dictionary = Cfg.g("perf_state", {})
	if not st.get("on", false):
		return "Performance mode isn't on."
	if String(st.get("previous_plan", "")) != "":
		await run("power", {"mode": "set", "plan": st.previous_plan})
	for p in st.get("reopen", []):
		OS.create_process(p, [])
	Cfg.s("perf_state", {})
	log_action("Performance mode OFF: reopened %d apps" % st.get("reopen", []).size())
	return "Performance mode off. Power plan restored and %d apps reopened." % st.get("reopen", []).size()


func tidy(folder: String, by := "type") -> String:
	var plan := await run("files", {"mode": "tidy_plan", "folder": folder, "by": by})
	if plan.has("error"):
		return _err(plan)
	if int(plan.get("total", 0)) == 0:
		return "Nothing loose to tidy in %s." % plan.get("folder", folder)
	var parts := []
	for s in plan.get("summary", []):
		parts.append("%s %d" % [s.folder, int(s.files)])
	var a := await _ask("Tidy %s? Move %d files into folders: %s." % [plan.folder, int(plan.total), ", ".join(parts)], "Only loose files are moved (nothing is deleted). You can undo it afterwards.")
	if not a.allowed:
		return "User denied the tidy."
	var r := await run("files", {"mode": "tidy_apply", "folder": folder, "by": by})
	if r.has("error"):
		return _err(r)
	Cfg.s("last_undo", {"label": "tidy of " + String(r.folder), "log": r.get("log", [])})
	log_action("Tidied %s: moved %d files" % [r.folder, int(r.moved)])
	return "Moved %d files in %s. Say \"undo\" if you hate it." % [int(r.moved), r.folder]


func rename(folder: String, find := "", replace := "", prefix := "", number := false, ext := "") -> String:
	var args := {"folder": folder, "find": find, "replace": replace, "prefix": prefix, "number": number, "ext": ext}
	args.mode = "rename_plan"
	var plan := await run("files", args)
	if plan.has("error"):
		return _err(plan)
	if int(plan.get("total", 0)) == 0:
		return "That rename wouldn't change any file names."
	var preview := []
	for p in plan.get("preview", []):
		preview.append("%s  ->  %s" % [String(p.from).get_file(), String(p.to).get_file()])
	var a := await _ask("Rename %d files in %s?" % [int(plan.total), plan.folder], "\n".join(preview) + ("\n..." if int(plan.total) > preview.size() else ""))
	if not a.allowed:
		return "User denied the rename."
	args.mode = "rename_apply"
	var r := await run("files", args)
	if r.has("error"):
		return _err(r)
	Cfg.s("last_undo", {"label": "rename in " + String(r.folder), "log": r.get("log", [])})
	log_action("Renamed %d files in %s" % [int(r.renamed), r.folder])
	return "Renamed %d files. Undo is available." % int(r.renamed)


func undo_last() -> String:
	var u: Dictionary = Cfg.g("last_undo", {})
	if u.is_empty():
		return "Nothing to undo."
	var a := await _ask("Undo the last %s (%d files)?" % [u.label, u.log.size()])
	if not a.allowed:
		return "User denied the undo."
	var r := await run("files", {"mode": "undo", "log": u.log})
	Cfg.s("last_undo", {})
	log_action("Undid %s: restored %d" % [u.label, int(r.get("restored", 0))])
	return "Put back %d files." % int(r.get("restored", 0))


func recycle(paths: Array) -> String:
	if paths.is_empty():
		return "No files given."
	var names := []
	for p in paths:
		names.append(String(p))
	var a := await _ask("Send %d item(s) to the Recycle Bin?" % paths.size(), "\n".join(names.slice(0, 15)) + ("\n..." if names.size() > 15 else ""))
	if not a.allowed:
		return "User denied deleting."
	var r := await run("files", {"mode": "delete", "paths": paths})
	log_action("Recycled %d items" % int(r.get("recycled", 0)))
	return "Sent %d to the Recycle Bin.%s" % [int(r.get("recycled", 0)), (" Failed: " + ", ".join(r.failed)) if not r.get("failed", []).is_empty() else ""]


func run_command(command: String, explanation: String, admin := false) -> String:
	var a := await _ask(explanation + ("\nNeeds admin, so Windows will ask too." if admin else ""), command, [], admin)
	if not a.allowed:
		return "User denied running the command."
	var r := await run("run", {"command": command}, admin)
	if r.has("error"):
		return _err(r)
	log_action("Ran command (%s): %s" % [explanation, command.replace("\n", " ").left(200)])
	var out := String(r.get("output", "")).strip_edges()
	return ("(no output)" if out == "" else out.left(3500)) + ("" if r.get("ok", true) else "\n[command failed]")


func open_target(target: String) -> String:
	var err := OS.shell_open(target)
	return "Opened " + target if err == OK else "Couldn't open " + target


# ------------------------------------------------------------------ routines

func routine_text(r: Dictionary) -> String:
	var lines := []
	for s in r.get("steps", []):
		lines.append("- %s %s" % [s.get("action", "?"), s.get("target", "")])
	return "\n".join(lines)


## approved_already: true when the user picked it from the menu themselves.
func run_routine(name: String, approved_already := false) -> String:
	var r := {}
	for x in Cfg.g("routines", []):
		if String(x.name).to_lower() == name.to_lower():
			r = x
	if r.is_empty():
		return "No routine called '%s'." % name
	if not approved_already:
		var a := await _ask("Run the \"%s\" routine?" % r.name, routine_text(r))
		if not a.allowed:
			return "User denied the routine."
	var done := []
	for s in r.get("steps", []):
		var t := String(s.get("target", ""))
		match String(s.get("action", "")):
			"open": done.append(open_target(t))
			"close":
				await run("close", {"names": [t], "force": false})
				done.append("closed " + t)
			"power_plan": done.append(await power_set(t, false))
			"perf_on":
				var st: Dictionary = Cfg.g("perf_state", {})
				if st.get("on", false):
					done.append("perf mode already on")
				else:
					var msg := await _perf_quick_on()
					done.append(msg)
			"perf_off": done.append(await perf_mode_off())
			"command":
				await run("run", {"command": t})
				done.append("ran command")
			"wait": await get_tree().create_timer(clampf(float(t), 0.0, 60.0)).timeout
	log_action("Routine '%s' ran" % r.name)
	return "Ran \"%s\": %s" % [r.name, "; ".join(done)]


func _perf_quick_on() -> String:
	# routine version: close the user's own list only, no extra questions
	var close_list: Array = Cfg.g("perf_apps", [])
	var reopened := []
	if not close_list.is_empty():
		var r := await run("close", {"names": close_list, "force": false})
		for x in r.get("results", []):
			if x.status == "closed":
				reopened.append_array(x.get("paths", []))
	var pr := await run("power", {"mode": "set", "plan": "high"})
	Cfg.s("perf_state", {"on": true, "previous_plan": pr.get("previous", ""), "reopen": reopened})
	return "perf mode on"


func save_routine(name: String, description: String, steps: Array) -> String:
	var list: Array = Cfg.g("routines", []).duplicate(true)
	list = list.filter(func(x): return String(x.name).to_lower() != name.to_lower())
	list.append({"name": name, "description": description, "steps": steps})
	Cfg.s("routines", list)
	log_action("Saved routine '%s'" % name)
	return "Saved routine \"%s\". It's in my right-click menu under PC." % name


func _exit_tree() -> void:
	for th in _threads.values():
		if th.is_started():
			th.wait_to_finish()
