# scripts/team_weapon_selector.gd
# Pantalla de selección de equipo y arma antes de entrar al mapa.
# Rellena los OptionButton con los datos reales de skill.cfg.json.
extends Control

@onready var opt_equipo:  OptionButton = $VBox/OptEquipo
@onready var opt_arma:    OptionButton = $VBox/OptArma
@onready var btn_jugar:   Button       = $VBox/BtnJugar
@onready var lbl_detalle: Label        = $VBox/LblDetalle

# Lista paralela para recuperar el nombre de arma por índice
var _armas_lista: Array[String] = []

func _ready() -> void:
	# ── Equipos ──────────────────────────────────────────────────────
	opt_equipo.clear()
	opt_equipo.add_item("Equipo Azul (Aliado)",   0)
	opt_equipo.add_item("Equipo Rojo (Enemigo)",  1)
	# Por defecto: azul
	opt_equipo.select(0)

	# ── Armas desde ConfigManager ────────────────────────────────────
	_poblar_armas()

	# Mostrar detalle del arma seleccionada al inicio
	_on_arma_seleccionada(0)

	opt_arma.item_selected.connect(_on_arma_seleccionada)
	btn_jugar.pressed.connect(_on_jugar_pressed)

func _poblar_armas() -> void:
	_armas_lista.clear()
	opt_arma.clear()
	var armas_raw: Dictionary = ConfigManager._data.get("Armas", {})
	for categoria: String in armas_raw.keys():
		var cat_dict: Dictionary = armas_raw[categoria]
		for nombre_arma: String in cat_dict.keys():
			_armas_lista.append(nombre_arma)
			opt_arma.add_item("%s  [%s]" % [nombre_arma, categoria])

	if _armas_lista.is_empty():
		push_error("TeamWeaponSelector: No se encontraron armas en skill.cfg.json")

func _on_arma_seleccionada(index: int) -> void:
	if index < 0 or index >= _armas_lista.size():
		return
	var nombre: String = _armas_lista[index]
	var cfg: Dictionary = ConfigManager.get_arma(nombre)
	if cfg.is_empty():
		lbl_detalle.text = ""
		return
	lbl_detalle.text = (
		"%s\nDaño al jugador: %s  |  Daño al NPC: %s\nCargador: %s  |  Reserva: %s\nCadencia: %ss/bala  |  Recarga: %ss" % [
			nombre,
			str(cfg.get("DañoAlJugador", "—")),
			str(cfg.get("DañoAlNPC", "—")),
			str(cfg.get("TamañoCargador", "—")),
			str(cfg.get("ReservaMunicionMaxima", "—")),
			str(cfg.get("SegundosPorBala", "—")),
			str(cfg.get("TiempoRecargaSegundos", "—")),
		]
	)

func _on_jugar_pressed() -> void:
	if _armas_lista.is_empty():
		return

	# ── Guardar equipo ────────────────────────────────────────────────
	match opt_equipo.get_selected_id():
		0: GameState.selected_team = "azul"
		1: GameState.selected_team = "rojo"

	# ── Guardar arma ─────────────────────────────────────────────────
	var arma_idx: int = opt_arma.get_selected()
	if arma_idx >= 0 and arma_idx < _armas_lista.size():
		GameState.selected_weapon = _armas_lista[arma_idx]

	# ── Cargar mapa ───────────────────────────────────────────────────
	get_tree().change_scene_to_file(GameState.selected_map)
