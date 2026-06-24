# scripts/game_state.gd
# Autoload singleton registrado como "GameState".
# Guarda el estado persistente entre escenas.

extends Node
class_name GameStateClass

# Equipo 0 = Espectador (sin equipo, sin amigos ni enemigos)
# Equipo 1 = Azul
# Equipo 2 = Rojo
# Equipo 3 = Amarillo (futuro)
# Equipo 4 = Verde    (futuro)
enum Equipo {
	ESPECTADOR = 0,
	AZUL       = 1,
	ROJO       = 2,
	AMARILLO   = 3,
	VERDE      = 4
}

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
var selected_weapon: String = "USP"

# El jugador empieza como Espectador hasta que elija equipo
var player_team: int = Equipo.ESPECTADOR

func _ready() -> void:
	pass

# Devuelve true SOLO si ambos equipos son distintos Y ninguno es Espectador.
func son_enemigos(equipo_a: int, equipo_b: int) -> bool:
	if equipo_a == Equipo.ESPECTADOR or equipo_b == Equipo.ESPECTADOR:
		return false
	return equipo_a != equipo_b

func nombre_equipo(id: int) -> String:
	return NOMBRE_EQUIPO.get(id, "Desconocido")

func color_equipo(id: int) -> Color:
	return COLOR_EQUIPO.get(id, Color.WHITE)
