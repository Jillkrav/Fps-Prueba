# scripts/ai/movement_command.gd
# ──────────────────────────────────────────────────────────────────
# MOVEMENT COMMAND — Recurso de comando de movimiento
#
# Escrito por: DecisionSystem / BotBrain
# Leído por:   MovementSystem
#
# Representa una orden de movimiento que el DecisionSystem emite
# y el MovementSystem ejecuta. MovementSystem es el ÚNICO que
# traduce esto a velocity.
#
# ── MODOS ──
# NONE      → Sin comando (MovementSystem decide)
# NAVIGATE  → Pathfinding hacia target_position
# DIRECT    → Vector directo (strafe, retreat, etc.)
# HOLD      → Quieto intencional, frenar suavemente
# DODGE     → Impulso evasivo (dodge)
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name MovementCommand


# ══════════════════════════════════════════════════════════════════
# ENUM — Modos de movimiento
# ══════════════════════════════════════════════════════════════════

enum Mode {
	NONE = 0,      # Sin comando (MovementSystem no interviene)
	NAVIGATE = 1,  # Pathfinding hacia target_position
	DIRECT = 2,    # Vector directo (direction * speed)
	HOLD = 3,      # Quieto intencional
	DODGE = 4,     # Evasión lateral
	STOP = 5,      # Frenada inmediata
}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

var mode: int = Mode.NONE
var target_position: Vector3 = Vector3.ZERO  # Para NAVIGATE
var direction: Vector3 = Vector3.ZERO        # Para DIRECT
var speed: float = 0.0
var jump: bool = false                       # ¿Saltar este frame?
var jump_velocity: float = 5.0              # Velocidad de salto
var sprint: bool = false                     # ¿Correr?
var dodge_direction: Vector3 = Vector3.ZERO  # Para DODGE
var dodge_impulse: float = 10.0             # Fuerza de evasión


# ══════════════════════════════════════════════════════════════════
# MÉTODOS DE CONFIGURACIÓN
# ══════════════════════════════════════════════════════════════════

## Configura modo NAVIGATE (pathfinding)
func set_navigate(target_pos: Vector3, move_speed: float) -> void:
	mode = Mode.NAVIGATE
	target_position = target_pos
	speed = move_speed
	direction = Vector3.ZERO

## Configura modo DIRECT (vector directo, ej: strafe)
func set_direct(dir: Vector3, move_speed: float) -> void:
	mode = Mode.DIRECT
	direction = dir
	speed = move_speed
	target_position = Vector3.ZERO

## Configura modo HOLD (quieto intencional)
func set_hold() -> void:
	mode = Mode.HOLD
	target_position = Vector3.ZERO
	direction = Vector3.ZERO
	speed = 0.0

## Configura modo DODGE (evasión)
func set_dodge(dir: Vector3, impulse: float = 10.0) -> void:
	mode = Mode.DODGE
	dodge_direction = dir
	dodge_impulse = impulse
	speed = 0.0

## Configura modo STOP (frenada inmediata)
func set_stop() -> void:
	mode = Mode.STOP
	target_position = Vector3.ZERO
	direction = Vector3.ZERO
	speed = 0.0

## Solicita un salto
func request_jump(velocity: float = 5.0) -> void:
	jump = true
	jump_velocity = velocity

## Resetea al estado por defecto (NONE)
func reset() -> void:
	mode = Mode.NONE
	target_position = Vector3.ZERO
	direction = Vector3.ZERO
	speed = 0.0
	jump = false
	jump_velocity = 5.0
	sprint = false
	dodge_direction = Vector3.ZERO
	dodge_impulse = 10.0


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func _to_string() -> String:
	var mode_names := {
		Mode.NONE: "NONE",
		Mode.NAVIGATE: "NAV",
		Mode.DIRECT: "DIR",
		Mode.HOLD: "HOLD",
		Mode.DODGE: "DODGE",
		Mode.STOP: "STOP",
	}
	return "Cmd[%s speed=%.1f jump=%s]" % [
		mode_names.get(mode, "?"),
		speed,
		"Y" if jump else "N",
	]
