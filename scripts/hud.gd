extends CanvasLayer

# ─────────────────────────────────────────
# REFERENCIAS UI — paths reales de hud.tscn
# ─────────────────────────────────────────

@onready var spawn_label:  Label       = $HUD/MarginContainer/VBox/SpawnLabel
@onready var weapon_label: Label       = $HUD/MarginContainer/VBox/AmmoContainer/WeaponLabel
@onready var ammo_label:   Label       = $HUD/MarginContainer/VBox/AmmoContainer/AmmoLabel
@onready var health_bar:   ProgressBar = $HUD/MarginContainer/VBox/HealthBar
@onready var health_text:  Label       = $HUD/MarginContainer/VBox/HealthBar/Label
@onready var crosshair:    TextureRect = $HUD/Crosshair
@onready var dev_menu:     Control     = $DevMenu
@onready var pause_screen: Control     = $PauseScreen
@onready var death_screen: Control     = $DeathScreen
@onready var options_menu: Control     = $OptionsMenu

# Core HP bars (en el HUD, parte superior)
@onready var core_blue_bar:  ProgressBar = $CoreBars/BlueCoreBar
@onready var core_blue_text: Label       = $CoreBars/BlueCoreBar/Label
@onready var core_red_bar:   ProgressBar = $CoreBars/RedCoreBar
@onready var core_red_text:  Label       = $CoreBars/RedCoreBar/Label

# Match result overlay
@onready var match_over:    Control = $MatchOver
@onready var match_result:  Label   = $MatchOver/Label
@onready var match_sub:     Label   = $MatchOver/SubLabel

var _player:       Player     = null
var _menu_abierto: bool       = false

func _ready() -> void:
	# FIX: registrar en grupo para que spawner.gd pueda encontrarlo con get_nodes_in_group("hud")
	add_to_group("hud")
	_conectar_player()
	_configurar_pausa()
	_configurar_death_screen()
	_conectar_core_hud()
	_conectar_match_end()
	_configurar_match_over_buttons()

func _conectar_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if not _player:
		return
	if not _player.health_changed.is_connected(update_health):
		_player.health_changed.connect(update_health)
	if not _player.weapon_changed.is_connected(_on_player_weapon_changed):
		_player.weapon_changed.connect(_on_player_weapon_changed)
	if not _player.ammo_changed.is_connected(update_ammo):
		_player.ammo_changed.connect(update_ammo)
	if not _player.player_died.is_connected(_on_player_died):
		_player.player_died.connect(_on_player_died)
	update_health(_player.current_health, _player.max_health)

func _configurar_pausa() -> void:
	var btn_continuar: Button = get_node_or_null("PauseScreen/Buttons/BtnContinuar")
	var btn_menu:      Button = get_node_or_null("PauseScreen/Buttons/BtnMenu")
	var btn_options:   Button = get_node_or_null("PauseScreen/Buttons/BtnOptions")
	if btn_continuar and not btn_continuar.pressed.is_connected(_on_btn_continuar_pressed):
		btn_continuar.pressed.connect(_on_btn_continuar_pressed)
	if btn_menu and not btn_menu.pressed.is_connected(_on_btn_menu_pressed):
		btn_menu.pressed.connect(_on_btn_menu_pressed)
	if btn_options and not btn_options.pressed.is_connected(_on_btn_options_pressed):
		btn_options.pressed.connect(_on_btn_options_pressed)
	if options_menu and not options_menu.is_connected("closed", _on_options_closed):
		options_menu.closed.connect(_on_options_closed)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.is_action("dev_menu"):
		if dev_menu:
			dev_menu.toggle_menu()
			_menu_abierto = dev_menu.visible
		get_viewport().set_input_as_handled()
	elif event.is_action("pause_menu"):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_cursor_manual() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if not _esta_una_ui_abierta():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle_pause() -> void:
	if death_screen and death_screen.visible:
		return
	if dev_menu and dev_menu.visible:
		dev_menu.toggle_menu()
		_menu_abierto = false
		return
	if options_menu and options_menu.visible:
		options_menu.toggle()
		pause_screen.visible = true
		_menu_abierto = true
		return
	if not pause_screen:
		return
	pause_screen.visible = not pause_screen.visible
	_menu_abierto = pause_screen.visible
	if pause_screen.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
		process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _esta_una_ui_abierta() -> bool:
	return \
		(pause_screen and pause_screen.visible) or \
		(death_screen and death_screen.visible) or \
		(dev_menu and dev_menu.visible) or \
		(options_menu and options_menu.visible)

func _on_player_weapon_changed(weapon_name: String, current_ammo: int, max_ammo: int) -> void:
	update_weapon_name(weapon_name)
	update_ammo(current_ammo, max_ammo)

func _configurar_death_screen() -> void:
	var btn_reintentar: Button = get_node_or_null("DeathScreen/Buttons/BtnReintentar")
	var btn_menu:      Button = get_node_or_null("DeathScreen/Buttons/BtnMenu")
	if btn_reintentar and not btn_reintentar.pressed.is_connected(_on_btn_reintentar_pressed):
		btn_reintentar.pressed.connect(_on_btn_reintentar_pressed)
	if btn_menu and not btn_menu.pressed.is_connected(_on_btn_death_menu_pressed):
		btn_menu.pressed.connect(_on_btn_death_menu_pressed)

func _on_player_died() -> void:
	if death_screen:
		death_screen.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_btn_reintentar_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

func _on_btn_death_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_btn_options_pressed() -> void:
	"""Open the options menu from the pause screen."""
	if options_menu:
		pause_screen.visible = false
		options_menu.toggle()
		_menu_abierto = true

func _on_options_closed() -> void:
	"""When options menu is closed, go back to pause screen."""
	if options_menu:
		options_menu.visible = false
	pause_screen.visible = true
	_menu_abierto = true

func _on_btn_continuar_pressed() -> void:
	if pause_screen and pause_screen.visible:
		pause_screen.visible = false
		get_tree().paused = false
		_menu_abierto = false
		process_mode = Node.PROCESS_MODE_INHERIT
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_btn_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func update_health(current: float, maximum: float) -> void:
	if health_bar:
		health_bar.value = (current / maximum) * 100.0
	if health_text:
		health_text.text = "VIDA: %d / %d" % [int(current), int(maximum)]

func update_ammo(current_ammo: int, max_ammo: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [current_ammo, max_ammo]

func update_weapon_name(wname: String) -> void:
	if weapon_label:
		weapon_label.text = wname

func update_spawn_timer(time_left: float) -> void:
	if spawn_label:
		spawn_label.text = "Siguiente oleada en: %.1fs" % time_left

# ─────────────────────────────────────────
# CORE HUD — BARRAS DE VIDA SUPERIORES
# ─────────────────────────────────────────

func _conectar_core_hud() -> void:
	if not is_instance_valid(GameState):
		return
	if not GameState.core_health_changed.is_connected(_on_core_health_changed):
		GameState.core_health_changed.connect(_on_core_health_changed)

func _on_core_health_changed(team: int, current_hp: float, max_hp: float) -> void:
	match team:
		int(Enums.Equipo.AZUL):
			_update_core_bar(core_blue_bar, core_blue_text, current_hp, max_hp, "AZUL")
		int(Enums.Equipo.ROJO):
			_update_core_bar(core_red_bar, core_red_text, current_hp, max_hp, "ROJO")

func _update_core_bar(bar: ProgressBar, label: Label, current: float, max_val: float, team_name: String) -> void:
	if not bar or not label:
		return
	bar.value = (current / max_val) * 100.0
	label.text = "%d / %d" % [int(current), int(max_val)]
	
	# Cambiar color segun salud
	if current / max_val < 0.25:
		bar.modulate = Color(1.0, 0.2, 0.2)  # Rojo critico
	elif current / max_val < 0.5:
		bar.modulate = Color(1.0, 0.7, 0.1)  # Naranja
	else:
		match team_name:
			"AZUL": bar.modulate = Color(0.2, 0.5, 1.0)
			"ROJO": bar.modulate = Color(1.0, 0.2, 0.2)
			_: bar.modulate = Color.WHITE

# ─────────────────────────────────────────
# MATCH END — VICTORIA / DERROTA
# ─────────────────────────────────────────

func _conectar_match_end() -> void:
	if not is_instance_valid(GameState):
		return
	if not GameState.match_ended.is_connected(_on_match_ended):
		GameState.match_ended.connect(_on_match_ended)

func _configurar_match_over_buttons() -> void:
	var btn_reintentar: Button = get_node_or_null("MatchOver/BtnReintentar")
	var btn_menu: Button = get_node_or_null("MatchOver/BtnMenu")
	if btn_reintentar and not btn_reintentar.pressed.is_connected(_on_btn_reintentar_pressed):
		btn_reintentar.pressed.connect(_on_btn_reintentar_pressed)
	if btn_menu and not btn_menu.pressed.is_connected(_on_btn_menu_pressed):
		btn_menu.pressed.connect(_on_btn_menu_pressed)

func _on_match_ended(winning_team: int) -> void:
	if not match_over:
		return
	
	var player_team: int = GameState.player_team
	var is_victory: bool = (winning_team >= 0 and winning_team == player_team)
	
	match_over.visible = true
	if is_victory:
		match_result.text = "VICTORIA"
		match_result.modulate = Color(0.2, 1.0, 0.2)
		match_sub.text = "¡Tu equipo ha destruido el Core enemigo!"
	else:
		match_result.text = "DERROTA"
		match_result.modulate = Color(1.0, 0.2, 0.2)
		match_sub.text = "El Core de tu equipo ha sido destruido."
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Re-conectar los botones por si la escena se recargo
	_configurar_match_over_buttons()
	
	_debug("[HUD] Partida terminada. Ganador: %d | Victoria: %s" % [winning_team, str(is_victory)])

func _debug(msg: String) -> void:
	print(msg)
