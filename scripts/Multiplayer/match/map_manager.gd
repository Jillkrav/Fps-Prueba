# scripts/map_manager.gd
# Se attacha al nodo raíz del mapa (Map1) para inicializar la partida.
# Reemplaza los CSGBox3D "Core Azul" / "Core Rojo" con instancias de core.tscn
# y configura los spawners para la partida de bots vs bots.
extends Node

## Si se attacha al nodo raiz del mapa (Map1), auto_start_match=true
## lo iniciara automaticamente. Como autoload, busca el mapa en el arbol.
@export var auto_start_match: bool = true
@export var auto_find_map: bool = true  # Busca el mapa como autoload

var _core_scene: PackedScene = preload("res://scenes/Multiplayer/objetos/objectives/core.tscn")
var _base_anchor_scene: PackedScene = preload("res://scenes/Multiplayer/objetos/objectives/base_anchor.tscn")
var _debug_zone_scene: PackedScene = preload("res://scenes/Compartido/debug/debug_map_zone.tscn")
var _map_root: Node = null

## Dimensiones físicas de NpcBase. El NavMesh debe usar la misma holgura que
## la cápsula para no planificar pasos que el cuerpo real no puede completar.
# Los valores de bake se ajustan a los vóxeles: ceil(0.65 / 0.30) * 0.30 = 0.90
# y ceil(1.80 / 0.25) * 0.25 = 2.00. Así no se pierde holgura ni se emiten
# advertencias de precisión durante el horneado.
const BOT_NAVMESH_AGENT_RADIUS: float = 0.9
const BOT_NAVMESH_AGENT_HEIGHT: float = 2.0
const BOT_NAVMESH_CELL_SIZE: float = 0.3
const BOT_NAVMESH_CELL_HEIGHT: float = 0.25

func _ready() -> void:
	if _is_story_mode():
		return
	if auto_start_match:
		if get_parent() == get_tree().root and auto_find_map:
			# Usado como autoload o singleton: buscar el mapa en el arbol
			call_deferred("_find_and_setup")
		else:
			# Usado como script attachado a un nodo del mapa
			_map_root = get_parent()
			call_deferred("_setup_match")

## Reactiva la detección tras volver de Historia antes de cargar un mapa MP.
func prepare_multiplayer_map_setup() -> void:
	if _is_story_mode():
		return
	call_deferred("_find_and_setup")


func _find_and_setup() -> void:
	if _is_story_mode():
		return
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
	# El radio se alinea con la cápsula (0.65) para que el pathfinding deje
	# espacio real alrededor de muros. El motor cuantiza internamente según
	# cell_size cuando hornea; nunca reducimos la holgura por debajo del cuerpo.
	nav_mesh.agent_radius = BOT_NAVMESH_AGENT_RADIUS
	nav_mesh.agent_height = BOT_NAVMESH_AGENT_HEIGHT
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.cell_size = BOT_NAVMESH_CELL_SIZE
	nav_mesh.cell_height = BOT_NAVMESH_CELL_HEIGHT
	
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

	# No continuar con rutas de diagnóstico cuando el NavMesh devuelve el vector
	# cero para posiciones que quedaron fuera del horneado.
	for label in test_positions:
		var diagnostic_point: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, test_positions[label])
		if diagnostic_point == Vector3.ZERO:
			return
	
	# Consultas de diagnóstico desactivadas: este mapa mantiene puntos de spawn y
	# core fuera del NavMesh horneado, y NavigationServer3D registra errores al
	# intentar trazar entre ellos. La validación real ocurre al emitir destinos
	# authored válidos desde MovementSystem/NavigationAgent3D.

## Configura una red macro mínima entre los corredores authored del mapa.
## Los `CaminoBot` siguen guiando la intención; NavigationAgent3D conserva el
## recorrido físico, los recursos y las coberturas como desvíos de corto alcance.
func _configure_bot_route_graph() -> void:
	if _map_root == null:
		return
	var route_paths: Dictionary = {
		&"blue_hub": NodePath("NavigationRegion3D/Caminos (nav)/Base azul/CaminoGenericoBase"),
		&"red_hub": NodePath("NavigationRegion3D/Caminos (nav)/Base roja/CaminoGenericoBase"),
		&"assault_red_blue": NodePath("NavigationRegion3D/Caminos (nav)/General/Asalto/CaminoAsaltoBase"),
		&"assault_blue_red_a": NodePath("NavigationRegion3D/Caminos (nav)/General/Asalto/CaminoAsaltoBase2"),
		&"assault_blue_red_b": NodePath("NavigationRegion3D/Caminos (nav)/General/Asalto/CaminoAsaltoBase3"),
		&"flank_blue_red_a": NodePath("NavigationRegion3D/Caminos (nav)/General/Flanco/CaminoFlancoBase"),
		&"flank_red_blue_a": NodePath("NavigationRegion3D/Caminos (nav)/General/Flanco/CaminoFlancoBase2"),
		&"flank_blue_red_b": NodePath("NavigationRegion3D/Caminos (nav)/General/Flanco/CaminoFlancoBase3"),
		&"flank_red_blue_b": NodePath("NavigationRegion3D/Caminos (nav)/General/Flanco/CaminoFlancoBase4"),
	}
	var routes: Dictionary = {}
	for route_id: StringName in route_paths:
		var route_path: NodePath = route_paths[route_id] as NodePath
		var route: CaminoBot = _map_root.get_node_or_null(route_path) as CaminoBot
		if route == null or not route.is_usable():
			return
		routes[route_id] = route

	# Las rutas abiertas se recorren en su dirección authored. Así la salida de
	# una base no se puede tomar al revés y terminar en la conexión equivocada.
	for route_id: StringName in routes:
		var route: CaminoBot = routes[route_id] as CaminoBot
		route.reverse_allowed = false
		route.route_id = route_id

	_configure_route_link(routes, &"blue_hub", [
		&"assault_blue_red_a", &"assault_blue_red_b",
		&"flank_blue_red_a", &"flank_blue_red_b",
	], [1.2, 0.8, 1.0, 0.8])
	_configure_route_link(routes, &"red_hub", [&"assault_red_blue"], [1.0])
	_configure_route_link(routes, &"assault_red_blue", [&"blue_hub"], [1.0])
	_configure_route_link(routes, &"assault_blue_red_a", [&"red_hub"], [1.0])
	_configure_route_link(routes, &"assault_blue_red_b", [&"red_hub"], [1.0])
	_configure_route_link(routes, &"flank_blue_red_a", [&"flank_red_blue_a"], [1.0])
	_configure_route_link(routes, &"flank_red_blue_a", [&"blue_hub"], [1.0])
	_configure_route_link(routes, &"flank_blue_red_b", [&"flank_red_blue_b"], [1.0])
	_configure_route_link(routes, &"flank_red_blue_b", [&"blue_hub"], [1.0])
	print("[MapManager] Red macro de rutas configurada: %d corredores." % routes.size())


## Conecta una ruta a destinos del mismo árbol. `get_path_to()` evita NodePaths
## frágiles en escena y permite que la configuración siga funcionando si el
## autor reordena nodos contenedores sin renombrar rutas.
func _configure_route_link(routes: Dictionary, source_id: StringName, destination_ids: Array[StringName], weights: Array[float]) -> void:
	var source: CaminoBot = routes.get(source_id, null) as CaminoBot
	if source == null:
		return
	var next_paths: Array[NodePath] = []
	var next_weights: Array[float] = []
	for index: int in range(destination_ids.size()):
		var destination_id: StringName = destination_ids[index]
		var destination: CaminoBot = routes.get(destination_id, null) as CaminoBot
		if destination == null:
			continue
		next_paths.append(source.get_path_to(destination))
		next_weights.append(weights[index] if index < weights.size() else 1.0)
	source.next_paths = next_paths
	source.next_path_weights = next_weights


func _setup_match() -> void:
	if _is_story_mode():
		return
	# 0. Sincronizar maximo de jugadores desde GameState (configurado desde el menu)
	if is_instance_valid(GameState) and GameStateMP.max_players_total > 0:
		MatchManager.max_players_total = GameStateMP.max_players_total
	
	# 0.5 Asegurar nodos de UI necesarios (HUD, selector de equipo)
	_ensure_ui_nodes()
	
	# 1. Encontrar y reemplazar los cores CSGBox3D con core.tscn instancias
	_replace_cores()

	# 1.5 Crear referencias semánticas de base y áreas de depuración si faltan.
	# No afectan el modo actual ni requieren que otros mapas tengan un núcleo.
	_ensure_base_anchors()
	_ensure_debug_zones()
	
	# 2. Asegurar que los spawners spawnen en sus equipos correctos
	_configure_spawners()
	
	# 2.5 Conectar corredores macro y mejorar navegación
	_configure_bot_route_graph()
	_update_navigation()
	
	# 3. Conectar fin de partida
	if GameStateMP.match_ended.is_connected(_on_match_ended):
		GameStateMP.match_ended.disconnect(_on_match_ended)
	GameStateMP.match_ended.connect(_on_match_ended)
	
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

## Crea los marcadores invisibles que la IA usa como bases semánticas.
## Se anclan a núcleos existentes por compatibilidad, o a spawners si el modo no usa núcleo.
func _ensure_base_anchors() -> void:
	if _map_root == null or _base_anchor_scene == null:
		return
	for team_id: int in [int(Enums.Equipo.AZUL), int(Enums.Equipo.ROJO)]:
		if _find_base_anchor(team_id) != null:
			continue
		var anchor: Node3D = _base_anchor_scene.instantiate() as Node3D
		if anchor == null:
			continue
		anchor.name = "BaseAzul" if team_id == int(Enums.Equipo.AZUL) else "BaseRoja"
		anchor.set("team", team_id)
		var reference: Node3D = _find_base_reference(team_id)
		_map_root.add_child(anchor)
		if reference != null:
			anchor.global_position = reference.global_position
		anchor.owner = _map_root
		print("[MapManager] Marcador de base creado: %s" % anchor.name)
	if is_instance_valid(TeamAI):
		TeamAI.refresh_objectives()


func _find_base_anchor(team_id: int) -> Node3D:
	var anchors: Array[Node] = get_tree().get_nodes_in_group(&"base_anchors")
	for anchor: Node in anchors:
		if anchor is Node3D and int(anchor.get("team")) == team_id:
			return anchor as Node3D
	return null


func _find_base_reference(team_id: int) -> Node3D:
	var core_name: String = "Core Azul" if team_id == int(Enums.Equipo.AZUL) else "Core Rojo"
	var core: Node3D = _map_root.find_child(core_name, true, false) as Node3D
	if core != null:
		return core
	var spawner_name: String = "BlueSpawner" if team_id == int(Enums.Equipo.AZUL) else "RedSpawner"
	return _map_root.find_child(spawner_name, true, false) as Node3D


## Añade tres volúmenes sin colisión para depuración si el mapa no los definió.
func _ensure_debug_zones() -> void:
	if _map_root == null or _debug_zone_scene == null:
		return
	var blue_base: Node3D = _find_base_anchor(int(Enums.Equipo.AZUL))
	var red_base: Node3D = _find_base_anchor(int(Enums.Equipo.ROJO))
	if blue_base == null or red_base == null:
		return
	var mid_position: Vector3 = (blue_base.global_position + red_base.global_position) * 0.5
	var definitions: Array[Dictionary] = [
		{"id": &"base_azul", "position": blue_base.global_position, "size": Vector3(55.0, 8.0, 35.0)},
		{"id": &"base_roja", "position": red_base.global_position, "size": Vector3(55.0, 8.0, 35.0)},
		{"id": &"mitad_mapa", "position": mid_position, "size": Vector3(55.0, 8.0, 10.0)},
	]
	for definition: Dictionary in definitions:
		var zone_id: StringName = definition["id"] as StringName
		if _find_debug_zone(zone_id) != null:
			continue
		var zone: DebugMapZone = _debug_zone_scene.instantiate() as DebugMapZone
		if zone == null:
			continue
		var zone_position: Vector3 = definition["position"] as Vector3
		var zone_size: Vector3 = definition["size"] as Vector3
		zone.name = String(zone_id)
		zone.zone_id = zone_id
		_map_root.add_child(zone)
		zone.global_position = zone_position
		zone.set_zone_size(zone_size)
		zone.owner = _map_root
		print("[MapManager] Zona debug creada: %s" % zone.zone_id)


func _find_debug_zone(zone_id: StringName) -> DebugMapZone:
	var zones: Array[Node] = get_tree().get_nodes_in_group(&"map_debug_zones")
	for zone: Node in zones:
		if zone is DebugMapZone and (zone as DebugMapZone).zone_id == zone_id:
			return zone as DebugMapZone
	return null


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
	
	var spawner_script: Script = preload("res://Scripts/Multiplayer/match/spawner.gd")
	
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

## Asegura que los nodos de UI necesarios (HUDLayer, TeamWeaponSelector)
## existan como hijos del mapa raiz. Si faltan, los instancia automaticamente.
## Esto permite que mapas que no tienen estos nodos (como Mapa_de_guerra)
## funcionen igual que map_1.tscn sin necesidad de modificar la escena.
func _ensure_ui_nodes() -> void:
	if not _map_root:
		return
	
	if not _map_root.find_child("HUDLayer", true, false):
		var hud_scene: PackedScene = preload("res://scenes/Compartido/hud.tscn")
		var hud: CanvasLayer = hud_scene.instantiate() as CanvasLayer
		hud.name = "HUDLayer"
		hud.add_to_group("hud")
		_map_root.add_child(hud)
		hud.owner = _map_root
		print("[MapManager] HUDLayer instanciado automaticamente")
	
	if not _map_root.find_child("TeamWeaponSelector", true, false):
		var selector_scene: PackedScene = preload("res://scenes/Multiplayer/objetos/team_weapon_selector.tscn")
		var selector: CanvasLayer = selector_scene.instantiate() as CanvasLayer
		selector.name = "TeamWeaponSelector"
		_map_root.add_child(selector)
		selector.owner = _map_root
		print("[MapManager] TeamWeaponSelector instanciado automaticamente")

func _is_story_mode() -> bool:
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	return story_state != null and story_state.has_method("is_story_active") and bool(story_state.call("is_story_active"))


func _on_match_ended(winning_team: int) -> void:
	print("[MapManager] Partida terminada! Ganador: %s" % GameState.nombre_equipo(winning_team))
	# Limpiar estado de MatchManager
	MatchManager.reset_match()
