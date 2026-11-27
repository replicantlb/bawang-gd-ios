extends "res://script/global.gdc"

const PersonalityPatches = preload("res://ios_personality_ai_patches.gd")
const SOLO_DISPLAY_PATCHES = {
	"res://packed/sgz_script/solo/solo_attack.gd": ["res://ios_solo_attack.gd", "779d62a63b9555cbc15559cd0787647d669ba99d2ffa30bc720f8d44e266fe3d"],
	"res://packed/sgz_script/solo/solo_crazy_attack.gd": ["res://ios_solo_crazy_attack.gd", "9bada1b55b11753bd7cfe214091b3534a1952b162ae92a5aa3bdfa2b61e2c43b"],
}


static func load_script(path: String):
	var native_path = path
	if not native_path.begins_with("res://") and not native_path.begins_with("resource/"):
		native_path = "res://resource/sgz_script/" + native_path
	if not DataManager.is_developer():
		native_path = native_path.replace("res://resource/sgz_script/", "res://packed/sgz_script/")
	if DataManager.mod_path == DataManager.DEFAULT_MOD_PATH and PersonalityPatches.SOURCE_HASHES.has(native_path):
		var source = Global.get_file_text(native_path)
		if PersonalityPatches.supports(native_path, source):
			if Global.SCRIPT_CACHE.has(native_path) and Global.SCRIPT_CACHE[native_path] != null:
				Global.SCRIPT_CACHE[native_path]._init()
				return Global.SCRIPT_CACHE[native_path]
			var patched = PersonalityPatches.apply(native_path, source)
			if patched != source:
				var personality_script = GDScript.new()
				personality_script.source_code = patched
				if personality_script.reload() == OK:
					var personality_ai = personality_script.new()
					Global.SCRIPT_CACHE[native_path] = personality_ai
					return personality_ai
	# Only substitute the two verified 2.560 sources. Custom mods retain their
	# own scripts, and native callers keep the original cache keys/init lifecycle.
	if DataManager.mod_path == DataManager.DEFAULT_MOD_PATH and SOLO_DISPLAY_PATCHES.has(native_path):
		var patch: Array = SOLO_DISPLAY_PATCHES[native_path]
		if Global.get_file_text(native_path).sha256_text() == patch[1]:
			if Global.SCRIPT_CACHE.has(native_path) and Global.SCRIPT_CACHE[native_path] != null:
				Global.SCRIPT_CACHE[native_path]._init()
				return Global.SCRIPT_CACHE[native_path]
			var script = load(patch[0])
			if script != null:
				var instance = script.new()
				Global.SCRIPT_CACHE[native_path] = instance
				return instance
	return load("res://script/global.gdc").load_script(path)


func save_file_text(path: String, data: String) -> bool:
	if is_inside_tree():
		var trial = get_node_or_null("/root/TrialSession")
		if trial != null and (trial.active or trial.restoring):
			path = trial.sandbox_write_path(path)
			if path.empty() or Directory.new().make_dir_recursive(path.get_base_dir()) != OK:
				return false
	return .save_file_text(path, data)
