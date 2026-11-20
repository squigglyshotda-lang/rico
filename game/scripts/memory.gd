extends Node
## Rico's local memory: facts about you and your PC, a cache of past answers,
## and a record of how much Claude has cost. All stored on disk, nothing online.

const FACTS_PATH := "user://memory.json"
const CACHE_PATH := "user://answer_cache.json"
const USAGE_PATH := "user://usage.json"
const CACHE_MAX := 600
const CACHE_DAYS := 30

# USD per million tokens: [input, output, cache_write, cache_read]
const PRICES := {
	"claude-haiku-5-5": [0.10, 0.50, 0.125, 0.01],
	"claude-sonnet-5-5": [2.0, 10.0, 2.50, 0.10],
}
const STOP := ["the", "a", "an", "is", "are", "was", "to", "of", "and", "or", "in", "on", "for", "it", "my", "me", "i", "you", "your", "do", "does", "what", "how", "can", "with", "that", "this", "be", "at", "by", "from", "about", "please", "rico"]
const VOLATILE := ["today", "now", "tonight", "tomorrow", "yesterday", "latest", "current", "currently", "news", "weather", "price", "time", "remind", "reminder", "timer", "my ", "mine", "that file", "pc", "computer", "laptop", "open", "close", "running", "remember", "forget"]

var facts: Array = []      # [{t, tag, at}]
var cache := {}            # key -> {q, a, at, src}
var usage := {}            # "YYYY-MM-DD" -> stats
var usd_to_gbp := 0.79


func _ready() -> void:
	facts = _load(FACTS_PATH, {"facts": []}).get("facts", [])
	cache = _load(CACHE_PATH, {})
	usage = _load(USAGE_PATH, {})


func _load(path: String, fallback):
	if not FileAccess.file_exists(path):
		return fallback
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == typeof(fallback) else fallback


func _save(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


static func words(text: String) -> PackedStringArray:
	var clean := ""
	for c in text.to_lower():
		clean += c if (c.is_valid_identifier() or c.is_valid_int() or c == "'") else " "
	var out := PackedStringArray()
	for w in clean.split(" ", false):
		if w.length() > 1 and not w in STOP:
			out.append(w)
	return out


static func norm(text: String) -> String:
	return " ".join(words(text))


# ------------------------------------------------------------------ facts

func add_fact(text: String, tag := "") -> void:
	text = text.strip_edges().trim_suffix(".")
	if text == "":
		return
	if tag != "":
		facts = facts.filter(func(f): return f.get("tag", "") != tag)
	else:
		facts = facts.filter(func(f): return String(f.t).to_lower() != text.to_lower())
	facts.append({"t": text, "tag": tag, "at": Time.get_date_string_from_system()})
	_save(FACTS_PATH, {"facts": facts})


func forget(about: String) -> int:
	var w := words(about)
	var before := facts.size()
	facts = facts.filter(func(f):
		var fw := words(String(f.t))
		for x in w:
			if x in fw: return false
		return true)
	_save(FACTS_PATH, {"facts": facts})
	return before - facts.size()


func remove_fact_at(i: int) -> void:
	if i >= 0 and i < facts.size():
		facts.remove_at(i)
		_save(FACTS_PATH, {"facts": facts})


## The few facts that share words with the message (so Claude only gets what's relevant).
func relevant(text: String, n := 5, include_tags: Array = []) -> Array:
	var w := words(text)
	var scored := []
	for f in facts:
		if f.get("tag", "") in include_tags and f.get("tag", "") != "":
			scored.append([100, f.t])
			continue
		var fw := words(String(f.t))
		var s := 0
		for x in w:
			if x in fw: s += 1
		if s > 0:
			scored.append([s, f.t])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored.slice(0, n).map(func(x): return x[1])


# ------------------------------------------------------------------ answer cache

static func cacheable(question: String) -> bool:
	var q := " " + question.to_lower() + " "
	for v in VOLATILE:
		if v in q:
			return false
	return words(question).size() >= 2


func cache_get(question: String) -> String:
	if not cacheable(question):
		return ""
	var key := norm(question)
	var now := Time.get_unix_time_from_system()
	if cache.has(key) and now - float(cache[key].at) < CACHE_DAYS * 86400:
		return String(cache[key].a)
	# near-duplicate: same meaningful words, give or take one
	var w := words(question)
	if w.size() < 3:
		return ""
	for k in cache.keys():
		var kw := String(k).split(" ", false)
		var inter := 0
		for x in w:
			if x in kw: inter += 1
		var union := w.size() + kw.size() - inter
		if union > 0 and float(inter) / union >= 0.8 and now - float(cache[k].at) < CACHE_DAYS * 86400:
			return String(cache[k].a)
	return ""


func cache_put(question: String, answer: String, src: String) -> void:
	if not cacheable(question) or answer.length() < 2:
		return
	cache[norm(question)] = {"q": question.left(200), "a": answer, "at": Time.get_unix_time_from_system(), "src": src}
	if cache.size() > CACHE_MAX:
		var keys := cache.keys()
		keys.sort_custom(func(a, b): return float(cache[a].at) < float(cache[b].at))
		for k in keys.slice(0, cache.size() - CACHE_MAX):
			cache.erase(k)
	_save(CACHE_PATH, cache)


func clear_cache() -> void:
	cache = {}
	_save(CACHE_PATH, cache)


# ------------------------------------------------------------------ usage

func _today() -> Dictionary:
	var d := Time.get_date_string_from_system()
	if not usage.has(d):
		usage[d] = {"in": 0, "out": 0, "cw": 0, "cr": 0, "usd": 0.0, "haiku": 0, "sonnet": 0, "mini": 0, "cache": 0, "local": 0}
	return usage[d]


## Records a Claude call and returns its cost in GBP.
func add_usage(model: String, u: Dictionary) -> float:
	var p: Array = PRICES.get(model, PRICES["claude-sonnet-5-5"])
	var i := int(u.get("input_tokens", 0))
	var o := int(u.get("output_tokens", 0))
	var cw := int(u.get("cache_creation_input_tokens", 0))
	var cr := int(u.get("cache_read_input_tokens", 0))
	var searches := int(u.get("server_tool_use", {}).get("web_search_requests", 0)) if u.get("server_tool_use") is Dictionary else 0
	var usd: float = (i * p[0] + o * p[1] + cw * p[2] + cr * p[3]) / 1e6 + searches * 0.01
	var t := _today()
	t["in"] += i; t["out"] += o; t["cw"] += cw; t["cr"] += cr
	t["usd"] = float(t["usd"]) + usd
	t["sonnet" if "sonnet" in model else "haiku"] += 1
	_save(USAGE_PATH, usage)
	return usd * usd_to_gbp


func count(kind: String) -> void:
	var t := _today()
	t[kind] = int(t.get(kind, 0)) + 1
	_save(USAGE_PATH, usage)


func today_gbp() -> float:
	return float(_today().usd) * usd_to_gbp


func month_stats() -> Dictionary:
	var prefix := Time.get_date_string_from_system().left(7)
	var out := {"in": 0, "out": 0, "cw": 0, "cr": 0, "usd": 0.0, "haiku": 0, "sonnet": 0, "mini": 0, "cache": 0, "local": 0}
	for d in usage.keys():
		if String(d).begins_with(prefix):
			for k in out.keys():
				out[k] += usage[d].get(k, 0)
	return out


func today_stats() -> Dictionary:
	return _today().duplicate()


static func fmt_gbp(gbp: float) -> String:
	if gbp < 0.01:
		return "%.2fp" % (gbp * 100.0)
	return "£%.2f" % gbp
