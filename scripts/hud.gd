extends CanvasLayer

# ─────────────────────────────────────────
# REFERENCIAS UI — paths reales de hud.tscn
# ─────────────────────────────────────────

@onready var spawn_label: Label = $HUD/MarginContainer/VBox/SpawnLabel
@onready var weapon_label: Label = $HUD/MarginContainer/VBox/AmmoContainer/WeaponLabel
@onready var ammo_label: Label = $HUD/MarginContainer/VBox/AmmoContainer/AmmoLabel
@onready var health_bar: ProgressBar = $HUD/MarginContainer/VBox/HealthBar
@onready var health_text: Label = $HUD/MarginContainer/VBox/HealthBar/Label
@onready var crosshair: TextureRect = $HUD/Crosshair
@onready var dev_menu: Control = $DevMenu
@onready var pause_screen: Control = $PauseScreen
@onready var death_screen: Control = $DeathScreen

var _weapon_selector_panel: PanelContainer = null
var _weapon_list: VBoxContainer = null
var _spawner: NpcSpawner = null
var _player: Player = null
var _menu_abierto: bool = false

func _ready() -> void:
	_build_weapon_selector()
	_conectar_player()
	_configurar_pausa()

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
	if _player.active_weapon:
		_on_player_weapon_changed(_player.active_weapon.weapon_name, _player.active_weapon.ammo_in_mag, _player.active_weapon.reserve_ammo)

func _configurar_pausa() -> void:
	var btn_continuar: Button = get_node_or_null("PauseScreen/Buttons/BtnContinuar")
	var btn_menu: Button = get_node_or_null("PauseScreen/Buttons/BtnMenu")
	if btn_continuar and not btn_continuar.pressed.is_connected(_on_btn_continuar_pressed):
		btn_continuar.pressed.connect(_on_btn_continuar_pressed)
	if btn_menu and not btn_menu.pressed.is_connected(_on_btn_menu_pressed):
		btn_menu.pressed.connect(_on_btn_menu_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_toggle_cursor_manual()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Q:
			if _weapon_selector_panel and _weapon_selector_panel.visible:
				_toggle_weapon_selector()
				get_viewport().set_input_as_handled()
				return
			if dev_menu and dev_menu.visible:
				dev_menu.toggle_menu()
				_menu_abierto = false
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				abrir_selector_armas()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
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
	if _weapon_selector_panel and _weapon_selector_panel.visible:
		_toggle_weapon_selector()
		return
	if dev_menu and dev_menu.visible:
		dev_menu.toggle_menu()
		_menu_abierto = false
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
	return (pause_screen and pause_screen.visible) or (death_screen and death_screen.visible) or (dev_menu and dev_menu.visible) or (_weapon_selector_panel and _weapon_selector_panel.visible)

func _build_weapon_selector() -> void:
	_weapon_selector_panel = PanelContainer.new()
	_weapon_selector_panel.visible = false
	_weapon_selector_panel.set_anchors_preset(Control.PRESET_CENTER)
	_weapon_selector_panel.custom_minimum_size = Vector2(300, 0)
	_weapon_selector_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_weapon_selector_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_weapon_selector_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	_weapon_selector_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	var titulo := Label.new()
	titulo.text = "Seleccionar Arma"
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(titulo)
	var sep := HSeparator.new()
	vbox.add_child(sep)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 4)
	_weapon_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_weapon_list)
	var btn_cerrar := Button.new()
	btn_cerrar.text = "Cerrar [Q]"
	btn_cerrar.add_theme_font_size_override("font_size", 15)
	btn_cerrar.pressed.connect(_toggle_weapon_selector)
	vbox.add_child(btn_cerrar)
	_poblar_lista_armas()

func _poblar_lista_armas() -> void:
	if not is_instance_valid(_weapon_list):
		return
	for child in _weapon_list.get_children():
		child.queue_free()
	var armas_raw: Dictionary = {}
	if ConfigManager and ConfigManager._data.has("Armas"):
		armas_raw = ConfigManager._data["Armas"]
	for categoria in armas_raw.keys():
		var lbl_cat := Label.new()
		lbl_cat.text = "── " + categoria + " ──"
		lbl_cat.add_theme_font_size_override("font_size", 13)
		lbl_cat.modulate = Color(0.75, 0.75, 0.75)
		_weapon_list.add_child(lbl_cat)
		for nombre_arma in armas_raw[categoria].keys():
			var btn := Button.new()
			btn.text = nombre_arma
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 36)
			btn.add_theme_font_size_override("font_size", 17)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_on_arma_seleccionada.bind(nombre_arma))
			_weapon_list.add_child(btn)

func abrir_selector_armas() -> void:
	if not is_instance_valid(_weapon_selector_panel):
		return
	_poblar_lista_armas()
	_weapon_selector_panel.visible = true
	_menu_abierto = true
	_get_spawner()
	if _spawner:
		_spawner.pausar_spawn()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _toggle_weapon_selector() -> void:
	if not is_instance_valid(_weapon_selector_panel):
		return
	var abrir: bool = not _weapon_selector_panel.visible
	_weapon_selector_panel.visible = abrir
	_menu_abierto = abrir
	_get_spawner()
	if _spawner:
		if abrir:
			_spawner.pausar_spawn()
		else:
			_spawner.reanudar_spawn()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if abrir else Input.MOUSE_MODE_CAPTURED

func _on_arma_seleccionada(nombre_arma: String) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and player.has_method("cambiar_arma"):
		player.cambiar_arma(nombre_arma)
	_weapon_selector_panel.visible = false
	_menu_abierto = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_get_spawner()
	if _spawner:
		_spawner.reanudar_spawn()

func _get_spawner() -> void:
	if _spawner and is_instance_valid(_spawner):
		return
	var spawners: Array = get_tree().get_nodes_in_group("spawner")
	if not spawners.is_empty():
		_spawner = spawners[0] as NpcSpawner
		return
	var root: Node = get_tree().current_scene
	if root:
		for child in root.get_children():
			if child is NpcSpawner:
				_spawner = child
				break

func _on_player_weapon_changed(weapon_name: String, current_ammo: int, max_ammo: int) -> void:
	update_weapon_name(weapon_name)
	update_ammo(current_ammo, max_ammo)

func _on_player_died() -> void:
	if death_screen:
		death_screen.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
