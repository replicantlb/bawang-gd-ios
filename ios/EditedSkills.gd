extends "res://script/skill_system/Skill_Helper.gd"

const SAVE_KEY = "ios_skill_edits"
const LEVELS = ["LV1", "LV2", "LV3", "LV4", "LV5", "LV6", "LV7", "LV8"]
const DefaultPatch = preload("res://ios_skill_defaults.gd")


func actor_skill_scopes(actor_id: int) -> Array:
	return DefaultPatch.new().scopes_for_actor(actor_id)


func can_store_actor_defaults(actor_id: int) -> bool:
	return DefaultPatch.new().actor_supported(actor_id)


func save_actor_skill_configuration(actor_id: int, changes_by_scope: Dictionary, also_default: bool, edited_gender: String) -> String:
	if not can_edit_actor_skills(actor_id):
		return "当前模式无法修改技能。"
	var patch = DefaultPatch.new()
	var error = patch.validate_scopes(actor_id, changes_by_scope, edited_gender, true)
	if not error.empty():
		return error
	var configurations = {}
	for scope in actor_skill_scopes(actor_id):
		var original = _raw_actor_skill_configuration(actor_id, scope, false)
		var current = _raw_actor_skill_configuration(actor_id, scope, true)
		for level in changes_by_scope.get(scope, {}):
			current[level] = original.get(level, "") if changes_by_scope[scope][level] == null else changes_by_scope[scope][level]
		configurations[scope] = current
	error = patch.validate_scopes(actor_id, configurations, edited_gender)
	if not error.empty():
		return error
	if also_default:
		if not patch.actor_supported(actor_id):
			return "自建武将请使用创建配置，不写入原版武将默认补丁。"
		var read = patch.read_document()
		if read.has("error"):
			return read.error
		var document: Dictionary = read.data
		document.actors[str(actor_id)] = configurations.duplicate(true)
		error = patch.write_document(document)
		if not error.empty():
			return error
	for scope in changes_by_scope:
		save_actor_skill_edits(actor_id, scope, changes_by_scope[scope])
	return ""


func _raw_actor_skill_configuration(actor_id: int, scope: String, with_edits: bool) -> Dictionary:
	# Runtime getters can upgrade 八阵* after this campaign's event. Defaults
	# must preserve the configured skill, so future campaigns earn that upgrade.
	var source: Dictionary = ActorHelper.actor(actor_id).get_diy_skills() if actor_id == StaticManager.ACTOR_ID_DIY else StaticManager.actor_skills[actor_id]
	var names = {}
	for level in LEVELS:
		var name = str(source.get(level, ""))
		var sides = name.split("/", true)
		if sides.size() > 1:
			name = sides[1] if scope == "阴" else sides[0]
		names[level] = name
	if with_edits:
		var edits = DataManager.actors[actor_id].get(SAVE_KEY, {})
		if edits is Dictionary and edits.get(scope, {}) is Dictionary:
			for level in LEVELS:
				var value = edits.get(scope, {}).get(level)
				if value is String:
					names[level] = value
	return names


func apply_skill_defaults_to_new_campaign() -> void:
	# Same-scenario resource reloads can retain actor metadata. Detach it before
	# seeding a new campaign, including when the global file is invalid.
	DataManager.actors = DataManager.actors.duplicate(true)
	for record in DataManager.actors:
		record.erase(SAVE_KEY)
	DataManager.common_variable.erase("ios_skill_defaults")
	reset_skills_list_cache(SKILLS_LIST_CACHE_ENABLED)
	var patch = DefaultPatch.new()
	var read = patch.read_document()
	if read.has("error"):
		return
	for actor_key in read.data.actors:
		var actor_id = int(actor_key)
		if actor_id >= DataManager.actors.size():
			continue
		DataManager.actors[actor_id][SAVE_KEY] = read.data.actors[actor_key].duplicate(true)
	if not read.data.actors.empty():
		DataManager.common_variable["ios_skill_defaults"] = {"format": 1, "actors": read.data.actors.keys(), "patch_hash": JSON.print(read.data).sha256_text()}
	reset_skills_list_cache(SKILLS_LIST_CACHE_ENABLED)


func can_edit_actor_skills(actor_id: int) -> bool:
	return actor_id >= 0 and actor_id < DataManager.actors.size() \
		and actor_id < StaticManager.actor_skills.size() \
		and DataManager.get_game_setting("技能系统") == "是" \
		and DataManager.cheater_disabled().empty()


func actor_skill_scope(actor_id: int, side := "") -> String:
	var actor = ActorHelper.actor(actor_id)
	if not actor.has_side():
		return "default"
	if side.empty():
		side = actor.get_side()
	if side in ["阴", "醉", "魂"]:
		return "阴"
	if side in ["", "阳"]:
		return "阳"
	return ""


func save_actor_skill_edits(actor_id: int, scope: String, changes: Dictionary) -> void:
	if changes.empty() or scope.empty() or not can_edit_actor_skills(actor_id):
		return
	var record: Dictionary = DataManager.actors[actor_id]
	var edits = record.get(SAVE_KEY, {})
	if not edits is Dictionary:
		edits = {}
	var slots = edits.get(scope, {})
	if not slots is Dictionary:
		slots = {}
	for level in changes:
		if not level in LEVELS:
			continue
		if changes[level] == null:
			slots.erase(level)
		elif changes[level] is String:
			slots[level] = changes[level]
	if slots.empty():
		edits.erase(scope)
	else:
		edits[scope] = slots
	if edits.empty():
		record.erase(SAVE_KEY)
	else:
		record[SAVE_KEY] = edits
	reset_skills_list_cache(SKILLS_LIST_CACHE_ENABLED)


func get_actor_original_skill_names(actor_id: int, side: String = "") -> Dictionary:
	return .get_actor_default_skill_names(actor_id, side)


func get_actor_default_skill_names(actorId: int, specifiedSide: String = "") -> Dictionary:
	var names = .get_actor_default_skill_names(actorId, specifiedSide)
	if actorId < 0 or actorId >= DataManager.actors.size():
		return names
	var edits = DataManager.actors[actorId].get(SAVE_KEY, null)
	if not edits is Dictionary or not DataManager.cheater_disabled().empty():
		return names
	var slots = edits.get(actor_skill_scope(actorId, specifiedSide), null)
	if not slots is Dictionary:
		return names
	for level in LEVELS:
		var skill_name = slots.get(level, null)
		if not skill_name is String:
			continue
		if skill_name.empty():
			names[level] = ""
			continue
		var skill = StaticManager.get_skill(skill_name)
		if skill != null:
			var upgraded: String = skill.upgraded_for_actor(actorId)
			names[level] = upgraded if not upgraded.empty() else skill_name
	return names
