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
	ROAMING = 0,        # Deambular / patrullar
	HUNTING = 1,        # Persecución de última posición conocida
	COMBAT = 2,         # Raíz de combate (elige sub-estado)
	RETREATING = 3,     # Retirada táctica
	TAKING_HIT = 4,     # Recibiendo daño / stun
	FLEEING = 5,        # Supervivencia: arma guardada, buscar recurso/base
	COVER_RELOAD = 6,   # Buscar cobertura y recargar bajo presión
}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Tipo de este estado (identificador único en la FSM)
@export var state_type: int = StateType.ROAMING

## Nombre legible para debug
@export var state_name: String = "abstract"

## Límite de tiempo (segundos) que este estado puede permanecer activo antes
## de que el watchdog de DecisionSystem lo fuerce a `timeout_fallback`.
## INF = sin límite (estado hogar, p.ej. ROAMING).
var max_duration: float = INF

## Estado al que ir si se supera `max_duration`.
## Solo aplica si `max_duration` es finito.
var timeout_fallback: int = StateType.ROAMING

## Referencia al DecisionSystem (padre)
var decision_system: DecisionSystem = null


# ══════════════════════════════════════════════════════════════════
# ACCESO A SISTEMAS (vía DecisionSystem)
# ══════════════════════════════════════════════════════════════════

var bot: BotBase:
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


## Llamado por DecisionSystem cuando el watchdog fuerza la salida de este
## estado por superar `max_duration`. Útil para limpiar estado antes del
## timeout (p.ej. FLEEING cancela el modo huir para evitar re-entrada).
func on_timeout_forced() -> void:
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
