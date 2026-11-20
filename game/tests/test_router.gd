extends SceneTree
func _init():
	var M = load("res://scripts/memory.gd").new()
	M.facts = [{"t": "Uses Blender 4.2 for modelling", "tag": ""}, {"t": "PC: Windows 11, Ryzen 7; 32 GB RAM", "tag": "pc"}, {"t": "Partner likes cosy games", "tag": ""}]
	print("relevant blender: ", M.relevant("how do I bake normals in blender", 5))
	print("relevant pc tags: ", M.relevant("clean junk", 5, ["pc"]))
	M.cache = {}
	M.cache[M.norm("what is the capital of peru")] = {"a": "Lima.", "at": Time.get_unix_time_from_system()}
	print("cache exact: ", M.cache_get("What is the capital of Peru?"))
	print("cache near: ", M.cache_get("whats the capital city of peru"))
	print("cacheable my pc: ", M.cacheable("how much ram does my pc have"))
	print("cost haiku: ", M.PRICES["claude-haiku-5-5"])
	quit()
