extends CanvasLayer

# ─────────────────────────────────────────
# REFERENCIAS UI — paths reales de hud.tscn
# ─────────────────────────────────────────

@onready var spawn_label:  Label       = $HUD/MarginContainer/VBox/SpawnLabel
@onready var weapon_label:    Label       = $HUD/MarginContainer/VBox/AmmoContainer/WeaponLabel
@onready var ammo_label:      Label       = $HUD/MarginContainer/VBox/AmmoContainer/AmmoLabel
@onready var ammo_type_label: Label       = $HUD/MarginContainer/VBox/AmmoTypeLabel
@onready var health_bar:   ProgressBar = $HUD/MarginContainer/VBox/HealthBar
@onready var health_text:  Label       = $HUD/MarginContainer/VBox/HealthBar/Label
@onready var crosshair:          TextureRect = $HUD/Crosshair
@onready var weapon_crosshair:   TextureRect = $HUD/WeaponCrosshair  # Fase 2
@onready var dev_menu:     Control     = $DevMenu
@onready var pause_screen: Control     = $PauseScreen
@onready var death_screen: Control     = $DeathScreen
@onready var options_menu: Control     = $OptionsMenu
@onready var scoreboard:   Control     = $Scoreboard

# Weapon pickup prompt
@onready var weapon_prompt:       Control = $WeaponPrompt
@onready var prompt_label:        Label   = $WeaponPrompt/PromptLabel
@onready var replace_label:       Label   = $WeaponPrompt/ReplaceLabel

# Core HP bars (en el HUD, parte superior)
@onready var core_blue_bar:  ProgressBar = $CoreBars/BlueCoreBar
@onready var core_blue_text: Label       = $CoreBars/BlueCoreBar/Label
@onready var core_red_bar:   ProgressBar = $CoreBars/RedCoreBar
@onready var core_red_text:  Label       = $CoreBars/RedCoreBar/Label

# Match result overlay
@onready var match_over:    Control = $MatchOver
@onready var match_result:  Label   = $MatchOver/Label
@onready var match_sub:     Label   = $MatchOver/SubLabel

# Auto Balance label (parte superior central)
@onready var auto_balance_label: Label = $AutoBalanceLabel

# Step-up 2 indicator (↑)
@onready var step_up_indicator: Label = $StepUpIndicator
@onready var camera_toggle_btn: Button = $CameraToggleBtn

# Weapon equip state indicator (Fase 5)
@onready var weapon_state_label: Label = $HUD/MarginContainer/VBox/WeaponStateLabel

var _player:       Player     = null
var _menu_abierto: bool       = false
## Hasta cuándo (ms) mostrar el toast de campaña ([C] para seguir a aliados).
var _story_toast_until: float = 0.0

# ── Menú de órdenes de aliado (campaign, [E] sobre un Tirador) ──
var _npc_menu_ui: Control = null
var _npc_menu_title: Label = null
var _npc_menu_buttons: Array[Button] = []
var _npc_menu_options: Array[String] = ["libre", "guard", "follow"]
var _npc_menu_target: Node = null

func _ready() -> void:
	# FIX: registrar en grupo para que spawner.gd pueda encontrarlo con get_nodes_in_group("hud")
	add_to_group("hud")
	_build_npc_command_menu()
	_apply_story_presentation()
	# ── Step-up 2 indicator: asegurar que empieza OCULTO ──
	if step_up_indicator:
		step_up_indicator.visible = false
	_conectar_player()
	_configurar_pausa()
	_configurar_death_screen()
	if not _is_story_mode():
		_conectar_core_hud()
		_conectar_auto_balance()
		_conectar_match_end()
		_configurar_match_over_buttons()
	# Botón de toggle cámara (conexión única, _ready solo corre una vez)
	if camera_toggle_btn and not camera_toggle_btn.pressed.is_connected(_on_camera_toggle_pressed):
		camera_toggle_btn.pressed.connect(_on_camera_toggle_pressed)

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
	# Conectar al sistema de respawn unificado del MatchManager solo en MP.
	if not _is_story_mode() and is_instance_valid(MatchManager):
		if not MatchManager.player_respawned.is_connected(_on_player_respawned):
			MatchManager.player_respawned.connect(_on_player_respawned)
	# ── Step-up 2 indicator ──
	if not _player.vault_availability_changed.is_connected(_on_vault_availability_changed):
		_player.vault_availability_changed.connect(_on_vault_availability_changed)
	# ── ADS toggle (Fase 2) ──
	if not _player.ads_changed.is_connected(_on_player_ads_changed):
		_player.ads_changed.connect(_on_player_ads_changed)
	# ── Camera mode toggle ──
	if not _player.camera_mode_changed.is_connected(_on_camera_mode_changed):
		_player.camera_mode_changed.connect(_on_camera_mode_changed)
	# Sincronizar estado inicial del botón
	if is_instance_valid(camera_toggle_btn):
		_on_camera_mode_changed(_player.is_third_person)
	update_health(_player.current_health, _player.max_health)
	# Conectar estado de equipamiento de arma (Fase 5)
	_conectar_weapon_equip_state()

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

func _process(_delta: float) -> void:
	# Actualizar posición del crosshair del arma (Fase 2)
	_update_weapon_crosshair()
	_hide_story_toast_if_due()

	# Manejo de Scoreboard (solo multijugador).
	if _is_story_mode():
		if scoreboard != null and scoreboard.visible:
			scoreboard.hide_scoreboard()
		# En modo Historia el scoreboard no aplica: [C] ordena a todos los
		# aliados seguir al jugador (toggle). [Tab] es intercambio de armas.
		if Input.is_action_just_pressed("follow_all"):
			_toggle_ally_follow()
		return
	if not _menu_abierto and not get_tree().paused:
		if Input.is_action_pressed("scoreboard"):
			if scoreboard and not scoreboard.visible:
				scoreboard.show_scoreboard()
		else:
			if scoreboard and scoreboard.visible:
				scoreboard.hide_scoreboard()
	else:
		# Asegurar que el scoreboard se oculte si hay un menu abierto
		if scoreboard and scoreboard.visible:
			scoreboard.hide_scoreboard()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# ── Menú de órdenes de aliado (teclas rápidas 1/2/3, E/Esc para salir) ──
	if is_npc_command_menu_open():
		match event.physical_keycode:
			KEY_1:
				_apply_npc_command("libre")
			KEY_2:
				_apply_npc_command("guard")
			KEY_3:
				_apply_npc_command("follow")
			KEY_E, KEY_ESCAPE:
				_close_npc_command_menu()
		get_viewport().set_input_as_handled()
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
	update_ammo_type(weapon_name)

func _configurar_death_screen() -> void:
	var btn_menu: Button = get_node_or_null("DeathScreen/Buttons/BtnMenu")
	if btn_menu and not btn_menu.pressed.is_connected(_on_btn_death_menu_pressed):
		btn_menu.pressed.connect(_on_btn_death_menu_pressed)

func _on_player_died() -> void:
	if death_screen:
		death_screen.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var death_label: Label = get_node_or_null("DeathScreen/Label") as Label
		if death_label != null:
			death_label.text = "HAS MUERTO\nREAPARECIENDO..." if _is_story_mode() else "HAS MUERTO"
		var death_menu_button: Button = get_node_or_null("DeathScreen/Buttons/BtnMenu") as Button
		if death_menu_button != null:
			death_menu_button.visible = not _is_story_mode()
	# Ocultar indicador de step-up al morir
	if step_up_indicator:
		step_up_indicator.visible = false
	# Ocultar botón de cámara al morir
	if is_instance_valid(camera_toggle_btn):
		camera_toggle_btn.visible = false
	# El respawn automatico lo gestiona el MatchManager ahora.
	# La pantalla de muerte se ocultara cuando llegue la senal player_respawned.

## Restaura el HUD tras un checkpoint de Historia.
func story_player_respawned() -> void:
	if death_screen != null:
		death_screen.visible = false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(camera_toggle_btn):
		camera_toggle_btn.visible = true
	var death_menu_button: Button = get_node_or_null("DeathScreen/Buttons/BtnMenu") as Button
	if death_menu_button != null:
		death_menu_button.visible = true


func _on_player_respawned() -> void:
	"""El MatchManager respawneara al jugador y emitira esta senal."""
	if death_screen and death_screen.visible:
		death_screen.visible = false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Reconectar al jugador (pudo haber sido recreado en el respawn)
	_conectar_player()
	# Restaurar visibilidad del botón de cámara
	if is_instance_valid(camera_toggle_btn):
		camera_toggle_btn.visible = true

func _cleanup_match_state() -> void:
	"""Limpia el estado del modo que estaba activo antes de volver al menú."""
	if _is_story_mode():
		var story_state: Node = get_node_or_null("/root/GameStateSP")
		if story_state != null and story_state.has_method("reset_session"):
			story_state.call("reset_session")
		return
	if is_instance_valid(MatchManager):
		MatchManager.reset_match()
	if is_instance_valid(GameState):
		GameStateMP.reset_match()

func _on_btn_death_menu_pressed() -> void:
	get_tree().paused = false
	_cleanup_match_state()
	get_tree().change_scene_to_file("res://scenes/Compartido/main_menu.tscn")

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
	_cleanup_match_state()
	get_tree().change_scene_to_file("res://scenes/Compartido/main_menu.tscn")

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

func update_ammo_type(weapon_name: String) -> void:
	if not ammo_type_label:
		return
	if weapon_name.is_empty():
		ammo_type_label.text = ""
		return
	var datos: Dictionary = ConfigManager.get_arma(weapon_name)
	if datos.is_empty():
		ammo_type_label.text = ""
		return
	var categoria: String = datos.get("DisplayCategoria", datos.get("CategoriaMunicion", ""))
	var num_perdigones: int = datos.get("NumeroPerdigones", 1)
	var texto_tipo: String = _formatear_categoria_hud(categoria, num_perdigones)
	ammo_type_label.text = "Tipo: %s" % texto_tipo

## Convierte el codigo interno de CategoriaMunicion a texto legible para el HUD.
func _formatear_categoria_hud(categoria: String, num_perdigones: int = 1) -> String:
	match categoria:
		"bala":
			return "Bala"
		"perdigones":
			return "Perdigones (x%d)" % num_perdigones
		"arrojadiza":
			return "Arrojadiza"
		"explosiva":
			return "Explosiva"
		"plasma":
			return "Plasma"
		"cuerpo_a_cuerpo":
			return "Cuerpo a cuerpo"
		_:
			return categoria.capitalize()

## Actualiza el objetivo mostrado en Historia.
func set_story_objective(text: String) -> void:
	if spawn_label != null:
		spawn_label.text = "OBJETIVO: %s" % text
		spawn_label.visible = not text.is_empty()


## Mensaje temporal en pantalla para campaña (ej. aviso de "seguir a aliados").
## Reutiliza el label superior central que en Historia se oculta por defecto.
func show_story_toast(text: String) -> void:
	if auto_balance_label == null:
		return
	auto_balance_label.text = text
	auto_balance_label.visible = true
	_story_toast_until = Time.get_ticks_msec() + 3000


func _hide_story_toast_if_due() -> void:
	if _story_toast_until <= 0.0:
		return
	if auto_balance_label == null or not auto_balance_label.visible:
		return
	if Time.get_ticks_msec() >= _story_toast_until:
		auto_balance_label.visible = false
		_story_toast_until = 0.0


## [C] en modo Historia: ordena a TODOS los aliados seguir al jugador (toggle).
func _toggle_ally_follow() -> void:
	var controller: Node = get_tree().get_first_node_in_group(&"story_level_controller")
	if controller == null or not controller.has_method("toggle_ally_follow"):
		return
	controller.call("toggle_ally_follow")


# ═══ Menú de órdenes de aliado (campaña) ══════════════════════════════════
## Construye el menú radial (3 botones: Libre / Guardia / Sigueme). Se oculta
## hasta que el jugador pulsa [E] sobre un Tirador aliado.
func _build_npc_command_menu() -> void:
	if _npc_menu_ui != null:
		return
	_npc_menu_ui = Control.new()
	_npc_menu_ui.name = "NpcCommandMenu"
	var full := Control.PRESET_FULL_RECT
	_npc_menu_ui.set_anchors_preset(full)
	_npc_menu_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	_npc_menu_ui.visible = false
	add_child(_npc_menu_ui)
	# Fondo oscurecido
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.set_anchors_preset(full)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_npc_menu_ui.add_child(dim)
	# Título
	_npc_menu_title = Label.new()
	_npc_menu_title.name = "Title"
	_npc_menu_title.text = "ÓRDENES"
	_npc_menu_title.add_theme_font_size_override("font_size", 24)
	_npc_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_menu_ui.add_child(_npc_menu_title)
	# Botones (posiciones circulares se ajustan al abrir).
	var labels: Array[String] = ["1 · LIBRE", "2 · GUARDIA", "3 · SIGUEME"]
	for i in _npc_menu_options.size():
		var b := Button.new()
		b.text = labels[i]
		b.custom_minimum_size = Vector2(170, 46)
		b.size = Vector2(170, 46)
		b.pivot_offset = b.size * 0.5
		b.pressed.connect(_apply_npc_command.bind(_npc_menu_options[i]))
		_npc_menu_ui.add_child(b)
		_npc_menu_buttons.append(b)


## ¿El menú de órdenes de aliado está abierto?
func is_npc_command_menu_open() -> bool:
	return _npc_menu_ui != null and _npc_menu_ui.visible


## Abre el menú para el NPC indicado (ciclo del jugador).
func open_npc_command_menu(npc: Node) -> void:
	_npc_menu_target = npc
	if _npc_menu_ui == null:
		_build_npc_command_menu()
	if _npc_menu_target != null and _npc_menu_target.has_method("is_allied_with_player"):
		var nombre: String = str(_npc_menu_target.get("name"))
		_npc_menu_title.text = "ÓRDENES — %s" % nombre
	# Posicionar los 3 botones en círculo alrededor del centro.
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var radius: float = 150.0
	for i in _npc_menu_buttons.size():
		var angle: float = deg_to_rad(-90.0 + float(i) * 120.0)
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		var b: Button = _npc_menu_buttons[i]
		b.set_anchors_preset(Control.PRESET_TOP_LEFT)
		b.position = pos - b.size * 0.5
	_npc_menu_title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_npc_menu_title.size = Vector2(360, 40)
	_npc_menu_title.position = center - Vector2(180.0, 130.0)
	_npc_menu_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Cierra el menú y restaura la captura del ratón.
func _close_npc_command_menu() -> void:
	if _npc_menu_ui == null:
		return
	_npc_menu_ui.visible = false
	_npc_menu_target = null
	if not _esta_una_ui_abierta():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Aplica la orden seleccionada al NPC objetivo y cierra el menú.
func _apply_npc_command(mode: String) -> void:
	var npc: Node = _npc_menu_target
	_close_npc_command_menu()
	if npc == null or not is_instance_valid(npc):
		return
	if npc.has_method("apply_command_mode"):
		npc.call("apply_command_mode", mode)


func _is_story_mode() -> bool:
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state != null and story_state.has_method("is_story_active") and bool(story_state.call("is_story_active")):
		return true
	var current_scene: Node = get_tree().current_scene
	return current_scene != null and current_scene.get_node_or_null("StoryLevelController") != null


func _apply_story_presentation() -> void:
	if not _is_story_mode():
		return
	if core_blue_bar != null:
		core_blue_bar.get_parent().visible = false
	if auto_balance_label != null:
		auto_balance_label.visible = false
	if match_over != null:
		match_over.visible = false
	if scoreboard != null:
		scoreboard.visible = false


func update_spawn_timer(time_left: float) -> void:
	if spawn_label:
		spawn_label.text = "Siguiente oleada en: %.1fs" % time_left

# ─────────────────────────────────────────
# CORE HUD — BARRAS DE VIDA SUPERIORES
# ─────────────────────────────────────────

func _conectar_core_hud() -> void:
	if not is_instance_valid(GameState):
		return
	if not GameStateMP.core_health_changed.is_connected(_on_core_health_changed):
		GameStateMP.core_health_changed.connect(_on_core_health_changed)

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
# AUTO BALANCE — MENSAJE EN PANTALLA
# ─────────────────────────────────────────

func _conectar_auto_balance() -> void:
	if not is_instance_valid(MatchManager):
		return
	if not MatchManager.auto_balance_countdown.is_connected(_on_auto_balance_countdown):
		MatchManager.auto_balance_countdown.connect(_on_auto_balance_countdown)
	if not MatchManager.auto_balance_cancelled.is_connected(_on_auto_balance_cancelled):
		MatchManager.auto_balance_cancelled.connect(_on_auto_balance_cancelled)
	if not MatchManager.auto_balance_executed.is_connected(_on_auto_balance_executed):
		MatchManager.auto_balance_executed.connect(_on_auto_balance_executed)

func _on_auto_balance_countdown(time_left: int) -> void:
	if not auto_balance_label:
		return
	auto_balance_label.visible = true
	auto_balance_label.text = "Auto Balance en %d..." % time_left

func _on_auto_balance_cancelled() -> void:
	if auto_balance_label:
		auto_balance_label.visible = false

func _on_auto_balance_executed(_pawn: Node, _old_team: int, _new_team: int) -> void:
	if auto_balance_label:
		auto_balance_label.visible = false

# ─────────────────────────────────────────
# MATCH END — VICTORIA / DERROTA
# ─────────────────────────────────────────

func _conectar_match_end() -> void:
	if not is_instance_valid(GameState):
		return
	if not GameStateMP.match_ended.is_connected(_on_match_ended):
		GameStateMP.match_ended.connect(_on_match_ended)

func _configurar_match_over_buttons() -> void:
	var btn_menu: Button = get_node_or_null("MatchOver/BtnMenu")
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

# ─────────────────────────────────────────
# WEAPON PICKUP PROMPT
# ─────────────────────────────────────────

## Muestra el prompt de recogida de arma.
## new_weapon: nombre del arma en el suelo.
## current_weapon: nombre del arma actual (vacío si no tiene).
func show_weapon_prompt(new_weapon: String, current_weapon: String) -> void:
	if not weapon_prompt or not prompt_label or not replace_label:
		return
	
	if current_weapon != "":
		prompt_label.text = "Presiona E para recoger %s" % new_weapon
		replace_label.text = "(Reemplazará tu %s)" % current_weapon
		replace_label.visible = true
	else:
		prompt_label.text = "Presiona E para recoger %s" % new_weapon
		replace_label.visible = false
	
	weapon_prompt.visible = true

## Oculta el prompt de recogida de arma.
func hide_weapon_prompt() -> void:
	if weapon_prompt:
		weapon_prompt.visible = false

# ─────────────────────────────────────────
# STEP-UP 2 INDICATOR (Flecha ↑)
# ─────────────────────────────────────────

## Muestra/oculta el indicador de vault disponible.
func _on_vault_availability_changed(available: bool) -> void:
	if step_up_indicator:
		step_up_indicator.visible = available


# ─────────────────────────────────────────
# CAMERA MODE TOGGLE (1ra / 3ra Persona)
# ─────────────────────────────────────────

func _on_camera_toggle_pressed() -> void:
	"""Llamado al presionar el botón del HUD. Delega en Player."""
	if not _player or not is_instance_valid(_player):
		return
	if _player.is_dead:
		return
	_player.toggle_camera_mode()


func _on_camera_mode_changed(is_third_person: bool) -> void:
	"""Actualiza el texto del botón según el modo actual."""
	if not is_instance_valid(camera_toggle_btn):
		return
	camera_toggle_btn.text = "3ra Persona: ON" if is_third_person else "3ra Persona: OFF"


# ══════════════════════════════════════════════════════════════════
# ADS + WEAPON CROSSHAIR (Fase 2)
# ══════════════════════════════════════════════════════════════════

func _on_player_ads_changed(is_ads: bool) -> void:
	"""Actualiza visibilidad del crosshair del arma al cambiar ADS."""
	if not weapon_crosshair:
		return
	if not _player or not is_instance_valid(_player):
		weapon_crosshair.visible = false
		return
	# Al entrar en ADS: ocultar o atenuar el crosshair central
	if is_ads:
		# Atenuar el crosshair central durante ADS
		if crosshair:
			crosshair.modulate = Color(1, 1, 1, 0.2)
	else:
		# Restaurar crosshair central al salir de ADS
		if crosshair:
			crosshair.modulate = Color(1, 1, 1, 0.6)
		weapon_crosshair.visible = false


func _update_weapon_crosshair() -> void:
	"""Proyecta el punto de impacto del cañón del arma a la pantalla.
	Hace un raycast desde el cañón en su dirección forward y proyecta
	el punto de impacto. Más preciso que proyectar la posición del cañón.
	Solo se muestra durante ADS."""
	if not weapon_crosshair:
		return
	if not _player or not is_instance_valid(_player):
		weapon_crosshair.visible = false
		return
	if not _player.is_ads:
		weapon_crosshair.visible = false
		return
	
	var weapon: Weapon = _player.active_weapon
	if not weapon or not is_instance_valid(weapon):
		weapon_crosshair.visible = false
		return
	
	# Obtener la cámara activa (1P o 3P)
	var cam: Camera3D = _player.third_person_camera if _player.is_third_person else _player.camera
	if not cam:
		weapon_crosshair.visible = false
		return
	
	# ── Raycast desde el cañón en su dirección forward ──────────
	var muzzle_pos: Vector3 = weapon._get_muzzle_position()
	var muzzle_dir: Vector3 = -weapon.global_transform.basis.z  # Forward del arma
	var alcance: float = weapon.weapon_range if weapon.weapon_range > 0 else 100.0
	var end_pos: Vector3 = muzzle_pos + muzzle_dir * alcance
	
	var space_state: PhysicsDirectSpaceState3D = weapon.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, end_pos)
	# Excluir al Player y al arma para que el raycast no los detecte
	var exclude_rids: Array[RID] = []
	if _player and is_instance_valid(_player):
		exclude_rids.append(_player.get_rid())
	if is_instance_valid(weapon):
		_collect_weapon_rids(weapon, exclude_rids)
	query.exclude = exclude_rids
	
	var hit: Dictionary = space_state.intersect_ray(query)
	var target_point: Vector3 = hit.get("position", end_pos)
	
	# Proyectar el punto de impacto a coordenadas de pantalla
	var screen_pos: Vector2 = cam.unproject_position(target_point)
	
	# ── Zona segura: clampa el crosshair dentro del 80% de la pantalla (Fase 7) ──
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var margin_x: float = viewport_size.x * 0.1  # 10% de margen a cada lado
	var margin_y: float = viewport_size.y * 0.1  # 10% de margen arriba/abajo
	screen_pos.x = clamp(screen_pos.x, margin_x, viewport_size.x - margin_x)
	screen_pos.y = clamp(screen_pos.y, margin_y, viewport_size.y - margin_y)
	
	# Centrar el crosshair en el punto proyectado
	weapon_crosshair.position = screen_pos - weapon_crosshair.size * 0.5
	weapon_crosshair.visible = true


## Recolecta recursivamente RIDs de nodos de colisión del arma
## para excluirlos del raycast del crosshair.
func _collect_weapon_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	for child: Node in node.get_children():
		_collect_weapon_rids(child, rids)


# ══════════════════════════════════════════════════════════════════
# WEAPON EQUIP STATE (Fase 5)
# ══════════════════════════════════════════════════════════════════

func _conectar_weapon_equip_state() -> void:
	if not _player or not is_instance_valid(_player):
		return
	if not _player.weapon_equip_state:
		return
	if not _player.weapon_equip_state.equip_state_changed.is_connected(_on_weapon_equip_state_changed):
		_player.weapon_equip_state.equip_state_changed.connect(_on_weapon_equip_state_changed)
	# Sincronizar estado inicial
	_on_weapon_equip_state_changed(_player.weapon_equip_state.is_equipped)


func _on_weapon_equip_state_changed(is_now_equipped: bool) -> void:
	update_weapon_equip_state(is_now_equipped)
	_sync_crosshair_visibility(is_now_equipped)


## Actualiza el label de estado del arma en el HUD.
func update_weapon_equip_state(is_equipped: bool) -> void:
	if not weapon_state_label:
		return
	weapon_state_label.visible = true
	if is_equipped:
		weapon_state_label.text = "ARMA ACTIVA"
		weapon_state_label.modulate = Color(0.3, 1.0, 0.3, 1)  # Verde
	else:
		weapon_state_label.text = "ARMA GUARDADA"
		weapon_state_label.modulate = Color(1.0, 0.6, 0.2, 1)  # Naranja


## Muestra/oculta la mira según estado del arma.
func _sync_crosshair_visibility(is_equipped: bool) -> void:
	if crosshair:
		crosshair.visible = is_equipped
	# También ocultar el crosshair del arma si el arma no está equipada (Fase 2)
	if weapon_crosshair:
		weapon_crosshair.visible = false


func _debug(msg: String) -> void:
	print(msg)
