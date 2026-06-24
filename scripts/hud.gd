# scripts/hud.gd
extends CanvasLayer

# ─────────────────────────────────────────
# REFERENCIAS UI
# ─────────────────────────────────────────

@onready var health_label:       Label  = $MarginContainer/HUDLayout/TopRow/HealthLabel
@onready var ammo_label:         Label  = $MarginContainer/HUDLayout/TopRow/AmmoLabel
@onready var weapon_name_label:  Label  = $MarginContainer/HUDLayout/TopRow/WeaponNameLabel
@onready var spawn_timer_label:  Label  = $MarginContainer/HUDLayout/TopRow/SpawnTimerLabel
@onready var crosshair:          Label  = $Crosshair

# Boton ARMAS (Q) — se construye en _ready()
var _btn_armas: Button = null

# Panel selector de armas en partida
var _weapon_selector_panel: PanelContainer = null
var _weapon_list:           VBoxContainer  = null

# Referencia al spawner para pausar/reanudar
var _spawner: NpcSpawner = null

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func _ready() -> void:
	_build_boton_armas()
	_build_weapon_selector()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_toggle_weapon_selector()

# ─────────────────────────────────────────
# CONSTRUCCION DINAMICA — BOTON ARMAS
# ─────────────────────────────────────────

func _build_boton_armas() -> void:
	_btn_armas = Button.new()
	_btn_armas.text               = "ARMAS  [Q]"
	_btn_armas.custom_minimum_size = Vector2(130, 40)
	_btn_armas.add_theme_font_size_override("font_size", 16)
	_btn_armas.pressed.connect(_toggle_weapon_selector)

	# Intentar agregarlo al TopRow si existe; si no, al root del HUD
	var top_row: Node = get_node_or_null("MarginContainer/HUDLayout/TopRow")
	if top_row:
		top_row.add_child(_btn_armas)
	else:
		add_child(_btn_armas)
		_btn_armas.position = Vector2(10, 10)

# ─────────────────────────────────────────
# CONSTRUCCION DINAMICA — SELECTOR DE ARMAS
# ─────────────────────────────────────────

func _build_weapon_selector() -> void:
	_weapon_selector_panel = PanelContainer.new()
	_weapon_selector_panel.visible = false
	# Centrar en pantalla
	_weapon_selector_panel.set_anchors_preset(Control.PRESET_CENTER)
	_weapon_selector_panel.custom_minimum_size = Vector2(280, 0)
	add_child(_weapon_selector_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	_weapon_selector_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Titulo
	var titulo := Label.new()
	titulo.text = "Seleccionar Arma"
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(titulo)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Lista scrollable de armas
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 4)
	_weapon_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_weapon_list)

	# Boton cerrar
	var btn_cerrar := Button.new()
	btn_cerrar.text = "Cerrar  [Q]"
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
		# Encabezado de categoria
		var lbl_cat := Label.new()
		lbl_cat.text = "── " + categoria + " ──"
		lbl_cat.add_theme_font_size_override("font_size", 13)
		lbl_cat.modulate = Color(0.75, 0.75, 0.75)
		_weapon_list.add_child(lbl_cat)

		for nombre_arma in armas_raw[categoria].keys():
			var btn := Button.new()
			btn.text                    = nombre_arma
			btn.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size     = Vector2(0, 36)
			btn.add_theme_font_size_override("font_size", 17)
			btn.alignment               = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_on_arma_seleccionada.bind(nombre_arma))
			_weapon_list.add_child(btn)

# ─────────────────────────────────────────
# LOGICA DEL SELECTOR EN PARTIDA
# ─────────────────────────────────────────

func _toggle_weapon_selector() -> void:
	if not is_instance_valid(_weapon_selector_panel):
		return
	var abrir: bool = not _weapon_selector_panel.visible
	_weapon_selector_panel.visible = abrir

	# Pausar / reanudar spawn
	_get_spawner()
	if _spawner:
		if abrir:
			_spawner.pausar_spawn()
		else:
			_spawner.reanudar_spawn()

	# Pausar movimiento del jugador y liberar cursor
	if abrir:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_arma_seleccionada(nombre_arma: String) -> void:
	# Cambiar arma al jugador en tiempo real
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and player.has_method("cambiar_arma"):
		player.cambiar_arma(nombre_arma)

	# Cerrar el panel
	_weapon_selector_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Reanudar spawn
	_get_spawner()
	if _spawner:
		_spawner.reanudar_spawn()

func _get_spawner() -> void:
	if _spawner and is_instance_valid(_spawner):
		return
	var spawners: Array = get_tree().get_nodes_in_group("spawner")
	if not spawners.is_empty():
		_spawner = spawners[0] as NpcSpawner
	else:
		# Buscar por clase directamente si no tiene grupo
		for node in get_tree().get_nodes_in_group("npc"):
			pass  # fallback: se encontrara via get_tree si el spawner usa add_to_group
		var root: Node = get_tree().current_scene
		if root:
			for child in root.get_children():
				if child is NpcSpawner:
					_spawner = child
					break

# ─────────────────────────────────────────
# API PUBLICA — actualizaciones de datos
# ─────────────────────────────────────────

func update_health(current: float, maximum: float) -> void:
	if health_label:
		health_label.text = "HP: %d / %d" % [int(current), int(maximum)]

func update_ammo(current_ammo: int, max_ammo: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [current_ammo, max_ammo]

func update_weapon_name(wname: String) -> void:
	if weapon_name_label:
		weapon_name_label.text = wname

func update_spawn_timer(time_left: float) -> void:
	if spawn_timer_label:
		spawn_timer_label.text = "Spawn: %.1fs" % time_left
