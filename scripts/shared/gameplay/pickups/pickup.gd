# scripts/pickup.gd
# Clase base para TODOS los objetos recogibles del juego (armas, vida,
# munición, armaduras, objetos especiales).
#
# Extiende RigidBody3D para que al caer al suelo tenga física real,
# repose sobre el terreno y no atraviese el piso.
#
# Cada pickup lleva un Area3D hijo ("PickupArea") que detecta
# automáticamente a personajes (Player y NpcBase) que se acerquen.
#
# CÓMO EXTENDER:
#   1. Define un nuevo valor en el enum Type
#   2. Extiende esta clase
#   3. Implementa _on_picked_up(picker) con tu lógica específica
#   4. Opcional: sobreescribe _update_visual() para tu representación gráfica
extends RigidBody3D
class_name Pickup

# ─── Tipos de pickup ──────────────────────────────────────────────────
# Añadir nuevos tipos aquí cuando se implementen health/ammo/armor/special
enum Type { WEAPON, HEALTH, AMMO, ARMOR, SPECIAL }

# ─── Configuración exportada ──────────────────────────────────────────
## Tipo de pickup (WEAPON, HEALTH, AMMO, etc.)
@export var pickup_type: int = Type.WEAPON
## Segundos antes de desaparecer automáticamente (0 = permanente)
@export var lifetime: float = 30.0

# ─── Datos específicos del contenido ──────────────────────────────────
## Diccionario genérico con los datos del pickup.
## Para armas: {"tipo_arma", "balas_cargador", "balas_reserva", "capacidad_cargador"}
## Para salud: {"curacion"}
## Para munición: {"tipo_municion", "cantidad"}
var pickup_data: Dictionary = {}

# ─── Señales ──────────────────────────────────────────────────────────
## Se emite cuando alguien recoge el pickup, justo antes de destruirlo.
signal picked_up(pickup: Node, picker: Node)

# ─── Referencias a nodos hijo ─────────────────────────────────────────
@onready var pickup_area: Area3D = $PickupArea
@onready var despawn_timer: Timer = $DespawnTimer
@onready var label_3d: Label3D = $Label3D
@onready var _pickup_manager = get_node("/root/PickupManager")

# ─── Inicialización ───────────────────────────────────────────────────
func _ready() -> void:
	# Registrar en el gestor global de pickups
	if _pickup_manager:
		_pickup_manager.register(self)

	# ── Configurar físicas ──────────────────────────────────────────
	# FASE 1: Caída inicial. El pickup está en capa 1 para colisionar
	#         con el mundo (suelo/paredes) y reposar físicamente.
	#         El jugador lo detecta (su mask=13 incluye capa 1), pero
	#         solo durante la fracción de segundo que tarda en caer.
	collision_layer = 1
	collision_mask = 1
	gravity_scale = 1.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body_entered.connect(_on_physics_body_entered)

	# ── Configurar área de detección ────────────────────────────────
	# Detecta personajes en capa 2 (CharacterBody: Player + NpcBase)
	if pickup_area:
		pickup_area.collision_layer = 0
		pickup_area.collision_mask = 2
		pickup_area.body_entered.connect(_on_area_body_entered)
		pickup_area.body_exited.connect(_on_area_body_exited)

	# ── Timer de despawn ────────────────────────────────────────────
	if despawn_timer and lifetime > 0.0:
		despawn_timer.wait_time = lifetime
		despawn_timer.one_shot = true
		despawn_timer.start()
		despawn_timer.timeout.connect(_on_despawn_timeout)

	# ── Transición a FASE 2 ─────────────────────────────────────────
	# Después de ~1s el pickup ya reposa en el suelo. Lo congelamos y
	# lo movemos a capa 9 (NO escaneada por Player mask=13 ni NPC
	# mask=15). El jugador/NPC ya no choca físicamente con él, pero
	# el PickupArea (mask=2) sigue detectando personajes para recoger.
	sleeping_state_changed.connect(_on_sleeping_state_changed)
	# Fallback por si el body nunca duerme (ej. sobre superficie móvil)
	if not sleeping:
		await get_tree().create_timer(1.5).timeout
		if not is_queued_for_deletion() and not sleeping:
			_disable_player_collision()

	# ── Visual ──────────────────────────────────────────────────────
	_update_visual()

# ─── Método virtual (implementar en subclases) ────────────────────────
## Se llama cuando un personaje recoge este pickup.
## Recibe el Node que lo recogió (Player o NpcBase).
func _on_picked_up(_picker: Node) -> void:
	pass

# ─── Método virtual para visual (implementar en subclases) ────────────
func _update_visual() -> void:
	pass

# ─── Recoger el pickup ────────────────────────────────────────────────
## Llamado cuando un personaje válido toca el área de recogida.
func pick_up(picker: Node) -> void:
	if not is_instance_valid(picker):
		return

	# Llamar a la lógica específica del subtipo
	_on_picked_up(picker)
	picked_up.emit(self, picker)

	# Limpieza
	if _pickup_manager:
		_pickup_manager.unregister(self)
	queue_free()

# ─── Detección por área ───────────────────────────────────────────────
func _on_area_body_entered(body: Node) -> void:
	if not body is CharacterBody3D:
		return

	# No recoger si está muerto
	if body.get("is_dead") == true:
		return

	# Permitir que el personaje decida si puede/puede recoger
	# El personaje llama a pick_up() cuando confirma la recogida
	if body.has_method("_on_pickup_area_entered"):
		body._on_pickup_area_entered(self)
	else:
		# Fallback: recoger directamente
		pick_up(body)

## Notifica al personaje cuando sale del área de recogida.
func _on_area_body_exited(body: Node) -> void:
	if not body is CharacterBody3D:
		return
	
	if body.has_method("_on_pickup_area_exited"):
		body._on_pickup_area_exited(self)

# ─── Transición a FASE 2: desactivar colisión con personajes ──────────
## Detecta cuando el RigidBody entra en reposo (sleeping) y desactiva
## la colisión física con personajes cambiando de capa.
func _on_sleeping_state_changed() -> void:
	if sleeping:
		_disable_player_collision()

## Desactiva la colisión física con jugadores/NPCs moviendo el pickup
## a la capa 9 (valor 256). El jugador (mask=13 -> capas 1,3,4) y el
## NPC (mask=15 -> capas 1,2,3,4) no escanean la capa 9, por lo que
## el personaje atraviesa el pickup sin obstrucción.
##
## El PickupArea (mask=2) sigue detectando personajes independientemente.
func _disable_player_collision() -> void:
	if freeze:
		return  # Ya está en fase 2

	# Congelar en la posición actual (no más físicas)
	freeze = true

	# Cambiar a capa dedicada para pickups (capa 9, valor 256)
	# Player mask=13 → capas 1,3,4  → NO incluye 9  ✓
	# NPC    mask=15 → capas 1,2,3,4 → NO incluye 9  ✓
	# El pickup conserva mask=1 por si el sistema de físicas lo requiere
	# NOTA: En Godot las capas son bits: capa N = 1 << (N-1)
	collision_layer = 256  # capa 9 (1 << 8)
	collision_mask = 1

# ─── Congelar al reposar (legacy) ─────────────────────────────────────
func _on_physics_body_entered(_body: Node) -> void:
	# Cuando el pickup colisiona con algo (suelo), reducir fricción
	# y permitir que repose sin rebotar
	pass

# ─── Despawn por tiempo ───────────────────────────────────────────────
func _on_despawn_timeout() -> void:
	if _pickup_manager:
		_pickup_manager.unregister(self)
	queue_free()
