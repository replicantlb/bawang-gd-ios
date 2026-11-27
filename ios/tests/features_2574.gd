extends SceneTree

var checks := 0
var failures := 0
var taps := 0
var manager


func _initialize():
	call_deferred("_run")


func check(value, label: String) -> void:
	checks += 1
	print("FEATURE_CHECK ", label, " ", value)
	if not value:
		failures += 1


func frames(count := 3):
	for _index in range(count):
		yield(self, "idle_frame")


func mouse(position: Vector2, pressed: bool) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	Input.parse_input_event(event)


func key(code: int, pressed: bool, unicode_value := 0) -> void:
	var event = InputEventKey.new()
	event.scancode = code
	event.unicode = unicode_value
	event.pressed = pressed
	Input.parse_input_event(event)


func touch(index: int, position: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)


func _tapped() -> void:
	taps += 1


func _run():
	yield(frames(), "completed")
	var name = OS.get_environment("BAWANG_QA_NAME")
	if not name.begins_with("BawangFeatureQA-") or OS.get_user_data_dir().get_file() != name:
		quit(1)
		return
	manager = root.get_node("MobileKeyboard")
	check(manager.get_script().resource_path == "res://ios_keyboard_manager.gd", "keyboard manager autoload installed")
	var layer = CanvasLayer.new()
	layer.layer = 200
	root.add_child(layer)
	var popup = PopupPanel.new()
	popup.popup_exclusive = true
	layer.add_child(popup)
	var body = Control.new()
	popup.add_child(body)
	var first = LineEdit.new()
	first.text = "中文搜索"
	first.clear_button_enabled = true
	first.rect_position = Vector2(30, 30)
	first.rect_size = Vector2(280, 50)
	body.add_child(first)
	var second = LineEdit.new()
	second.rect_position = Vector2(350, 30)
	second.rect_size = Vector2(280, 50)
	body.add_child(second)
	var multiline = TextEdit.new()
	multiline.text = "补丁第一行"
	multiline.rect_position = Vector2(30, 110)
	multiline.rect_size = Vector2(280, 110)
	body.add_child(multiline)
	var number = SpinBox.new()
	number.max_value = 1000
	number.rect_position = Vector2(350, 110)
	number.rect_size = Vector2(150, 50)
	body.add_child(number)
	var button = Button.new()
	button.text = "选择结果"
	button.focus_mode = Control.FOCUS_NONE
	button.rect_position = Vector2(350, 200)
	button.rect_size = Vector2(200, 50)
	button.connect("pressed", self, "_tapped")
	body.add_child(button)
	popup.popup_centered(Vector2(760, 400))
	yield(frames(), "completed")
	first.grab_focus()
	yield(frames(), "completed")
	var inside = first.rect_global_position + Vector2(20, 20)
	mouse(inside, true)
	mouse(inside, false)
	yield(frames(), "completed")
	check(first.has_focus() and first.text == "中文搜索", "tap inside input preserves focus and text")
	var destination = second.rect_global_position + Vector2(20, 20)
	mouse(destination, true)
	mouse(destination, false)
	yield(frames(), "completed")
	check(second.has_focus(), "switching fields keeps new input focused")
	first.grab_focus()
	yield(frames(), "completed")
	var target = button.rect_global_position + button.rect_size * 0.5
	mouse(target, true)
	yield(frames(), "completed")
	check(first.has_focus() and taps == 0, "outside press does not dismiss or activate before release")
	mouse(target, false)
	yield(frames(), "completed")
	check(taps == 1 and not first.has_focus(), "result tap activates once and dismisses after release")
	check(popup.visible, "keyboard dismissal keeps exclusive popup open")
	first.grab_focus()
	yield(frames(), "completed")
	var blank = popup.rect_global_position + Vector2(700, 330)
	mouse(blank, true)
	yield(frames(), "completed")
	second.grab_focus()
	first.grab_focus()
	mouse(blank, false)
	yield(frames(), "completed")
	check(first.has_focus(), "old outside gesture cannot dismiss an input refocused in same frame")
	touch(0, blank, true)
	yield(frames(), "completed")
	touch(1, inside, true)
	yield(frames(), "completed")
	touch(0, blank, false)
	yield(frames(), "completed")
	check(first.has_focus(), "outside finger release cannot blur input while another finger is inside")
	touch(1, inside, false)
	yield(frames(), "completed")
	check(first.has_focus() and manager._pointers.empty(), "new inside touch supersedes old outside gesture without stuck pointers")
	first.grab_focus()
	yield(frames(), "completed")
	key(KEY_ENTER, true, 13)
	key(KEY_ENTER, false)
	yield(frames(), "completed")
	check(not first.has_focus() and first.text == "中文搜索", "single line Return completes without changing text")
	number.get_line_edit().grab_focus()
	yield(frames(), "completed")
	number.get_line_edit().text = "42"
	key(KEY_ENTER, true, 13)
	key(KEY_ENTER, false)
	yield(frames(), "completed")
	check(number.value == 42 and not number.get_line_edit().has_focus(), "SpinBox commits number before dismissing")
	number.get_line_edit().grab_focus()
	yield(frames(), "completed")
	number.get_line_edit().text = "84"
	mouse(target, true)
	mouse(target, false)
	yield(frames(), "completed")
	check(number.value == 84, "outside tap commits SpinBox draft on focus loss")
	multiline.grab_focus()
	multiline.cursor_set_line(0)
	multiline.cursor_set_column(multiline.text.length())
	yield(frames(), "completed")
	key(KEY_ENTER, true, 10)
	key(KEY_ENTER, false)
	yield(frames(), "completed")
	check(multiline.has_focus() and "\n" in multiline.text, "multiline Return remains a newline")
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	yield(frames(), "completed")
	check(not multiline.has_focus() and popup.visible, "Escape dismisses keyboard without closing popup")
	first.grab_focus()
	yield(frames(), "completed")
	manager._observe_keyboard(300, 0.01)
	manager._observe_keyboard(0, 0.2)
	check(not first.has_focus(), "native keyboard close releases matching Godot focus")
	first.grab_focus()
	yield(frames(), "completed")
	manager._observe_keyboard(300, 0.01)
	manager._observe_keyboard(0, 0.01)
	second.grab_focus()
	manager._watch_focus()
	manager._observe_keyboard(0, 0.2)
	check(second.has_focus(), "delayed native close does not blur another input")
	check(not manager._is_editor(button), "ordinary controls excluded")
	first.editable = false
	check(not manager._is_editor(first), "read only key binding input excluded")
	first.editable = true
	first.virtual_keyboard_enabled = false
	check(not manager._is_editor(first), "inputs with virtual keyboard disabled excluded")
	first.virtual_keyboard_enabled = true
	first.grab_focus()
	yield(frames(), "completed")
	paused = true
	mouse(blank, true)
	mouse(blank, false)
	yield(frames(), "completed")
	check(not first.has_focus(), "keyboard dismissal works while gameplay is paused")
	paused = false
	first.grab_focus()
	yield(frames(), "completed")
	touch(0, blank, true)
	manager._notification(MainLoop.NOTIFICATION_APP_PAUSED)
	check(not first.has_focus() and manager._pointers.empty(), "backgrounding releases focus and pending touches")
	touch(0, blank, false)
	second.grab_focus()
	yield(frames(), "completed")
	popup.hide()
	yield(frames(), "completed")
	check(not second.has_focus(), "hidden popup releases input focus")
	layer.queue_free()
	yield(frames(), "completed")
	check(manager._pointers.empty(), "pointer bookkeeping is cleared")
	print("FEATURE_RESULT ", checks, " ", failures)
	quit(1 if failures > 0 else 0)
