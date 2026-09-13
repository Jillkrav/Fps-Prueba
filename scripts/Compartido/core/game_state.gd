# scripts/game_state.gd
# Autoload singleton registrado como "GameState".
# Guarda el estado persistente entre escenas (COMPARTIDO).

extends Node
class_name GameStateClass

# Alias de Enums.Equipo para compatibilidad con codigo existente.
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

var selected_map:    String = "res://scenes/Multiplayer/mapas/map_1.tscn"
var selected_weapon: String = ""

# El jugador empieza como Espectador hasta que elija equipo
var player_team: int = int(Enums.Equipo.ESPECTADOR)

# ── Debug: Modo Dios y Fuego Amigo ────────────────────────────────
## Si es true, el jugador (human) nunca muere ni recibe daño.
var god_mode: bool = false
## Si es true, el daño entre aliados (mismo equipo) está permitido.
## Si es false, bots y jugadores del mismo equipo no pueden hacerse daño.
var friendly_fire: bool = true

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

func _ready() -> void:
	_load_mouse_settings()

# ── Funciones compartidas ─────────────────────────────────────────

# Devuelve true SOLO si ambos equipos son distintos Y ninguno es Espectador.
func son_enemigos(equipo_a: int, equipo_b: int) -> bool:
	if equipo_a == int(Enums.Equipo.ESPECTADOR) or equipo_b == int(Enums.Equipo.ESPECTADOR):
		return false
	return equipo_a != equipo_b

func nombre_equipo(id: int) -> String:
	return NOMBRE_EQUIPO.get(id, "Desconocido")

# ── Helpers de equipo para Fuego Amigo ─────────────────────────────

## Devuelve el equipo de un pawn (Player o BotBase), o -1 si no se puede
## determinar. Útil para comprobar fuego amigo.
func obtener_equipo_de_pawn(pawn: Node) -> int:
	if not pawn:
		return -1
	if pawn is Player:
		return player_team
	if "equipo_id" in pawn:
		return int(pawn.equipo_id)
	return -1

## Resuelve el nodo atacante desde un killer_id. El killer_id puede ser
## un player_id de MatchManager (jugadores/bots registrados) o un
## instance_id (proyectiles, explosiones, melee). Devuelve null si no se
## puede resolver.
func obtener_atacante_desde_id(killer_id: int) -> Node:
	if killer_id <= 0:
		return null
	# GameState se registra como autoload ANTES que MatchManager, así que
	# resolvemos el singleton por nodo en lugar de por identificador global.
	var mm: Node = get_node_or_null("/root/MatchManager")
	if mm:
		var pd: PlayerData = mm.get_player_data(killer_id)
		if pd and is_instance_valid(pd.pawn):
			return pd.pawn
	var inst: Object = instance_from_id(killer_id)
	if inst is Node and is_instance_valid(inst):
		return inst as Node
	return null

## Devuelve true si el daño debe ignorarse por fuego amigo: cuando el
## fuego amigo está desactivado y el atacante está en el mismo equipo
## que la víctima.
func es_dano_bloqueado_por_fff(killer_id: int, victima: Node) -> bool:
	if friendly_fire:
		return false
	var atacante: Node = obtener_atacante_desde_id(killer_id)
	if not atacante:
		return false
	var eq_atk: int = obtener_equipo_de_pawn(atacante)
	var eq_vic: int = obtener_equipo_de_pawn(victima)
	if eq_atk == -1 or eq_vic == -1:
		return false
	return eq_atk == eq_vic

func color_equipo(id: int) -> Color:
	return COLOR_EQUIPO.get(id, Color.WHITE)

# ── Mouse settings persistence ─────────────────────────────────────

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
