# scripts/options_menu.gd
# Ventana de Opciones con pestanas: Partida, Audio, Video, Teclas
extends Control
class_name OptionsMenu

signal closed()

# ── Referencias a nodos ──────────────────────────────────────────────
@onready var tab_container: TabContainer = $BgPanel/Panel/VBoxContainer/TabContainer

# Partida
@onready var partida_grid: GridContainer = $BgPanel/Panel/VBoxContainer/TabContainer/Partida/Margin/VBox/Grid
@onready var btn_team_info: Button = $BgPanel/Panel/VBoxContainer/TabContainer/Partida/Margin/VBox/BtnTeamInfo
@onready var btn_restart: Button = $BgPanel/Panel/VBoxContainer/TabContainer/Partida/Margin/VBox/BtnRestart

# Audio
@onready var master_slider: HSlider = $BgPanel/Panel/VBoxContainer/TabContainer/Audio/Margin/VBox/MasterSlider
@onready var master_label: Label = $BgPanel/Panel/VBoxContainer/TabContainer/Audio/Margin/VBox/MasterLabel

# Video
@onready var resolution_option: OptionButton = $BgPanel/Panel/VBoxContainer/TabContainer/Video/Margin/VBox/ResolutionOption
@onready var fullscreen_check: CheckButton = $BgPanel/Panel/VBoxContainer/TabContainer/Video/Margin/VBox/FullscreenCheck

# Teclas
@onready var teclas_grid: GridContainer = $BgPanel/Panel/VBoxContainer/TabContainer/Teclas/Margin/VBox/ScrollContainer/Grid

# Mouse
@onready var mouse_sensitivity_slider: HSlider = $BgPanel/Panel/VBoxContainer/TabContainer/Mouse/Margin/VBox/SensitivitySlider
@onready var mouse_sensitivity_label: Label = $BgPanel/Panel/VBoxContainer/TabContainer/Mouse/Margin/VBox/SensitivityLabel
@onready var mouse_invert_y_check: CheckButton = $BgPanel/Panel/VBoxContainer/TabContainer/Mouse/Margin/VBox/InvertYCheck

# ── Variables ─────────────────────────────────────────────────────────
var _waiting_for_key: String = ""
var _team_buttons: Array[Button] = []

# Formatos de resolucion disponibles
var _resolutions: Array[Vector2i] = [
	Vector2i(640, 480),
	Vector2i(800, 600),
	Vector2i(1024, 768),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_partida()
	_setup_audio()
	_setup_video()
	_setup_teclas()
	_setup_mouse()
	_setup_buttons()

func _setup_buttons() -> void:
	var btn_cerrar: Button = $BgPanel/Panel/VBoxContainer/BtnCerrar
	if btn_cerrar:
		btn_cerrar.pressed.connect(_on_close_pressed)

func _on_close_pressed() -> void:
	visible = false
	closed.emit()

# ═══════════════════════════════════════════════════════════════════════
# PARTIDA
# ═══════════════════════════════════════════════════════════════════════

func _setup_partida() -> void:
	if not partida_grid:
		return
	# Botones de equipo en el grid
	_team_buttons.clear()
	for child in partida_grid.get_children():
		child.queue_free()

	var equipos: Array[int] = [int(Enums.Equipo.AZUL), int(Enums.Equipo.ROJO), int(Enums.Equipo.AMARILLO), int(Enums.Equipo.VERDE)]
	for id in equipos:
		var btn := Button.new()
		btn.text = GameState.nombre_equipo(id)
		btn.custom_minimum_size = Vector2(120, 40)
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", GameState.color_equipo(id))
		btn.pressed.connect(_on_team_selected.bind(id))
		partida_grid.add_child(btn)
		_team_buttons.append(btn)

	# Actualizar label de equipo actual
	_update_team_info()

	# Boton reiniciar
	if btn_restart:
		btn_restart.pressed.connect(_on_restart_pressed)

func _update_team_info() -> void:
	if btn_team_info and is_instance_valid(btn_team_info):
		btn_team_info.text = "Equipo actual: %s" % GameState.nombre_equipo(GameState.player_team)
		btn_team_info.add_theme_color_override("font_color", GameState.color_equipo(GameState.player_team))

func _on_team_selected(team_id: int) -> void:
	# Usar el sistema unificado de cambio de equipo del MatchManager
	if is_instance_valid(MatchManager) and MatchManager.is_match_started():
		if is_instance_valid(MatchManager.player):
			MatchManager.cambiar_equipo_jugador(team_id)
		else:
			push_warning("[OptionsMenu] No hay jugador para cambiar de equipo")
	else:
		# Si la partida no ha empezado, cambiar directamente (escena menu)
		GameState.player_team = team_id
	_update_team_info()
	# Re-evaluar enemigos de los NPCs
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc is NpcBase:
			npc._re_evaluar_enemigos()

func _on_restart_pressed() -> void:
	visible = false
	get_tree().paused = false
	get_tree().reload_current_scene()

# ═══════════════════════════════════════════════════════════════════════
# AUDIO
# ═══════════════════════════════════════════════════════════════════════

func _setup_audio() -> void:
	if master_slider and not master_slider.value_changed.is_connected(_on_volume_changed):
		master_slider.value_changed.connect(_on_volume_changed)
	_audio_refresh()

func _audio_refresh() -> void:
	if master_slider:
		var current_volume: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
		master_slider.value = current_volume
		_update_volume_label(current_volume)

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), value)
	_update_volume_label(value)

func _update_volume_label(value: float) -> void:
	if master_label:
		var percent: float = (value + 60.0) / 60.0 * 100.0
		percent = clamp(percent, 0.0, 100.0)
		master_label.text = "Volumen Maestro: %d%%" % percent

# ═══════════════════════════════════════════════════════════════════════
# VIDEO
# ═══════════════════════════════════════════════════════════════════════

func _setup_video() -> void:
	# Resolucion
	if resolution_option:
		resolution_option.clear()
		var current_size: Vector2i = DisplayServer.window_get_size()
		var selected_idx: int = 0
		for i in range(_resolutions.size()):
			var res: Vector2i = _resolutions[i]
			resolution_option.add_item("%d x %d" % [res.x, res.y], i)
			if res == current_size:
				selected_idx = i
		resolution_option.select(selected_idx)
		resolution_option.item_selected.connect(_on_resolution_selected)

	# Pantalla completa
	if fullscreen_check:
		fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)

func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < _resolutions.size():
		var res: Vector2i = _resolutions[index]
		DisplayServer.window_set_size(res)

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

# ═══════════════════════════════════════════════════════════════════════
# TECLAS (Key Binding)
# ═══════════════════════════════════════════════════════════════════════

func _setup_teclas() -> void:
	if not teclas_grid:
		return
	# Limpiar grid
	for child in teclas_grid.get_children():
		child.queue_free()

	teclas_grid.columns = 2

	var actions_to_bind: Array[String] = [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "shoot", "reload", "crouch",
		"pause_menu", "dev_menu"
	]

	for action in actions_to_bind:
		var label_text: String = InputManager.ACTION_LABELS.get(action, action)
		var lbl := Label.new()
		lbl.text = label_text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.custom_minimum_size = Vector2(180, 36)
		teclas_grid.add_child(lbl)

		var btn := Button.new()
		btn.name = "Btn_" + action
		btn.custom_minimum_size = Vector2(200, 36)
		btn.text = _get_key_display_name(action)
		btn.pressed.connect(_on_rebind_pressed.bind(action, btn))
		teclas_grid.add_child(btn)

	# Boton de restaurar defaults
	var separator := HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 10)
	teclas_grid.add_child(separator)
	var sep_dummy := HSeparator.new()
	sep_dummy.custom_minimum_size = Vector2(0, 10)
	sep_dummy.modulate = Color.TRANSPARENT
	teclas_grid.add_child(sep_dummy)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 0)
	teclas_grid.add_child(spacer)

	var btn_reset := Button.new()
	btn_reset.text = "Restaurar valores por defecto"
	btn_reset.custom_minimum_size = Vector2(200, 40)
	btn_reset.pressed.connect(_on_reset_bindings_pressed)
	teclas_grid.add_child(btn_reset)

func _get_key_display_name(action: String) -> String:
	var events: Array[InputEvent] = InputManager.get_action_events(action)
	var names: Array[String] = []
	for ev in events:
		if ev is InputEventKey:
			names.append(OS.get_keycode_string(ev.physical_keycode))
		elif ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT:
					names.append("Click Izquierdo")
				MOUSE_BUTTON_RIGHT:
					names.append("Click Derecho")
				MOUSE_BUTTON_MIDDLE:
					names.append("Click Medio")
				_:
					names.append("Boton %d" % ev.button_index)
	return ", ".join(names) if not names.is_empty() else "[Sin asignar]"

func _on_rebind_pressed(action: String, btn: Button) -> void:
	if _waiting_for_key != "":
		return  # Ya estamos esperando una tecla

	_waiting_for_key = action
	btn.text = "Presiona una tecla..."
	btn.disabled = true

	# Usar _input_root para capturar la siguiente tecla
	# Necesitamos que el nodo procese input aunque el menu este abierto
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if _waiting_for_key == "":
		return

	if event is InputEventKey and event.pressed:
		var action = _waiting_for_key
		_waiting_for_key = ""

		var keycode: int = event.physical_keycode
		if keycode == 0:
			keycode = event.keycode
		if keycode == 0:
			set_process_input(false)
			return

		InputManager.rebind_key(action, keycode)
		_refresh_teclas()
		get_viewport().set_input_as_handled()
		set_process_input(false)

	elif event is InputEventMouseButton and event.pressed:
		var action = _waiting_for_key
		_waiting_for_key = ""

		if action == "shoot":
			InputManager.rebind_mouse(action, event.button_index)
		else:
			# Solo permitir bindear mouse a la accion de disparo (movimiento, etc.)
			# Cancelar el bindeo - restaurar texto
			pass
		_refresh_teclas()
		get_viewport().set_input_as_handled()
		set_process_input(false)

func _refresh_teclas() -> void:
	# Actualizar textos de todos los botones de teclas
	var actions_to_bind: Array[String] = [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "shoot", "reload", "crouch",
		"pause_menu", "dev_menu"
	]
	for action in actions_to_bind:
		var btn: Button = get_node_or_null("BgPanel/Panel/VBoxContainer/TabContainer/Teclas/Margin/VBox/ScrollContainer/Grid/Btn_" + action)
		if btn:
			btn.text = _get_key_display_name(action)
			btn.disabled = false

func _on_reset_bindings_pressed() -> void:
	InputManager.reset_to_defaults()
	_refresh_teclas()

# ═══════════════════════════════════════════════════════════════════════
# MOUSE
# ═══════════════════════════════════════════════════════════════════════

func _setup_mouse() -> void:
	if mouse_sensitivity_slider and not mouse_sensitivity_slider.value_changed.is_connected(_on_sensitivity_changed):
		mouse_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	if mouse_invert_y_check and not mouse_invert_y_check.toggled.is_connected(_on_invert_y_toggled):
		mouse_invert_y_check.toggled.connect(_on_invert_y_toggled)
	_mouse_refresh()

func _mouse_refresh() -> void:
	if mouse_sensitivity_slider:
		mouse_sensitivity_slider.value = GameState.mouse_sensitivity
		_update_sensitivity_label(GameState.mouse_sensitivity)
	if mouse_invert_y_check:
		mouse_invert_y_check.button_pressed = GameState.mouse_invert_y

func _on_sensitivity_changed(value: float) -> void:
	GameState.mouse_sensitivity = value
	GameState.save_mouse_settings()
	_update_sensitivity_label(value)

func _update_sensitivity_label(value: float) -> void:
	if mouse_sensitivity_label:
		mouse_sensitivity_label.text = "Sensibilidad: %.4f" % value

func _on_invert_y_toggled(toggled_on: bool) -> void:
	GameState.mouse_invert_y = toggled_on
	GameState.save_mouse_settings()

func toggle() -> void:
	visible = not visible
	if visible:
		# Refrescar datos al abrir
		_update_team_info()
		_audio_refresh()
		_mouse_refresh()
		_highlight_current_team()
		move_to_front()
	else:
		if _waiting_for_key != "":
			_waiting_for_key = ""
			set_process_input(false)
			_refresh_teclas()

func _highlight_current_team() -> void:
	# Actualizar colores de botones de equipo
	for btn in _team_buttons:
		if not is_instance_valid(btn):
			continue
		var id: int = -1
		# Buscar el id por el texto
		for team_id in GameState.NOMBRE_EQUIPO.keys():
			if GameState.nombre_equipo(team_id) == btn.text:
				id = team_id
				break
		if id >= 0:
			if id == GameState.player_team:
				btn.add_theme_stylebox_override("normal", _get_selected_style())
			else:
				btn.remove_theme_stylebox_override("normal")
				btn.add_theme_color_override("font_color", GameState.color_equipo(id))

func _get_selected_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.4, 0.2)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 1.0, 0.5)
	return style
