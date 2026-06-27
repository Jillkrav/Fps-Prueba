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
## Señal emitida cuando el jugador humano respawnea automaticamente.
signal player_respawned()
signal team_sizes_updated(blue_size: int, red_size: int)

## Señal emitida cuando cambian los datos de los jugadores (kills, muertes, etc.)
## El Scoreboard se conecta a esta senal para refrescarse.
signal players_data_changed()

# ═══════════════════════════════════════════
# AUTO BALANCE — SEÑALES
# ═══════════════════════════════════════════

## Se emite cada segundo durante la cuenta regresiva del Auto Balance.
signal auto_balance_countdown(time_left: int)

## Se emite cuando el Auto Balance se cancela (los equipos se balancearon solos).
signal auto_balance_cancelled()

## Se emite cuando el Auto Balance mueve un jugador de equipo.
signal auto_balance_executed(pawn: Node, old_team: int, new_team: int)

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

# ═══════════════════════════════════════════
# AUTO BALANCE — CONFIGURACION
# ═══════════════════════════════════════════

## Tiempo de gracia en segundos antes de ejecutar el Auto Balance.
@export var auto_balance_grace_period: float = 5.0

## Si es true, el Auto Balance esta habilitado durante la partida.
@export var auto_balance_enabled: bool = true

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
# AUTO BALANCE — ESTADOS INTERNOS
# ═══════════════════════════════════════════

## Timer de cuenta regresiva para Auto Balance (en segundos).
var _auto_balance_timer: float = 0.0

## Indica si la cuenta regresiva de Auto Balance esta activa.
var _auto_balance_active: bool = false

## Cache del ultimo segundo mostrado para evitar emitir la senal innecesariamente.
var _last_countdown_second: int = -1

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
	# SOLO sobrescribir si el array entrante NO esta vacio.
	# Esto evita que _configure_spawners() destruya puntos registrados
	# por _auto_register_match_manager() de los spawners cuando
	# find_child("RedSpawner") falla.
	if not blue_points.is_empty():
		spawn_points_blue = blue_points.duplicate()
	if not red_points.is_empty():
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
	
	# Filtrar referencias invalidas (dangling tras reset_match + cambio de escena)
	points = points.filter(func(p): return is_instance_valid(p))
	
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
	
	# Asegurar que el bot no quede en la lista de inactivos
	if bot in _inactive_bots:
		_inactive_bots.erase(bot)
	
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

## Registra la muerte del jugador humano en el sistema de respawn unificado.
## A partir de ahora, el MatchManager gestiona el timer de respawn del jugador
## (como ya hace con los bots), y el HUD solo escucha la senal player_respawned.
func reportar_muerte_player() -> void:
	if not is_instance_valid(player):
		return
	if player.is_dead:
		_respawn_timers[player] = respawn_time
		# Actualizar PlayerData: pasar a estado RESPAWNING
		var pid: int = _pawn_to_player_id.get(player, -1)
		if pid >= 0 and _players_data.has(pid):
			var pd: PlayerData = _players_data[pid]
			pd.status = PlayerData.Status.RESPAWNING
			pd.respawn_time_left = respawn_time
			pd.health = 0.0
			_sync_player_data_from_pawn(pd)
			players_data_changed.emit()
		print("[MatchManager] Jugador murio. Respawn en %.1f s" % respawn_time)

func _process(delta: float) -> void:
	if not _match_started:
		return
	
	# Auto Balance: detectar desbalances y gestionar cuenta regresiva
	_check_team_balance(delta)
	
	# ── Gestionar timers de respawn (UNIFICADO: jugador + bots) ──
	var pawns_a_respawn: Array[Node] = []
	for pawn in _respawn_timers.keys():
		if not is_instance_valid(pawn):
			_respawn_timers.erase(pawn)
			continue
		_respawn_timers[pawn] -= delta
		if _respawn_timers[pawn] <= 0.0:
			pawns_a_respawn.append(pawn)
		
		# Actualizar respawn_time_left en PlayerData para los contadores en vivo
		var pid: int = _pawn_to_player_id.get(pawn, -1)
		if pid >= 0 and _players_data.has(pid):
			_players_data[pid].respawn_time_left = _respawn_timers.get(pawn, 0.0)
	
	for pawn in pawns_a_respawn:
		_respawn_timers.erase(pawn)
		if pawn == player:
			_respawnear_player()
		else:
			_respawnear_bot(pawn as NpcBase)
	
	# Sincronizar estados de todos los jugadores
	_sync_all_players_status()

## Respawnea al jugador humano cuando su timer de respawn expira.
func _respawnear_player() -> void:
	if not is_instance_valid(player):
		return
	
	player.respawn()
	
	# Actualizar PlayerData
	var pid: int = _pawn_to_player_id.get(player, -1)
	if pid >= 0 and _players_data.has(pid):
		var pd: PlayerData = _players_data[pid]
		pd.status = PlayerData.Status.ALIVE
		pd.respawn_time_left = 0.0
		_sync_player_data_from_pawn(pd)
		players_data_changed.emit()
	
	player_respawned.emit()
	print("[MatchManager] Jugador respawneado en %s" % GameState.nombre_equipo(GameState.player_team))

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
	"""Cambia al jugador humano de equipo.
	
	DELEGA en _cambiar_equipo_pawn() — la unica funcion de cambio de equipo.
	Mantiene esta funcion publica para compatibilidad con el codigo existente.
	"""
	if not is_instance_valid(player):
		return false
	if player_team == nuevo_equipo:
		return false  # Ya esta en ese equipo
	
	var old_team: int = player_team
	var success: bool = _cambiar_equipo_pawn(player, nuevo_equipo)
	
	if success:
		print("[MatchManager] Jugador cambio de %s a %s. Azul=%d, Rojo=%d" % [
			GameState.nombre_equipo(old_team),
			GameState.nombre_equipo(nuevo_equipo),
			blue_bots_active, red_bots_active
		])
	
	return success

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

## Cuenta jugadores activos totales (vivos, no inactivos) en un equipo, incluyendo muertos.
func _contar_miembros_por_equipo(team: int) -> int:
	var count: int = 0
	for pd in _players_data.values():
		if pd.team == team and pd.status != PlayerData.Status.INACTIVE:
			count += 1
	return count

# ═══════════════════════════════════════════
# CAMBIO DE EQUIPO UNIFICADO
# ═══════════════════════════════════════════

## Funcion UNICA de cambio de equipo.
## Tanto cambiar_equipo_jugador() como el Auto Balance pasan por aqui.
## Recibe cualquier pawn (Player o NpcBase) y lo mueve al nuevo equipo.
##
## NUEVO COMPORTAMIENTO (TF2-style):
## 1. Cambia el equipo internamente.
## 2. Mata al pawn usando el flujo de muerte existente (die()).
## 3. Entra en la cola de respawn normal.
## 4. Cuando el timer de respawn expire, respawnea en el spawn del NUEVO equipo.
##
## Devuelve true si el cambio se realizo con exito.
func _cambiar_equipo_pawn(pawn: Node, nuevo_equipo: int) -> bool:
	if not is_instance_valid(pawn):
		return false
	
	var is_player: bool = (pawn == player)
	var old_team: int
	
	if is_player:
		if player_team == nuevo_equipo:
			return false
		old_team = player_team
	else:
		var bot := pawn as NpcBase
		if not bot or bot not in bot_pool:
			return false
		if bot.equipo_id == nuevo_equipo:
			return false
		old_team = bot.equipo_id
	
	# ── Verificar capacidad del nuevo equipo ──
	var new_team_total: int = _contar_miembros_por_equipo(nuevo_equipo)
	if new_team_total >= max_per_team:
		# El equipo esta lleno. Intercambiar: desactivar un bot del nuevo equipo.
		var bot_to_deactivate: NpcBase = _encontrar_bot_activo_en_equipo(nuevo_equipo)
		if not bot_to_deactivate:
			push_warning("[MatchManager] No hay bot disponible para intercambiar en %s" % GameState.nombre_equipo(nuevo_equipo))
			return false
		
		if nuevo_equipo == int(Enums.Equipo.AZUL):
			blue_bots_active -= 1
		elif nuevo_equipo == int(Enums.Equipo.ROJO):
			red_bots_active -= 1
		_desactivar_bot(bot_to_deactivate)
		# _rellenar_equipo_con_bot_inactivo() lo activara para old_team si hay espacio
	
	# ── 1. ACTUALIZAR EQUIPO INTERNAMENTE ──
	if is_player:
		player_team = nuevo_equipo
		GameState.player_team = nuevo_equipo
	else:
		var bot := pawn as NpcBase
		# Decrementar contador del equipo ANTIGUO (el pawn sale de ese equipo)
		if old_team == int(Enums.Equipo.AZUL):
			blue_bots_active -= 1
		elif old_team == int(Enums.Equipo.ROJO):
			red_bots_active -= 1
		# Asignar al NUEVO equipo (el contador se incrementara al respawnear)
		bot.equipo_id = nuevo_equipo
	
	# ── 2. ACTUALIZAR PLAYERDATA ──
	var pid: int = _pawn_to_player_id.get(pawn, -1)
	if pid >= 0 and _players_data.has(pid):
		_players_data[pid].team = nuevo_equipo
		_sync_player_data_from_pawn(_players_data[pid])
		players_data_changed.emit()
	
	# ── 3. MATAR AL PAWN (usando el flujo de muerte existente) ──
	if is_player:
		if player.has_method("die"):
			player.die(-1)  # Sin asesino (cambio de equipo)
	else:
		var bot := pawn as NpcBase
		_kill_pawn_for_team_change(bot)
	
	# ── 4. RELLENAR EQUIPO ANTIGUO si hace falta ──
	if old_team != int(Enums.Equipo.ESPECTADOR):
		var old_alive: int = _contar_activos_por_equipo(old_team)
		if old_alive < max_per_team:
			_rellenar_equipo_con_bot_inactivo(old_team)
	
	# ── 5. RE-EVALUAR ENEMIGOS ──
	_re_evaluar_todos_los_enemigos()
	
	# ── 6. EMITIR SEÑALES ──
	team_changed.emit(pawn, old_team, nuevo_equipo)
	emit_team_sizes()
	print("[MatchManager] Pawn %s cambio de %s a %s (muerto, respawn en %.1f s para %s). Azul=%d, Rojo=%d" % [
		pawn.name,
		GameState.nombre_equipo(old_team),
		GameState.nombre_equipo(nuevo_equipo),
		respawn_time,
		GameState.nombre_equipo(nuevo_equipo),
		blue_bots_active, red_bots_active
	])
	return true

## Mata un bot especificamente para cambio de equipo.
## NO llama a reportar_muerte_bot() porque los contadores ya se actualizaron
## manualmente en _cambiar_equipo_pawn().
## Solo reporta estadisticas (killer_id=-1, no cuenta como kill).
func _kill_pawn_for_team_change(bot: NpcBase) -> void:
	if bot.is_dead:
		return
	
	bot.is_dead = true
	
	# Reportar estadisticas (killer_id=-1 para que nadie reciba kill)
	if is_instance_valid(MatchManager):
		MatchManager.reportar_muerte(bot, -1)
	
	# Soltar arma (efecto visual)
	if bot.has_method("_drop_weapon"):
		bot._drop_weapon()
	
	# Deshabilitar fisicas, proceso y visibilidad
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.hide()
	
	# Deshabilitar colision
	var cs: CollisionShape3D = bot.find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = true
	
	# Detener navegacion
	if bot.navigation_agent:
		bot.navigation_agent.target_position = bot.global_position
	
	# Iniciar timer de respawn para el NUEVO equipo (equipo_id ya se actualizo)
	_respawn_timers[bot] = respawn_time
	
	# Actualizar PlayerData a estado RESPAWNING
	var pid: int = _pawn_to_player_id.get(bot, -1)
	if pid >= 0 and _players_data.has(pid):
		var pd: PlayerData = _players_data[pid]
		pd.status = PlayerData.Status.RESPAWNING
		pd.respawn_time_left = respawn_time
		pd.health = 0.0
		_sync_player_data_from_pawn(pd)
		players_data_changed.emit()
	
	print("[MatchManager] Bot %s muerto por cambio de equipo. Respawn para %s en %.1f s" % [
		bot.name,
		GameState.nombre_equipo(bot.equipo_id),
		respawn_time
	])

## Re-evalua los enemigos de todos los NPCs vivos.
func _re_evaluar_todos_los_enemigos() -> void:
	for bot in bot_pool:
		if is_instance_valid(bot) and not bot.is_dead and bot.has_method("_re_evaluar_enemigos"):
			bot._re_evaluar_enemigos()
	# El jugador tambien re-evalua si tiene el metodo
	if is_instance_valid(player) and player.has_method("_re_evaluar_enemigos"):
		player._re_evaluar_enemigos()

# ═══════════════════════════════════════════
# AUTO BALANCE
# ═══════════════════════════════════════════

## Verifica si hay desbalance y gestiona la cuenta regresiva.
## Se llama desde _process().
func _check_team_balance(delta: float) -> void:
	if not _match_started or not auto_balance_enabled:
		return
	if not is_instance_valid(GameState) or not GameState.match_active:
		return
	
	var blue_count: int = _contar_miembros_por_equipo(int(Enums.Equipo.AZUL))
	var red_count: int = _contar_miembros_por_equipo(int(Enums.Equipo.ROJO))
	
	# El desbalance se define como > 1 jugador de diferencia
	var diff: int = abs(blue_count - red_count)
	var is_unbalanced: bool = (diff > 1)
	
	if is_unbalanced and not _auto_balance_active:
		# Iniciar cuenta regresiva
		_start_auto_balance_countdown()
	elif not is_unbalanced and _auto_balance_active:
		# Los equipos se balancearon solos, cancelar
		_cancel_auto_balance()
	
	# Si la cuenta regresiva esta activa, actualizarla
	if _auto_balance_active:
		_auto_balance_timer -= delta
		
		# Emitir senal cada segundo
		var current_second: int = int(ceil(_auto_balance_timer))
		if current_second != _last_countdown_second and current_second >= 0:
			_last_countdown_second = current_second
			auto_balance_countdown.emit(current_second)
		
		# Si el tiempo se acabo, ejecutar
		if _auto_balance_timer <= 0.0:
			_execute_auto_balance()

func _start_auto_balance_countdown() -> void:
	_auto_balance_timer = auto_balance_grace_period
	_auto_balance_active = true
	_last_countdown_second = int(ceil(auto_balance_grace_period))
	# Emitir el primer tick inmediatamente
	auto_balance_countdown.emit(_last_countdown_second)
	print("[MatchManager] Auto Balance iniciado. Cuenta regresiva: %.0f s" % auto_balance_grace_period)

func _cancel_auto_balance() -> void:
	_auto_balance_active = false
	_auto_balance_timer = 0.0
	_last_countdown_second = -1
	auto_balance_cancelled.emit()
	print("[MatchManager] Auto Balance cancelado — los equipos se balancearon solos.")

## Ejecuta el Auto Balance: mueve un jugador del equipo con mas integrantes
## al equipo con menos integrantes.
func _execute_auto_balance() -> void:
	_auto_balance_active = false
	_auto_balance_timer = 0.0
	_last_countdown_second = -1
	
	var blue_count: int = _contar_miembros_por_equipo(int(Enums.Equipo.AZUL))
	var red_count: int = _contar_miembros_por_equipo(int(Enums.Equipo.ROJO))
	
	if blue_count == red_count:
		print("[MatchManager] Auto Balance cancelado — equipos ya estan balanceados.")
		auto_balance_cancelled.emit()
		return
	
	# Determinar equipo sobrepoblado y subpoblado
	var from_team: int
	var to_team: int
	if blue_count > red_count:
		from_team = int(Enums.Equipo.AZUL)
		to_team = int(Enums.Equipo.ROJO)
	else:
		from_team = int(Enums.Equipo.ROJO)
		to_team = int(Enums.Equipo.AZUL)
	
	# Seleccionar que jugador mover (usa la estrategia actual)
	var pawn_to_move: Node = _select_player_to_move(from_team)
	if not pawn_to_move:
		push_warning("[MatchManager] No se pudo seleccionar un jugador para Auto Balance desde %s" % GameState.nombre_equipo(from_team))
		auto_balance_cancelled.emit()
		return
	
	var old_team_of_pawn: int = from_team
	var success: bool = _cambiar_equipo_pawn(pawn_to_move, to_team)
	
	if success:
		auto_balance_executed.emit(pawn_to_move, old_team_of_pawn, to_team)
		print("[MatchManager] Auto Balance ejecutado: %s movido de %s a %s" % [
			pawn_to_move.name,
			GameState.nombre_equipo(old_team_of_pawn),
			GameState.nombre_equipo(to_team)
		])
	else:
		push_warning("[MatchManager] Fallo al ejecutar Auto Balance para %s" % pawn_to_move.name)
		auto_balance_cancelled.emit()

## Selecciona que jugador mover del equipo sobrepoblado.
## Esta funcion esta DISENADA para ser facilmente intercambiable en el futuro.
## Estrategias futuras posibles:
##   - Mover solo bots (excluir humanos)
##   - Mover al jugador con menor puntaje (kills-deaths)
##   - No mover jugadores que aparecieron hace pocos segundos
##   - Balancear solo al finalizar una ronda
##
## Actual: seleccion aleatoria entre los miembros del equipo.
func _select_player_to_move(team: int) -> Node:
	var candidates: Array[Node] = []
	
	# Recolectar candidatos del equipo
	for pd in _players_data.values():
		if pd.team == team and pd.status != PlayerData.Status.INACTIVE and is_instance_valid(pd.pawn):
			candidates.append(pd.pawn)
	
	if candidates.is_empty():
		return null
	
	# ESTRATEGIA ACTUAL: seleccion aleatoria
	return candidates[randi() % candidates.size()]
	#
	# ESTRATEGIAS FUTURAS (ejemplos):
	#
	# Estrategia 1: Solo bots, excluir humano
	#   var human_filtered: Array[Node] = []
	#   for c in candidates:
	#       if c != player: human_filtered.append(c)
	#   if human_filtered.is_empty(): return null
	#   return human_filtered[randi() % human_filtered.size()]
	#
	# Estrategia 2: Peor puntaje (menos kills - deaths)
	#   candidates.sort_custom(func(a, b): return _get_score(a) < _get_score(b))
	#   return candidates[0]
	#
	# Estrategia 3: Peor rendimiento + evitar recien aparecidos
	#   var now: float = Time.get_ticks_msec()
	#   var filtered: Array[Node] = []
	#   for c in candidates:
	#       var pd := _players_data.get(_pawn_to_player_id.get(c, -1))
	#       if pd and (now - pd.spawn_time_ms > 5000.0): filtered.append(c)
	#   if filtered.is_empty(): filtered = candidates
	#   filtered.sort_custom(func(a, b): return _get_score(a) < _get_score(b))
	#   return filtered[0]

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
		# NOTA: _inactive_bots es Array[NpcBase], solo verificamos si pawn es NpcBase
		# para evitar errores de TypedArray con el jugador (Player).
		if pawn is NpcBase and pawn in _inactive_bots:
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
	# ★ PRESERVAR spawn points para que "Reintentar" funcione sin recargar escena.
	# _configure_spawners() los sobrescribira al iniciar una nueva partida real.
	blue_bots_active = 0
	red_bots_active = 0
	_match_started = false
	# Limpiar estado de Auto Balance
	_auto_balance_timer = 0.0
	_auto_balance_active = false
	_last_countdown_second = -1
	player = null
	player_team = int(Enums.Equipo.ESPECTADOR)
	# Limpiar registro de jugadores
	_players_data.clear()
	_pawn_to_player_id.clear()
	_next_player_id = 1000
	# Limpiar estado de GameState
	if is_instance_valid(GameState):
		GameState.reset_match()
	print("[MatchManager] Partida reseteada (spawn points preservados: Azul=%d, Rojo=%d)" % [spawn_points_blue.size(), spawn_points_red.size()])
