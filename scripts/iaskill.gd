# iaskill.gd
# Sistema de IA modular para NPCs del FPS.
# Extiende NpcBase y orquesta la maquina de estados tactica.
# No reemplaza la logica de NpcBase, la complementa con hooks opcionales.

extends NpcBase
class_name IaSkill

# ─────────────────────────────────────────
# HOOKS VIRTUALES
# Subclases pueden sobreescribir estos metodos
# para comportamientos especializados por tipo de NPC.
# ─────────────────────────────────────────

## Llamado cuando el NPC detecta un enemigo por vision y confirma LOS.
func on_enemigo_detectado_vision(enemigo: Node3D) -> void:
	pass

## Llamado cuando el NPC pierde la linea de vision del objetivo.
func on_linea_de_vision_perdida() -> void:
	pass

## Llamado cuando el NPC detecta ruido en su area de audio.
func on_ruido_detectado(posicion: Vector3) -> void:
	pass

## Llamado cuando el NPC entra en ARRANSE.
func on_arrancarse() -> void:
	pass

## Llamado cuando el NPC llega al destino de BUSCANDO.
func on_destino_buscando_alcanzado() -> void:
	pass

## Llamado en cada frame de ATACANDO.
## Retorna true si la subclase manejara el ataque (omite attempt_attack del base).
func on_frame_atacando(_delta: float) -> bool:
	return false

# ─────────────────────────────────────────
# SOBREESCRITURA DE ESTADOS
# ─────────────────────────────────────────

func _proceso_atacando(delta: float) -> void:
	if target == null or not is_instance_valid(target) \
		or (target.has_method("is_dead") and target.get("is_dead") == true):
		target = null
		_reaccionando = false
		_objetivo_reaccion = null
		on_linea_de_vision_perdida()
		_cambiar_estado(EstadoTactico.BUSCANDO)
		return

	if not _tiene_linea_de_vision(target):
		_reaccionando = false
		_objetivo_reaccion = null
		_posicion_ruido = target.global_transform.origin
		on_linea_de_vision_perdida()
		_cambiar_estado(EstadoTactico.BUSCANDO)
		return

	if not on_frame_atacando(delta):
		var dist: float = global_transform.origin.distance_to(target.global_transform.origin)
		look_at_target_flat(target.global_transform.origin)
		if dist <= attack_range:
			velocity.x = 0
			velocity.z = 0
			attempt_attack()
		else:
			_mover_hacia(target.global_transform.origin)

func _on_audio_body_entered(body: Node3D) -> void:
	super._on_audio_body_entered(body)
	if _es_enemigo(body):
		on_ruido_detectado(body.global_transform.origin)

# ─────────────────────────────────────────
# CAMBIO DE ESTADO CON HOOKS
# ─────────────────────────────────────────

func _cambiar_estado(nuevo_estado: EstadoTactico) -> void:
	if estado_actual == nuevo_estado:
		return
	var estado_anterior: EstadoTactico = estado_actual
	super._cambiar_estado(nuevo_estado)

	match nuevo_estado:
		EstadoTactico.ARRANSE:
			_objetivo_vida = null
			_objetivo_aliado = null
			on_arrancarse()
		EstadoTactico.BUSCANDO:
			if estado_anterior == EstadoTactico.ATACANDO:
				on_linea_de_vision_perdida()
		EstadoTactico.ATACANDO:
			if target:
				on_enemigo_detectado_vision(target)

# ─────────────────────────────────────────
# INFORMACION UTIL PARA SUBCLASES
# ─────────────────────────────────────────

## Retorna true si el NPC tiene LOS al objetivo actual.
func tiene_los_al_objetivo() -> bool:
	if target and is_instance_valid(target):
		return _tiene_linea_de_vision(target)
	return false

## Retorna el estado actual como String para debug/HUD.
func get_estado_nombre() -> String:
	return EstadoTactico.keys()[estado_actual]

## Retorna el porcentaje de vida actual (0.0 a 1.0).
func get_vida_porcentaje() -> float:
	return current_health / max_health

## Retorna true si el NPC esta en modo de huida.
func esta_arrancandose() -> bool:
	return estado_actual == EstadoTactico.ARRANSE
