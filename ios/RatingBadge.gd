extends Control

const COLORS = {"S": Color("f4ce66"), "A": Color("eda27f"), "B": Color("8fd0ba"), "C": Color("b9c3d5"), "D": Color("969696"), "?": Color("aaaaaa")}
var grades := []
var font: DynamicFont


func _ready() -> void:
	set_meta("ios_rating_decoration", true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	font = Global.get_font(12)
	set_process(false)


func show_grades(values: Array) -> void:
	grades = values.duplicate()
	var width = max(17, grades.size() * 12 + max(0, grades.size() - 1) * 5 + 5)
	anchor_left = 1
	anchor_right = 1
	margin_left = -width - 3
	margin_right = -3
	margin_top = 2
	margin_bottom = 19
	update()


func _draw() -> void:
	if font == null or grades.empty():
		return
	var background = StyleBoxFlat.new()
	background.bg_color = Color(0.07, 0.07, 0.08, 0.9)
	background.set_corner_radius_all(3)
	draw_style_box(background, Rect2(Vector2.ZERO, rect_size))
	var x = 4.0
	for index in range(grades.size()):
		var grade = grades[index]
		if index > 0:
			draw_string(font, Vector2(x, 13), "/", Color("aaaaaa"))
			x += 5
		draw_string(font, Vector2(x, 13), grade, COLORS.get(grade, COLORS["?"]))
		x += 12
