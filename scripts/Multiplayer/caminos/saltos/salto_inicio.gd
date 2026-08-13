@tool
extends Area3D
class_name SaltoInicio

@export var jump_id: StringName
@export var target_finish: NodePath
@export var permitted_roles: Array[CaminoBot.Role] = []
## Activo por defecto: el trigger solo inicia el salto si BotBase valida
## distancia, suelo y trayectoria en MovementSystem.
@export var enabled: bool = true
@export_range(0.0, 10.0, 0.1) var cooldown_per_bot: float = 1.0

var _cooldowns: Dictionary = {}


func _on_body_entered(body: Node3D) -> void:
	if not enabled or not body.has_method("start_authored_jump"):
		return
	if not _can_use(body):
		return
	var finish: SaltoFin = get_node_or_null(target_finish) as SaltoFin
	if finish == null:
		push_warning("SaltoInicio %s no tiene SaltoFin asignado." % name)
		return
	_cooldowns[body.get_instance_id()] = Time.get_ticks_msec() / 1000.0
	body.start_authored_jump(finish)


func _can_use(body: Node3D) -> bool:
	var body_id: int = body.get_instance_id()
	var last_time: float = _cooldowns.get(body_id, -INF)
	if Time.get_ticks_msec() / 1000.0 - last_time < cooldown_per_bot:
		return false
	if permitted_roles.is_empty():
		return true
	if body is not BotBase:
		return false

	var bot: BotBase = body as BotBase
	return _get_route_role_for_bot(bot.rol) in permitted_roles


func _get_route_role_for_bot(bot_role: int) -> int:
	match bot_role:
		Roles.Type.ASALTO:
			return CaminoBot.Role.ASSAULT
		Roles.Type.FLANQUEADOR:
			return CaminoBot.Role.FLANKER
		Roles.Type.DEFENSOR, Roles.Type.FRANCOTIRADOR:
			return CaminoBot.Role.DEFENDER
		Roles.Type.PATRULLADOR:
			return CaminoBot.Role.PATROL
		Roles.Type.APOYO:
			return CaminoBot.Role.SUPPORT
		_:
			return CaminoBot.Role.ASSAULT
