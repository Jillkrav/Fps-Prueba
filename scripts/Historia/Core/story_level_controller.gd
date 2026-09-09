@tool
class_name StoryLevelController
extends Node

## Controlador de una misión de Historia.
## Cada mapa instancia uno y expone sus propiedades en el Inspector: spawn,
## checkpoint, arma inicial, objetivo y escena siguiente.
signal level_started(level_id: String)
signal level_completed(level_id: String)
signal player_respawned(player: Player)

@export_category("Definición de misión (recomendada)")
## Fuente de verdad de la misión: story_map_list.json (se busca por level_id).
## Este recurso .tres es SOLO un fallback legado para mapas que NO están en la
## lista de campaña (p. ej. mapas sueltos de pruebas). Para la campaña, edita
## el JSON; los campos del nodo de abajo quedan como valores por defecto.
## Se tipa como Resource para permitir que el archivo cargue aun antes de que el
## editor haya reindexado clases nuevas; asigna StoryLevelDefinition (.tres).
@export var level_definition: Resource = null

@export_category("Level (fallback legado)")
@export_multiline var objective_text: String = "Llega a la salida."

@export_category("Nodes")
@export var player_path: NodePath = NodePath("../Player")
@export var initial_checkpoint_path: NodePath = NodePath("../Checkpoints/StartCheckpoint/SpawnMarker")

@export_category("Respawn")
@export_range(0.1, 10.0, 0.1) var respawn_delay: float = 2.0

# ─── Desplegables data-driven (desde JSON) ────────────────────────────────
# Estos campos aparecen en el Inspector como menús desplegables generados
# desde los JSON centrales (ver _get_property_list y StoryDataCatalog):
#   - level_id        -> story_map_list.json
#   - next_level_path -> story_map_list.json (+ opción de volver al menú)
#   - starting_weapon -> skill.json
## ID del nivel (nivel de campaña). Menú desplegable desde story_map_list.json.
var level_id: String = "story_test"
## Escena del siguiente nivel. Menú desplegable; vacío = volver al menú.
var next_level_path: String = ""
## Arma inicial del jugador. Menú desplegable desde skill.json.
var starting_weapon: String = "Glock"

var player: Player = null
var _is_respawning: bool = false
var _is_completing: bool = false

## Escena del arma tirada en el suelo, para re-crear las que soltaron NPCs.
const DROPPED_WEAPON_SCENE: PackedScene = preload("res://scenes/Compartido/pickups/dropped_weapon.tscn")


## Inspeccionado como menús desplegables generados desde los JSON del juego.
func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append({
		"name": "Nivel y arma (menús desde JSON)",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_CATEGORY,
	})
	props.append({
		"name": "level_id",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.campaign_id_hint(),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "next_level_path",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.campaign_scene_hint(true),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "starting_weapon",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.weapon_hint(),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	return props


func _get(property: StringName) -> Variant:
	match property:
		&"level_id":
			return level_id
		&"next_level_path":
			return next_level_path
		&"starting_weapon":
			return starting_weapon
	return null


func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"level_id":
			level_id = str(value)
			return true
		&"next_level_path":
			next_level_path = str(value)
			return true
		&"starting_weapon":
			starting_weapon = str(value)
			return true
	return false


func _ready() -> void:
	# En el editor el script es @tool solo para mostrar los desplegables;
	# aquí no debe ejecutar lógica de misión (no hay jugador ni GameStateSP).
	if Engine.is_editor_hint():
		return
	add_to_group(&"story_level_controller")
	_apply_level_definition()
	player = get_node_or_null(player_path) as Player
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set("player_team", int(Enums.Equipo.AZUL))
		game_state.set("friendly_fire", false)
	var current_scene: Node = get_tree().current_scene
	var scene_path: String = current_scene.scene_file_path if current_scene != null else ""
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state == null or not story_state.has_method("begin_story"):
		push_error("[StoryLevelController] GameStateSP no está disponible.")
		return
	# Si venimos de una partida guardada del MISMO nivel (menú «continuar»),
	# conservamos el checkpoint que ya cargó SaveManager.load_game(); si no,
	# comenzamos la misión desde cero (comportamiento clásico / nueva partida).
	var resuming_same_level: bool = (
		int(story_state.get("session_mode")) == GameStateSPClass.SessionMode.HISTORIA
		and str(story_state.get("current_level_id")) == level_id
	)
	if resuming_same_level and story_state.has_method("resume_story"):
		story_state.call("resume_story")
	else:
		story_state.call("begin_story", level_id, scene_path)
	# Informar al gestor de persistencia qué nivel se está cargando: los
	# interactuables persistentes lo consultan al restaurarse (call_deferred).
	var level_state_manager: Node = get_node_or_null("/root/LevelStateManager")
	if level_state_manager != null and level_state_manager.has_method("set_current_level"):
		level_state_manager.set_current_level(level_id)
	if player != null and not player.player_died.is_connected(on_player_died):
		player.player_died.connect(on_player_died)
	call_deferred("_initialize_level")


func _initialize_level() -> void:
	if player == null or not is_instance_valid(player):
		push_error("[StoryLevelController] No se encontró Player en %s." % player_path)
		return
	# Restaurar el objetivo guardado del nivel (si venimos de una vuelta atrás).
	_restore_saved_objective()
	# ¿Llegamos a través de un StoryExit enlazado a un StorySpawnPoint de ESTE
	# mapa? Si es así, _apply_spawn_point coloca al jugador en ESE punto
	# (posición y orientación) y aplica vida/arma (el snapshot guardado tiene
	# prioridad: ir y volver NO pierde progreso).
	var spawn_point: StorySpawnPoint = _consume_entry_spawn_point()
	if spawn_point != null:
		_apply_spawn_point(spawn_point)
	else:
		# Primera entrada / reinicio: configuración clásica de entrada.
		_apply_player_state(null)
		var initial_checkpoint: Marker3D = get_node_or_null(initial_checkpoint_path) as Marker3D
		if initial_checkpoint != null:
			var game_state: Node = get_node_or_null("/root/GameStateSP")
			var has_checkpoint: bool = game_state != null and bool(game_state.get("has_checkpoint"))
			# En una vuelta atrás conservamos el último checkpoint; en la primera
			# entrada usamos el inicial.
			if not has_checkpoint:
				set_checkpoint(initial_checkpoint.global_position, false)
	# Re-crear las armas que soltaron NPCs muertos en una visita anterior.
	_restore_dynamic_drops()
	_set_objective(objective_text)
	level_started.emit(level_id)
	# El mapa terminó de cargar, restauró su estado y entrega el control al
	# jugador: ocultamos la pantalla de carga.
	var loading_screen: Node = get_node_or_null("/root/StoryLoadingScreen")
	if loading_screen != null and loading_screen.has_method("hide_loading"):
		loading_screen.hide_loading()


## Re-crea en el mapa las armas que soltaron NPCs muertos en una visita
## anterior (persistencia de "drops" dinámicos). Al recogerlas, su estado pasa
## a "collected" y dejan de aparecer.
func _restore_dynamic_drops() -> void:
	var lsm: Node = get_node_or_null("/root/LevelStateManager")
	if lsm == null or not lsm.has_method("collect_dynamic_drops"):
		return
	for data: Dictionary in lsm.collect_dynamic_drops(level_id):
		var key: String = str(data.get("key", ""))
		if key.is_empty():
			continue
		var drop: Node = DROPPED_WEAPON_SCENE.instantiate()
		drop.name = "RestoredDrop_%s" % key
		drop.set("state_id", key)
		var wd: Variant = data.get("weapon_data", {})
		if wd is Dictionary and drop.has_method("set_weapon_data"):
			drop.call("set_weapon_data", wd)
		var container: Node = get_parent()
		if container == null:
			drop.free()
			continue
		# Añadir PRIMERO al árbol y posicionar DESPUÉS: global_position no se
		# aplica en un nodo que aún no está dentro del árbol (quedaría en el
		# origen del mapa).
		container.add_child(drop)
		var t: Array = data.get("transform", [])
		if t.size() >= 3:
			drop.global_position = Vector3(float(t[0]), float(t[1]), float(t[2]))
			if t.size() >= 4:
				drop.global_rotation = Vector3(0.0, float(t[3]), 0.0)
		drop.set("_spawn_transform", drop.global_transform)


## Restaura el objetivo del nivel si había un estado guardado para él.
func _restore_saved_objective() -> void:
	var level_state_manager: Node = get_node_or_null("/root/LevelStateManager")
	if level_state_manager == null or not level_state_manager.has_method("get_entity_state"):
		return
	var st: Dictionary = level_state_manager.get_entity_state(level_id, LevelStateManager.CONTROLLER_STATE_ID)
	var saved_objective: String = str(st.get("objective", ""))
	if not saved_objective.is_empty():
		objective_text = saved_objective


## Aplica el arma inicial clásica del nivel (comportamiento original).
func _apply_starting_weapon() -> void:
	if player == null or not is_instance_valid(player):
		return
	if starting_weapon.is_empty():
		return
	player.setup_weapon(starting_weapon)
	if player.weapon_equip_state != null:
		player.weapon_equip_state.equip()


## Aplica el snapshot guardado del jugador (vida, arma y municiones) al volver
## a un nivel o tras cargar una partida.
func _apply_player_snapshot(snapshot: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	var health: float = float(snapshot.get("health", 0.0))
	if health > 0.0:
		player.current_health = minf(health, player.max_health)
		if player.has_signal(&"health_changed"):
			player.health_changed.emit(player.current_health, player.max_health)
	var weapon_name: String = str(snapshot.get("weapon", ""))
	if not weapon_name.is_empty():
		player.setup_weapon(weapon_name)
		var weapon: Node = player.get("active_weapon")
		if weapon != null and is_instance_valid(weapon):
			if snapshot.has("ammo_in_mag"):
				weapon.set("ammo_in_mag", int(snapshot["ammo_in_mag"]))
			if snapshot.has("reserve_ammo"):
				weapon.set("reserve_ammo", int(snapshot["reserve_ammo"]))
		if player.weapon_equip_state != null:
			player.weapon_equip_state.equip()
	elif not starting_weapon.is_empty():
		_apply_starting_weapon()


## Lee y consume GameStateSP.entry_exit_key; si corresponde a un StorySpawnPoint
## de ESTE mapa, lo devuelve (si no, null).
func _consume_entry_spawn_point() -> StorySpawnPoint:
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state == null:
		return null
	var raw_key: Variant = story_state.get("entry_exit_key")
	var exit_key: String = str(raw_key) if raw_key != null else ""
	story_state.set("entry_exit_key", "")
	if exit_key.is_empty():
		return null
	# Defensa: el exit ya entrega la clave limpia, pero normalizamos por si
	# llegara con la etiqueta del desplegable ("Mapa X:res://...") para que el
	# emparejamiento nunca falle en silencio (clean_exit_key es idempotente).
	exit_key = StoryDataCatalog.clean_exit_key(exit_key)
	for node: Node in get_tree().get_nodes_in_group("story_spawn_points"):
		var sp: StorySpawnPoint = node as StorySpawnPoint
		if sp == null:
			continue
		# Coincidencia clásica: el punto se enlazó al exit por «source_story_exit».
		if sp.get_source_exit_key() == exit_key:
			return sp
		# Coincidencia por el exit: la clave ES el punto elegido en
		# «destination_spawn_point» del exit (clave propia del punto).
		if sp.get_spawn_key() == exit_key:
			return sp
	return null


## Aplica un StorySpawnPoint: posición y orientación de entrada. La vida y el
## arma las decide _apply_player_state (el snapshot guardado tiene prioridad),
## de modo que volver a un mapa por un punto de entrada NO borra el progreso.
func _apply_spawn_point(sp: StorySpawnPoint) -> void:
	if player == null or not is_instance_valid(player):
		return
	# Posición y orientación: el Marker3D define dónde y hacia dónde mirar.
	player.global_position = sp.global_position
	player.global_rotation = Vector3(0.0, sp.global_rotation.y, 0.0)
	# Vida / arma según prioridad (snapshot guardado primero).
	_apply_player_state(sp)
	# El respawn dentro del nivel vuelve a este punto de entrada.
	set_checkpoint(sp.global_position, false)


## Aplica el estado del jugador al entrar al nivel. Prioridad:
##   1) Snapshot guardado (vida/arma/municiones) si existe -> se conserva al
##      ir y volver entre mapas (el punto de entrada no lo pisa).
##   2) Sin snapshot (primera entrada / partida nueva): la configuración del
##      punto de entrada si el diseñador la puso, o el arma inicial del nivel.
func _apply_player_state(sp: StorySpawnPoint = null) -> void:
	if player == null or not is_instance_valid(player):
		return
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	var player_snapshot: Dictionary = {}
	if save_manager != null and save_manager.has_method("get_player_snapshot"):
		player_snapshot = save_manager.get_player_snapshot()
	if not player_snapshot.is_empty():
		_apply_player_snapshot(player_snapshot)
		return
	# Sin snapshot: config del punto de entrada (si la definió) o arma inicial.
	var health: float = 0.0
	var weapon: String = ""
	if sp != null:
		health = sp.spawn_health
		weapon = _clean_spawn_weapon(sp.spawn_weapon)
	if health > 0.0:
		player.current_health = minf(health, player.max_health)
		if player.has_signal(&"health_changed"):
			player.health_changed.emit(player.current_health, player.max_health)
	if not weapon.is_empty():
		player.setup_weapon(weapon)
		if player.weapon_equip_state != null:
			player.weapon_equip_state.equip()
	elif not starting_weapon.is_empty():
		_apply_starting_weapon()


## Limpia el valor del desplegable de arma de un StorySpawnPoint: la opción
## «(No cambiar):» es el placeholder del menú y se trata como "sin arma".
func _clean_spawn_weapon(value: String) -> String:
	var v: String = str(value).strip_edges()
	if v.is_empty() or v == "(No cambiar):":
		return ""
	return v


func set_checkpoint(position: Vector3, announce: bool = true) -> void:
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state != null and story_state.has_method("set_checkpoint"):
		story_state.call("set_checkpoint", position)
	if announce:
		_show_message("CHECKPOINT ACTIVADO")


func on_player_died() -> void:
	if _is_respawning:
		return
	_is_respawning = true
	_show_message("HAS MUERTO. REAPARECIENDO...")
	await get_tree().create_timer(respawn_delay).timeout
	if player == null or not is_instance_valid(player):
		return
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	var has_checkpoint: bool = story_state != null and bool(story_state.get("has_checkpoint"))
	var respawn_position: Vector3 = story_state.get("checkpoint_position") as Vector3 if has_checkpoint else player.global_position
	player.respawn_at(respawn_position)
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method("story_player_respawned"):
		hud.story_player_respawned()
	_set_objective(objective_text)
	_is_respawning = false
	player_respawned.emit(player)


func request_level_complete(exit_node: Node = null, destination: String = "") -> void:
	if _is_completing:
		return
	_is_completing = true
	# Una salida puede viajar sin completar la misión (regreso/desvío).
	var completes: bool = true
	if exit_node != null and exit_node.get("completes_level") != null:
		completes = bool(exit_node.get("completes_level"))
	# Destino: prioridad al de la salida; si viene vacío, el siguiente nivel.
	# Limpiamos la etiqueta del desplegable ("Mapa X:res://...") por si acaso.
	var target: String = StoryDataCatalog.clean_scene_path(str(destination))
	if target.is_empty():
		target = StoryDataCatalog.clean_scene_path(next_level_path)
	# Registrar el exit por el que se sale: el nivel de destino lo usa para
	# colocar al jugador en su StorySpawnPoint correspondiente.
	if exit_node != null and exit_node.has_method("get_entry_key"):
		var story_state: Node = get_node_or_null("/root/GameStateSP")
		if story_state != null:
			story_state.set("entry_exit_key", exit_node.get_entry_key())
	if completes:
		var story_state: Node = get_node_or_null("/root/GameStateSP")
		if story_state != null and story_state.has_method("complete_current_level"):
			story_state.call("complete_current_level")
		_show_message("MISIÓN COMPLETADA")
		level_completed.emit(level_id)
	await get_tree().create_timer(1.5).timeout
	# ── Persistencia: capturar estado del nivel + guardar + pantalla de carga ──
	var level_state_manager: Node = get_node_or_null("/root/LevelStateManager")
	if level_state_manager != null and level_state_manager.has_method("set_entity_state"):
		level_state_manager.set_entity_state(level_id, LevelStateManager.CONTROLLER_STATE_ID, {"objective": objective_text})
	if level_state_manager != null and level_state_manager.has_method("capture_level_state"):
		level_state_manager.capture_level_state(level_id)
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("save_current_game"):
		save_manager.save_current_game(1)
	var loading_screen: Node = get_node_or_null("/root/StoryLoadingScreen")
	if loading_screen != null and loading_screen.has_method("show_loading"):
		var target_name: String = StoryDataCatalog.campaign_name_for_scene(target)
		loading_screen.show_loading("CARGANDO", target_name)
	await get_tree().process_frame
	if not target.is_empty() and ResourceLoader.exists(target):
		get_tree().change_scene_to_file(target)
	else:
		get_tree().change_scene_to_file("res://scenes/Compartido/main_menu.tscn")


## API pública para eventos y objetivos data-driven.
func set_objective(text: String) -> void:
	if text.is_empty():
		return
	objective_text = text
	_set_objective(text)


## API pública para eventos y mensajes temporales de campaña.
func show_message(text: String) -> void:
	if text.is_empty():
		return
	_show_message(text)


## Ordena a los NPCs aliados del nivel que sigan (o dejen de seguir) al
## jugador. Se dispara con [Tab] en una misión de Historia.
func toggle_ally_follow() -> void:
	var allied: Array[Node] = []
	for npc: Node in get_tree().get_nodes_in_group(&"npc"):
		if npc == null or not is_instance_valid(npc):
			continue
		if not npc.has_method("set_following"):
			continue
		if npc.has_method("is_allied_with_player") and not bool(npc.call("is_allied_with_player")):
			continue
		allied.append(npc)
	if allied.is_empty():
		_show_story_toast("Sin aliados para seguirte")
		return
	var target_state: bool = not bool(allied[0].get("following"))
	for npc: Node in allied:
		npc.call("set_following", target_state)
	if target_state:
		_show_story_toast("Aliados: ¡A mi lado! ([C] para detener)")
	else:
		_show_story_toast("Aliados: En posición")


func _show_story_toast(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method("show_story_toast"):
		hud.show_story_toast(text)


## API pública para recompensas de eventos de campaña.
func give_player_weapon(weapon_name: String) -> void:
	if player == null or not is_instance_valid(player) or weapon_name.is_empty():
		return
	player.setup_weapon(weapon_name)
	if player.weapon_equip_state != null:
		player.weapon_equip_state.equip()


## Aplica la definición de la misión. Fuente de verdad: story_map_list.json
## (se busca el nivel por su level_id). Si el nivel no está en la lista de
## campaña, usa el recurso .tres legado asignado en la escena como fallback.
func _apply_level_definition() -> void:
	var entry: Dictionary = StoryDataCatalog.campaign_entry_for_id(level_id)
	if not entry.is_empty():
		_apply_campaign_entry(entry)
		return
	if level_definition == null:
		return
	var definition_level_id: String = str(level_definition.get("level_id"))
	var definition_objective: String = str(level_definition.get("objective_text"))
	var definition_weapon: String = str(level_definition.get("starting_weapon"))
	if not definition_level_id.is_empty():
		level_id = definition_level_id
	if not definition_objective.is_empty():
		objective_text = definition_objective
	# Una ruta vacía en el recurso significa intencionalmente «volver al menú».
	next_level_path = str(level_definition.get("next_level_path"))
	if not definition_weapon.is_empty():
		starting_weapon = definition_weapon
	respawn_delay = float(level_definition.get("respawn_delay"))


## Aplica los datos de una entrada de story_map_list.json (fuente de verdad).
func _apply_campaign_entry(entry: Dictionary) -> void:
	var id: String = str(entry.get("id", ""))
	if not id.is_empty():
		level_id = id
	var objective: String = str(entry.get("objective_text", ""))
	if not objective.is_empty():
		objective_text = objective
	# Ruta vacía = intencionalmente «volver al menú».
	next_level_path = str(entry.get("next_level_path", ""))
	var weapon: String = str(entry.get("starting_weapon", ""))
	if not weapon.is_empty():
		starting_weapon = weapon
	respawn_delay = float(entry.get("respawn_delay", 2.0))


func _set_objective(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method("set_story_objective"):
		hud.set_story_objective(text)


func _show_message(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method("set_story_objective"):
		hud.set_story_objective(text)
