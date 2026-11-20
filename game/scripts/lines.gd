extends RefCounted
## Rico's canned lines: idle quips, reactions and app tips.

const GREET := [
	"Rico, reporting for duty. Try not to make it boring.",
	"Back again? Fine. I'm loaded and ready.",
	"Ricochet's here. Ctrl+Shift+Space if you need me. You will.",
]

const IDLE := [
	"Just polishing my casing. Don't mind me.",
	"Fun fact: I'm the only bullet with a growth mindset.",
	"I could be in a cool action game right now. Instead: desktop.",
	"Your files are judging you. I can tell.",
	"Hydrate. Or don't. I'm a bullet, not your mum.",
	"Is that the same window you had open an hour ago? Bold.",
	"I've been told I have a magnetic personality. It's the brass.",
	"Remember: every bug is just a feature you haven't pitched yet.",
	"I'm not idle. I'm conserving momentum.",
	"Psst. Save your work. Trust me.",
]

const POKE := [
	"Oi. Personal space.",
	"Yes? Need something, or just poking things?",
	"That tickles. Stop it. Actually, do it again.",
	"Click me one more time and I'm going off.",
	"I'm listening. Grudgingly.",
]

const FLUNG := [
	"Wheee! I mean, how dare you.",
	"Ricochet is literally my name. Thanks for the cardio.",
	"Ping! Ping! Ping! ...I'm fine.",
	"Do that again and I'm filing a complaint.",
	"Ten out of ten, would bounce again.",
]

const WAKE := [
	"Huh? I was resting my eyes.",
	"Oh, you're back. I was guarding the desktop. Asleep. Same thing.",
]

const BREAK := [
	"You've been at it for ages. Stand up, stretch, look at something far away. I'll wait.",
	"Break time. Your spine called; it wants a word.",
	"Mandatory break. Get a drink. Blink. Remember what the sun looks like.",
]

const NO_KEY := "I'm only half a brain without a Claude API key. Right-click me, Settings, Chat tab. Until then I can still do timers: try \"remind me in 10 minutes to stretch\"."

const TIPS := {
	"godot": [
		"Godot tip: F5 runs the project, F6 runs just the scene you're in.",
		"Godot tip: Ctrl+Shift+F searches every script in the project.",
		"Godot tip: while the game runs, the Remote tab in the Scene dock shows the live scene tree.",
		"Godot tip: mark a node as unique (% name) and grab it with %NodeName from any script in that scene.",
		"Godot tip: Ctrl+K comments or uncomments the selected lines.",
		"Godot tip: Ctrl+click a function name to jump to where it's defined.",
		"Godot tip: print_debug() also tells you the script and line it came from.",
		"Godot tip: Ctrl+D duplicates the selected node.",
	],
	"blender": [
		"Blender tip: F3 searches for any command you've forgotten the shortcut for.",
		"Blender tip: Ctrl+A, All Transforms before exporting saves a world of pain in Godot.",
		"Blender tip: Numpad period frames the selected object.",
		"Blender tip: Alt+Z toggles X-ray so you can select through things.",
		"Blender tip: Shift+D duplicates, Alt+D makes a linked duplicate that shares the mesh.",
		"Blender tip: M moves the selection to another collection.",
		"Blender tip: N opens the sidebar with exact transform values.",
	],
	"code": [
		"VS Code tip: Ctrl+P quick-opens any file by name.",
		"VS Code tip: Alt+Up or Alt+Down moves the current line.",
		"VS Code tip: Ctrl+D adds the next match to your selection.",
		"VS Code tip: F2 renames a symbol everywhere.",
	],
	"figma": [
		"Figma tip: Shift+A wraps the selection in auto layout.",
		"Figma tip: hold Alt while hovering to measure distances.",
		"Figma tip: Ctrl+Alt+K turns the selection into a component.",
		"Figma tip: Shift+R toggles rulers.",
	],
	"art": [
		"Art tip: flip the canvas horizontally now and then. Wonky proportions jump right out.",
		"Art tip: squint at your piece. If the shapes still read, the values are working.",
		"Art tip: block in big shapes first, details last. Like a bullet: casing before engraving.",
	],
	"browser": [
		"That doesn't look like Godot to me. Just saying.",
		"Research, is it? Sure. I'll pretend I believe you.",
	],
}


static func pick(arr: Array) -> String:
	return arr[randi() % arr.size()]


static func app_kind(title: String) -> String:
	var t := title.to_lower()
	if "godot" in t: return "godot"
	if "blender" in t: return "blender"
	if "visual studio code" in t: return "code"
	if "figma" in t: return "figma"
	if "krita" in t or "photoshop" in t or "clip studio" in t or "aseprite" in t or "procreate" in t: return "art"
	if "youtube" in t or "reddit" in t or "tiktok" in t: return "browser"
	return ""
