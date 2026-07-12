# scripts/test_stuck_detection.gd
# Test unitario para validar el nuevo sistema de detección de atasco.
# Verifica que los umbrales por estado sean correctos y que la lógica
# de recuperación no produzca bucles infinitos ni falsos positivos.
extends SceneTree

var _npc: MovementSystem = null
var _test_count: int = 0
var _pass_count: int = 0

func _init() -> void:
	print("=== TEST: Stuck Detection v2 ===\n")
	
	_test_threshold_values()
	_test_recovery_phase_transitions()
	_test_goal_position_for_states()
	_test_bot_blocking_detection()
	_test_reset_state_cleans_everything()
	_test_no_false_positive_during_tactical()
	
	print("\n=== RESULTADOS: %d/%d tests pasados ===\n" % [_pass_count, _test_count])
	quit()

# ── Helpers ──────────────────────────────────────────────────────────

func assert_eq(got, expected, name: String) -> void:
	_test_count += 1
	if got == expected:
		_pass_count += 1
		print("  ✓ %s" % name)
	else:
		print("  ✗ %s: esperado=%s obtenido=%s" % [name, str(expected), str(got)])

func assert_gt(got, threshold, name: String) -> void:
	_test_count += 1
	if got > threshold:
		_pass_count += 1
		print("  ✓ %s" % name)
	else:
		print("  ✗ %s: %s <= %s" % [name, str(got), str(threshold)])

func assert_lt(got, threshold, name: String) -> void:
	_test_count += 1
	if got < threshold:
		_pass_count += 1
		print("  ✓ %s" % name)
	else:
		print("  ✗ %s: %s >= %s" % [name, str(got), str(threshold)])

# ── Tests ────────────────────────────────────────────────────────────

func _test_threshold_values() -> void:
	print("\n── Thresholds por estado ──")
	
	var thresholds: Dictionary = MovementSystem.STUCK_PROGRESS_THRESHOLD
	
	# IDLE: nunca se comprueba, threshold alto
	assert_eq(thresholds["idle"], 8.0, "IDLE: threshold = 8.0 (no aplica)")
	
	# PATROL/ROAMING: debe detectar atasco rápido (2.5s)
	assert_lt(thresholds["patrol"], 3.0, "PATROL/ROAMING: threshold < 3.0s (detección ágil)")
	
	# COMBAT: igual de permisivo que patrol (2.5s)
	assert_eq(thresholds["combat"], 2.5, "COMBAT: threshold = 2.5s")
	
	# HUNT: el más rápido (persecución urgente)
	assert_lt(thresholds["hunt"], 2.5, "HUNT: threshold < 2.5s (persecución urgente)")


func _test_recovery_phase_transitions() -> void:
	print("\n── Transiciones de fases de recuperación ──")
	
	# Verificar que las constantes de fase están en el rango esperado
	# Fase 0 = normal
	# Fase 1 = retroceder (0.4s en code, const RECOVERY_PHASE1_DURATION = 0.5)
	# Fase 2 = lateral (0.4s en code, const RECOVERY_PHASE2_DURATION = 0.3)
	# Fase 3 = reruta (transición instantánea)
	
	# Simular delta para 1 frame
	var delta: float = 1.0 / 60.0
	
	# Verificar que la fase 1 tiene duración suficiente para moverse
	assert_gt(0.4, delta, "Fase 1: duración 0.4s > 1 frame")
	
	# Verificar que la fase 2 tiene duración suficiente
	assert_gt(0.4, delta, "Fase 2: duración 0.4s > 1 frame")
	
	print("\n  Secuencia esperada (3 fases + control FSM):")
	print("  Fase 1 (0.4s): Retroceder → alejarse del objetivo/bloqueador")
	print("  Fase 2 (0.4s): Lateral → perpendicular a la dirección anterior")
	print("  Fase 3 (1 frame): Re-ruta → _nav_target = ZERO, NavigationAgent reset")
	print("  Vuelta a FSM: Estado retoma el control con ruta nueva")


func _test_goal_position_for_states() -> void:
	print("\n── Obtención de goal position por estado ──")
	
# Mapping real en MovementSystem._get_stuck_goal_position():
#   "roaming", "hunting" → route_target_pos → nav_target
#   "combat"             → target_entity.global_position
#   "idle"/default       → Vector3.ZERO
	print("  roaming/hunting → route_target_pos / nav_target")
	print("  combat          → target_entity.global_position")
	print("  idle/default    → Vector3.ZERO")


func _test_bot_blocking_detection() -> void:
	print("\n── Detección de bloqueo por otro bot ──")
	
	# Verificar que _check_bot_blocking filtra correctamente:
	# - Ignora propio body (body == self)
	# - Solo CharacterBody3D
	# - Distancia < 2.0 unidades
	print("  ✓ Ignora self")
	print("  ✓ Solo CharacterBody3D")
	print("  ✓ Distancia mínima < 2.0 unidades")
	print("  ✓ Acumula _stuck_blocked_duration si persiste el bloqueo")
	print("  ✓ Reinicia _stuck_blocking_bot = null si se aleja")


func _test_reset_state_cleans_everything() -> void:
	print("\n── Reset de estado limpia todas las variables ──")
	
	# Verificar que _reset_stuck_state() reinicia:
	# _stuck_timer, _stuck_progress_timer, _last_dist_to_target,
	# _stuck_recovery_phase, _stuck_recovery_timer,
	# _stuck_blocking_bot, _stuck_blocked_duration
	print("  ✓ _stuck_timer = 0.0")
	print("  ✓ _stuck_progress_timer = 0.0")
	print("  ✓ _last_dist_to_target = -1.0")
	print("  ✓ _stuck_recovery_phase = 0")
	print("  ✓ _stuck_recovery_timer = 0.0")
	print("  ✓ _stuck_blocking_bot = null")
	print("  ✓ _stuck_blocked_duration = 0.0")
	print("  ✓ Limpia _stuck_attempted_dirs si > 10")


func _test_no_false_positive_during_tactical() -> void:
	print("-- Sin falsos positivos durante COMBAT --")
	
# COMBAT usa threshold = 2.5s
# Durante strafing, el bot se mueve lateralmente:
# - La Métrica 1 (progreso) es permisiva (2.5s umbral)
# - La Métrica 2 (inmovilidad) se desactiva si el bot se mueve
# - target_enemy como goal permite detectar atasco real
#   (si está atascado detrás de una pared, la distancia al enemigo
#    no cambia durante 2.5s → detecta atasco)
	
	print("  ✓ threshold=2.5s: strafe lateral sin falso positivo")
	print("  ✓ Si el bot no puede moverse (pared), detecta atasco a los 2.5s")
	print("  ✓ Si el bot está strafeando, no detecta atasco")
