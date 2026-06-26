# scripts/player_data.gd
# Contenedor de datos de un jugador (humano o bot).
# El MatchManager mantiene el registro centralizado de todas las instancias.
# El Scoreboard y otros sistemas solo LEEN estos datos — nunca los duplican.
class_name PlayerData
extends RefCounted

## Estado del jugador desde la perspectiva del Scoreboard.
enum Status {
	ALIVE,       # Vivo y jugando
	DEAD,        # Muerto, esperando respawn
	RESPAWNING,  # En proceso de reaparicion (con temporizador activo)
	INACTIVE     # Bot desactivado / sin equipo asignado
}

# ── Identidad ──────────────────────────────

## ID unico asignado por MatchManager
var player_id: int = 0

## Nombre para mostrar en el Scoreboard
var player_name: String = ""

## Referencia al nodo fisico (Player o NpcBase)
var pawn: Node = null

## true si es el jugador humano, false si es bot
var is_human: bool = false

# ── Estado del juego ───────────────────────

## Equipo actual (usar Enums.Equipo)
var team: int = 0

## Estado actual
var status: Status = Status.INACTIVE

# ── Salud ──────────────────────────────────

var health: float = 0.0
var max_health: float = 100.0

# ── Estadisticas ───────────────────────────

var kills: int = 0
var deaths: int = 0
# Futuro: ping, asistencias, damage_done, damage_taken, etc.

# ── Respawn ────────────────────────────────

## Tiempo restante de respawn (solo relevante cuando status == RESPAWNING)
var respawn_time_left: float = 0.0

# ── Utilidad ───────────────────────────────

func _to_string() -> String:
	return "[PlayerData #%d %s | Team:%d HP:%.0f/%.0f K:%d D:%d Status:%s]" % [
		player_id, player_name, team, health, max_health, kills, deaths, Status.keys()[status]
	]
