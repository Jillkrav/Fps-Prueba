extends Node

# Singleton para persistencia del estado de juego
class_name GameStateClass

var selected_map: String = "res://scenes/maps/map_1.tscn"
var selected_weapon: String = "metralleta"
var selected_team: String = ""

var player_max_health: float = 100.0
var player_current_health: float = 100.0

# Configuraciones de armas para facilitar acceso global con soporte de recarga
const WEAPON_CONFIGS: Dictionary = {
	"metralleta": {
		"name": "Metralleta",
		"damage": 10.0,
		"fire_rate": 0.12, # Tiempo entre disparos
		"max_ammo": 120, # Reserva máxima
		"clip_size": 30, # Capacidad del cargador
		"spread": 0.03,
		"range": 50.0,
		"reload_time": 1.5, # Tiempo de recarga en segundos
		"color": Color(0.2, 0.6, 1.0) # Color representativo del placeholder
	},
	"escopeta": {
		"name": "Escopeta",
		"damage": 12.0, # Por perdigón
		"pellets": 8, # Número de perdigones
		"fire_rate": 0.8,
		"max_ammo": 24, # Reserva máxima
		"clip_size": 6, # Capacidad del cargador
		"spread": 0.12,
		"range": 15.0,
		"reload_time": 2.2, # Tiempo de recarga en segundos
		"color": Color(1.0, 0.4, 0.1) # Color representativo del placeholder
	}
}

func _ready() -> void:
	pass
