extends Node
## Reminders, timers and break nudges. Saved so they survive restarts.

signal due(reminder: Dictionary)
signal break_due
signal list_changed

const PATH := "user://reminders.json"

var items: Array = []        # {id, text, due (unix), repeat (minutes)}
var _next_id := 1
var _acc := 0.0
var _active_seconds := 0.0


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			items = parsed.get("items", [])
			_next_id = int(parsed.get("next_id", 1))


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"items": items, "next_id": _next_id}))
	list_changed.emit()


func now() -> float:
	return Time.get_unix_time_from_system()


func add(text: String, minutes: float, repeat := 0.0) -> Dictionary:
	var r := {"id": _next_id, "text": text, "due": now() + minutes * 60.0, "repeat": repeat}
	_next_id += 1
	items.append(r)
	_save()
	return r


func add_at(text: String, hhmm: String, repeat := 0.0) -> Dictionary:
	var parts := hhmm.strip_edges().split(":")
	if parts.size() < 2:
		return {}
	var d := Time.get_datetime_dict_from_system()
	var target := d.duplicate()
	target.hour = int(parts[0])
	target.minute = int(parts[1])
	target.second = 0
	var tz := Time.get_time_zone_from_system()
	var unix: float = Time.get_unix_time_from_datetime_dict(target) - tz.bias * 60
	if unix <= now():
		unix += 86400
	return add(text, (unix - now()) / 60.0, repeat)


func cancel(id: int) -> bool:
	for i in items.size():
		if int(items[i].id) == id:
			items.remove_at(i)
			_save()
			return true
	return false


func snooze(r: Dictionary, minutes: float) -> void:
	add(r.text, minutes)


func pending() -> Array:
	var copy := items.duplicate()
	copy.sort_custom(func(a, b): return a.due < b.due)
	return copy


func describe(r: Dictionary) -> String:
	var secs := int(r.due - now())
	var when := ""
	if secs < 60:
		when = "in under a minute"
	elif secs < 3600:
		when = "in %d min" % ceili(secs / 60.0)
	else:
		var dt := Time.get_datetime_dict_from_unix_time(int(r.due) + Time.get_time_zone_from_system().bias * 60)
		when = "at %02d:%02d" % [dt.hour, dt.minute]
	var rep := " (every %d min)" % int(r.repeat) if float(r.repeat) > 0 else ""
	return "#%d %s, %s%s" % [int(r.id), r.text, when, rep]


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 1.0:
		return
	_active_seconds += _acc
	_acc = 0.0
	var t := now()
	var fired := false
	for r in items.duplicate():
		if float(r.due) <= t:
			fired = true
			items.erase(r)
			if float(r.repeat) > 0:
				var again: Dictionary = r.duplicate()
				again.due = t + float(r.repeat) * 60.0
				items.append(again)
			due.emit(r)
	if fired:
		_save()
	var bm := float(Cfg.g("break_minutes", 60))
	if bm > 0 and _active_seconds >= bm * 60.0:
		_active_seconds = 0.0
		break_due.emit()


func reset_break_clock() -> void:
	_active_seconds = 0.0
