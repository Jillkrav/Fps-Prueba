# Auditoría de Violaciones Arquitectónicas
## Proyecto UT99-Inspired — Godot 4.2+

Generado: 30 Junio 2026
Propósito: Mapear TODOS los lugares que violan las reglas de arquitectura
antes de comenzar la refactorización.

---

## RESUMEN

| Concepto | Estado |
|----------|--------|
| ✅ movement_command | No existe aún (se creará en Fase 2) |
| ✅ combat_command | No existe aún (se creará en Fase 3) |
| ✅ aim_rotation | No existe aún (se creará en Fase 4) |
| ❌ **velocity** | 8+ lugares diferentes escriben velocity — MÚLTIPLES VIOLACIONES |
| ❌ **target_enemy** | 2+ sistemas escriben target_enemy — VIOLACIÓN |
| ❌ **Stuck Detection** | DUPLICADO: npc_base.gd Y navigation_system.gd tienen su propia lógica de stuck |

---

## ═══════════════════════════════════════════
## 1. velocity — Propietario: MovementSystem (Fase 2)
## ═══════════════════════════════════════════

### player.gd (OK — es el jugador humano, no NPC)
| Línea | Código | Tipo |
|-------|--------|------|
| 98 | `velocity.y -= gravity * delta` | OK (Player) |
| 119 | `velocity.y = jump_velocity` | OK (Player) |
| 126-127 | `velocity.xz = direction * speed` | OK (Player) |
| 129-130 | `velocity.xz = move_toward(...)` | OK (Player) |
| 131 | `move_and_slide()` | OK (Player) |

### npc_base.gd — 15 asignaciones directas [LEGACY → MovementSystem]
| Línea | Código | Contexto | Tipo |
|-------|--------|----------|------|
| 213 | `velocity.y -= _gravity * delta` | Gravedad del NPC | LEGACY |
| 401-402 | `velocity.xz = move_toward(...)` | Frenado al llegar a destino | LEGACY |
| 414-415 | `velocity.xz = dir * speed` | Movimiento navegado hacia next_path_position | LEGACY |
| 833 | `velocity.y = jumpiness * 12.0 + 3.0` | Stuck recovery fase 1 — saltar | LEGACY |
| 836-837 | `velocity.xz = _stuck_recovery_dir * speed` | Stuck recovery fase 1 | LEGACY |
| 853-854 | `velocity.xz = _stuck_recovery_dir * 3.5` | Stuck recovery fase 2 | LEGACY |

### behavior_combat.gd — 1 violación CRÍTICA
| Línea | Código | Contexto | Tipo |
|-------|--------|----------|------|
| 267 | `brain.bot.velocity.y = 5.0` | Salto durante strafe en combate | ❌ VIOLACIÓN |

### bot_brain.gd — 4 asignaciones (fallback legacy)
| Línea | Código | Contexto | Tipo |
|-------|--------|----------|------|
| 272-273 | `bot.velocity.xz = dir * m.speed` | Fallback DIRECT (sin NavigationSystem) | LEGACY |
| 276-277 | `bot.velocity.xz = move_toward(...)` | Fallback HOLD (sin NavigationSystem) | LEGACY |

### navigation_system.gd — 13 asignaciones [LEGACY + VIOLACIÓN]
| Línea | Código | Contexto | Tipo |
|-------|--------|----------|------|
| 294-295 | `bot.velocity.xz = vel` | move_direction() — movimiento directo | LEGACY |
| 302-303 | `bot.velocity.xz = move_toward(...)` | hold_position() | LEGACY |
| 376 | `bot.velocity.y = AUTO_JUMP_VELOCITY` | Auto-jump al encontrar obstáculo | LEGACY |
| 513-514 | `bot.velocity.xz = move_toward(...)` | Frenado al llegar (navegación interna) | LEGACY |
| 530-531 | `bot.velocity.xz = vel` | Navegación operativa escribiendo velocity | LEGACY |
| 1063 | `bot.velocity.y = bot.jumpiness * 12.0 + 3.0` | Stuck recovery fase 1 (NavigationSystem) | LEGACY |
| 1066-1067 | `bot.velocity.xz = _stuck_recovery_dir * speed` | Stuck recovery fase 1 | LEGACY |
| 1084-1085 | `bot.velocity.xz = _stuck_recovery_dir * RECOVERY_PHASE2_SPEED` | Stuck recovery fase 2 | LEGACY |

### dev_menu.gd — 1 asignación controlada
| Línea | Código | Contexto | Tipo |
|-------|--------|----------|------|
| 360 | `bot.velocity = Vector3.ZERO` | AI Disable — detener todos los bots | OK (control externo) |

### TOTAL: 8+ lugares escriben velocity (solo en NPCs)
- ❌ behavior_combat.gd: 1 violación directa
- ⚠️ npc_base.gd: 6 lugares legacy
- ⚠️ navigation_system.gd: 8 lugares legacy
- ⚠️ bot_brain.gd: 4 lugares legacy (fallback)

---

## ═══════════════════════════════════════════
## 2. target_enemy — Propietario: DecisionSystem (Fase 3)
## ═══════════════════════════════════════════

### perception_system.gd — ESCRIBE target_enemy [VIOLACIÓN]
| Línea | Código | Contexto | Tipo |
|-------|--------|----------|------|
| 182 | `target_enemy = null` | Reset al detectar enemigo muerto | ❌ VIOLACIÓN |
| 210 | `target_enemy = best_body` | Asignación de nuevo objetivo | ❌ VIOLACIÓN |
| 218 | `bot.target_enemy = target_enemy` | Sincroniza con NpcBase | ❌ VIOLACIÓN |
| 280 | `target_enemy = null` | Reset del sistema | ❌ VIOLACIÓN |

### npc_base.gd — ESCRIBE target_enemy [VIOLACIÓN]
| Línea | Código | Contexto | Tipo |
|-------|--------|----------|------|
| 529 | `if target_enemy == null` (lectura) | Solo lectura — OK (pero variable debería estar en DecisionSystem) | ⚠️ |
| 583 | `target_enemy = null` | _re_evaluar_enemigos() | ❌ VIOLACIÓN |
| 663 | `target_enemy = _enemy_core` | Asignación del core como objetivo | ❌ VIOLACIÓN |
| 670 | `target_enemy = null` | Release del core | ❌ VIOLACIÓN |
| 980 | `target_enemy = null` | Respawn/reset | ❌ VIOLACIÓN |

### TOTAL: 9 lugares escriben target_enemy
- ❌ perception_system.gd: 4 (debería solo sugerir, no asignar)
- ❌ npc_base.gd: 4 (debería ser propiedad de DecisionSystem)
- ⚠️ npc_base.gd: 1 lectura (correcto)

---

## ═══════════════════════════════════════════
## 3. movement_command / combat_command / aim_rotation
## ═══════════════════════════════════════════

NO EXISTEN en el código actual. Estas variables se crearán en
Fases 2-4 como parte de la refactorización.

### Movimiento actual: DecisionContext
El sistema actual usa `DecisionContext` (res://scripts/ai/decision_context.gd)
que es un Resource con MovementIntent y CombatIntent. Esto es un precursor
de la arquitectura objetivo pero:
- NO es un sistema de comandos puro
- BotBrain._execute_context() traduce el contexto a velocity DIRECTAMENTE
- No hay separación clara entre "decisión" y "ejecución"

### Apuntado actual: _aim_at_target()
- npc_base.gd línea 361: `_aim_at_target()` modifica `head.rotation`
- bot_brain.gd línea 281: llama a `bot._aim_at_target(c.aim_target)`
- No existe `aim_rotation` como variable independiente

---

## ═══════════════════════════════════════════
## 4. move_and_slide() — Solo CharacterBody3D
## ═══════════════════════════════════════════

| Archivo | Línea | Tipo |
|---------|-------|------|
| player.gd | 131 | OK (Player) |
| npc_base.gd | 215 | OK (NpcBase) |
| navigation_system.gd | 1215, 1218, 1225, 1250 | Comentarios/docs — no llama directamente |

✅ Solo los 2 CharacterBody3D llaman move_and_slide(). Correcto.

---

## ═══════════════════════════════════════════
## 5. STUCK DETECTION — DUPLICADO CRÍTICO
## ═══════════════════════════════════════════

El sistema de detección de stuck está DUPLICADO en dos lugares:

### npc_base.gd (~80 líneas de lógica de stuck)
- Líneas 73-106: Variables `_stuck_*`
- Líneas 595, 684-906: Lógica de detección y recuperación
- Tiene 3 fases de recuperación con escritura directa de velocity

### navigation_system.gd (~100 líneas de lógica de stuck)
- Líneas 158-230: Variables `_stuck_*`
- Líneas 1050-1090: Lógica de recuperación con 3 fases
- Misma estructura, mismas fases, variables diferentes

### Problema: ¿Cuál de los dos se ejecuta realmente?
- NpcBase._physics_process() llama:
  1. `navigation_sys.update(delta)` → stuck recovery en NavigationSystem
  2. `_process_movement()` → stuck recovery en NpcBase
- AMBOS se ejecutan, potencialmente pisándose mutuamente

---

## ═══════════════════════════════════════════
## 6. OTROS HALLAZGOS
## ═══════════════════════════════════════════

### 6.1 NavigationSystem hinchado (1399 lines)
- Mezcla: pathfinding + stuck + auto-jump + avoidance + steering
- Debería ser solo: gestión de navmesh + semantic points

### 6.2 team_ai.gd VACÍO
- Archivo existe pero sin implementación
- No hay ObjectiveSystem ni OrderSystem

### 6.3 Behaviors escriben en NpcBase directamente
- behavior_combat.gd: `brain.bot.velocity.y = 5.0` (violación)
- behavior_hunt.gd: usa `brain.context.movement.set_navigate()` (correcto)
- behavior_patrol.gd: usa `brain.context.movement.set_navigate()` (correcto)

### 6.4 _re_evaluar_enemigos() obsoleto
- npc_base.gd línea 582: Función completa para re-evaluar enemigos
-

### 6.4 _re_evaluar_enemigos() obsoleto
- npc_base.gd línea 582: Función completa para re-evaluar enemigos
- PerceptionSystem ya hace esto — es código duplicado

### 6.5 RouteDiversifier y _route_* en NpcBase
- npc_base.gd líneas 49-66: Route diversification (legacy)
- Debería ser parte de MovementSystem

---

## PLAN DE ACCIÓN (orden de fases)

1. **Fase 0** ✅ (esta auditoría)
2. **Fase 1**: Limpiar PerceptionSystem (que no escriba target_enemy) y MemorySystem
3. **Fase 2**: Crear MovementSystem (único escritor de velocity) + MovementCommand
4. **Fase 3**: Crear DecisionSystem + FSM (único escritor de commands + target)
5. **Fase 4**: Crear CombatSystem (único escritor de aim_rotation)
6. **Fase 5**: WeaponSystem + AI Profiles
7. **Fase 6**: ObjectiveSystem + OrderSystem (team_ai.gd)
8. **Fase 7**: Semantic Navigation
9. **Fase 8**: Limpieza final (eliminar todo legacy)
