extends RefCounted
## Offline 3D-printing troubleshooting for the Bambu Lab H2D, in Rico's voice.

const PROBLEMS := [
	{"keys": ["string", "hairy", "cobweb", "wisps"], "title": "Stringing",
		"fix": "1. Dry the filament: PETG and TPU are thirsty little things (the AMS can dry them, or use a dryer).\n2. Drop the nozzle temp 5 to 10 C.\n3. Nudge retraction up a touch and turn on wipe while retracting.\n4. A quick blast with a heat gun cleans up what's left."},
	{"keys": ["warp", "lift", "curl", "corners up", "peel"], "title": "Warping",
		"fix": "1. Wash the plate with warm water and dish soap. Fingers are adhesion's enemy.\n2. Add a brim (5 to 8 mm), and glue stick for PETG/ABS/ASA.\n3. ABS/ASA: keep the door and lid closed and let the chamber warm up first.\n4. Check the plate type in Bambu Studio matches the plate you're actually using."},
	{"keys": ["first layer", "not stick", "won't stick", "adhesion", "came off", "detached", "knocked off"], "title": "First layer not sticking",
		"fix": "1. Clean the plate with soap and water, then don't touch it.\n2. Run bed levelling (Calibration on the printer).\n3. Match the plate type and bed temp to the filament.\n4. Slow the first layer down and add a brim for small footprints."},
	{"keys": ["spaghetti", "birds nest", "bird's nest", "mess", "noodle"], "title": "Spaghetti",
		"fix": "The print came loose or something had nothing to stand on.\n1. Fix adhesion first (clean plate, brim).\n2. Check overhangs: add supports (tree supports are tidy).\n3. Make sure spaghetti detection is on so the H2D stops early next time."},
	{"keys": ["layer shift", "shifted", "offset layers", "skewed", "step"], "title": "Layer shift",
		"fix": "1. Look for anything the toolhead could hit: curled edges, cables, a stray purge blob.\n2. Lower the speed or acceleration for that print.\n3. Check belt tension and run the printer's calibration.\n4. Turn on avoid crossing walls if it keeps snagging."},
	{"keys": ["under extru", "under-extru", "gaps", "thin walls", "missing layers", "weak", "holes in", "clicking"], "title": "Under-extrusion",
		"fix": "1. Wet filament is suspect number one: dry it.\n2. Check the AMS path for tangles or a cracked PTFE tube.\n3. Partial clog: do a cold pull, or swap the hotend (the H2D makes that quick).\n4. Run flow calibration for that filament in Bambu Studio."},
	{"keys": ["elephant foot", "bottom flare", "first layers squished", "bulging bottom"], "title": "Elephant's foot",
		"fix": "1. Lower the bed temp by about 5 C.\n2. Set elephant foot compensation (about 0.1 to 0.15 mm) in Bambu Studio.\n3. A small chamfer on the bottom edge of the model hides it completely."},
	{"keys": ["blob", "zit", "pimple", "seam"], "title": "Blobs and zits",
		"fix": "1. Set the seam to Aligned or Back so it hides somewhere sensible.\n2. Dry the filament.\n3. Turn on wipe and scarf seams in Bambu Studio."},
	{"keys": ["ringing", "ghosting", "ripples", "echo"], "title": "Ringing and ghosting",
		"fix": "1. Re-run vibration compensation (the printer's calibration).\n2. Make sure the printer sits on something solid, not a wobbly desk.\n3. Lower the outer-wall speed and acceleration for show-off prints."},
	{"keys": ["overhang", "droop", "sag", "bridg"], "title": "Droopy overhangs and bridges",
		"fix": "1. More part cooling, and slower overhangs.\n2. Add supports past about 50 degrees.\n3. Rotate the model so the ugly bits face the plate."},
	{"keys": ["clog", "nothing coming out", "no extrusion", "jam"], "title": "Clogged nozzle",
		"fix": "1. Heat up and do a cold pull with PLA or cleaning filament.\n2. Check the extruder isn't chewing the filament.\n3. Still stuck? Swap the hotend: on the H2D it's a quick job."},
]


static func diagnose(text: String) -> String:
	var t := text.to_lower()
	var printy := false
	for w in ["print", "layer", "filament", "nozzle", "bed", "plate", "pla", "petg", "abs", "asa", "tpu", "h2d", "bambu", "extru"]:
		if w in t:
			printy = true
			break
	for p in PROBLEMS:
		for k in p.keys:
			if k in t and (printy or k.length() > 6):
				return "%s, the classic. Here's the fix:\n%s" % [p.title, p.fix]
	return ""


static func model_search_urls(q: String) -> Array:
	var e := q.strip_edges().uri_encode()
	return [
		"https://makerworld.com/en/search/models?keyword=" + e,
		"https://www.printables.com/search/models?q=" + e,
		"https://www.thingiverse.com/search?q=" + e,
	]
