extends Control

const KEYBOARD_CLOSE_GRACE := 0.18

var _editor_ref: WeakRef
var _focus_epoch := 0
var _pointers := {}
var _outside := {}
var _keyboard_height_before := 0
var _keyboard_editor: WeakRef
var _keyboard_epoch := -1
var _closed_editor: WeakRef
var _closed_epoch := -1
var _closed_elapsed := 0.0
var _escape_latched := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	pause_mode = Node.PAUSE_MODE_PROCESS


func _is_editor(control) -> bool:
	if not is_instance_valid(control) or not control is Control or not control.is_visible_in_tree():
		return false
	if control is LineEdit:
		return control.editable and control.virtual_keyboard_enabled
	if control is TextEdit:
		return not control.readonly and control.virtual_keyboard_enabled
	return false


func _ref_value(reference: WeakRef):
	return reference.get_ref() if reference != null else null


func _watch_focus() -> void:
	var owner = get_focus_owner()
	var editor = owner if _is_editor(owner) else null
	var previous = _ref_value(_editor_ref)
	if editor == previous and (_editor_ref == null or previous != null):
		return
	_focus_epoch += 1
	_editor_ref = weakref(editor) if editor != null else null
	if editor != null and not editor.is_connected("focus_exited", self, "_editor_focus_exited"):
		editor.connect("focus_exited", self, "_editor_focus_exited")
	if editor is LineEdit and not editor.is_connected("text_entered", self, "_line_finished"):
		# SpinBox gets the original signal first, so its value is committed before
		# focus is released. TextEdit keeps its ordinary multiline Return behavior.
		editor.connect("text_entered", self, "_line_finished", [weakref(editor)])
	if editor == null and (previous != null or _keyboard_height_before > 0):
		if _pointers.empty():
			call_deferred("_dismiss_if_same_editor", weakref(previous) if previous != null else null, _focus_epoch)


func _editor_focus_exited() -> void:
	# Even an A -> B -> A switch inside one frame invalidates an older gesture.
	_focus_epoch += 1


func _process(delta: float) -> void:
	_watch_focus()
	_observe_keyboard(OS.get_virtual_keyboard_height(), delta)
	var owner = get_focus_owner()
	if is_instance_valid(owner) and (owner is LineEdit or owner is TextEdit) and not owner.is_visible_in_tree() and _pointers.empty():
		call_deferred("_dismiss_if_same_editor", weakref(owner), _focus_epoch)


func _observe_keyboard(height: int, delta: float) -> void:
	if height > 0:
		_keyboard_editor = _editor_ref
		_keyboard_epoch = _focus_epoch
		_closed_editor = null
	elif _keyboard_height_before > 0:
		# The native accessory resigns UIKit's responder. Also release the matching
		# Godot focus once the keyboard has really closed; ignore a new text field.
		_closed_editor = _keyboard_editor
		_closed_epoch = _keyboard_epoch
		_closed_elapsed = 0.0
	_keyboard_height_before = height
	if height == 0 and _closed_editor != null:
		_closed_elapsed += delta
		if _closed_elapsed >= KEYBOARD_CLOSE_GRACE and _pointers.empty():
			var closed = _closed_editor
			_closed_editor = null
			if _closed_epoch == _focus_epoch:
				_dismiss_if_same_editor(closed)


func _contains(editor: Control, position: Vector2) -> bool:
	var local = editor.get_global_transform_with_canvas().affine_inverse().xform(position)
	return Rect2(Vector2.ZERO, editor.rect_size).has_point(local)


func _input(event: InputEvent) -> void:
	_watch_focus()
	if event is InputEventKey and event.scancode == KEY_ESCAPE:
		if not event.pressed and _escape_latched:
			_escape_latched = false
			get_tree().set_input_as_handled()
		elif event.pressed and _is_editor(get_focus_owner()):
			_escape_latched = true
			_dismiss_if_same_editor(weakref(get_focus_owner()))
			get_tree().set_input_as_handled()
		return
	var key = ""
	var pressed = false
	var position = Vector2.ZERO
	if event is InputEventScreenTouch:
		key = "touch:" + str(event.index)
		pressed = event.pressed
		position = event.position
	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		key = "mouse"
		pressed = event.pressed
		position = event.position
	else:
		return
	if pressed:
		var owner = get_focus_owner()
		if _is_editor(owner) and _contains(owner, position):
			# A new interaction inside this input also supersedes an older outside
			# finger, even when the field never lost focus in between.
			_focus_epoch += 1
			_pointers[key] = {}
		else:
			_pointers[key] = {"editor": weakref(owner), "epoch": _focus_epoch} if _is_editor(owner) else {}
	else:
		var original: Dictionary = _pointers.get(key, {})
		_pointers.erase(key)
		var editor = _ref_value(original.get("editor"))
		if is_instance_valid(editor) and not _contains(editor, position):
			_outside = original
		if _pointers.empty() and not _outside.empty():
			var outside = _outside
			_outside = {}
			# Never resize the popup between button-down and button-up, and never
			# consume the tap which selects a result, scrolls, or opens another input.
			call_deferred("_dismiss_if_same_editor", outside.editor, outside.epoch)


func _line_finished(_text: String, editor: WeakRef) -> void:
	call_deferred("_dismiss_if_same_editor", editor, _focus_epoch)


func _dismiss_if_same_editor(reference: WeakRef, epoch := -1) -> void:
	var editor = _ref_value(reference)
	var current = get_focus_owner()
	if _is_editor(current) and epoch >= 0 and epoch != _focus_epoch:
		return
	if _is_editor(current) and current != editor:
		return
	if is_instance_valid(editor) and current == editor:
		editor.release_focus()
	OS.hide_virtual_keyboard()


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_FOCUS_OUT or what == MainLoop.NOTIFICATION_APP_PAUSED:
		_pointers.clear()
		_outside = {}
		_closed_editor = null
		_escape_latched = false
		if is_inside_tree():
			var owner = get_focus_owner()
			if _is_editor(owner):
				_dismiss_if_same_editor(weakref(owner))
