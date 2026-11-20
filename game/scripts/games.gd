extends Node
## Game help state: which game you're playing, per-game checklists
## (collectibles/achievements) and a small cache of tips.

const PATH := "user://games.json"
const STORE_MARKERS := ["\\steamapps\\common\\", "\\epic games\\", "\\gog galaxy\\games\\", "\\gog games\\", "\\xboxgames\\",
	"\\riot games\\", "\\ubisoft game launcher\\games\\", "\\ea games\\", "\\battle.net\\", "\\itch\\apps\\", "\\games\\"]
const NOT_GAMES := ["steam.exe", "steamwebhelper.exe", "epicgameslauncher.exe", "galaxyclient.exe", "eadesktop.exe", "battle.net.exe",
	"upc.exe", "riotclientservices.exe", "itch.exe", "crashreport", "launcher"]

var data := {}            # game -> {lists: {title: [{t, done}]}, tips: [], played_min}
var override := ""        # set by "I'm playing X"
var detected := ""


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			data = d


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func current() -> String:
	return override if override != "" else detected


## Work out the game name from the app in front, or "" if it isn't a game.
static func detect(path: String, title: String) -> String:
	var p := path.to_lower().replace("/", "\\")
	var exe := p.get_file()
	for n in NOT_GAMES:
		if n in exe:
			return ""
	for m in STORE_MARKERS:
		var i := p.find(m)
		if i >= 0:
			var rest := path.substr(i + m.length()).replace("/", "\\")
			var folder := rest.split("\\", false)[0] if rest != "" else ""
			return folder.replace("_", " ").strip_edges()
	return ""


func entry(game: String) -> Dictionary:
	var key := game.strip_edges()
	if not data.has(key):
		data[key] = {"lists": {}, "tips": [], "played_min": 0}
	return data[key]


# ------------------------------------------------------------------ checklists

func set_list(game: String, title: String, items: Array) -> String:
	var e := entry(game)
	var list := []
	for it in items:
		list.append({"t": String(it), "done": false})
	e.lists[title] = list
	save()
	return "Saved \"%s\" for %s: %d items." % [title, game, list.size()]


func tick(game: String, item: String, done := true) -> String:
	var e := entry(game)
	var q := item.to_lower().strip_edges()
	var best: Dictionary = {}
	var best_title := ""
	var best_score := 0.0
	for title in e.lists.keys():
		for it in e.lists[title]:
			var t := String(it.t).to_lower()
			var sc := 100.0 if t == q else (80.0 if t.begins_with(q) else (60.0 if q in t or t in q else 0.0))
			if sc > best_score:
				best_score = sc
				best = it
				best_title = title
	if best.is_empty():
		return ""
	best.done = done
	save()
	var lst: Array = e.lists[best_title]
	var n := lst.filter(func(x): return x.done).size()
	return "%s %s (%s: %d/%d)." % ["Ticked" if done else "Unticked", best.t, best_title, n, lst.size()]


func show(game: String, only_left := true, limit := 12) -> String:
	var e := entry(game)
	if e.lists.is_empty():
		return "No checklists for %s yet." % game
	var out := []
	for title in e.lists.keys():
		var lst: Array = e.lists[title]
		var left := lst.filter(func(x): return not x.done)
		out.append("%s: %d/%d done" % [title, lst.size() - left.size(), lst.size()])
		if only_left:
			for it in left.slice(0, limit):
				out.append("  - " + String(it.t))
			if left.size() > limit:
				out.append("  ...and %d more" % (left.size() - limit))
	return "\n".join(out)


# ------------------------------------------------------------------ tips

func next_tip(game: String) -> String:
	var e := entry(game)
	if e.tips.is_empty():
		return ""
	var tip: String = e.tips.pop_front()
	save()
	return tip


func add_tips(game: String, tips: Array) -> void:
	var e := entry(game)
	for t in tips:
		var s := String(t).strip_edges()
		if s != "":
			e.tips.append(s)
	save()
