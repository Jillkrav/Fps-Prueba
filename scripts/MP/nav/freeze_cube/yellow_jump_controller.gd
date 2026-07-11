# scripts/yellow_jump_controller.gd
# ──────────────────────────────────────────────────────────────────
# Controlador de salto amarillo — se añade como hijo del NPC cuando
# el FreezeCube2 (morado) lo congela.
#
# Maneja el movimiento parabólico hacia el YellowCube y luego
# descongela al NPC automáticamente.
# ──────────────────────────────────────────────────────────────────
extends Node
class_name YellowJumpController


# ── Parámetros del salto ────────────────────
var _jump_start: Vector3 = Vector3.ZERO
var _jump_target: Vector3 = Vector3.ZERO
var _jump_progress: float = 0.0
var _jump_duration: float = 1.5
var _jump_arc: float = 3.0

## Tiempo total que el NPC estará congelado (incluye el salto).
var _freeze_duration: float = 5.0
var _elapsed: float = 0.0

## Si no hay yellow cube disponible, solo congelar sin salto.
var _has_target: bool = false


func setup(
	jump_start: Vector3,
	jump_target: Vector3,
	duration: float,
	arc: float,
	freeze_duration: float
) -> void:
	_jump_start = jump_start
	_jump_target = jump_target
	_jump_target.y += 0.5  # Aterrizar sobre el cubo
	_jump_duration = duration
	_jump_arc = arc
	_freeze_duration = freeze_duration
	_has_target = true


func _process(delta: float) -> void:
	var npc: NpcBase = get_parent() as NpcBase
	if not npc or not is_instance_valid(npc) or npc.is_dead:
		_finish(npc)
		return
	
	_elapsed += delta
	
	# ── Tiempo de congelación terminado: descongelar ──────────
	if _elapsed >= _freeze_duration:
		_finish(npc)
		return
	
	# ── Salto parabólico (solo si hay target) ─────────────────
	if _has_target:
		_jump_progress += delta / _jump_duration
		var t: float = minf(_jump_progress, 1.0)
		
		# Interpolar posición XZ
		var pos: Vector3 = _jump_start.lerp(_jump_target, t)
		
		# Arco parabólico en Y: 4 * h * t * (1 - t)
		var base_y: float = lerpf(_jump_start.y, _jump_target.y, t)
		pos.y = base_y + _jump_arc * 4.0 * t * (1.0 - t)
		
		npc.global_position = pos
		npc.velocity = Vector3.ZERO
		
		# Rotar hacia el objetivo
		var look_pos: Vector3 = _jump_target
		look_pos.y = npc.global_position.y
		if t < 1.0:
			var dir: Vector3 = (look_pos - npc.global_position).normalized()
			if dir.length_squared() > 0.001:
				var target_basis: Basis = Basis.looking_at(dir, Vector3.UP)
				var current_transform: Transform3D = npc.global_transform
				var current_basis: Basis = current_transform.basis.orthonormalized()
				var slerp_weight: float = clampf(delta * 4.0, 0.0, 1.0)
				current_transform.basis = current_basis.slerp(target_basis, slerp_weight).orthonormalized()
				npc.global_transform = current_transform
		
		# Aterrizar al llegar
		if _jump_progress >= 1.0:
			npc.global_position = _jump_target
			npc.velocity = Vector3.ZERO


func _finish(npc: NpcBase) -> void:
	if npc and is_instance_valid(npc):
		npc.is_frozen = false
	queue_free()
