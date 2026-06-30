# scripts/ai/bot_behavior.gd
# ──────────────────────────────────────────────────────────────────
# CLASE BASE PARA COMPORTAMIENTOS MODULARES DE NPC
#
# Cada comportamiento (behavior) es un módulo independiente que
# compite por ser ejecutado. El BotBrain evalúa todos los behaviors
# cada frame y ejecuta el de mayor prioridad.
#
# ── CÓMO EXTENDER ──
# 1. Crea un nuevo script que extienda BotBehavior
# 2. Implementa get_priority() y execute()
# 3. Opcional: enter(), exit() para transiciones limpias
# 4. Regístralo en BotBrain._register_behaviors()
#
# ── COMPORTAMIENTO PREDEFINIDO ──
# - get_priority() retorna -1 (nunca se ejecuta)
# - execute() no hace nada
# - enter() / exit() no hacen nada
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name BotBehavior


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Nombre legible del comportamiento (para debug)
var behavior_name: String = "abstract"


# ══════════════════════════════════════════════════════════════════
# INTERFAZ PÚBLICA — Sobrescribir en subclases
# ══════════════════════════════════════════════════════════════════

## Retorna la prioridad de este comportamiento (0+ = ejecutar,
## -1 = no debe ejecutarse). El brain ejecuta el de mayor prioridad.
func get_priority(_brain: BotBrain) -> float:
	return -1.0


## Llamado cuando este behavior se convierte en el activo.
## Útil para inicializar estado específico (ej: resetear timers).
func enter(_brain: BotBrain) -> void:
	pass


## Llamado cada frame mientras este behavior está activo.
## Aquí va la lógica principal del comportamiento.
func execute(_brain: BotBrain, _delta: float) -> void:
	pass


## Llamado cuando este behavior deja de ser el activo.
## Útil para limpiar estado o notificar al brain.
func exit(_brain: BotBrain) -> void:
	pass
