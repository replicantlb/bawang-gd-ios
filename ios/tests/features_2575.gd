extends SceneTree

var checks := 0
var failures := 0
var dm
var sm
var service
var global


func _initialize():
	call_deferred("_run")


func check(value, label: String) -> void:
	checks += 1
	print("FEATURE_CHECK ", label, " ", value)
	if not value:
		failures += 1


func frames(count := 4):
	for _index in range(count):
		yield(self, "idle_frame")


func read_text(path: String) -> String:
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return ""
	var result = file.get_as_text()
	file.close()
	return result


func stable_affairs() -> void:
	root.get_node("FlowManager").clear()
	root.get_node("LoadControl").end_script()
	sm.current_scene().affiars_run._init()
	sm.current_scene().affiars_run.player_control.player_ready()
	paused = false


func state_hash() -> int:
	var data = dm.get_save_data().duplicate(true)
	data.erase("存档时间")
	return data.hash()


func faction_row(vstate_id: int) -> Dictionary:
	for row in service.current_factions(false):
		if row.vstate_id == vstate_id:
			return row
	return {}


func write_slot(data: Dictionary, name: String) -> String:
	var path = dm.get_common_path() + "save/" + name + ".sav"
	Directory.new().make_dir_recursive(path.get_base_dir())
	var file = File.new()
	if file.open(path, File.WRITE) != OK:
		return ""
	file.store_string(JSON.print(data))
	file.close()
	return path


func press(action: String):
	Input.action_press(action)
	yield(frames(3), "completed")
	Input.action_release(action)
	yield(frames(7), "completed")


func at_scene(name: String, mode: int) -> bool:
	var scene = sm.current_scene()
	return scene != null and scene.is_processing() and scene.filename.get_file().get_basename() == name and (mode < 0 or scene.get("scene_view_mode") == mode)


func start_new_campaign():
	sm.go_to_scene("res://scene/Main.tscn")
	yield(frames(5), "completed")
	var route = [["EMU_START", "scene_drama", -1], ["EMU_A", "scene_set", -1], ["EMU_START", "scene_title", 0], ["EMU_START", "scene_title", 1], ["EMU_START", "scene_title", 2], ["EMU_START", "scene_title", 5], ["EMU_START", "scene_pickLord", -1], ["EMU_A", "scene_affiars", -1]]
	for step in route:
		for _attempt in range(35):
			if at_scene(step[1], step[2]):
				break
			yield(press(step[0]), "completed")
		if not at_scene(step[1], step[2]):
			check(false, "native new campaign route reached " + str(step))
			return
	yield(frames(5), "completed")


func legal_targets(war, vstate_id: int) -> Array:
	var targets := []
	var city_api = load("res://script/objects/clCity.gd")
	for city in city_api.all_cities([vstate_id]):
		for id in city.get_connected_city_ids([], [vstate_id]):
			if not id in targets and war._target_city_id_valid(vstate_id, id):
				targets.append(id)
	return targets


func set_month_serial(serial: int) -> void:
	dm.year = int((serial - 1) / 12)
	dm.month = (serial - 1) % 12 + 1


func check_goal_lifecycle() -> void:
	var snapshot: Dictionary = dm.get_save_data().duplicate(true)
	var war = global.load_script("affiars/auto_events/AI/think_war.gd")
	var selected_faction := -1
	var candidates := []
	for record in service.current_factions(false):
		if record.is_player:
			continue
		var actual: Array = legal_targets(war, record.vstate_id)
		if actual.size() >= 2:
			selected_faction = record.vstate_id
			candidates = actual
			break
	check(selected_faction >= 0, "fixture has two native-legal adjacent AI targets")
	if selected_faction < 0:
		return
	var month = dm.year * 12 + dm.month
	var selected = service.choose_target(selected_faction, candidates, candidates[0])
	var first_goal: Dictionary = dm.get_env_dict(service.STATE_KEY).get("goals", {}).get(str(selected_faction), {})
	check(selected in candidates and first_goal.get("city", -1) == selected and first_goal.get("since", -1) == month, "real legal target creates a dated strategic goal")
	set_month_serial(month + 1)
	var continued = service.choose_target(selected_faction, legal_targets(war, selected_faction), candidates[0])
	var second_goal: Dictionary = dm.get_env_dict(service.STATE_KEY).get("goals", {}).get(str(selected_faction), {})
	check(continued == selected and second_goal.get("since", -1) == month, "unchanged next-month situation preserves target and original start date")
	set_month_serial(month + 3)
	var reevaluated = service.choose_target(selected_faction, legal_targets(war, selected_faction), candidates[0])
	var renewed: Dictionary = dm.get_env_dict(service.STATE_KEY).get("goals", {}).get(str(selected_faction), {})
	check(reevaluated in candidates and renewed.get("city", -1) == reevaluated and renewed.get("since", -1) == month + 3, "three-month expiry reevaluates and renews strategic goal date")
	# A captured target is no longer a foreign adjacent candidate. Rebuild the
	# candidates with the original validator; never insert a fabricated target.
	dm.citys[reevaluated]["归属"] = selected_faction
	var remaining: Array = legal_targets(war, selected_faction)
	check(not reevaluated in remaining and not remaining.empty(), "captured old target leaves native legal candidate set")
	if not remaining.empty():
		var redirected = service.choose_target(selected_faction, remaining, remaining[0])
		check(redirected in remaining and redirected != reevaluated, "obsolete remembered target cannot override current legal alternatives")
	service.set_enabled(false)
	check(dm.get_env_dict(service.STATE_KEY).get("goals", {}).empty(), "disabling personality mode clears remembered strategic goals")
	dm.set_save_data(snapshot)


func _run():
	yield(self, "idle_frame")
	var name = OS.get_environment("BAWANG_QA_NAME")
	if not name.begins_with("BawangFeatureQA-") or OS.get_user_data_dir().get_file() != name:
		quit(1)
		return
	dm = root.get_node("DataManager")
	sm = root.get_node("SceneManager")
	global = root.get_node("Global")
	service = root.get_node_or_null("RulerPersonalities")
	check(service != null and service.has_method("profile_for"), "personality service loaded and parsed")
	if failures > 0:
		quit(1)
		return
	var parsed = JSON.parse(read_text(OS.get_environment("BAWANG_QA_SAVE")))
	check(parsed.error == OK and parsed.result is Dictionary, "read isolated legacy fixture")
	if failures > 0:
		quit(1)
		return
	var legacy: Dictionary = parsed.result
	legacy.common_variable.erase(service.STATE_KEY)
	legacy.flows_history_list = []
	dm.set_save_data(legacy.duplicate(true))
	sm.go_to_scene("res://scene/scene_affiars/scene_affiars.tscn")
	yield(frames(), "completed")
	stable_affairs()
	yield(frames(), "completed")
	check(service.is_enabled(), "legacy save defaults to enabled personality mode")
	var raw_before = dm.common_variable.duplicate(true).hash()
	var rows: Array = service.current_factions(false)
	check(not rows.empty() and dm.common_variable.hash() == raw_before, "public roster preview does not initialize save metadata")
	var presets = JSON.parse(read_text("res://ios_ruler_personalities.json")).result.presets
	var preset_ok = presets.size() >= 60
	for key in presets:
		var profile: Dictionary = service.profile_for(int(key), false)
		preset_ok = preset_ok and profile.source == "人物预设" and profile.primary == presets[key].primary and profile.secondary == presets[key].secondary and profile.primary != profile.secondary
	check(preset_ok, "all historical presets resolve by actor identity")
	var fallback_id = 0
	while presets.has(str(fallback_id)):
		fallback_id += 1
	seed(257506)
	var expected_random = randi()
	seed(257506)
	var automatic: Dictionary = service.profile_for(fallback_id, false)
	check(randi() == expected_random and automatic.source == "自动性格" and automatic.primary != automatic.secondary, "fallback generation is deterministic and consumes no RNG")
	var raw_actor = dm.actors[fallback_id].duplicate(true)
	dm.actors[fallback_id]["武"] = 1
	dm.actors[fallback_id]["知"] = 1
	dm.actors[fallback_id]["等级"] = 8
	dm.actors[fallback_id]["武器"] = 0
	check(service.profile_for(fallback_id, false).primary == automatic.primary and service.profile_for(fallback_id, false).secondary == automatic.secondary, "native fallback ignores later equipment and stat edits")
	dm.actors[fallback_id] = raw_actor
	var frozen: Dictionary = service.profile_for(fallback_id)
	check(service.set_manual(fallback_id, "好战", "进取"), "manual personality accepted")
	check(service.profile_for(fallback_id).source == "手动设置" and service.profile_for(fallback_id).primary == "好战", "manual selection takes priority over automatic fallback")
	service.reset_profile(fallback_id)
	check(service.profile_for(fallback_id).primary == frozen.primary and service.profile_for(fallback_id).secondary == frozen.secondary and service.profile_for(fallback_id).source == "自动性格", "reset restores frozen original automatic profile")
	check(not service.set_manual(fallback_id, "守成", "守成") and not service.set_manual(-1, "守成", "谋略"), "duplicate traits and invalid actor rejected")
	var diy_id = root.get_node("StaticManager").ACTOR_ID_DIY
	if diy_id >= 0 and diy_id < dm.actors.size():
		var original_diy = dm.actors[diy_id].duplicate(true)
		var diy_profile: Dictionary = service.profile_for(diy_id)
		dm.actors[diy_id]["胆"] = 100
		dm.actors[diy_id]["德"] = 0
		dm.actors[diy_id]["武"] = 100
		check(diy_profile.source == "自动性格" and service.profile_for(diy_id).primary == diy_profile.primary and service.profile_for(diy_id).secondary == diy_profile.secondary, "custom ruler fallback remains frozen after creation stats change")
		dm.actors[diy_id] = original_diy
	var ai_row := {}
	var player_row := {}
	for row in rows:
		if row.is_player:
			player_row = row
		elif ai_row.empty():
			ai_row = row
	check(not ai_row.empty(), "fixture contains a live AI faction")
	if ai_row.empty():
		quit(1)
		return
	var faction_id = int(ai_row.vstate_id)
	check(service.affects_faction(faction_id), "personality mode affects a live AI ruler")
	if not player_row.empty():
		check(not service.affects_faction(player_row.vstate_id), "player ruler remains under manual control")
	service.prepare_save()
	check_goal_lifecycle()
	var original_lord = int(dm.vstates[faction_id]["君主"])
	var original_relations = dm.vstates[faction_id].get("势力关系", {}).duplicate(true)
	var alliance_hash = dm.vstates_alliance.hash()
	var metadata = dm.get_env_dict(service.STATE_KEY).duplicate(true)
	metadata.goals = {str(faction_id): {"lord": original_lord, "city": 0, "since": dm.year * 12 + dm.month}}
	dm.set_env(service.STATE_KEY, metadata)
	dm.vstates[faction_id]["君主"] = fallback_id
	var after_succession = faction_row(faction_id)
	check(after_succession.lord_id == fallback_id and after_succession.previous_lord_id == original_lord and after_succession.profile.source == "自动性格", "arbitrary successor uses own fallback and publicly shows predecessor")
	check(service.affects_faction(faction_id) and not dm.get_env_dict(service.STATE_KEY).get("goals", {}).has(str(faction_id)), "new ruler invalidates previous ruler strategic goal")
	check(dm.vstates[faction_id].get("势力关系", {}).hash() == original_relations.hash() and dm.vstates_alliance.hash() == alliance_hash, "succession personality leaves diplomacy and alliances intact")
	metadata = dm.get_env_dict(service.STATE_KEY).duplicate(true)
	metadata.goals = {str(faction_id): {"lord": fallback_id, "city": 0, "since": dm.year * 12 + dm.month}}
	dm.set_env(service.STATE_KEY, metadata)
	dm.set_env("内政.AI性格君主", fallback_id)
	service.set_manual(fallback_id, "好战", "进取")
	check(not dm.get_env_dict(service.STATE_KEY).get("goals", {}).has(str(faction_id)) and dm.get_env_int("内政.AI性格君主", -1) == -1, "manual change invalidates ruler old goal and action marker")
	metadata = dm.get_env_dict(service.STATE_KEY).duplicate(true)
	metadata.goals = {str(faction_id): {"lord": fallback_id, "city": 0, "since": dm.year * 12 + dm.month}}
	dm.set_env(service.STATE_KEY, metadata)
	dm.set_env("内政.AI性格君主", fallback_id)
	service.reset_profile(fallback_id)
	check(not dm.get_env_dict(service.STATE_KEY).get("goals", {}).has(str(faction_id)) and dm.get_env_int("内政.AI性格君主", -1) == -1, "restoring default invalidates stale ruler plan")
	var saved = JSON.parse(JSON.print(dm.get_save_data())).result
	dm.set_save_data(saved)
	check(faction_row(faction_id).lord_id == fallback_id and service.profile_for(fallback_id).source == "自动性格", "personality and succession survive native save roundtrip")
	var transfer_token = service.session_token()
	dm.set_save_data(dm.get_save_data().duplicate(true))
	check(service.session_token() == transfer_token, "ordinary native scene transfer keeps session token")
	var supported_mod = dm.mod_path
	dm.mod_path = "res://unsupported_mod/"
	check(not service.supported() and not service.affects_faction(faction_id), "custom mods retain native decision behavior")
	dm.mod_path = supported_mod
	service.set_enabled(false)
	check(not service.affects_faction(faction_id), "campaign switch disables personality decisions")
	service.set_enabled(true)
	var patcher = load("res://ios_personality_ai_patches.gd")
	var paths = patcher.SOURCE_HASHES.keys()
	var patched_ok = true
	var guarded_ok = true
	for path in paths:
		var source: String = global.get_file_text(path)
		var changed: String = patcher.apply(path, source)
		var obj = global.load_script(path)
		patched_ok = patched_ok and changed != source and obj != null and obj.get_script().source_code == changed and global.SCRIPT_CACHE.get(path) == obj
		guarded_ok = guarded_ok and patcher.apply(path, source + "\n# external source edit\n") == source + "\n# external source edit\n" and patcher.apply(path, changed) == changed
	check(patched_ok, "four actual AI scripts compile through canonical Global cache route")
	check(guarded_ok, "modified sources and repeated patching safely retain input")
	var current_sort = dm.vstate_no
	dm.vstate_no = dm.vstates_sort.find(faction_id)
	var ai = global.load_script("affiars/auto_events/affiars_AI_control.gd")
	var aggressive_wars = 0
	var aggressive_develop = 0
	var defensive_wars = 0
	var defensive_develop = 0
	var bounded_pool = true
	service.set_manual(fallback_id, "好战", "进取")
	for _attempt in range(200):
		ai._update_ai_work()
		var pool: Array = dm.get_env_array("内政.AI战略")
		bounded_pool = bounded_pool and pool.size() == 5 and pool.has("发展") and pool.has("策略") and pool.has("战争")
		aggressive_wars += pool.count("战争")
		aggressive_develop += pool.count("发展")
	service.set_manual(fallback_id, "守成", "重才")
	for _attempt in range(200):
		ai._update_ai_work()
		var pool: Array = dm.get_env_array("内政.AI战略")
		bounded_pool = bounded_pool and pool.size() == 5 and pool.has("发展") and pool.has("策略") and pool.has("战争")
		defensive_wars += pool.count("战争")
		defensive_develop += pool.count("发展")
	check(bounded_pool, "personality keeps native five-action pool and all action types")
	check(aggressive_wars > defensive_wars and defensive_develop > aggressive_develop, "real AI pools show distinct ruler preferences across repeated decisions")
	service.set_enabled(false)
	# Bound native flows execute synchronously in add_flow(). Exercise the real
	# action dispatcher, but isolate its downstream event chain with the engine's
	# existing test mode; otherwise random diplomacy can end this fixture's turn
	# before the following public UI and trial checks even begin.
	var prior_test_mode = sm.is_test_running
	sm.is_test_running = true
	dm.orderbook = 30
	ai.AI_actions()
	sm.is_test_running = prior_test_mode
	check(dm.get_env_array("内政.AI战略").size() <= 5 and not dm.common_variable.has("内政.AI性格君主"), "disabling mid-cycle discards old personality action pool")
	root.get_node("FlowManager").clear()
	ai._update_ai_work()
	check(dm.get_env_array("内政.AI战略") == ["策略", "发展", "战争", "发展", "策略"], "disabled mode restores original native action pool")
	service.set_enabled(true)
	dm.vstate_no = current_sort
	dm.set_save_data(legacy.duplicate(true))
	sm.go_to_scene("res://scene/scene_affiars/scene_affiars.tscn")
	yield(frames(), "completed")
	stable_affairs()
	yield(frames(), "completed")
	service.prepare_save()
	var before_public = state_hash()
	var canvas = CanvasLayer.new()
	canvas.layer = 120
	root.add_child(canvas)
	var panel = load("res://ios_ruler_personality_panel.gd").new()
	panel.layer = canvas
	canvas.add_child(panel)
	var ready_for_public = not root.get_node("FlowManager").has_task() and root.get_node("LoadControl")._script_object.empty() and sm.current_scene().affiars_run.player_control.get_view_model() == 1
	check(ready_for_public and panel.open_manager(), "public ruler panel opens in stable native player scene")
	yield(frames(), "completed")
	panel.hide()
	yield(frames(), "completed")
	check(state_hash() == before_public, "opening and closing public panel never edits campaign")
	var trial = root.get_node("TrialSession")
	var formal = state_hash()
	var trial_config = {"mode": "plain", "left": {"actor_id": 2, "side": "阳", "level": 8, "soldiers": 1000, "skills": {}, "equipment": {}}, "right": {"actor_id": 25, "side": "default", "level": 8, "soldiers": 1000, "skills": {}, "equipment": {}}}
	check(trial.start_trial(trial_config).empty(), "trial starts with formal personality metadata")
	yield(frames(35), "completed")
	service.set_manual(2, "机会", "守成")
	service.set_enabled(false)
	trial.finish_trial()
	check(state_hash() == formal, "trial personality changes cannot leak into formal campaign")
	for child in trial.get_children():
		if child is CanvasLayer:
			child.queue_free()
	service.set_manual(2, "好战", "进取")
	service.set_enabled(false)
	var reload_data: Dictionary = dm.get_save_data().duplicate(true)
	var paths_to_load = []
	paths_to_load.append(write_slot(reload_data, "personality_a"))
	var second_save = reload_data.duplicate(true)
	second_save.common_variable.erase(service.STATE_KEY)
	paths_to_load.append(write_slot(second_save, "personality_b"))
	paths_to_load.append(paths_to_load[1])
	var previous_token = service.session_token()
	for path in paths_to_load:
		root.get_node("FlowManager")._translate("load_game_data|" + path, false)
		yield(frames(6), "completed")
		stable_affairs()
		check(service.session_token() != previous_token, "real native load changes token including repeat slot")
		previous_token = service.session_token()
		if path.ends_with("personality_a.sav"):
			check(service.profile_for(2, false).source == "手动设置" and not service.is_enabled(), "native slot A restores its own manual setting and feature switch")
		if path.ends_with("personality_b.sav"):
			check(service.profile_for(2, false).source == "人物预设" and service.is_enabled(), "legacy alternate slot does not inherit other save manual settings")
	var before_new_campaign = service.session_token()
	service.set_manual(2, "好战", "进取")
	service.set_enabled(false)
	yield(start_new_campaign(), "completed")
	check(service.session_token() != before_new_campaign, "full native new campaign changes session token")
	check(service.profile_for(2, false).source == "人物预设" and service.is_enabled(), "new campaign discards prior campaign manual personality and switch")
	print("FEATURE_RESULT ", checks, " ", failures)
	quit(1 if failures > 0 else 0)
