extends Node
class_name GameStateClass

# Singleton para persistencia del estado de juego.
# Los valores de armas y salud ya NO se definen aquí:
# se leen en tiempo de ejecución desde ConfigManager (skill.cfg.json).

var selected_map: String = "res://scenes/maps/map_1.tscn"

## Nombre exacto del arma según skill.cfg.json.
## Se asigna desde team_weapon_selector.gd al elegir arma.
## Vacío = el jugador no ha elegido arma todavía (se usará la primera disponible).
var selected_weapon: String = ""

## Equipo del jugador. Vacío = sin equipo asignado (tratado como Equipo.UNO por defecto).
var selected_team: String = "azul"

var player_max_health: float = 100.0
var player_current_health: float = 100.0

func _ready() -> void:
	pass

## Devuelve la primera arma disponible en el JSON como fallback seguro.
func get_weapon_or_default() -> String:
	if not selected_weapon.is_empty():
		return selected_weapon
	# Fallback: tomar la primera arma del JSON
	var armas_raw: Dictionary = ConfigManager._data.get("Armas", {})
	for categoria in armas_raw.values():
		if categoria is Dictionary and not categoria.is_empty():
			return categoria.keys()[0]
	return "USP"
