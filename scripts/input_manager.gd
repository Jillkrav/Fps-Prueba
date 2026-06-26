# scripts/input_manager.gd
# Autoload singleton. Ensure all input actions exist and manage key rebinding.
extends Node

# Signal emitted when any key binding changes
signal key_binding_changed(action_name: String)

# Dictionary with default action names and their human-readable labels
const ACTION_LABELS: Dictionary = {
	"move_forward": "Moverse Adelante",
	"move_back": "Moverse Atrás",
	"move_left": "Moverse Izquierda",
	"move_right": "Moverse Derecha",
	"jump": "Saltar",
	"shoot": "Disparar",
	"reload": "Recargar",
	"crouch": "Agacharse",
	"pause_menu": "Menú de Pausa",
	"dev_menu": "Menú Dev",
	"scoreboard": "Scoreboard / Tabla"
}

# Default key mappings (action_name -> physical_keycode or mouse button)
const DEFAULT_KEYS: Dictionary = {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"reload": KEY_R,
	"crouch": KEY_C,
	"pause_menu": KEY_ESCAPE,
	"dev_menu": KEY_Q,
	"scoreboard": KEY_TAB
}

# Default mouse button mappings (action_name -> button_index)
const DEFAULT_MOUSE: Dictionary = {
	"shoot": MOUSE_BUTTON_LEFT
}

# Second key for shoot (F key)
const DEFAULT_KEY_SECONDARY: Dictionary = {
	"shoot": KEY_F
}

# Path to save custom key bindings
const BINDINGS_PATH: String = "user://key_bindings.cfg"

func _ready() -> void:
	_ensure_actions_exist()
	_load_bindings()

func _ensure_actions_exist() -> void:
	"""Ensure all required input actions exist in InputMap."""
	for action in ACTION_LABELS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			# Add default binding
			if DEFAULT_KEYS.has(action):
				var event := InputEventKey.new()
				event.physical_keycode = DEFAULT_KEYS[action]
				InputMap.action_add_event(action, event)
			if DEFAULT_MOUSE.has(action):
				var event := InputEventMouseButton.new()
				event.button_index = DEFAULT_MOUSE[action]
				InputMap.action_add_event(action, event)
			if DEFAULT_KEY_SECONDARY.has(action):
				var event := InputEventKey.new()
				event.physical_keycode = DEFAULT_KEY_SECONDARY[action]
				InputMap.action_add_event(action, event)

func get_action_key(action_name: String) -> int:
	"""Get the primary physical keycode for an action. Returns -1 if not found."""
	if not InputMap.has_action(action_name):
		return -1
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			return event.physical_keycode
	return -1

func get_action_mouse_button(action_name: String) -> int:
	"""Get the mouse button index for an action. Returns -1 if not found."""
	if not InputMap.has_action(action_name):
		return -1
	for event in InputMap.action_get_events(action_name):
		if event is InputEventMouseButton:
			return event.button_index
	return -1

func get_action_events(action_name: String) -> Array[InputEvent]:
	"""Get all events for an action."""
	if not InputMap.has_action(action_name):
		return []
	return InputMap.action_get_events(action_name)

func rebind_key(action_name: String, new_keycode: int) -> void:
	"""Rebind an action to a new key. Removes all existing key events for that action and adds the new one."""
	if not InputMap.has_action(action_name):
		return

	# Remove all existing InputEventKey for this action
	var existing_events: Array = InputMap.action_get_events(action_name)
	for event in existing_events:
		if event is InputEventKey:
			InputMap.action_erase_event(action_name, event)

	# Add the new key event
	var new_event := InputEventKey.new()
	new_event.physical_keycode = new_keycode as Key
	InputMap.action_add_event(action_name, new_event)

	key_binding_changed.emit(action_name)
	_save_bindings()

func rebind_mouse(action_name: String, button_index: int) -> void:
	"""Rebind an action to a new mouse button."""
	if not InputMap.has_action(action_name):
		return

	# Remove all existing InputEventMouseButton for this action
	var existing_events: Array = InputMap.action_get_events(action_name)
	for event in existing_events:
		if event is InputEventMouseButton:
			InputMap.action_erase_event(action_name, event)

	# Add the new mouse button event
	var new_event := InputEventMouseButton.new()
	new_event.button_index = button_index as MouseButton
	InputMap.action_add_event(action_name, new_event)

	key_binding_changed.emit(action_name)
	_save_bindings()

func _save_bindings() -> void:
	"""Save current key bindings to a config file."""
	var config := ConfigFile.new()

	for action in ACTION_LABELS.keys():
		var events: Array[InputEvent] = get_action_events(action)
		var event_data: Array[Dictionary] = []
		for event in events:
			if event is InputEventKey:
				event_data.append({
					"type": "key",
					"physical_keycode": event.physical_keycode
				})
			elif event is InputEventMouseButton:
				event_data.append({
					"type": "mouse",
					"button_index": event.button_index
				})
		if not event_data.is_empty():
			config.set_value("bindings", action, event_data)

	config.save(BINDINGS_PATH)

func _load_bindings() -> void:
	"""Load custom key bindings from config file."""
	var config := ConfigFile.new()
	var err: Error = config.load(BINDINGS_PATH)
	if err != OK:
		return  # No custom bindings saved yet

	for action in ACTION_LABELS.keys():
		if not config.has_section_key("bindings", action):
			continue
		var event_data: Array = config.get_value("bindings", action, [])
		if event_data.is_empty():
			continue

		# Remove existing events for this action (except defaults we want to replace)
		var existing: Array = InputMap.action_get_events(action)
		for event in existing:
			if event is InputEventKey or event is InputEventMouseButton:
				InputMap.action_erase_event(action, event)

		# Add saved events
		for data in event_data:
			if data.get("type") == "key" and data.has("physical_keycode"):
				var ev := InputEventKey.new()
				ev.physical_keycode = data["physical_keycode"]
				InputMap.action_add_event(action, ev)
			elif data.get("type") == "mouse" and data.has("button_index"):
				var ev := InputEventMouseButton.new()
				ev.button_index = data["button_index"]
				InputMap.action_add_event(action, ev)

func reset_to_defaults() -> void:
	"""Reset all key bindings to defaults."""
	for action in ACTION_LABELS.keys():
		# Remove all events
		var events: Array = InputMap.action_get_events(action)
		for event in events:
			if event is InputEventKey or event is InputEventMouseButton:
				InputMap.action_erase_event(action, event)

		# Add default key
		if DEFAULT_KEYS.has(action):
			var ev := InputEventKey.new()
			ev.physical_keycode = DEFAULT_KEYS[action]
			InputMap.action_add_event(action, ev)

		# Add default mouse
		if DEFAULT_MOUSE.has(action):
			var ev := InputEventMouseButton.new()
			ev.button_index = DEFAULT_MOUSE[action]
			InputMap.action_add_event(action, ev)

		# Add secondary key
		if DEFAULT_KEY_SECONDARY.has(action):
			var ev := InputEventKey.new()
			ev.physical_keycode = DEFAULT_KEY_SECONDARY[action]
			InputMap.action_add_event(action, ev)

	# Delete saved bindings file
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists(BINDINGS_PATH.get_file()):
		dir.remove(BINDINGS_PATH.get_file())

	key_binding_changed.emit("")
