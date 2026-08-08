# scripts/game_modes/core_attack/core_attack_mode.gd
# ──────────────────────────────────────────────────────────────────
# CORE ATTACK MODE — Adaptador del modo actual (destruir el núcleo).
#
# Encapsula el comportamiento existente de "destruir el core enemigo"
# dentro del sistema de modos. No rompe nada: sigue usando GameStateMP
# y los cores ya registrados.
#
# Los bots consultan este modo para saber qué atacar/defender, y se
# adaptan automáticamente a que existan o no rutas authored.
# ──────────────────────────────────────────────────────────────────
extends "res://Scripts/Multiplayer/game_modes/game_mode.gd"
class_name CoreAttackMode

func _init() -> void:
	mode_id = "core_attack"
	mode_name = "Destruir el núcleo"


## Objetivo principal: destruir el core enemigo.
func get_objectives_for_team(team: int) -> Array[Objective]:
	var results: Array[Objective] = []
	var enemy_core: Node = _get_enemy_core(team)
	if enemy_core and is_instance_valid(enemy_core) and enemy_core.is_inside_tree():
		var obj := Objective.attack(enemy_core.global_position, team, "core_attack_%s" % team)
		obj.target_node = enemy_core.get_path()
		results.append(obj)
	return results


## Objetivo de defensa: proteger el core propio.
func get_defense_objective(team: int) -> Objective:
	var own_core: Node = _get_own_core(team)
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		return Objective.defend(own_core.global_position, team, "core_defend_%s" % team)
	return null


## Victoria: el core enemigo fue destruido (lo gestiona GameStateMP).
func team_has_won(team: int) -> bool:
	if not GameStateMP:
		return false
	return GameStateMP.winner_team == team and GameStateMP.match_active == false


## Core enemigo del equipo.
func _get_enemy_core(team: int) -> Node:
	if not GameStateMP:
		return null
	if team == int(Enums.Equipo.AZUL):
		return GameStateMP.core_red
	elif team == int(Enums.Equipo.ROJO):
		return GameStateMP.core_blue
	return null


## Core propio del equipo.
func _get_own_core(team: int) -> Node:
	if not GameStateMP:
		return null
	if team == int(Enums.Equipo.AZUL):
		return GameStateMP.core_blue
	elif team == int(Enums.Equipo.ROJO):
		return GameStateMP.core_red
	return null