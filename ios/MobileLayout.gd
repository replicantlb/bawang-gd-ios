extends Reference


static func available_area(viewport: Viewport, margin := 12.0, avoid_keyboard := true) -> Rect2:
	var logical = viewport.get_visible_rect()
	var window_size = OS.get_window_size()
	var keyboard = OS.get_virtual_keyboard_height() if avoid_keyboard else 0
	var fallback = logical
	if window_size.y > 0:
		fallback.size.y = max(0, logical.size.y - keyboard * logical.size.y / window_size.y)
	# The application uses a centered root viewport with stretch/aspect="keep".
	# Child viewports and unknown render configurations retain conservative margins.
	if viewport != viewport.get_tree().root or window_size.x <= 0 or window_size.y <= 0:
		return _inset(fallback, margin)
	var safe = Rect2(Vector2.ZERO, window_size)
	if OS.has_method("get_window_safe_area"):
		var reported = OS.call("get_window_safe_area")
		if reported is Rect2 and reported.size.x > 0 and reported.size.y > 0:
			safe = reported
	var result = map_window_area(logical, viewport.get_final_transform(), viewport.size, window_size, safe, keyboard)
	return _inset(result, margin)


static func map_window_area(logical: Rect2, final_transform: Transform2D, render_size: Vector2, window_size: Vector2, safe: Rect2, keyboard_pixels := 0.0) -> Rect2:
	var fallback = logical
	if window_size.y > 0:
		fallback.size.y = max(0, logical.size.y - keyboard_pixels * logical.size.y / window_size.y)
	var determinant = final_transform.x.x * final_transform.y.y - final_transform.x.y * final_transform.y.x
	if abs(determinant) < 0.00001 or abs(final_transform.x.y) > 0.0001 or abs(final_transform.y.x) > 0.0001:
		return fallback
	if render_size.x <= 0 or render_size.y <= 0 or render_size.x > window_size.x + 2 or render_size.y > window_size.y + 2:
		return fallback
	# OS safe area is in window-local physical pixels on both current Mac and iOS
	# templates. Window position is deliberately not subtracted.
	var offset = (window_size - render_size) * 0.5
	var render_rect = Rect2(offset, render_size)
	var pixels = safe.clip(Rect2(Vector2.ZERO, window_size)).clip(render_rect)
	if keyboard_pixels > 0:
		pixels = pixels.clip(Rect2(Vector2.ZERO, Vector2(window_size.x, max(0, window_size.y - keyboard_pixels))))
	if pixels.size.x <= 0 or pixels.size.y <= 0:
		return Rect2(logical.position, Vector2.ZERO)
	pixels.position -= offset
	var mapped: Rect2 = final_transform.affine_inverse().xform(pixels)
	return mapped.clip(logical)


static func _inset(area: Rect2, margin: float) -> Rect2:
	var horizontal = min(max(0, margin), area.size.x * 0.5)
	var vertical = min(max(0, margin), area.size.y * 0.5)
	return Rect2(area.position + Vector2(horizontal, vertical), Vector2(max(0, area.size.x - horizontal * 2), max(0, area.size.y - vertical * 2)))
