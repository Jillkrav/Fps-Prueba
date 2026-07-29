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
