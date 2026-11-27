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


func read_text(path: String) -> String:
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return ""
	var text = file.get_as_text()
	file.close()
	return text


func campaign_hash() -> int:
	var data = root.get_node("DataManager").get_save_data().duplicate(true)
	data.erase("存档时间")
	return data.hash()


func roster():
	var layer = CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	var panel = load("res://ios_prison_roster.gd").new()
	panel.layer = layer
	layer.add_child(panel)
	check(panel.open_manager(), "open native prisoner context")
	return panel


func _run():
	yield(self, "idle_frame")
	var name = OS.get_environment("BAWANG_QA_NAME")
	if not name.begins_with("BawangFeatureQA-") or OS.get_user_data_dir().get_file() != name:
		quit(1)
		return
	var dm = root.get_node("DataManager")
	var sm = root.get_node("SceneManager")
	var global = root.get_node("Global")
	for pair in [["solo_attack", "ios_solo_attack"], ["solo_crazy_attack", "ios_solo_crazy_attack"]]:
		var path = "res://packed/sgz_script/solo/%s.gd" % pair[0]
		var original: String = global.get_file_text(path)
		var patched = read_text("res://%s.gd" % pair[1])
		check(not original.empty() and patched == original.replace("wa.get_name(), rateShow, criticalChance", "wa.get_name(), rate, criticalChance"), pair[0] + " only changes display argument")
		var loaded = global.load_script(path)
		check(loaded != null and loaded.get_script().resource_path == "res://%s.gd" % pair[1], pair[0] + " guarded routing")
		check(global.load_script(path) == loaded and global.SCRIPT_CACHE.get(path) == loaded, pair[0] + " original cache key reused")
	var fixture = JSON.parse(read_text(OS.get_environment("BAWANG_QA_SAVE")))
	check(fixture.error == OK and fixture.result is Dictionary, "fixture parses")
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
	var panel = roster()
	var actor_id = -1
	var city_id = -2
	var origin_id = -2
	var query = ""
	if not panel.records.empty():
		var target: Dictionary = panel.records.back()
		actor_id = target.actor_id
		city_id = target.city_id
		origin_id = target.origin_id
		query = target.name
	panel.search.text = query
	panel._select_id(panel.city_filter, city_id)
	panel._select_id(panel.origin_filter, origin_id)
	panel.sort_filter.select(2)
	panel.descending = true
	panel.selected_actor_id = actor_id
	panel._apply_filters()
	if actor_id >= 0:
		panel._locate_selected()
	else:
		panel.hide()
	yield(frames(2), "completed")
	var after_navigation = campaign_hash()
	panel = roster()
	check(panel.search.text == query and panel.city_filter.get_selected_id() == city_id and panel._selected_origin_id() == origin_id, "reopen restores search and both filters")
	check(panel.sort_filter.selected == 2 and panel.descending and panel.selected_actor_id == actor_id, "reopen restores ordering and selected officer")
	panel.hide()
	check(campaign_hash() == after_navigation, "view restoration does not modify campaign")
	yield(frames(2), "completed")
	var views = root.get_node("PrisonViewState")
	var generation = views.generation_token()
	dm.set_save_data(dm.get_save_data().duplicate(true))
	check(views.generation_token() == generation, "scene-style transfers retain view generation")
	var trial = root.get_node("TrialSession")
	var profile_left = {"actor_id": 2, "side": "阳", "level": 8, "soldiers": 1000, "skills": {}, "equipment": {}}
	var profile_right = {"actor_id": 25, "side": "default", "level": 8, "soldiers": 1000, "skills": {}, "equipment": {}}
	check(trial.start_trial({"mode": "plain", "left": profile_left, "right": profile_right}).empty(), "start native formation fixture")
	yield(frames(35), "completed")
	var menu = sm.image_menu
	check(menu.get_script().resource_path == "res://ios_formation_menu.gd", "native menu uses formation renderer")
	var fight = dm.get_current_battle_fight()
	menu.hide()
	dm.set_env("当前武将", 2)
	var choices := []
	for formation in fight.get_possible_formations(2):
		choices.append([int(formation), false, 22])
	menu.items = choices
	menu.set_lsc(90 + (4 - choices.size()) * 30)
	menu._set_data(0.8)
	menu.show_msg("请排兵布阵：", 2)
	menu.show_orderbook(false)
	menu.show()
	yield(frames(2), "completed")
	check(menu.get_node("FormationPreview").is_visible_in_tree(), "preview visible on first open without cursor input")
	var hints = sm.VirtualKey.get_node("BattleHints")
	check(not hints.entry.visible, "formation preview is not covered by battle hints entry")
	var unit_positions := []
	for unit in dm.battle_units:
		unit_positions.append(unit.unit_position)
	var before_preview = campaign_hash()
	menu._formation_clicked(choices.size() - 1)
	var unchanged = campaign_hash() == before_preview
	for index in range(dm.battle_units.size()):
		unchanged = unchanged and dm.battle_units[index].unit_position == unit_positions[index]
	check(unchanged and menu.cursor_index == choices.size() - 1, "touch preview changes selection without placing units")
	menu.hide()
	check(not menu.get_node("FormationPreview").is_visible_in_tree(), "closing formation hides preview")
	check(hints.entry.visible, "closing formation restores battle hints entry")
	var placement = global.load_script(dm.mod_path + "sgz_script/battle/IFormation.gd")
	for actor in [2, 25]:
		for formation in fight.get_possible_formations(actor):
			var before = campaign_hash()
			var projected: Dictionary = menu.project_formation(actor, formation)
			check(not projected.empty() and campaign_hash() == before, "projection is read only")
			placement.set_formation(actor, formation)
			var matches = true
			for unit in projected.units:
				matches = matches and dm.battle_units[unit.unit_id].unit_position == unit.position
			check(matches, "projection matches native placement including mirror")
	trial.finish_trial()
	check(views.generation_token() == generation, "trial restores campaign UI cache")
	for child in trial.get_children():
		if child is CanvasLayer:
			child.queue_free()
	views.reset_campaign()
	panel = roster()
	check(panel.search.text.empty() and panel.city_filter.get_selected_id() == -2 and panel.sort_filter.selected == 0, "new campaign resets view")
	panel.hide()
	print("FEATURE_RESULT ", checks, " ", failures)
	quit(1 if failures > 0 else 0)
