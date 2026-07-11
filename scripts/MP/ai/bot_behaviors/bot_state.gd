# scripts/ai/bot_state.gd
# ──────────────────────────────────────────────────────────────────
# CLASE BASE PARA ESTADOS DE LA FSM (FASE 3)
#
# Cada estado es un Node hijo de DecisionSystem.
# Los estados ESCRIBEN en DecisionSystem.target_entity,
# movement_command y combat_command.
#
# ── CICLO DE VIDA ──
#   enter(previous_state) → Al activar este estado
#   execute(delta)        → Cada frame mientras está activo
#   exit(next_state)      → Al desactivar este estado
#
# ── MANEJADORES DE EVENTOS ──
#   Se llaman desde DecisionSystem cuando ocurre el evento.
#   Cada estado decide si responde (por defecto: no hace nada).
# ──────────────────────────────────────────────────────────────────
extends Node
class_name BotState


# ══════════════════════════════════════════════════════════════════
# ENUM — Tipos de estado de la FSM
# ══════════════════════════════════════════════════════════════════

enum StateType {
	ACQUISITION = 0,    # Adquisición de objetivo
	COMBAT = 1,         # Raíz de combate (elige sub-estado)
	TACTICAL_MOVE = 2,  # Strafe táctico
	CHARGING = 3,       # Carga frontal
	RANGED_ATTACK = 4,  # Ataque a distancia
	HUNTING = 5,        # Persecución de última posición conocida
	STAKEOUT = 6,       # Vigilancia de un punto
	RETREATING = 7,     # Retirada táctica
	ROAMING = 8,        # Deambular / patrullar
	WANDERING = 9,      # Vagabundeo aleatorio
	HOLDING = 10,       # Quieto / mantener posición
	FALLING = 11,       # Cayendo
	TAKING_HIT = 12,    # Recibiendo daño / stun
}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Tipo de este estado (identificador único en la FSM)
@export var state_type: int = StateType.ROAMING

## Nombre legible para debug
@export var state_name: String = "abstract"

## Referencia al DecisionSystem (padre)
var decision_system: DecisionSystem = null


# ══════════════════════════════════════════════════════════════════
# ACCESO A SISTEMAS (vía DecisionSystem)
# ══════════════════════════════════════════════════════════════════

var bot: NpcBase:
	get: return decision_system.bot if decision_system else null

var perception: PerceptionSystem:
	get: return decision_system.perception_sys if decision_system else null

var memory: MemorySystem:
	get: return decision_system.memory_sys if decision_system else null

var movement: MovementSystem:
	get: return decision_system.movement_sys if decision_system else null

var navigation: NavigationSystem:
	get: return decision_system.navigation_sys if decision_system else null

var movement_cmd: MovementCommand:
	get: return decision_system.movement_command if decision_system else null

var combat_cmd: CombatCommand:
	get: return decision_system.combat_command if decision_system else null


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

## Llamado cuando este estado se convierte en el activo.
func enter(_previous_state: BotState) -> void:
	pass


## Llamado cada frame mientras este estado está activo.
## Aquí se escribe en movement_command, combat_command, target_entity.
func execute(_delta: float) -> void:
	pass


## Llamado cuando este estado deja de ser el activo.
func exit(_next_state: BotState) -> void:
	pass


# ══════════════════════════════════════════════════════════════════
# MANEJADORES DE EVENTOS
# ══════════════════════════════════════════════════════════════════
# Se llaman desde DecisionSystem cuando ocurre el evento.
# Por defecto no hacen nada — cada estado decide si responde.

func on_see_player(_player: Node3D) -> void:
	pass

func on_hear_noise(_loudness: float, _source: Vector3) -> void:
	pass

func on_take_damage(_amount: float, _attacker: Node3D) -> void:
	pass

func on_hit_wall(_normal: Vector3) -> void:
	pass

func on_stuck_detected(_phase: int, _cause: String) -> void:
	pass

func on_destination_reached() -> void:
	pass


# ══════════════════════════════════════════════════════════════════
# UTILIDADES PARA ESTADOS HIJOS
# ══════════════════════════════════════════════════════════════════

## Cambia a otro estado de la FSM. Llama a DecisionSystem.
func change_state(new_type: int) -> void:
	if decision_system:
		decision_system.change_state(new_type)

## ¿Hay un objetivo enemigo válido?
func has_target() -> bool:
	return decision_system and decision_system.has_target()

## Distancia al objetivo actual (o INF si no hay).
func dist_to_target() -> float:
	if decision_system:
		return decision_system.dist_to_target()
	return INF

## ¿El objetivo actual está muerto?
func is_target_dead() -> bool:
	return decision_system and decision_system.is_target_dead()

## Porcentaje de salud del bot (0.0 - 1.0).
func health_pct() -> float:
	if decision_system:
		return decision_system.health_pct()
	return 0.0

## Debug
func _debug(msg: String) -> void:
	if bot:
		bot._debug("[%s] %s" % [state_name, msg])
