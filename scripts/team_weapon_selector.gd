# scripts/team_weapon_selector.gd
# Pantalla de seleccion de equipo + arma al iniciar la partida.
# Usa los IDs numericos de GameState.Equipo.
# NOTA: los .connect() de botones NO van aqui, ya estan conectados en la escena .tscn.
extends CanvasLayer

@onready var team_panel:    VBoxContainer = $TeamPanel
@onready var weapon_panel:  VBoxContainer = $WeaponPanel
@onready var btn_rojo:      Button        = $TeamPanel/BtnRojo
@onready var btn_azul:      Button        = $TeamPanel/BtnAzul
@onready var btn_volver:    Button        = $WeaponPanel/BtnVolver
@onready var btn_metralleta: Button       = $WeaponPanel/WeaponsRow/BtnMetralleta
@onready var btn_escopeta:   Button       = $WeaponPanel/WeaponsRow/BtnEscopeta
@onready var weapon_title:  Label         = $WeaponPanel/Title

var _armas_lista: Array[String]   = []
var _armas_buttons: Array[Button] = []
var _selected_team_id: int        = int(Enums.Equipo.ESPECTADOR)
var _scroll: ScrollContainer      = null
var _list:   VBoxContainer        = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	team_panel.visible   = true
	weapon_panel.visible = false
	_construir_lista()
	_poblar_armas()

func _construir_lista() -> void:
	var row: Node = get_node_or_null("WeaponPanel/WeaponsRow")
	if row:
		row.visible = false
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 340)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	weapon_panel.add_child(_scroll)
	weapon_panel.move_child(_scroll, weapon_panel.get_child_count() - 2)

func _poblar_armas() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	_armas_lista.clear()
	_armas_buttons.clear()
	var categorias: Array[String] = ["Pistolas", "Escopetas", "Subfusiles", "Rifles", "Francotiradores", "Melee"]
	var hay_armas: bool = false
	for categoria in categorias:
		var armas_cat: Array[String] = ConfigManager.get_nombres_armas(categoria)
		if armas_cat.is_empty():
			continue
		hay_armas = true
		var lbl := Label.new()
		lbl.text = "-- " + categoria + " --"
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.modulate = Color(0.75, 0.75, 0.75)
		_list.add_child(lbl)
		for nombre_arma in armas_cat:
			_armas_lista.append(nombre_arma)
			var btn := Button.new()
			btn.text = nombre_arma
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 38)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 17)
			btn.pressed.connect(_on_weapon_pressed.bind(nombre_arma))
			_list.add_child(btn)
			_armas_buttons.append(btn)
	if not hay_armas:
		if is_instance_valid(btn_metralleta): btn_metralleta.visible = true
		if is_instance_valid(btn_escopeta):   btn_escopeta.visible   = true

# --- Llamados desde la escena (conectados en el editor) ---

func _on_team_rojo_pressed() -> void:
	_selected_team_id = int(Enums.Equipo.ROJO)
	team_panel.visible   = false
	weapon_panel.visible = true
	if is_instance_valid(weapon_title):
		weapon_title.text = "Equipo Rojo - Elige tu arma"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_team_azul_pressed() -> void:
	_selected_team_id = int(Enums.Equipo.AZUL)
	team_panel.visible   = false
	weapon_panel.visible = true
	if is_instance_valid(weapon_title):
		weapon_title.text = "Equipo Azul - Elige tu arma"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_weapon_pressed(nombre_arma: String) -> void:
	_confirmar_seleccion(nombre_arma)

func _on_weapon_metralleta_pressed() -> void:
	_confirmar_seleccion("MP7")

func _on_weapon_escopeta_pressed() -> void:
	_confirmar_seleccion("M3")

func _on_weapon_back_pressed() -> void:
	weapon_panel.visible = false
	team_panel.visible   = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _confirmar_seleccion(nombre_arma: String) -> void:
	GameState.player_team     = _selected_team_id
	GameState.selected_weapon = nombre_arma
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Equipar el arma en el jugador inmediatamente
	var player_ref: Player = get_tree().get_first_node_in_group("player") as Player
	if player_ref:
		player_ref.setup_weapon(nombre_arma)

	# ── NUEVO: Iniciar la partida a traves de MatchManager ──
	# El MatchManager crea todos los bots necesarios para alcanzar
	# el maximo de jugadores, los asigna a equipos, y los coloca
	# en los puntos de spawn correspondientes.
	if is_instance_valid(player_ref):
		MatchManager.iniciar_partida(player_ref, _selected_team_id)

	queue_free()
