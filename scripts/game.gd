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
	load_lopp()
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


# ================================================================ your lopp: coins, upgrades, drawing
const LOPP_PATH := "user://my_lopp.cfg"
const PAINT_PATH := "user://my_lopp_drawing.png"
const PRICES := {"tape": 2, "glue": 1, "layer": 120, "shield": 60, "rod": 40, "teeth": 80}

var coins := 150
var loadout := {}            # tapes: [PackedVector3Array], glue: [Vector3], shields/rods: [[pos, normal, rot]], layer, teeth
var paint: Image             # your drawing
var lopp_seed := 0           # keeps your lopp's hand-folded shape the same


func _init_lopp() -> void:
	loadout = {"tapes": [], "glue": [], "shields": [], "rods": [], "layer": false, "teeth": false}
	paint = Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	paint.fill(Color(0, 0, 0, 0))
	lopp_seed = randi() % 100000 + 1


func load_lopp() -> void:
	_init_lopp()
	var cf := ConfigFile.new()
	if cf.load(LOPP_PATH) == OK:
		coins = cf.get_value("lopp", "coins", coins)
		lopp_seed = cf.get_value("lopp", "seed", lopp_seed)
		for k in loadout:
			loadout[k] = cf.get_value("lopp", k, loadout[k])
	if FileAccess.file_exists(PAINT_PATH):
		var img := Image.load_from_file(PAINT_PATH)
		if img and img.get_width() == 1024:
			img.convert(Image.FORMAT_RGBA8)
			paint = img


func save_lopp() -> void:
	var cf := ConfigFile.new()
	cf.set_value("lopp", "coins", coins)
	cf.set_value("lopp", "seed", lopp_seed)
	for k in loadout:
		cf.set_value("lopp", k, loadout[k])
	cf.save(LOPP_PATH)
	paint.save_png(PAINT_PATH)


## The computer's lopp gets tougher on higher difficulty
func cpu_loadout() -> Dictionary:
	return {"tapes": [], "glue": [], "shields": [], "rods": [], "layer": difficulty >= 2, "teeth": difficulty >= 1 and randf() < 0.5}
