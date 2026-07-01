# ARQUITECTURA DEFINITIVA — SISTEMA DE IA PARA FPS EN GODOT 4

> **Documento Oficial de Especificación**
> Fecha: 2026-06-30 | Versión: 1.0
> Basado en: Ingeniería inversa de UT99 (17 archivos fuente), análisis del proyecto actual, y mejoras modernas para Godot 4.
> Estado: **Especificación vinculante** — todo el código futuro debe adherirse a este documento.

---

## ÍNDICE

1. [PRINCIPIOS FUNDAMENTALES](#1-principios-fundamentales)
2. [DIAGRAMA DE MÓDULOS](#2-diagrama-de-módulos)
3. [MÓDULO 1: PerceptionSystem](#3-módulo-1-perceptionsystem)
4. [MÓDULO 2: MemorySystem](#4-módulo-2-memorysystem)
5. [MÓDULO 3: DecisionSystem (FSM)](#5-módulo-3-decisionsystem-fsm)
6. [MÓDULO 4: MovementSystem](#6-módulo-4-movementsystem)
7. [MÓDULO 5: CombatSystem](#7-módulo-5-combatsystem)
8. [MÓDULO 6: WeaponSystem](#8-módulo-6-weaponsystem)
9. [MÓDULO 7: HealthSystem](#9-módulo-7-healthsystem)
10. [MÓDULO 8: NavigationSystem (Global)](#10-módulo-8-navigationsystem-global)
11. [MÓDULO 9: ObjectiveSystem (GameMode)](#11-módulo-9-objectivesystem-gamemode)
12. [MÓDULO 10: OrderSystem](#12-módulo-10-ordersystem)
13. [MÓDULO 11: SkillSystem](#13-módulo-11-skillsystem)
14. [MÓDULO 12: TeamCoordinator](#14-módulo-12-teamcoordinator)
15. [MATRIZ DE DATA OWNERSHIP](#15-matriz-de-data-ownership)
16. [FLUJO DEL FRAME (ORDEN ESTRICTO)](#16-flujo-del-frame-orden-estricto)
17. [MAPA COMPLETO DE SEÑALES](#17-mapa-completo-de-señales)
18. [FSM: ESTADOS Y TRANSICIONES](#18-fsm-estados-y-transiciones)
19. [COMANDOS: MovementCommand y CombatCommand](#19-comandos-movementcommand-y-combatcommand)
20. [NAVEGACIÓN SEMÁNTICA](#20-navegación-semántica)
21. [SISTEMA DE ÓRDENES (UT99 REALORDERS)](#21-sistema-de-órdenes-ut99-realorders)
22. [PERFILES DE BOT (BotProfile + TacticalRole)](#22-perfiles-de-bot-botprofile--tacticalrole)
23. [PERFILES DE ARMA (WeaponAIProfile)](#23-perfiles-de-arma-weaponprofile)
24. [DIFICULTAD DINÁMICA](#24-dificultad-dinámica)
25. [PERSONALIDAD Y VOCES](#25-personalidad-y-voces)
26. [INTEGRACIÓN CON GAMEMODES](#26-integración-con-gamemodes)
27. [ESTRUCTURA DE ESCENA (NODE TREE)](#27-estructura-de-escena-node-tree)
28. [PLAN DE MIGRACIÓN DEFINITIVO](#28-plan-de-migración-definitivo)
29. [GLOSARIO](#29-glosario)

---

## 1. PRINCIPIOS FUNDAMENTALES

### 1.1 Single Writer Principle (SWP)
Cada variable del sistema tiene **exactamente un propietario** que puede escribirla. Cualquier otro sistema que necesite modificarla debe hacerlo a través de comandos o señales.

### 1.2 Command-Query Separation (CQS)
Los sistemas se comunican mediante:
- **Comandos** (escrituras): `MovementCommand`, `CombatCommand`
- **Consultas** (lecturas): leer variables expuestas de otros sistemas
- **Señales** (eventos): `entity_detected`, `stuck_detected`, `damage_taken`

### 1.3 Prohibiciones Absolutas
```
❌ MovementSystem escribe target_entity
❌ CombatSystem escribe velocity
❌ DecisionSystem escribe velocity
❌ WeaponSystem escribe movement_command
❌ PerceptionSystem escribe memory_store
❌ NavigationSystem escribe algo en bots
❌ HealthSystem escribe sensor_data
❌ ObjectiveSystem escribe algo en bots (solo emite señales)
```

### 1.4 Regla de Acoplamiento
- Los sistemas de un bot se comunican por **referencia directa** (hermanos en el árbol)
- Los sistemas globales se comunican por **señales** (Signal Bus)
- Ningún sistema global tiene referencia directa a un sistema interno de bot

### 1.5 Regla de Estado Transitorio
- `MovementCommand` y `CombatCommand` son **recursos transitorios** — se crean cada frame, se consumen y se descartan
- No persisten entre frames
- Su estado por defecto es "no hacer nada" (NONE / engage=false)

---

## 2. DIAGRAMA DE MÓDULOS

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SISTEMAS GLOBALES (Autoload/Mapa)                   │
│                                                                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐   │
│  │ NavigationSystem  │  │  ObjectiveSystem  │  │     SkillSystem          │   │
│  │ (1 por mapa)      │  │  (GameMode)       │  │  (Resource Global)       │   │
│  │                   │  │                   │  │                          │   │
│  │ Prop: navmesh     │  │ Prop: objectives  │  │ Prop: bot_profiles       │   │
│  │ Prop: semantic_pts│  │ Prop: orders      │  │ Prop: difficulty_table   │   │
│  │ Servicio: pathfind│  │ Prop: match_phase │  │ Servicio: get_profile()  │   │
│  └────────┬──────────┘  └────────┬──────────┘  └──────────┬───────────────┘   │
│           │                      │                        │                    │
│           │ Señales globales      │ Señales globales       │ Init de bots       │
│           ▼                      ▼                        ▼                    │
└─────────────────────────────────────────────────────────────────────────────┘
         │                      │                        │
         ▼                      ▼                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          BOT (CharacterBody3D)                               │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     SISTEMAS INTERNOS DEL BOT                         │   │
│  │                                                                       │   │
│  │  ┌──────────────┐   ┌──────────┐   ┌────────────────────────────┐    │   │
│  │  │ Perception   │──▶│ Memory   │──▶│   DecisionSystem (FSM)     │    │   │
│  │  │ System       │   │ System   │   │                            │    │   │
│  │  │              │   │          │   │  Prop: current_state       │    │   │
│  │  │ Prop:        │   │ Prop:    │   │  Prop: target_entity       │    │   │
│  │  │ sensor_data  │   │ memory_  │   │  Prop: movement_command    │    │   │
│  │  │              │   │ store    │   │  Prop: combat_command      │    │   │
│  │  └──────────────┘   └──────────┘   │  Prop: focus_point         │    │   │
│  │                                    └──────┬───────────┬─────────┘    │   │
│  │                                           │           │               │   │
│  │              ┌────────────────────────────┘           │               │   │
│  │              ▼                                        ▼               │   │
│  │  ┌──────────────────────┐              ┌────────────────────────┐    │   │
│  │  │   MovementSystem     │              │     CombatSystem        │    │   │
│  │  │                      │              │                         │    │   │
│  │  │  Prop: velocity      │              │  Prop: aim_rotation     │    │   │
│  │  │  Prop: navigation_   │              │  Prop: dodge_state      │    │   │
│  │  │        path          │              │  Prop: engagement_data  │    │   │
│  │  │  Prop: stuck_state   │              │                         │    │   │
│  │  │  Prop: movement_mode │              │  Lee: combat_command    │    │   │
│  │  │                      │              │  Lee: weapon_status     │    │   │
│  │  │  Lee: movement_cmd   │              │  Lee: target_entity     │    │   │
│  │  └──────────────────────┘              └──────────┬──────────────┘    │   │
│  │                                                   │                    │   │
│  │  ┌──────────────────────┐              ┌──────────▼──────────────┐    │   │
│  │  │    HealthSystem      │              │     WeaponSystem        │    │   │
│  │  │                      │              │                         │    │   │
│  │  │  Prop: health        │              │  Prop: weapon_status    │    │   │
│  │  │  Prop: armor         │              │  Prop: ammo_count       │    │   │
│  │  │  Prop: damage_history│              │  Prop: ai_profile(R)    │    │   │
│  │  │  Prop: is_alive      │              │  Prop: reload_state     │    │   │
│  │  └──────────────────────┘              └─────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     DATOS ASOCIADOS (Resources)                       │   │
│  │                                                                       │   │
│  │  BotProfile (Resource) — asignado por SkillSystem al iniciar          │   │
│  │  TacticalRole (RefCounted) — creado por NpcBase según Enums.Rol      │   │
│  │  WeaponAIProfile (Resource) — cargado desde el arma equipada          │   │
│  │  TeamIdentifier (Node) — identidad de equipo                           │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. MÓDULO 1: PerceptionSystem

### 3.1 Responsabilidad Única
Producir datos sensoriales crudos del mundo. **NO decide qué hacer con ellos.** NO escribe en target_entity, velocity, ni memory_store.

### 3.2 Data Ownership
| Variable | Propietario | Lectores | Prohibido escribir |
|----------|-------------|----------|-------------------|
| `sensor_data.visible: Array[Sighting]` | PerceptionSystem | DecisionSystem, MemorySystem | Todos los demás |
| `sensor_data.heard: Array[NoiseEvent]` | PerceptionSystem | DecisionSystem | Todos los demás |
| `sensor_data.threats: Array[ThreatAssessment]` | PerceptionSystem | DecisionSystem | Todos los demás |
| `sensor_data.last_known_positions: Dictionary` | PerceptionSystem | DecisionSystem | Todos los demás |

### 3.3 Entradas (Solo Lectura)
- `bot.global_position` (posición propia)
- `bot.head.global_transform` (dirección de mirada)
- `Area3D.overlapping_bodies` (cuerpos en zona de visión)
- `RayCast3D.get_collider()` (línea de visión)
- Escena global (posiciones de otros nodos)

### 3.4 Salidas (Escritura)
- `sensor_data.visible` — entidades visibles este frame
- `sensor_data.heard` — ruidos detectados este frame
- `sensor_data.threats` — evaluaciones de amenaza (si aplica)

### 3.5 Señales que Emite
| Señal | Cuándo | Datos |
|-------|--------|-------|
| `entity_detected` | Primera vez que ve una entidad | entity_id, position, confidence |
| `entity_lost` | Pierde visión de una entidad | entity_id, last_known_position |
| `threat_assessed` | Nueva evaluación de amenaza | entity_id, threat_level |
| `noise_heard` | Detecta un ruido | position, loudness, source |

### 3.6 Algoritmos

**Visión:**
```
1. Obtener overlapping_bodies del Area3D
2. Filtrar: mismo bot, muertos, invisibles, mismos equipo
3. Para cada candidato:
   a. Calcular target_pos (posición + altura de ojos)
   b. Configurar RayCast hacia target_pos
   c. Verificar LOS (colisionador es el cuerpo o su descendiente)
   d. Si hay LOS → crear Sighting con distancia, ángulo, timestamp
4. Ordenar sightings por prioridad (distancia, amenaza, rol)
5. Escribir sensor_data.visible
```

**Audición (futuro):**
```
1. Escuchar señales de noise_heard del área
2. Crear NoiseEvent con posición, loudness, tipo
3. Escribir sensor_data.heard
```

### 3.7 Lo que NUNCA hace
- NO escribe `target_entity` en NpcBase
- NO escribe `velocity`
- NO escribe `memory_store` directamente (emite señal para MemorySystem)
- NO escribe `movement_command` ni `combat_command`

---

## 4. MÓDULO 2: MemorySystem

### 4.1 Responsabilidad Única
Almacenar, consolidar y hacer expirar información a lo largo del tiempo. Transforma una IA reactiva en una IA que "recuerda".

### 4.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `memory_store: Array[MemoryEntry]` | **MemorySystem** | DecisionSystem (solo query) |
| `_durations: Dictionary` | MemorySystem | MemorySystem interno |

### 4.3 Tipos de Memoria
| Tipo | Duración | Propósito |
|------|----------|-----------|
| `ENEMY_POSITION` | 15s | Última posición conocida de enemigo |
| `GUNSHOT` | 8s | Disparo/explosión escuchado |
| `HEALTH_PACK` | 20s | Botiquín visto |
| `WEAPON_ITEM` | 25s | Arma vista en el suelo |
| `SUSPICIOUS_NOISE` | 6s | Ruido desconocido |
| `ALLY_POSITION` | 10s | Posición de aliado |
| `NAV_TARGET` | 5s | Destino de navegación (debug) |
| `DAMAGE_SOURCE` | 10s | Quién me disparó y desde dónde |
| `OBJECTIVE_PROGRESS` | 30s | Progreso hacia objetivo actual |

### 4.4 MemoryEntry Structure
```
class MemoryEntry:
    type: int                     # MemoryType
    data: Dictionary              # Payload flexible
    position: Vector3             # Posición del evento
    confidence: float             # 0.0-1.0
    timestamp: float              # Tiempo de creación (Unix)
    duration: float               # Duración en segundos
    _age: float                   # Edad acumulada
```

### 4.5 API Pública
| Método | Descripción |
|--------|-------------|
| `record(type, data, position, confidence)` | Registrar nueva memoria (o merge con existente) |
| `record_enemy_position(enemy, position)` | Atajo para ENEMY_POSITION |
| `record_gunshot(position, loudness)` | Atajo para GUNSHOT |
| `record_health_pack(pickup, position)` | Atajo para HEALTH_PACK |
| `record_damage_source(attacker, position)` | Atajo para DAMAGE_SOURCE |
| `get_most_recent(type) -> MemoryEntry` | Entrada más reciente de un tipo |
| `get_all_of_type(type) -> Array[MemoryEntry]` | Todas las entradas de un tipo |
| `has_type(type, max_age) -> bool` | ¿Hay al menos una entrada válida? |
| `get_position(type) -> Vector3` | Posición de la más reciente |
| `has_enemy_memory() -> bool` | ¿Hay enemigos recordados? |
| `get_last_enemy_position() -> Vector3` | Última posición de enemigo |
| `forget_all()` | Limpiar todas las memorias |

### 4.6 Reglas de Merge
- Si una nueva memoria del mismo tipo está cerca (distancia < 5 uds) de una existente, se **fusionan**: actualiza timestamp, incrementa confidence, resetea age
- Si la memoria supera MAX_ENTRIES (100), se elimina la más vieja

### 4.7 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `memory_updated(type, entity_id)` | Una memoria existente se actualizó |
| `memory_expired(type, entity_id)` | Una memoria expiró |
| `memory_consolidated(type, entries_count)` | Múltiples memorias se fusionaron |

---

## 5. MÓDULO 3: DecisionSystem (FSM)

### 5.1 Responsabilidad Única
**Tomar decisiones.** Es el único sistema que decide QUÉ hacer. Traduce la información sensorial y de memoria en comandos de movimiento y combate.

### 5.2 Data Ownership
| Variable | Propietario | Lectores | Prohibido escribir |
|----------|-------------|----------|-------------------|
| `current_state: State` | **DecisionSystem** | Debug overlay | Todos los demás |
| `target_entity: Node3D` | **DecisionSystem** | CombatSystem, PerceptionSystem | MovementSystem, WeaponSystem |
| `movement_command: MovementCommand` | **DecisionSystem** | MovementSystem | CombatSystem, WeaponSystem |
| `combat_command: CombatCommand` | **DecisionSystem** | CombatSystem | MovementSystem, WeaponSystem |
| `focus_point: Vector3` | **DecisionSystem** | CombatSystem (aim) | MovementSystem |
| `enemy_history: Array[EntityRecord]` | **DecisionSystem** | — (interno) | Todos los demás |
| `objective_priority: Dictionary` | **DecisionSystem** | Debug | Todos los demás |

### 5.3 Entradas (Solo Lectura)
- `sensor_data` (PerceptionSystem)
- `memory_store` (MemorySystem) — solo a través de métodos query
- `objectives`, `orders` (ObjectiveSystem)
- `weapon_status`, `ai_profile` (WeaponSystem)
- `health`, `last_damage`, `damage_history` (HealthSystem)
- `stuck_state`, `current_position` (MovementSystem)
- `engagement_analysis` (CombatSystem)
- `bot_profile` (SkillSystem)

### 5.4 Salidas (Escritura)
- `current_state` — estado activo de la FSM
- `target_entity` — enemigo/objetivo seleccionado
- `movement_command` — comando de movimiento para MovementSystem
- `combat_command` — comando de combate para CombatSystem
- `focus_point` — punto de interés visual

### 5.5 Estructura Interna

```
DecisionSystem
├── StateMachine (Node)
│   ├── State_StartUp
│   ├── State_Roaming
│   ├── State_Attacking          # Padre de estados de combate
│   │   ├── State_TacticalMove
│   │   ├── State_Charging
│   │   ├── State_RangedAttack
│   │   └── State_Retreating
│   ├── State_Hunting
│   ├── State_StakeOut
│   ├── State_Holding
│   ├── State_TakingHit
│   └── State_Falling
├── TargetEvaluator (Node)
│   └── threat_assess() -> float
├── CommandValidator (Node)
│   └── validate_movement(cmd) -> bool
│   └── validate_combat(cmd) -> bool
└── ObjectiveEvaluator (Node)
    └── evaluate_objectives() -> Objective
```

### 5.6 Algoritmo de Selección de Objetivo (SetEnemy modernizado)

```
evaluate_target_candidates(candidates: Array[Sighting]) -> EntitySighting:
    1. Si es el mismo enemigo que ya tenemos → retornar (inercia)
    2. Si es inválido (muerto, self) → filtrar
    3. Si no tenemos enemigo actual → aceptar el mejor candidato
    4. Si tenemos enemigo actual:
       a. Calcular threat_score para cada candidato
       b. Aplicar penalización de inercia (basada en tiempo comprometido)
       c. Aplicar bonus de venganza (daño recibido últimos 2s)
       d. Aplicar bonus de remate (enemigo actual < 30 HP → ×3 inercia)
       e. Si threat_score(nuevo) > threat_score(actual) + inercia → cambiar
    5. Actualizar enemy_history (pila de últimos 3)
```

### 5.7 Algoritmo de Evaluación de Amenaza (AssessThreat modernizado)

```
assess_threat(candidate: Sighting) -> float:
    1. threat_base = relative_strength(self, candidate)  # -1.0 a 1.0
    2. threat_distance = distance_threat_curve.sample(candidate.distance)  # curva suave
    3. threat_health = 1.0 - (candidate.health / candidate.max_health)  # enemigo herido = más fácil
    4. threat_damage = damage_from_entity(candidate.entity_id, 3.0)  # daño recibido últimos 3s
    5. threat_weapon = estimate_threat_from_weapon(candidate.weapon, distance)
    6. threat_visibility = 1.0 if candidate.can_see_me else 0.5  # ¿puede verme?
    7. threat_gamemode = ObjectiveSystem.get_threat_modifier(self, candidate)
    
    8. return clamp(
         threat_base * 0.3 +
         threat_distance * 0.2 +
         threat_health * 0.1 +
         threat_damage * 0.15 +
         threat_weapon * 0.15 +
         threat_visibility * 0.05 +
         threat_gamemode * 0.05,
       0.0, 2.0)
```

### 5.8 Algoritmo RelativeStrength (modernizado)

```
relative_strength(self, other) -> float:  # -1.0 a 1.0
    1. self_effective_health = self.health + self.armor * 0.6
    2. other_effective_health = other.health + other.armor * 0.6
    
    3. self_power = self_effective_health * weapon_dps(self.weapon, distance) * skill_modifier(self.skill)
    4. other_power = other_effective_health * weapon_dps(other.weapon, distance) * skill_modifier(other.skill)
    
    5. return clamp((other_power - self_power) / (other_power + self_power + EPSILON), -1.0, 1.0)
```

### 5.9 Algoritmo ChooseAttackMode (modernizado)

```
choose_attack_mode():
    1. if enemy == null or enemy.dead → return
    2. if weapon == null or no_ammo → set_state(FLEE_TO_WEAPON)
    3. [TeamGame] if FindSpecialAttractionFor(self) → override
    4. attitude = get_attitude_towards(enemy)
       - FEAR → set_state(RETREATING)
       - FRIENDLY → what_to_do_next()
    5. if not has_los(enemy):
       - if memory.has_type(ENEMY_POSITION) → set_state(HUNTING)
       - else → set_state(STAKEOUT)
    6. if has_los(enemy):
       - if relative_strength < -0.5 → set_state(RETREATING)
       - elif distance > preferred_range_max → set_state(CHARGING)
       - elif distance < preferred_range_min → set_state(TACTICAL_MOVE) (backpedal)
       - else → set_state(TACTICAL_MOVE) (strafe + fire)
```

---

## 6. MÓDULO 4: MovementSystem

### 6.1 Responsabilidad Única
**Ejecutar movimiento.** Traduce comandos de movimiento en velocity. Es el ÚNICO sistema que escribe velocity.

### 6.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `velocity: Vector3` | **MovementSystem** | Physics engine (move_and_slide) |
| `navigation_path: Array[Vector3]` | **MovementSystem** | — (interno) |
| `stuck_state: StuckState` | **MovementSystem** | DecisionSystem |
| `current_speed: float` | **MovementSystem** | DecisionSystem (lectura) |
| `movement_mode: MovementMode` | **MovementSystem** | Debug overlay |

### 6.3 Modos de Movimiento
| Modo | Descripción | Cuándo se usa |
|------|-------------|---------------|
| `NAVIGATE` | Pathfinding hacia destino | Patrol, Hunt, Chase, Retreat |
| `DIRECT` | Vector directo | Strafe, dodge, retreat direccional |
| `DODGE` | Impulso con salto | Evasión en combate |
| `STOP` | Frenado intencional | Holding, idle |
| `SLIDE` | Deslizamiento lateral | Strafe con facing al enemigo |

### 6.4 Algoritmo Principal

```
process(delta):
    1. cmd = decision_system.movement_command
    2. if cmd.mode == NONE → return (sin movimiento)
    
    3. match cmd.mode:
       NAVIGATE:
         agent.target_position = cmd.target_position
         if agent.is_navigation_finished():
           emit("destination_reached")
           return
         next_pos = agent.get_next_path_position()
         direction = (next_pos - global_position).normalized()
         desired_velocity = direction * cmd.speed
         desired_velocity = apply_avoidance(desired_velocity, delta)
       
       DIRECT:
         desired_velocity = cmd.direction.normalized() * cmd.speed
         desired_velocity = apply_avoidance(desired_velocity, delta)
       
       DODGE:
         desired_velocity = cmd.direction * cmd.impulse
         desired_velocity.y = cmd.jump_velocity
       
       STOP:
         desired_velocity = velocity.move_toward(Vector3.ZERO, braking * delta)
    
    4. # Aplicar gravedad (MovementSystem es el ÚNICO)
       if not is_on_floor():
         velocity.y -= gravity * delta
    
    5. velocity = desired_velocity  # MovementSystem escribe
    6. check_stuck(delta)  # Solo emite señales, no cambia destino
```

### 6.5 Stuck Detection (Solo Emite Señales)
```
check_stuck(delta):
    1. Si stuck_suppressed → return (suprimido por combate)
    2. Métrica 1: Progreso hacia objetivo
       - Si distancia al target no ha disminuido en N segundos → stuck
    3. Métrica 2: Inmovilidad absoluta
       - Si posición no cambia en M segundos → stuck
    4. Métrica 3: Oscilación
       - Si ratio distancia_recorrida/desplazamiento_neto > 3.5 → stuck
    5. Métrica 4: Bloqueo por otro bot
       - Si otro CharacterBody bloquea > 1.5s → stuck
    
    6. Si stuck → emit("stuck_detected", phase, cause)
       NO cambiar destino. NO cambiar ruta. Solo emitir señal.
```

### 6.6 Evitación entre NPCs
```
apply_avoidance(desired_velocity, delta) -> Vector3:
    1. Para cada bot cercano (radio AVOIDANCE_RADIUS):
       - Calcular vector de separación (normalizado, inverso a distancia)
       - Aplicar fuerza AVOIDANCE_FORCE * (1 - dist/radius)
       - Mezclar lateralmente (AVOIDANCE_LATERAL_BLEND)
    2. Garantizar AVOIDANCE_MIN_FORWARD de velocidad hacia adelante
    3. Retornar velocity ajustada
```

### 6.7 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `destination_reached(pos)` | El bot llegó a su destino |
| `path_blocked(dist)` | La ruta está bloqueada |
| `stuck_detected(phase, cause)` | El bot está atascado |
| `stuck_resolved()` | El atasco se resolvió |
| `movement_interrupted(cause)` | Movimiento interrumpido |

---

## 7. MÓDULO 5: CombatSystem

### 7.1 Responsabilidad Única
Manejar combate: puntería, modo de fuego, evasión. **NUNCA escribe velocity.**

### 7.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `aim_rotation: Quaternion` | **CombatSystem** | Modelo/Arma (visual) |
| `preferred_fire_mode: int` | **CombatSystem** | WeaponSystem |
| `dodge_state: DodgeState` | **CombatSystem** | DecisionSystem |
| `current_target_position: Vector3` | **CombatSystem** | WeaponSystem |
| `engagement_analysis: EngagementData` | **CombatSystem** | DecisionSystem |

### 7.3 Algoritmo de Puntería (AdjustAim modernizado)

```
adjust_aim(target_entity, weapon_profile) -> Quaternion:
    1. target_pos = target_entity.global_position + Vector3.UP * 1.2
    
    2. # Predicción de movimiento (si weapon_profile.lead_target)
       if weapon_profile.lead_target:
         target_velocity = target_entity.velocity
         travel_time = distance / projectile_speed
         target_pos += target_velocity * travel_time
    
    3. # Error de puntería (basado en skill y distancia)
       aim_error = calculate_aim_error(skill, distance, weapon_profile)
       target_pos += Vector3(randf_range(-aim_error, aim_error),
                             randf_range(-aim_error, aim_error),
                             0)
    
    4. # Ajuste por splash damage
       if weapon_profile.splash_damage and distance < splash_radius:
         target_pos = target_pos + Vector3.DOWN * 0.5  # apuntar al suelo
    
    5. return global_transform.looking_at(target_pos).basis.get_rotation_quaternion()
```

### 7.4 Algoritmo de Decisión de Disparo
```
should_fire(combat_command, weapon_status) -> bool:
    1. if not combat_command.engage → false
    2. if weapon_status.is_reloading → false
    3. if weapon_status.ammo <= 0 → false (emit "out_of_ammo")
    4. if not has_los(target) → false
    
    5. # Refire rate (UT99: probabilidad de seguir disparando)
       if just_fired:
         if randf() > weapon_profile.refire_rate → false (pausa)
    
    6. return true
```

### 7.5 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `weapon_fired(hit_results)` | El arma disparó |
| `target_in_range(entity_id, dist)` | Enemigo entró en rango óptimo |
| `target_lost(entity_id)` | Enemigo salió de rango/LOS |
| `out_of_ammo(weapon_type)` | Sin munición |
| `dodge_performed(direction)` | Se ejecutó un dodge |
| `aim_updated(new_rotation)` | La puntería cambió |

---

## 8. MÓDULO 6: WeaponSystem

### 8.1 Responsabilidad Única
Gestionar estado del arma: cadencia, munición, recarga, perfil de IA.

### 8.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `weapon_status: WeaponStatus` | **WeaponSystem** | CombatSystem, DecisionSystem |
| `ammo_count: int` | **WeaponSystem** | DecisionSystem |
| `reserve_ammo: int` | **WeaponSystem** | DecisionSystem |
| `cooldown_timer: float` | **WeaponSystem** | — (interno) |
| `reload_state: ReloadState` | **WeaponSystem** | CombatSystem |
| `ai_profile: WeaponAIProfile` | **WeaponSystem** | CombatSystem (rating), DecisionSystem |

### 8.3 WeaponAIProfile (Resource)
```
WeaponAIProfile:
    ai_rating: float           # 0.0-1.0 poder general
    preferred_range_min: float # distancia óptima mínima
    preferred_range_max: float # distancia óptima máxima
    splash_damage: bool        # ¿daño por área?
    lead_target: bool          # ¿predecir posición?
    refire_rate: float         # 0.0-1.0 probabilidad de seguir disparando
    aim_error_multiplier: float # multiplicador de error base
    attack_style: float        # -1.0 defensivo, +1.0 agresivo
    defense_style: float       # igual
    prefers_alt_fire: bool     # ¿usa modo alterno?
    is_melee: bool             # ¿es cuerpo a cuerpo?
    is_instant_hit: bool       # ¿hitscan?
    projectile_speed: float    # velocidad del proyectil (para predicción)
    splash_radius: float       # radio de splash
    height_advantage: float    # -1 abajo mejor, +1 arriba mejor
    
    func effective_dps(distance, ammo_ratio, height_delta) -> float
    func situational_rating(distance, context) -> float
```

### 8.4 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `weapon_ready()` | Arma lista para disparar |
| `weapon_empty()` | Sin munición en cargador |
| `reload_started(duration)` | Inicio de recarga |
| `reload_completed()` | Recarga terminada |
| `ammo_changed(current, reserve)` | Cambio en munición |

---

## 9. MÓDULO 7: HealthSystem

### 9.1 Responsabilidad Única
Gestionar salud, armadura, daño, muerte.

### 9.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `health: float` | **HealthSystem** | DecisionSystem, UISystem |
| `max_health: float` | **HealthSystem** | DecisionSystem |
| `armor: float` | **HealthSystem** | DecisionSystem |
| `damage_history: Array[DamageEvent]` | **HealthSystem** | DecisionSystem |
| `is_alive: bool` | **HealthSystem** | Todos (lectura) |
| `last_damage_time: float` | **HealthSystem** | DecisionSystem |
| `last_attacker: Node3D` | **HealthSystem** | DecisionSystem |

### 9.3 DamageEvent Structure
```
DamageEvent:
    amount: float
    attacker: Node3D
    damage_type: String
    position: Vector3
    timestamp: float
    armor_absorbed: float
```

### 9.4 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `damage_taken(amount, attacker, type)` | Recibió daño |
| `health_changed(new_health)` | Salud cambió |
| `death(attacker)` | Murió |
| `armor_depleted()` | Armadura agotada |
| `heal_received(amount, source)` | Recibió curación |

---

## 10. MÓDULO 8: NavigationSystem (Global)

### 10.1 Responsabilidad Única
Gestionar el grafo de navegación del mapa y los puntos semánticos. **NO decide rutas. NO mueve bots. NO detecta stuck.**

### 10.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `navigation_mesh: NavigationMesh` | **NavigationSystem** | NavigationServer3D |
| `semantic_points: Array[SemanticPoint]` | **NavigationSystem** | DecisionSystem (vía query) |
| `navigation_region: NavigationRegion3D` | **NavigationSystem** | NavigationServer3D |

### 10.3 API Pública (Solo Servicio)
```
get_path(from: Vector3, to: Vector3) -> Array[Vector3]
get_semantic_points(type: SemanticPointType, team: int) -> Array[SemanticPoint]
get_nearest_semantic_point(pos: Vector3, type: SemanticPointType) -> SemanticPoint
get_ambush_points(team: int) -> Array[SemanticPoint]
get_defense_points(objective_id: String) -> Array[SemanticPoint]
get_alternate_paths(team: int) -> Array[SemanticPoint]
has_semantic_point_near(pos: Vector3, type: SemanticPointType, radius: float) -> bool
```

### 10.4 Lo que NUNCA hace
- NO escribe `velocity` de ningún bot
- NO escribe `target_entity` de ningún bot
- NO cambia destinos de navegación de bots
- NO detecta stuck (eso es MovementSystem)
- NO decide qué ruta tomar (eso es DecisionSystem → MovementSystem)

---

## 11. MÓDULO 9: ObjectiveSystem (GameMode)

### 11.1 Responsabilidad Única
Definir los objetivos del equipo y del bot. **NO dice cómo cumplirlos.**

### 11.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `team_objectives: Array[Objective]` | **ObjectiveSystem** | DecisionSystem (solo lectura) |
| `match_phase: MatchPhase` | **ObjectiveSystem** | Todos (solo lectura) |
| `team_scores: Array[int]` | **ObjectiveSystem** | UI, Scoreboard |
| `match_timer: float` | **ObjectiveSystem** | UI, Scoreboard |

### 11.3 Objective Structure
```
Objective:
    objective_id: String
    objective_type: Enum { CAPTURE, DEFEND, ATTACK, RETURN, ESCORT, HOLD }
    target_node: NodePath
    position: Vector3
    team: int
    priority: float
    completion_radius: float
    is_completed: bool
    fallback_objective: String
    expires_at: float          # tiempo de expiración (opcional)
    assigned_bots: Array[int]  # bots asignados a este objetivo
```

### 11.4 MatchPhase
```
enum MatchPhase {
    WARMUP,
    ACTIVE,
    OVERTIME,
    COMPLETED,
}
```

### 11.5 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `objective_updated(objective, bot_id)` | Objetivo cambió |
| `objective_completed(objective_id, team)` | Objetivo completado |
| `match_phase_changed(new_phase)` | Fase de partida cambió |
| `threat_modifier(bot_id, threat_value)` | Modificador de amenaza por GameMode |
| `special_attraction(bot_id, position)` | Atracción especial para un bot |

### 11.6 Integración con GameModes
Cada GameMode (DM, TDM, CTF, DOM, AS) extiende ObjectiveSystem:
- **Deathmatch**: Sin objetivos de equipo. Cada bot usa FREELANCE.
- **TeamDeathmatch**: Objetivo = eliminar enemigos. Prioridad por cercanía.
- **CTF**: Objetivos = CAPTURE(flag enemiga), DEFEND(flag propia), RETURN(flag caída).
- **Dominación**: Objetivos = CAPTURE(puntos de control), DEFEND(puntos tomados).
- **Asalto**: Objetivos = ATTACK(fortaleza), DEFEND(fortaleza). Prioridad dinámica por fortalezas destruidas.

---

## 12. MÓDULO 10: OrderSystem

### 12.1 Responsabilidad Única
Gestionar órdenes por bot, jerarquía líder→seguidor, y separación RealOrders vs Orders.

### 12.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `current_orders: Dictionary[bot_id, Order]` | **OrderSystem** | DecisionSystem |
| `real_orders: Dictionary[bot_id, Order]` | **OrderSystem** | DecisionSystem (init) |
| `leaders: Dictionary[team_id, bot_id]` | **OrderSystem** | DecisionSystem |
| `order_givers: Dictionary[bot_id, Node3D]` | **OrderSystem** | DecisionSystem |

### 12.3 Order Types (UT99)
| Orden | Comportamiento |
|-------|----------------|
| `FREELANCE` | Sin órdenes específicas. El bot decide según su perfil y rol. |
| `ATTACK` | Atacar objetivo del equipo (core, bandera, punto de control). |
| `DEFEND` | Defender un punto específico (core, bandera, punto). Usa DefensePoint. |
| `FOLLOW` | Seguir a un líder (otro bot o jugador). Mantener distancia. |
| `HOLD` | Mantener posición fija. No moverse del punto asignado. |
| `POINT` | Apoyar a un jugador específico (escolta). |

### 12.4 Separación RealOrders vs Orders (UT99 exacto)
```
RealOrders: orden original y persistente. Se asigna al inicio de partida
o cuando un líder/GameMode cambia la misión del bot.

Orders: orden actual. Puede cambiar TEMPORALMENTE:
  - "Vi un enemigo" → Orders cambia a ATTACK (perseguir)
  - "Me están atacando" → Orders cambia a RETREAT (retirada temporal)
  - "Escuché un ruido" → Orders cambia a HUNT (investigar)

Regla: Cuando el bot completa su acción temporal, llama:
  SetOrders(RealOrders, OrderGiver, true)
  Esto restaura la orden original.
```

### 12.5 API
```
set_orders(bot_id, orders_type, target)
get_current_orders(bot_id) -> Order
get_real_orders(bot_id) -> Order
restore_real_orders(bot_id)
set_leader(team_id, leader_bot_id)
get_leader(team_id) -> Bot
```

---

## 13. MÓDULO 11: SkillSystem

### 13.1 Responsabilidad Única
Definir y gestionar perfiles de habilidad y personalidad de cada bot.

### 13.2 Data Ownership
| Variable | Propietario |
|----------|-------------|
| `bot_profiles: Dictionary[bot_id, BotProfile]` | **SkillSystem** |
| `difficulty_table: Dictionary` | **SkillSystem** |
| `match_history: Dictionary[bot_id, MatchRecord]` | **SkillSystem** |

### 13.3 BotProfile (Resource)
```
BotProfile:
    bot_name: String
    skill: int                    # 0-7 (UT99)
    accuracy: float               # 0.0-1.0
    combat_style: float           # -1.0 sniper / +1.0 agresivo
    aggressiveness: float         # 0.0-1.0
    alertness: float              # -1.0 distraído / +1.0 alerta
    camping_rate: float           # 0.0-1.0
    strafing_ability: float       # 0.0-1.0
    favorite_weapon: String
    jumpy: bool
    lead_target: bool
    b_devious: bool               # tácticas engañosas (fintas, caminos falsos)
    voice_type: String
    team: int
    difficulty_tier: String       # novice / standard / veteran / elite
    skin: String                  # skin visual
```

### 13.4 MatchRecord
```
MatchRecord:
    games_played: int
    wins_against_player: int
    losses_against_player: int
    current_streak: int           # racha actual de victorias/derrotas
    last_adjustment_time: float
```

### 13.5 API
```
get_profile(bot_id) -> BotProfile
get_random_profile_for_team(team) -> BotProfile
initialize_skill(bot, difficulty_level)
adjust_skill(bot_id, won_against_player)
```

---

## 14. MÓDULO 12: TeamCoordinator

### 14.1 Responsabilidad Única
Coordinar acciones entre bots del mismo equipo. Sustituye a team_ai.gd (actualmente vacío).

### 14.2 Data Ownership
| Variable | Propietario |
|----------|-------------|
| `team_composition: Dictionary[team_id, Array[bot_id]]` | **TeamCoordinator** |
| `role_assignment: Dictionary[team_id, Dictionary]` | **TeamCoordinator** |
| `squad_formations: Dictionary` | **TeamCoordinator** |

### 14.3 Funcionalidades

**Asignación de Roles:**
- Distribuir equitativamente los roles tácticos entre bots del equipo
- Re-asignar roles cuando un bot muere (otro cubre su posición)
- Identificar roles faltantes (ej: "no hay defensores, reasignar un assault")

**Coordinación de Ataques:**
- Identificar cuándo múltiples bots atacan al mismo objetivo
- Evitar saturación: si 3+ bots ya atacan un punto, los demás buscan otro
- Flanqueo coordinado: un grupo atrae, otro flanquea

**Solicitud de Ayuda:**
- Cuando un bot está en apuros (salud baja, superado en número)
- TeamCoordinator asigna el bot más cercano como refuerzo
- Limitación: máximo 2 bots por solicitud (no abandonar otras posiciones)

**Liderazgo:**
- Cada equipo tiene un líder (primer bot en asignarse)
- Si el líder muere, el segundo bot con más skill asume
- El líder coordina, no da órdenes directas (el OrderSystem las ejecuta)

### 14.4 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `role_changed(bot_id, new_role)` | Rol de un bot cambió |
| `help_requested(bot_id, position, severity)` | Bot pide ayuda |
| `help_dispatched(helper_id, target_id)` | Refuerzo asignado |
| `formation_updated(team, formation)` | Formación del equipo cambió |
| `leader_changed(team, new_leader_id)` | Nuevo líder del equipo |

---

## 15. MATRIZ DE DATA OWNERSHIP

### 15.1 Tabla Completa

| Variable | Propietario (ESCRIBE) | Lectores | Prohibido escribir |
|----------|----------------------|----------|-------------------|
| `velocity` | **MovementSystem** | Physics engine | DecisionSystem, CombatSystem, WeaponSystem, PerceptionSystem, HealthSystem |
| `global_position` | **Physics engine** | Todos leen | Nadie escribe directamente |
| `target_entity` | **DecisionSystem** | CombatSystem, PerceptionSystem | MovementSystem, WeaponSystem, HealthSystem |
| `movement_command` | **DecisionSystem** | MovementSystem | CombatSystem, WeaponSystem, PerceptionSystem |
| `combat_command` | **DecisionSystem** | CombatSystem | MovementSystem, WeaponSystem, HealthSystem |
| `aim_rotation` | **CombatSystem** | Model/Arma (visual) | DecisionSystem, MovementSystem, WeaponSystem |
| `weapon_status` | **WeaponSystem** | CombatSystem, DecisionSystem | MovementSystem, PerceptionSystem, HealthSystem |
| `ammo_count` | **WeaponSystem** | DecisionSystem, CombatSystem | MovementSystem, HealthSystem |
| `health` | **HealthSystem** | DecisionSystem, UI | MovementSystem, CombatSystem, WeaponSystem |
| `sensor_data` | **PerceptionSystem** | DecisionSystem, MemorySystem | MovementSystem, CombatSystem, WeaponSystem |
| `memory_store` | **MemorySystem** | DecisionSystem | PerceptionSystem (solo emite), todos los demás |
| `stuck_state` | **MovementSystem** | DecisionSystem | CombatSystem, WeaponSystem, HealthSystem |
| `navigation_path` | **MovementSystem** | — (interno) | Todos los demás |
| `objectives` | **ObjectiveSystem** | DecisionSystem | Todos los bots |
| `orders` | **OrderSystem** | DecisionSystem | MovementSystem, CombatSystem |
| `bot_profile` | **SkillSystem** | DecisionSystem (init) | MovementSystem, CombatSystem |
| `damage_history` | **HealthSystem** | DecisionSystem | CombatSystem, MovementSystem |
| `navigation_mesh` | **NavigationSystem** | NavigationServer3D | Todos los bots |
| `semantic_points` | **NavigationSystem** | DecisionSystem (vía query) | Todos los bots |
| `match_phase` | **ObjectiveSystem** | Todos (solo lectura) | Todos los bots |

### 15.2 Reglas de Acceso por Sistema

| Sistema | Puede escribir | Puede leer | Nunca escribe |
|---------|---------------|------------|---------------|
| PerceptionSystem | sensor_data | Posiciones globales, collision shapes | velocity, target_entity, movement_command, memory_store |
| MemorySystem | memory_store | sensor_data (vía señal) | velocity, target, commands, sensor_data |
| DecisionSystem | target_entity, movement_command, combat_command, focus_point, current_state | sensor_data, memory_store, objectives, orders, weapon_status, health, stuck_state | velocity, aim_rotation, weapon_status, ammo |
| MovementSystem | velocity, navigation_path, stuck_state | movement_command, NavigationAgent3D | target_entity, combat_command, aim_rotation |
| CombatSystem | aim_rotation, dodge_state, engagement_data | combat_command, weapon_status, target_entity | velocity, movement_command, navigation_path |
| WeaponSystem | weapon_status, ammo, cooldown | combat_command.fire_request | velocity, target_entity, movement_command |
| HealthSystem | health, damage_history | — (solo recibe daño) | velocity, target, commands |
| NavigationSystem | navigation_mesh, semantic_points | Geometría del mapa | Todo lo del bot |
| ObjectiveSystem | objectives, match_phase, scores | Estado global de partida | Todo lo del bot (solo emite señales) |
| OrderSystem | orders, leaders | objectives | Todo lo demás |
| SkillSystem | bot_profiles | — | Todo lo demás |
| TeamCoordinator | team_composition, role_assignment | objectives, scores | Todo lo demás |

---

## 16. FLUJO DEL FRAME (ORDEN ESTRICTO)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    FRAME COMPLETO (delta = 1/60)                     │
│                    Llamado desde NpcBase._physics_process()          │
└─────────────────────────────────────────────────────────────────────┘

FASE 0: SISTEMAS GLOBALES (orden fijo, 1 vez por frame)
┌─────────────────────────────────────────────────────────────────────┐
│ ObjectiveSystem.process(delta)                                      │
│   └── Verificar estado de objetivos, emitir cambios                │
│ NavigationSystem.process(delta)                                      │
│   └── Solo actualizar estructuras internas si cambió el mapa        │
│ TeamCoordinator.process(delta)                                       │
│   └── Coordinación entre bots, re-asignación de roles               │
└─────────────────────────────────────────────────────────────────────┘

FASE 1: SENSORES (por cada bot, orden fijo)
┌─────────────────────────────────────────────────────────────────────┐
│ 1. PerceptionSystem.update(delta)                                   │
│    ├── Escanear Area3D por cuerpos enemigos                         │
│    ├── Verificar LOS con RayCast3D                                  │
│    ├── Escribir: sensor_data.visible, .heard, .threats              │
│    └── Emitir: entity_detected, entity_lost, noise_heard            │
│                                                                     │
│ 2. MemorySystem.update(delta)                                       │
│    ├── Escuchar señales de PerceptionSystem                         │
│    ├── Integrar nuevos datos en memory_store                        │
│    ├── Decaer memorias existentes                                   │
│    ├── Escribir: memory_store (append/update/expire)                │
│    └── Emitir: memory_updated, memory_expired                       │
└─────────────────────────────────────────────────────────────────────┘

FASE 2: DECISIÓN (por cada bot)
┌─────────────────────────────────────────────────────────────────────┐
│ 3. DecisionSystem.process(delta)                                    │
│    ├── 3a. FSM.evaluate_transitions()                               │
│    │   ├── Leer: sensor_data, memory_store, objectives, orders      │
│    │   ├── Leer: health, weapon_status, stuck_state                 │
│    │   ├── Evaluar: ¿cambiar de estado?                             │
│    │   └── Si cambia → emitir state_changed, llamar exit/enter      │
│    │                                                                │
│    ├── 3b. FSM.state.execute(delta)                                 │
│    │   ├── Estado activo ejecuta su lógica                          │
│    │   ├── Escribir: movement_command, combat_command, target       │
│    │   ├── Escribir: focus_point                                    │
│    │   └── El estado NO escribe velocity, NO escribe weapon         │
│    │                                                                │
│    ├── 3c. TargetEvaluator.evaluate()                               │
│    │   ├── Si hay nuevos candidatos → evaluar amenaza               │
│    │   └── Decidir si cambiar de objetivo                           │
│    │                                                                │
│    └── 3d. CommandValidator.validate()                              │
│        ├── Validar movement_command (destino válido?)               │
│        ├── Validar combat_command (target vivo?)                    │
│        └── Si inválido → resetear a NONE/HOLD                       │
└─────────────────────────────────────────────────────────────────────┘

FASE 3: EJECUCIÓN (por cada bot)
┌─────────────────────────────────────────────────────────────────────┐
│ 4. CombatSystem.process(delta)                                      │
│    ├── Leer: combat_command (de DecisionSystem)                     │
│    ├── Leer: target_entity.position (de la escena)                  │
│    ├── Leer: weapon_status, ai_profile (de WeaponSystem)            │
│    ├── Calcular: aim_rotation = adjust_aim(target, weapon_profile)  │
│    ├── Calcular: should_fire = debería disparar este frame          │
│    ├── Escribir: aim_rotation (sin tocar velocity)                  │
│    ├── Escribir: engagement_analysis                                │
│    └── Emitir: weapon_fired, target_in_range, etc.                  │
│                                                                     │
│ 5. MovementSystem.process(delta)                                    │
│    ├── Leer: movement_command (de DecisionSystem)                   │
│    ├── Consultar: NavigationAgent3D (ruta actual)                   │
│    ├── Calcular: desired_velocity según modo                        │
│    ├── Aplicar: avoidance (separación entre bots)                   │
│    ├── Aplicar: gravedad (solo aquí)                                │
│    ├── ESCRIBIR: velocity                                           │
│    └── Emitir: stuck signals (si aplica)                            │
│                                                                     │
│ 6. WeaponSystem.process(delta)                                      │
│    ├── Leer: combat_command.should_fire (de CombatSystem)           │
│    ├── Procesar: cooldown, recarga, munición                        │
│    ├── Si fire_request && can_fire() → ejecutar fire()              │
│    └── Escribir: weapon_status, ammo, cooldown                      │
│                                                                     │
│ 7. HealthSystem.process(delta)  [solo si hay daño continuo]        │
│    └── Procesar: efectos de zona (lava, ácido, zonas de daño)      │
└─────────────────────────────────────────────────────────────────────┘

FASE 4: FÍSICA (por cada bot)
┌─────────────────────────────────────────────────────────────────────┐
│ 8. Physics engine (move_and_slide)                                  │
│    ├── LEE: velocity (ya escrita por MovementSystem)                │
│    ├── Aplica: colisiones, fricción, restitución                    │
│    ├── ESCRIBE: global_position (actualizada por física)            │
│    └── ESCRIBE: is_on_floor, is_on_wall (actualizado por física)    │
└─────────────────────────────────────────────────────────────────────┘

FASE 5: POST-PROCESAMIENTO (por cada bot)
┌─────────────────────────────────────────────────────────────────────┐
│ 9. MovementSystem.post_process(delta)                               │
│    ├── Verificar: stuck post-movimiento                             │
│    ├── Verificar: llegada a destino                                 │
│    └── Emitir: destination_reached, stuck_detected, path_blocked    │
│                                                                     │
│ 10. CombatSystem.post_process(delta)                                │
│     ├── Aplicar: aim_rotation al modelo/arma (solo visual)          │
│     └── No toca velocity, no toca posición                          │
└─────────────────────────────────────────────────────────────────────┘

FASE 6: SEÑALES DIFERIDAS (por cada bot, si las hay)
┌─────────────────────────────────────────────────────────────────────┐
│ 11. Procesar señales entrantes del frame anterior                   │
│     ├── DecisionSystem.on_destination_reached()                     │
│     ├── DecisionSystem.on_stuck_detected()                          │
│     ├── DecisionSystem.on_damage_taken()                            │
│     ├── DecisionSystem.on_target_lost()                             │
│     └── DecisionSystem.on_orders_changed()                          │
└─────────────────────────────────────────────────────────────────────┘
```

### 16.1 Timing Garantizado

| Sistema | Orden | Por qué este orden |
|---------|-------|-------------------|
| ObjectiveSystem | 0 | Los objetivos deben estar definidos antes de que los bots decidan |
| NavigationSystem | 0 | El navmesh debe estar listo antes de que los bots lo consulten |
| PerceptionSystem | 1 | Los datos sensoriales crudos deben estar listos para la memoria y decisión |
| MemorySystem | 2 | La memoria se actualiza con los datos sensoriales del mismo frame |
| DecisionSystem | 3 | Decide basado en percepción + memoria del mismo frame |
| CombatSystem | 4 | Calcula puntería basado en la decisión de combate |
| MovementSystem | 5 | Calcula velocity basado en la decisión de movimiento |
| WeaponSystem | 6 | Dispara basado en la decisión de combate + aim |
| HealthSystem | 7 | Procesa daño continuo (no urgente, puede ir al final) |
| Physics | 8 | move_and_slide usa la velocity final |
| Post-process | 9 | Verifica resultados del movimiento |

---

## 17. MAPA COMPLETO DE SEÑALES

### 17.1 Conexiones Internas del Bot

```
PerceptionSystem ──entity_detected──────────────▶ DecisionSystem
PerceptionSystem ──entity_lost──────────────────▶ DecisionSystem
PerceptionSystem ──threat_assessed──────────────▶ DecisionSystem
PerceptionSystem ──noise_heard──────────────────▶ MemorySystem
PerceptionSystem ──noise_heard──────────────────▶ DecisionSystem

MemorySystem ──────memory_updated───────────────▶ DecisionSystem
MemorySystem ──────memory_expired───────────────▶ DecisionSystem

MovementSystem ────destination_reached──────────▶ DecisionSystem
MovementSystem ────stuck_detected───────────────▶ DecisionSystem
MovementSystem ────path_blocked─────────────────▶ DecisionSystem

CombatSystem ──────weapon_fired─────────────────▶ WeaponSystem
CombatSystem ──────target_in_range──────────────▶ DecisionSystem
CombatSystem ──────target_lost──────────────────▶ DecisionSystem
CombatSystem ──────out_of_ammo──────────────────▶ DecisionSystem
CombatSystem ──────dodge_performed──────────────▶ MovementSystem (vía DecisionSystem)

WeaponSystem ──────weapon_ready─────────────────▶ CombatSystem
WeaponSystem ──────weapon_empty─────────────────▶ CombatSystem
WeaponSystem ──────weapon_empty─────────────────▶ DecisionSystem
WeaponSystem ──────reload_started───────────────▶ CombatSystem
WeaponSystem ──────reload_completed─────────────▶ CombatSystem
WeaponSystem ──────ammo_changed─────────────────▶ DecisionSystem

HealthSystem ──────damage_taken─────────────────▶ DecisionSystem
HealthSystem ──────damage_taken─────────────────▶ MemorySystem
HealthSystem ──────health_changed───────────────▶ DecisionSystem
HealthSystem ──────death────────────────────────▶ DecisionSystem
HealthSystem ──────death────────────────────────▶ MatchManager
```

### 17.2 Conexiones Globales

```
ObjectiveSystem ───objective_updated────────────▶ TeamCoordinator
ObjectiveSystem ───objective_updated────────────▶ DecisionSystem (cada bot)
ObjectiveSystem ───objective_completed──────────▶ TeamCoordinator
ObjectiveSystem ───match_phase_changed──────────▶ MatchManager
ObjectiveSystem ───match_phase_changed──────────▶ HUD
ObjectiveSystem ───orders_changed───────────────▶ DecisionSystem (bot específico)
ObjectiveSystem ───special_attraction───────────▶ DecisionSystem (bot específico)

TeamCoordinator ───role_changed─────────────────▶ DecisionSystem (bot específico)
TeamCoordinator ───help_requested───────────────▶ DecisionSystem (bots cercanos)
TeamCoordinator ───leader_changed───────────────▶ OrderSystem

MatchManager ──────match_started────────────────▶ ObjectiveSystem
MatchManager ──────match_started────────────────▶ SkillSystem
MatchManager ──────match_started────────────────▶ TeamCoordinator
MatchManager ──────match_started────────────────▶ HUD
MatchManager ──────bot_respawned────────────────▶ ObjectiveSystem
MatchManager ──────bot_respawned────────────────▶ SkillSystem (AdjustSkill)

GameState ─────────match_ended──────────────────▶ MatchManager
GameState ─────────match_ended──────────────────▶ HUD
GameState ─────────match_ended──────────────────▶ ObjectiveSystem
```

### 17.3 Signal Bus (Autoload)

```
BotSignalBus (Autoload)
├── Señales de broadcast a todos los bots
├── Útil para comunicación que no necesita destinatario específico
├── Ejemplos:
│   ├── team_objective_updated(objective_id, team)
│   ├── global_alert(position, type, intensity)
│   └── match_phase_changed(phase)
└── Los bots se conectan en _ready() y se desconectan en _exit_tree()
```

---

## 18. FSM: ESTADOS Y TRANSICIONES

### 18.1 Jerarquía de Estados (UT99 adaptada)

```
StartUp (inicial)
  │
  ├──▶ Roaming (estado por defecto)
  │       │
  │       ├──▶ Wandering (sin objetivo claro)
  │       │
  │       ├──▶ Holding (orden HOLD recibida)
  │       │
  │       ├──▶ Attacking (cuando detecta/detectan enemigo)
  │       │       │
  │       │       ├──▶ TacticalMove (combate evasivo)
  │       │       ├──▶ Charging (carga agresiva)
  │       │       ├──▶ RangedAttack (ataque a distancia)
  │       │       └──▶ Retreating (retirada táctica)
  │       │
  │       ├──▶ Hunting (perseguir última posición conocida)
  │       │
  │       ├──▶ StakeOut (esperar en última posición conocida)
  │       │
  │       ├──▶ TakingHit (reacción al recibir daño)
  │       │
  │       └──▶ Falling (cayendo)
  │
  └── Acquisition (transición temporal al detectar enemigo)
```

### 18.2 Tabla de Estados

| Estado | Prioridad | Propósito | ¿Cuándo se activa? |
|--------|-----------|-----------|-------------------|
| `TAKING_HIT` | 110 | Reacción inmediata al daño | Daño recibido y actitud no agresiva |
| `ATTACKING` | 100 | Combate activo | Enemigo visible o detectado |
| `RETREATING` | 90 | Retirada táctico | Salud baja, enemigo más fuerte |
| `HUNTING` | 50 | Persecución | Perdió visión, hay memoria de posición |
| `STAKEOUT` | 40 | Espera táctica | Perdió visión, sin memoria reciente |
| `HOLDING` | 30 | Mantener posición | Orden DEFEND/HOLD recibida |
| `ROAMING` | 10 | Patrullaje general | Sin enemigos, sin órdenes específicas |
| `FALLING` | 5 | Cayendo | No está en el suelo |
| `WANDERING` | 3 | Deambular | Sin objetivo, rol patrullero |
| `STARTUP` | 0 | Inicialización | Primera vez que se ejecuta |

### 18.3 Matriz de Transiciones

```
Estado Actual    ▶ Puede transicionar a
─────────────────────────────────────────────────────
STARTUP          ▶ ROAMING, HOLDING (si hay órdenes)
ROAMING          ▶ ATTACKING, HUNTING, STAKEOUT, HOLDING, TAKING_HIT, FALLING, RETREATING
WANDERING        ▶ ROAMING (si encuentra objetivo), ATTACKING, TAKING_HIT
HOLDING          ▶ ATTACKING, TAKING_HIT, RETREATING, ROAMING (si orden cambia)
ATTACKING        ▶ TACTICAL_MOVE, CHARGING, RANGED_ATTACK, RETREATING, HUNTING, TAKING_HIT
TACTICAL_MOVE    ▶ RANGED_ATTACK, CHARGING, RETREATING, ATTACKING (pierde LOS)
CHARGING         ▶ TACTICAL_MOVE, RANGED_ATTACK, RETREATING
RANGED_ATTACK    ▶ TACTICAL_MOVE, CHARGING, RETREATING
RETREATING       ▶ ATTACKING (si llega a zona segura), ROAMING
HUNTING          ▶ ATTACKING (encuentra enemigo), STAKEOUT (llega y no encuentra), ROAMING
STAKEOUT         ▶ ATTACKING (enemigo aparece), HUNTING (memoria se actualiza), ROAMING
TAKING_HIT       ▶ ATTACKING (daño de enemigo visible), RETREATING, ROAMING
FALLING          ▶ ROAMING (aterriza), cualquier estado de combate
```

### 18.4 Reglas de Transición (generales)

1. **Un estado solo puede transicionar durante su propio `evaluate_transitions()`**
2. **La transición ocurre entre frames**, nunca en medio de un `execute()`
3. **Cada estado tiene `enter()` y `exit()`** que se llaman en la transición
4. **Prioridad define qué estado gana** si múltiples condiciones se cumplen
5. **Excepción**: TAKING_HIT y FALLING son estados "interruptores" — pueden interrumpir cualquier estado

### 18.5 Ejemplo: Ciclo Completo de Combate

```
1. ROAMING: patrullando hacia core enemigo
2. PerceptionSystem detecta enemigo
   → DecisionSystem recibe entity_detected
3. FSM.evaluate_transitions():
   - condition: has_visible_enemy AND should_engage
   - transition: ROAMING → ATTACKING
4. ATTACKING.enter():
   - Fijar target_entity
   - Decidir sub-estado según distancia
5. ATTACKING.execute():
   - combat_command: engage=true, fire_mode=primario
   - movement_command: mode=NAVIGATE, target=enemy.position
6. Enemigo se acerca → transition: ATTACKING → TACTICAL_MOVE
7. TACTICAL_MOVE.execute():
   - combat_command: engage=true (disparar)
   - movement_command: mode=DIRECT, direction=strafe
8. Enemigo huye → transition: TACTICAL_MOVE → CHARGING
9. CHARGING.execute():
   - combat_command: engage=true
   - movement_command: mode=NAVIGATE, target=enemy (perseguir)
10. Pierde visión del enemigo → transition: CHARGING → HUNTING
11. HUNTING.execute():
    - movement_command: mode=NAVIGATE, target=last_seen_position
12. Llega y no encuentra → transition: HUNTING → ROAMING
```

---

## 19. COMANDOS: MovementCommand y CombatCommand

### 19.1 MovementCommand (Resource Transitorio)
```
class MovementCommand:
    enum Mode { NONE, NAVIGATE, DIRECT, DODGE, STOP }
    
    mode: Mode = NONE
    target_position: Vector3     # Para NAVIGATE
    direction: Vector3           # Para DIRECT, DODGE
    speed: float = 0.0
    jump: bool = false
    jump_velocity: float = 0.0
    sprint: bool = false
    dodge_impulse: float = 0.0
    use_advanced_tactics: bool = false  # flanqueo, wall-dodge, etc.
```

### 19.2 CombatCommand (Resource Transitorio)
```
class CombatCommand:
    engage: bool = false         # ¿disparar este frame?
    target_id: int
    fire_mode: int = 0           # 0=primario, 1=alterno
    aim_at_position: Vector3     # posición exacta para apuntar
    aim_at_entity: NodePath      # o ruta a la entidad
    force_fire: bool = false     # ignorar refire rate
    cease_fire: bool = false     # dejar de disparar explícitamente
    movement_adjustment: Vector3 # ajuste de movimiento solicitado por combate
                                 # (MovementSystem puede limitarlo/ignorarlo)
```

### 19.3 Reglas de los Comandos
1. **Se crean nuevos cada frame** — DecisionSystem los escribe en FASE 2
2. **Se consumen una vez** — MovementSystem/CombatSystem los leen una vez en FASE 3
3. **Estado por defecto** = "no hacer nada" (NONE / engage=false)
4. **Si no se escribe un comando** el frame actual, el sistema ejecutor no hace nada
5. **El CommandValidator** verifica coherencia antes de que los ejecutores lean

---

## 20. NAVEGACIÓN SEMÁNTICA

### 20.1 SemanticPoint (Resource)

Jerarquía inspirada en NavigationPoint de UT99:

```
SemanticPoint (base)
├── type: SemanticPointType
├── position: Vector3
├── team: int (-1 = neutral)
├── priority: int
├── look_direction: Vector3
├── sight_radius: float
├── extra_cost: float (costo adicional en pathfinding)
├── tags: Array[String]
├── is_one_way: bool
├── is_return_only: bool
├── is_player_only: bool
└── selection_weight: float (0.0-1.0, para distribución probabilística)
```

### 20.2 Tipos de SemanticPoint

| Tipo | Propósito | Atributos especiales |
|------|-----------|---------------------|
| `PATH` | Nodo de ruta genérico | — |
| `AMBUSH` | Punto de emboscada | `look_direction`, `sight_radius`, `is_sniper_spot` |
| `DEFENSE` | Punto de defensa por equipo | `team`, `priority`, `fort_tag` (asociación a objetivo) |
| `ALTERNATE` | Ruta alternativa (CTF) | `team`, `selection_weight`, `is_return_only` |
| `LIFT_CENTER` | Centro de ascensor | `lift_reference`, `trigger_reference` |
| `LIFT_EXIT` | Salida de ascensor | `lift_center_reference` |
| `ITEM` | Punto donde aparece un item | `item_type`, `respawn_time` |
| `SNIPER` | Punto de francotirador | `look_direction`, `sight_radius`, `min_skill` |

### 20.3 Integración con NavigationServer3D

```
En lugar de reemplazar NavigationServer3D, los SemanticPoints se
superponen como una capa semántica sobre el navmesh.

Flujo de pathfinding semántico:
1. MovementSystem (en el bot) solicita ruta: A → B
2. NavigationServer3D calcula ruta geométrica (navmesh)
3. DecisionSystem consulta NavigationSystem:
   "Dame el SemanticPoint más cercano a mi destino"
4. DecisionSystem decide:
   a) Usar ruta directa (más rápida, predecible)
   b) Usar ruta con flanqueo (ALTERNATE path)
   c) Ir a punto AMBUSH cercano
   d) Ir a punto DEFENSE si está defendiendo
5. MovementSystem ejecuta la ruta geométrica
   + ocasionalmente verifica: "¿estoy pasando por un punto táctico?"
```

### 20.4 Costos Dinámicos (ExtraCost / SpecialCost)

```
NavigationSystem expone:
  get_adjusted_cost(semantic_point, bot_context) -> float
    - Base: semantic_point.extra_cost
    - Si el bot está herido: +10.0 (evitar zonas peligrosas)
    - Si el bot tiene bandera: +20.0 para ALTERNATE (preferir ruta segura)
    - Si el punto está bajo fuego enemigo: +15.0
    - Personalizable por GameMode vía callback
```

### 20.5 AlternatePath System (CTF)

```
Flujo de selección de ruta alternativa:
1. Bot tiene orden ATTACK en CTF
2. DecisionSystem consulta NavigationSystem:
   "¿Hay AlternatePaths para mi equipo?"
3. Si sí:
   - Cada AlternatePath tiene selection_weight
   - Distribución probabilística entre bots del equipo
   - Algunos van por ruta directa, otros por alterna
4. Si el bot lleva la bandera (return):
   - Prefiere AlternatePath con is_return_only=true
   - Mayor extra_cost para rutas directas (más riesgo)
```

---

## 21. SISTEMA DE ÓRDENES (UT99 RealOrders)

### 21.1 Estructura

```
OrderSystem (subsistema de ObjectiveSystem)
├── current_orders: Dictionary[bot_id, Order]
├── real_orders: Dictionary[bot_id, Order]
├── leaders: Dictionary[team_id, bot_id]
└── order_givers: Dictionary[bot_id, Node3D]

Order:
    order_type: OrderType  # FREELANCE, ATTACK, DEFEND, FOLLOW, HOLD, POINT
    target: NodePath       # a quién/apuntar la orden
    position: Vector3      # posición asociada
    giver: Node3D          # quién dio la orden (GameMode, líder, jugador)
    timestamp: float       # cuándo se dio
    is_temporary: bool     # si es temporal (Orders) o persistente (RealOrders)
```

### 21.2 Flujo de Órdenes (UT99 exacto)

```
1. Inicio de partida:
   MatchManager asigna órdenes iniciales según GameMode y rol:
   - DEFENDER → DEFEND (core/propio)
   - ASSAULT → ATTACK (core enemigo)
   - FLANKER → ATTACK (con ruta alternativa)
   - PATROLLER → FREELANCE (sin órdenes fijas)

2. Durante la partida:
   Los bots pueden DESVIARSE temporalmente de sus órdenes:
   - "Veo un enemigo" → Orders cambia a ATTACK (temporal)
   - "Me disparan" → Orders cambia a RETREAT (temporal)
   - "Oigo un ruido" → Orders cambia a HUNT (temporal)

3. Restauración:
   Cuando el bot completa su acción temporal:
   - Enemigo muerto o escapó → SetOrders(RealOrders, OrderGiver, true)
   - Llegó a zona segura → SetOrders(RealOrders, OrderGiver, true)
   - FindSpecialAttractionFor() retorna null → SetOrders(RealOrders, OrderGiver, true)

4. Cambio permanente:
   - GameMode cambia objetivo (ej: nueva fortaleza en Asalto)
   - Líder asigna nueva misión
   - RealOrders se actualiza, y el bot ejecuta SetOrders con la nueva orden
```

### 21.3 Jerarquía Líder→Seguidor

```
1. Cada equipo tiene un líder (primer bot en asignarse, o el de mayor skill)
2. El líder NO ordena directamente — el OrderSystem gestiona las órdenes
3. El líder es un "punto de referencia" para FOLLOW:
   - Los bots con orden FOLLOW siguen al líder
   - Distancia de seguimiento: 5-10 unidades
   - Si el líder muere, reasignar seguidores al nuevo líder
4. bLeading flag: el líder sabe que otros le siguen
   - Puede esperar si el seguidor se queda atrás
   - Puede cambiar de ruta si el seguidor está atascado
```

---

## 22. PERFILES DE BOT (BotProfile + TacticalRole)

### 22.1 Sistema de Dos Capas

```
CAPA 1: BotProfile (Resource) — Define QUIÉN es el bot
  - Identidad: nombre, equipo, voz, skin
  - Habilidad: skill, accuracy, strafing_ability
  - Personalidad: combat_style, aggressiveness, alertness, camping_rate, jumpy
  - Preferencias: favorite_weapon, lead_target, b_devious
  
CAPA 2: TacticalRole (RefCounted) — Define CÓMO se comporta en equipo
  - Movimiento: movement_profile, speed_multiplier, flanking_bias
  - Combate: preferred_engagement_min/max, aggression, strafe_change_interval
  - Táctico: base_defense_radius, objective_focus, reaction_range, target_persistence
  - Exploración: route_re_eval_rate, jump_frequency

El BotProfile es ESTÁTICO (se asigna al inicio).
El TacticalRole puede CAMBIAR (TeamCoordinator reasigna según necesidades).
```

### 22.2 Perfiles de Dificultad (Skill Tiers)

| Tier | Skill | accuracy | strafing | alertness | camping | lead_target | Descripción |
|------|-------|----------|----------|-----------|---------|-------------|-------------|
| NOVICE | 0-1 | 0.1-0.2 | 0.0 | -0.5 | 0.0 | false | Dispara sin puntería, se queda quieto |
| STANDARD | 2-3 | 0.3-0.5 | 0.3 | 0.0 | 0.2 | false | Bot promedio de UT99 |
| VETERAN | 4-5 | 0.6-0.7 | 0.6 | 0.5 | 0.3 | true | Strafing competente, predice |
| ELITE | 6-7 | 0.8-1.0 | 0.9 | 1.0 | 0.4 | true | Precisión máxima, tácticas engañosas (bDevious) |

### 22.3 TacticalRole Configuration Matrix

| Parámetro | DEFENDER | ASSAULT | FLANKER | PATROLLER |
|-----------|----------|---------|---------|-----------|
| movement_profile | DEFENSIVE | AGGRESSIVE | FLANKING | PATROL |
| preferred_engagement_min | 3.0 | 5.0 | 3.0 | 6.0 |
| preferred_engagement_max | 12.0 | 18.0 | 12.0 | 20.0 |
| aggression | 0.35 | 0.75 | 0.65 | 0.5 |
| target_persistence | 8.0s | 6.0s | 4.0s | 2.5s |
| base_defense_radius | 20.0 | 0.0 | 0.0 | 40.0 |
| flanking_bias | 0.0 | 0.2 | 0.9 | 0.4 |
| objective_focus | 0.4 | 0.8 | 0.6 | 0.2 |
| speed_multiplier | 0.9 | 1.15 | 1.2 | 1.0 |
| jump_frequency | 0.1 | 0.3 | 0.5 | 0.2 |
| reaction_range | 25.0 | ∞ | ∞ | 35.0 |
| strafe_change_interval | 3.5s | 1.5s | 1.0s | 2.5s |
| route_re_eval_rate | 5.0s | 3.0s | 2.0s | 2.5s |

---

## 23. PERFILES DE ARMA (WeaponAIProfile)

### 23.1 WeaponAIProfile (Resource)

```
class WeaponAIProfile extends Resource:
    ai_rating: float                    # 0.0-1.0 poder general
    preferred_range_min: float          # distancia óptima mínima (uds)
    preferred_range_max: float          # distancia óptima máxima (uds)
    splash_damage: bool                 # ¿daño por área?
    splash_radius: float                # radio de splash
    lead_target: bool                   # ¿predecir posición del enemigo?
    refire_rate: float                  # 0.0-1.0 probabilidad de seguir disparando
    aim_error_base: int                 # error base en unidades (ej: 2000)
    attack_style_modifier: float        # -1.0 a 1.0 (modifica combat_style del bot)
    defense_style_modifier: float       # -1.0 a 1.0
    prefers_alt_fire: bool              # ¿usa modo alterno por defecto?
    is_melee: bool                      # ¿es cuerpo a cuerpo?
    is_instant_hit: bool                # ¿hitscan?
    projectile_speed: float             # velocidad del proyectil (para predicción)
    height_advantage: float             # -1 mejor desde abajo, +1 mejor desde arriba
    base_dps: float                     # daño por segundo base
    optimal_range_falloff: float        # caída de efectividad fuera de rango óptimo
    
    func effective_dps(distance, ammo_ratio, height_delta) -> float
    func situational_rating(distance, bot_context) -> float
    func get_recommended_fire_mode(distance, target_info) -> int
```

### 23.2 Integración con el Bot

```
1. WeaponSystem carga el WeaponAIProfile desde el Resource asociado al arma
2. CombatSystem consulta el profile para:
   - Decidir modo de fuego (primario/alterno)
   - Calcular error de puntería adaptativo
   - Determinar si debe predecir posición
   - Elegir entre apuntar al cuerpo o al suelo (splash)
3. DecisionSystem consulta el profile para:
   - Evaluar RelativeStrength (via effective_dps)
   - Decidir distancia de engagement ideal
   - Elegir arma de la cadena de inventario (SwitchToBestWeapon)
4. SkillSystem usa el profile para escalar por dificultad:
   - Bots novatos: ignoran lead_target, mayor aim_error
   - Bots veteranos: usan refire_rate completo, menor aim_error
```

### 23.3 Tabla de Ratings por Arma (Ejemplo)

| Arma | Rating | Rango Pref | Splash | Lead | Refire | error_base |
|------|--------|------------|--------|------|--------|-----------|
| USP | 0.3 | 2-15 | no | no | 0.6 | 2000 |
| Shotgun | 0.5 | 2-10 | no | no | 0.7 | 2500 |
| Rifle | 0.7 | 15-50 | no | sí | 0.5 | 1000 |
| Rocket | 0.8 | 5-25 | sí | sí | 0.3 | 1500 |
| Minigun | 0.6 | 5-30 | no | sí | 0.9 | 1800 |
| Sniper | 0.9 | 30-80 | no | sí | 0.2 | 500 |

---

## 24. DIFICULTAD DINÁMICA

### 24.1 Algoritmo AdjustSkill (UT99 modernizado)

```
AdjustSkill(bot_id, won_against_player: bool):
    1. profile = bot_profiles[bot_id]
    2. match_record = match_history[bot_id]
    3. match_record.games_played += 1
    
    4. if won_against_player:
       # Bot ganó → baja dificultad (fue demasiado difícil)
       match_record.current_streak = max(0, match_record.current_streak - 1)
       adjustment = -2.0 / min(match_record.games_played, 10)
    5. else:
       # Bot perdió → sube dificultad (fue demasiado fácil)
       match_record.current_streak += 1
       adjustment = 2.0 / min(match_record.games_played, 10)
    
    6. profile.skill = clamp(profile.skill + adjustment, 0, 7)
    7. profile.accuracy = clamp(profile.accuracy + adjustment * 0.05, 0.0, 1.0)
    8. profile.strafing_ability = clamp(profile.strafing_ability + adjustment * 0.03, 0.0, 1.0)
    
    9. # Recalcular tier
       if profile.skill < 2: profile.difficulty_tier = "novice"
       elif profile.skill < 4: profile.difficulty_tier = "standard"
       elif profile.skill < 6: profile.difficulty_tier = "veteran"
       else: profile.difficulty_tier = "elite"
    
    10. match_record.last_adjustment_time = Time.get_ticks_msec() / 1000.0
```

### 24.2 Impacto del Skill en el Comportamiento

| Atributo | Skill 0 (Novice) | Skill 3 (Standard) | Skill 5 (Veteran) | Skill 7 (Elite) |
|----------|-----------------|-------------------|-------------------|-----------------|
| accuracy | 0.1 | 0.4 | 0.65 | 0.9 |
| strafing_ability | 0.0 | 0.3 | 0.6 | 0.9 |
| alertness | -0.5 | 0.0 | 0.5 | 1.0 |
| camping_rate | 0.0 | 0.2 | 0.3 | 0.4 |
| lead_target | false | false | true | true |
| b_devious | false | false | false | true |
| Aim error base | ×3.0 | ×1.5 | ×1.0 | ×0.5 |
| Reaction time | +0.5s | +0.2s | normal | -0.2s |
| Weapon switch speed | lento | normal | rápido | instantáneo |

### 24.3 Dificultad por Mapa/GameMode

```
Cada mapa y GameMode puede definir un modificador de dificultad base:
  - Mapa pequeño (DM-Deathmatch): +0 skill (fácil de encontrar enemigos)
  - Mapa grande (CTF-Face): +2 skill (difícil navegar)
  - Contra jugador humano: +1 skill (bonus por ser humano)
  - Contra múltiples bots aliados: -1 skill (compensar número)
```

---

## 25. PERSONALIDAD Y VOCES

### 25.1 Componentes de Personalidad

```
BotProfile.personality:
    aggressiveness: 0.0-1.0    # ¿Busca pelea o la evita?
    alertness: -1.0 a 1.0      # ¿Nota cosas o está distraído?
    camping_rate: 0.0-1.0      # ¿Le gusta quedarse quieto?
    jumpy: bool                # ¿Salta constantemente?
    b_devious: bool            # ¿Usa tácticas engañosas?
    combat_style: -1.0 a 1.0   # Sniper vs Agresivo
    
    # Estos modifican el comportamiento BASE del TacticalRole
    # Ej: Un ASSAULT con alta camping_rate puede detenerse a acampar
    # Ej: Un DEFENDER con alta aggressiveness a veces persigue
```

### 25.2 Sistema de Voces (UT99 style)

```
VoiceType Resource:
    name: String
    sound_bank: Dictionary      # mapa de eventos → AudioStream
    kill_phrases: Array[String]
    death_phrases: Array[String]
    order_ack_phrases: Array[String]
    enemy_spotted_phrases: Array[String]
    help_phrases: Array[String]
    
    func play_event(event_type: String) -> void:
        # Reproducir sonido asociado al evento
        # Los bots ELITE hablan más frecuentemente
        # Los bots NOVICE solo hablan en eventos críticos
```

### 25.3 Modificadores de Personalidad en Combate

```
Agresividad alta (0.8+):
  - Prefiere CHARGING sobre TACTICAL_MOVE
  - Menor umbral de retirada (no se retira hasta 15% HP)
  - Mayor refire_rate (dispara constantemente)
  - Busca combate cuerpo a cuerpo
  - Usa menos cobertura

Agresividad baja (0.2-):
  - Prefiere TACTICAL_MOVE sobre CHARGING
  - Se retira al 50% HP
  - Menor refire_rate (dispara con cautela)
  - Busca distancia
  - Usa cobertura frecuentemente

Alertness alta (0.8+):
  - Menor tiempo de reacción a nuevos estímulos
  - Detecta enemigos en ángulos más amplios (visión periférica)
  - Cambia de objetivo más rápido
  - Recuerda enemigos por más tiempo (+5s en memoria)

Alertness baja (-0.5):
  - Mayor tiempo de reacción
  - Visión más estrecha
  - Persiste más en objetivo actual (no se distrae)
  - Olvida enemigos más rápido (-5s en memoria)
```

---

## 26. INTEGRACIÓN CON GAMEMODES

### 26.1 Arquitectura GameMode

```
ObjectiveSystem (base)
├── find_special_attraction_for(bot) -> Vector3  # ¿Hay algo interesante para este bot?
├── get_threat_modifier(bot, candidate) -> float  # Modificador de amenaza específico
├── get_objectives_for_team(team) -> Array[Objective]
├── get_objectives_for_bot(bot) -> Array[Objective]
└── on_bot_killed(victim, killer)

Los GameModes concretos heredan y SOBRESCRIBEN estos métodos:

GameMode_Deathmatch
  - Sin objetivos de equipo
  - find_special_attraction_for: siempre null (todo es "ve y pelea")
  - get_threat_modifier: sin modificador

GameMode_TeamDeathmatch
  - find_special_attraction_for: enemigos cerca de aliados
  - get_threat_modifier: +0.2 si el enemigo está matando aliados

GameMode_CTF
  - find_special_attraction_for: bandera caída, bandera enemiga, base enemiga
  - get_threat_modifier: +0.5 si el enemigo lleva la bandera
  - get_objectives_for_team: CAPTURE bandera enemiga, DEFEND bandera propia, RETURN bandera caída

GameMode_Domination
  - find_special_attraction_for: puntos de control sin capturar, puntos bajo ataque
  - get_threat_modifier: +0.3 cerca de punto de control disputado
  - get_objectives_for_team: CAPTURE puntos neutrales, DEFEND puntos propios

GameMode_Assault
  - find_special_attraction_for: fortaleza activa, DefensePoints de fortaleza
  - get_threat_modifier: +0.4 si el enemigo está en la fortaleza actual
  - get_objectives_for_team: ATTACK fortaleza X, DEFEND fortaleza Y
  - Prioridad de fortaleza: la más cercana no destruida
```

### 26.2 FindSpecialAttraction (patrón Strategy)

```
Este es el mecanismo por el cual el GameMode "secuestra" la decisión del bot.
El bot llama a FindSpecialAttractionFor() durante ChooseAttackMode().
Si retorna una posición, el bot va ALLÍ, ignorando su decisión normal.

Esto permite:
  - CTF: "ve a recoger la bandera caída"
  - DOM: "ve a capturar el punto de control"
  - AS: "ve a la fortaleza"
  - TDM: "ve a apoyar a tu aliado que está siendo atacado"
```

### 26.3 MatchManager y GameState

```
MatchManager (Autoload) — GESTIONA la partida
  - Pool de bots, spawn, respawn, auto-balance
  - Registro centralizado de PlayerData
  - Inicia/termina la partida
  - NO tiene lógica de IA

GameState (Autoload) — ESTADO de la partida
  - match_active, winner_team, cores
  - Configuración global (sensibilidad, mapa seleccionado)
  - NO tiene lógica de gameplay

ObjectiveSystem (en el mapa) — OBJETIVOS de la partida
  - Define qué deben hacer los bots
  - Se instancia según el GameMode seleccionado

División clara:
  MatchManager = "cómo se juega" (reglas de partida)
  GameState = "qué está pasando" (estado global)
  ObjectiveSystem = "qué deben hacer los bots" (objetivos de IA)
```

---

## 27. ESTRUCTURA DE ESCENA (NODE TREE)

### 27.1 Nodo Bot (CharacterBody3D)

```
npc.tscn:
EnemyBot (CharacterBody3D)
├── CollisionShape3D
├── NavigationAgent3D (Godot nativo)
├── AreaVision (Area3D) — zona de detección visual
├── RaycastVision (RayCast3D) — línea de visión
├── Head (Node3D) — punto de origen para raycast visual
│   └── WeaponPivot (Node3D) — punto de anclaje del arma
│       └── Weapon (Weapon) — instancia del arma
├── AI (Node)
│   ├── PerceptionSystem (Node)
│   │   └── SightCone (Area3D) — opcional, cono de visión
│   ├── MemorySystem (Node)
│   ├── DecisionSystem (Node)
│   │   ├── StateMachine (Node)
│   │   │   ├── State_StartUp (BotState)
│   │   │   ├── State_Roaming (BotState)
│   │   │   ├── State_Attacking (BotState)
│   │   │   │   ├── State_TacticalMove (BotState)
│   │   │   │   ├── State_Charging (BotState)
│   │   │   │   └── State_RangedAttack (BotState)
│   │   │   ├── State_Hunting (BotState)
│   │   │   ├── State_StakeOut (BotState)
│   │   │   ├── State_Retreating (BotState)
│   │   │   ├── State_Holding (BotState)
│   │   │   ├── State_TakingHit (BotState)
│   │   │   └── State_Falling (BotState)
│   │   ├── TargetEvaluator (Node)
│   │   └── CommandValidator (Node)
│   ├── MovementSystem (Node)
│   │   ├── StuckDetector (Node)
│   │   └── AutoJumper (Node)
│   ├── CombatSystem (Node)
│   │   └── AimController (Node)
│   ├── WeaponSystem (Node)
│   │   └── WeaponAIProfile (Resource)
│   └── HealthSystem (Node)
├── BotProfile (Resource) — asignado por SkillSystem
└── TeamIdentifier (Node)
```

### 27.2 Sistemas Globales

```
Mapa (escena del nivel):
├── NavigationRegion3D — navmesh del mapa
├── NavigationSystem (Node) — gestor de navegación + puntos semánticos
├── ObjectiveSystem (Node) — gestor de objetivos (GameMode)
│   └── OrderSystem (Node) — gestor de órdenes
├── TeamCoordinator (Node) — coordinación entre bots
└── SemanticPoints (Node)
    ├── AmbushPoint (Marker3D) — punto de emboscada
    ├── DefensePoint (Marker3D) — punto de defensa
    └── AlternatePath (Marker3D) — ruta alternativa

Autoloads:
├── MatchManager (Autoload) — gestión de partida
├── GameState (Autoload) — estado global
├── SkillSystem (Autoload) — perfiles de bots
├── BotSignalBus (Autoload) — bus de señales globales
└── PickupManager (Autoload) — gestión de items recogibles (existente)
```

---

## 28. PLAN DE MIGRACIÓN DEFINITIVO

### Fase 0: Auditoría (Completada) ✓
- Mapear todos los escritores de velocity → HECHO
- Mapear todos los escritores de target_enemy → HECHO
- Mapear todos los escritores de weapon → HECHO
- Documento de arquitectura actual → HECHO
- Ingeniería inversa de UT99 → HECHO
- Análisis de modernización → HECHO

### Fase 1: Resources y Data Types (1-2 días)
1. Crear `BotProfile.gd` (Resource) — extraer de npc_base.gd
2. Crear `WeaponAIProfile.gd` (Resource) — nuevo
3. Crear `SemanticPoint.gd` (Resource) — nuevo
4. Crear `MovementCommand.gd` (Resource) — refactorizar desde DecisionContext
5. Crear `CombatCommand.gd` (Resource) — refactorizar desde DecisionContext
6. Crear `Objective.gd` (Resource) — nuevo
7. Crear `BotState.gd` (base class para estados) — nuevo

### Fase 2: MovementSystem (3-5 días)
1. Crear nuevo `MovementSystem.gd` como Nodo independiente
2. MovementSystem es el ÚNICO escritor de velocity
3. MovementSystem recibe MovementCommand (no escribe en NpcBase.velocity directamente)
4. MovementSystem usa NavigationAgent3D nativo
5. StuckDetector es interno a MovementSystem y SOLO emite señales
6. AutoJumper es interno a MovementSystem y SOLO emite señales
7. MovementSystem NO cambia destino por su cuenta
8. MovementSystem NO cambia target_entity por su cuenta

### Fase 3: PerceptionSystem + MemorySystem (2-3 días)
1. Consolidar PerceptionSystem existente (ya está modular)
2. PerceptionSystem SOLO escribe sensor_data (no target_enemy en NpcBase)
3. Consolidar MemorySystem existente (ya está modular)
4. Agregar tipos de memoria faltantes (DAMAGE_SOURCE, OBJECTIVE_PROGRESS)
5. Conectar señales Perception → Memory

### Fase 4: DecisionSystem + FSM (5-7 días)
1. Crear DecisionSystem con StateMachine
2. Implementar BotState base con enter()/execute()/exit()/evaluate_transitions()
3. Implementar estados priorizados (ver tabla 18.2)
4. DecisionSystem es el ÚNICO escritor de:
   - target_entity
   - movement_command
   - combat_command
   - focus_point
5. Implementar TargetEvaluator (AssessThreat modernizado)
6. Implementar CommandValidator

### Fase 5: CombatSystem (3-5 días)
1. Crear nuevo CombatSystem.gd como Nodo independiente
2. CombatSystem es el ÚNICO escritor de aim_rotation
3. CombatSystem NUNCA escribe velocity
4. CombatSystem usa WeaponAIProfile para decisiones de puntería
5. CombatSystem integra dodge_state como SOLICITUD, no escritura directa
6. CombatSystem solo escribe "wants_dodge" en su propia data
7. DecisionSystem decide si concede el dodge (vía movement_command)

### Fase 6: WeaponSystem + WeaponAIProfile (2-3 días)
1. Extraer WeaponAIProfile de Weapon.gd a Resource independiente
2. WeaponSystem expone effective_dps(distance, ammo) para RelativeStrength
3. WeaponSystem expone situational_rating(distance, context) para ChooseAttackMode
4. Integrar refire_rate, lead_target, aim_error en el cálculo de puntería

### Fase 7: ObjectiveSystem + OrderSystem (4-5 días)
1. Implementar team_ai.gd como ObjectiveSystem completo
2. Sistema de órdenes (FreeLance, Attack, Defend, Follow, Hold, Point)
3. Separación RealOrders vs CurrentOrders
4. Jerarquía líder→seguidor
5. FindSpecialAttractionFor() por GameMode
6. GameThreatAdd() por GameMode

### Fase 8: Semantic Navigation (3-4 días)
1. Implementar SemanticPoints como Resources
2. Colocar puntos en mapas existentes (Ambush, Defense, Alternate, Sniper)
3. Integrar con NavigationServer3D para costos dinámicos
4. Sistema de AlternatePath para CTF
5. Sistema de puntos de defensa por equipo y prioridad

### Fase 9: SkillSystem + Dificultad Dinámica (2-3 días)
1. Implementar SkillSystem como Autoload
2. Implementar BotProfile con 32 slots (como UT99)
3. Algoritmo AdjustSkill con persistencia entre partidas
4. InitializeSkill con dificultad base + modificadores

### Fase 10: TeamCoordinator (3-4 días)
1. Asignación dinámica de roles
2. Coordinación de ataques en equipo
3. Solicitud de ayuda entre bots
4. Sistema de liderazgo

### Fase 11: Eliminación de Legacy y Tests (3-5 días)
1. Eliminar NpcBase.brain (reemplazar por DecisionSystem)
2. Eliminar DecisionContext (reemplazar por MovementCommand + CombatCommand)
3. Eliminar behaviors viejos (behavior_*.gd → estados FSM)
4. Eliminar NavigationSystem viejo (reemplazar por nuevo MovementSystem)
5. Eliminar BotBrain (reemplazar por DecisionSystem)
6. Escribir tests de integración para cada sistema

### Fase 12: Pulido y Balance (continuo)
1. Calibrar curvas de amenaza para sensación UT99
2. Calibrar refire_rate, aim_error, strafe por skill
3. Playtesting con diferentes GameModes
4. Ajustar SemanticPoints en mapas para mejor flujo táctico
5. Balance de dificultad dinámica

---

## 29. GLOSARIO

| Término | Significado |
|---------|------------|
| **FSM** | Finite State Machine. Máquina de estados con transiciones explícitas entre estados. |
| **Command** | Resource transitorio que un sistema escribe y otro lee (MovementCommand, CombatCommand). |
| **Signal** | Evento de Godot. Un sistema emite, otro escucha. Comunicación desacoplada. |
| **Data Owner** | Único sistema que puede escribir una variable específica. |
| **SWP** | Single Writer Principle. Principio de que cada variable tiene un solo escritor. |
| **SemanticPoint** | Punto de navegación con significado táctico (emboscada, defensa, ruta alterna). |
| **Objective** | Meta que el GameMode asigna. Los bots solo leen objectives, nunca los escriben. |
| **Order** | Instrucción de equipo (FreeLance, Attack, Defend, Follow, Hold). |
| **RealOrders** | Orden persistente original. El bot puede desviarse temporalmente pero siempre vuelve. |
| **CurrentOrders** | Orden actual (puede cambiar temporalmente). Cuando se completa, se restaura RealOrders. |
| **TacticalRole** | Perfil de comportamiento táctico que define cómo un bot se mueve y pelea. |
| **BotProfile** | Resource con identidad, habilidad y personalidad del bot. |
| **WeaponAIProfile** | Resource con datos de IA para un arma (rating, rango, splash, predicción). |
| **Engagement** | Estado de combate activo contra un enemigo específico. |
| **Tactical Move** | Movimiento evasivo en combate (strafe, retroceso, cobertura). |
| **Strafing** | Movimiento lateral manteniendo el frente hacia el enemigo. |
| **Splash Damage** | Daño por área. Cambia la puntería (apuntar al suelo, no al cuerpo). |
| **Lead Target** | Predecir posición futura del enemigo para acertar con proyectiles. |
| **Refire Rate** | Probabilidad de seguir disparando después de cada disparo (según skill). |
| **LOS** | Line of Sight. Línea de visión sin obstáculos entre dos puntos. |
| **Acquisition** | Estado de transición: el bot acaba de detectar un enemigo. |
| **StakeOut** | Esperar en la última posición conocida del enemigo. |
| **bDevious** | Flag de UT99: el bot usa tácticas engañosas (fintas, rutas falsas). |
| **SpecialHandling** | Hook de navegación de UT99: un nodo intercepta la ruta del bot. |
| **SpecialCost** | Costo dinámico de un nodo de navegación según contexto. |
| **AdjustSkill** | Algoritmo de dificultad dinámica: sube si pierde, baja si gana. |
| **RelativeStrength** | Comparación de poder relativo entre dos entidades (-1 a 1). |
| **AssessThreat** | Evaluación multi-factor de nivel de amenaza de un candidato. |
| **FindSpecialAttraction** | Hook de GameMode: qué debe hacer este bot específicamente. |
| **RateSelf** | Método de arma que devuelve su efectividad en contexto actual. |
| **bLeading** | Flag de UT99: este bot es líder y otros le siguen. |
| **SupportingPlayer** | A qué jugador/bot está apoyando este bot. |

---

## APÉNDICE A: COMPARACIÓN CON SISTEMA ACTUAL

| Sistema Actual (problema) | Sistema Nuevo (solución) |
|--------------------------|-------------------------|
| Múltiples escritores de velocity | MovementSystem es ÚNICO escritor |
| Múltiples escritores de target_enemy | DecisionSystem es ÚNICO escritor |
| NpcBase: 1112 líneas (clase dios) | Sistemas modulares: ~200 líneas c/u |
| NavigationSystem: 1399 líneas | NavigationSystem global (~300 líneas) + MovementSystem (~400 líneas) |
| Behaviors (BotBehavior) escriben velocity | Behaviors/Estados escriben commands, no velocity |
| Sin FSM real (prioridades planas) | FSM con 12 estados, transiciones explícitas, enter/exit |
| Sin perfiles de IA en armas | WeaponAIProfile con rating, splash, lead, refire |
| team_ai.gd vacío (18 líneas) | ObjectiveSystem + OrderSystem + TeamCoordinator completos |
| Sin sistema de órdenes | OrderSystem con RealOrders/CurrentOrders, jerarquía líder |
| Sin ambush/defense points | SemanticPoints: AMBUSH, DEFENSE, ALTERNATE, LIFT, SNIPER |
| DecisionContext como blackboard mixto | MovementCommand + CombatCommand como resources transitorios |
| HealthSystem no existe (salud en NpcBase) | HealthSystem independiente con damage_history |
| PerceptionSystem escribe target_enemy | PerceptionSystem solo escribe sensor_data |
| Sin dificultad dinámica | SkillSystem con AdjustSkill (UT99 exacto) |
| Sin coordinación de equipo | TeamCoordinator con roles, ayuda, liderazgo |

---

> **Este documento constituye la especificación oficial del proyecto.**
> Todo el código futuro debe adherirse a los principios, ownership y flujos aquí definidos.
> Versión: 1.0 | Fecha: 2026-06-30 | Próxima revisión: Al completar Fase 6
