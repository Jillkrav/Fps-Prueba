class_name StoryNpcDamageTurn
extends Node

## Componente reutilizable para que cualquier NPC gire de forma SUAVE (no
## instantánea) hacia el origen del daño cuando recibe un impacto.
##
## CÓMO USARLO EN UN NPC (nuevo o futuro):
##   1. Añade este script como hijo del NPC (CharacterBody3D / Node3D) y
##      nómbralo "DamageTurn" (ese nombre lo busca el NPC en take_damage).
##   2. En su take_damage(), con la posición mundial del origen del daño:
##        _turn_to_damage_source(from_position)   # o directamente:
##        $DamageTurn.trigger(from_position)
##   3. Ajusta turn_speed (grados/s) y turn_duration (s) en el Inspector.
##
## El giro solo rota el YAW del NPC (eje Y): nunca afecta al movimiento ni a
## otras rotaciones. Se desactiva solo al llegar al ángulo o al agotar
## turn_duration, devolviendo el control al comportamiento normal del NPC.

## Velocidad de giro en grados por segundo (constante → suave, no instantáneo).
@export_range(60.0, 720.0, 15.0) var turn_speed: float = 360.0
## Tiempo máximo (s) dedicado a girar hacia el origen del daño antes de
## devolver el control a la IA del NPC.
@export_range(0.1, 2.0, 0.05) var turn_duration: float = 0.5

var _turn_from: Vector3 = Vector3.INF
var _turn_timer: float = 0.0


## Inicia el giro hacia `from_position` (posición mundial del origen del daño).
## Ignora posiciones no finitas / desconocidas (Vector3.INF).
func trigger(from_position: Vector3) -> void:
	if from_position == Vector3.INF or not from_position.is_finite():
		return
	var npc := get_parent() as Node3D
	if npc == null:
		return
	_turn_from = from_position
	_turn_timer = turn_duration
	set_physics_process(true)


func _ready() -> void:
	# Solo se procesa mientras haya un giro pendiente (ahorra trabajo con muchos NPCs).
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	var npc := get_parent() as Node3D
	if npc == null:
		set_physics_process(false)
		return
	_turn_timer -= delta
	if _turn_timer <= 0.0:
		set_physics_process(false)
		return
	var to_source: Vector3 = _turn_from - npc.global_position
	to_source.y = 0.0
	if to_source.length_squared() < 0.0001:
		set_physics_process(false)
		return
	var target_yaw: float = atan2(-to_source.x, -to_source.z)
	var yaw_diff: float = wrapf(target_yaw - npc.rotation.y, -PI, PI)
	var max_step: float = deg_to_rad(turn_speed) * delta
	npc.rotation.y += clampf(yaw_diff, -max_step, max_step)
	# ¿Ya orientado hacia el origen? Termina el giro para no pelear con la IA.
	if absf(yaw_diff) <= deg_to_rad(1.0):
		set_physics_process(false)
