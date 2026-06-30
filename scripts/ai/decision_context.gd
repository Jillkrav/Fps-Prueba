# scripts/ai/decision_context.gd
# ──────────────────────────────────────────────────────────────────
# CONTEXTO DE DECISIÓN (Blackboard ligero para BotBrain)
#
# Pizarra compartida entre behaviors y BotBrain.
# Los behaviors ESCRIBEN sus intenciones aquí durante execute().
# BotBrain LEE y TRADUCE estas intenciones a llamadas a sistemas.
#
# ── ESTRUCTURA INTERNA ──
# MovementIntent  → qué movimiento quiere el behavior
# CombatIntent    → qué acción de combate quiere el behavior
# StateFlags      → estado actual del bot (lectura/escritura)
#
# ── REGLAS ──
# - Solo el behavior ACTIVO escribe durante execute()
# - Los behaviors NO escriben en get_priority() (solo lectura)
# - context.reset_frame() se llama al inicio de cada process()
# - resolve_context() valida coherencia antes de ejecutar
#
# ── PROGRESIÓN ──
# Fase 1: Behaviors usan API antigua (brain.navigate_to).
#         Context existe pero nadie escribe → execute_context() no hace nada.
# Fase 5: Behaviors migran a escribir en context.
#         execute_context() traduce a sistemas.
#         Ambos modos pueden coexistir durante la migración.
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name DecisionContext


# ══════════════════════════════════════════════════════════════════
# BLOQUE 1: MovementIntent
# ══════════════════════════════════════════════════════════════════

## Intención de movimiento que un behavior comunica a BotBrain.
class MovementIntent:
	## Modos de movimiento disponibles
	enum Mode {
		NONE = 0,      # Sin intención de movimiento (usa API antigua)
		NAVIGATE = 1,  # Pathfinding hacia un destino
		DIRECT = 2,    # Vector directo (strafe, retreat, etc.)
		HOLD = 3,      # Quieto intencional
	}

	var mode: int = Mode.NONE
	var target: Vector3 = Vector3.ZERO    # Para NAVIGATE
	var vector: Vector3 = Vector3.ZERO    # Para DIRECT
	var speed: float = 0.0

	## Configura modo NAVIGATE
	func set_navigate(target_pos: Vector3, move_speed: float) -> void:
		mode = Mode.NAVIGATE
		target = target_pos
		speed = move_speed
		vector = Vector3.ZERO

	## Configura modo DIRECT (vector directo)
	func set_direct(direction: Vector3, move_speed: float) -> void:
		mode = Mode.DIRECT
		vector = direction
		speed = move_speed
		target = Vector3.ZERO

	## Configura modo HOLD (quieto)
	func set_hold() -> void:
		mode = Mode.HOLD
		target = Vector3.ZERO
		vector = Vector3.ZERO
		speed = 0.0

	## Resetea al estado por defecto (NONE)
	func reset() -> void:
		mode = Mode.NONE
		target = Vector3.ZERO
		vector = Vector3.ZERO
		speed = 0.0


# ══════════════════════════════════════════════════════════════════
# BLOQUE 2: CombatIntent
# ══════════════════════════════════════════════════════════════════

## Intención de combate que un behavior comunica a BotBrain.
class CombatIntent:
	var aim_target: Vector3 = Vector3.ZERO    # Dónde apuntar
	var wants_to_shoot: bool = false           # Disparar este frame
	var strafe_direction: int = 1              # -1 o 1 para strafe

	## Resetea al estado por defecto
	func reset() -> void:
		aim_target = Vector3.ZERO
		wants_to_shoot = false
		# strafe_direction NO se resetea (persiste entre frames)


# ══════════════════════════════════════════════════════════════════
# BLOQUE 3: StateFlags
# ══════════════════════════════════════════════════════════════════

## Estado actual del bot. Lo escriben behaviors y BotBrain.
class StateFlags:
	var behavior_name: String = "idle"
	var is_stuck: bool = false
	var is_retreating: bool = false
	var time_in_behavior: float = 0.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES DEL CONTEXTO
# ══════════════════════════════════════════════════════════════════

var movement: MovementIntent = MovementIntent.new()
var combat: CombatIntent = CombatIntent.new()
var flags: StateFlags = StateFlags.new()


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

## Resetea los intents transitorios al inicio de cada frame.
## Los behaviors los reescribirán durante execute().
## Los StateFlags NO se resetean (persisten entre frames).
func reset_frame() -> void:
	movement.reset()
	combat.reset()


# ══════════════════════════════════════════════════════════════════
# VALIDACIÓN (resolve_context)
# ══════════════════════════════════════════════════════════════════

## Valida y normaliza el contexto antes de ejecutarlo.
## Previene estados imposibles o contradictorios.
## Se llama DESPUÉS de behavior.execute() y ANTES de execute_context().
##
## Reglas actuales:
## - NAVIGATE sin velocidad o sin target → HOLD
## - DIRECT sin vector o sin velocidad → HOLD
## - is_retreating sin DIRECT coherente → corrección
func resolve() -> void:
	# ── Validar MovementIntent ─────────────────────────────────
	match movement.mode:
		MovementIntent.Mode.NAVIGATE:
			if movement.speed <= 0.0 or movement.target == Vector3.ZERO:
				movement.set_hold()

		MovementIntent.Mode.DIRECT:
			if movement.speed <= 0.0 or movement.vector == Vector3.ZERO:
				movement.set_hold()

		MovementIntent.Mode.HOLD, MovementIntent.Mode.NONE:
			pass  # Siempre válidos

	# ── Validar coherencia retreat + movimiento ────────────────
	if flags.is_retreating and movement.mode == MovementIntent.Mode.NONE:
		# Retreat implica movimiento; si no hay intent, forzar HOLD
		movement.set_hold()


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func _to_string() -> String:
	var mode_names := {
		MovementIntent.Mode.NONE: "NONE",
		MovementIntent.Mode.NAVIGATE: "NAVIGATE",
		MovementIntent.Mode.DIRECT: "DIRECT",
		MovementIntent.Mode.HOLD: "HOLD",
	}
	return "Ctx[move=%s speed=%.1f shoot=%s stuck=%s retreat=%s]" % [
		mode_names.get(movement.mode, "?"),
		movement.speed,
		"Y" if combat.wants_to_shoot else "N",
		"Y" if flags.is_stuck else "N",
		"Y" if flags.is_retreating else "N",
	]
