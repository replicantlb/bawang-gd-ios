extends Node

signal trial_started
signal trial_finished

const RECOVERY_PATH = "user://trial_recovery.json"
const SANDBOX_ROOT = "user://trial_sandbox/"
const AFFAIRS_PATH = "res://scene/scene_affiars/scene_affiars.tscn"
const WAR_PATH = "res://scene/scene_war/scene_war.tscn"
const BATTLE_PATH = "res://scene/scene_battle/scene_battle.tscn"
const SOLO_PATH = "res://scene/scene_solo/scene_solo.tscn"
const LEVELS = ["LV1", "LV2", "LV3", "LV4", "LV5", "LV6", "LV7", "LV8"]
const EQUIPMENT_SLOTS = ["武器", "防具", "道具", "坐骑"]
const RUNTIME_NODES = ["Global", "StaticManager", "DataManager", "ActorHelper", "SkillHelper", "OrderHistory", "EndlessGame", "AutoLoad", "FlowManager", "LoadControl", "SceneManager", "PrisonViewState"]

var active := false
var restoring := false
var configuration := {}
var last_error := ""
var _launching := false
var _finishing := false
var _snapshot := {}
var _runtime := {}
var _index_state := {}
var _formal_scene: Node
var _formal_parent: Node
var _formal_ui := []
var _was_paused := false
var _engine_time_scale := 1.0
var _exit_layer: CanvasLayer
var _finish_message := "已退出试炼。原战役进度已恢复。"
var _recovery_layer: CanvasLayer


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(true)
	call_deferred("_prompt_recovery")


func sandbox_path() -> String:
	return OS.get_user_data_dir() + "/trial_sandbox/sgz/"


func sandbox_write_path(path: String) -> String:
	var absolute = ProjectSettings.globalize_path(path).simplify_path()
	var root_path = OS.get_user_data_dir()
	var sandbox = root_path + "/trial_sandbox/"
	if absolute.begins_with(sandbox):
		return absolute
	var relative = absolute.substr(root_path.length() + 1) if absolute.begins_with(root_path + "/") else "external/" + absolute.sha256_text() + ".txt"
	var target = sandbox + relative
	Directory.new().make_dir_recursive(target.get_base_dir())
	return target


func can_start_trial() -> String:
	if active or restoring:
		return "请先结束当前试炼。"
	if has_recovery():
		return "上次试炼尚有恢复记录，请先恢复或放弃恢复。"
	if DataManager.get_current_scene_id() != 10000:
		return "请回到内政大地图后开始试炼。"
	if AutoLoad.check_is_multigame() or DataManager.is_autoplay_mode():
		return "试炼仅支持单机手动操作。"
	var scene = SceneManager.current_scene()
	if scene == null or scene.get("affiars_run") == null:
		return "内政界面尚未准备完成。"
	if FlowManager.has_task() or not LoadControl._script_object.empty():
		return "请先结束当前对话或事件，再开始试炼。"
	if SceneManager.popuped:
		return "请先关闭当前提示，再开始试炼。"
	if scene.affiars_run.player_control.get_view_model() != 1:
		return "请回到选择城市的内政主界面，再开始试炼。"
	return ""


func validate_configuration(config: Dictionary) -> String:
	if not config.get("mode") in ["war", "plain", "walldoor", "wallcity", "solo"]:
		return "请选择试炼场景。"
	for key in ["left", "right"]:
		var side = config.get(key)
		if not side is Dictionary:
			return "请设置交战双方。"
		var actor_id = side.get("actor_id", -1)
		if not actor_id is int or actor_id < 0 or actor_id >= DataManager.actors.size():
			return "武将编号无效。"
		if not side.get("level", 8) is int or side.get("level", 8) < 1 or side.get("level", 8) > 8:
			return "武将等级必须在 1～8 之间。"
		if not side.get("soldiers", 1000) is int or side.get("soldiers", 1000) < 1 or side.get("soldiers", 1000) > 9999:
			return "兵力必须在 1～9999 之间。"
		var scope = str(side.get("side", "default"))
		var scopes = SkillHelper.actor_skill_scopes(actor_id)
		if not scope in scopes:
			return "武将技能面不匹配。"
		var skills = side.get("skills", {})
		if not skills is Dictionary:
			return "技能配置无效。"
		var skill_scopes = side.get("skills_by_scope", {scope: skills})
		if not skill_scopes is Dictionary:
			return "技能配置无效。"
		var patch = load("res://ios_skill_defaults.gd").new()
		var error = patch.validate_scopes(actor_id, skill_scopes, str(DataManager.actors[actor_id].get("性别", "")))
		if not error.empty():
			return error
		var equipment = side.get("equipment", {})
		if not equipment is Dictionary:
			return "装备配置无效。"
		var factory = load("res://script/objects/clEquip.gd")
		for slot in equipment:
			if not slot in EQUIPMENT_SLOTS or not equipment[slot] is int:
				return "装备配置无效。"
			var found = false
			for equip in factory.all_equips(slot, true):
				if equip.id == equipment[slot]:
					found = true
					break
			if not found:
				return "选择的装备不存在。"
	if config.left.actor_id == config.right.actor_id:
		return "交战双方请选择不同武将。"
	return ""


func start_trial(config: Dictionary) -> String:
	last_error = can_start_trial()
	if not last_error.empty():
		return last_error
	last_error = validate_configuration(config)
	if not last_error.empty():
		return last_error
	_snapshot = DataManager.get_save_data().duplicate(true)
	last_error = _write_recovery(_snapshot)
	if not last_error.empty():
		_snapshot.clear()
		return last_error
	last_error = _prepare_sandbox()
	if not last_error.empty():
		Directory.new().remove(RECOVERY_PATH)
		_snapshot.clear()
		return last_error
	configuration = config.duplicate(true)
	_finish_message = "已退出试炼。原战役进度已恢复。"
	_was_paused = get_tree().paused
	_engine_time_scale = Engine.time_scale
	_formal_scene = SceneManager.current_scene()
	_formal_parent = _formal_scene.get_parent()
	_formal_ui.clear()
	_capture_ui(SceneManager)
	_runtime.clear()
	# Retain the original containers, and give the trial its own containers before
	# native reset/load code can clear or update them in place.
	for name in RUNTIME_NODES:
		var node = get_node_or_null("/root/" + name)
		if node != null:
			_runtime[name] = _detach_script_state(node)
	_index_state = _detach_script_state(StaticManager.saveIdx)
	active = true
	_launching = true
	_release_input()
	_formal_parent.remove_child(_formal_scene)
	DataManager.set_save_data(_snapshot.duplicate(true))
	# Challenge restrictions belong to the retained campaign, not this sandbox.
	DataManager.unset_env("挑战赛")
	DataManager.game_set["技能系统"] = "是"
	DataManager.endless_mode = false
	FlowManager.clear()
	LoadControl.end_script()
	SceneManager.Quit._on_btnBackToGame_pressed()
	SceneManager.VirtualKey.show()
	SceneManager.VirtualKey.emu_enable = true
	SceneManager.hide_all_tool()
	SceneManager.Quit.hide()
	SceneManager.black.hide()
	get_tree().paused = false
	_create_exit_button()
	_initialize_war()
	call_deferred("_launch_scene")
	emit_signal("trial_started")
	return ""


func _initialize_war() -> void:
	var left_id: int = configuration.left.actor_id
	var right_id: int = configuration.right.actor_id
	# Dedicated forces make every historical or custom officer selectable,
	# independently of their allegiance or life status in the campaign.
	DataManager.citys[0]["归属"] = 0
	DataManager.citys[1]["归属"] = 1
	DataManager.vstates_alliance.clear()
	for city in DataManager.citys:
		for key in ["武将", "监狱"]:
			if city.get(key) is Array:
				city[key].erase(left_id)
				city[key].erase(right_id)
	for item in [[0, left_id], [1, right_id]]:
		DataManager.citys[item[0]]["武将"] = [item[1]]
		DataManager.citys[item[0]]["监狱"] = []
		DataManager.vstates[item[0]]["君主"] = item[1]
		DataManager.vstates[item[0]]["状态"] = "正常"
		DataManager.vstates[item[0]]["继承人"] = [item[1]]
		DataManager.vstates[item[0]]["友好势力"] = []
		DataManager.vstates[item[0]]["仇恨势力"] = []
	DataManager.players.resize(1)
	DataManager.players[0].actorId = left_id
	_apply_actor(configuration.left, 0)
	_apply_actor(configuration.right, 1)
	var wf = DataManager.new_war_fight(0, 1)
	var factory = load("res://script/War_Vstate.gd")
	wf.attackerWV = factory.new(wf.fromVstateId, false, true)
	wf.defenderWV = factory.new(wf.targetVstateId, false, false)
	for item in [[wf.attackerWV, left_id, 0], [wf.defenderWV, right_id, 1]]:
		item[0].from_cityId = item[2]
		item[0].init_actors = [item[1]]
		item[0].main_actorId = item[1]
		item[0].money = 1000
		item[0].rice = 30000
	wf.sendActors = [left_id]
	wf.init_war()
	wf.get_war_actor(left_id).position = Vector2(6, 6)
	wf.get_war_actor(right_id).position = Vector2(7, 6)
	DataManager.set_env("战争-当前步骤", -1)
	DataManager.set_env("战争-下个步骤", -1)
	SkillHelper.reset_skills_list_cache(false)
	if configuration.mode == "war":
		return
	var bf = DataManager.new_battle_fight(left_id)
	bf.targetId = right_id
	bf.terrian = "land" if configuration.mode in ["plain", "solo"] else configuration.mode
	bf.fromTerrian = "land"
	bf.locationX = 7
	bf.locationY = 6
	DataManager.set_env("白兵战-当前步骤", -1)
	DataManager.set_env("白兵战-下个步骤", -1)
	DataManager.battle_run = configuration.mode != "solo"
	if configuration.mode == "solo":
		bf.ready_to_start()
		bf.get_attacker().battle_init()
		bf.get_defender().battle_init()


func _apply_actor(settings: Dictionary, city_id: int) -> void:
	var actor = ActorHelper.actor(settings.actor_id)
	actor.set_status_officed(city_id)
	actor.set_level(settings.get("level", 8))
	actor.set_hp(actor.get_max_hp())
	actor.set_soldiers(settings.get("soldiers", 1000))
	if settings.get("side", "default") != "default":
		actor.set_side(settings.side)
	var scope = settings.get("side", "default")
	var edits = DataManager.actors[settings.actor_id].get("ios_skill_edits", {}).duplicate(true)
	for key in settings.get("skills_by_scope", {scope: settings.get("skills", {})}):
		edits[key] = settings.get("skills_by_scope", {scope: settings.get("skills", {})})[key].duplicate(true)
	DataManager.actors[settings.actor_id]["ios_skill_edits"] = edits
	var factory = load("res://script/objects/clEquip.gd")
	for slot in settings.get("equipment", {}):
		actor.set_equip(factory.equip(settings.equipment[slot], slot))


func _launch_scene() -> void:
	var path = WAR_PATH if configuration.mode == "war" else SOLO_PATH if configuration.mode == "solo" else BATTLE_PATH
	SceneManager.go_to_scene(path)
	for _frame in range(120):
		yield(get_tree(), "idle_frame")
		if not active:
			return
		var scene = SceneManager.current_scene()
		if scene != null and scene.filename == path and SceneManager.load_scene_complete:
			if configuration.mode == "war":
				scene.war_auto_run.war_step_0()
			elif configuration.mode == "solo":
				FlowManager.add_flow("solo_run_start")
			else:
				FlowManager.add_flow("battle_run_start")
			_launching = false
			return
	last_error = "试炼场景加载失败，已返回原战役。"
	finish_trial()


func intercept_scene_change(path: String) -> bool:
	if not active or restoring or _launching:
		return false
	var allowed = [WAR_PATH, BATTLE_PATH, SOLO_PATH] if configuration.mode == "war" else [SOLO_PATH] if configuration.mode == "solo" else [BATTLE_PATH, SOLO_PATH]
	if path in allowed:
		return false
	# Native victory/defeat/retreat may queue more settlement flows after changing
	# scenes. Stop those flows before returning to the retained campaign scene.
	FlowManager.enable_add = false
	FlowManager.clear()
	_finish_message = _result_summary()
	get_tree().paused = true
	call_deferred("finish_trial")
	return true


func finish_trial() -> void:
	if not active or _finishing:
		return
	_finishing = true
	restoring = true
	get_tree().paused = true
	_release_input()
	FlowManager.clear()
	LoadControl.end_script()
	for child in SceneManager.scene_layer.get_children():
		SceneManager.scene_layer.remove_child(child)
		child.queue_free()
	for name in RUNTIME_NODES:
		var node = get_node_or_null("/root/" + name)
		if node != null and _runtime.has(name):
			_restore_script_state(node, _runtime[name])
	_restore_script_state(StaticManager.saveIdx, _index_state)
	if is_instance_valid(_formal_scene) and is_instance_valid(_formal_parent):
		_formal_parent.add_child(_formal_scene)
	for state in _formal_ui:
		var node = state.node
		if not is_instance_valid(node):
			continue
		node.set_process(state.process)
		node.set_physics_process(state.physics)
		node.set_process_input(state.input)
		node.set_process_unhandled_input(state.unhandled)
		node.set_process_unhandled_key_input(state.unhandled_key)
		if state.has("visible"):
			node.visible = state.visible
		if state.has("disabled"):
			node.disabled = state.disabled
		if state.has("emu_enable"):
			node.emu_enable = state.emu_enable
	if is_instance_valid(_exit_layer):
		_exit_layer.queue_free()
	active = false
	restoring = false
	_launching = false
	_finishing = false
	_runtime.clear()
	_index_state.clear()
	_formal_ui.clear()
	_snapshot.clear()
	Directory.new().remove(RECOVERY_PATH)
	get_tree().paused = _was_paused
	Engine.time_scale = _engine_time_scale
	SoundManager.stop()
	SoundManager.play_bgm()
	SoundManager.pause(_was_paused)
	emit_signal("trial_finished")
	_show_finished_message(_finish_message)


func _process(_delta: float) -> void:
	if not active:
		return
	if SceneManager.Quit.visible:
		SceneManager.Quit._on_btnBackToGame_pressed()
	var button = SceneManager.VirtualKey.get_node_or_null("btnSetting")
	if button != null:
		button.hide()
		if button is BaseButton:
			button.disabled = true


func _create_exit_button() -> void:
	_exit_layer = CanvasLayer.new()
	_exit_layer.layer = 125
	_exit_layer.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(_exit_layer)
	var button = Button.new()
	button.text = "退出试炼"
	button.rect_position = Vector2(14, 12)
	button.rect_min_size = Vector2(150, 58)
	button.add_font_override("font", _ui_font())
	button.connect("pressed", self, "finish_trial")
	_exit_layer.add_child(button)


func _ui_font():
	var font = SceneManager.tips.get_font("font").duplicate()
	if font is DynamicFont:
		font.size = 24
	return font


func _result_summary() -> String:
	if configuration.mode in ["plain", "walldoor", "wallcity"]:
		var fight = DataManager.get_current_battle_fight()
		if fight != null and fight.get_winner() != null:
			return "本次试炼：%s获胜。\n已返回原战役，试炼结果不影响战役。" % fight.get_winner().get_name()
	return "本次试炼已结束。\n已返回原战役，试炼结果不影响战役。"


func _show_finished_message(message: String, title := "试炼结束") -> void:
	var layer = CanvasLayer.new()
	layer.layer = 126
	layer.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(layer)
	var dialog = AcceptDialog.new()
	dialog.window_title = title
	dialog.dialog_text = message
	dialog.popup_exclusive = true
	dialog.add_font_override("font", _ui_font())
	dialog.add_font_override("title_font", _ui_font())
	dialog.get_label().add_font_override("font", _ui_font())
	dialog.get_ok().text = "返回战役"
	dialog.get_ok().rect_min_size = Vector2(180, 48)
	dialog.get_ok().add_font_override("font", _ui_font())
	dialog.connect("popup_hide", layer, "queue_free")
	layer.add_child(dialog)
	dialog.popup_centered(Vector2(560, 190))


func _prompt_recovery() -> void:
	if not has_recovery() or active:
		return
	# Main installs its initial scene after autoloads. Wait for that scene so the
	# recovery choice appears above the title screen, before any new campaign.
	for _frame in range(120):
		yield(get_tree(), "idle_frame")
		if SceneManager.current_scene() != null:
			break
	if not has_recovery() or active:
		return
	_recovery_layer = CanvasLayer.new()
	_recovery_layer.layer = 130
	_recovery_layer.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(_recovery_layer)
	var dialog = ConfirmationDialog.new()
	dialog.window_title = "恢复原战役"
	dialog.dialog_text = "上次试炼未正常结束。\n是否恢复到开始试炼前的原战役？\n正式存档没有被试炼覆盖。"
	dialog.popup_exclusive = true
	dialog.get_ok().text = "恢复战役"
	dialog.get_cancel().text = "放弃恢复"
	dialog.add_font_override("title_font", _ui_font())
	dialog.get_label().add_font_override("font", _ui_font())
	dialog.get_ok().rect_min_size = Vector2(180, 48)
	dialog.get_cancel().rect_min_size = Vector2(180, 48)
	for control in [dialog, dialog.get_ok(), dialog.get_cancel()]:
		control.add_font_override("font", _ui_font())
	dialog.connect("confirmed", self, "_recovery_confirmed")
	dialog.get_cancel().connect("pressed", self, "_recovery_discarded")
	dialog.connect("popup_hide", self, "_recovery_prompt_closed")
	_recovery_layer.add_child(dialog)
	get_tree().paused = true
	dialog.popup_centered(Vector2(600, 220))


func _recovery_prompt_closed() -> void:
	if is_instance_valid(_recovery_layer):
		_recovery_layer.queue_free()
	if not restoring:
		get_tree().paused = false


func _recovery_confirmed() -> void:
	if is_instance_valid(_recovery_layer):
		_recovery_layer.queue_free()
	get_tree().paused = false
	var error = recover_trial()
	if not error.empty():
		_show_finished_message(error + "\n恢复记录已保留，正式存档未改变。", "恢复失败")


func _recovery_discarded() -> void:
	discard_recovery()
	if is_instance_valid(_recovery_layer):
		_recovery_layer.queue_free()
	get_tree().paused = false


func _release_input() -> void:
	for pad in get_tree().get_nodes_in_group("ios_virtual_pad"):
		pad.release_all_touches()
	for action in InputMap.get_actions():
		Input.action_release(action)


func _detach_script_state(object: Object) -> Dictionary:
	var state = {}
	for property in object.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var value = object.get(property.name)
		state[property.name] = value
		if value is Dictionary or value is Array:
			object.set(property.name, value.duplicate(true))
	return state


func _restore_script_state(object: Object, state: Dictionary) -> void:
	for key in state:
		object.set(key, state[key])


func _capture_ui(node: Node) -> void:
	var state = {"node": node, "process": node.is_processing(), "physics": node.is_physics_processing(), "input": node.is_processing_input(), "unhandled": node.is_processing_unhandled_input(), "unhandled_key": node.is_processing_unhandled_key_input()}
	if node is CanvasItem:
		state.visible = node.visible
		if node is BaseButton:
			state.disabled = node.disabled
	if node == SceneManager.VirtualKey:
		state.emu_enable = node.emu_enable
	_formal_ui.append(state)
	for child in node.get_children():
		_capture_ui(child)


func _prepare_sandbox() -> String:
	var directory = Directory.new()
	for path in [sandbox_path() + "save", sandbox_path() + "mod/patches", SANDBOX_ROOT + "save_scene"]:
		if directory.make_dir_recursive(path) != OK:
			return "无法创建试炼目录，未开始试炼。"
	# Native loading also reloads historical-actor and equipment definitions.
	# Copy those definitions into the sandbox so patched equipment remains valid.
	var formal_root = OS.get_user_data_dir() + "/sgz/mod/patches/"
	for name in ["actors.json", "equips.json"]:
		directory.remove(sandbox_path() + "mod/patches/" + name)
		if File.new().file_exists(formal_root + name):
			if directory.copy(formal_root + name, sandbox_path() + "mod/patches/" + name) != OK:
				return "无法准备试炼装备与武将配置，未开始试炼。"
	return ""


func _write_recovery(snapshot: Dictionary) -> String:
	var content = JSON.print(snapshot)
	var document = {"kind": "bawang-trial-recovery", "format": 1, "snapshot": snapshot, "sha256": content.sha256_text()}
	var file = File.new()
	if file.open(RECOVERY_PATH + ".tmp", File.WRITE) != OK:
		return "无法创建战役恢复记录，未开始试炼。"
	file.store_string(JSON.print(document))
	file.flush()
	var result = file.get_error()
	file.close()
	if result != OK or Directory.new().rename(RECOVERY_PATH + ".tmp", RECOVERY_PATH) != OK:
		return "战役恢复记录写入失败，未开始试炼。"
	return ""


func has_recovery() -> bool:
	return File.new().file_exists(RECOVERY_PATH)


func read_recovery() -> Dictionary:
	var file = File.new()
	if file.open(RECOVERY_PATH, File.READ) != OK:
		return {"error": "无法读取试炼恢复记录。"}
	if file.get_len() > 32 * 1024 * 1024:
		file.close()
		return {"error": "试炼恢复记录过大。"}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or not parsed.result is Dictionary:
		return {"error": "试炼恢复记录损坏。"}
	var data: Dictionary = parsed.result
	if data.get("kind") != "bawang-trial-recovery" or data.get("format") != 1 or not data.get("snapshot") is Dictionary:
		return {"error": "试炼恢复记录格式无效。"}
	if JSON.print(data.snapshot).sha256_text() != data.get("sha256", ""):
		return {"error": "试炼恢复记录校验失败。"}
	if data.snapshot.get("current_scene_path") != AFFAIRS_PATH or not data.snapshot.get("actors") is Array or not data.snapshot.get("citys") is Array:
		return {"error": "试炼恢复记录的战役无效。"}
	var storage = load("res://ios_storage_service.gd").new()
	var error = storage.validate_content("save/paused.sav", JSON.print(data.snapshot))
	if not error.empty():
		return {"error": "试炼恢复记录无效：" + error}
	if data.snapshot.common_variable.get("内政-玩家-步骤", -1) != 1 or data.snapshot.battle_run:
		return {"error": "试炼恢复记录并非稳定的内政主界面。"}
	return {"data": data.snapshot}


func recover_trial() -> String:
	if active or restoring:
		return "请先结束当前试炼。"
	var read = read_recovery()
	if read.has("error"):
		return read.error
	restoring = true
	DataManager.set_save_data(read.data)
	FlowManager.clear()
	LoadControl.end_script()
	SceneManager.go_to_scene(AFFAIRS_PATH)
	call_deferred("_resume_recovered_campaign")
	return ""


func _resume_recovered_campaign() -> void:
	for _frame in range(120):
		yield(get_tree(), "idle_frame")
		var scene = SceneManager.current_scene()
		if scene != null and scene.filename == AFFAIRS_PATH and SceneManager.load_scene_complete:
			# Resume city selection directly; monthly events, rewards and autosaves
			# have already happened in the captured stable campaign.
			scene.affiars_run.player_control.player_ready()
			restoring = false
			Directory.new().remove(RECOVERY_PATH)
			get_tree().paused = false
			return
	last_error = "恢复界面加载失败，恢复记录已保留。"
	restoring = false


func discard_recovery() -> void:
	if not active and not restoring:
		Directory.new().remove(RECOVERY_PATH)
