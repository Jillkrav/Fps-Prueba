# scripts/map_manager.gd
# Se attacha al nodo raíz del mapa (Map1) para inicializar la partida.
# Reemplaza los CSGBox3D "Core Azul" / "Core Rojo" con instancias de core.tscn
# y configura los spawners para la partida de bots vs bots.
extends Node

## Si se attacha al nodo raiz del mapa (Map1), auto_start_match=true
## lo iniciara automaticamente. Como autoload, busca el mapa en el arbol.
@export var auto_start_match: bool = true
@export var auto_find_map: bool = true  # Busca el mapa como autoload

var _core_scene: PackedScene = preload("res://scenes/objectives/core.tscn")
var _map_root: Node = null

func _ready() -> void:
	if auto_start_match:
		if get_parent() == get_tree().root and auto_find_map:
			# Usado como autoload o singleton: buscar el mapa en el arbol
			call_deferred("_find_and_setup")
		else:
			# Usado como script attachado a un nodo del mapa
			_map_root = get_parent()
			call_deferred("_setup_match")

func _find_and_setup() -> void:
	# Buscar el mapa en la escena raiz (somos autoload, somos hijo de root)
	var map_node: Node = null
	for child in get_tree().root.get_children():
		if child == self:
			continue
		if "Map" in child.name or "map" in child.name:
			map_node = child
			break
	if not map_node:
		map_node = get_tree().get_first_node_in_group("map")
	# Buscar por nodo NavigationRegion3D como senial de que el mapa cargo
	if not map_node:
		var nav: Node = get_tree().root.find_child("NavigationRegion3D", true, false)
		if nav:
			map_node = nav.get_parent()
	
	if map_node:
		_map_root = map_node
		_setup_match()
	else:
		# Reintentar en el siguiente frame
		get_tree().create_timer(0.5).timeout.connect(_find_and_setup)

## Verificar y mejorar la navegación.
## Extiende el NavMesh para cubrir ambas bases (Z=-60 a Z=130).
## El Core Azul está en Z=-56 y el Core Rojo en Z=127, ambos fuera
## del NavMesh horneado original (Z=-35 a Z=135).
func _update_navigation() -> void:
	if not _map_root:
		return
	var nav_region: NavigationRegion3D = _map_root.find_child("NavigationRegion3D", true, false)
	if not nav_region:
		push_error("[MapManager] No se encontro NavigationRegion3D")
		return
	
	# Construir StaticBody3D temporales espejando las collision shapes
	# de los CSGBox3D (excluyendo techos). Se colocan bajo un Node3D
	# temporal hijo de nav_region; al parsear pasando temp_root como root,
	# el parser solo ve StaticBody3D (nunca los CSG), eliminando el warning.
	var temp_root: Node3D = Node3D.new()
	temp_root.name = "TempNavGeo"
	for child in _map_root.find_children("*", "CSGBox3D", true, false):
		if "oof" in child.name:  # "Roof" o "roof" — excluir techos
			continue
		var csg: CSGBox3D = child
		if not csg.use_collision:
			continue
		var body: StaticBody3D = StaticBody3D.new()
		var shape_node: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = csg.size
		shape_node.shape = box_shape
		body.add_child(shape_node)
		body.global_transform = csg.global_transform
		temp_root.add_child(body)
	nav_region.add_child(temp_root)
	
	var nav_mesh: NavigationMesh = NavigationMesh.new()
	nav_mesh.agent_radius = 0.5     # 2 * cell_size = 0.5 (exacto)
	nav_mesh.agent_height = 1.75    # 7 * cell_height = 1.75 (exacto)
	nav_mesh.agent_max_climb = 0.25 # 1 * cell_height = 0.25 (exacto)
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25     # Coincide con el mapa de navegación por defecto
	
	var source_geo: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	# parse_source_geometry_data recorre los hijos de temp_root únicamente.
	# Como solo contiene StaticBody3D, jamas parsea mallas CSG.
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_geo, temp_root)
	
	# Limpiar temporales antes de hornear
	temp_root.queue_free()
	
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geo)
	
	var poly_count: int = nav_mesh.get_polygon_count()
	if poly_count == 0:
		push_warning("[MapManager] No se generaron poligonos, se mantiene el NavMesh original")
		return
	
	nav_region.navigation_mesh = nav_mesh
	print("[MapManager] NavMesh horneado con %d poligonos (techos excluidos)" % poly_count)
	
	# Verificar cobertura 0.5s despues para dar tiempo al server de sincronizar
	get_tree().create_timer(0.5).timeout.connect(_check_navmesh_coverage.bind(nav_region))

func _check_navmesh_coverage(nav_region: NavigationRegion3D) -> void:
	if not is_instance_valid(nav_region):
		return
	var nav_map: RID = nav_region.get_navigation_map()
	if not NavigationServer3D.map_is_active(nav_map):
		printerr("[MapManager] ERROR: Navigation map NO esta activa!")
		return
	
	var test_positions: Dictionary = {
		"SpawnAzul1": Vector3(-6, 0, -11.7),
		"SpawnRojo1": Vector3(-6, 0, 72.2),
		"CoreAzul": Vector3(-9.26, 0, -56.58),
		"CoreRojo": Vector3(9.04, 0, 127.21),
	}
	for label in test_positions:
		var pos: Vector3 = test_positions[label]
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, pos)
		var dist: float = pos.distance_to(closest)
		var ok: String = "OK" if dist < 0.5 else "FUERA"
		print("[MapManager] NavMesh[%s]: %s dist=%.2f" % [ok, label, dist])
	
	# Also test a path query
	var test_path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, Vector3(0,0,0), Vector3(0,0,10), true)
	print("[MapManager] Path test (0,0,0)->(0,0,10): size=%d" % test_path.size())
	
	# Test from spawn to core
	var spawn_pos: Vector3 = test_positions.get("SpawnAzul1", Vector3())
	var core_pos: Vector3 = test_positions.get("CoreRojo", Vector3())
	if spawn_pos != Vector3() and core_pos != Vector3():
		var full_path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, spawn_pos, core_pos, true)
		print("[MapManager] Path spawn->core: size=%d" % full_path.size())

func _setup_match() -> void:
	# 1. Encontrar y reemplazar los cores CSGBox3D con core.tscn instancias
	_replace_cores()
	
	# 2. Asegurar que los spawners spawnen en sus equipos correctos
	_configure_spawners()
	
	# 2.5 Mejorar navegación
	_update_navigation()
	
	# 3. Conectar fin de partida
	if GameState.match_ended.is_connected(_on_match_ended):
		GameState.match_ended.disconnect(_on_match_ended)
	GameState.match_ended.connect(_on_match_ended)
	
	print("[MapManager] Mapa inicializado para partida de bots!")

func _replace_cores() -> void:
	if not _map_root:
		return
	# Buscar los nodos que representan cores
	var blue_core_node = _map_root.find_child("Core Azul", true, false)
	var red_core_node = _map_root.find_child("Core Rojo", true, false)
	
	# Si el core ya es una instancia de core.tscn (StaticBody3D con script core.gd),
	# solo asignamos el equipo. Si es CSGBox3D, lo reemplazamos.
	_asignar_o_reemplazar_core(blue_core_node, int(Enums.Equipo.AZUL))
	_asignar_o_reemplazar_core(red_core_node, int(Enums.Equipo.ROJO))

func _asignar_o_reemplazar_core(core_node: Node, team_id: int) -> void:
	if not core_node:
		return
	
	var team_name: String = GameState.nombre_equipo(team_id)
	
	if core_node is Core:
		# Ya es instancia de core.tscn, solo asignar equipo
		core_node.set("team", team_id)
		core_node.set("display_name", "Core %s" % team_name)
		core_node.call_deferred("_apply_team_appearance")
		print("[MapManager] Core %s configurado (team=%d)" % [team_name, team_id])
	elif core_node is CSGBox3D:
		# Reemplazar CSGBox3D con core.tscn
		var parent = core_node.get_parent()
		var pos = core_node.position
		var name_ = core_node.name
		parent.remove_child(core_node)
		core_node.queue_free()
		
		var new_core = _core_scene.instantiate()
		new_core.name = name_
		new_core.set("team", team_id)
		new_core.set("display_name", "Core %s" % team_name)
		parent.add_child(new_core)
		new_core.position = pos
		print("[MapManager] Core %s reemplazado (era CSGBox3D)" % team_name)

func _configure_spawners() -> void:
	if not _map_root:
		return
	# Registrar puntos de spawn en MatchManager.
	# Los spawners solo proporcionan puntos de spawn que el MatchManager usa
	# para asignar equipos. Cada base tiene su propio spawner (BlueSpawner / RedSpawner).
	var blue_spawner = _map_root.find_child("BlueSpawner", true, false)
	var red_spawner = _map_root.find_child("RedSpawner", true, false)
	
	# Fallback: si no se encuentran por nombre, buscar cualquier nodo
	# que tenga script de spawner (para compatibilidad con mapas antiguos)
	if not blue_spawner and not red_spawner:
		for child in _map_root.get_children():
			if child is Node3D and child.name.to_lower().find("spawn") >= 0:
				if child.has_method("get_spawn_points"):
					# Spawner mixto antiguo: asignar mitad al azul, mitad al rojo
					blue_spawner = child
					red_spawner = child
					print("[MapManager] Spawner mixto encontrado: %s. Asignando puntos por mitades." % child.name)
					break
	
	var spawner_script: Script = preload("res://scripts/spawner.gd")
	
	# ── Configurar BlueSpawner ──
	var blue_points: Array[Marker3D] = []
	if blue_spawner:
		# Asignar script si es un Node3D plano (sin script)
		# NOTA: set_script() ya activa _ready() -> _init_spawner() automaticamente
		if not blue_spawner.has_method("get_spawn_points"):
			blue_spawner.set_script(spawner_script)
			print("[MapManager] BlueSpawner: script asignado")
		# Forzar equipo AZUL en este spawner y validar que los puntos hijos
		# pertenezcan a este spawner y no a otro.
		blue_spawner.force_team = int(Enums.Equipo.AZUL)
		# Recolectar puntos de spawn directamente (SIEMPRE desde los hijos directos)
		for child in blue_spawner.get_children():
			if child is Marker3D:
				blue_points.append(child)
		print("[MapManager] BlueSpawner: %d puntos de spawn en %s" % [blue_points.size(), blue_spawner.name])
	
	# ── Configurar RedSpawner ──
	var red_points: Array[Marker3D] = []
	if red_spawner and red_spawner != blue_spawner:
		if not red_spawner.has_method("get_spawn_points"):
			red_spawner.set_script(spawner_script)
			print("[MapManager] RedSpawner: script asignado")
		red_spawner.force_team = int(Enums.Equipo.ROJO)
		for child in red_spawner.get_children():
			if child is Marker3D:
				red_points.append(child)
		print("[MapManager] RedSpawner: %d puntos de spawn en %s" % [red_points.size(), red_spawner.name])
	elif red_spawner == blue_spawner and blue_spawner:
		# Mismo spawner para ambos: dividir puntos entre equipos
		var all_markers: Array[Marker3D] = []
		for child in blue_spawner.get_children():
			if child is Marker3D:
				all_markers.append(child)
		# Repartir: la mitad al azul, la mitad al rojo
		var marker_count: float = all_markers.size() as float
		var half: int = int(marker_count * 0.5)
		for i in all_markers.size():
			if i < half:
				blue_points.append(all_markers[i])
			else:
				red_points.append(all_markers[i])
		print("[MapManager] Spawner mixto: %d puntos divididos (Azul=%d, Rojo=%d)" % [all_markers.size(), blue_points.size(), red_points.size()])
	
	# ── Validacion: asegurar que ambos equipos tengan al menos 1 punto ──
	if blue_points.is_empty():
		push_warning("[MapManager] BlueSpawner no tiene puntos de spawn!")
	if red_points.is_empty():
		push_warning("[MapManager] RedSpawner no tiene puntos de spawn!")
	
	# Registrar todos los puntos en MatchManager
	MatchManager.registrar_spawn_points(blue_points, red_points)
	print("[MapManager] Spawn points registrados en MatchManager: Azul=%d, Rojo=%d" % [blue_points.size(), red_points.size()])

func _on_match_ended(winning_team: int) -> void:
	print("[MapManager] Partida terminada! Ganador: %s" % GameState.nombre_equipo(winning_team))
	# Limpiar estado de MatchManager
	MatchManager.reset_match()
