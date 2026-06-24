extends CanvasLayer

# ─────────────────────────────────────────
# REFERENCIAS UI — paths reales de hud.tscn
# ─────────────────────────────────────────

# HUD principal
@onready var spawn_label:       Label       = $HUD/MarginContainer/VBox/SpawnLabel
@onready var weapon_label:      Label       = $HUD/MarginContainer/VBox/AmmoContainer/WeaponLabel
@onready var ammo_label:        Label       = $HUD/MarginContainer/VBox/AmmoContainer/AmmoLabel
@onready var health_bar:        ProgressBar = $HUD/MarginContainer/VBox/HealthBar
@onready var health_text:       Label       = $HUD/MarginContainer/VBox/HealthBar/Label
@onready var crosshair:         TextureRect = $HUD/Crosshair

# DevMenu (Control hijo directo de HUDLayer)
@onready var dev_menu: Control = $DevMenu

# Panel selector de armas en partida (construido dinamicamente)
var _weapon_selector_panel: PanelContainer = null
var _weapon_list:           VBoxContainer  = null

# Referencia al spawner
var _spawner: NpcSpawner = null

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func _ready() -> void:
	_build_weapon_selector()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			# Si el selector de armas esta abierto, cerrarlo primero
			if _weapon_selector_panel and _weapon_selector_panel.visible:
				_toggle_weapon_selector()
				return
			# Abrir/cerrar DevMenu
			if dev_menu:
				dev_menu.toggle_menu()

# ─────────────────────────────────────────
# CONSTRUCCION DINAMICA — SELECTOR DE ARMAS
# ─────────────────────────────────────────

func _build_weapon_selector() -> void:
	_weapon_selector_panel = PanelContainer.new()
	_weapon_selector_panel.visible = false

	# Anclar al centro de pantalla con tamaNNo fijo para que nunca se escape
	_weapon_selector_panel.set_anchors_preset(Control.PRESET_CENTER)
	_weapon_selector_panel.custom_minimum_size = Vector2(300, 0)
	_weapon_selector_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_weapon_selector_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH

	# Agregar como hijo directo del CanvasLayer (mismo nivel que HUD)
	add_child(_weapon_selector_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_theme_constant_override("margin_left",   18)
	margin.add_theme_constant_override("margin_right",  18)
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

	# Lista scrollable con altura maxima controlada
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
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
		var lbl_cat := Label.new()
		lbl_cat.text = "── " + categoria + " ──"
		lbl_cat.add_theme_font_size_override("font_size", 13)
		lbl_cat.modulate = Color(0.75, 0.75, 0.75)
		_weapon_list.add_child(lbl_cat)

		for nombre_arma in armas_raw[categoria].keys():
			var btn := Button.new()
			btn.text                  = nombre_arma
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size   = Vector2(0, 36)
			btn.add_theme_font_size_override("font_size", 17)
			btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_on_arma_seleccionada.bind(nombre_arma))
			_weapon_list.add_child(btn)

# ─────────────────────────────────────────
# LOGICA DEL SELECTOR EN PARTIDA
# ─────────────────────────────────────────

func abrir_selector_armas() -> void:
	if not is_instance_valid(_weapon_selector_panel):
		return
	_poblar_lista_armas()
	_weapon_selector_panel.visible = true
	_get_spawner()
	if _spawner:
		_spawner.pausar_spawn()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _toggle_weapon_selector() -> void:
	if not is_instance_valid(_weapon_selector_panel):
		return
	var abrir: bool = not _weapon_selector_panel.visible
	_weapon_selector_panel.visible = abrir
	_get_spawner()
	if _spawner:
		if abrir:
			_spawner.pausar_spawn()
		else:
			_spawner.reanudar_spawn()
	if abrir:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_arma_seleccionada(nombre_arma: String) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and player.has_method("cambiar_arma"):
		player.cambiar_arma(nombre_arma)
	_weapon_selector_panel.visible = false
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

# ─────────────────────────────────────────
# API PUBLICA — actualizaciones de datos
# ─────────────────────────────────────────

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
