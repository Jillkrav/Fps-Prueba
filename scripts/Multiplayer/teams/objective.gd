# scripts/ai/objective.gd
# ──────────────────────────────────────────────────────────────────
# OBJECTIVE — Recurso de objetivo táctico (FASE 6)
#
# Representa un objetivo que el equipo puede perseguir.
# Creado por TeamAI y consumido por los estados de la FSM.
#
# ── TIPOS ──
# ATTACK  → Destruir/atacar un objetivo enemigo (core, bot, posición)
# DEFEND  → Proteger un punto/entidad aliada
# CAPTURE → Tomar control de un punto del mapa
# ESCORT  → Acompañar a una unidad aliada
# RETURN  → Volver a la base
# HOLD    → Mantener posición actual
# ──────────────────────────────────────────────────────────────────
extends Resource
class_name Objective


# ══════════════════════════════════════════════════════════════════
# ENUMS
# ══════════════════════════════════════════════════════════════════

## Tipos de objetivo disponibles
enum Type {
	ATTACK = 0,   # Atacar/destruir objetivo
	DEFEND = 1,   # Defender un punto/entidad
	CAPTURE = 2,  # Capturar un punto
	ESCORT = 3,   # Acompañar unidad
	RETURN = 4,   # Regresar a base
	HOLD = 5,     # Mantener posición
}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Identificador único del objetivo (ej: "core_red_attack")
@export var objective_id: String = ""

## Tipo de objetivo
@export var objective_type: int = Type.ATTACK

## Nodo objetivo (opcional — ej: el Core enemigo)
@export var target_node: NodePath = NodePath()

## Posición mundial del objetivo
@export var position: Vector3 = Vector3.ZERO

## Equipo al que pertenece este objetivo (quién lo creó)
@export var team: int = -1

## Prioridad (más alto = más urgente)
@export var priority: float = 1.0

## Radio dentro del cual se considera el objetivo completado
@export var completion_radius: float = 4.0

## ¿Ya se completó?
@export var is_completed: bool = false

## Objetivo alternativo si este falla/se destruye
@export var fallback_objective: String = ""

## Nombre legible para debug
@export var display_name: String = "Objective"


# ══════════════════════════════════════════════════════════════════
# MÉTODOS
# ══════════════════════════════════════════════════════════════════

## Crea un objetivo ATTACK hacia una posición
static func attack(target_pos: Vector3, team_id: int, obj_id: String = "") -> Objective:
	var obj := Objective.new()
	obj.objective_id = obj_id if obj_id != "" else "attack_%s" % [str(randi())]
	obj.objective_type = Type.ATTACK
	obj.position = target_pos
	obj.team = team_id
	obj.display_name = "Atacar"
	return obj


## Crea un objetivo DEFEND para proteger una posición
static func defend(target_pos: Vector3, team_id: int, obj_id: String = "") -> Objective:
	var obj := Objective.new()
	obj.objective_id = obj_id if obj_id != "" else "defend_%s" % [str(randi())]
	obj.objective_type = Type.DEFEND
	obj.position = target_pos
	obj.team = team_id
	obj.display_name = "Defender"
	return obj


## Crea un objetivo RETURN a la base
static func return_to_base(target_pos: Vector3, team_id: int) -> Objective:
	var obj := Objective.new()
	obj.objective_id = "return_%s_%s" % [GameState.nombre_equipo(team_id), str(randi())]
	obj.objective_type = Type.RETURN
	obj.position = target_pos
	obj.team = team_id
	obj.display_name = "Retornar"
	return obj


## Crea un objetivo HOLD en la posición actual
static func hold(position_to_hold: Vector3, team_id: int) -> Objective:
	var obj := Objective.new()
	obj.objective_id = "hold_%s" % [str(randi())]
	obj.objective_type = Type.HOLD
	obj.position = position_to_hold
	obj.team = team_id
	obj.display_name = "Mantener"
	return obj


func _to_string() -> String:
	return "Obj[%s | %s | prior=%.1f done=%s]" % [
		display_name,
		_type_name(),
		priority,
		"Y" if is_completed else "N",
	]


func _type_name() -> String:
	match objective_type:
		Type.ATTACK:  return "ATTACK"
		Type.DEFEND:  return "DEFEND"
		Type.CAPTURE: return "CAPTURE"
		Type.ESCORT:  return "ESCORT"
		Type.RETURN:  return "RETURN"
		Type.HOLD:    return "HOLD"
	return "?"
