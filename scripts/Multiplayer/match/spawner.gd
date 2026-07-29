# scripts/spawner.gd
# Spawner simplificado: SOLO proporciona puntos de aparicion para el MatchManager.
# Ya no crea bots ni gestiona timers de spawn.
# El MatchManager (autoload) se encarga de todo: creacion de bots,
# asignacion a equipos, respawn, y limites de jugadores.
extends Node3D
class_name NpcSpawner

## Forzar un equipo especifico: -1 = mezclado, 1 = AZUL, 2 = ROJO
## Si se asigna un equipo, get_spawn_points() solo devolvera puntos
## si el equipo solicitante coincide.
@export var force_team: int = -1

## Puntos de spawn hijos directos (se auto-detectan)
var spawn_points: Array[Marker3D] = []

## Si es true, el spawner no se usa
@export var disabled: bool = false

func _ready() -> void:
	if disabled:
		return
	_init_spawner()

## Inicializa los puntos de spawn. Se llama externamente si el script
## se asigna dinamicamente via set_script() desde MapManager.
func _init_spawner() -> void:
	# Limpiar por si se llama multiple veces (defensivo)
	spawn_points.clear()
	# Recolectar hijos Marker3D como puntos de spawn
	for child in get_children():
		if child is Marker3D:
			spawn_points.append(child)
	
	if spawn_points.is_empty():
		push_warning("[Spawner] %s no tiene hijos Marker3D como puntos de spawn" % name)
		return
	
	print("[Spawner] %s inicializado con %d puntos de spawn. Team=%s" % [
		name, spawn_points.size(), 
		GameState.nombre_equipo(force_team) if force_team >= 0 else "Mixto"
	])
	
	# Auto-registrar puntos de spawn en MatchManager si el equipo esta definido
	_auto_register_match_manager()

## Auto-registra los puntos de spawn en MatchManager.
## Esto permite que los spawners funcionen incluso si MapManager
## no logra ejecutar _configure_spawners() a tiempo.
func _auto_register_match_manager() -> void:
	if force_team < 0:
		return  # Equipo mixto, no puede auto-registrarse solo
	if spawn_points.is_empty():
		return
	if not MatchManager:
		push_warning("[Spawner] MatchManager no disponible, no se pueden registrar spawn points")
		return
	
	MatchManager.registrar_spawn_points_equipo(force_team, spawn_points)
	print("[Spawner] %s auto-registrado en MatchManager: %d puntos para %s" % [
		name, spawn_points.size(), GameState.nombre_equipo(force_team)
	])

## Devuelve los puntos de spawn. Si force_team >= 0 y el equipo
## solicitante no coincide, devuelve array vacio (seguridad extra).
func get_spawn_points(requesting_team: int = -1) -> Array[Marker3D]:
	# Si este spawner es de un equipo especifico, validar que el
	# equipo solicitante coincida
	if force_team >= 0 and requesting_team >= 0 and requesting_team != force_team:
		return []
	return spawn_points.duplicate()

## Versión sin filtro de equipo para compatibilidad.
## MatchManager la usa desde _configure_spawners() para recolectar
## puntos sin filtrar (el filtrado ocurre en registrar_spawn_points).
func get_spawn_points_all() -> Array[Marker3D]:
	return spawn_points.duplicate()
