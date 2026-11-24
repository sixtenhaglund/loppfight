extends Node
## Autoload "Game": lives for the whole time the game runs, even when the fight scene restarts.
## It remembers the settings (saved to disk) and the match score between rounds.

const SAVE_PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High"]
const DIFF_NAMES := ["Easy", "Normal", "Hard"]

# ---- settings (saved) ----
var quality := 2          # 0 low, 1 medium, 2 high
var volume := 0.8         # 0..1
var shake := true
var show_fps := false
var fullscreen := false
var difficulty := 1       # 0 easy, 1 normal, 2 hard

# ---- match (not saved) ----
var mode := "menu"        # "menu" = main menu with a demo fight behind it, "fight" = you are playing
var round_no := 1
var wins := [0, 0]        # [you, cpu]
const WINS_NEEDED := 2    # best of 3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		quality = 1       # browsers are slower: start on Medium
	load_settings()
	apply_audio()
	apply_window()


func is_web() -> bool:
	return OS.has_feature("web")


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	quality = clampi(cf.get_value("s", "quality", quality), 0, 2)
	volume = clampf(cf.get_value("s", "volume", volume), 0.0, 1.0)
	shake = cf.get_value("s", "shake", shake)
	show_fps = cf.get_value("s", "show_fps", show_fps)
	fullscreen = cf.get_value("s", "fullscreen", fullscreen)
	difficulty = clampi(cf.get_value("s", "difficulty", difficulty), 0, 2)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in ["quality", "volume", "shake", "show_fps", "fullscreen", "difficulty"]:
		cf.set_value("s", k, get(k))
	cf.save(SAVE_PATH)


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func apply_window() -> void:
	if is_web():
		return   # browsers only allow fullscreen after a click, so it's done from the button itself
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## How finely the paper is cut (more cells = nicer rips but slower)
func paper_detail() -> int:
	return [7, 8, 9][quality]


func max_debris() -> int:
	return [50, 100, 160][quality]


func new_match() -> void:
	round_no = 1
	wins = [0, 0]
	mode = "fight"
