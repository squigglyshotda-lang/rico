extends RefCounted
## Rico's canned lines: idle quips, reactions and app tips.

const GREET := [
	"Rico, reporting for duty. Try not to make it boring.",
	"Back again? Fine. I'm loaded and ready.",
	"Ricochet's here. Alt+Space if you need me. You will.",
	"Morning, boss. Or whatever time it is in gamer hours.",
	"I'm up, I'm polished, I'm mildly judgemental. Let's go.",
]

const IDLE := [
	"Just polishing my casing. Don't mind me.",
	"Fun fact: I'm the only bullet with a growth mindset.",
	"Your files are judging you. I can tell.",
	"Hydrate. Or don't. I'm a bullet, not your mum.",
	"I'm not idle. I'm conserving momentum.",
	"Psst. Save your work. Trust me.",
	"Remember: every bug is just a feature you haven't pitched yet.",
	"If you're stuck on a design, squint at it. Works on me too.",
	"Thumbnail it before you render it. Wise words from a bullet.",
	"Your backlog called. It's still growing.",
	"Hot take: the UI is fine, it just needs more padding. It always needs more padding.",
	"I could fetch you a coffee, but, you know. No legs.",
	"Need a timer? A tip? A pep talk? I do all three, badly.",
	"Ctrl+S. I'm just saying it so you don't have to remember.",
]

const POKE := [
	"Oi. Personal space.",
	"Yes? Need something, or just poking things?",
	"That tickles. Stop it. Actually, do it again.",
	"Click me one more time and I'm going off.",
	"I'm listening. Grudgingly.",
	"You rang?",
	"I'm a precision instrument, not a stress ball.",
]

const FLUNG := [
	"Wheee! I mean, how dare you.",
	"Ricochet is literally my name. Thanks for the cardio.",
	"Ping! Ping! Ping! ...I'm fine.",
	"Do that again and I'm filing a complaint.",
	"Ten out of ten, would bounce again.",
	"Physics: undefeated. Me: slightly dented.",
]

const WAKE := [
	"Huh? I was resting my eyes.",
	"Oh, you're back. I was guarding the desktop. Asleep. Same thing.",
	"I wasn't sleeping, I was buffering.",
]

const BREAK := [
	"You've been at it for ages. Stand up, stretch, look at something far away. I'll wait.",
	"Break time. Your spine called; it wants a word.",
	"Mandatory break. Get a drink. Blink. Remember what the sun looks like.",
	"Wrists, eyes, back. Pick one and look after it for five minutes.",
]

const GAME_FIRST := [
	"Ooh, %s. New game smell. Ask me anything: bosses, builds, collectibles. Hints first, no spoilers.",
	"%s, eh? I'll be over here with tips. Shout if something's beating you up.",
]
const GAME_BACK := [
	"Back in %s. Try not to die in the first five minutes this time.",
	"%s again? Respect. I'll keep the tips coming.",
	"Ah, %s. Need a hand, or are we pretending we know what we're doing?",
]
const GAME_SET := [
	"Got it, you're playing %s. Ask me anything about it.",
	"%s it is. I'll tailor my wisdom accordingly.",
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
		"UX tip: check contrast. Small grey text on white looks classy and reads terribly.",
		"UX tip: one primary button per screen. Two primaries means zero.",
		"UX tip: stick to an 8 px spacing grid and the layout tidies itself up.",
		"Figma tip: Shift+A wraps the selection in auto layout.",
		"Figma tip: hold Alt while hovering to measure distances.",
		"Figma tip: Ctrl+Alt+K turns the selection into a component.",
		"Figma tip: Shift+R toggles rulers.",
	],
	"art": [
		"Art tip: flip the canvas horizontally now and then. Wonky proportions jump right out.",
		"Art tip: squint at your piece. If the shapes still read, the values are working.",
		"Art tip: block in big shapes first, details last. Like a bullet: casing before engraving.",
		"Art tip: check your values in greyscale. A black-and-white layer on top in Color mode does it.",
		"Art tip: vary your line weight. Thicker where things overlap or sit in shadow, thinner in the light.",
		"Art tip: pick your light source before you shade, then stick to it like I stick to walls.",
		"Art tip: save a new version before any big change. Future you will send flowers.",
		"Art tip: zoom out to thumbnail size every so often. If it reads small, it reads.",
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
