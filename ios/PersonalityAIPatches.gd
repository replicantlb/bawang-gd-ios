extends Reference

# Exact 2.560 sources only. Keep native guards, actions, costs and battle rules.
const SOURCE_HASHES = {
	"res://packed/sgz_script/affiars/auto_events/affiars_AI_control.gd": "28b68b299387788c02c3860978e4a6fe2c793bd7274eb81d499f3d09d1400bec",
	"res://packed/sgz_script/affiars/auto_events/AI/policy.gd": "d6bef7e338829f269f44b13e592020a0059b66913ce5dfd14e24023d6db87747",
	"res://packed/sgz_script/affiars/auto_events/AI/project.gd": "226c270ce3909f1922524161f9036ec6811c10228a60abd683abf30c89f18237",
	"res://packed/sgz_script/affiars/auto_events/AI/think_war.gd": "45bf6d8bbfbcee94caa953a81ae6582ae94611b39444f13072ab9d5427826833",
}

const REPLACEMENTS = {
	"res://packed/sgz_script/affiars/auto_events/affiars_AI_control.gd": [
		["""	var ai_work = DataManager.get_env_array("内政.AI战略")
""", """	var personality_vstate_id = -1
	if DataManager.vstate_no >= 0 and DataManager.vstate_no < DataManager.vstates_sort.size():
		personality_vstate_id = int(DataManager.vstates_sort[DataManager.vstate_no])
	if RulerPersonalities.affects_faction(personality_vstate_id):
		var personality_lord_id = clVState.vstate(personality_vstate_id).get_lord_id()
		if DataManager.get_env_int("内政.AI性格君主", -1) != personality_lord_id:
			_update_ai_work()
	elif DataManager.common_variable.has("内政.AI性格君主"):
		_update_ai_work()
	var ai_work = DataManager.get_env_array("内政.AI战略")
"""],
		["""	DataManager.set_env("内政.AI战略", ai_work)
""", """	var vstate_id = -1
	if DataManager.vstate_no >= 0 and DataManager.vstate_no < DataManager.vstates_sort.size():
		vstate_id = int(DataManager.vstates_sort[DataManager.vstate_no])
	if RulerPersonalities.affects_faction(vstate_id):
		DataManager.set_env("内政.AI性格君主", clVState.vstate(vstate_id).get_lord_id())
		var weighted_pool = RulerPersonalities.action_pool(vstate_id)
		if weighted_pool is Array and not weighted_pool.empty():
			ai_work = weighted_pool
	else:
		DataManager.unset_env("内政.AI性格君主")
	DataManager.set_env("内政.AI战略", ai_work)
"""],
	],
	"res://packed/sgz_script/affiars/auto_events/AI/policy.gd": [
		["""	var methods = ["rescue", "envoy", "ally", "wedge", "canvass", "incite"]
	methods.shuffle()
""", """	var methods = ["rescue", "envoy", "ally", "wedge", "canvass", "incite"]
	if RulerPersonalities.affects_faction(vstateId):
		var weighted_methods = RulerPersonalities.policy_methods(vstateId)
		if weighted_methods is Array and not weighted_methods.empty():
			methods = weighted_methods
	methods.shuffle()
"""],
	],
	"res://packed/sgz_script/affiars/auto_events/AI/project.gd": [
		["""		if enemyCityIdsAround.empty():
			max_actors_num = 1
""", """		if enemyCityIdsAround.empty():
			max_actors_num = 1
		elif RulerPersonalities.affects_faction(vstateId):
			max_actors_num = max(max_actors_num, min(10, RulerPersonalities.reserve_count(vstateId, max_actors_num, enemyCityIdsAround.size())))
"""],
	],
	"res://packed/sgz_script/affiars/auto_events/AI/think_war.gd": [
		["func think_about_target_city_id(vstateId:int)->int:", "func _personality_native_target_city_id(vstateId:int)->int:"],
		["""	#派出武将
	var temp_actors = []
""", """	if RulerPersonalities.affects_faction(vstateId):
		var other_frontiers = fromCity.get_connected_city_ids([], [-1, vstateId])
		other_frontiers.erase(targetCity.ID)
		if not other_frontiers.empty():
			need_defence_num = max(need_defence_num, min(10, RulerPersonalities.reserve_count(vstateId, need_defence_num, other_frontiers.size())))
	#派出武将
	var temp_actors = []
"""],
	],
}

const WAR_WRAPPER = """

# Keep the native difficulty and feasibility gates; personality only ranks
# adjacent, non-allied targets from the original strategic decision phase.
func think_about_target_city_id(vstateId:int)->int:
	var native_target = _personality_native_target_city_id(vstateId)
	if native_target < 0 or not RulerPersonalities.affects_faction(vstateId):
		return native_target
	var used_sources = []
	for record in DataManager.war_history:
		if record.size() >= 4 and int(record[0]) == DataManager.year and int(record[1]) == DataManager.month and int(record[2]) == vstateId:
			used_sources.append(int(record[3]))
	var candidates = []
	for owned_city in clCity.all_cities([vstateId]):
		if owned_city.ID in used_sources:
			continue
		for city_id in owned_city.get_connected_city_ids([], [vstateId]):
			if city_id < 0 or city_id >= DataManager.citys.size() or city_id in candidates:
				continue
			if not _target_city_id_valid(vstateId, city_id):
				continue
			candidates.append(city_id)
	if candidates.empty():
		return -1
	var selected = RulerPersonalities.choose_target(vstateId, candidates, native_target)
	if selected in candidates:
		return selected
	return native_target if native_target in candidates else -1
"""


static func supports(path: String, source: String) -> bool:
	return SOURCE_HASHES.has(path) and source.sha256_text() == SOURCE_HASHES[path]


static func apply(path: String, source: String) -> String:
	if not supports(path, source):
		if SOURCE_HASHES.has(path):
			printerr("Ruler personalities: source differs, retaining native script: " + path)
		return source
	for replacement in REPLACEMENTS[path]:
		if source.count(replacement[0]) != 1:
			printerr("Ruler personalities: patch site is not unique, retaining native script: " + path)
			return source
	var patched = source
	for replacement in REPLACEMENTS[path]:
		patched = patched.replace(replacement[0], replacement[1])
	if path.ends_with("/AI/think_war.gd"):
		patched += WAR_WRAPPER
	return patched
