# scripts/game_modes/game_mode.gd
# ──────────────────────────────────────────────────────────────────
# GAME MODE — Clase base abstracta para modos de juego.
#
# Define el contrato que cualquier modo debe implementar para que los
# bots y el framework de partida se adapten automáticamente a él.
#
# Objetivo: que los bots tengan PROPÓSITOS según el modo de juego,
# sin depender de implementaciones específicas ni de rutas authored.
#
# ── CÓMO EXTENDER ──
# 1. Crea una subclase (ej: CoreAttackMode, CaptureTheFlagMode, ...).
# 2. Implementa get_objectives_for_team() y las señales de estado.
# 3. Regístrala en GameModeManager para activarla.
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name GameMode

## Identificador único del modo.
var mode_id: String = "base"

## Nombre legible para UI/debug.
var mode_name: String = "Base"


# ══════════════════════════════════════════════════════════════════
# API PRINCIPAL — Implementar en subclases
# ══════════════════════════════════════════════════════════════════

## Devuelve los objetivos primarios para el equipo `team`.
## Retorna un Array[Objective] (clase Objective existente).
func get_objectives_for_team(_team: int) -> Array[Objective]:
	return []


## Devuelve el objetivo de defensa (dónde proteger) para el equipo.
## Retorna null si el modo no tiene defensa.
func get_defense_objective(_team: int) -> Objective:
	return null


## Devuelve los puntos de captura/control relevantes para el modo.
## Retorna un Array[Node] (ZonePoint u otros).
func get_capture_points() -> Array[Node]:
	return []


## Puntos de aparición relevantes para el equipo (si el modo los define).
func get_spawn_points(_team: int) -> Array[Node]:
	return []


## ¿El equipo `team` ya ganó? (para victoria automática).
func team_has_won(_team: int) -> bool:
	return false


# ══════════════════════════════════════════════════════════════════
# UTILIDADES PARA SUBCLASES
# ══════════════════════════════════════════════════════════════════

## Crea y devuelve una Objective de ataque hacia una posición.
func _make_attack(target_pos: Vector3, team: int, obj_id: String = "") -> Objective:
	return Objective.attack(target_pos, team, obj_id)


## Crea y devuelve una Objective de defensa hacia una posición.
func _make_defend(target_pos: Vector3, team: int, obj_id: String = "") -> Objective:
	return Objective.defend(target_pos, team, obj_id)


## Crea y devuelve una Objective de captura hacia una posición.
func _make_capture(target_pos: Vector3, team: int, obj_id: String = "") -> Objective:
	var obj := Objective.new()
	obj.objective_type = Objective.Type.CAPTURE
	obj.position = target_pos
	obj.team = team
	obj.objective_id = obj_id if obj_id != "" else "capture_%s" % [str(randi())]
	obj.display_name = "Capturar"
	return obj


func _to_string() -> String:
	return "GameMode[%s]" % mode_name