# teddy_animator.gd
# ──────────────────────────────────────────────────────────────────
# Controlador de animaciones para cualquier modelo con esqueleto
# Mixamo (Sin_nombre, Combine, GIGN, etc.).
#
# Carga las animaciones desde un AnimationSet (recurso externo) y
# las reproduce según el estado del NPC padre.
#
# ── SEGURIDAD ──
# - Si no encuentra AnimationSet o NPC, no hace nada (0 impacto)
# - Si una animación no carga, la omite (no crashea)
# - Si el AnimationPlayer no existe, no hace nada
# ──────────────────────────────────────────────────────────────────
extends Node3D
class_name TeddyAnimator

# ══════════════════════════════════════════════════════════════════
# EXPORTS
# ══════════════════════════════════════════════════════════════════

## Set de animaciones opcional. Si es null, el animador no carga animaciones.
## Usamos Resource como tipo para evitar dependencias del parser con class_name
@export var animation_set: Resource = null

## Nombre interno de cada animación dentro del AnimationPlayer.
const ANIM_IDLE: String = "idle"
const ANIM_WALK: String = "walk"
const ANIM_RUN: String = "run"
const ANIM_HIT: String = "hit"
const ANIM_DEATH: String = "death"
const ANIM_IDLE_CROUCH: String = "idle_crouch"
const ANIM_WALK_CROUCH: String = "walk_crouch"

## Claves de muerte en el AnimationSet.
const DEATH_KEY_FRONT: String = "death_front"
const DEATH_KEY_BACK: String = "death_back"
const DEATH_KEY_RIGHT: String = "death_right"
const DEATH_KEY_DEFAULT: String = "death_front"


# ══════════════════════════════════════════════════════════════════
# REFERENCIAS
# ══════════════════════════════════════════════════════════════════

var _animation_player: AnimationPlayer = null
var _npc: BotBase = null

## Última animación reproducida (para evitar transiciones repetidas).
var _current_anim: String = ""

## Flag: ya se disparó la animación de muerte (evita repetir).
var _death_animation_triggered: bool = false
## Flag: el NPC estaba muerto en el frame anterior (para detectar respawn).
var _was_dead: bool = false


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	# ── Buscar AnimationPlayer en la jerarquía ──
	_animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not _animation_player:
		push_warning("TeddyAnimator: No se encontró AnimationPlayer")
		set_process(false)
		return
	
	# ── Buscar NPC padre ──
	_npc = _find_npc_parent()
	
	# ── Cargar animaciones desde los FBX ──
	_load_animations()


func _process(_delta: float) -> void:
	if not _animation_player or not _npc:
		return
	
	# ── Prioridad 0: Muerte ──
	if _npc.is_dead:
		if not _death_animation_triggered:
			_play_death_animation()
			_death_animation_triggered = true
		_was_dead = true
		# Una vez muerto, no cambiar más la animación
		return
	
	# ── Detectar respawn (transición muerto → vivo) ──
	if _was_dead:
		_death_animation_triggered = false
		_current_anim = ""
		_was_dead = false
	
	# Determinar qué animación reproducir según el estado del NPC
	var target_anim: String = _get_target_animation()
	
	# Solo cambiar si es diferente a la actual
	if target_anim != _current_anim and _animation_player.has_animation(target_anim):
		_current_anim = target_anim
		_animation_player.play(target_anim, 0.15, 1.0, false)


# ══════════════════════════════════════════════════════════════════
# LÓGICA DE SELECCIÓN DE ANIMACIÓN
# ══════════════════════════════════════════════════════════════════

## Devuelve el nombre de la animación que debe reproducirse
## según el estado actual del NPC.
func _get_target_animation() -> String:
	if not _npc or not _npc.movement_sys:
		return ANIM_IDLE
	
	# ── Prioridad 1: Hit reaction ──
	# Si el NPC está en estado TAKING_HIT, reproducir hit
	if _npc.decision_sys and _npc.decision_sys.current_state:
		if _npc.decision_sys.current_state.state_type == BotState.StateType.TAKING_HIT:
			if _animation_player.has_animation(ANIM_HIT):
				return ANIM_HIT
	
	# ── Prioridad 2: Marcha (idle/walk/run/sprint/crouch) ──
	var gait: int = _npc.movement_sys.current_gait
	
	match gait:
		MovementSystem.MovementGait.CROUCH:
			# Si está quieto → idle_crouch, si se mueve → walk_crouch
			if _npc and Vector3(_npc.velocity.x, 0.0, _npc.velocity.z).length() > 0.3 and _animation_player.has_animation(ANIM_WALK_CROUCH):
				return ANIM_WALK_CROUCH
			elif _animation_player.has_animation(ANIM_IDLE_CROUCH):
				return ANIM_IDLE_CROUCH
			return ANIM_IDLE
		MovementSystem.MovementGait.SPRINT, MovementSystem.MovementGait.RUN:
			return ANIM_RUN
		MovementSystem.MovementGait.WALK:
			return ANIM_WALK
		_:
			return ANIM_IDLE


# ══════════════════════════════════════════════════════════════════
# CARGA DE ANIMACIONES DESDE FBX
# ══════════════════════════════════════════════════════════════════

## Carga animaciones desde el AnimationSet y las registra
## en el AnimationPlayer.
func _load_animations() -> void:
	if not _animation_player or not animation_set:
		return
	
	# Claves de animaciones base que cargamos siempre
	var base_keys: Array[String] = [
		ANIM_IDLE, ANIM_WALK, ANIM_RUN, ANIM_HIT,
		ANIM_IDLE_CROUCH, ANIM_WALK_CROUCH,
	]
	
	for key in base_keys:
		var filename: String = animation_set.animations.get(key, "")
		if filename.is_empty():
			continue
		var path: String = animation_set.fbx_directory.path_join(filename)
		_load_single_animation(path, key)
	
	# Si no se cargó idle, usar el embebido "mixamo_com"
	if not _animation_player.has_animation(ANIM_IDLE) and _animation_player.has_animation("mixamo_com"):
		var embedded: Animation = _animation_player.get_animation("mixamo_com")
		if embedded:
			_animation_player.add_animation(ANIM_IDLE, embedded)
			_current_anim = ANIM_IDLE


## Carga UNA animación desde un FBX de Mixamo.
## source puede ser una ruta res:// o uid://
func _load_single_animation(source: String, anim_name: String) -> void:
	if source.is_empty():
		return
	
	var fbx_scene: PackedScene = null
	
	# Intentar cargar como uid:// o res://
	if source.begins_with("uid://"):
		var uid: String = source
		fbx_scene = load(uid) as PackedScene
	else:
		fbx_scene = load(source) as PackedScene
	
	if not fbx_scene:
		push_warning("TeddyAnimator: No se pudo cargar: ", source)
		return
	
	# Instanciar temporalmente para extraer la animación
	var instance: Node = fbx_scene.instantiate()
	if not instance:
		return
	
	var fb_anim_player: AnimationPlayer = instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if fb_anim_player and fb_anim_player.has_animation("mixamo_com"):
		var anim: Animation = fb_anim_player.get_animation("mixamo_com")
		if anim:
			# Duplicar para independencia de recursos
			var anim_copy: Animation = anim.duplicate(true)
			anim_copy.resource_name = anim_name
			_animation_player.add_animation(anim_name, anim_copy)
	
	# Limpiar instancia temporal
	instance.queue_free()


# ══════════════════════════════════════════════════════════════════
# ANIMACIÓN DE MUERTE (ON-DEMAND)
# ══════════════════════════════════════════════════════════════════

## Reproduce la animación de muerte según la dirección del golpe mortal.
## Carga el FBX correspondiente on-demand desde el AnimationSet.
func _play_death_animation() -> void:
	if not _animation_player or not _npc or not animation_set:
		return
	
	# Seleccionar clave de death según death_direction
	var death_key: String = _select_death_key(_npc.death_direction)
	var death_filename: String = animation_set.animations.get(death_key, "")
	var death_path: String = ""
	if not death_filename.is_empty():
		death_path = animation_set.fbx_directory.path_join(death_filename)
	if death_path.is_empty():
		push_warning("TeddyAnimator: No hay death anim definida para: ", death_key)
		return
	
	# Cargar y extraer la animación (on-demand)
	var fbx_scene: PackedScene = load(death_path) as PackedScene
	if not fbx_scene:
		push_warning("TeddyAnimator: No se pudo cargar death: ", death_path)
		return
	
	var instance: Node = fbx_scene.instantiate()
	if not instance:
		return
	
	var fb_anim: AnimationPlayer = instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if fb_anim and fb_anim.has_animation("mixamo_com"):
		var anim: Animation = fb_anim.get_animation("mixamo_com")
		if anim:
			if _animation_player.has_animation(ANIM_DEATH):
				_animation_player.remove_animation(ANIM_DEATH)
			
			var anim_copy: Animation = anim.duplicate(true)
			anim_copy.resource_name = ANIM_DEATH
			anim_copy.loop_mode = Animation.LOOP_NONE
			_animation_player.add_animation(ANIM_DEATH, anim_copy)
			
			_current_anim = ANIM_DEATH
			_animation_player.play(ANIM_DEATH, 0.15, 1.0, false)
	
	instance.queue_free()


## Selecciona la clave del AnimationSet según la dirección del golpe.
## Retorna "death_front", "death_back" o "death_right".
func _select_death_key(death_dir: Vector3) -> String:
	if death_dir.length_squared() < 0.001:
		return DEATH_KEY_DEFAULT
	
	var forward: Vector3 = -_npc.global_transform.basis.z
	var right: Vector3 = _npc.global_transform.basis.x
	var dir_norm: Vector3 = death_dir.normalized()
	
	var fwd_dot: float = dir_norm.dot(forward)
	var right_dot: float = dir_norm.dot(right)
	
	if abs(right_dot) > 0.5 and right_dot > 0:
		return DEATH_KEY_RIGHT
	if fwd_dot > 0.3:
		return DEATH_KEY_FRONT
	return DEATH_KEY_BACK


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

## Busca el NPC padre ascendiendo en la jerarquía.
func _find_npc_parent() -> BotBase:
	var parent: Node = get_parent()
	while parent:
		if parent is BotBase:
			return parent as BotBase
		parent = parent.get_parent()
	return null
