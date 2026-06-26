# scripts/game_state.gd
# Autoload singleton registrado como "GameState".
# Guarda el estado persistente entre escenas + match state.

extends Node
class_name GameStateClass

# Alias de Enums.Equipo para compatibilidad con codigo existente.
# Las nuevas implementaciones deben usar Enums.Equipo directamente.
const Equipo = Enums.Equipo

const NOMBRE_EQUIPO: Dictionary = {
	0: "Espectador",
	1: "Azul",
	2: "Rojo",
	3: "Amarillo",
	4: "Verde"
}

const COLOR_EQUIPO: Dictionary = {
	0: Color(0.6,  0.6,  0.6),    # Gris  - Espectador
	1: Color(0.15, 0.35, 0.9),    # Azul
	2: Color(0.85, 0.15, 0.15),   # Rojo
	3: Color(0.85, 0.75, 0.1),    # Amarillo
	4: Color(0.15, 0.75, 0.25)    # Verde
}

var selected_map:    String = "res://scenes/maps/map_1.tscn"
var selected_weapon: String = ""

# El jugador empieza como Espectador hasta que elija equipo
var player_team: int = int(Enums.Equipo.ESPECTADOR)

# Ajustes de mouse compartidos
var mouse_sensitivity: float = 0.002:
	set(value):
		mouse_sensitivity = value
		save_mouse_settings()
var mouse_invert_y: bool = false:
	set(value):
		mouse_invert_y = value
		save_mouse_settings()

const MOUSE_SETTINGS_PATH: String = "user://mouse_settings.cfg"

# ── Match State ────────────────────────────────────────────────────────

## Indica si la partida esta activa (true desde que inicia hasta que un core muere)
var match_active: bool = false

## Equipo ganador (-1 = nadie aun, o empate)
var winner_team: int = -1

## Referencias a los cores (se registran al iniciar el mapa)
var core_blue: Node = null
var core_red: Node = null

## Señal para notificar fin de partida
signal match_ended(winning_team: int)
signal core_health_changed(team: int, current_hp: float, max_hp: float)

func _ready() -> void:
	_load_mouse_settings()
	match_active = false
	winner_team = -1
	core_blue = null
	core_red = null

# ── Funciones de partida ───────────────────────────────────────────────

func start_match() -> void:
	match_active = true
	winner_team = -1
	print("[GameState] Partida iniciada")

func register_core(core_node: Node) -> void:
	if not core_node or not core_node.has_method("get_team"):
		return
	var team_id: int = core_node.team if "team" in core_node else -1
	if team_id == int(Enums.Equipo.AZUL):
		core_blue = core_node
		print("[GameState] Core Azul registrado en " + str(core_node.global_position))
	elif team_id == int(Enums.Equipo.ROJO):
		core_red = core_node
		print("[GameState] Core Rojo registrado en " + str(core_node.global_position))

	if core_blue and core_red:
		start_match()

func on_core_destroyed(core_team: int) -> void:
	if not match_active:
		return
	match_active = false
	
	# El equipo contrario al core destruido gana
	if core_team == int(Enums.Equipo.AZUL):
		winner_team = int(Enums.Equipo.ROJO)
	elif core_team == int(Enums.Equipo.ROJO):
		winner_team = int(Enums.Equipo.AZUL)
	else:
		winner_team = -1
	
	print("[GameState] Core %s destruido. Ganador: %s" % [
		GameState.nombre_equipo(core_team),
		GameState.nombre_equipo(winner_team) if winner_team >= 0 else "Nadie"
	])
	
	match_ended.emit(winner_team)

func is_player_victory() -> bool:
	if winner_team < 0:
		return false
	return winner_team == player_team

func on_core_health_updated(team: int, current_hp: float, max_hp: float) -> void:
	core_health_changed.emit(team, current_hp, max_hp)

func reset_match() -> void:
	match_active = false
	winner_team = -1
	core_blue = null
	core_red = null

# ── Funciones existentes ───────────────────────────────────────────────

# Devuelve true SOLO si ambos equipos son distintos Y ninguno es Espectador.
func son_enemigos(equipo_a: int, equipo_b: int) -> bool:
	if equipo_a == int(Enums.Equipo.ESPECTADOR) or equipo_b == int(Enums.Equipo.ESPECTADOR):
		return false
	return equipo_a != equipo_b

func nombre_equipo(id: int) -> String:
	return NOMBRE_EQUIPO.get(id, "Desconocido")

func color_equipo(id: int) -> Color:
	return COLOR_EQUIPO.get(id, Color.WHITE)

# ── Mouse settings persistence ──────────────────────────────────────────

func save_mouse_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("mouse", "sensitivity", mouse_sensitivity)
	config.set_value("mouse", "invert_y", mouse_invert_y)
	config.save(MOUSE_SETTINGS_PATH)

func _load_mouse_settings() -> void:
	var config := ConfigFile.new()
	var err: Error = config.load(MOUSE_SETTINGS_PATH)
	if err != OK:
		return
	if config.has_section_key("mouse", "sensitivity"):
		mouse_sensitivity = config.get_value("mouse", "sensitivity", 0.002)
	if config.has_section_key("mouse", "invert_y"):
		mouse_invert_y = config.get_value("mouse", "invert_y", false)
