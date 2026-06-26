# scripts/match_manager.gd
# MatchManager — Sistema centralizado de gestion de partida.
# Controla: maximo de jugadores, bots por equipo, jugadores humanos,
# cambios de equipo, respawn y reutilizacion de bots.
#
# Inspirado en TeamGamePlus.uc / DeathMatchPlus.uc de Unreal Tournament
# (referencias en config/Botpack/Prioridad/).
#
# Autoload singleton registrado como "MatchManager".
extends Node
# NOTA: No usar class_name — el autoload en project.godot ya registra "MatchManager" globalmente.

# ═══════════════════════════════════════════
# SEÑALES
# ═══════════════════════════════════════════

signal match_started()
# NOTA: usar GameState.match_ended en lugar de esta — el match_ended de GameState
# es el que usan hud.gd y map_manager.gd para detectar fin de partida.
signal team_changed(pawn: Node, old_team: int, new_team: int)
signal bot_respawned(bot: Node, team: int)
signal team_sizes_updated(blue_size: int, red_size: int)

## Señal emitida cuando cambian los datos de los jugadores (kills, muertes, etc.)
## El Scoreboard se conecta a esta senal para refrescarse.
signal players_data_changed()

# ═══════════════════════════════════════════
# EXPORTS — Configurables desde el inspector
# ═══════════════════════════════════════════

## Maximo total de jugadores en la partida (bots + humano)
@export var max_players_total: int = 24:
	set(val):
		max_players_total = val
		_actualizar_limites()

## Tiempo de respawn en segundos
@export var respawn_time: float = 5.0

## Prefab del bot NPC
@export var npc_scene: PackedScene = preload("res://scenes/npcs/npc.tscn")

# ═══════════════════════════════════════════
# ESTADOS INTERNOS
# ═══════════════════════════════════════════

## Limite por equipo (se calcula automaticamente)
var max_per_team: int = 12

## Pool de todas las instancias de bots (vivas, muertas, inactivas)
var bot_pool: Array[NpcBase] = []

## Referencia al jugador humano
var player: Player = null

## Spawn points por equipo
var spawn_points_blue: Array[Marker3D] = []
var spawn_points_red: Array[Marker3D] = []

## Contadores actuales
var blue_bots_active: int = 0
var red_bots_active: int = 0
var player_team: int = int(Enums.Equipo.ESPECTADOR)

## Bots inactivos (disponibles para reutilizar)
var _inactive_bots: Array[NpcBase] = []

## Bandera de partida iniciada
var _match_started: bool = false

## Getter publico para consultar si la partida ha comenzado.
func is_match_started() -> bool:
	return _match_started

## Temporizador de respawn
var _respawn_timers: Dictionary = {}  # bot -> tiempo restante

# ═══════════════════════════════════════════
# REGISTRO CENTRALIZADO DE JUGADORES (PlayerData)
# ═══════════════════════════════════════════

## Todos los jugadores indexados por player_id
var _players_data: Dictionary[int, PlayerData] = {}

## Busqueda inversa: pawn (Player o NpcBase) -> player_id
var _pawn_to_player_id: Dictionary = {}

## Contador incremental de IDs
var _next_player_id: int = 1000

# ═══════════════════════════════════════════
# INICIALIZACION
# ═══════════════════════════════════════════

func _ready() -> void:
	_actualizar_limites()
	print("[MatchManager] Inicializado. Max total: %d, Max por equipo: %d" % [max_players_total, max_per_team])

func _actualizar_limites() -> void:
	# ceil() maneja pares e impares: 24→12, 25→13
	max_per_team = ceil(max_players_total / 2.0)

# ═══════════════════════════════════════════
# CONFIGURACION DE SPAWN POINTS
# ═══════════════════════════════════════════

func registrar_spawn_points(blue_points: Array[Marker3D], red_points: Array[Marker3D]) -> void:
	spawn_points_blue = blue_points.duplicate()
	spawn_points_red = red_points.duplicate()
	print("[MatchManager] Spawn points registrados: Azul=%d, Rojo=%d" % [spawn_points_blue.size(), spawn_points_red.size()])

## Registra puntos de spawn para un equipo especifico (registro incremental).
## Cada spawner puede llamar a este metodo independientemente.
func registrar_spawn_points_equipo(team: int, points: Array[Marker3D]) -> void:
	match team:
		int(Enums.Equipo.AZUL):
			spawn_points_blue = points.duplicate()
		int(Enums.Equipo.ROJO):
			spawn_points_red = points.duplicate()
		_:
			push_warning("[MatchManager] Equipo desconocido al registrar spawn points: %d" % team)
			return
	var count: int = spawn_points_blue.size() if team == int(Enums.Equipo.AZUL) else spawn_points_red.size()
	print("[MatchManager] Spawn points registrados para %s: %d" % [GameState.nombre_equipo(team), count])

func obtener_spawn_point(team: int, exclude_positions: Array = []) -> Marker3D:
	var points: Array[Marker3D]
	match team:
		int(Enums.Equipo.AZUL):
			points = spawn_points_blue
		int(Enums.Equipo.ROJO):
			points = spawn_points_red
		_:
			return null
	
	if points.is_empty():
		push_warning("[MatchManager] No hay puntos de spawn para %s!" % GameState.nombre_equipo(team))
		return null
	
	# ── Validacion extra: verificar que los puntos coincidan con el equipo ──
	# Si un marker de BlueSpawner aparece en la lista roja (o viceversa),
	# es un bug de configuracion. Detectarlo y reportarlo.
	if points.size() > 0:
		var sample_marker: Marker3D = points[0]
		var parent_name: String = sample_marker.get_parent().name.to_lower() if sample_marker.get_parent() else ""
		var team_name: String = GameState.nombre_equipo(team).to_lower()
		if team_name == "azul" and "blue" not in parent_name and "azul" not in parent_name:
			push_error("[MatchManager] ERROR: Spawn point %s NO pertenece a BlueSpawner (padre=%s)!" % [sample_marker.name, parent_name])
		elif team_name == "rojo" and "red" not in parent_name and "rojo" not in parent_name:
			push_error("[MatchManager] ERROR: Spawn point %s NO pertenece a RedSpawner (padre=%s)!" % [sample_marker.name, parent_name])
	
	# Intentar encontrar un punto alejado de otros jugadores
	var candidates: Array[Marker3D] = []
	for p in points:
		var too_close: bool = false
		for pos in exclude_positions:
			if p.global_position.distance_to(pos) < 2.0:
				too_close = true
				break
		if not too_close:
			candidates.append(p)
	
	var chosen: Marker3D
	if candidates.is_empty():
		chosen = points[randi() % points.size()]
	else:
		chosen = candidates[randi() % candidates.size()]
	
	print("[MatchManager] Spawn para %s: %s en (%.1f, %.1f, %.1f)" % [
		GameState.nombre_equipo(team),
		chosen.name, chosen.global_position.x, chosen.global_position.y, chosen.global_position.z
	])
	return chosen

# ═══════════════════════════════════════════
# INICIO DE PARTIDA (tras seleccion de equipo)
# ═══════════════════════════════════════════

func iniciar_partida(player_ref: Player, team_id: int) -> void:
	player = player_ref
	player_team = team_id
	
	# El jugador cuenta para su equipo
	var player_team_count: int = 1
	var _other_team: int = int(Enums.Equipo.AZUL) if team_id == int(Enums.Equipo.ROJO) else int(Enums.Equipo.ROJO)
	var other_team_count: int = 0
	
	# Calcular cuantos bots necesita cada equipo para alcanzar el limite
	var bots_for_player_team: int = max_per_team - player_team_count
	var bots_for_other_team: int = max_per_team - other_team_count
	
	print("[MatchManager] Iniciando partida. Jugador en %s. Azul necesita %d bots, Rojo necesita %d bots" % [
		GameState.nombre_equipo(team_id), 
		bots_for_player_team if team_id == int(Enums.Equipo.AZUL) else bots_for_other_team,
		bots_for_other_team if team_id == int(Enums.Equipo.AZUL) else bots_for_player_team
	])
	
	# Crear todos los bots necesarios
	var total_bots: int = bots_for_player_team + bots_for_other_team
	_crear_pool_de_bots(total_bots)
	
	# Asignar bots a sus equipos
	_asignar_bots_a_equipos(team_id, bots_for_player_team, bots_for_other_team)
	
	# Registrar al jugador humano en el sistema central
	var human_id: int = _pawn_to_player_id.get(player, -1)
	if human_id < 0:
		# Primera vez: registrar
		human_id = _register_pawn(player, "Jugador", true)
	
	if _players_data.has(human_id):
		var pd: PlayerData = _players_data[human_id]
		pd.team = team_id
		pd.status = PlayerData.Status.ALIVE
		pd.health = player.current_health
		pd.max_health = player.max_health
		players_data_changed.emit()
	
	_match_started = true
	match_started.emit()
	emit_team_sizes()
	print("[MatchManager] Partida iniciada con %d bots. Azul=%d activos, Rojo=%d activos" % [
		bot_pool.size(), blue_bots_active, red_bots_active
	])

func _crear_pool_de_bots(cantidad: int) -> void:
	var map_root: Node = _find_map_root()
	if not map_root:
		push_error("[MatchManager] No se encontro el mapa para crear bots")
		return
	
	for i in range(cantidad):
		var bot: NpcBase = npc_scene.instantiate() as NpcBase
		bot_pool.append(bot)
		map_root.add_child(bot)
		# Los bots empiezan invisibles/desactivados hasta que se les asigne equipo
		bot.is_invisible = true
		bot.is_dead = true
		bot.set_physics_process(false)
		bot.set_process(false)
		bot.hide()
		if bot.has_node("CollisionShape3D"):
			bot.find_child("CollisionShape3D").disabled = true
		
		# Registrar en el sistema central de jugadores
		var bot_name: String = "Bot #%d" % _next_player_id
		_register_pawn(bot, bot_name, false)
	
	print("[MatchManager] Pool de %d bots creada" % bot_pool.size())

func _asignar_bots_a_equipos(player_team_id: int, count_player_team: int, count_other_team: int) -> void:
	var blue_count: int = count_player_team if player_team_id == int(Enums.Equipo.AZUL) else count_other_team
	var red_count: int = count_other_team if player_team_id == int(Enums.Equipo.AZUL) else count_player_team
	
	var blue_assigned: int = 0
	var red_assigned: int = 0
	
	for bot in bot_pool:
		var team: int
		if blue_assigned < blue_count:
			team = int(Enums.Equipo.AZUL)
			blue_assigned += 1
		elif red_assigned < red_count:
			team = int(Enums.Equipo.ROJO)
			red_assigned += 1
		else:
			break  # No deberia ocurrir si la pool tiene el tamano correcto
		
		_activar_bot(bot, team)
	
	blue_bots_active = blue_assigned
	red_bots_active = red_assigned

func _activar_bot(bot: NpcBase, team: int) -> void:
	# ── SEGURIDAD: Verificar que el spawner tiene puntos para este equipo ──
	var spawn: Marker3D = obtener_spawn_point(team)
	if spawn == null:
		push_error("[MatchManager] CRITICO: No hay spawn point para %s! Equipo=%s" % [bot.name, GameState.nombre_equipo(team)])
		# Fallback: colocar en origen (malo pero no crash)
		bot.global_position = Vector3.ZERO
	else:
		# ── Validacion extra: verificar que el punto de spawn pertenece al equipo correcto ──
		var spawn_parent_name: String = spawn.get_parent().name.to_lower() if spawn.get_parent() else ""
		var is_blue_spawn: bool = "blue" in spawn_parent_name
		var is_red_spawn: bool = "red" in spawn_parent_name
		var team_name: String = GameState.nombre_equipo(team).to_lower()
		
		if team_name == "azul" and not is_blue_spawn and is_red_spawn:
			push_error("[MatchManager] CRITICO: Bot %s de equipo AZUL va a spawn ROJO (%s)!" % [bot.name, spawn.name])
		elif team_name == "rojo" and not is_red_spawn and is_blue_spawn:
			push_error("[MatchManager] CRITICO: Bot %s de equipo ROJO va a spawn AZUL (%s)!" % [bot.name, spawn.name])
		
		bot.global_position = spawn.global_position + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	
	bot.equipo_id = team
	bot.is_invisible = false
	bot.is_dead = false
	bot.set_physics_process(true)
	bot.set_process(true)
	bot.show()
	
	# Re-habilitar colisiones
	var collision_shape: CollisionShape3D = bot.find_child("CollisionShape3D") as CollisionShape3D
	if collision_shape:
		collision_shape.disabled = false
	
	# Restaurar salud
	bot.current_health = bot.max_health
	
	# Asignar arma aleatoria
	var armas: Array[String] = ConfigManager.get_nombres_armas()
	if not armas.is_empty():
		bot.nombre_arma = armas[randi() % armas.size()]
	
	# Re-equipar arma si el bot ya tiene el metodo
	if bot.has_method("_equipar_arma"):
		bot.call_deferred("_equipar_arma")
	if bot.has_method("_aplicar_color_equipo"):
		bot.call_deferred("_aplicar_color_equipo")
	
	# Re-evaluar enemigos
	if bot.has_method("_re_evaluar_enemigos"):
		bot.call_deferred("_re_evaluar_enemigos")
	
	# Actualizar PlayerData del bot
	var pid: int = _pawn_to_player_id.get(bot, -1)
	if pid >= 0 and _players_data.has(pid):
		var pd: PlayerData = _players_data[pid]
		pd.team = team
		pd.status = PlayerData.Status.ALIVE
		pd.health = bot.max_health
	
	print("[MatchManager] Bot activado en equipo %s" % GameState.nombre_equipo(team))

# ═══════════════════════════════════════════
# SISTEMA DE RESPAWN
# ═══════════════════════════════════════════

func reportar_muerte_bot(bot: NpcBase) -> void:
	if not bot in bot_pool:
		return  # No es un bot nuestro, ignorar
	
	if bot.equipo_id == int(Enums.Equipo.AZUL):
		blue_bots_active -= 1
	elif bot.equipo_id == int(Enums.Equipo.ROJO):
		red_bots_active -= 1
	
	# Iniciar timer de respawn
	_respawn_timers[bot] = respawn_time
	
	# Actualizar PlayerData: pasar a estado RESPAWNING
	var pid: int = _pawn_to_player_id.get(bot, -1)
	if pid >= 0 and _players_data.has(pid):
		var pd: PlayerData = _players_data[pid]
		pd.status = PlayerData.Status.RESPAWNING
		pd.respawn_time_left = respawn_time
		_sync_player_data_from_pawn(pd)
		players_data_changed.emit()
	
	print("[MatchManager] Bot %s murio. Respawn en %.1f s. Azul=%d, Rojo=%d" % [
		GameState.nombre_equipo(bot.equipo_id), respawn_time, blue_bots_active, red_bots_active
	])

func _process(delta: float) -> void:
	if not _match_started:
		return
	
	# Gestionar timers de respawn
	var bots_a_respawn: Array[NpcBase] = []
	for bot in _respawn_timers.keys():
		if not is_instance_valid(bot):
			_respawn_timers.erase(bot)
			continue
		_respawn_timers[bot] -= delta
		if _respawn_timers[bot] <= 0.0:
			bots_a_respawn.append(bot)
		
		# Actualizar respawn_time_left en PlayerData para los contadores en vivo
		var pid: int = _pawn_to_player_id.get(bot, -1)
		if pid >= 0 and _players_data.has(pid):
			_players_data[pid].respawn_time_left = _respawn_timers.get(bot, 0.0)
	
	for bot in bots_a_respawn:
		_respawn_timers.erase(bot)
		_respawnear_bot(bot)
	
	# Sincronizar estados de todos los jugadores
	_sync_all_players_status()

func _respawnear_bot(bot: NpcBase) -> void:
	if not is_instance_valid(bot):
		return
	if bot in _inactive_bots:
		_inactive_bots.erase(bot)
	
	var team: int = bot.equipo_id
	
	# Verificar que no se exceda el limite del equipo
	var team_count: int = _contar_activos_por_equipo(team)
	if team_count >= max_per_team:
		# El equipo esta lleno, poner el bot como inactivo
		_desactivar_bot(bot)
		return
	
	# Delegar la restauracion interna al propio bot (respawn() en npc_base.gd)
	# Esto re-equipa arma, re-evalua enemigos, restaura FSM, etc.
	bot.respawn()
	
	# Colocar en spawn point (MatchManager decide DÓNDE, no el bot)
	var spawn: Marker3D = obtener_spawn_point(team)
	if spawn:
		bot.global_position = spawn.global_position + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	
	# Actualizar contadores
	if team == int(Enums.Equipo.AZUL):
		blue_bots_active += 1
	elif team == int(Enums.Equipo.ROJO):
		red_bots_active += 1
	
	# Actualizar PlayerData del bot respawneado
	var pid: int = _pawn_to_player_id.get(bot, -1)
	if pid >= 0 and _players_data.has(pid):
		var pd: PlayerData = _players_data[pid]
		pd.status = PlayerData.Status.ALIVE
		pd.respawn_time_left = 0.0
		_sync_player_data_from_pawn(pd)
		players_data_changed.emit()
	
	bot_respawned.emit(bot, team)
	emit_team_sizes()
	print("[MatchManager] Bot respawneado en %s" % GameState.nombre_equipo(team))

func _desactivar_bot(bot: NpcBase) -> void:
	if not is_instance_valid(bot):
		return
	
	bot.is_dead = true
	bot.is_invisible = true
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.hide()
	
	var collision_shape: CollisionShape3D = bot.find_child("CollisionShape3D") as CollisionShape3D
	if collision_shape:
		collision_shape.disabled = true
	
	if not bot in _inactive_bots:
		_inactive_bots.append(bot)
	
	# Actualizar PlayerData: el bot ahora esta inactivo
	var pid: int = _pawn_to_player_id.get(bot, -1)
	if pid >= 0 and _players_data.has(pid):
		var pd: PlayerData = _players_data[pid]
		pd.status = PlayerData.Status.INACTIVE
		pd.team = int(Enums.Equipo.ESPECTADOR)
		players_data_changed.emit()

# ═══════════════════════════════════════════
# CAMBIO DE EQUIPO
# ═══════════════════════════════════════════

func cambiar_equipo_jugador(nuevo_equipo: int) -> bool:
	if not is_instance_valid(player):
		return false
	if player_team == nuevo_equipo:
		return false  # Ya esta en ese equipo
	
	var old_team: int = player_team
	
	# Verificar que el nuevo equipo no este lleno
	var new_team_count: int = _contar_activos_por_equipo(nuevo_equipo)
	if new_team_count >= max_per_team:
		# El equipo esta lleno. Necesitamos intercambiar un bot.
		# Buscar un bot en el nuevo equipo para desactivarlo
		var bot_to_deactivate: NpcBase = _encontrar_bot_activo_en_equipo(nuevo_equipo)
		if not bot_to_deactivate:
			push_warning("[MatchManager] No hay bot disponible para intercambiar en %s" % GameState.nombre_equipo(nuevo_equipo))
			return false
		
		# Desactivar ese bot (sale de su equipo)
		_desactivar_bot(bot_to_deactivate)
		if nuevo_equipo == int(Enums.Equipo.AZUL):
			blue_bots_active -= 1
		else:
			red_bots_active -= 1
		
		# El bot inactivo se reutilizara para el equipo contrario si hay espacio
		bot_to_deactivate.equipo_id = old_team
	
	# Mover al jugador al nuevo equipo
	player_team = nuevo_equipo
	GameState.player_team = nuevo_equipo
	
	# Actualizar PlayerData del jugador humano
	var human_id: int = _pawn_to_player_id.get(player, -1)
	if human_id >= 0 and _players_data.has(human_id):
		_players_data[human_id].team = nuevo_equipo
		_sync_player_data_from_pawn(_players_data[human_id])
		players_data_changed.emit()
	
	# Si el equipo anterior perdio un jugador humano, compensar con un bot inactivo
	if old_team != int(Enums.Equipo.ESPECTADOR):
		var old_team_count_after: int = _contar_activos_por_equipo(old_team)
		if old_team_count_after < max_per_team:
			# Hay espacio en el equipo anterior, rellenar con bot inactivo si hay
			_rellenar_equipo_con_bot_inactivo(old_team)
	
	# Re-evaluar enemigos del jugador
	if player.has_method("_re_evaluar_enemigos"):
		# Los NPCs se re-evaluaran solos
		pass
	
	# Re-evaluar enemigos de todos los NPCs
	for bot in bot_pool:
		if is_instance_valid(bot) and not bot.is_dead and bot.has_method("_re_evaluar_enemigos"):
			bot._re_evaluar_enemigos()
	
	team_changed.emit(player, old_team, nuevo_equipo)
	emit_team_sizes()
	print("[MatchManager] Jugador cambio de %s a %s. Azul=%d, Rojo=%d" % [
		GameState.nombre_equipo(old_team), 
		GameState.nombre_equipo(nuevo_equipo),
		blue_bots_active, red_bots_active
	])
	return true

func _rellenar_equipo_con_bot_inactivo(team: int) -> void:
	if _inactive_bots.is_empty():
		return
	
	var team_count: int = _contar_activos_por_equipo(team)
	if team_count >= max_per_team:
		return
	
	# Buscar un bot inactivo que fuera de este equipo, o cualquiera
	var bot: NpcBase = null
	for b in _inactive_bots:
		if is_instance_valid(b):
			bot = b
			break
	
	if bot:
		_inactive_bots.erase(bot)
		bot.equipo_id = team
		_activar_bot(bot, team)
		if team == int(Enums.Equipo.AZUL):
			blue_bots_active += 1
		elif team == int(Enums.Equipo.ROJO):
			red_bots_active += 1

func _encontrar_bot_activo_en_equipo(team: int) -> NpcBase:
	for bot in bot_pool:
		if not is_instance_valid(bot):
			continue
		if bot.is_dead:
			continue
		if bot.equipo_id == team:
			return bot
	return null

func _contar_activos_por_equipo(team: int) -> int:
	var count: int = 0
	for bot in bot_pool:
		if is_instance_valid(bot) and not bot.is_dead and bot.equipo_id == team:
			count += 1
	# Si el jugador humano esta en este equipo, contar tambien
	if is_instance_valid(player) and player_team == team and not player.is_dead:
		count += 1
	return count

# ═══════════════════════════════════════════
# UTILIDADES
# ═══════════════════════════════════════════

func emit_team_sizes() -> void:
	team_sizes_updated.emit(blue_bots_active, red_bots_active)

func _find_map_root() -> Node:
	for child in get_tree().root.get_children():
		if child == self:
			continue
		if "Map" in child.name or "map" in child.name:
			return child
	var nav: Node = get_tree().root.find_child("NavigationRegion3D", true, false)
	if nav:
		return nav.get_parent()
	return null

# ═══════════════════════════════════════════
# REGISTRO CENTRALIZADO DE JUGADORES
# ═══════════════════════════════════════════

## Registra un pawn (Player o NpcBase) en el sistema y devuelve su player_id.
## El caller debe proporcionar nombre y si es humano.
func _register_pawn(pawn: Node, player_name: String, is_human: bool) -> int:
	var pd: PlayerData = PlayerData.new()
	pd.player_id = _next_player_id
	pd.player_name = player_name
	pd.pawn = pawn
	pd.is_human = is_human
	pd.team = int(Enums.Equipo.ESPECTADOR)
	pd.status = PlayerData.Status.INACTIVE
	_players_data[_next_player_id] = pd
	_pawn_to_player_id[pawn] = _next_player_id
	_next_player_id += 1
	return pd.player_id

## Elimina un jugador del registro (ej: al resetear partida).
func _unregister_player(player_id: int) -> void:
	if _players_data.has(player_id):
		var pd: PlayerData = _players_data[player_id]
		if pd.pawn and _pawn_to_player_id.has(pd.pawn):
			_pawn_to_player_id.erase(pd.pawn)
		_players_data.erase(player_id)

## Devuelve el player_id de un pawn, o -1 si no esta registrado.
func get_player_id_by_pawn(pawn: Node) -> int:
	return _pawn_to_player_id.get(pawn, -1)

## Devuelve el PlayerData de un jugador por su ID, o null.
func get_player_data(player_id: int) -> PlayerData:
	return _players_data.get(player_id, null)

## Devuelve TODOS los PlayerData registrados (humanos + bots, cualquier estado).
func get_all_players_data() -> Array[PlayerData]:
	return _players_data.values()

## Devuelve los PlayerData de un equipo especifico, excluyendo INACTIVOS.
func get_players_by_team(team_id: int) -> Array[PlayerData]:
	var result: Array[PlayerData] = []
	for pd in _players_data.values():
		if pd.team == team_id and pd.status != PlayerData.Status.INACTIVE:
			result.append(pd)
	return result

## Cuenta jugadores por estado (para las estadisticas globales).
func count_players_by_status(status: PlayerData.Status) -> int:
	var count: int = 0
	for pd in _players_data.values():
		if pd.status == status and pd.team != int(Enums.Equipo.ESPECTADOR):
			count += 1
	return count

## Cuenta jugadores que tienen equipo asignado (no espectadores ni inactivos).
func count_active_players() -> int:
	var count: int = 0
	for pd in _players_data.values():
		if pd.team != int(Enums.Equipo.ESPECTADOR) and pd.status != PlayerData.Status.INACTIVE:
			count += 1
	return count

## Sincroniza los datos de un PlayerData desde su pawn fisico.
func _sync_player_data_from_pawn(pd: PlayerData) -> void:
	if not is_instance_valid(pd.pawn):
		return
	var pawn: Node = pd.pawn
	if pawn is Player:
		pd.health = pawn.current_health
		pd.max_health = pawn.max_health
		pd.team = GameState.player_team
	elif pawn is NpcBase:
		pd.health = pawn.current_health
		pd.max_health = pawn.max_health
		pd.team = pawn.equipo_id

## Actualiza el estado de todos los PlayerData basado en el estado real de los pawns.
func _sync_all_players_status() -> void:
	for pd in _players_data.values():
		if not is_instance_valid(pd.pawn):
			continue
		var pawn: Node = pd.pawn
		var is_dead_val: bool = pawn.get("is_dead") if "is_dead" in pawn else true
		
		# Actualizar health/team
		_sync_player_data_from_pawn(pd)
		
		# Determinar estado
		if pawn in _inactive_bots:
			pd.status = PlayerData.Status.INACTIVE
		elif is_dead_val and _respawn_timers.has(pawn):
			pd.status = PlayerData.Status.RESPAWNING
			pd.respawn_time_left = _respawn_timers.get(pawn, 0.0)
		elif is_dead_val:
			pd.status = PlayerData.Status.DEAD
		else:
			pd.status = PlayerData.Status.ALIVE

# ═══════════════════════════════════════════
# REPORTE DE MUERTES Y ESTADISTICAS
# ═══════════════════════════════════════════

## Metodo UNIFICADO para reportar una muerte.
## `victim_pawn` es el nodo que murio (Player o NpcBase).
## `killer_id` es el player_id del asesino (-1 si fue muerte accidental/environmental).
func reportar_muerte(victim_pawn: Node, killer_id: int = -1) -> void:
	var victim_id: int = _pawn_to_player_id.get(victim_pawn, -1)
	if victim_id < 0:
		return  # No registrado, ignorar
	
	var victim_data: PlayerData = _players_data.get(victim_id)
	if not victim_data:
		return
	
	# Incrementar muertes de la victima
	victim_data.deaths += 1
	
	# Incrementar kills del asesino
	if killer_id >= 0 and _players_data.has(killer_id):
		_players_data[killer_id].kills += 1
	
	# Notificar al Scoreboard
	players_data_changed.emit()

func reset_match() -> void:
	# Limpiar todo para una nueva partida
	for bot in bot_pool:
		if is_instance_valid(bot):
			bot.queue_free()
	bot_pool.clear()
	_inactive_bots.clear()
	_respawn_timers.clear()
	spawn_points_blue.clear()
	spawn_points_red.clear()
	blue_bots_active = 0
	red_bots_active = 0
	_match_started = false
	player = null
	player_team = int(Enums.Equipo.ESPECTADOR)
	# Limpiar registro de jugadores
	_players_data.clear()
	_pawn_to_player_id.clear()
	_next_player_id = 1000
	# Limpiar estado de GameState
	if is_instance_valid(GameState):
		GameState.reset_match()
	print("[MatchManager] Partida reseteada")
