# scripts/game_state.gd
# Autoload singleton — persiste estado entre escenas.
# NO almacena stats de armas ni de NPCs: eso lo hace ConfigManager.
extends Node
class_name GameStateClass

var selected_map: String    = "res://scenes/maps/map_1.tscn"
var selected_weapon: String = "USP"  # Debe ser un nombre exacto de skill.cfg.json

var player_max_health: float    = 0.0
var player_current_health: float = 0.0

func _ready() -> void:
	# Leer salud del jugador desde ConfigManager una vez que esté listo
	player_max_health     = ConfigManager.salud_jugador
	player_current_health = player_max_health
