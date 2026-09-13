# scripts/game_state_mp.gd
# Autoload singleton registrado como "GameStateMP".
# Guarda el estado de la partida Multiplayer.

extends Node
class_name GameStateMPClass

# ═══════════════════════════════════════════════════════════════════
# MATCH CONFIG
# ═══════════════════════════════════════════════════════════════════

## Maximo total de jugadores en la partida (bots + jugador humano)
## Este valor se usa al iniciar MatchManager. Cambiable desde el inspector
## en el autoload MatchManager (propiedad max_players_total).
var max_players_total: int = 24

## Maximo de jugadores por equipo (se calcula como max_players_total / 2)
var max_per_team: int = 12

# ═══════════════════════════════════════════════════════════════════
# MATCH STATE
# ═══════════════════════════════════════════════════════════════════

## Indica si la partida esta activa (true desde que inicia hasta que un core muere)
var match_active: bool = false

## Equipo ganador (-1 = nadie aun, o empate)
var winner_team: int = -1

## Referencias a los cores (se registran al iniciar el mapa)
var core_blue: Node = null
var core_red: Node = null

## Senial para notificar fin de partida
signal match_ended(winning_team: int)
signal core_health_changed(team: int, current_hp: float, max_hp: float)

func _ready() -> void:
	match_active = false
	winner_team = -1
	core_blue = null
	core_red = null

# ═══════════════════════════════════════════════════════════════════
# FUNCIONES DE PARTIDA
# ═══════════════════════════════════════════════════════════════════

func start_match() -> void:
	match_active = true
	winner_team = -1
	print("[GameStateMP] Partida iniciada")

func register_core(core_node: Node) -> void:
	if not core_node or not core_node.has_method("get_team"):
		return
	var team_id: int = core_node.team if "team" in core_node else -1
	if team_id == int(Enums.Equipo.AZUL):
		core_blue = core_node
		print("[GameStateMP] Core Azul registrado en " + str(core_node.global_position))
	elif team_id == int(Enums.Equipo.ROJO):
		core_red = core_node
		print("[GameStateMP] Core Rojo registrado en " + str(core_node.global_position))

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

	print("[GameStateMP] Core %s destruido. Ganador: %s" % [
		GameState.nombre_equipo(core_team),
		GameState.nombre_equipo(winner_team) if winner_team >= 0 else "Nadie"
	])

	match_ended.emit(winner_team)

func is_player_victory() -> bool:
	if winner_team < 0:
		return false
	return winner_team == GameState.player_team

func on_core_health_updated(team: int, current_hp: float, max_hp: float) -> void:
	core_health_changed.emit(team, current_hp, max_hp)

func reset_match() -> void:
	match_active = false
	winner_team = -1
	core_blue = null
	core_red = null
