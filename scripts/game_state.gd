extends Node
class_name GameStateClass

# Singleton para persistencia del estado de juego.
# Los valores de armas y salud ya NO se definen aquí:
# se leen en tiempo de ejecución desde ConfigManager (skill.cfg.json).

var selected_map: String = "res://scenes/maps/map_1.tscn"

## Nombre exacto del arma según skill.cfg.json.
## Cambiar este valor para que el jugador empiece con otra arma.
var selected_weapon: String = "USP"

var selected_team: String = ""

var player_max_health: float = 100.0
var player_current_health: float = 100.0

func _ready() -> void:
	pass
