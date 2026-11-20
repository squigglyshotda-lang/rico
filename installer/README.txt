RICO - your cheeky desktop bullet
==================================

Installed with Rico-Setup. He lives in %LOCALAPPDATA%\Programs\Rico and
updates himself automatically (Settings > Rico > Updates). Uninstall from
Windows Settings > Apps, like any other app.

First things first
  Right-click Rico > Settings > Chat, and paste a Claude API key
  (console.anthropic.com). Without one he can still do timers and
  reminders, e.g. "remind me in 10 minutes to stretch".

Mouse
  Left-click: chat      Right-click: menu      Drag: move him
  Drag and let go fast: fling him and watch him ricochet

Keyboard (works from any app)
  Alt+Space          search bar (apps, files, maths, conversions, Rico actions)
  Ctrl+Shift+Space   open / close chat
  Ctrl+Alt+Space     talk (press again to stop)
  Ctrl+Alt+R         hide / show Rico
  Esc                close the bubble

Controller (hold View/Back, then press)
  A  chat / confirm      X  talk      B  close bubble      Y  hide / show
  RB search bar (listening; D-pad picks, A opens, Y asks Rico)

Getting out of your way
  Rico hops into free space beside whichever window you're using.
  Drag him somewhere while an app is in front and that becomes his spot
  for that app (e.g. one spot for Blender, another for Godot). Right-click
  > "Forget my spot for this app" to undo. Turn dodging off in Settings > Rico.

Looking after your PC (right-click > PC, or just ask him)
  "Why is my PC slow?", "clean up my junk", "game mode on/off",
  "tidy my Downloads", "find my biggest files", "how hot is my PC?",
  "stop Spotify starting with Windows", "make a Work routine that...".
  Looking things up happens instantly. Anything that changes, closes or
  deletes shows an Allow / Deny card first (with "Show details" for the
  exact command). Admin-only jobs also get the normal Windows prompt.
  Everything he does is listed in Settings > Activity. Turn it all off in
  Settings > PC. Temperatures use LibreHardwareMonitor (in tools\lhm);
  CPU temps need admin and the free PawnIO driver.

Spending as little as possible
  Everyday requests (timers, reminders, opening apps/projects, maths,
  conversions, PC actions, "remember that...") are handled offline for free.
  Repeat questions are answered from memory. Chat and simple questions can
  go to his offline brain (Settings > Usage > Download, 2 GB, runs on your
  PC). Claude gets only the hard stuff, with trimmed prompts and caching,
  and steps up to the bigger model only for hard questions. Each AI reply
  shows what it cost; Settings > Usage has the meter and a daily cap.

Tray icon: left-click hides/shows Rico, right-click opens his menu.

Voice input runs offline with Whisper. The first time you talk, Rico
downloads his speech model (~150 MB, once). After that your speech never
leaves your PC; only the transcribed text is sent to Claude.

Settings and reminders are stored in %APPDATA%\Rico.

If Windows SmartScreen warns you, choose "More info" > "Run anyway"
(the app isn't code-signed).
