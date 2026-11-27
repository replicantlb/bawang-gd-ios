extends Reference

# Imports are data only. Never use paths supplied by an archive without validation.
const FORMAT = 1
const MAX_FILE_BYTES = 16 * 1024 * 1024
const MAX_TOTAL_BYTES = 64 * 1024 * 1024
const PATCH_PATH = "mod/patches/actors.json"
const SkillDefaults = preload("res://ios_skill_defaults.gd")
const SKILL_PATCH_PATH = "mod/patches/skills.json"
const PRESETS_PATH = "ios_skill_presets.json"
const JOURNAL_PATH = "user://ios_pending_import.json"
var recovery_notice := ""


func ensure_directories() -> int:
	var directory = Directory.new()
	for path in [base_path() + "save", base_path() + "mod/patches", "user://imports", "user://exports", "user://backups"]:
		var error = directory.make_dir_recursive(path)
		if error != OK:
			return error
	return _recover_import()


func base_path() -> String:
	return DataManager.get_common_path()


func disk_path(relative: String) -> String:
	return "user://" + relative if relative == PRESETS_PATH else base_path() + relative


func allowed_path(relative: String) -> bool:
	if relative in [PATCH_PATH, SKILL_PATCH_PATH, PRESETS_PATH]:
		return true
	if not relative.begins_with("save/") or not relative.ends_with(".sav"):
		return false
	var name = relative.substr(5)
	var stem = name.get_basename()
	if stem.empty() or stem.length() > 64:
		return false
	# Native slots and automatic saves use lower-case ASCII names. Reject aliases
	# (case folding, control characters, path separators) before staging files.
	for index in range(stem.length()):
		var code = stem.ord_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 122) and not code in [45, 95]:
			return false
	return true


func list_files(folder: String, suffix: String) -> Array:
	var result = []
	var directory = Directory.new()
	if directory.open(folder) != OK:
		return result
	directory.list_dir_begin(true, true)
	var filename = directory.get_next()
	while not filename.empty():
		if not directory.current_is_dir() and filename.ends_with(suffix):
			result.append(filename)
		filename = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result


func read_text(path: String, maximum := MAX_FILE_BYTES) -> Dictionary:
	var file = File.new()
	var error = file.open(path, File.READ)
	if error != OK:
		return {"error": "无法读取文件（%d）。" % error}
	if file.get_len() > maximum:
		file.close()
		return {"error": "文件超过支持的大小，未导入。"}
	var content = file.get_as_text()
	file.close()
	return {"content": content}


func _json(content: String) -> Dictionary:
	var parsed = JSON.parse(content)
	if parsed.error != OK or not parsed.result is Dictionary:
		return {"error": "文件不是有效的 JSON 数据。"}
	return {"data": parsed.result}


func _integer(value, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_REAL] and value >= low and value <= high and int(value) == value


func validate_content(relative: String, content: String) -> String:
	var parsed = _json(content)
	if parsed.has("error"):
		return parsed.error
	var data: Dictionary = parsed.data
	if relative == SKILL_PATCH_PATH:
		return SkillDefaults.new().validate_document(data)
	if relative == PATCH_PATH:
		for actor_key in data:
			if not actor_key is String or not actor_key.is_valid_integer() or str(int(actor_key)) != actor_key:
				return "补丁中有无效的武将编号。"
			var actor_id = int(actor_key)
			if actor_id < 0 or actor_id >= StaticManager.actors.size() or not data[actor_key] is Dictionary:
				return "补丁中的武将不属于当前版本。"
			for attribute in data[actor_key]:
				var value = data[actor_key][attribute]
				if not attribute in StaticManager.PATCH_ATTRS or not _integer(value, 1, 99):
					return "补丁属性仅支持体、武、知、统、政、德、胆，数值须为 1～99 的整数。"
		return ""
	if relative == PRESETS_PATH:
		if not _integer(data.get("version"), 1, 1) or not data.get("presets") is Array or data.presets.size() > 12:
			return "技能收藏格式不支持。"
		for preset in data.presets:
			if not preset is Dictionary or not preset.get("name") is String or not preset.get("skills") is Array or not preset.skills.size() in [4, 8]:
				return "技能收藏内容不完整。"
			for skill_name in preset.skills:
				if not skill_name is String:
					return "技能收藏包含无效的技能名称。"
		return ""
	if not _integer(data.get("COMPABILITY"), DataManager.COMPABILITY, DataManager.COMPABILITY) or not data.get("VERSION") is String or data.VERSION != DataManager.VERSION:
		return "存档版本不匹配，需要 GD 2.560 的兼容存档。"
	for key in ["common_variable", "game_set", "actor_scene_skill", "actor_disabled_equip_types", "skill_cd", "skill_variable", "vstates_alliance", "stratagem_execution", "solo_fight", "battle_fight"]:
		if not data.get(key) is Dictionary:
			return "存档缺少有效的 %s 数据。" % key
	for key in ["players", "weapons", "suits", "jewelrys", "steeds", "control_sort", "vstates_sort", "battle_units", "battle_actors", "battle_type_sort", "skill_range_buff", "war_control_sort", "actor_ban_scene_skill"]:
		if not data.get(key) is Array:
			return "存档缺少有效的 %s 数据。" % key
	if data.players.empty() or not _integer(data.get("year"), 0, 9999) or not _integer(data.get("month"), 1, 12) or not data.get("battle_run") is bool:
		return "存档的玩家、年月或战斗状态无效。"
	for key in ["actors", "citys", "vstates"]:
		if not data.get(key) is Array or data[key].empty():
			return "存档缺少有效的武将、城市或势力数据。"
	if data.actors.size() != StaticManager.actors.size():
		return "存档武将数量与当前版本不一致。"
	for records in [data.actors, data.citys, data.vstates]:
		for index in range(records.size()):
			if not records[index] is Dictionary or not _integer(records[index].get("ID"), index, index):
				return "存档中的武将、城市或势力编号不完整。"
	for city in data.citys:
		if not city.get("武将") is Array or not city.get("城池坐标") is Dictionary:
			return "存档城市数据不完整。"
	for state in data.vstates:
		if not _integer(state.get("君主"), -1, data.actors.size() - 1) or not state.get("状态") is String:
			return "存档势力数据不完整。"
	var scene = str(data.get("current_scene_path", ""))
	if not scene.begins_with("res://scene/") or not scene.ends_with(".tscn") or not ResourceLoader.exists(scene):
		return "存档场景不属于当前游戏。"
	if not data.get("mod_path") is String or data.mod_path != DataManager.DEFAULT_MOD_PATH:
		return "此存档需要其他模组，当前手机版未包含该模组。"
	return ""


func first_free_slot() -> int:
	for index in range(200):
		if not File.new().file_exists(base_path() + "save/%d.sav" % index):
			return index
	return 0


func inspect_import(path: String, save_slot := -1) -> Dictionary:
	var read = read_text(path, MAX_TOTAL_BYTES * 2)
	if read.has("error"):
		return read
	var parsed = _json(read.content)
	if parsed.has("error"):
		return parsed
	var data: Dictionary = parsed.data
	var entries = []
	if data.get("kind") is String and data.kind == "bawang-backup":
		if not _integer(data.get("format"), FORMAT, FORMAT) or not data.get("entries") is Array or data.entries.size() > 1000:
			return {"error": "备份格式不支持。"}
		entries = data.entries.duplicate(true)
	elif data.get("kind") is String and data.kind == "bawang-skill-defaults":
		entries = [{"path": SKILL_PATCH_PATH, "content": read.content}]
	elif path.to_lower().ends_with(".sav"):
		var destination = first_free_slot() if save_slot < 0 else save_slot
		if destination < 0 or destination >= 200:
			return {"error": "存档点必须在 1～200 之间。"}
		entries = [{"path": "save/%d.sav" % destination, "content": read.content}]
	else:
		entries = [{"path": PATCH_PATH, "content": read.content}]
	var checked = validate_entries(entries)
	if not checked.empty():
		return {"error": checked}
	return {"entries": entries, "summary": describe_entries(entries)}


func validate_entries(entries: Array) -> String:
	if entries.empty():
		return "文件中没有可导入的数据。"
	var seen = {}
	var total = 0
	for entry in entries:
		if not entry is Dictionary or not entry.get("path") is String or not allowed_path(entry.path) or seen.has(entry.path):
			return "备份包含重复或不支持的文件路径。"
		seen[entry.path] = true
		if entry.has("missing") and not entry.missing is bool:
			return "备份的文件状态无效。"
		if entry.get("missing", false):
			continue
		if not entry.get("content") is String:
			return "备份文件内容不完整。"
		var size = entry.content.to_utf8().size()
		total += size
		if size > MAX_FILE_BYTES or total > MAX_TOTAL_BYTES:
			return "备份数据过大，未导入。"
		if entry.has("sha256") and (not entry.sha256 is String or entry.sha256 != entry.content.sha256_text()):
			return "备份校验失败，文件可能已损坏。"
		var error = validate_content(entry.path, entry.content)
		if not error.empty():
			return entry.path.get_file() + "：" + error
	return ""


func _entry(relative: String) -> Dictionary:
	var file = File.new()
	if not file.file_exists(disk_path(relative)):
		return {"path": relative, "missing": true}
	var read = read_text(disk_path(relative))
	if read.has("error"):
		return read
	return {"path": relative, "content": read.content, "sha256": read.content.sha256_text()}


func _stamp() -> String:
	var date = OS.get_datetime()
	return "%04d%02d%02d-%02d%02d%02d-%d" % [date.year, date.month, date.day, date.hour, date.minute, date.second, OS.get_ticks_msec()]


func _write_json(path: String, data: Dictionary) -> String:
	var file = File.new()
	var error = file.open(path, File.WRITE)
	if error != OK:
		return "无法写入文件（%d）。" % error
	file.store_string(JSON.print(data, "  "))
	file.flush()
	error = file.get_error()
	file.close()
	return "" if error == OK else "写入失败（%d），请检查可用空间。" % error


func _write_journal(data: Dictionary) -> bool:
	var temporary = JOURNAL_PATH + ".tmp"
	if not _write_json(temporary, data).empty():
		return false
	return Directory.new().rename(temporary, JOURNAL_PATH) == OK


func _recover_import() -> int:
	if not File.new().file_exists(JOURNAL_PATH):
		return OK
	var read = read_text(JOURNAL_PATH)
	if read.has("error"):
		return ERR_FILE_CANT_READ
	var parsed = _json(read.content)
	if parsed.has("error"):
		recovery_notice = "上次导入记录损坏，请先导出 backups 中的备份。"
		return ERR_FILE_CORRUPT
	var journal: Dictionary = parsed.data
	if not journal.get("token") is String or not journal.token.begins_with(".import-") or not journal.get("files") is Array or not journal.get("committed") is bool:
		return ERR_FILE_CORRUPT
	var token: String = journal.token
	if token.length() > 80:
		return ERR_FILE_CORRUPT
	for index in range(8, token.length()):
		if not token.ord_at(index) in range(48, 58) and token.ord_at(index) != 45:
			return ERR_FILE_CORRUPT
	var seen = {}
	for item in journal.files:
		if not item is Dictionary or not item.get("path") is String or not allowed_path(item.path) or not item.get("had_original") is bool or seen.has(item.path):
			return ERR_FILE_CORRUPT
		seen[item.path] = true
	var directory = Directory.new()
	for item in journal.files:
		var target = disk_path(item.path)
		var previous = target + token + ".previous"
		if File.new().file_exists(previous):
			if journal.committed:
				if directory.remove(previous) != OK:
					return ERR_FILE_CANT_WRITE
			else:
				if File.new().file_exists(target) and directory.remove(target) != OK:
					return ERR_FILE_CANT_WRITE
				if directory.rename(previous, target) != OK:
					return ERR_FILE_CANT_WRITE
		elif not journal.committed and not item.had_original and File.new().file_exists(target):
			if directory.remove(target) != OK:
				return ERR_FILE_CANT_WRITE
		if File.new().file_exists(target + token) and directory.remove(target + token) != OK:
			return ERR_FILE_CANT_WRITE
	if directory.remove(JOURNAL_PATH) != OK:
		return ERR_FILE_CANT_WRITE
	_refresh_default_attributes()
	recovery_notice = "已清理上次完成的导入。" if journal.committed else "上次导入被中断，已自动恢复导入前的文件。"
	return OK


func create_backup(paths := [], folder := "user://backups", label := "备份") -> Dictionary:
	if ensure_directories() != OK:
		return {"error": "无法创建备份目录。"}
	if paths.empty():
		for name in list_files(base_path() + "save", ".sav"):
			paths.append("save/" + name)
		paths.append(PATCH_PATH)
		paths.append(SKILL_PATCH_PATH)
		paths.append(PRESETS_PATH)
	var entries = []
	var total = 0
	for relative in paths:
		if not allowed_path(relative):
			return {"error": "不支持备份此文件。"}
		var entry = _entry(relative)
		if entry.has("error"):
			return entry
		total += str(entry.get("content", "")).to_utf8().size()
		if total > MAX_TOTAL_BYTES:
			return {"error": "备份超过 64 MB，请分次导出存档。"}
		entries.append(entry)
	var path = folder + "/" + label + "-" + _stamp() + ".bawang.json"
	var error = _write_json(path, {"kind": "bawang-backup", "format": FORMAT, "game_version": DataManager.VERSION, "created_at": OS.get_datetime(), "entries": entries})
	return {"path": path} if error.empty() else {"error": error}


func export_file(relative: String) -> Dictionary:
	if not allowed_path(relative) or ensure_directories() != OK:
		return {"error": "无法导出此文件。"}
	var entry = _entry(relative)
	if entry.has("error"):
		return entry
	if entry.get("missing", false):
		if relative == SKILL_PATCH_PATH:
			entry = {"content": JSON.print(SkillDefaults.new().empty_document())}
		elif relative != PATCH_PATH:
			return {"error": "文件不存在。"}
		else:
			entry = {"content": "{}"}
	var path = "user://exports/" + _stamp() + "-" + relative.get_file()
	var file = File.new()
	var error = file.open(path, File.WRITE)
	if error != OK:
		return {"error": "导出失败（%d）。" % error}
	file.store_string(entry.content)
	file.flush()
	error = file.get_error()
	file.close()
	return {"path": path} if error == OK else {"error": "导出写入失败，请检查可用空间。"}


func apply_import(entries: Array) -> Dictionary:
	var error = validate_entries(entries)
	if not error.empty():
		return {"error": error}
	var paths = []
	for entry in entries:
		paths.append(entry.path)
	var backup = create_backup(paths, "user://backups", "导入前")
	if backup.has("error"):
		return {"error": "导入前备份失败，未覆盖任何文件。" + backup.error}
	error = _replace_entries(entries)
	if not error.empty():
		return {"error": error + "\n原文件备份：" + backup.path}
	for entry in entries:
		if entry.path == PATCH_PATH:
			_refresh_default_attributes()
		elif entry.path.begins_with("save/"):
			StaticManager.saveIdx.update_save_index(entry.path.get_file().get_basename())
	return {"backup": backup.path}


func _refresh_default_attributes() -> void:
	# Static defaults can contain a previously applied patch. Restore those first
	# on a deep copy, so campaign actor dictionaries are never touched by aliasing.
	var defaults: Array = StaticManager.actors.duplicate(true)
	for record in defaults:
		for attribute in StaticManager.PATCH_ATTRS:
			if record.has("原" + attribute):
				record[attribute] = record["原" + attribute]
	StaticManager.actors = defaults
	StaticManager.actor_patches = {}
	StaticManager.reload_and_apply_actor_patches()


func _replace_entries(entries: Array) -> String:
	var directory = Directory.new()
	var token = ".import-" + _stamp()
	var staged = []
	for entry in entries:
		var target = disk_path(entry.path)
		if not entry.get("missing", false):
			var file = File.new()
			var error = file.open(target + token, File.WRITE)
			if error != OK:
				_cleanup_staged(staged)
				return "无法准备导入文件，未覆盖原文件。"
			file.store_string(entry.content)
			file.flush()
			error = file.get_error()
			file.close()
			staged.append(target + token)
			var check = read_text(target + token)
			if error != OK or check.has("error") or check.content.sha256_text() != entry.content.sha256_text():
				_cleanup_staged(staged)
				return "导入文件写入校验失败，未覆盖原文件。"
	var moved = []
	var installed = []
	var journal = {"token": token, "committed": false, "files": []}
	for entry in entries:
		journal.files.append({"path": entry.path, "had_original": File.new().file_exists(disk_path(entry.path))})
	if not _write_journal(journal):
		_cleanup_staged(staged)
		return "无法记录导入恢复信息，未覆盖原文件。"
	for entry in entries:
		var target = disk_path(entry.path)
		if File.new().file_exists(target):
			if directory.rename(target, target + token + ".previous") != OK:
				return _rollback(moved, installed, staged)
			moved.append([target, target + token + ".previous"])
		if not entry.get("missing", false):
			if directory.rename(target + token, target) != OK:
				return _rollback(moved, installed, staged)
			installed.append(target)
	journal.committed = true
	if not _write_journal(journal):
		return _rollback(moved, installed, staged)
	var cleaned = true
	for pair in moved:
		if directory.remove(pair[1]) != OK:
			cleaned = false
	_cleanup_staged(staged)
	if cleaned:
		directory.remove(JOURNAL_PATH)
	return ""


func _cleanup_staged(paths: Array) -> void:
	var directory = Directory.new()
	for path in paths:
		if File.new().file_exists(path):
			directory.remove(path)


func _rollback(moved: Array, installed: Array, staged: Array) -> String:
	var directory = Directory.new()
	var failed = false
	for path in installed:
		if directory.remove(path) != OK:
			failed = true
	for pair in moved:
		if directory.rename(pair[1], pair[0]) != OK:
			failed = true
	_cleanup_staged(staged)
	if not failed:
		directory.remove(JOURNAL_PATH)
	return "导入失败，部分原文件需从备份恢复。" if failed else "导入失败，已恢复原文件。"


func describe_entries(entries: Array) -> String:
	var lines = ["将处理 %d 个文件。" % entries.size()]
	for entry in entries:
		if entry.get("missing", false):
			lines.append("恢复为不存在：" + entry.path)
		elif entry.path == PATCH_PATH:
			lines.append(describe_patch(JSON.parse(entry.content).result))
		elif entry.path == PRESETS_PATH:
			lines.append("技能收藏配置")
		elif entry.path == SKILL_PATCH_PATH:
			lines.append(SkillDefaults.new().describe(JSON.parse(entry.content).result))
		else:
			var data = JSON.parse(entry.content).result
			var name = entry.path.get_file().get_basename()
			var title = "存档点 %d" % (int(name) + 1) if name.is_valid_integer() else entry.path.get_file()
			lines.append("%s　%s年%s月　%s" % [title, data.get("year", "?"), data.get("month", "?"), data.get("存档时间", "")])
	lines.append("\n存档导入后请从读取存档进入；属性补丁在新开游戏时应用。\n只恢复清单中的文件，其他存档保留。覆盖前会自动备份。")
	return PoolStringArray(lines).join("\n")


func describe_patch(data: Dictionary, compare := true) -> String:
	var lines = ["武将属性补丁：%d 人%s" % [data.size(), "（替换整份补丁）" if compare else ""]]
	var shown = 0
	for actor_key in data:
		if shown >= 40:
			lines.append("其余 %d 人也将导入。" % (data.size() - shown))
			break
		var actor_id = int(actor_key)
		var actor = ActorHelper.actor(actor_id)
		var changes = []
		var previous = StaticManager.actor_patches.get(str(actor_id), {})
		for attribute in data[actor_key]:
			changes.append("%s %s→%s" % [attribute, previous.get(attribute, actor._get_attr_int_original(attribute)), data[actor_key][attribute]] if compare else "%s %s" % [attribute, data[actor_key][attribute]])
		lines.append(actor.get_name() + "：" + PoolStringArray(changes).join("，"))
		shown += 1
	var removed = 0
	for actor_key in StaticManager.actor_patches:
		if not data.has(actor_key):
			removed += 1
	if compare and removed > 0:
		lines.append("现有补丁中另外 %d 人的整项修改将移除。" % removed)
	return PoolStringArray(lines).join("\n")
