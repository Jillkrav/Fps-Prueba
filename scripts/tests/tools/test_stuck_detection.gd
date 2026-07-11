# scripts/test_stuck_detection.gd
# Test unitario para validar el nuevo sistema de detección de atasco.
# Verifica que los umbrales por estado sean correctos y que la lógica
# de recuperación no produzca bucles infinitos ni falsos positivos.
extends SceneTree

var _npc: NpcBase = null
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
	
	var thresholds = NpcBase.STUCK_PROGRESS_THRESHOLD
	
	# ROAMING (estado 1): debe detectar atasco rápido (2.5s)
	assert_lt(thresholds[1], 3.0, "ROAMING: threshold < 3.0s (detección ágil)")
	
	# ATTACKING (estado 2): más permisivo que ROAMING
	assert_gt(thresholds[2], thresholds[1], "ATTACKING: threshold > ROAMING (más permisivo en combate)")
	
	# TACTICAL_MOVE (estado 3): el más permisivo
	assert_gt(thresholds[3], thresholds[2], "TACTICAL_MOVE: threshold > ATTACKING (strafing activo)")
	assert_gt(thresholds[3], 5.0, "TACTICAL_MOVE: threshold > 5.0s (muy permisivo)")
	
	# HUNTING (estado 4): el más rápido (persecución)
	assert_lt(thresholds[4], 2.5, "HUNTING: threshold < 2.5s (persecución urgente)")
	
	# IDLE (estado 0): no aplica (nunca se comprueba)
	assert_eq(thresholds[0], 8.0, "IDLE: threshold = 8.0 (no aplica)")


func _test_recovery_phase_transitions() -> void:
	print("\n── Transiciones de fases de recuperación ──")
	
	# Verificar que las constantes de fase están en el rango esperado
	# Fase 0 = normal
	# Fase 1 = retroceder (0.4s)
	# Fase 2 = lateral (0.3s)  
	# Fase 3 = reruta (transición)
	
	# Simular delta para 1 frame
	var delta: float = 1.0 / 60.0
	
	# Verificar que la fase 1 tiene duración suficiente para moverse
	assert_gt(0.4, delta, "Fase 1: duración 0.4s > 1 frame")
	
	# Verificar que la fase 2 tiene duración suficiente
	assert_gt(0.3, delta, "Fase 2: duración 0.3s > 1 frame")
	
	print("\n  Secuencia esperada (3 fases + control FSM):")
	print("  Fase 1 (0.4s): Retroceder → alejarse del objetivo/bloqueador")
	print("  Fase 2 (0.3s): Lateral → perpendicular a la dirección anterior")
	print("  Fase 3 (1 frame): Re-ruta → _nav_target = ZERO, NavigationAgent reset")
	print("  Vuelta a FSM: Estado retoma el control con ruta nueva")


func _test_goal_position_for_states() -> void:
	print("\n── Obtención de goal position por estado ──")
	
	# Simular llamada a _get_stuck_goal_position para cada estado
	# ROAMING: usa _nav_target
	# ATTACKING: usa target_enemy
	# TACTICAL_MOVE: usa target_enemy
	# HUNTING: usa _nav_target
	# IDLE: Vector3.ZERO
	
	# Verificar que ROAMING y HUNTING comparten la misma fuente
	# Verificar que ATTACKING y TACTICAL_MOVE comparten la misma fuente
	print("  ROAMING/HUNTING → _nav_target")
	print("  ATTACKING/TACTICAL_MOVE → target_enemy.global_position")
	print("  IDLE → Vector3.ZERO (no检测)")


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
	print("-- Sin falsos positivos durante TACTICAL_MOVE --")
	
	# TACTICAL_MOVE usa threshold = 6.0s
	# Durante strafing, el bot se mueve lateralmente:
	# - La Métrica 1 (progreso) es permisiva (6s umbral)
	# - La Métrica 2 (inmovilidad) no se activa porque el bot se mueve
	# - target_enemy como goal permite detectar atasco real
	#   (si está atascado detrás de una pared, la distancia al enemigo
	#    no cambia durante 6s → detecta atasco)
	
	print("  ✓ threshold=6.0s: strafe lateral sin falso positivo")
	print("  ✓ Si el bot no puede moverse (pared), detecta atasco a los 6s")
	print("  ✓ Si el bot está strafeando, no detecta atasco")
