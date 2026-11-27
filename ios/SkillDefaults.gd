extends Reference

const RELATIVE_PATH = "mod/patches/skills.json"
const LEVELS = ["LV1", "LV2", "LV3", "LV4", "LV5", "LV6", "LV7", "LV8"]
const FORMAT = 1
const MAX_BYTES = 1024 * 1024


func file_path() -> String:
	return DataManager.get_common_path() + RELATIVE_PATH


func empty_document() -> Dictionary:
	return {"kind": "bawang-skill-defaults", "format": FORMAT, "game_version": "2.560", "actors": {}}


func scopes_for_actor(actor_id: int) -> Array:
	if actor_id < 0 or actor_id >= StaticManager.actor_skills.size():
		return []
	for level in LEVELS:
		if str(StaticManager.actor_skills[actor_id].get(level, "")).find("/") >= 0:
			return ["阳", "阴"]
	return ["default"]


func actor_supported(actor_id: int) -> bool:
	return actor_id >= 0 and actor_id < StaticManager.actors.size() and actor_id != StaticManager.ACTOR_ID_DIY


func validate_document(data) -> String:
	if not data is Dictionary:
		return "技能默认补丁必须是对象格式。"
	if not data.get("kind") is String or data.kind != "bawang-skill-defaults" or not data.get("format") is float and not data.get("format") is int:
		return "技能默认补丁格式不支持。"
	if data.format != FORMAT or not data.get("game_version") is String or data.game_version != "2.560" or not data.get("actors") is Dictionary:
		return "技能默认补丁版本不匹配。"
	for actor_key in data.actors:
		if not actor_key is String or not actor_key.is_valid_integer() or str(int(actor_key)) != actor_key:
			return "技能默认补丁有无效的武将编号。"
		var actor_id = int(actor_key)
		if not actor_supported(actor_id):
			return "技能默认补丁仅支持原版武将，自建武将使用创建配置。"
		var error = validate_scopes(actor_id, data.actors[actor_key], str(StaticManager.actors[actor_id].get("性别", "")))
		if not error.empty():
			return "武将 %d：%s" % [actor_id, error]
	return ""


func validate_scopes(actor_id: int, scopes, gender: String, allow_restore := false) -> String:
	if not scopes is Dictionary:
		return "技能面配置无效。"
	var valid_scopes = scopes_for_actor(actor_id)
	for scope in scopes:
		if not scope in valid_scopes or not scopes[scope] is Dictionary:
			return "技能面与武将不符。"
		var used = []
		for level in scopes[scope]:
			if not level in LEVELS:
				return "技能栏位必须是 LV1～LV8。"
			var name = scopes[scope][level]
			if allow_restore and name == null:
				continue
			if not name is String:
				return "技能名称格式无效。"
			if name.empty():
				continue
			var skill = StaticManager.get_skill(name)
			if skill == null or not skill.exclusive_valid_for_actor(actor_id):
				return "「%s」不适用于此武将。" % name
			if not skill._gendersOnly.empty() and not gender in skill._gendersOnly:
				return "「%s」不适用于此性别。" % name
			if name in used:
				return "同一面不能重复配置「%s」。" % name
			used.append(name)
	return ""


func read_document() -> Dictionary:
	var file = File.new()
	if not file.file_exists(file_path()):
		return {"data": empty_document()}
	var error = file.open(file_path(), File.READ)
	if error != OK:
		return {"error": "无法读取技能默认补丁（%d）。" % error}
	if file.get_len() > MAX_BYTES:
		file.close()
		return {"error": "技能默认补丁超过支持的大小。"}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK:
		return {"error": "技能默认补丁内容损坏。"}
	error = validate_document(parsed.result)
	if not str(error).empty():
		return {"error": error}
	return {"data": parsed.result}


func write_document(data: Dictionary) -> String:
	var trial = Engine.get_main_loop().root.get_node_or_null("TrialSession")
	if trial != null and trial.active:
		return "试炼中不能修改新局默认；请结束试炼后再保存。"
	var error = validate_document(data)
	if not error.empty():
		return error
	var directory = Directory.new()
	if directory.make_dir_recursive(file_path().get_base_dir()) != OK:
		return "无法创建技能默认补丁目录。"
	var backup_error = _backup_previous()
	if not backup_error.empty():
		return backup_error
	var temporary = file_path() + ".tmp"
	var file = File.new()
	if file.open(temporary, File.WRITE) != OK:
		return "技能默认补丁无法写入，未修改本局。"
	file.store_string(JSON.print(data, "  "))
	file.flush()
	var result = file.get_error()
	file.close()
	if result != OK:
		return "技能默认补丁写入失败，原补丁已保留。"
	var check = File.new()
	if check.open(temporary, File.READ) != OK:
		return "技能默认补丁无法校验。"
	var parsed = JSON.parse(check.get_as_text())
	check.close()
	if parsed.error != OK or not validate_document(parsed.result).empty():
		return "技能默认补丁写入校验失败。"
	if directory.rename(temporary, file_path()) != OK:
		return "技能默认补丁替换失败，原补丁已保留。"
	return ""


func _backup_previous() -> String:
	var directory = Directory.new()
	if directory.make_dir_recursive("user://backups") != OK:
		return "无法备份原技能默认补丁，未作修改。"
	var entry = {"path": RELATIVE_PATH, "missing": true}
	var file = File.new()
	if file.file_exists(file_path()):
		if file.open(file_path(), File.READ) != OK:
			return "无法读取原技能默认补丁，未作修改。"
		var content = file.get_as_text()
		file.close()
		entry = {"path": RELATIVE_PATH, "content": content, "sha256": content.sha256_text()}
	var time = OS.get_datetime()
	var stamp = "%04d%02d%02d-%02d%02d%02d-%d" % [time.year, time.month, time.day, time.hour, time.minute, time.second, OS.get_ticks_msec()]
	var path = "user://backups/技能默认变更-" + stamp + ".bawang.json"
	if file.open(path, File.WRITE) != OK:
		return "原技能默认补丁备份失败，未作修改。"
	file.store_string(JSON.print({"kind": "bawang-backup", "format": 1, "game_version": "2.560", "entries": [entry]}, "  "))
	file.flush()
	var error = file.get_error()
	file.close()
	return "" if error == OK else "原技能默认补丁备份写入失败，未作修改。"


func describe(data: Dictionary) -> String:
	var lines = ["技能默认补丁：%d 名武将" % data.actors.size(), "只用于以后新开游戏；读取旧存档不会自动套用。"]
	for actor_key in data.actors:
		var actor = ActorHelper.actor(int(actor_key))
		for scope in data.actors[actor_key]:
			var names = []
			for level in LEVELS:
				if data.actors[actor_key][scope].has(level):
					var name: String = data.actors[actor_key][scope][level]
					names.append("%s %s" % [level, name if not name.empty() else "无技能"])
			lines.append("%s%s：%s" % [actor.get_name(), "（%s面）" % scope if scope != "default" else "", PoolStringArray(names).join("、")])
	return PoolStringArray(lines).join("\n")
