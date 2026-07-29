# scripts/vault_controller.gd
# ─────────────────────────────────────────────────────────────────────────────
# VAULT CONTROLLER — Sistema de vaulting (subirse a obstáculos medianos)
#
# Componente reutilizable para CharacterBody3D (Player + NPCs).
# Detecta obstáculos frontales que son demasiado altos para el step-up nativo
# pero aún escalables, y ejecuta una interpolación de posición para que el
# personaje termine PARADO SOBRE el obstáculo.
#
# FLUJO:
#   1. Llamar a try_vault(direction) cuando el personaje se mueve hacia un obstáculo
#   2. Si hay un obstáculo vaultable, el controller entra en estado VAULTING
#   3. Cada frame, process_vault(delta) calcula la velocidad necesaria para
#      llevar al personaje desde su posición actual hasta el target sobre el obstáculo
#   4. El CALLER debe llamar a move_and_slide() después de process_vault()
#   5. Al terminar, el personaje se encuentra sobre el obstáculo
#
# USO:
#   var vault: VaultController = VaultController.new()
#   vault.setup(self)  # self debe ser CharacterBody3D
#   # En _physics_process:
#   if vault.process_vault(delta):  # ¿Sigue vaulting?
#       move_and_slide()
#       return
#   if vault.try_vault(direction):
#       vault.process_vault(delta)
#       move_and_slide()
#       return
#   # ... movimiento normal ...
# ─────────────────────────────────────────────────────────────────────────────
class_name VaultController
extends RefCounted

# ════════════════════════════════════════════════════════════════════════════
# SEÑALES
# ════════════════════════════════════════════════════════════════════════════

signal vault_started(obstacle_height: float)
signal vault_finished()


# ════════════════════════════════════════════════════════════════════════════
# CONFIGURACIÓN EXPUESTA
# ════════════════════════════════════════════════════════════════════════════

## Altura máxima de obstáculo que se puede vault (igual a la altura del personaje ~1.8u).
var vault_max_height: float = 1.8

## Separación extra por encima del obstáculo para evitar colisión residual.
var vault_overshoot: float = 0.25

## Cuánto avanza horizontalmente el personaje durante el vault.
var vault_forward_advance: float = 0.8

## Distancia extra para los raycasts de detección (más allá del radio de la cápsula).
var detect_distance_extra: float = 0.3

## Cooldown en segundos después de un vault antes de poder vaultear de nuevo.
var post_vault_cooldown: float = 0.3


# ════════════════════════════════════════════════════════════════════════════
# ESTADO
# ════════════════════════════════════════════════════════════════════════════

enum State { IDLE, VAULTING }

var state: int = State.IDLE
var character: CharacterBody3D = null

# Cache de dimensiones de cápsula
var _capsule_radius: float = 0.65
var _capsule_height: float = 1.8
## Distancia desde character.global_position hasta el fondo de la cápsula.
## (cuando character está en el suelo, esta es la altura del centro sobre el suelo)
var _capsule_feet_offset: float = 0.65

# Estado del vault en curso
var _vault_target_pos: Vector3 = Vector3.ZERO
var _vault_start_pos: Vector3 = Vector3.ZERO
var _vault_direction: Vector3 = Vector3.FORWARD
var _vault_elapsed: float = 0.0
var _vault_duration: float = 0.5
var _vault_obstacle_height: float = 0.0

# Cooldown
var _cooldown_until: float = 0.0


# ════════════════════════════════════════════════════════════════════════════
# API PÚBLICA
# ════════════════════════════════════════════════════════════════════════════

## Inicializa el controller con la referencia al CharacterBody3D.
## Debe llamarse antes de usar try_vault() o process_vault().
func setup(char_node: CharacterBody3D) -> void:
	character = char_node
	if not character:
		return
	# Leer dimensiones de la cápsula de colisión si existe
	if character.has_node("CollisionShape3D"):
		var cs: CollisionShape3D = character.get_node("CollisionShape3D") as CollisionShape3D
		if cs and cs.shape is CapsuleShape3D:
			var capsule: CapsuleShape3D = cs.shape as CapsuleShape3D
			_capsule_radius = capsule.radius
			_capsule_height = capsule.height
			# feet_offset = distancia desde character.gp hasta fondo de la cápsula
			# Fondo de la cápsula = character.gp + cs.position.y - height/2 - radius
			# → feet_offset = -(cs.position.y - height/2 - radius) = -cs.position.y + height/2 + radius
			_capsule_feet_offset = -cs.position.y + capsule.height * 0.5 + capsule.radius


## Retorna true si el personaje está actualmente vaulting.
func is_vaulting() -> bool:
	return state == State.VAULTING


## Verifica si hay un obstáculo vaultable en la dirección indicada,
## SIN iniciar el vault. Útil para UI indicators (jugador) o decisiones (bots).
## 'direction' debe ser un vector normalizado.
## 'current_time' es un timestamp en segundos.
func can_vault(direction: Vector3, current_time: float) -> bool:
	if state != State.IDLE or character == null:
		return false
	if character.is_dead:
		return false
	if current_time < _cooldown_until:
		return false
	if not character.is_on_floor():
		return false
	if direction.length_squared() < 0.01:
		return false

	var space_state: PhysicsDirectSpaceState3D = character.get_world_3d().direct_space_state
	if not space_state:
		return false

	var origin: Vector3 = character.global_position
	var dir: Vector3 = direction.normalized()
	var check_dist: float = _capsule_radius + detect_distance_extra
	var exclude: Array = [character]
	var mask: int = character.collision_mask

	# ── PASO 1: RAY BAJO (0.15u sobre pies) → detectar obstáculo ──
	var foot_origin: Vector3 = origin + Vector3(0, 0.15, 0)
	var foot_end: Vector3 = foot_origin + dir * check_dist
	var foot_query = PhysicsRayQueryParameters3D.create(foot_origin, foot_end)
	foot_query.collision_mask = mask
	foot_query.exclude = exclude
	var foot_hit: Dictionary = space_state.intersect_ray(foot_query)

	if foot_hit.is_empty():
		return false
	if foot_hit.normal.y >= 0.3:
		return false  # Rampa, no obstáculo vertical

	# ── PASO 2: RAY MEDIO (capsule_radius*1.2) → más alto que step-up? ──
	var mid_height: float = _capsule_radius * 1.2
	var mid_origin: Vector3 = origin + Vector3(0, mid_height, 0)
	var mid_end: Vector3 = mid_origin + dir * check_dist
	var mid_query = PhysicsRayQueryParameters3D.create(mid_origin, mid_end)
	mid_query.collision_mask = mask
	mid_query.exclude = exclude
	var mid_hit: Dictionary = space_state.intersect_ray(mid_query)

	if mid_hit.is_empty():
		return false  # Demasiado bajo → step-up lo maneja

	# ── PASO 3: RAY ALTO (vault_max_height) → dentro de rango vault? ──
	var top_origin: Vector3 = origin + Vector3(0, vault_max_height, 0)
	var top_end: Vector3 = top_origin + dir * check_dist
	var top_query = PhysicsRayQueryParameters3D.create(top_origin, top_end)
	top_query.collision_mask = mask
	top_query.exclude = exclude
	var top_hit: Dictionary = space_state.intersect_ray(top_query)

	if not top_hit.is_empty():
		return false  # Demasiado alto

	return true


## Intenta iniciar un vault en la dirección indicada.
## 'direction' debe ser un vector normalizado.
## 'current_time' es un timestamp en segundos.
## Retorna true si el vault se inició.
func try_vault(direction: Vector3, current_time: float) -> bool:
	if not can_vault(direction, current_time):
		return false
	if character == null:
		return false

	var space_state: PhysicsDirectSpaceState3D = character.get_world_3d().direct_space_state
	if not space_state:
		return false

	var dir: Vector3 = direction.normalized()
	var check_dist: float = _capsule_radius + detect_distance_extra
	var exclude: Array = [character]

	# ── Encontrar la altura exacta de la parte superior del obstáculo ──
	var mid_height: float = _capsule_radius * 1.2
	var obstacle_top: float = _find_obstacle_top(space_state, dir, check_dist, exclude, mid_height, vault_max_height)
	if obstacle_top < 0.0:
		return false

	# ── ¡Iniciar vault! ──
	_start_vault(dir, obstacle_top)
	return true


## Procesa el vault en curso (debe llamarse cada frame mientras is_vaulting()).
## Retorna true si el vault sigue en progreso, false si terminó.
func process_vault(delta: float, current_time: float) -> bool:
	if state != State.VAULTING:
		return false

	_vault_elapsed += delta
	var t: float = clamp(_vault_elapsed / _vault_duration, 0.0, 1.0)

	if t >= 1.0:
		_finish_vault(current_time)
		return false

	# Easing suave: ease-out cúbico (empieza rápido, termina suave)
	var eased_t: float = 1.0 - pow(1.0 - t, 3.0)

	# Interpolar posición
	var target_pos: Vector3 = _vault_start_pos.lerp(_vault_target_pos, eased_t)

	# Calcular velocidad necesaria para llegar al target este frame
	var displacement: Vector3 = target_pos - character.global_position
	var vel: Vector3 = displacement / max(delta, 0.001)

	# Limitar velocidad máxima para evitar explosiones
	var max_vel: float = 20.0
	if vel.length() > max_vel:
		vel = vel.normalized() * max_vel

	character.velocity = vel
	return true


# ════════════════════════════════════════════════════════════════════════════
# MÉTODOS INTERNOS
# ════════════════════════════════════════════════════════════════════════════

## Encuentra la altura aproximada de la superficie superior del obstáculo
## haciendo raycasts de arriba hacia abajo.
## Retorna la altura RELATIVA desde character.global_position hasta el tope.
func _find_obstacle_top(
	space_state: PhysicsDirectSpaceState3D,
	dir: Vector3,
	dist: float,
	exclude: Array,
	min_y: float,
	max_y: float
) -> float:
	var origin: Vector3 = character.global_position
	var step: float = 0.05  # 5cm de precisión

	# Marchar desde vault_max_height hacia abajo.
	# El PRIMER hit desde arriba es la superficie superior del obstáculo.
	for i in range(int(max_y / step) + 1, int(min_y / step) - 1, -1):
		var height: float = i * step
		var ray_origin: Vector3 = origin + Vector3(0, height, 0)
		var ray_end: Vector3 = ray_origin + dir * dist
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.collision_mask = character.collision_mask
		query.exclude = exclude
		var hit: Dictionary = space_state.intersect_ray(query)

		if not hit.is_empty():
			return height  # Primer hit = tope del obstáculo

	return -1.0  # No se encontró


## Inicia la secuencia de vaulting.
func _start_vault(dir: Vector3, obstacle_height: float) -> void:
	state = State.VAULTING
	_vault_direction = dir
	_vault_obstacle_height = obstacle_height
	_vault_start_pos = character.global_position

	# Calcular target: sobre el obstáculo + overshoot + avance horizontal
	# obstacle_height es la altura relativa desde character.gp hasta el tope del obstáculo
	# El tope del obstáculo en coordenadas del mundo = _vault_start_pos.y + obstacle_height
	# Para que el personaje esté DE PIE sobre el obstáculo:
	#   character.gp.y = tope_obstaculo.y + feet_offset + overshoot
	# Donde feet_offset = distancia desde character.gp hasta el fondo de la cápsula
	_vault_target_pos = character.global_position
	_vault_target_pos.y = _vault_start_pos.y + obstacle_height + _capsule_feet_offset + vault_overshoot
	# Avance horizontal
	_vault_target_pos += dir * vault_forward_advance

	# Duración más lenta para animación de "subirse" (step-up 2)
	# Rango: ~0.5s para obstáculos bajos, ~1.1s para los más altos (1.56u)
	_vault_duration = 0.5 + (obstacle_height / vault_max_height) * 0.6
	_vault_elapsed = 0.0

	vault_started.emit(obstacle_height)


## Finaliza el vault y coloca al personaje exactamente en la posición target.
func _finish_vault(current_time: float) -> void:
	# Posición final exacta
	character.global_position = _vault_target_pos
	character.velocity = Vector3.ZERO

	state = State.IDLE
	_cooldown_until = current_time + post_vault_cooldown
	vault_finished.emit()
