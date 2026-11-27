extends "res://windows/virtukey.gd"

const UP = 1
const DOWN = 2
const LEFT = 4
const RIGHT = 8
const DIRECTIONS = ["ANALOG_UP", "ANALOG_DOWN", "ANALOG_LEFT", "ANALOG_RIGHT"]
const ACTIONS = ["ANALOG_UP", "ANALOG_DOWN", "ANALOG_LEFT", "ANALOG_RIGHT", "EMU_A", "EMU_B", "EMU_X", "EMU_Y", "EMU_SELECT", "EMU_START"]
const BUTTONS = {
	"btnUp": UP, "btnDown": DOWN, "btnLeft": LEFT, "btnRight": RIGHT,
	"btnLeftUp": LEFT | UP, "btnLeftDown": LEFT | DOWN,
	"btnRightUp": RIGHT | UP, "btnRightDown": RIGHT | DOWN,
}
const FACE_BUTTONS = ["A", "B", "X", "Y", "select", "start"]

onready var direction_pad: Control = $VirtualKey/con_analog
var direction_buttons := []
var face_buttons := []
# A touch belongs to the control where it began until that finger is lifted.
var touch_points := {}
var control_mask := 0
var direction_mask := 0
var press_sequence := 0
var last_diagonal_setting := true
var hit_probe := CircleShape2D.new()


func _ready() -> void:
	add_to_group("ios_virtual_pad")
	hit_probe.radius = 0.01
	for button_name in BUTTONS:
		var button: TouchScreenButton = direction_pad.get_node(button_name)
		direction_buttons.append([button, BUTTONS[button_name], _shape_origin(button)])
	for index in range(FACE_BUTTONS.size()):
		var suffix: String = FACE_BUTTONS[index]
		var container = get_node("VirtualKey/con_btnemu_" + suffix)
		var button: TouchScreenButton = container.get_node("btnemu_" + suffix)
		face_buttons.append([button, 1 << (index + 4), _shape_origin(button)])
		# Gameplay signals are removed by prepare_game_pack; retain the original
		# layout editor's selection/dragging behavior while emulation is disabled.
		button.connect("pressed", self, "_layout_button_pressed", [container])
		button.connect("visibility_changed", self, "_face_visibility_changed")
	direction_pad.connect("visibility_changed", self, "_direction_pad_visibility_changed")
	set_physics_process(false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if not _accepts_controls():
		release_all_touches()
		return

	var fresh_mask := 0
	if event is InputEventScreenTouch:
		if event.pressed:
			# Reusing an index must never leave its previous owner's action held.
			touch_points.erase(event.index)
			var owner = _owner_at(event.position)
			if owner >= -1:
				press_sequence += 1
				touch_points[event.index] = {"owner": owner, "position": event.position, "sequence": press_sequence}
				fresh_mask = _touch_mask(touch_points[event.index])
		else:
			touch_points.erase(event.index)
	elif touch_points.has(event.index):
		touch_points[event.index]["position"] = event.position
	else:
		return

	set_physics_process(not touch_points.empty())
	_update_controls(fresh_mask)


func _physics_process(_delta: float) -> void:
	if not _accepts_controls():
		release_all_touches()
	else:
		# Also notices a single button being hidden or a layout setting changing.
		# Never reassert consumed actions every frame; only a fresh press may do so.
		_update_controls()


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_FOCUS_OUT or what == MainLoop.NOTIFICATION_APP_PAUSED:
		release_all_touches()


func _exit_tree() -> void:
	release_all_touches()


func _layout_button_pressed(container: Control) -> void:
	if emu_set:
		on_enum_btn_set_pressed(container)


func change_set_mode(enabled: bool) -> void:
	release_all_touches()
	.change_set_mode(enabled)


func _on_btnSetting_pressed() -> void:
	release_all_touches()
	if _trial_active():
		Input.action_release("EMU_MENU")
		return
	._on_btnSetting_pressed()


func _on_btnSetting_released() -> void:
	if _trial_active():
		Input.action_release("EMU_MENU")
		return
	._on_btnSetting_released()


func _virtualkey_show() -> void:
	# The native display refresh also opens the ordinary menu for EMU_MENU.
	# Keep its button highlights/speed controls, but consume that action in trials.
	if _trial_active():
		Input.action_release("EMU_MENU")
	._virtualkey_show()


func _trial_active() -> bool:
	var session = get_node_or_null("/root/TrialSession")
	return session != null and session.active


func _direction_pad_visibility_changed() -> void:
	if not direction_pad.is_visible_in_tree():
		for index in touch_points.keys():
			if touch_points[index]["owner"] == -1:
				touch_points.erase(index)
		_update_controls()


func _face_visibility_changed() -> void:
	for index in touch_points.keys():
		var owner: int = touch_points[index]["owner"]
		if owner >= 0 and not face_buttons[owner][0].is_visible_in_tree():
			touch_points.erase(index)
	_update_controls()


func _accepts_controls() -> bool:
	if not emu_enable or emu_set or not is_visible_in_tree():
		return false
	var modal = get_viewport().get_modal_stack_top()
	return modal == null or not modal.popup_exclusive


func _shape_origin(button: TouchScreenButton) -> Vector2:
	if not button.shape_centered:
		return Vector2.ZERO
	if button.normal != null:
		return button.normal.get_size() * 0.5
	var shape := button.shape
	if shape is RectangleShape2D:
		return shape.extents
	if shape is CircleShape2D:
		return Vector2(shape.radius, shape.radius)
	if shape is CapsuleShape2D:
		return Vector2(shape.radius, shape.radius + shape.height * 0.5)
	return Vector2.ZERO


func _contains(entry: Array, position: Vector2) -> bool:
	var button: TouchScreenButton = entry[0]
	if not button.is_visible_in_tree():
		return false
	var local = button.get_global_transform_with_canvas().affine_inverse().xform(position)
	if button.shape != null:
		return button.shape.collide(Transform2D(), hit_probe, Transform2D(0, local - entry[2]))
	if button.normal == null:
		return false
	return Rect2(Vector2.ZERO, button.normal.get_size()).has_point(local)


func _direction_bits_at(position: Vector2) -> int:
	var mask := 0
	for entry in direction_buttons:
		var bits: int = entry[1]
		if not allow_tilting and (bits & (bits - 1)) != 0:
			continue
		if _contains(entry, position):
			mask |= bits
	# A single finger on overlapping custom buttons must not press opposite axes.
	if (mask & (UP | DOWN)) == (UP | DOWN):
		mask &= ~(UP | DOWN)
	if (mask & (LEFT | RIGHT)) == (LEFT | RIGHT):
		mask &= ~(LEFT | RIGHT)
	return mask


func _owner_at(position: Vector2) -> int:
	for index in range(face_buttons.size()):
		if _contains(face_buttons[index], position):
			return index
	if direction_pad.is_visible_in_tree() and _direction_bits_at(position) != 0:
		return -1
	return -2


func _touch_mask(touch: Dictionary) -> int:
	if touch["owner"] == -1:
		return _direction_bits_at(touch["position"]) if direction_pad.is_visible_in_tree() else 0
	var entry: Array = face_buttons[touch["owner"]]
	return entry[1] if _contains(entry, touch["position"]) else 0


func _update_controls(fresh_mask := 0) -> void:
	last_diagonal_setting = allow_tilting
	var mask := 0
	var horizontal_sequence := -1
	var vertical_sequence := -1
	for touch in touch_points.values():
		var bits := _touch_mask(touch)
		mask |= bits & ~15
		if (bits & (LEFT | RIGHT)) != 0 and touch["sequence"] > horizontal_sequence:
			horizontal_sequence = touch["sequence"]
			mask = (mask & ~(LEFT | RIGHT)) | (bits & (LEFT | RIGHT))
		if (bits & (UP | DOWN)) != 0 and touch["sequence"] > vertical_sequence:
			vertical_sequence = touch["sequence"]
			mask = (mask & ~(UP | DOWN)) | (bits & (UP | DOWN))
	_set_control_mask(mask, fresh_mask & mask)


func release_all_touches() -> void:
	touch_points.clear()
	set_physics_process(false)
	_set_control_mask(0)


# Keep the former cleanup entry point for integrations with the virtual pad.
func _clear_direction_touches() -> void:
	release_all_touches()


func _set_control_mask(mask: int, fresh_mask := 0) -> void:
	var changed := control_mask ^ mask
	control_mask = mask
	direction_mask = mask & 15
	for index in range(ACTIONS.size()):
		var bit := 1 << index
		var action: String = ACTIONS[index]
		if (changed & bit) != 0:
			if (mask & bit) != 0:
				Input.action_press(action)
			else:
				Input.action_release(action)
		elif (fresh_mask & bit) != 0 and not Input.is_action_pressed(action):
			Input.action_press(action)
