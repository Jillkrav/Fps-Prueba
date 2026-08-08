# scripts/game_modes/game_mode_manager.gd
# ──────────────────────────────────────────────────────────────────
# GAME MODE MANAGER — Autoload que gestiona el modo de juego activo.
#
# Permite que los bots consulten "cuál es mi objetivo" de forma
# independiente del modo específico. El modo por defecto es
# Core Attack (no rompe nada).
#
# ── REGISTRO ──
# 1. Añadir este script como autoload "GameModeManager" en project.godot.
# 2. El modo activo se configura en set_mode() o por defecto.
# ──────────────────────────────────────────────────────────────────
extends Node

## Enums de modos de juego soportados.
enum ModeType {
	CORE_ATTACK = 0,
	# FUTURO: CAPTURE_THE_FLAG, KING_OF_THE_HILL, PAYLOAD, ATTACK_POINTS,
	#         TEAM_DEATHMATCH, DEATHMATCH, ATTACK_DEFEND
}

## Modo de juego activo.
var active_mode: GameMode = null

## Modo por defecto (no rompe el modo actual).
var default_mode: int = ModeType.CORE_ATTACK


func _ready() -> void:
	set_mode(default_mode)


## Configura el modo activo por su tipo.
func set_mode(mode_type: int) -> void:
	match mode_type:
		ModeType.CORE_ATTACK:
			active_mode = CoreAttackMode.new()
		_:
			active_mode = CoreAttackMode.new()
	print("[GameModeManager] Modo activo: %s" % (active_mode.mode_name if active_mode else "Ninguno"))


## Objetivos primarios del equipo para la IA.
func get_objectives_for_team(team: int) -> Array[Objective]:
	if active_mode:
		return active_mode.get_objectives_for_team(team)
	return []


## Objetivo de defensa del equipo.
func get_defense_objective(team: int) -> Objective:
	if active_mode:
		return active_mode.get_defense_objective(team)
	return null


## Puntos de captura del modo.
func get_capture_points() -> Array[Node]:
	if active_mode:
		return active_mode.get_capture_points()
	return []


## Objetivo principal más prioritario para un equipo (para bots).
func get_primary_objective(team: int) -> Objective:
	var objectives: Array[Objective] = get_objectives_for_team(team)
	if objectives.is_empty():
		return null
	var best: Objective = objectives[0]
	for obj: Objective in objectives:
		if obj.priority > best.priority:
			best = obj
	return best