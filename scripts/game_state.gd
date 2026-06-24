# scripts/game_state.gd
# Autoload singleton registrado como "GameState".
# Guarda el estado persistente entre escenas (mapa y arma seleccionados).
# Las configuraciones de armas ya NO se guardan aqui: usa ConfigManager.get_arma().
extends Node
class_name GameStateClass

var selected_map:    String = "res://scenes/maps/map_1.tscn"
var selected_weapon: String = "USP"

func _ready() -> void:
	pass
