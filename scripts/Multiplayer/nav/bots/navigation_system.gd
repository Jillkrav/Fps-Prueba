# scripts/ai/navigation/navigation_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE NAVEGACIÓN — Adaptador del NavigationAgent3D
#
# La selección táctica de rutas authored vive en BotAuthoredRouteNavigator.
# Este componente conserva únicamente la API de navegación usada por los
# sistemas de movimiento y estados de los bots.
# ──────────────────────────────────────────────────────────────────
extends Node
class_name NavigationSystem


## Referencia al bot dueño.
var bot: BotBase:
	get:
		if _bot == null:
			_bot = get_parent() as BotBase
		return _bot
var _bot: BotBase = null

## NavigationAgent del bot (buscado como hijo de BotBase).
var agent: NavigationAgent3D = null


func _ready() -> void:
	_bot = get_parent() as BotBase
	if bot != null:
		agent = bot.get_node_or_null("NavigationAgent3D") as NavigationAgent3D


## ¿La navegación actual ha llegado a su destino?
func is_navigation_finished() -> bool:
	if agent == null:
		return true
	return agent.is_navigation_finished()


## Obtiene la siguiente posición del camino calculado por NavigationAgent3D.
func get_next_path_position() -> Vector3:
	if agent == null:
		return Vector3.ZERO
	return agent.get_next_path_position()


## Establece el destino del NavigationAgent3D.
func set_destination(target: Vector3) -> void:
	if agent == null:
		return
	agent.target_position = target
