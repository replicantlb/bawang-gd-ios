extends SceneTree

var checks := 0
var failures := 0


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


func campaign_hash() -> int:
	var data = root.get_node("DataManager").get_save_data().duplicate(true)
	data.erase("存档时间")
	return data.hash()


func read_text(path: String) -> String:
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return "MISSING"
	var content = file.get_as_text()
	file.close()
	return content


func profile(actor_id: int, scope: String) -> Dictionary:
	var helper = root.get_node("SkillHelper")
	var skills = {}
	for side in helper.actor_skill_scopes(actor_id):
		skills[side] = helper._raw_actor_skill_configuration(actor_id, side, true)
	return {"actor_id": actor_id, "side": scope, "level": 8, "soldiers": 1000, "skills": skills[scope], "skills_by_scope": skills, "equipment": {"武器": 0, "防具": 0, "道具": 0, "坐骑": 0}}


func _run():
	yield(self, "idle_frame")
	var name = OS.get_environment("BAWANG_QA_NAME")
	if not name.begins_with("BawangFeatureQA-") or OS.get_user_data_dir().get_file() != name:
		push_error("Refusing to test outside isolated QA data")
		quit(1)
		return
	var dm = root.get_node("DataManager")
	var sm = root.get_node("SceneManager")
	var helper = root.get_node("SkillHelper")
	var trial = root.get_node("TrialSession")
	var fixture = JSON.parse(read_text(OS.get_environment("BAWANG_QA_SAVE")))
	check(fixture.error == OK and fixture.result is Dictionary, "read fixture")
	if failures > 0:
		quit(1)
		return
	dm.set_save_data(fixture.result)
	sm.go_to_scene("res://scene/scene_affiars/scene_affiars.tscn")
	yield(frames(), "completed")
	root.get_node("FlowManager").clear()
	root.get_node("LoadControl").end_script()
	sm.current_scene().affiars_run._init()
	sm.current_scene().affiars_run.player_control.player_ready()
	yield(frames(), "completed")
	check(trial.can_start_trial().empty(), "stable campaign accepted")
	dm.set_env("挑战赛", {"version": root.get_node("StaticManager").CURRENT_CHALLANGE_VERSION})
	var scene_id = sm.current_scene().get_instance_id()
	var config = {"mode": "plain", "left": profile(2, "阴"), "right": profile(25, "default")}
	config.left.skills_by_scope["阳"].LV1 = "神武"
	config.left.skills_by_scope["阴"].LV1 = "智神"
	config.left.skills = config.left.skills_by_scope["阴"].duplicate()
	var invalid = config.duplicate(true)
	invalid.right.actor_id = invalid.left.actor_id
	check(not trial.validate_configuration(invalid).empty(), "reject same officer")
	var global = root.get_node("Global")
	global.save_file_text("user://trial-qa-sentinel.txt", "FORMAL")
	var original_sentinel = read_text("user://trial-qa-sentinel.txt")
	var formal_save = dm.get_common_path() + "save/paused.sav"
	var original_paused = read_text(formal_save)
	for mode in ["plain", "walldoor", "wallcity", "solo", "war"]:
		config.mode = mode
		sm.Quit.show_menu()
		var was_menu_processing = sm.Quit.is_processing()
		var original = campaign_hash()
		check(trial.start_trial(config).empty(), mode + " starts from real menu")
		yield(frames(35), "completed")
		check(trial.active and sm.VirtualKey.visible and sm.VirtualKey.emu_enable and not paused, mode + " touch controls available")
		check(not dm.is_challange_game(), mode + " campaign challenge does not suppress trial skills")
		check(dm.get_war_actor(2).get_controlNo() == root.get_node("AutoLoad").playerNo and dm.get_war_actor(25).get_controlNo() < 0, mode + " correct player and AI")
		check(helper.get_actor_default_skill_names(2, "阳").LV1 == "神武" and helper.get_actor_default_skill_names(2, "阴").LV1 == "智神", mode + " both skill faces retained")
		global.save_file_text("user://trial-qa-sentinel.txt", "TRIAL")
		dm.auto_save("paused")
		check(read_text("user://trial-qa-sentinel.txt") == original_sentinel and read_text(formal_save) == original_paused, mode + " file writes isolated")
		check(sm.save_current_scene(0).empty(), mode + " native scene persistence blocked")
		Input.action_press("EMU_MENU")
		yield(frames(3), "completed")
		Input.action_release("EMU_MENU")
		check(not sm.Quit.visible and not paused and sm.VirtualKey.visible, mode + " menu cannot invisibly pause trial")
		trial.finish_trial()
		check(not trial.active and sm.current_scene().get_instance_id() == scene_id and campaign_hash() == original, mode + " original scene and campaign restored")
		check(sm.Quit.is_processing() == was_menu_processing, mode + " original menu input restored")
		for child in trial.get_children():
			if child is CanvasLayer:
				child.queue_free()
		sm.Quit._on_btnBackToGame_pressed()
		yield(frames(2), "completed")
	var roster_script = load("res://ios_prison_roster.gd")
	check(roster_script.can_open(), "prison roster allowed in own turn")
	var before_roster = campaign_hash()
	var layer = CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	var roster = roster_script.new()
	roster.layer = layer
	layer.add_child(roster)
	check(roster.open_manager(), "open prisoner roster")
	var expected = []
	for city in dm.citys:
		if int(city.get("归属", -1)) == roster.owner_id:
			for actor_id in city.get("监狱", []):
				if not int(actor_id) in expected:
					expected.append(int(actor_id))
	var actual = []
	for record in roster.records:
		actual.append(record.actor_id)
	expected.sort()
	actual.sort()
	check(expected == actual, "all own prisons and no enemy prisons")
	roster.search.text = "不会匹配的测试姓名"
	roster._apply_filters()
	check(roster.filtered.empty() and roster.locate_button.disabled, "empty filter safe")
	roster.hide()
	check(campaign_hash() == before_roster, "browsing leaves campaign unchanged")
	trial._write_recovery({"current_scene_path": "res://scene/scene_affiars/scene_affiars.tscn", "actors": [], "citys": []})
	check(trial.read_recovery().has("error"), "reject checksummed but malformed recovery")
	trial.discard_recovery()
	var temporary = trial.RECOVERY_PATH + ".tmp"
	Directory.new().make_dir(temporary)
	var original = campaign_hash()
	check(not trial.start_trial(config).empty() and not trial.active and campaign_hash() == original, "journal write failure leaves original campaign intact")
	Directory.new().remove(temporary)
	print("FEATURE_RESULT ", checks, " ", failures)
	quit(1 if failures > 0 else 0)
