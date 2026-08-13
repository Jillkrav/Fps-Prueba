# scripts/ai/combat_command.gd
# ──────────────────────────────────────────────────────────────────
# COMBAT COMMAND — Recurso de comando de combate
#
# Escrito por: DecisionSystem (FSM states)
# Leído por:   CombatSystem
#
# Representa una orden de combate que el DecisionSystem emite
# y el CombatSystem ejecuta. CombatSystem traduce esto a
# aim_rotation, modo de fuego, y solicitudes de evasión.
#
# ── CAMPOS ──
# engage        → ¿Debemos entrar en modo combate?
# target_id     → ID de la entidad objetivo (para tracking)
# fire_mode     → 0=primario, 1=alterno
# aim_at_position → Dónde apuntar (mundo)
# force_fire    → Disparar aunque no esté perfectamente alineado
# cease_fire    → Dejar de disparar inmediatamente
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name CombatCommand


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## ¿Debemos entrar en modo combate?
var engage: bool = false

## ID de la entidad objetivo (para tracking en CombatSystem)
var target_id: int = -1

## Modo de fuego: 0=primario, 1=alterno
var fire_mode: int = 0

## Posición mundial a la que apuntar
var aim_at_position: Vector3 = Vector3.ZERO

## Forzar disparo aunque no esté perfectamente alineado
var force_fire: bool = false

## Cesación inmediata de fuego
var cease_fire: bool = false

## Solicita una rotación reactiva sin abrir fuego. La escribe DecisionSystem
## y la consume CombatSystem, que conserva la propiedad exclusiva del aim.
var attention_enabled: bool = false

## Velocidad angular máxima de atención en radianes por segundo.
## 0.0 mantiene la puntería instantánea existente para combate normal.
var attention_turn_speed: float = 0.0

## Tiempo máximo que CombatSystem mantendrá esta atención antes de liberarla.
var attention_timeout: float = 0.0


# ══════════════════════════════════════════════════════════════════
# MÉTODOS DE CONFIGURACIÓN
# ══════════════════════════════════════════════════════════════════

## Configura combate ofensivo: apuntar y disparar
func set_engage(target_pos: Vector3, f_mode: int = 0) -> void:
	engage = true
	aim_at_position = target_pos
	fire_mode = f_mode
	cease_fire = false

## Configura solo apuntar (sin disparar)
func set_aim(target_pos: Vector3) -> void:
	engage = false
	aim_at_position = target_pos
	cease_fire = false


## Configura una atención visual con giro limitado y sin disparo.
func set_attention(target_pos: Vector3, turn_speed: float, timeout: float) -> void:
	engage = false
	aim_at_position = target_pos
	cease_fire = true
	attention_enabled = true
	attention_turn_speed = maxf(turn_speed, 0.0)
	attention_timeout = maxf(timeout, 0.0)


## Detener fuego
func set_cease_fire() -> void:
	cease_fire = true
	engage = false
	force_fire = false

## Resetea al estado por defecto
func reset() -> void:
	engage = false
	target_id = -1
	fire_mode = 0
	aim_at_position = Vector3.ZERO
	force_fire = false
	cease_fire = false
	attention_enabled = false
	attention_turn_speed = 0.0
	attention_timeout = 0.0


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func _to_string() -> String:
	return "CombatCmd[engage=%s fire=%d cease=%s]" % [
		"Y" if engage else "N",
		fire_mode,
		"Y" if cease_fire else "N",
	]
