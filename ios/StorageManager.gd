extends PopupPanel

const StorageService = preload("res://ios_storage_service.gd")
const MobileLayout = preload("res://ios_mobile_layout.gd")
var service = StorageService.new()
var files: ItemList
var details: RichTextLabel
var status: Label
var slot: SpinBox
var picker: FileDialog
var confirmation: ConfirmationDialog
var import_preview: RichTextLabel
var default_actor_ids := []
var remove_default: Button
var selected_paths := []
var pending_entries := []
var tab := "saves"
var was_paused := false
var opened := false
var layer: CanvasLayer


func open_manager() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	popup_exclusive = true
	service.ensure_directories()
	_build()
	var available = MobileLayout.available_area(get_viewport(), 16.0, true)
	popup_centered(Vector2(min(960, available.size.x), min(560, available.size.y)))
	rect_position = available.position + (available.size - rect_size) * 0.5
	was_paused = get_tree().paused
	get_tree().paused = true
	opened = true
	connect("popup_hide", self, "_closed")
	_refresh()
	set_process(true)


func _process(_delta: float) -> void:
	if not visible:
		return
	var available = MobileLayout.available_area(get_viewport(), 16.0, true)
	rect_size = Vector2(min(960, available.size.x), min(560, available.size.y))
	rect_position = available.position + (available.size - rect_size) * 0.5


func _button(text: String, target: String, parent: Node, arguments := []) -> Button:
	var button = Button.new()
	button.text = text
	button.rect_min_size.y = 46
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.connect("pressed", self, target, arguments)
	parent.add_child(button)
	return button


func _build() -> void:
	var theme_font = Theme.new()
	theme_font.default_font = Global.get_font(25)
	theme = theme_font
	var style = StyleBoxFlat.new()
	style.bg_color = Color("28231f")
	style.border_color = Color("b79a6b")
	style.set_border_width_all(2)
	add_stylebox_override("panel", style)
	var body = VBoxContainer.new()
	add_child(body)
	body.anchor_right = 1
	body.anchor_bottom = 1
	body.margin_left = 16
	body.margin_right = -16
	body.margin_top = 12
	body.margin_bottom = -12
	body.add_constant_override("separation", 8)
	var heading = HBoxContainer.new()
	body.add_child(heading)
	var title = Label.new()
	title.text = "存档与补丁"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_button("关闭", "hide", heading).size_flags_horizontal = 0
	var navigation = HBoxContainer.new()
	body.add_child(navigation)
	_button("存档", "_switch_tab", navigation, ["saves"])
	_button("属性补丁", "_switch_tab", navigation, ["patch"])
	_button("技能默认", "_switch_tab", navigation, ["skill_defaults"])
	_button("恢复备份", "_switch_tab", navigation, ["backups"])
	var content = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	files = ItemList.new()
	files.rect_min_size.x = 250
	files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	files.connect("item_selected", self, "_selected")
	content.add_child(files)
	details = RichTextLabel.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.bbcode_enabled = false
	content.add_child(details)
	var target = HBoxContainer.new()
	body.add_child(target)
	var label = Label.new()
	label.text = "单个存档导入到存档点"
	target.add_child(label)
	slot = SpinBox.new()
	slot.min_value = 1
	slot.max_value = 200
	slot.value = service.first_free_slot() + 1
	slot.rect_min_size = Vector2(150, 46)
	target.add_child(slot)
	var hint = Label.new()
	hint.text = "导入后再读取，当前进度不会切换"
	target.add_child(hint)
	var actions = HBoxContainer.new()
	body.add_child(actions)
	_button("导出所选", "_export_selected", actions)
	_button("导入文件", "_choose_import", actions)
	_button("导出完整备份", "_export_all", actions)
	_button("恢复所选备份", "_restore_selected", actions)
	remove_default = _button("移除默认", "_remove_default_selected", actions)
	remove_default.hide()
	status = Label.new()
	status.autowrap = true
	status.rect_min_size.y = 60
	status.text = "“文件”App → 我的 iPhone → 霸王的大陆GD 2.560\n导出文件在 exports；把待导入文件放入 imports。"
	if not service.recovery_notice.empty():
		status.text = service.recovery_notice + "\n" + status.text
	body.add_child(status)
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.mode = FileDialog.MODE_OPEN_FILE
	picker.window_title = "选择存档、补丁或备份"
	picker.filters = PoolStringArray(["*.sav ; 游戏存档", "*.json ; 属性补丁、技能默认或备份"])
	picker.connect("file_selected", self, "_inspect_file")
	add_child(picker)
	confirmation = ConfirmationDialog.new()
	confirmation.window_title = "确认导入"
	confirmation.get_ok().text = "备份并导入"
	confirmation.get_cancel().text = "取消"
	confirmation.connect("confirmed", self, "_apply_pending")
	import_preview = RichTextLabel.new()
	import_preview.rect_min_size = Vector2(740, 300)
	import_preview.bbcode_enabled = false
	confirmation.add_child(import_preview)
	add_child(confirmation)


func _switch_tab(next: String) -> void:
	tab = next
	_refresh()


func _refresh() -> void:
	files.clear()
	selected_paths.clear()
	default_actor_ids.clear()
	remove_default.visible = tab == "skill_defaults"
	if tab == "patch":
		files.add_item("武将属性补丁")
		selected_paths.append(service.disk_path(service.PATCH_PATH))
	elif tab == "skill_defaults":
		var patch = service.SkillDefaults.new()
		var read = patch.read_document()
		if read.has("error"):
			details.text = read.error
			return
		var keys = read.data.actors.keys()
		keys.sort()
		for key in keys:
			var actor_id = int(key)
			files.add_item(ActorHelper.actor(actor_id).get_name())
			selected_paths.append(patch.file_path())
			default_actor_ids.append(actor_id)
		if keys.empty():
			files.add_item("暂无技能默认补丁")
			selected_paths.append(patch.file_path())
	elif tab == "backups":
		var names = service.list_files("user://backups", ".bawang.json")
		names.invert()
		for name in names:
			files.add_item(name)
			selected_paths.append("user://backups/" + name)
	else:
		for name in service.list_files(service.base_path() + "save", ".sav"):
			files.add_item("存档点 %d" % (int(name.get_basename()) + 1) if name.get_basename().is_valid_integer() else name)
			selected_paths.append(service.base_path() + "save/" + name)
	if files.get_item_count() > 0:
		files.select(0)
		_selected(0)
	else:
		details.text = "暂无备份。每次导入前会自动创建备份，也可以导出完整备份。" if tab == "backups" else "暂无存档。请先在游戏菜单中保存。"


func _selected(index: int) -> void:
	if index < 0 or index >= selected_paths.size():
		return
	var path: String = selected_paths[index]
	if tab == "skill_defaults":
		var patch = service.SkillDefaults.new()
		var read = patch.read_document()
		if read.has("error"):
			details.text = read.error
			return
		var document: Dictionary = read.data
		if index < default_actor_ids.size():
			var actor_key = str(default_actor_ids[index])
			document.actors = {actor_key: document.actors[actor_key]}
			details.text = patch.describe(document) + "\n\n导出会包含整份技能默认补丁。“移除默认”只移除所选武将，不改变本局或其他旧档。"
		else:
			details.text = "暂无技能默认补丁。\n在修改器中选择技能，勾选“另存新局默认”，再到武将页保存。\n\n以后新开游戏会沿用；读取旧存档不会套用。"
		return
	if tab == "patch" and not File.new().file_exists(path):
		details.text = "尚未修改默认武将属性。\n\n可在游戏资料 → 数据补丁中编辑，或导入其他玩家提供的 actors.json。\n\n补丁只在新开游戏时应用。"
		return
	if tab in ["saves", "patch"]:
		var read = service.read_text(path)
		if read.has("error"):
			details.text = read.error
			return
		var relative = service.PATCH_PATH if tab == "patch" else "save/" + path.get_file()
		var error = service.validate_content(relative, read.content)
		if not error.empty():
			details.text = error
			return
		var data = JSON.parse(read.content).result
		if tab == "patch":
			details.text = service.describe_patch(data, false) + "\n\n用于新开游戏，不改变当前进度。"
		else:
			details.text = "%s\n%d年%d月\n保存时间：%s\n\n选择“导出所选”备份这一存档。\n导入存档后，请从游戏菜单读取。" % [files.get_item_text(index), data.year, data.month, data.get("存档时间", "未知")]
		return
	var original_slot = int(path.get_file().get_basename()) if tab == "saves" and path.get_file().get_basename().is_valid_integer() else -1
	var inspected = service.inspect_import(path, original_slot)
	details.text = inspected.get("error", inspected.get("summary", ""))


func _selected_path() -> String:
	var selected = files.get_selected_items()
	return "" if selected.empty() else selected_paths[selected[0]]


func _export_selected() -> void:
	var path = _selected_path()
	if path.empty():
		status.text = "请先选择文件。"
		return
	if tab == "backups":
		var directory = Directory.new()
		var exported = "user://exports/" + path.get_file()
		status.text = "已导出到 exports/" + path.get_file() if directory.copy(path, exported) == OK else "导出失败，请检查可用空间。"
		return
	var relative = service.SKILL_PATCH_PATH if tab == "skill_defaults" else (service.PATCH_PATH if tab == "patch" else "save/" + path.get_file())
	_show_result(service.export_file(relative), "已导出到 exports/")


func _remove_default_selected() -> void:
	var selected = files.get_selected_items()
	if tab != "skill_defaults" or selected.empty() or selected[0] >= default_actor_ids.size():
		status.text = "请先选择一名有默认补丁的武将。"
		return
	var actor_id: int = default_actor_ids[selected[0]]
	var dialog = ConfirmationDialog.new()
	dialog.window_title = "移除技能默认"
	dialog.dialog_text = "移除%s的技能默认补丁？\n会先备份；本局与其他旧存档保持不变。" % ActorHelper.actor(actor_id).get_name()
	dialog.get_ok().text = "备份并移除"
	dialog.get_cancel().text = "取消"
	dialog.get_ok().rect_min_size = Vector2(180, 48)
	dialog.get_cancel().rect_min_size = Vector2(120, 48)
	dialog.connect("confirmed", self, "_remove_default_confirmed", [actor_id])
	dialog.connect("popup_hide", dialog, "queue_free")
	add_child(dialog)
	dialog.popup_centered(Vector2(740, 230))


func _remove_default_confirmed(actor_id: int) -> void:
	var patch = service.SkillDefaults.new()
	var read = patch.read_document()
	if read.has("error"):
		status.text = read.error
		return
	read.data.actors.erase(str(actor_id))
	var error: String = patch.write_document(read.data)
	status.text = "已移除新局默认，本局未改变；原补丁已备份。" if error.empty() else error
	_refresh()


func _export_all() -> void:
	_show_result(service.create_backup([], "user://exports", "完整备份"), "已导出到 exports/")


func _show_result(result: Dictionary, message: String) -> void:
	status.text = result.error if result.has("error") else message + str(result.path).get_file()


func _choose_import() -> void:
	var typed = slot.get_line_edit().text.strip_edges()
	if typed.is_valid_integer():
		slot.value = int(typed)
	slot.get_line_edit().release_focus()
	OS.hide_virtual_keyboard()
	picker.current_dir = ProjectSettings.globalize_path("user://imports")
	picker.popup_centered_ratio(0.92)


func _restore_selected() -> void:
	if tab != "backups" or _selected_path().empty():
		status.text = "请在“恢复备份”中选择一份备份。"
		return
	_inspect_file(_selected_path())


func _inspect_file(path: String) -> void:
	var inspected = service.inspect_import(path, int(slot.value) - 1)
	if inspected.has("error"):
		status.text = inspected.error
		return
	pending_entries = inspected.entries
	details.text = inspected.summary
	confirmation.dialog_text = ""
	import_preview.text = inspected.summary
	confirmation.popup_centered(Vector2(820, 430))


func _apply_pending() -> void:
	var result = service.apply_import(pending_entries)
	pending_entries.clear()
	if result.has("error"):
		status.text = result.error
		return
	status.text = "导入完成。读取存档后进入该进度；补丁在新开游戏时生效。原文件保存在 backups/。"
	_refresh()


func _closed() -> void:
	if opened:
		get_tree().paused = was_paused
		opened = false
	queue_free()
	if is_instance_valid(layer):
		layer.queue_free()


func _exit_tree() -> void:
	if opened and get_tree() != null:
		get_tree().paused = was_paused
