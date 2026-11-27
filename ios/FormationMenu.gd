extends "res://windows/lsc_image_menu.gdc"

const Layout = preload("res://ios_mobile_layout.gd")
const BATTLE_PATH = "res://scene/scene_battle/scene_battle.tscn"

class FormationBoard extends Control:
	var projection := {}
	var cell_size := 21.0
	var unit_font: Font
	var type_colors := {}

	func _draw() -> void:
		if projection.empty() or unit_font == null:
			return
		var columns: int = projection.columns
		var rows: int = projection.rows
		draw_rect(Rect2(Vector2.ZERO, Vector2(columns, rows) * cell_size), Color("#f2e9d0"))
		for x in range(columns + 1):
			draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, rows * cell_size), Color("#d0c5a7"))
		for y in range(rows + 1):
			draw_line(Vector2(0, y * cell_size), Vector2(columns * cell_size, y * cell_size), Color("#d0c5a7"))
		for unit in projection.units:
			var position: Vector2 = unit.position
			if position.x < 0 or position.y < 0 or position.x >= columns or position.y >= rows:
				continue
			var tile = Rect2(position * cell_size + Vector2.ONE, Vector2.ONE * (cell_size - 2))
			var color: Color = type_colors.get(unit.symbol, Color("#6b6670"))
			draw_rect(tile, color)
			draw_rect(tile, Color("#332c23"), false)
			var text_size = unit_font.get_string_size(unit.symbol)
			var origin = tile.position + Vector2((tile.size.x - text_size.x) * 0.5, (tile.size.y - unit_font.get_height()) * 0.5 + unit_font.get_ascent())
			draw_string(unit_font, origin, unit.symbol, Color("#282019") if unit.symbol == "将" else Color.white)

var _formation_mode := false
var _preview_panel: Panel
var _preview_title: Label
var _legend: RichTextLabel
var _help: Label
var _board: FormationBoard
var _last_preview_key := ""
var _native_layout := []
var _colors := {"将": Color("#ecc15a"), "步": Color("#3579ad"), "骑": Color("#ae493e"), "弓": Color("#37815b"), "象": Color("#875299"), "藤": Color("#76823c"), "仙": Color("#38868e"), "门": Color("#846242")}


func _ready() -> void:
	connect("visibility_changed", self, "_preview_visibility_changed")


func _set_data(scale: float = 1.5):
	_formation_mode = _has_formation_context()
	_last_preview_key = ""
	._set_data(scale)
	if not _formation_mode:
		_restore_native_layout()
		if is_instance_valid(_preview_panel):
			_preview_panel.hide()
			_board.projection = {}
		return
	_ensure_preview()
	_capture_native_layout()
	var grid = container.get_node("container")
	var cards = []
	for child in grid.get_children():
		if child.is_queued_for_deletion():
			grid.remove_child(child)
		elif child is Control:
			cards.append(child)
	for index in range(min(items.size(), cards.size())):
		var card = cards[index]
		var sprite: Sprite = card.get_child(0)
		var button = Button.new()
		button.name = "FormationChoice"
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.rect_size = sprite.texture.get_size() * scale
		button.rect_position = -button.rect_size * 0.5
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_stylebox_override(state, StyleBoxEmpty.new())
		button.hint_tooltip = str(StaticManager.get_formation_setting(int(items[index][0])).get("name", "阵型"))
		button.connect("pressed", self, "_formation_clicked", [index])
		card.add_child(button)
	_refresh_preview()


func UpdateCursor():
	.UpdateCursor()
	if _formation_mode:
		_refresh_preview()


func _formation_clicked(index: int) -> void:
	if not _formation_mode or index < 0 or index >= items.size():
		return
	set_cursor(index)
	UpdateCursor()


func _has_formation_context() -> bool:
	var scene = SceneManager.current_scene()
	if scene == null or scene.filename != BATTLE_PATH or items.empty():
		return false
	var fight = DataManager.get_current_battle_fight()
	if fight == null:
		return false
	var actor_id = DataManager.get_env_int("当前武将", -1)
	if not actor_id in [fight.get_attacker_id(), fight.get_defender_id()]:
		return false
	for item in items:
		if not item is Array or item.size() != 3 or not item[0] is int or not item[1] is bool or not item[2] is int:
			return false
		if item[1] != (actor_id == fight.get_defender_id()):
			return false
	for unit in DataManager.battle_units:
		if unit.leaderId == actor_id:
			return true
	return false


# Pure projection of IFormation.set_formation: preserve the native array order,
# its only two filters, and its per-unit right-side mirror. Never place units.
func project_formation(actor_id: int, formation: int) -> Dictionary:
	var scene = SceneManager.current_scene()
	if scene == null or scene.filename != BATTLE_PATH:
		return {}
	var setting = StaticManager.get_formation_setting(formation)
	if not setting is Dictionary or not setting.get("positions") is Array:
		return {}
	var result = {"actor_id": actor_id, "formation": formation, "name": str(setting.get("name", "阵型")), "columns": int(scene.cell_columns), "rows": int(scene.cell_rows), "units": [], "fixed": {}, "counts": {}, "outside": 0}
	var index = 0
	for unit in DataManager.battle_units:
		if unit.leaderId != actor_id:
			continue
		var type_name = str(unit.Type)
		if unit.dic_combat.get("不布阵", false):
			result.fixed[type_name] = int(result.fixed.get(type_name, 0)) + 1
			continue
		var position = Vector2(-1, -1)
		if index < setting.positions.size():
			position = Vector2(setting.positions[index][0], setting.positions[index][1])
		if unit.get_side() == Vector2.RIGHT:
			position.x = scene.cell_columns - position.x - 1
		index += 1
		result.units.append({"unit_id": unit.unitId, "type": type_name, "symbol": _symbol(type_name), "position": position})
		result.counts[type_name] = int(result.counts.get(type_name, 0)) + 1
		if position.x < 0 or position.y < 0 or position.x >= result.columns or position.y >= result.rows:
			result.outside += 1
	return result


func create_formation_texture(formation: int, inverted: bool, units: int) -> ImageTexture:
	if not _formation_mode or not _has_formation_context():
		return .create_formation_texture(formation, inverted, units)
	var fight = DataManager.get_current_battle_fight()
	var actor_id = fight.get_defender_id() if inverted else fight.get_attacker_id()
	var projection = project_formation(actor_id, formation)
	if projection.empty():
		return .create_formation_texture(formation, inverted, units)
	var width = 168 if formation == 4 else 108
	var image = Image.new()
	image.create(width, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color("#f2e9d0"))
	image.lock()
	_paint_rect(image, Rect2(0, 0, width, 3), Color("#352d23"))
	_paint_rect(image, Rect2(0, 93, width, 3), Color("#352d23"))
	_paint_rect(image, Rect2(0, 0, 3, 96), Color("#352d23"))
	_paint_rect(image, Rect2(width - 3, 0, 3, 96), Color("#352d23"))
	for unit in projection.units:
		var position: Vector2 = unit.position
		if position.x < 0 or position.y < 0 or position.x >= projection.columns or position.y >= projection.rows:
			continue
		var x = position.x * 16 + 12
		if inverted:
			x = (position.x - projection.columns + 1) * 16 + width - 13
		var y = position.y * 10
		var color: Color = _colors.get(unit.symbol, Color("#6b6670"))
		_paint_rect(image, Rect2(x - 6, y - 5, 11, 8), Color("#352d23"))
		_paint_rect(image, Rect2(x - 5, y - 4, 9, 6), color)
		# Distinct marks remain readable in the compact native thumbnails.
		if unit.symbol == "将":
			_paint_rect(image, Rect2(x - 1, y - 3, 2, 4), Color.white)
		elif unit.symbol in ["骑", "象"]:
			_paint_rect(image, Rect2(x - 4, y - 1, 7, 1), Color.white)
		elif unit.symbol == "弓":
			_paint_rect(image, Rect2(x + 2, y - 3, 1, 4), Color.white)
		elif unit.symbol == "藤":
			_paint_rect(image, Rect2(x - 3, y - 3, 1, 4), Color.white)
			_paint_rect(image, Rect2(x, y - 3, 1, 4), Color.white)
	image.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(image, 0)
	return texture


func _paint_rect(image: Image, area: Rect2, color: Color) -> void:
	for x in range(max(0, int(area.position.x)), min(image.get_width(), int(area.end.x))):
		for y in range(max(0, int(area.position.y)), min(image.get_height(), int(area.end.y))):
			image.set_pixel(x, y, color)


func _symbol(type_name: String) -> String:
	if type_name.begins_with("将"):
		return "将"
	if type_name.find("藤") >= 0:
		return "藤"
	var base_name = type_name.split("(")[0]
	for symbol in ["象", "弓", "骑", "步", "仙"]:
		if base_name.find(symbol) >= 0:
			return symbol
	if type_name.find("门") >= 0:
		return "门"
	return type_name.substr(0, 1) if not type_name.empty() else "兵"


func _font(size: int):
	var font = rtlMessage.get_font("normal_font").duplicate()
	if font is DynamicFont:
		font.size = size
	return font


func _ensure_preview() -> void:
	if is_instance_valid(_preview_panel):
		return
	_preview_panel = Panel.new()
	_preview_panel.name = "FormationPreview"
	_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#29251f")
	style.border_color = Color("#b59b68")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	_preview_panel.add_stylebox_override("panel", style)
	add_child(_preview_panel)
	_preview_title = Label.new()
	_preview_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_title.add_font_override("font", _font(24))
	_preview_title.add_color_override("font_color", Color("#f6e6bd"))
	_preview_panel.add_child(_preview_title)
	_board = FormationBoard.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.unit_font = _font(17)
	_board.type_colors = _colors
	_preview_panel.add_child(_board)
	_legend = RichTextLabel.new()
	_legend.mouse_filter = Control.MOUSE_FILTER_PASS
	_legend.bbcode_enabled = true
	_legend.scroll_active = true
	_legend.add_font_override("normal_font", _font(18))
	_legend.add_font_override("bold_font", _font(18))
	_legend.add_color_override("default_color", Color("#f4ead4"))
	_preview_panel.add_child(_legend)
	_help = Label.new()
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_font_override("font", _font(18))
	_help.add_color_override("font_color", Color("#d7c8aa"))
	_help.text = "点选后按 A 确认"
	_preview_panel.add_child(_help)


func _refresh_preview() -> void:
	if not is_instance_valid(_preview_panel):
		return
	if not is_visible_in_tree() or not _has_formation_context() or cursor_index < 0 or cursor_index >= items.size():
		_preview_panel.hide()
		_board.projection = {}
		_last_preview_key = ""
		return
	var actor_id = DataManager.get_env_int("当前武将", -1)
	var formation = int(items[cursor_index][0])
	var projection = project_formation(actor_id, formation)
	if projection.empty():
		_preview_panel.hide()
		return
	var key = str(actor_id) + ":" + str(formation) + ":" + str(projection.hash())
	if key != _last_preview_key:
		_last_preview_key = key
		_board.projection = projection
		_board.update()
		var inverted = bool(items[cursor_index][1])
		_preview_title.text = "%s · %s · %s" % [ActorHelper.actor(actor_id).get_name(), projection.name, "← 守方" if inverted else "攻方 →"]
		_legend.clear()
		for type_name in projection.counts:
			_legend.push_color(_colors.get(_symbol(type_name), Color("#bdb5c6")))
			_legend.add_text("■ ")
			_legend.pop()
			_legend.add_text("%s ×%d\n" % [type_name, projection.counts[type_name]])
		if not projection.fixed.empty():
			_legend.add_text("\n固定单位（不布阵）\n")
			for type_name in projection.fixed:
				_legend.add_text("%s ×%d\n" % [type_name, projection.fixed[type_name]])
		if projection.outside > 0:
			_legend.add_text("\n未入阵：%d\n" % projection.outside)
	_preview_panel.show()
	_layout_preview()


func _layout_preview() -> void:
	var area = Layout.available_area(get_viewport(), 12, false)
	var compact = area.size.y < 470
	var menu_height = 112.0 if compact else 190.0
	var menu_width = min(600.0, area.size.x)
	rect_size = Vector2(menu_width, menu_height)
	rect_global_position = Vector2(area.position.x + (area.size.x - menu_width) * 0.5, area.end.y - menu_height)
	get_node("bottom_scene").rect_size = Vector2(menu_width, menu_height)
	if compact:
		conActor.hide()
		rtlMessage.hide()
		container.rect_position = Vector2(14, 15)
		container.rect_size = Vector2(menu_width - 28, 96)
	else:
		conActor.visible = _actorId >= 0
		rtlMessage.show()
		container.rect_position = Vector2(145, 66)
		container.rect_size = Vector2(menu_width - 192, 120)
	var menu_top = rect_global_position.y
	var height = min(290.0, menu_top - area.position.y - 12.0)
	if height < 180:
		height = min(290.0, area.size.y - rect_size.y - 20.0)
	var width = min(520.0, area.size.x)
	_preview_panel.rect_size = Vector2(width, max(180.0, height))
	_preview_panel.rect_global_position = Vector2(area.position.x + (area.size.x - width) * 0.5, max(area.position.y, menu_top - _preview_panel.rect_size.y - 8.0))
	_preview_title.rect_position = Vector2(14, 8)
	_preview_title.rect_size = Vector2(width - 28, 32)
	var cell = max(11.0, min(23.0, min((width - 215.0) / _board.projection.get("columns", 16), (_preview_panel.rect_size.y - 56.0) / _board.projection.get("rows", 10))))
	_board.cell_size = cell
	_board.rect_position = Vector2(14, 44)
	_board.rect_size = Vector2(_board.projection.get("columns", 16), _board.projection.get("rows", 10)) * cell
	if _board.unit_font is DynamicFont:
		_board.unit_font.size = max(10, int(cell) - 3)
	_board.update()
	_legend.rect_position = Vector2(_board.rect_position.x + _board.rect_size.x + 16, 44)
	_legend.rect_size = Vector2(max(100, width - _legend.rect_position.x - 12), _preview_panel.rect_size.y - 76)
	_help.rect_position = Vector2(_legend.rect_position.x, _preview_panel.rect_size.y - 29)
	_help.rect_size = Vector2(_legend.rect_size.x, 24)


func _capture_native_layout() -> void:
	if not _native_layout.empty():
		return
	for node in [self, get_node("bottom_scene"), conActor, rtlMessage, container]:
		var state = {"node": node, "visible": node.visible}
		for property in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "margin_left", "margin_top", "margin_right", "margin_bottom"]:
			state[property] = node.get(property)
		_native_layout.append(state)


func _restore_native_layout() -> void:
	for state in _native_layout:
		if not is_instance_valid(state.node):
			continue
		for property in state:
			if property != "node" and (property != "visible" or state.node != self):
				state.node.set(property, state[property])
	_native_layout.clear()


func _preview_visibility_changed() -> void:
	if is_visible_in_tree():
		if _formation_mode:
			_capture_native_layout()
			_refresh_preview()
	else:
		_restore_native_layout()
		if is_instance_valid(_preview_panel):
			_preview_panel.hide()
			_board.projection = {}
		_last_preview_key = ""
