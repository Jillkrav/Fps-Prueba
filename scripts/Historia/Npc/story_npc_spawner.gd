class_name StoryNPCSpawner
extends Node3D

## Spawner genérico de NPCs para niveles de Historia.
##
## Se coloca en cualquier mapa de Historia y se configura entero desde el
## Inspector:
##   - Qué NPC spawnea (NpcType CUERPO_A_CUERPO/TIRADOR + opcional override_scene).
##   - A qué facción pertenece (faction_id; ver story_factions.json).
##   - Qué "skin" lleva: aleatoria, manual (skin_color) o por facción.
##   - Cómo se comporta (spawn_behavior: Patrulla / Guardia) + parámetros de IA.
##   - Grupo NO oleada: spawn_count totales, con tope de vivos a la vez
##     (max_alive) y reposición (respawn_delay) mientras mueren.
##   - Salud máxima (max_health), arma(s) del TIRADOR y drop al morir. Para
##     los TIRADORES puedes elegir UNA arma (weapon_name) o VARIAS a la vez
##     (weapon_names): con varias, cada NPC del grupo recibe un arma distinta
##     de la lista, en orden de selección (weapon_assignment_mode=SEQUENTIAL)
##     o al azar (RANDOM).
##   - Qué lo activa (TriggerMode, ver enum).
##
## Expone la interfaz estándar del proyecto (activate / deactivate / toggle),
## así que puede conectarse a un StoryActionButton, a una StoryInvisibleWall o
## a cualquier otro elemento que llame a esos métodos.
##
## Para AÑADIR un nuevo tipo de NPC en el futuro:
##   1. Añade un valor al enum NpcType.
##   2. Añade su ruta a NPC_SCENES.
##   3. (Alternativa sin tocar el código) asigna su escena a override_scene.
## El NPC instanciado debe, preferiblemente con el método apply_spawn_config(cfg),
## consumir la configuración que este spawner le aplica (faccion, skin, modo,
## visión, radios). Ver CuerpoACuerpo como referencia.
##
## Convenciones mínimas para NPCs que NO implementan apply_spawn_config:
##   - Propiedad `faction_id` (int): se le asigna la facción del spawner.
##   - Propiedad `equipo_id` (int): se le asigna igual que faction_id. Puede ser
##     una variable interna (no export); el spawner la asigna con set().
##   - Método `apply_skin_color(color)`: recibe el color de skin elegido.
##   - Señal `died` (o tree_exited): se usa para dejar de seguir al NPC.

signal spawner_activated(spawner: StoryNPCSpawner)
signal spawner_deactivated(spawner: StoryNPCSpawner)
signal npc_spawned(spawner: StoryNPCSpawner, npc: Node3D)
signal spawner_finished(spawner: StoryNPCSpawner)
## Se emite cuando el grupo ha terminado por completo: no quedan NPCs por tirar
## y ningún NPC spawnado sigue vivo. Útil para objetivos "elimina a todos".
signal spawner_enemies_cleared(spawner: StoryNPCSpawner)

## Tipos de NPC disponibles. Ampliar al crear más NPCs.
enum NpcType {
	CUERPO_A_CUERPO,   ## Zombie / cuerpo a cuerpo (CuerpoACuerpo).
	TIRADOR,  ## Soldado armado con cualquier arma del arsenal (Tirador).
}

## Registro tipo -> escena. Ampliar aquí al crear más NPCs.
const NPC_SCENES: Dictionary = {
	NpcType.CUERPO_A_CUERPO: "res://scenes/Historia/npc/personajes/cuerpo_a_cuerpo.tscn",
	NpcType.TIRADOR: "res://scenes/Historia/npc/personajes/tirador.tscn",
}

enum TriggerMode {
	START_ON_READY,     ## Empieza a invocar solo al cargar el nivel.
	MANUAL_INTERACT,    ## El jugador pulsa la acción estando en la zona.
	AUTOMATIC_ON_ENTER, ## Empieza cuando el jugador entra en la zona.
	EXTERNAL_SIGNAL,    ## Lo activa algo externo (botón, pared...) vía activate().
}

## Modo de comportamiento BASE que se aplica a los NPCs al spawnearlos.
## Determina el ocioso y la disciplina de movimiento. El combate "asaltante"
## se activa aparte con el flag independiente `aggressive_enabled`.
enum SpawnBehavior {
	PATROL,     ## Exploración real sin límite de radio (respeta el navmesh y los obstáculos).
	GUARD,      ## Guardia dentro del punto de aparición; ataca solo al ver enemigos.
}

## Skins provisionales: mientras no existan modelos reales, cada "skin" es un
## color distinto. La paleta tiene 7 colores.
enum SkinColor {
	VERDE,
	ROJO,
	AZUL,
	AMARILLO,
	BLANCO,
	NEGRO,
	MORADO,
}

enum SkinSource {
	RANDOM_COLOR,  ## Cada NPC saca un color al azar de la paleta de 7.
	FIXED_COLOR,   ## Todos usan el color manual (skin_color) que elijas.
	FACTION_COLOR, ## Skin de FACCIÓN: el color que la facción define en
				   ## story_factions.json (skin por facción).
}

## Cómo se reparten las armas entre los TIRADORES cuando en el spawner se
## seleccionan VARIAS a la vez (export `weapon_names`).
enum WeaponAssignmentMode {
	SEQUENTIAL, ## En el ORDEN de selección: el 1º NPC con la 1ª arma, el 2º
				## con la 2ª, etc. Si hay más NPCs que armas, se vuelve a
				## empezar la lista (ciclo).
	RANDOM,     ## Cada NPC saca un arma al azar de la lista seleccionada.
}

## Paleta de 7 "skins" de color (a falta de modelos reales).
const SKIN_COLOR_VALUES: Dictionary = {
	SkinColor.VERDE:    Color("#5fbf4f"),
	SkinColor.ROJO:     Color("#d84f3f"),
	SkinColor.AZUL:     Color("#3f6fd8"),
	SkinColor.AMARILLO: Color("#d8c23f"),
	SkinColor.BLANCO:   Color("#e8e8e0"),
	SkinColor.NEGRO:    Color("#2a2a2e"),
	SkinColor.MORADO:   Color("#a14fd8"),
}

@export_category("Perfil reutilizable")
## Si asignas un StoryNPCVariant (.tres), define escena, facción, IA, skin y
## arma del NPC. Las propiedades clásicas de abajo quedan como fallback.
## Recurso StoryNPCVariant. Resource evita dependencia de indexación al importar.
@export var npc_variant: Resource = null

@export_category("Spawn")
@export var npc_type: NpcType = NpcType.CUERPO_A_CUERPO
## Escena alternativa al NpcType. Si se rellena, se usa esta en su lugar
## (útil para prototipar NPCs nuevos antes de registrarlos en NpcType).
@export var override_scene: PackedScene = null
## Número TOTAL de NPCs que tira este spawner (todo el grupo). No es una oleada:
## con max_alive puedes limitar cuántos están vivos a la vez.
@export_range(1, 999, 1) var spawn_count: int = 1
## Máximo de NPCs VIVOS al mismo tiempo (pool concurrente). Ej.: spawn_count=10,
## max_alive=3 -> solo verás 3 a la vez y según mueran se van reponiendo hasta
## completar los 10. -1 = sin límite (comportamiento clásico: todos a la vez).
@export_range(-1, 999, 1) var max_alive: int = -1
## Ritmo de spawn INICIAL: cuántos NPCs aparecen por segundo al llenar el pool.
@export_range(0.05, 100.0, 0.05) var spawn_rate: float = 1.0
## Segundos de espera tras la muerte de un NPC antes de reponer otro (solo si
## max_alive > 0 y todavía quedan NPCs del grupo). 0 = repone casi al instante.
@export_range(0.0, 60.0, 0.1) var respawn_delay: float = 1.5
## Desplazamiento aleatorio horizontal alrededor del SpawnPoint para que los
## NPCs no aparezcan apilados en el mismo punto.
@export_range(0.0, 8.0, 0.1) var spread_radius: float = 1.5
## Desplazamiento vertical aplicado a cada NPC al aparecer (posar sobre el suelo).
@export_range(-2.0, 2.0, 0.05) var spawn_height_offset: float = 0.05

@export_category("Stats")
## Salud MÁXIMA que se asigna a los NPCs que spawnea. -1 = usar la salud propia
## de cada NPC (la de su escena). Permite endurecer/suavizar un grupo completo
## o hacer un "mini-boss" sin nueva escena.
@export_range(-1.0, 100000.0, 1.0) var max_health: float = -1.0

@export_category("Facción")
## Facción de los NPCs que spawnea. Ver config/Historia/story_factions.json:
## 1 = Jugador y aliados, 2 = Zombies y aliens, 3 = Soldados enemigos, ...
## La enemistad la resuelve StoryFactionSystem (el modo guardia/patrulla y el
## combate NPC vs NPC futuro dependen de esto).
@export var faction_id: int = int(StoryFactionSystem.ENEMY_FACTION)

@export_category("Skin")
@export var skin_source: SkinSource = SkinSource.RANDOM_COLOR
@export var skin_color: SkinColor = SkinColor.VERDE

@export_category("Comportamiento")
## PATROL: los NPCs deambulan por la zona y persiguen al ver enemigos.
## GUARD : se quedan quietos en su puesto y atacan solo al ver al enemigo.
@export var spawn_behavior: SpawnBehavior = SpawnBehavior.PATROL
## Combate ASALTANTE (independiente del modo base `spawn_behavior`): los
## TIRADORES avanzan disparando, retroceden si el enemigo se acerca y corren
## al cadáver de sus bajas. Aplica tanto a PATROL como a GUARD. Los NPCs
## cuerpo a cuerpo lo ignoran (su IA no tiene combate agresivo).
@export var aggressive_enabled: bool = false
## Distancia máxima a la que los NPCs detectan/ven enemigos.
@export_range(1.0, 60.0, 0.5) var vision_range: float = 12.0
## Apertura del cono de visión en grados (360 = ven en todas direcciones).
@export_range(30.0, 360.0, 10.0) var vision_fov_degrees: float = 120.0
## Radio de deambulación alrededor del punto de aparición (solo PATROL).
@export_range(0.0, 20.0, 0.5) var wander_radius: float = 6.0
## Radio máximo alrededor de su puesto desde el que un guardia persigue al
## objetivo antes de volver a su puesto (solo GUARD).
@export_range(0.0, 40.0, 0.5) var guard_radius: float = 10.0

@export_category("Armas (solo TIRADOR)")
## Arma del arsenal con la que se equipa a cada TIRADOR que spawnea este
## spawner. Los NPCs CUERPO A CUERPO ignoran esta propiedad.
@export_enum("USP", "Glock", "Deagle", "M3", "Spas12", "Recortada", "EscopetaAutomatica", "MP7", "MP5", "AUG", "M4", "G36", "Scout", "AWP", "Crowbar", "Tonfa", "Machete", "Cuchillo", "Granada", "Ballesta", "LanzaGranadas", "Bazooka", "RiflePlasma", "PistolaPlasma") var weapon_name: String = "Glock"
## LISTA de armas opcional. Si se rellena con VARIAS armas (p. ej.
## ["Glock", "MP5", "M3"]), cada TIRADOR del grupo recibe un arma de esta lista
## en vez de la única de arriba:
##   - weapon_assignment_mode = SEQUENTIAL: el 1º con la 1ª, el 2º con la 2ª...
##     (si hay más NPCs que armas, el ciclo vuelve a empezar por la 1ª).
##   - weapon_assignment_mode = RANDOM: cada NPC saca un arma al azar de la lista.
## Si queda VACÍA, se usa la arma única `weapon_name` (comportamiento clásico).
## Ejemplo: spawn_count = 3 con ["Pistola", "Subfusil", "Escopeta"] -> un NPC
## con cada arma.
@export_enum("USP", "Glock", "Deagle", "M3", "Spas12", "Recortada", "EscopetaAutomatica", "MP7", "MP5", "AUG", "M4", "G36", "Scout", "AWP", "Crowbar", "Tonfa", "Machete", "Cuchillo", "Granada", "Ballesta", "LanzaGranadas", "Bazooka", "RiflePlasma", "PistolaPlasma") var weapon_names: Array[String] = []
## Cómo se reparten las armas de `weapon_names` entre los TIRADORES del grupo
## (solo tiene efecto si weapon_names tiene más de un arma).
@export var weapon_assignment_mode: WeaponAssignmentMode = WeaponAssignmentMode.SEQUENTIAL
## Munición inicial en el cargador para TIRADOR (-1 = la normal del arma).
@export_range(-1, 9999, 1) var weapon_mag_override: int = -1
## Munición inicial en reserva para TIRADOR (-1 = la normal del arma).
@export_range(-1, 9999, 1) var weapon_reserve_override: int = -1
## Al morir, el TIRADOR suelta el arma como WeaponPickup que el jugador puede
## recoger (con la munición que le quedaba).
@export var drop_weapon_on_death: bool = true
## Config especial opcional para los TIRADORES (granadas, cobertura...).
@export var tirador_config: TiradorConfig = null

@export_category("Ciclo de vida")
## Si true, al deactivate() se liberan todos los NPCs vivos persistidos.
@export var despawn_on_deactivate: bool = false

@export_category("Trigger")
@export var trigger_mode: TriggerMode = TriggerMode.START_ON_READY
@export var action_name: StringName = &"interact"
## Si true, una vez completada la oleada el spawner ya no se puede reactivar.
@export var one_shot: bool = true
## Tamaño de la zona de trigger (MANUAL_INTERACT / AUTOMATIC_ON_ENTER).
@export var trigger_box_size: Vector3 = Vector3(4.0, 3.0, 4.0)
## Retardo en segundos antes de empezar a invocar (solo START_ON_READY).
@export_range(0.0, 10.0, 0.1) var initial_delay: float = 0.0

@export_category("Presentation")
@export var display_name: String = "SPAWNER"
@export var show_debug_visual: bool = true

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, el spawner NO participa en la
## persistencia (la oleada se reinicia al volver al mapa).
## Si se rellena: al volver, una oleada terminada no reaparece y una a medias
## se reanuda desde los NPC que quedaban por tirar.
@export var state_id: String = ""

@onready var spawn_point: Node3D = $SpawnPoint
@onready var debug_mesh: MeshInstance3D = $DebugMesh
@onready var trigger_area: Area3D = $TriggerArea
@onready var trigger_shape: CollisionShape3D = $TriggerArea/CollisionShape3D
@onready var trigger_zone_mesh: MeshInstance3D = $TriggerArea/DebugZoneMesh
@onready var spawn_timer: Timer = $SpawnTimer
@onready var prompt_label: Label3D = $PromptLabel

var is_active: bool = false
## true cuando el grupo ha terminado por completo y one_shot impide reactivar.
var has_finished: bool = false
## Total de NPCs instanciados en esta activación (acumulador informativo).
var spawned_total: int = 0
## NPCs VIVOS que ha spawnado este grupo (los que siguen en escena).
var spawned_npcs: Array[Node] = []

var _start_delay_timer: float = 0.0
var _player_in_range: Player = null
## NPCs del grupo que quedan por tirar (spawn_count - los lanzados).
var _pending: int = 0
## true cuando la próxima reposición es por muerte (usará respawn_delay) y no
## por el llenado inicial (usará spawn_rate).
var _refilling: bool = false
## Evita emitir spawner_enemies_cleared más de una vez por grupo.
var _clear_emitted: bool = false
## Índice del ciclo de armas (modo SEQUENTIAL): apunta a la siguiente arma de
## `weapon_names` que recibirá el próximo TIRADOR. Se reinicia en cada grupo.
var _weapon_cycle_index: int = 0


func _ready() -> void:
	trigger_area.body_entered.connect(_on_body_entered)
	trigger_area.body_exited.connect(_on_body_exited)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	_apply_trigger_box_size()
	_setup_debug_visuals()
	_apply_faction_color_to_debug()
	prompt_label.visible = false
	trigger_area.monitoring = trigger_mode == TriggerMode.MANUAL_INTERACT \
			or trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER
	if not state_id.is_empty():
		LevelStateManager.register(self)
		# Al volver al mapa, un spawner activado por botón/pared/trigger debe
		# reanudarse solo: si la oleada quedó a medias, sigue con los NPC que
		# faltaban; si terminó, no se reactiva. (START_ON_READY usa su propio
		# arranque con _start_spawning_checked.)
		if trigger_mode != TriggerMode.START_ON_READY:
			call_deferred("_apply_restored_spawn_state")
	if trigger_mode == TriggerMode.START_ON_READY:
		if initial_delay > 0.0:
			_start_delay_timer = initial_delay
		else:
			call_deferred("_start_spawning_checked")


func _process(delta: float) -> void:
	if _start_delay_timer <= 0.0:
		return
	_start_delay_timer = maxf(0.0, _start_delay_timer - delta)
	if _start_delay_timer == 0.0:
		_start_spawning_checked()


func _unhandled_input(event: InputEvent) -> void:
	if trigger_mode != TriggerMode.MANUAL_INTERACT:
		return
	if is_active:
		return
	if _player_in_range == null or not is_instance_valid(_player_in_range):
		return
	if event.is_action_pressed(action_name):
		activate()
		get_viewport().set_input_as_handled()


## ── Interfaz estándar (StoryActionButton / StoryInvisibleWall / externos) ──

## Comienza un GRUPO de spawn: se lanza spawn_count NPCs en total, manteniendo
## a lo sumo max_alive vivos a la vez (los que mueren se van reponiendo).
func activate() -> void:
	if one_shot and has_finished:
		return
	_start_spawning()


func _start_spawning() -> void:
	if is_active:
		return
	spawned_total = 0
	_pending = spawn_count
	_clear_emitted = false
	_refilling = false
	_weapon_cycle_index = 0
	is_active = true
	spawner_activated.emit(self)
	_spawn_cycle_step()


## Un paso del ciclo del pool: lanza un NPC si puede y programa el siguiente.
func _spawn_cycle_step() -> void:
	if not is_active:
		return
	if _pending > 0 and get_active_npc_count() < _effective_max_alive():
		_spawn_one()
		_pending -= 1
	if _pending > 0 and get_active_npc_count() < _effective_max_alive():
		# Sigue el llenado/reposición con el intervalo según el origen del spawn.
		var interval: float = maxf(respawn_delay if _refilling else 1.0 / spawn_rate, 0.01)
		spawn_timer.wait_time = interval
		spawn_timer.start()
	else:
		spawn_timer.stop()
		_refilling = false
		_check_finished()


## Límite de NPCs vivos a la vez. -1 = sin límite (todos los del grupo).
func _effective_max_alive() -> int:
	if max_alive <= 0:
		return 2147483647
	return max_alive


## Pausa el pool. Se reanuda con activate() (que arranca un grupo nuevo).
func deactivate() -> void:
	if not is_active:
		return
	spawn_timer.stop()
	is_active = false
	spawner_deactivated.emit(self)
	if despawn_on_deactivate:
		_despawn_all()


func toggle() -> void:
	if is_active:
		deactivate()
	else:
		activate()


func get_active_npc_count() -> int:
	var count: int = 0
	for npc: Node in spawned_npcs:
		if is_instance_valid(npc):
			count += 1
	return count


func _on_spawn_timer_timeout() -> void:
	_spawn_cycle_step()


func _spawn_one() -> void:
	if spawned_total >= spawn_count:
		return
	var packed: PackedScene = _resolve_packed_scene()
	if packed == null:
		push_error("[StoryNPCSpawner] %s: no se pudo resolver la escena de NPC (tipo %d)." % [name, npc_type])
		_stop_spawning()
		return
	var npc: Node3D = packed.instantiate() as Node3D
	if npc == null:
		push_error("[StoryNPCSpawner] %s: la escena no instanció un Node3D." % name)
		_stop_spawning()
		return
	var pos: Vector3 = spawn_point.global_position
	if spread_radius > 0.0 and spawned_total > 0:
		var angle: float = randf() * TAU
		var radius: float = randf() * spread_radius
		pos.x += cos(angle) * radius
		pos.z += sin(angle) * radius
	pos.y += spawn_height_offset
	# Normalmente el spawner cuelga del mapa (current_scene). Si no hay escena
	# actual (p. ej. tests), usamos el padre para no depender de ella.
	var target_parent: Node = get_tree().current_scene
	if target_parent == null:
		target_parent = get_parent()
	if target_parent == null:
		push_error("[StoryNPCSpawner] %s: sin destino donde instanciar el NPC." % name)
		return
	target_parent.add_child(npc)
	npc.global_position = pos
	_apply_npc_config(npc, pos)
	_track_npc(npc)
	spawned_total += 1
	npc_spawned.emit(self, npc)


func _stop_spawning() -> void:
	spawn_timer.stop()
	is_active = false


# ── Persistencia de campaña (data-driven) ────────────────────────────────────
# Contrato: register + _restore_persistent_state + get_persistent_state +
# apply_persistent_state (ver LevelStateManager).

## Estado guardado como "terminado" (la oleada ya no debe reactivarse).
func _state_says_done() -> bool:
	if state_id.is_empty():
		return false
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	return bool(st.get("done", false))


## Arranque para START_ON_READY respetando el estado persistente: si la oleada
## terminó no arranca; si estaba a medias, reanuda los NPC que faltaban.
func _start_spawning_checked() -> void:
	if not _apply_restored_spawn_state():
		_start_spawning()


## Aplica el estado persistente ANTES de spawmear. Devuelve true si el arranque
## ya está gestionado (oleada terminada o reanudada).
func _apply_restored_spawn_state() -> bool:
	if state_id.is_empty():
		return false
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	if st.is_empty():
		return false
	if bool(st.get("done", false)):
		has_finished = true
		is_active = false
		return true
	var pending: int = int(st.get("pending", -1))
	var spawned: int = int(st.get("spawned_total", 0))
	if pending > 0:
		# Oleada a medias: reanudar desde los NPC que quedaban por tirar.
		_pending = pending
		spawned_total = spawned
		_clear_emitted = false
		_refilling = false
		_weapon_cycle_index = 0
		is_active = true
		_spawn_cycle_step()
		return true
	if spawned >= spawn_count:
		# Todo el grupo ya se lanzó (aunque quedara alguno vivo al irnos):
		# al volver no respawneamos.
		has_finished = true
		is_active = false
		return true
	return false


func _restore_persistent_state() -> void:
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	apply_persistent_state(st)


func get_persistent_state() -> Dictionary:
	return {
		"done": has_finished or (spawned_total >= spawn_count and get_active_npc_count() == 0),
		"pending": _pending,
		"spawned_total": spawned_total,
	}


func apply_persistent_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if bool(state.get("done", false)):
		has_finished = true
		is_active = false


## El grupo termina cuando no quedan NPCs por tirar y ninguno sigue vivo.
func _check_finished() -> void:
	if get_active_npc_count() > 0 or _pending > 0:
		return
	if is_active:
		is_active = false
	if one_shot:
		has_finished = true
	spawner_finished.emit(self)
	if not _clear_emitted:
		_clear_emitted = true
		spawner_enemies_cleared.emit(self)


func _resolve_packed_scene() -> PackedScene:
	if npc_variant != null:
		var variant_scene: PackedScene = _resolve_variant_scene()
		if variant_scene != null:
			return variant_scene
	if override_scene != null:
		return override_scene
	var scene_path: String = NPC_SCENES.get(npc_type, "")
	if scene_path.is_empty():
		return null
	return load(scene_path) as PackedScene


## ── Configuración aplicada a cada NPC spawnado ────────────────────────────

func _resolve_variant_scene() -> PackedScene:
	if npc_variant == null:
		return null
	var override: PackedScene = npc_variant.get("scene_override") as PackedScene
	if override != null:
		return override
	var npc_type_id: String = str(npc_variant.get("npc_type_id"))
	var scene_path: String = StoryNPCConfig.get_npc_scene_path(npc_type_id)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_warning("[StoryNPCSpawner] Variante '%s' sin escena válida." % npc_type_id)
		return null
	return ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene


func _build_variant_spawn_config(pos: Vector3) -> Dictionary:
	if npc_variant == null:
		return {}
	var cfg: Dictionary = {
		"faction_id": int(npc_variant.get("faction_id")),
		"spawn_mode": int(npc_variant.get("spawn_mode")),
		"aggressive_enabled": bool(npc_variant.get("aggressive_enabled")),
		"vision_range": float(npc_variant.get("vision_range")),
		"vision_fov_degrees": float(npc_variant.get("vision_fov_degrees")),
		"wander_radius": float(npc_variant.get("wander_radius")),
		"guard_radius": float(npc_variant.get("guard_radius")),
		"spawn_position": pos,
		"skin_color": npc_variant.get("skin_color") as Color,
		"weapon_name": str(npc_variant.get("weapon_name")),
		"weapon_mag_override": int(npc_variant.get("weapon_mag_override")),
		"weapon_reserve_override": int(npc_variant.get("weapon_reserve_override")),
		"drop_weapon_on_death": bool(npc_variant.get("drop_weapon_on_death")),
	}
	if bool(npc_variant.get("override_max_health")):
		cfg["max_health"] = float(npc_variant.get("max_health"))
	if bool(npc_variant.get("override_movement_speed")):
		cfg["movement_speed"] = float(npc_variant.get("movement_speed"))
	if bool(npc_variant.get("override_melee_damage")):
		cfg["melee_damage"] = float(npc_variant.get("melee_damage"))
	var variant_tirador_config: Resource = npc_variant.get("tirador_config") as Resource
	if variant_tirador_config != null:
		cfg["tirador_config"] = variant_tirador_config
	return cfg


func _apply_npc_config(npc: Node3D, pos: Vector3) -> void:
	if npc_variant != null:
		var variant_cfg: Dictionary = _build_variant_spawn_config(pos)
		if npc.has_method("apply_spawn_config"):
			npc.call("apply_spawn_config", variant_cfg)
			return
		if "faction_id" in npc:
			npc.set("faction_id", int(variant_cfg.get("faction_id", faction_id)))
		if "equipo_id" in npc:
			npc.set("equipo_id", int(variant_cfg.get("faction_id", faction_id)))
		if npc.has_method("apply_skin_color"):
			npc.call("apply_skin_color", variant_cfg.get("skin_color", Color.WHITE) as Color)
		return
	var cfg: Dictionary = {
		"faction_id": faction_id,
		"spawn_mode": int(spawn_behavior),
		"aggressive_enabled": aggressive_enabled,
		"vision_range": vision_range,
		"vision_fov_degrees": vision_fov_degrees,
		"wander_radius": wander_radius,
		"guard_radius": guard_radius,
		"spawn_position": pos,
		"skin_color": _pick_skin_color(),
		# Salud (solo se aplica si se configuró; por defecto usa la del NPC).
		"max_health": max_health,
		# Armas (consumidas solo por NPCs que las soporten, como TIRADOR).
		# Se resuelve por NPC: lista de armas (orden/aleatorio) o la única.
		"weapon_name": _pick_weapon_para_tirador(),
		"weapon_mag_override": weapon_mag_override,
		"weapon_reserve_override": weapon_reserve_override,
		"drop_weapon_on_death": drop_weapon_on_death,
		"tirador_config": tirador_config,
	}
	if npc.has_method("apply_spawn_config"):
		npc.call("apply_spawn_config", cfg)
		return
	# Convenciones mínimas para NPCs que no implementan apply_spawn_config:
	if "faction_id" in npc:
		npc.set("faction_id", faction_id)
	if "equipo_id" in npc:
		npc.set("equipo_id", faction_id)
	if npc.has_method("apply_skin_color"):
		npc.call("apply_skin_color", cfg["skin_color"])


## Resuelve el arma del próximo TIRADOR a spawnear:
##   - Si hay lista de armas (weapon_names): la entrega según
##     weapon_assignment_mode — SEQUENTIAL (en orden de selección, con ciclo)
##     o RANDOM (al azar entre las armas de la lista).
##   - Si la lista está vacía: usa la arma única (weapon_name), el
##     comportamiento clásico del spawner.
func _pick_weapon_para_tirador() -> String:
	var weapons: Array[String] = _normalized_weapon_list()
	if weapons.is_empty():
		return weapon_name
	if weapon_assignment_mode == WeaponAssignmentMode.RANDOM:
		return weapons[randi_range(0, weapons.size() - 1)]
	var idx: int = _weapon_cycle_index % weapons.size()
	_weapon_cycle_index += 1
	return weapons[idx]


## Lista de armas seleccionadas (weapon_names) limpiada: sin entradas vacías
## y sin espacios sobrantes, para no repartir armas en blanco.
func _normalized_weapon_list() -> Array[String]:
	var out: Array[String] = []
	for w: String in weapon_names:
		var s: String = w.strip_edges()
		if not s.is_empty():
			out.append(s)
	return out


## Elige la skin según el SkinSource: aleatoria, manual (FIXED_COLOR) o de la
## facción (FACTION_COLOR, color definido en story_factions.json).
func _pick_skin_color() -> Color:
	match skin_source:
		SkinSource.FIXED_COLOR:
			return SKIN_COLOR_VALUES.get(skin_color, Color.WHITE)
		SkinSource.FACTION_COLOR:
			return StoryFactionSystem.get_color(faction_id)
		_:
			var keys: Array = SKIN_COLOR_VALUES.keys()
			var idx: int = randi_range(0, keys.size() - 1)
			return SKIN_COLOR_VALUES.get(keys[idx], Color.WHITE)


## ── Tracking de NPCs spawnados ────────────────────────────────────────────

func _track_npc(npc: Node) -> void:
	spawned_npcs.append(npc)
	if npc.has_signal("died"):
		npc.connect("died", _on_npc_died)
	else:
		npc.tree_exited.connect(_on_npc_freed.bind(npc))


func _on_npc_died(enemy: Node3D, _killer_id: int = -1) -> void:
	_release_npc(enemy)


func _on_npc_freed(npc: Node) -> void:
	_release_npc(npc)


func _release_npc(npc: Node) -> void:
	if not spawned_npcs.has(npc):
		return
	spawned_npcs.erase(npc)
	_maybe_refill()
	_check_finished()


## Tras una muerte, si el pool sigue en curso y hay hueco, programa la
## reposición de un NPC tras respawn_delay.
func _maybe_refill() -> void:
	if not is_active:
		return
	if _pending <= 0 or get_active_npc_count() >= _effective_max_alive():
		return
	if not spawn_timer.is_stopped():
		return
	_refilling = true
	spawn_timer.wait_time = maxf(respawn_delay, 0.01)
	spawn_timer.start()


func _despawn_all() -> void:
	for npc: Node in spawned_npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	spawned_npcs.clear()


## ── Zona de trigger ──

func _apply_trigger_box_size() -> void:
	var shape: Shape3D = trigger_shape.shape
	if shape is BoxShape3D:
		var box: BoxShape3D = shape.duplicate()
		box.size = trigger_box_size
		trigger_shape.shape = box


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player or body.is_in_group(&"player")):
		return
	_player_in_range = body as Player
	if trigger_mode == TriggerMode.MANUAL_INTERACT:
		prompt_label.text = "[E] %s" % display_name
		prompt_label.visible = true
	elif trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER:
		activate()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		prompt_label.visible = false


## ── Visuales de debug ──

func _setup_debug_visuals() -> void:
	debug_mesh.visible = show_debug_visual
	var zone_mesh: Mesh = trigger_zone_mesh.mesh
	if zone_mesh is BoxMesh:
		var box_mesh: BoxMesh = zone_mesh.duplicate()
		box_mesh.size = trigger_box_size
		trigger_zone_mesh.mesh = box_mesh
	trigger_zone_mesh.visible = show_debug_visual and (
		trigger_mode == TriggerMode.MANUAL_INTERACT or trigger_mode == TriggerMode.AUTOMATIC_ON_ENTER
	)


## Tiñe el gizmo de debug con el color de la facción para que el diseñador
## vea de un vistazo qué facción spawnea aquí.
func _apply_faction_color_to_debug() -> void:
	if not show_debug_visual:
		return
	var mat: StandardMaterial3D = debug_mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	var mat_copy: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
	var col: Color = StoryFactionSystem.get_color(faction_id)
	mat_copy.albedo_color = Color(col.r, col.g, col.b, 0.55)
	mat_copy.emission = col
	debug_mesh.material_override = mat_copy
