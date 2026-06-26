# scripts/spawner.gd
# Spawner universal: usa solo npc.tscn y asigna armas aleatorias del config.
# Los equipos se manejan por ID numerico (GameState.Equipo).
extends Node3D
class_name NpcSpawner

@export var spawn_interval:        float = 8.0
@export var spawn_count_per_cycle: int   = 2
@export var min_alive_npcs: int = 4
@export var spawn_points_paths:    Array[NodePath] = []

## Si es true, el spawner no genera nada
@export var disabled: bool = false

## Forzar un equipo específico: -1 = mezclado, 1 = AZUL, 2 = ROJO
@export var force_team: int = -1

var npc_scene: PackedScene = preload("res://scenes/npcs/npc.tscn")

var spawn_timer: Timer
var spawn_points: Array[Marker3D] = []
var hud: CanvasLayer = null
var _selector_abierto: bool = false

func _ready() -> void:
	if disabled:
		return
	_init_spawner()

## Metodo publico para inicializar el spawner cuando el script se asigna
## dinamicamente via set_script() desde MapManager.
func _init_spawner() -> void:
	for path in spawn_points_paths:
		var node: Node = get_node_or_null(path)
		if node is Marker3D:
			spawn_points.append(node)

	if spawn_points.is_empty():
		for child in get_children():
			if child is Marker3D:
				spawn_points.append(child)

	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.one_shot  = false
	spawn_timer.autostart = true
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_timeout)

	hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if not hud:
		var hud_nodes: Array = get_tree().get_nodes_in_group("hud")
		if not hud_nodes.is_empty():
			hud = hud_nodes[0] as CanvasLayer

	call_deferred("spawn_wave")
	call_deferred("spawn_wave") # Doble wave para asegurar pelea inmediata

func pausar_spawn() -> void:
	_selector_abierto = true
	if spawn_timer and not spawn_timer.is_paused():
		spawn_timer.set_paused(true)

func reanudar_spawn() -> void:
	_selector_abierto = false
	if spawn_timer and spawn_timer.is_paused():
		spawn_timer.set_paused(false)

func _process(_delta: float) -> void:
	if disabled or _selector_abierto:
		return
	if spawn_timer and not spawn_timer.is_stopped():
		if hud and hud.has_method("update_spawn_timer"):
			hud.update_spawn_timer(spawn_timer.time_left)
		else:
			hud = get_tree().get_first_node_in_group("hud") as CanvasLayer

func _on_spawn_timeout() -> void:
	if disabled or _selector_abierto:
		return
	if is_instance_valid(GameState) and not GameState.match_active:
		return
	var alive: int = _count_alive_team_npcs()
	if alive < min_alive_npcs:
		spawn_wave()

func _count_alive_team_npcs() -> int:
	var count: int = 0
	var npcs: Array[Node] = get_tree().get_nodes_in_group("npc")
	for npc in npcs:
		if not is_instance_valid(npc):
			continue
		if npc.get("is_dead") == true:
			continue
		var npc_team: int = npc.get("equipo_id") if "equipo_id" in npc else -1
		if force_team >= 0:
			if npc_team == force_team:
				count += 1
		else:
			count += 1
	return count

func spawn_wave() -> void:
	if disabled or spawn_points.is_empty():
		return
	if not is_inside_tree() or not get_parent().is_inside_tree():
		return
	if is_instance_valid(GameState) and not GameState.match_active:
		return

	# Equipo del jugador por ID numerico
	var equipo_jugador: int = GameState.player_team

	# Equipo enemigo: si el jugador es Azul -> Rojo, si es Rojo -> Azul.
	# Si es Espectador (0), los NPCs spawnean como Rojo por defecto.
	var _equipo_enemigo: int
	match equipo_jugador:
		int(Enums.Equipo.AZUL):
			_equipo_enemigo = int(Enums.Equipo.ROJO)
		int(Enums.Equipo.ROJO):
			_equipo_enemigo = int(Enums.Equipo.AZUL)
		_:
			# Espectador u otro: spawnear Rojos por defecto
			_equipo_enemigo = int(Enums.Equipo.ROJO)

	# Lista de armas disponibles desde ConfigManager
	var armas_lista: Array[String] = ConfigManager.get_nombres_armas()
	if armas_lista.is_empty():
		armas_lista = [""]

	var count: int = 0
	for _i in range(spawn_count_per_cycle):
		var point: Marker3D = spawn_points[randi() % spawn_points.size()]
		if not point.is_inside_tree():
			continue

		var npc: NpcBase = npc_scene.instantiate() as NpcBase
		if not npc:
			continue

		# Asignar equipo
		if force_team >= 0:
			# Forzar un equipo específico (para spawners por equipo)
			npc.equipo_id = force_team
		else:
			# Mezclar Azul y Rojo para que pelen entre si
			npc.equipo_id = int(Enums.Equipo.AZUL) if count % 2 == 0 else int(Enums.Equipo.ROJO)
			count += 1

		npc.nombre_arma = armas_lista[randi() % armas_lista.size()]

		# npc.experiencia = Enums.Experiencia.values().pick_random()
		# npc.rol = Enums.Rol.values().pick_random()

		var spawn_pos: Vector3 = point.global_transform.origin + Vector3(
			randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)
		)
		get_parent().add_child(npc)
		npc.global_transform.origin = spawn_pos
