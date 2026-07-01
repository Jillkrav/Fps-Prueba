# ESPECIFICACIÓN OFICIAL — ARQUITECTURA DEFINITIVA DEL SISTEMA DE IA

> **Versión:** 2.0 — Definitiva
> **Fecha:** 2026-06-30
> **Estado:** ESPECIFICACIÓN VINCULANTE
> **Basado en:** Ingeniería inversa de 17 archivos fuente de UT99 + análisis del proyecto actual + modernización de algoritmos para Godot 4.7
>
> **Este documento REEMPLAZA y UNIFICA:**
> - `ARQUITECTURA_IA_UT99_GODOT4.md` (1417 líneas)
> - `UT99_AI_REVERSE_ENGINEERING.md` (1655 líneas)
> - `MODERNIZACION_ALGORITMOS_IA.md` (762 líneas)
> - `ARQUITECTURA_DEFINITIVA.md` (2022 líneas)

---

## ÍNDICE

1. [PRINCIPIOS FUNDAMENTALES](#1-principios-fundamentales)
2. [DIAGRAMA COMPLETO DE MÓDULOS](#2-diagrama-completo-de-módulos)
3. [PERCEPTION SYSTEM](#3-perception-system)
4. [MEMORY SYSTEM](#4-memory-system)
5. [DECISION SYSTEM — FSM](#5-decision-system--fsm)
6. [FSM — ESTADOS COMPLETOS CON ALGORITMOS UT99](#6-fsm--estados-completos-con-algoritmos-ut99)
7. [MOVEMENT SYSTEM](#7-movement-system)
8. [COMBAT SYSTEM](#8-combat-system)
9. [WEAPON SYSTEM](#9-weapon-system)
10. [HEALTH SYSTEM](#10-health-system)
11. [NAVIGATION SYSTEM (GLOBAL)](#11-navigation-system-global)
12. [NAVEGACIÓN SEMÁNTICA](#12-navegación-semántica)
13. [OBJECTIVE SYSTEM — GAMEMODE](#13-objective-system--gamemode)
14. [ORDER SYSTEM](#14-order-system)
15. [TEAM COORDINATOR](#15-team-coordinator)
16. [SKILL SYSTEM](#16-skill-system)
17. [MATRIZ DE DATA OWNERSHIP](#17-matriz-de-data-ownership)
18. [FLUJO DEL FRAME — ORDEN ESTRICTO](#18-flujo-del-frame--orden-estricto)
19. [MAPA COMPLETO DE SEÑALES](#19-mapa-completo-de-señales)
20. [COMANDOS — MOVEMENT Y COMBAT](#20-comandos--movement-y-combat)
21. [PERFILES DE BOT — BOTPROFILE + TACTICALROLE](#21-perfiles-de-bot--botprofile--tacticalrole)
22. [PERFILES DE ARMA — WEAPONAIPROFILE](#22-perfiles-de-arma--weaponaiprofile)
23. [DIFICULTAD DINÁMICA — ADJUSTSKILL](#23-dificultad-dinámica--adjustskill)
24. [PERSONALIDAD Y VOCES](#24-personalidad-y-voces)
25. [INTEGRACIÓN CON GAMEMODES](#25-integración-con-gamemodes)
26. [ESTRUCTURA DE ESCENA — NODE TREE](#26-estructura-de-escena--node-tree)
27. [BUGS DE UT99 Y CÓMO SE EVITAN](#27-bugs-de-ut99-y-cómo-se-evitan)
28. [PLAN DE MIGRACIÓN](#28-plan-de-migración)
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
❌ PerceptionSystem escribe memory_store directamente
❌ NavigationSystem escribe algo en bots
❌ HealthSystem escribe sensor_data
❌ ObjectiveSystem escribe algo en bots (solo emite señales)
❌ Cualquier sistema que no sea MovementSystem escribe velocity
```

### 1.4 Regla de Acoplamiento
- Los sistemas de un bot se comunican por **referencia directa** (hermanos en el árbol)
- Los sistemas globales se comunican por **señales** (Signal Bus)
- Ningún sistema global tiene referencia directa a un sistema interno de bot

### 1.5 Regla de Estado Transitorio
- `MovementCommand` y `CombatCommand` son **recursos transitorios**: se crean cada frame, se consumen y se descartan
- No persisten entre frames. Su estado por defecto es "no hacer nada" (NONE / engage=false)

### 1.6 Regla de Inercia de Objetivo (UT99)
- No cambiar de enemigo sin razón de peso
- Penalización progresiva: cuanto más tiempo has estado comprometido con un enemigo, más difícil cambiarlo
- Excepción: remate — si enemigo actual tiene < 30 HP, la inercia se multiplica ×3
- Excepción: venganza — si el enemigo te acaba de infligir daño (últimos 2s), gana bonus de amenaza

### 1.7 Regla de Señales Diferidas
- Las señales se procesan en el frame SIGUIENTE a su emisión
- Esto evita re-entrancia y garantiza que el estado del sistema sea consistente
- Las señales se acumulan en una cola y se procesan en FASE 6 del frame

### 1.8 Regla de Transición de Estado
- Un estado solo puede transicionar durante su propio `evaluate_transitions()`
- La transición ocurre entre frames, nunca en medio de un `execute()`
- Cada estado tiene `enter()` y `exit()` que se llaman en la transición
- Excepción: TAKING_HIT y FALLING son estados "interruptores" — pueden interrumpir cualquier estado

---

## 2. DIAGRAMA COMPLETO DE MÓDULOS

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                          SISTEMAS GLOBALES (Autoload / Mapa)                          │
│                                                                                       │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌───────────────────────────┐   │
│  │   NavigationSystem   │  │   ObjectiveSystem     │  │       SkillSystem         │   │
│  │   (1 por mapa)       │  │   (GameMode)          │  │   (Autoload)              │   │
│  │                      │  │                       │  │                           │   │
│  │  Prop: navmesh       │  │  Prop: objectives     │  │  Prop: bot_profiles       │   │
│  │  Prop: semantic_pts  │  │  Prop: match_phase    │  │  Prop: match_history      │   │
│  │  Servicio: pathfind  │  │  Prop: scores         │  │  Servicio: get_profile()  │   │
│  │  Servicio: query_pt  │  │  Hijo: OrderSystem    │  │  Servicio: adjust_skill() │   │
│  └─────────┬────────────┘  └─────────┬────────────┘  └───────────┬───────────────┘   │
│            │                         │                            │                    │
│            │                         │                            │ Init de bots        │
│            ▼                         ▼                            ▼                    │
│  ┌──────────────────────────────────────────────────────────────────────────────┐    │
│  │                          TeamCoordinator (en mapa)                            │    │
│  │  Prop: team_composition, role_assignment, squad_formations                   │    │
│  │  Servicio: assign_role(), request_help(), coordinate_attack()                │    │
│  └──────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                       │
└──────────────────────────────────────────────────────────────────────────────────────┘
         │                         │                        │
         │ Señales globales         │ Señales de GameMode    │ Asignación de perfil
         ▼                         ▼                        ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                BOT (CharacterBody3D) — res://scenes/npcs/npc.tscn                      │
│                                                                                       │
│  ┌──────────────────────────────────────────────────────────────────────────────┐    │
│  │                     SISTEMAS INTERNOS DEL BOT (bajo AI/)                       │    │
│  │                                                                               │    │
│  │  ┌─────────────────┐   ┌──────────────┐   ┌──────────────────────────────┐   │    │
│  │  │ PerceptionSystem │──▶│ MemorySystem │──▶│     DecisionSystem (FSM)     │   │    │
│  │  │                 │   │              │   │                              │   │    │
│  │  │ Prop: sensor_   │   │ Prop: memory_│   │  Prop: current_state         │   │    │
│  │  │      data       │   │      store   │   │  Prop: target_entity         │   │    │
│  │  │                 │   │              │   │  Prop: movement_command      │   │    │
│  │  │ Solo ESCRIBE:   │   │ Solo ESCRIBE:│   │  Prop: combat_command        │   │    │
│  │  │ sensor_data     │   │ memory_store │   │  Prop: focus_point           │   │    │
│  │  └─────────────────┘   └──────────────┘   │  Prop: enemy_history[3]      │   │    │
│  │                                           └──────┬───────────┬──────────┘   │    │
│  │                                                  │           │               │    │
│  │                         ┌────────────────────────┘           │               │    │
│  │                         ▼                                    ▼               │    │
│  │  ┌────────────────────────────┐          ┌────────────────────────────┐      │    │
│  │  │      MovementSystem        │          │        CombatSystem        │      │    │
│  │  │                            │          │                            │      │    │
│  │  │  ÚNICO escritor velocity   │          │  ÚNICO escritor aim_rot    │      │    │
│  │  │  Prop: velocity            │          │  Prop: aim_rotation        │      │    │
│  │  │  Prop: navigation_path     │          │  Prop: dodge_state         │      │    │
│  │  │  Prop: stuck_state         │          │  Prop: engagement_data     │      │    │
│  │  │  Prop: movement_mode       │          │  Prop: preferred_fire_mode │      │    │
│  │  │  Hijo: StuckDetector       │          │                            │      │    │
│  │  │  Hijo: AutoJumper          │          │  Lee: combat_command       │      │    │
│  │  │                            │          │  Lee: weapon_status        │      │    │
│  │  │  Lee: movement_command     │          │  Lee: target_entity        │      │    │
│  │  │  Lee: NavigationAgent3D    │          └──────────┬─────────────────┘      │    │
│  │  └────────────────────────────┘                     │                         │    │
│  │                                                     │                         │    │
│  │  ┌────────────────────────────┐          ┌──────────▼─────────────────┐      │    │
│  │  │      HealthSystem          │          │       WeaponSystem         │      │    │
│  │  │                            │          │                            │      │    │
│  │  │  Prop: health             │          │  Prop: weapon_status       │      │    │
│  │  │  Prop: armor              │          │  Prop: ammo_count          │      │    │
│  │  │  Prop: damage_history     │          │  Prop: reserve_ammo        │      │    │
│  │  │  Prop: is_alive           │          │  Prop: reload_state        │      │    │
│  │  │  Prop: last_attacker      │          │  Prop: cooldown_timer      │      │    │
│  │  │  Prop: effective_health   │          │  Prop: ai_profile (R)      │      │    │
│  │  └────────────────────────────┘          └────────────────────────────┘      │    │
│  └──────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                       │
│  ┌──────────────────────────────────────────────────────────────────────────────┐    │
│  │                  DATOS ASOCIADOS (Resources vinculados)                        │    │
│  │                                                                               │    │
│  │  BotProfile (Resource) — asignado por SkillSystem al iniciar                  │    │
│  │  TacticalRole (RefCounted) — asignado por TeamCoordinator según rol           │    │
│  │  WeaponAIProfile (Resource) — cargado desde el arma equipada                  │    │
│  │  TeamIdentifier (Node) — identidad de equipo y rol visual                     │    │
│  └──────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                       │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Resumen de Responsabilidades

| Sistema | Escribe | Lee | NUNCA escribe |
|---------|---------|-----|---------------|
| PerceptionSystem | sensor_data | Posiciones globales, colisiones | velocity, target, commands, memory |
| MemorySystem | memory_store | sensor_data (vía señal) | velocity, target, commands |
| DecisionSystem | target_entity, movement_command, combat_command, focus_point, current_state | sensor_data, memory, objectives, orders, weapon_status, health, stuck_state | velocity, aim_rotation, weapon_status |
| MovementSystem | velocity, navigation_path, stuck_state | movement_command | target_entity, combat_command, aim_rotation |
| CombatSystem | aim_rotation, dodge_state | combat_command, weapon_status, target_entity | velocity, movement_command |
| WeaponSystem | weapon_status, ammo, cooldown | combat_command.fire_request | velocity, target, commands |
| HealthSystem | health, damage_history | — (recibe daño externo) | velocity, target, commands |
| NavigationSystem | navmesh, semantic_points | Geometría del mapa | TODO del bot |
| ObjectiveSystem | objectives, match_phase | Estado global | TODO del bot (solo señales) |
| OrderSystem | orders, leaders | objectives | TODO del bot |
| SkillSystem | bot_profiles, match_history | — | TODO del bot |
| TeamCoordinator | role_assignment | objectives, scores | TODO del bot |

---

## 3. PERCEPTION SYSTEM

### 3.1 Responsabilidad Única
Producir datos sensoriales crudos del mundo. **NO decide qué hacer con ellos.** NO escribe en target_entity, velocity, ni memory_store.

### 3.2 Data Ownership
| Variable | Tipo | Propietario | Lectores |
|----------|------|-------------|----------|
| `sensor_data.visible` | `Array[Sighting]` | PerceptionSystem | DecisionSystem, MemorySystem |
| `sensor_data.heard` | `Array[NoiseEvent]` | PerceptionSystem | DecisionSystem |
| `sensor_data.threats` | `Array[ThreatAssessment]` | PerceptionSystem | DecisionSystem |
| `sensor_data.last_known_positions` | `Dictionary[int, PositionRecord]` | PerceptionSystem | DecisionSystem |

### 3.3 Algoritmo de Visión (UT99 LineOfSightTo modernizado)

```
update(delta):
    1. Obtener overlapping_bodies del Area3D (zona de visión)
    2. Filtrar candidatos:
       - Mismo bot → skip
       - Muertos → skip
       - Mismo equipo (si team game) → skip
       - Invisibles → skip
    3. Para cada candidato:
       a. target_pos = candidate.global_position + Vector3.UP * candidate.eye_height
       b. Configurar RayCast3D desde Head.global_position → target_pos
       c. Verificar LOS:
          - Si colisiona con candidate o su descendiente → VISIBLE
          - Si colisiona con otra geometría → NO VISIBLE
          - Si colisiona con otro CharacterBody → PARCIAL (depende de distancia)
       d. Calcular ángulo: dot(forward, direction_to_target)
       e. Si VISIBLE y dentro del cono de visión:
          - Crear Sighting(entity, position, health, weapon, distance, angle, timestamp, confidence)
    4. Actualizar last_known_positions para entidades visibles
    5. Escribir sensor_data.visible (ordenado por prioridad)
    6. Emitir entity_detected para nuevas entidades
    7. Emitir entity_lost para entidades que ya no son visibles
```

### 3.4 Estructuras de Datos

```
Sighting:
    entity_id: int
    entity: Node3D               # Referencia directa
    position: Vector3
    health: float                # Salud observada (si visible)
    max_health: float
    weapon_type: String          # Arma que sostiene (si visible)
    distance: float              # Distancia euclidiana
    angle: float                 # Ángulo desde el frente
    can_see_me: bool            # ¿Puede él verme a mí?
    timestamp: float
    confidence: float            # 0.0-1.0

NoiseEvent:
    position: Vector3
    source: Node3D
    loudness: float              # 0.0-1.0
    noise_type: String           # "gunshot", "explosion", "footstep", "voice"
    timestamp: float
    confidence: float

PositionRecord:
    position: Vector3
    timestamp: float
    velocity: Vector3            # Velocidad en el momento de la detección
    confidence: float
```

### 3.5 Señales que Emite
| Señal | Cuándo | Datos |
|-------|--------|-------|
| `entity_detected` | Primera vez que ve una entidad | entity_id, position, confidence |
| `entity_lost` | Pierde visión de una entidad | entity_id, last_known_position |
| `threat_assessed` | Nueva evaluación de amenaza | entity_id, threat_level |
| `noise_heard` | Detecta un ruido | position, loudness, source, noise_type |

### 3.6 Lo que NUNCA hace
- NO escribe `target_entity`
- NO escribe `velocity`
- NO escribe `memory_store` directamente (emite señal para MemorySystem)
- NO escribe `movement_command` ni `combat_command`

---

## 4. MEMORY SYSTEM

### 4.1 Responsabilidad Única
Almacenar, consolidar y hacer expirar información a lo largo del tiempo. Transforma una IA reactiva en una IA con memoria persistente.

### 4.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `memory_store: Array[MemoryEntry]` | **MemorySystem** | DecisionSystem (solo query) |
| `_durations: Dictionary[MemoryType, float]` | **MemorySystem** | — (interno) |
| `_position_merge_radius: float` | **MemorySystem** | — (interno) |

### 4.3 Tipos de Memoria (con duraciones UT99-auténticas)

| Tipo | Duración (UT99) | Propósito |
|------|-----------------|-----------|
| `ENEMY_POSITION` | 15s | Última posición conocida de enemigo |
| `GUNSHOT` | 8s | Disparo/explosión escuchado |
| `HEALTH_PACK` | 20s | Botiquín visto en el mapa |
| `WEAPON_ITEM` | 25s | Arma vista en el suelo |
| `ARMOR_ITEM` | 25s | Armadura vista |
| `AMMO_ITEM` | 20s | Munición vista |
| `SUSPICIOUS_NOISE` | 6s | Ruido desconocido |
| `ALLY_POSITION` | 10s | Posición de aliado conocida |
| `DAMAGE_SOURCE` | 10s | Quién me disparó y desde dónde |
| `OBJECTIVE_PROGRESS` | 30s | Progreso hacia objetivo actual |
| `ENEMY_HISTORY` | n/a (pila 3) | Últimos 3 enemigos recientes (no expira) |

### 4.4 MemoryEntry

```
MemoryEntry:
    memory_type: int          # MemoryType enum
    entity_id: int            # Entidad asociada (o -1)
    data: Dictionary          # Payload flexible (posición, estado, etc.)
    position: Vector3         # Posición del evento
    confidence: float         # 0.0-1.0 — decae con el tiempo
    created_at: float         # Timestamp de creación
    last_updated: float       # Timestamp de última actualización
    duration: float           # Duración en segundos desde last_updated
    age: float                # Edad actual (calculada cada frame)
    is_expired: bool          # age > duration
```

### 4.5 API Pública
```
record(type, data, position, confidence)           → Registrar nueva memoria
record_sighting(sighting: Sighting)                → Registrar desde PerceptionSystem
record_damage_source(attacker, position)           → Atajo para DAMAGE_SOURCE
record_enemy_position(enemy, position, velocity)   → Atajo para ENEMY_POSITION

get_most_recent(type) -> MemoryEntry               → Entrada más reciente
get_all_of_type(type) -> Array[MemoryEntry]        → Todas las entradas de un tipo
has_type(type, max_age) -> bool                    → ¿Hay al menos una entrada válida?
get_position(type) -> Vector3                      → Posición de la más reciente
get_all_positions(type) -> Array[Vector3]           → Posiciones de todas (para búsqueda)

has_enemy_memory() -> bool                         → ¿Hay enemigos recordados?
get_last_enemy_position() -> Vector3               → Última posición de enemigo
get_enemy_history() -> Array[EntityRecord]          → Últimos 3 enemigos

query_by_distance(type, from_pos, radius) -> Array → Memorias por cercanía
forget_all()                                       → Limpiar todas las memorias
forget_type(type)                                  → Limpiar un tipo específico
```

### 4.6 Reglas de Merge (UT99-auténticas)
- Si una nueva memoria del mismo tipo está cerca (distancia < 5 unidades) de una existente, se **fusionan**: actualiza timestamp, incrementa confidence (máx 1.0), resetea age
- Si una entidad sigue siendo visible, su ENEMY_POSITION se refresca continuamente (nunca expira mientras sea visible)
- MAX_ENTRIES = 100. Si se excede, se elimina la más vieja (no la de menor confianza — UT99 no jerarquiza por importancia)

### 4.7 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `memory_updated(memory_type, entity_id)` | Una memoria existente se actualizó o fusionó |
| `memory_expired(memory_type, entity_id)` | Una memoria expiró |
| `memory_consolidated(memory_type, entries_count)` | Múltiples memorias se fusionaron en una |

---

## 5. DECISION SYSTEM — FSM

### 5.1 Responsabilidad Única
**Tomar decisiones.** Es el único sistema que decide QUÉ hacer. Traduce percepción + memoria en comandos de movimiento y combate.

### 5.2 Data Ownership
| Variable | Propietario | Lectores | Prohibido escribir |
|----------|-------------|----------|-------------------|
| `current_state: BotState` | **DecisionSystem** | Debug overlay | Todos los demás |
| `target_entity: Node3D` | **DecisionSystem** | CombatSystem, PerceptionSystem | MovementSystem, WeaponSystem |
| `movement_command: MovementCommand` | **DecisionSystem** | MovementSystem | CombatSystem, WeaponSystem |
| `combat_command: CombatCommand` | **DecisionSystem** | CombatSystem | MovementSystem, WeaponSystem |
| `focus_point: Vector3` | **DecisionSystem** | CombatSystem (aim) | MovementSystem |
| `enemy_history: Array[EntityRecord]` | **DecisionSystem** | — (interno) | Todos los demás |
| `objective_priority: Dictionary` | **DecisionSystem** | Debug | Todos los demás |

### 5.3 Entradas (Solo Lectura)
- `sensor_data` (PerceptionSystem) — entidades visibles, ruidos, amenazas
- `memory_store` (MemorySystem) — solo a través de métodos query
- `objectives`, `orders` (ObjectiveSystem) — objetivos y órdenes del GameMode
- `weapon_status`, `ai_profile` (WeaponSystem) — estado del arma, perfil IA
- `health`, `last_damage`, `damage_history` (HealthSystem) — estado de salud
- `stuck_state`, `current_position` (MovementSystem) — estado de movimiento
- `engagement_analysis` (CombatSystem) — análisis de combate actual
- `bot_profile` (SkillSystem) — perfil de habilidad y personalidad

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
│   ├── State_Wandering
│   ├── State_Attacking          # Padre de estados de combate
│   │   ├── State_TacticalMove   # Strafe + disparo evasivo
│   │   ├── State_Charging       # Carga frontal
│   │   ├── State_RangedAttack   # Ataque a distancia
│   │   └── State_Retreating     # Retirada táctica
│   ├── State_Hunting            # Persecución
│   ├── State_StakeOut           # Espera en última posición
│   ├── State_Holding            # Mantener posición
│   ├── State_TakingHit          # Reacción a daño
│   └── State_Falling            # Cayendo
├── TargetEvaluator (Node)
│   └── assess_threat() -> float
├── CommandValidator (Node)
│   ├── validate_movement(cmd) -> bool
│   └── validate_combat(cmd) -> bool
└── ObjectiveEvaluator (Node)
    └── evaluate_objectives() -> Objective
```

### 5.6 Algoritmo SetEnemy (modernizado — corrige bugs UT99)

```
evaluate_target_candidates(candidates: Array[Sighting]) -> EntitySighting:
    1. Filtrar candidatos inválidos:
       - entity_id == self → skip
       - health <= 0 → skip
       - entity == null → skip
       - ya es nuestro target_actual → mantener (inercia)

    2. Si no tenemos target_actual → aceptar el mejor candidato
       - mejor = max(assess_threat(candidate) for candidate in candidates)

    3. Si tenemos target_actual:
       a. Calcular threat_score para cada candidato
       b. Calcular inertia_penalty:
          - commitment_time = Time.get_ticks_msec() - target_acquired_time
          - inertia = commitment_time * INERTIA_PER_SECOND  (default: 0.15/s)
          - Si target_actual.health < 30: inertia *= 3.0 (remate bonus)
          - Si recibió daño de candidato en últimos 2s: threat_score += 0.3 (venganza)
       c. Si max(threat_score(candidates)) > threat_score(target_actual) + inertia:
          - Cambiar: push target_actual a enemy_history[3]
          - target_actual = mejor candidato
          - Actualizar target_acquired_time
       d. Sino: mantener target_actual

    4. Actualizar enemy_history (pila FIFO de 3 slots)
       - UT99 bug fix: NO sobrescribir OldEnemy con candidatos rechazados
       - Solo pushear cuando hay cambio real de enemigo

    5. Emitir target_selected(entity_id) si cambió
```

**Bug de UT99 corregido:** En UT99, `SetEnemy()` sobrescribía `OldEnemy` incluso cuando el nuevo candidato era rechazado. Esto hacía que se perdiera el contexto del enemigo anterior silenciosamente. En esta implementación, `enemy_history` solo se actualiza cuando hay un cambio real de enemigo.

### 5.7 Algoritmo AssessThreat (modernizado — curvas continuas, sin cortes)

```
assess_threat(candidate: Sighting) -> float:
    1. FACTOR 1: RelativeStrength
       threat_base = relative_strength(self, candidate)  # -1.0 a 1.0

    2. FACTOR 2: Distancia (curva continua, sin corte de 800)
       threat_distance = distance_threat_curve.sample(candidate.distance)
       # Curva UT99-auténtica: ~0.3 a dist=800, ~0 a dist=1200
       # Implementada como Curve Resource de Godot

    3. FACTOR 3: Salud del enemigo (curva continua, sin corte de 20)
       threat_health = 1.0 - (candidate.health / candidate.max_health)
       # Enemigo herido = más vulnerable = más atractivo

    4. FACTOR 4: Daño recibido de ese enemigo (venganza)
       threat_damage = damage_from_entity(candidate.entity_id, 3.0)
       # Suma de daño recibido en últimos 3 segundos, normalizado a 0-1

    5. FACTOR 5: Arma del enemigo (DPS estimado)
       threat_weapon = estimate_weapon_threat(candidate.weapon_type, candidate.distance)
       # Usa WeaponAIProfile.effective_dps() del arma del enemigo
       # Rocket Launcher a media distancia = alta amenaza
       # Sniper Rifle a corta distancia = baja amenaza

    6. FACTOR 6: Visibilidad mutua
       threat_visibility = 1.0 if candidate.can_see_me else 0.3
       # Si el enemigo puede verme, es más urgente

    7. FACTOR 7: GameMode modifier
       threat_gamemode = ObjectiveSystem.get_threat_modifier(self, candidate)
       # CTF: +0.5 si lleva la bandera
       # DOM: +0.3 cerca de punto de control
       # AS: +0.4 si está en la fortaleza activa

    8. PESOS POR DEFECTO (UT99-auténticos, configurables)
       return clamp(
           threat_base         * 0.30 +
           threat_distance     * 0.20 +
           threat_health       * 0.10 +
           threat_damage       * 0.15 +
           threat_weapon       * 0.15 +
           threat_visibility   * 0.05 +
           threat_gamemode     * 0.05,
           0.0, 2.0)
```

**Bug de UT99 corregido:** UT99 usaba cortes duros (distancia < 800 → +0.3, salud < 20 → +0.3). Esto causaba diferencias drásticas en bordes (799 vs 801 unidades). Ahora se usan funciones continuas.

**Bug de UT99 corregido:** UT99 promediaba la salud del enemigo con su salud máxima (`0.5 * (health + max_health)`), haciendo que enemigos con 1 HP se vieran como saludables. Ahora se usa la salud real.

### 5.8 Algoritmo RelativeStrength (modernizado — poder efectivo real)

```
relative_strength(self, other) -> float:  # -1.0 a 1.0
    # self_power = salud_efectiva * DPS_arma * skill_modifier
    # other_power = salud_efectiva_enemigo * DPS_arma_enemigo * skill_modifier_enemigo

    1. self_effective_health = self.health + self.armor * 0.6
    2. other_effective_health = other.health + other.armor * 0.6
       # NOTA: usa salud REAL, no promediada (bug UT99 corregido)

    3. self_weapon_dps = WeaponSystem.effective_dps(distance, ammo_ratio, height_delta)
    4. other_weapon_dps = estimate_enemy_dps(other.weapon_type, distance)
       # Estima el DPS del arma visible del enemigo

    5. self_power = self_effective_health * self_weapon_dps * skill_modifier(self.skill)
    6. other_power = other_effective_health * other_weapon_dps * skill_modifier(other.skill)

    7. return clamp(
         (other_power - self_power) / (other_power + self_power + EPSILON),
         -1.0, 1.0)
```

**Bug de UT99 corregido:** UT99 no consideraba armadura, no consideraba munición, y usaba AIRating fijo en lugar de DPS contextual. Ahora se calcula poder efectivo real.

**Bug de UT99 corregido:** UT99 invertía la ventaja de altura (consideraba que estar más bajo era mejor). Ahora se considera correctamente: altura es ventaja, especialmente con splash damage.

### 5.9 Algoritmo ChooseAttackMode (árbol de decisión UT99 exacto, modernizado)

```
choose_attack_mode():
    1. if target_entity == null or target_entity.is_dead():
       → Salir (no hacer nada, dejar que WhatToDoNext decida)

    2. if weapon == null or no_ammo:
       → set_state(FLEE_TO_WEAPON)  # Priorizar conseguir arma
       # Bug fix UT99: verificar que realmente obtuvo un arma

    3. [TeamGame] FindSpecialAttractionFor(self) → si retorna posición:
       → set_state(SPECIAL_ATTRACTION)  # GameMode override
       # Se evalúa UNA SOLA vez (bug fix: UT99 lo evaluaba dos veces)

    4. attitude = get_attitude_towards(target_entity)
       if FEAR → set_state(RETREATING)
       if FRIENDLY → what_to_do_next()

    5. if not has_los(target_entity):
       # Perdió visión → Hunting o StakeOut
       if can_hunt(target_entity):
           # Fórmula UT99: distance > 600 + (FRand * relStr - combatStyle) * 600
           set_state(HUNTING)
       else:
           set_state(STAKEOUT)

    6. if has_los(target_entity):
       # Tiene visión → decidir sub-estado de combate
       if relative_strength(self, target_entity) < -0.5:
           # Enemigo mucho más fuerte → retirada
           set_state(RETREATING)
       elif distance > preferred_range_max:
           # Enemigo lejos → cargar
           set_state(CHARGING)
       elif distance < preferred_range_min and not is_melee:
           # Enemigo muy cerca → retroceder (TacticalMove backpedal)
           set_state(TACTICAL_MOVE)
       else:
           # Distancia óptima → strafe + disparo
           set_state(TACTICAL_MOVE)

    7. Validar transición:
       if not can_enter_state(target_state):
           → permanecer en estado actual y reintentar próximo frame
       # Bug fix UT99: evitar loops infinitos Attacking → ChooseAttackMode → WhatToDoNext
```

**Bug de UT99 corregido:** UT99 tenía un bug donde ChooseAttackMode podía causar loops infinitos (Attacking → ChooseAttackMode → WhatToDoNext → Attacking). Ahora hay validación de precondiciones en cada transición.

**Bug de UT99 corregido:** StakeOut ahora tiene timeout incluso para snipers (UT99 no lo tenía, los snipers se quedaban esperando indefinidamente).

---

## 6. FSM — ESTADOS COMPLETOS CON ALGORITMOS UT99

### 6.1 Jerarquía de Estados

```
StartUp (inicial)
  │
  ├──▶ Roaming (estado por defecto — patrullaje general)
  │       │
  │       ├──▶ Wandering (sin objetivo claro — deambular)
  │       │
  │       ├──▶ Holding (orden HOLD o DEFEND recibida)
  │       │
  │       ├──▶ Attacking (cuando detecta enemigo)
  │       │       │
  │       │       ├──▶ TacticalMove (strafe + fuego evasivo)
  │       │       ├──▶ Charging (carga frontal agresiva)
  │       │       ├──▶ RangedAttack (fuego a distancia estático)
  │       │       └──▶ Retreating (retirada táctica buscando recursos)
  │       │
  │       ├──▶ Hunting (persecución de última posición conocida)
  │       │
  │       ├──▶ StakeOut (espera en última posición conocida)
  │       │
  │       ├──▶ TakingHit (reacción inmediata al recibir daño)
  │       │
  │       └──▶ Falling (cayendo por el aire)
```

### 6.2 Tabla de Estados con Prioridades

| Estado | Prioridad | Propósito | Señales que maneja |
|--------|-----------|-----------|-------------------|
| `TAKING_HIT` | 110 | Reacción inmediata al daño | TakeDamage, SeePlayer, HearNoise |
| `ATTACKING` (padre) | 100 | Combate activo | SeePlayer, HearNoise, TakeDamage, EnemyNotVisible |
| `TACTICAL_MOVE` | 95 | Strafe evasivo + disparo | SeePlayer, TakeDamage, HitWall, Timer, EnemyNotVisible |
| `CHARGING` | 94 | Carga frontal | SeePlayer, TakeDamage, HitWall, EnemyNotVisible |
| `RANGED_ATTACK` | 93 | Ataque a distancia | SeePlayer, TakeDamage, HitWall, EnemyNotVisible |
| `RETREATING` | 90 | Retirada táctica | TakeDamage, SeePlayer, HearNoise, Timer |
| `HUNTING` | 50 | Persecución | SeePlayer, HearNoise, TakeDamage, EnemyNotVisible |
| `STAKEOUT` | 40 | Espera táctica | SeePlayer, TakeDamage, Timer |
| `HOLDING` | 30 | Mantener posición | SeePlayer, TakeDamage, HearNoise (limitado) |
| `ROAMING` | 10 | Patrullaje general | SeePlayer, HearNoise, TakeDamage |
| `FALLING` | 5 | Cayendo | Landed (solo) |
| `WANDERING` | 3 | Deambular sin rumbo | SeePlayer, HearNoise |
| `STARTUP` | 0 | Inicialización | Ninguno |

### 6.3 Matriz de Transiciones Completas

```
Estado Actual        ▶ Puede transicionar a
─────────────────────────────────────────────────────
STARTUP              ▶ ROAMING, HOLDING (si hay órdenes)
ROAMING              ▶ ATTACKING, HUNTING, STAKEOUT, HOLDING, TAKING_HIT, FALLING, RETREATING, WANDERING
WANDERING            ▶ ROAMING, ATTACKING, TAKING_HIT
HOLDING              ▶ ATTACKING, TAKING_HIT, RETREATING, ROAMING (si orden cambia)
ATTACKING (padre)    ▶ TACTICAL_MOVE, CHARGING, RANGED_ATTACK, RETREATING, HUNTING, TAKING_HIT
TACTICAL_MOVE        ▶ RANGED_ATTACK, CHARGING, RETREATING, HUNTING, TAKING_HIT
CHARGING             ▶ TACTICAL_MOVE, RANGED_ATTACK, RETREATING, HUNTING, TAKING_HIT
RANGED_ATTACK        ▶ TACTICAL_MOVE, CHARGING, RETREATING, HUNTING, TAKING_HIT
RETREATING           ▶ ATTACKING (si recupera), ROAMING, TAKING_HIT, HUNTING
HUNTING              ▶ ATTACKING (encuentra), STAKEOUT (llega y no hay), ROAMING (abandona), TAKING_HIT
STAKEOUT             ▶ ATTACKING (enemigo aparece), HUNTING (memoria se actualiza), ROAMING (timeout)
TAKING_HIT           ▶ ATTACKING (enemigo visible), RETREATING (salud baja), ROAMING (todo ok)
FALLING              ▶ ROAMING (aterriza), cualquier estado de combate
```

### 6.4 Estado ROAMING (Patrullaje — WhatToDoNext)

**Propósito:** Estado por defecto. El bot explora el mapa, busca recursos, patrulla.

**Algoritmo WhatToDoNext (UT99 exacto modernizado):**
```
enter():
    1. Detener disparo (cease_fire)
    2. Resetear flags: bDevious = false, bKamikaze = false
    3. Restaurar RealOrders → SetOrders(RealOrders, OrderGiver, true)
       # Esto asegura que el bot vuelva a su misión original
    4. Recuperar OldEnemy de enemy_history → si hay, setear como target
    5. Si target_entity != null → transition(ATTACKING)

execute(delta):
    1. Buscar objetivos (en orden de prioridad):
       a. ¿Hay enemigo visible? → transition(ATTACKING)
       b. ¿Escuché un ruido? → transition(HUNTING) (investigar)
       c. [TeamGame] ¿Hay atracción especial? → seguir atracción
       d. ¿Hay items cercanos (pickups)? → ir al mejor
       e. ¿Hay SemanticPoints (patrulla)? → ir al más cercano no visitado
       f. Sin nada → movimiento aleatorio (exploración)

    2. movement_command: mode=NAVIGATE, target=destino elegido
    3. combat_command: engage=false

evaluate_transitions():
    1. if taking_damage → transition(TAKING_HIT)
    2. if visible_enemy and should_engage → transition(ATTACKING)
    3. if heard_noise and not in_combat → transition(HUNTING)
    4. if orders_changed → evaluar nueva orden
    5. if is_falling → transition(FALLING)
```

### 6.5 Estado TACTICAL_MOVE (Movimiento Táctico — Strafe + Fuego)

**Propósito:** Combate evasivo. El bot strafea, usa cobertura, dispara. Es el estado de combate por defecto.

**Algoritmo TacticalMove (UT99 exacto modernizado):**

```
enter():
    1. Guardar posición inicial (para RecoverEnemy)
    2. Elegir dirección de strafe:
       bStrafeDir = alternar (toggle de UT99)
       # Alterna entre izquierda y derecha cada vez que entra

execute(delta):
    1. CombatCommand: engage=true, fire_mode=primario
    2. MovementCommand: mode=DIRECT
       a. Calcular strafe vector (fórmula UT99 exacta):
          enemyDir = (target_entity.position - self.position).normalized()
          strafeDir = perpendicular(enemyDir) * (1 if bStrafeDir else -1)
          aggressionFactor = 2 * (combat_style + randf()) - 1.1  # Fórmula UT99
          moveDir = lerp(enemyDir, strafeDir, aggressionFactor)
       b. movement_command.direction = moveDir
       c. movement_command.speed = combat_speed * speed_multiplier
       d. movement_command.face_target = target_entity

    3. RecoverEnemy (asomarse y disparar — joya de UT99):
       if has_los(target_entity):
           # Disparar mientras se tiene línea de visión
           combat_command.engage = true
           # Timer para decidir cuándo pasar a RangedAttack
           # UT99: FRand() > 0.5 + 0.17 * skill → RangedAttack
       else:
           # Sin LOS → moverse para recuperar
           combat_command.engage = false
           target = last_known_position
           # RecoverEnemy: ir a LastSeeingPos, disparo rápido, volver
           if recover_phase == PEEK:
               movement_command.target = last_seeing_position
           elif recover_phase == FIRE:
               combat_command.engage = true
               combat_command.force_fire = true  # quickFire
           elif recover_phase == RETREAT:
               movement_command.target = hiding_spot

    4. Strafing adaptativo por arma enemiga (mejora moderna):
       if enemy_weapon == ROCKET_LAUNCHER:
           strafe_change_interval *= 0.5  # cambiar dirección más seguido
           add_random_jitter()  # movimiento impredecible
       elif enemy_weapon == SNIPER:
           strafe_change_interval *= 2.0  # strafe más predecible
           prioritize_vertical_movement()  # saltos

evaluate_transitions():
    1. if !has_los(target) for > GIVE_UP_TACTICAL_TIME:
       → transition(HUNTING)  # GiveUpTactical de UT99
    2. if enemy_health <= 0 → transition(ROAMING)
    3. if relative_strength < -0.5 → transition(RETREATING)
    4. if distance < melee_range and is_melee → transition(CHARGING)
    5. if distance > preferred_range_max and can_close_gap:
       → transition(CHARGING)
    6. if no_strafe_progress for 8 seconds (no damage dealt, no distance change):
       → transition(HUNTING)  # Flanquear
    7. if is_falling → transition(FALLING)
    8. if taking_damage → transition(TAKING_HIT)  # Si actitud lo permite
```

### 6.6 Estado CHARGING (Carga)

**Propósito:** Cerrar distancia agresivamente hacia el enemigo.

```
enter():
    1. movement_mode = AGGRESSIVE
    2. sprint = true (si aplica)

execute(delta):
    1. CombatCommand: engage=true (disparar mientras carga)
    2. MovementCommand: mode=NAVIGATE, target=enemy.position
    3. movement_command.sprint = true
    4. movement_command.speed = max_speed * aggressiveness_multiplier

evaluate_transitions():
    1. if relative_strength < -0.5 → transition(RETREATING)
    2. if distance < tactical_move_threshold → transition(TACTICAL_MOVE)
    3. if enemy_health <= 0 → transition(ROAMING)
    4. if !has_los(target) → transition(HUNTING)
    5. if is_falling → transition(FALLING)
```

### 6.7 Estado RANGED_ATTACK (Ataque a Distancia)

**Propósito:** Disparar desde posición estática o semiestática.

```
execute(delta):
    1. CombatCommand: engage=true, fire_mode=primario o alterno
    2. MovementCommand: mode=STOP o mode=DIRECT con strafe mínimo
    3. focus_point = target_entity.position
    4. No hay movimiento significativo — el bot mantiene posición

evaluate_transitions():
    1. if distance < preferred_range_min → transition(TACTICAL_MOVE) (backpedal)
    2. if has_los(target) == false → transition(HUNTING)
    3. if enemy_health <= 0 → transition(ROAMING)
    4. if relative_strength < -0.5 → transition(RETREATING)
    5. if taking_damage consecutively → transition(TACTICAL_MOVE)
```

### 6.8 Estado RETREATING (Retirada Táctica — UT99 exacto)

**Propósito:** Retirada NO es huida de pánico. El bot se retira buscando recursos mientras mantiene conciencia del enemigo.

**Algoritmo Retreating (UT99 exacto modernizado):**

```
enter():
    1. fear_timer = 12.0 (8.0 en team games) — UT99 exacto
    2. Buscar mejor ruta de retirada con pickups

execute(delta):
    1. CombatCommand: engage=false (NO disparar mientras se retira)
       # Excepción: si tiene splash damage, disparar hacia atrás (disuasión)
       if weapon_profile.splash_damage:
           combat_command.engage = true
           combat_command.aim_at_position = enemy.position  # disparo de cobertura

    2. MovementCommand: mode=NAVIGATE
       target = mejor punto de retirada (RetreatPlanner)
       # RetreatPlanner calcula:
       #   a. Punto de retirada final (base, compañero, choke)
       #   b. Waypoints intermedios con pickups
       #   c. Puntos de cobertura intermedios
       #   d. Priorizar hemisferio OPUESTO al enemigo (bug fix UT99)

    3. Búsqueda de inventario durante retirada:
       radio = min(500 + skill * 70, distance_to_enemy * 0.8)
       # Bug fix: radio basado en distancia al enemigo, no fijo
       # Bug fix: solo pickups en dirección OPUESTA al enemigo

evaluate_transitions():
    1. if fear_timer <= 0 (12s sin ver enemigo):
       → transition(ATTACKING)  # Ya no le teme
       # Bug fix: el timer NO se resetea completamente con sightings
       # Cada sighting extiende el timer 2s adicionales, máx 20s
    2. if relative_strength > 0.3 (ahora soy más fuerte):
       → transition(ATTACKING)
    3. if health > 70 and has_weapon:
       → transition(ATTACKING)  # Se recuperó
    4. if no_health_packs_reachable:
       → bKamikaze = true → transition(TACTICAL_MOVE)  # Rendirse y pelear
       # Bug fix: verificar reachabilidad real con NavigationServer3D
```

### 6.9 Estado HUNTING (Persecución — UT99 exacto)

**Propósito:** Perseguir la última posición conocida del enemigo.

**Algoritmo Hunting (UT99 exacto modernizado):**

```
enter():
    1. hunt_timer = 26 - num_players - num_bots  # UT99 exacto
       # Más jugadores = menos tiempo buscando
    2. num_hunt_attempts = 0

execute(delta):
    1. CombatCommand: engage=false (no hay enemigo visible)
    2. MovementCommand: mode=NAVIGATE
       target = memory.get_last_enemy_position()
       # Con predicción de movimiento:
       #   estimated_pos = last_position + last_velocity * time_elapsed
       #   target = navigation_point más cercano a estimated_pos

    3. BlockedPath logic (UT99 bDevious — flanqueo):
       if path_to_target_is_blocked:
           bDevious = true (con probabilidad UT99: 0.52 - 0.12 * num_bots)
           buscar ruta alternativa

    4. FindViewSpot (UT99 — intentar recuperar LOS lateralmente):
       if not has_los_from_current_position:
           # Probar izquierda y derecha (bug fix UT99: original solo probaba una)
           try move lateral 2.5 * collision_radius
           if not has_los → try opposite direction

evaluate_transitions():
    1. if has_los(enemy) → transition(ATTACKING)
    2. if hunt_timer <= 0 → transition(ROAMING)  # Abandonar búsqueda
    3. if num_hunt_attempts > 60 → transition(ROAMING)  # Límite absoluto
    4. if can_stakeout() → transition(STAKEOUT)
       # CanStakeOut: enemy y bot pueden ver la última posición
    5. if heard_noise_closer → actualizar hunt_target
    6. if memory.has_type(DAMAGE_SOURCE) and not same_as_hunt_target:
       → actualizar hunt_target al DAMAGE_SOURCE (venganza)
    7. if is_falling → transition(FALLING)
```

**Bug de UT99 corregido:** En UT99, numHuntPaths se incrementaba por cada intento de pathfinding, no por tiempo. En mapas pequeños donde el bot podía ver a través de zonas, el contador se disparaba y abandonaba prematuramente. Ahora se usa tiempo real + intentos.

**Bug de UT99 corregido:** FindViewSpot en UT99 solo probaba una dirección (ambas ramas del if hacían lo mismo). Ahora prueba izquierda y derecha realmente.

### 6.10 Estado STAKEOUT (Emboscada — UT99 exacto)

**Propósito:** Esperar en la última posición conocida del enemigo.

**Algoritmo StakeOut (UT99 exacto modernizado):**

```
enter():
    1. evaluate_timer.start(1.0 + randf())  # UT99: Sleep(1 + FRand())
       # Pero el timer no bloquea — el bot sigue responsive
    2. look_timer.start(0.5 + randf())  # Cambiar dirección de mirada

execute(delta):
    1. CombatCommand: engage=false (esperando)
       # Excepción: si has_clear_shot → engage=true
       if has_clear_shot:
           combat_command.engage = true
           combat_command.fire_mode = preferido

    2. MovementCommand: mode=STOP
       # Quieto, apuntando hacia LastSeenPos
    3. focus_point = memory.get_last_enemy_position()

    4. Rotación de mirada (mejora moderna):
       if look_timer.timeout:
           # Barrer el área con cono de visión
           look_direction = rotate_towards_next_observation_point()
           # Más humano que mirar fijo a un punto

evaluate_transitions():
    1. if has_los(enemy) → transition(ATTACKING)
    2. if continue_stakeout() == false:
       # ContinueStakeOut (UT99 exacto):
       #   a. Si distancia > 300 + (relStr - combatStyle) * 350 → salir
       #   b. Si LastSeenTime > 2.5 + FMax(-1, 3*(FRand + 2*(relStr - combatStyle))) → salir
       #   c. Si !has_clear_shot por mucho tiempo → salir
       #   d. Si hay mejor cosa que hacer (pickup, orden) → salir
       → transition(HUNTING) o transition(ROAMING)
    3. if heard_noise → transition(HUNTING) (investigar)
    4. if is_falling → transition(FALLING)
```

**Bug de UT99 corregido:** UT99 usaba `Sleep(1 + FRand())` que bloqueaba el bot completamente (no respondía a daño ni estímulos durante el sueño). Ahora se usa Timer que no bloquea.

**Bug de UT99 corregido:** StakeOut para snipers no tenía timeout en UT99. Ahora tiene timeout global incluso para snipers.

### 6.11 Estado TAKING_HIT (Reacción a Daño)

**Propósito:** Reacción inmediata al recibir daño. Estado interrumptor con prioridad 110.

```
enter():
    1. Determinar dirección del daño (desde last_attacker.position)
    2. Si last_attacker es visible → transition(ATTACKING) inmediato
    3. Si no → girar hacia la dirección del daño
    4. take_hit_timer = 0.3 + randf() * 0.2  # 0.3-0.5 segundos de reacción

execute(delta):
    1. CombatCommand: engage=false (reacción, no acción)
    2. MovementCommand: mode=STOP o mode=DIRECT con pequeño dodge

evaluate_transitions():
    1. if take_hit_timer <= 0 → transition basado en contexto:
       - Si enemigo visible → ATTACKING
       - Si salud < 30 → RETREATING
       - Sino → ROAMING
    2. if !is_alive → transition a nada (morir)
```

---

## 7. MOVEMENT SYSTEM

### 7.1 Responsabilidad Única
**Ejecutar movimiento.** Traduce MovementCommand en velocity. Es el **ÚNICO** sistema que escribe velocity. También el único que escribe stuck_state y navigation_path.

### 7.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `velocity: Vector3` | **MovementSystem** | Physics engine (move_and_slide) |
| `navigation_path: Array[Vector3]` | **MovementSystem** | Debug overlay |
| `stuck_state: StuckState` | **MovementSystem** | DecisionSystem (solo lectura) |
| `current_speed: float` | **MovementSystem** | DecisionSystem |
| `movement_mode: MovementMode` | **MovementSystem** | DecisionSystem, Debug |

### 7.3 Modos de Movimiento
| Modo | Descripción | Cuándo se usa |
|------|-------------|---------------|
| `NONE` | Sin movimiento | Holding, StakeOut, TakingHit |
| `NAVIGATE` | Pathfinding hacia destino | Roaming, Hunting, Charging, Retreating |
| `DIRECT` | Vector directo (sin pathfinding) | TacticalMove (strafe), dodge |
| `DODGE` | Impulso con salto lateral | Evasión en combate (solicitado por CombatSystem) |
| `STOP` | Frenado intencional | Holding, RangedAttack |

### 7.4 Algoritmo Principal

```
process(delta):
    1. cmd = decision_system.movement_command
    2. if cmd.mode == NONE:
         desired_velocity = velocity.move_toward(Vector3.ZERO, BRAKING * delta)
         # Frenar gradualmente
    3. else:
         match cmd.mode:
           NAVIGATE:
             agent.target_position = cmd.target_position
             if agent.is_navigation_finished():
                 emit("destination_reached")
                 # No detenerse — dejar que DecisionSystem decida
                 desired_velocity = Vector3.ZERO
             else:
                 next_pos = agent.get_next_path_position()
                 direction = (next_pos - global_position).normalized()
                 desired_velocity = direction * cmd.speed

           DIRECT:
             direction = cmd.direction.normalized()
             desired_velocity = direction * cmd.speed
             # face_target se maneja externamente (CombatSystem ajusta rotación)

           DODGE:
             desired_velocity = cmd.direction * cmd.dodge_impulse
             if cmd.jump:
                 velocity.y = cmd.jump_velocity
             # DODGE overridea cualquier otra velocidad este frame

           STOP:
             desired_velocity = velocity.move_toward(Vector3.ZERO, BRAKING * delta)

    4. # Aplicar evitación entre NPCs (solo si mode != DODGE)
       if cmd.mode != DODGE:
           desired_velocity = apply_npc_avoidance(desired_velocity, delta)

    5. # Aplicar gravedad (MovementSystem es el ÚNICO que toca gravedad)
       if not is_on_floor():
           velocity.y -= GRAVITY * delta
       elif cmd.jump:
           velocity.y = cmd.jump_velocity

    6. # ESCRIBIR velocity (único lugar en todo el bot)
       velocity = desired_velocity

    7. # Verificar stuck (solo emite señales)
       check_stuck(delta)
```

### 7.5 Stuck Detection (Solo Emite Señales — Nunca Cambia Destino)

```
check_stuck(delta):
    1. if mode == NONE or mode == STOP → return (no verificar si está quieto)
    2. if stuck_suppressed → return (suprimido por combate)

    3. MÉTRICA 1: Progreso hacia objetivo
       if moving_towards_target():
           progress = distance_to_target_last_frame - distance_to_target_this_frame
           if progress < STUCK_PROGRESS_THRESHOLD for STUCK_TIME_THRESHOLD (1.5s):
               stuck_phase = PHASE_1  # Atascado leve

    4. MÉTRICA 2: Inmovilidad absoluta
       if global_position.distance_to(last_frame_position) < STUCK_IMMOBILE_THRESHOLD:
           if stuck_immobile_time > STUCK_IMMOBILE_TIME (1.0s):
               stuck_phase = PHASE_2  # Atascado severo

    5. MÉTRICA 3: Oscilación
       ratio = total_distance_traveled / net_displacement
       if ratio > OSCILLATION_RATIO (3.5):
           stuck_phase = PHASE_3  # Atascado por oscilación

    6. MÉTRICA 4: Bloqueo por otro bot
       if collision_state.blocked_by_character for > BLOCKED_BY_BOT_TIME (1.5s):
           stuck_phase = PHASE_4  # Bloqueado por otro CharacterBody

    7. if stuck_phase > current_stuck_state.phase:
         emit("stuck_detected", stuck_phase, cause)
         # MovementSystem NO cambia destino — solo informa

    8. if stuck_phase == 0 and current_stuck_state.phase > 0:
         emit("stuck_resolved")
```

### 7.6 Evitación entre NPCs

```
apply_npc_avoidance(desired, delta) -> Vector3:
    for other_bot in get_nearby_bots(AVOIDANCE_RADIUS):
        offset = global_position - other_bot.global_position
        distance = offset.length()
        if distance < AVOIDANCE_RADIUS and distance > 0.01:
            strength = AVOIDANCE_FORCE * (1.0 - distance / AVOIDANCE_RADIUS)
            separation = offset.normalized() * strength
            # Mezcla lateral: mantener avance, agregar separación
            forward = desired.normalized()
            lateral = separation - forward * forward.dot(separation)
            desired += lateral * AVOIDANCE_LATERAL_BLEND
    # Garantizar velocidad mínima hacia adelante
    if desired.length() > 0:
        forward_component = desired.normalized().dot(original_direction)
        if forward_component < AVOIDANCE_MIN_FORWARD:
            desired = desired.normalized() * AVOIDANCE_MIN_FORWARD * AVOIDANCE_SPEED
    return desired
```

### 7.7 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `destination_reached(pos)` | Llegó al destino NAVIGATE |
| `path_blocked(dist)` | Ruta bloqueada (NavigationAgent sin ruta) |
| `stuck_detected(phase, cause)` | Atasco detectado (NUNCA cambia destino) |
| `stuck_resolved()` | Atasco se resolvió solo |
| `movement_interrupted(cause)` | Movimiento interrumpido externamente |

---

## 8. COMBAT SYSTEM

### 8.1 Responsabilidad Única
Manejar combate: puntería, modo de fuego, evasión. **NUNCA escribe velocity.** Es el **ÚNICO** que escribe aim_rotation.

### 8.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `aim_rotation: Quaternion` | **CombatSystem** | Modelo/Arma (visual) |
| `preferred_fire_mode: int` | **CombatSystem** | WeaponSystem |
| `dodge_state: DodgeState` | **CombatSystem** | DecisionSystem (solo lectura) |
| `current_target_position: Vector3` | **CombatSystem** | WeaponSystem |
| `engagement_analysis: EngagementData` | **CombatSystem** | DecisionSystem |

### 8.3 Algoritmo AdjustAim (UT99 exacto modernizado)

```
adjust_aim(target_entity, weapon_profile) -> Quaternion:
    1. target_pos = target_entity.global_position + Vector3.UP * 1.2
       # Apuntar al centro del torso

    2. PREDICCIÓN (lead_target):
       if weapon_profile.lead_target and weapon_profile.projectile_speed > 0:
           target_velocity = target_entity.velocity
           distance = global_position.distance_to(target_pos)
           travel_time = distance / weapon_profile.projectile_speed
           target_pos += target_velocity * travel_time
           # Esto compensa el movimiento del enemigo

    3. ERROR DE PUNTERÍA (UT99 AdjustAim):
       aim_error = weapon_profile.aim_error_base
       aim_error *= skill_aim_error_multiplier(skill)  # 3.0 (novice) a 0.5 (elite)
       aim_error *= distance_aim_error_multiplier(distance)  # más error a más distancia
       # Añadir误差 aleatorio (diferente cada frame pero suave)
       target_pos += Vector3(
           randf_range(-aim_error, aim_error) * 0.01,
           randf_range(-aim_error, aim_error) * 0.01,
           0)

    4. SPLASH DAMAGE:
       if weapon_profile.splash_damage and distance < weapon_profile.splash_radius * 2:
           # Apuntar al suelo (más efectivo para splash)
           target_pos = target_entity.global_position + Vector3.DOWN * 0.5
           # Para splash, el error vertical es menor (queremos dar al suelo)

    5. return global_transform.looking_at(target_pos).basis.get_rotation_quaternion()
```

### 8.4 Algoritmo ShouldFire (Decisión de Disparo)

```
should_fire(combat_command, weapon_status) -> bool:
    1. if not combat_command.engage → false
    2. if weapon_status.is_reloading → false
    3. if weapon_status.ammo <= 0:
         emit("out_of_ammo", weapon_type)
         → false
    4. if not has_los(target_entity) → false
    5. if not is_aim_settled() → false  # No disparar mientras se ajusta puntería

    6. REFIRE RATE (UT99 exacto):
       if just_fired:
           # UT99: probabilidad de disparar de nuevo inmediatamente
           # Depende del arma y del skill del bot
           if randf() > weapon_profile.refire_rate:
               # Pausa entre disparos (comportamiento humano)
               → false
           # Bots hábiles tienen refire_rate más alto
           # Bots novatos pausan más seguido

    7. return true
```

### 8.5 Dodge State

```
DodgeState:
    wants_dodge: bool          # CombatSystem SOLICITA un dodge
    dodge_direction: Vector3   # Dirección solicitada
    dodge_impulse: float       # Fuerza del dodge
    jump_if_possible: bool     # ¿Saltar durante el dodge?

# CombatSystem SOLO escribe wants_dodge en su propia data
# DecisionSystem decide si CONCEDE el dodge (vía movement_command)
# MovementSystem ejecuta el dodge (vía mode=DODGE)

# ¿Cuándo solicita dodge?
# 1. Proyectil enemigo acercándose (detectado por raycast o听觉)
# 2. Daño recibido recientemente (dodge evasivo)
# 3. Strafing con cambio brusco de dirección
```

### 8.6 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `weapon_fired(hit_results)` | El arma disparó (resultados del hit) |
| `target_in_range(entity_id, dist)` | Enemigo entró en rango óptimo |
| `target_lost(entity_id)` | Enemigo perdió LOS o salió de rango |
| `out_of_ammo(weapon_type)` | Sin munición (consume la señal de WeaponSystem) |
| `dodge_performed(direction)` | Dodge ejecutado |
| `aim_updated(new_rotation)` | La puntería cambió significativamente |

---

## 9. WEAPON SYSTEM

### 9.1 Responsabilidad Única
Gestionar estado del arma: cadencia, munición, recarga, perfil de IA.

### 9.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `weapon_status: WeaponStatus` | **WeaponSystem** | CombatSystem, DecisionSystem |
| `ammo_count: int` | **WeaponSystem** | DecisionSystem |
| `reserve_ammo: int` | **WeaponSystem** | DecisionSystem |
| `cooldown_timer: float` | **WeaponSystem** | — (interno) |
| `reload_state: ReloadState` | **WeaponSystem** | CombatSystem |
| `ai_profile: WeaponAIProfile` | **WeaponSystem** (Resource) | CombatSystem, DecisionSystem |

### 9.3 API para IA

```
effective_dps(distance: float, ammo_ratio: float, height_delta: float) -> float:
    # Calcula daño por segundo efectivo en contexto actual
    base = ai_profile.base_dps
    range_factor = optimal_range_curve(distance)  # 0.0 fuera de rango, 1.0 en rango óptimo
    ammo_factor = 1.0 if ammo_ratio > 0.2 else ammo_ratio * 5.0  # penalizar si poca munición
    height_factor = 1.0 + height_delta * ai_profile.height_advantage * 0.1
    return base * range_factor * ammo_factor * height_factor

situational_rating(distance: float, context: BotContext) -> float:
    # Rating contextual (0.0-1.0) para SwitchToBestWeapon
    base = ai_profile.ai_rating
    range_rating = optimal_range_curve(distance)
    if context.is_indoor and ai_profile.splash_damage:
        range_rating *= 1.3  # Splash es mejor en espacios cerrados
    if context.is_outdoor and ai_profile.is_instant_hit:
        range_rating *= 1.2  # Hitscan es mejor en espacios abiertos
    return base * range_rating

get_recommended_fire_mode(distance: float, target_info: TargetInfo) -> int:
    # 0 = primario, 1 = alterno
    if ai_profile.prefers_alt_fire:
        return 1
    if ai_profile.splash_damage and distance < ai_profile.splash_radius * 3:
        return 1  # Modo alterno para splash cercano
    return 0  # Modo primario por defecto
```

### 9.4 WeaponAIProfile (Resource)

```
WeaponAIProfile:
    # Rating
    ai_rating: float                    # 0.0-1.0 poder general del arma

    # Distancia
    preferred_range_min: float          # Distancia óptima mínima
    preferred_range_max: float          # Distancia óptima máxima

    # Splash
    splash_damage: bool                 # ¿Daño por área?
    splash_radius: float                # Radio de splash

    # Predicción
    lead_target: bool                   # ¿Predecir posición del enemigo?
    projectile_speed: float             # Velocidad del proyectil

    # Cadencia
    refire_rate: float                  # 0.0-1.0 probabilidad de seguir disparando
    base_dps: float                     # Daño por segundo base

    # Puntería
    aim_error_base: int                 # Error base en unidades (2000 default)
    is_instant_hit: bool                # ¿Hitscan?
    is_melee: bool                      # ¿Cuerpo a cuerpo?
    optimal_range_falloff: float        # Caída de efectividad fuera de rango

    # Estilo
    attack_style_modifier: float        # -1.0 a 1.0 (modifica combat_style del bot)
    defense_style_modifier: float       # -1.0 a 1.0
    prefers_alt_fire: bool              # ¿Usa modo alterno por defecto?
    height_advantage: float             # -1 mejor desde abajo, +1 mejor desde arriba
```

### 9.5 Tabla de Ratings por Arma (Ejemplo)

| Arma | Rating | Rango Pref | Splash | Lead | Refire | error_base |
|------|--------|------------|--------|------|--------|-----------|
| USP Pistol | 0.3 | 2-15 | no | no | 0.6 | 2000 |
| Shotgun | 0.5 | 2-10 | no | no | 0.7 | 2500 |
| Rifle | 0.7 | 15-50 | no | sí | 0.5 | 1000 |
| Rocket Launcher | 0.8 | 5-25 | sí | sí | 0.3 | 1500 |
| Minigun | 0.6 | 5-30 | no | sí | 0.9 | 1800 |
| Sniper Rifle | 0.9 | 30-80 | no | sí | 0.2 | 500 |

### 9.6 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `weapon_ready()` | Arma lista para disparar (cooldown terminado) |
| `weapon_empty()` | Cargador vacío |
| `reload_started(duration)` | Inicio de recarga |
| `reload_completed()` | Recarga terminada |
| `ammo_changed(current, reserve)` | Cambio en munición |

---

## 10. HEALTH SYSTEM

### 10.1 Responsabilidad Única
Gestionar salud, armadura, daño, muerte.

### 10.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `health: float` | **HealthSystem** | DecisionSystem, UISystem |
| `max_health: float` | **HealthSystem** | DecisionSystem |
| `armor: float` | **HealthSystem** | DecisionSystem |
| `damage_history: Array[DamageEvent]` | **HealthSystem** | DecisionSystem |
| `is_alive: bool` | **HealthSystem** | Todos |
| `last_damage_time: float` | **HealthSystem** | DecisionSystem |
| `last_attacker: Node3D` | **HealthSystem** | DecisionSystem |
| `effective_health: float` | **HealthSystem** (calculated) | DecisionSystem (para RelativeStrength) |

### 10.3 DamageEvent
```
DamageEvent:
    amount: float
    attacker: Node3D
    damage_type: String     # "bullet", "explosion", "melee", "lava", etc.
    position: Vector3       # Posición del atacante en el momento del daño
    timestamp: float        # Time.get_ticks_msec() / 1000.0
    armor_absorbed: float   # Cuánto absorbió la armadura
    is_headshot: bool       # ¿Golpe crítico?
```

### 10.4 API

```
apply_damage(amount, attacker, damage_type, hit_position) -> void:
    1. damage_after_armor = max(amount - armor * ARMOR_ABSORPTION_RATE, amount * MIN_DAMAGE_THROUGH_ARMOR)
    2. armor = max(armor - amount * ARMOR_DAMAGE_RATE, 0)
    3. health -= damage_after_armor
    4. Registrar DamageEvent en damage_history
    5. last_attacker = attacker
    6. last_damage_time = Time.get_ticks_msec() / 1000.0
    7. emit("damage_taken", damage_after_armor, attacker, damage_type)
    8. emit("health_changed", health)
    9. if health <= 0: die(attacker)

die(killer) -> void:
    is_alive = false
    emit("death", killer)

heal(amount, source) -> void:
    health = min(health + amount, max_health)
    emit("heal_received", amount, source)
    emit("health_changed", health)

get_effective_health() -> float:
    return health + armor * ARMOR_ABSORPTION_RATE  # 0.6 default

get_damage_from_entity(entity_id, time_window) -> float:
    # Suma de daño recibido de entity_id en últimos time_window segundos
    return sum(d.amount for d in damage_history
               if d.attacker.get_instance_id() == entity_id
               and d.timestamp > Time.get_ticks_msec()/1000 - time_window)
```

### 10.5 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `damage_taken(amount, attacker, type)` | Recibió daño |
| `health_changed(new_health)` | Salud cambió |
| `death(attacker)` | Murió |
| `armor_depleted()` | Armadura se agotó |
| `heal_received(amount, source)` | Recibió curación |

---

## 11. NAVIGATION SYSTEM (GLOBAL)

### 11.1 Responsabilidad Única
Gestionar el grafo de navegación del mapa y los puntos semánticos. **NO decide rutas. NO mueve bots. NO detecta stuck.**

### 11.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `navigation_mesh: NavigationMesh` | **NavigationSystem** | NavigationServer3D |
| `semantic_points: Array[SemanticPoint]` | **NavigationSystem** | DecisionSystem (vía query) |
| `navigation_region: NavigationRegion3D` | **NavigationSystem** | NavigationServer3D |

### 11.3 API Pública (Solo Servicio)
```
# Rutas
get_path(from: Vector3, to: Vector3) -> Array[Vector3]
get_path_with_cost(from: Vector3, to: Vector3, cost_function: Callable) -> Array[Vector3]

# Puntos semánticos
get_semantic_points(type: SemanticPointType, team: int, tags: Array[String]) -> Array[SemanticPoint]
get_nearest_semantic_point(pos: Vector3, type: SemanticPointType, team: int) -> SemanticPoint
get_ambush_points(team: int) -> Array[SemanticPoint]
get_defense_points(objective_id: String, team: int) -> Array[SemanticPoint]
get_alternate_paths(team: int) -> Array[SemanticPoint]
get_sniper_points(min_skill: int) -> Array[SemanticPoint]
get_lift_points() -> Array[SemanticPoint]  # LiftCenter + LiftExit

# Query
has_semantic_point_near(pos: Vector3, type: SemanticPointType, radius: float) -> bool
get_nearest_navigation_point(pos: Vector3) -> Vector3
get_random_navigation_point() -> Vector3

# Costos dinámicos
get_adjusted_cost(semantic_point: SemanticPoint, bot_context: BotContext) -> float
set_dynamic_cost(semantic_point_id: int, extra_cost: float, duration: float)
```

### 11.4 Lo que NUNCA hace
- NO escribe `velocity` de ningún bot
- NO escribe `target_entity` de ningún bot
- NO cambia destinos de navegación de bots
- NO detecta stuck (eso es MovementSystem)
- NO decide qué ruta tomar (eso es DecisionSystem → MovementSystem)

---

## 12. NAVEGACIÓN SEMÁNTICA

### 12.1 SemanticPoint (Resource)

Jerarquía inspirada en NavigationPoint de UT99:

```
SemanticPoint:
    # Identidad
    point_id: int
    point_type: SemanticPointType
    position: Vector3
    team: int               # -1 = neutral
    priority: int           # Prioridad de selección

    # Táctica
    look_direction: Vector3     # Dirección de mirada (para ambush/sniper)
    sight_radius: float         # Radio de visión desde este punto
    is_sniper_spot: bool        # ¿Es punto de francotirador?
    tags: Array[String]         # Etiquetas para búsqueda

    # Navegación
    extra_cost: float           # Costo adicional en pathfinding
    is_one_way: bool            # ¿Solo se puede atravesar en una dirección?
    is_player_only: bool        # ¿Solo accesible para jugadores?
    selection_weight: float     # 0.0-1.0 — distribución probabilística entre bots

    # GameMode
    fort_tag: String            # Asociación a objetivo (CTF: "red_base", DOM: "control_A")
    item_type: String           # Tipo de item (si es ITEM point)
    respawn_time: float         # Tiempo de respawn del item

    # Ascensor
    lift_reference: NodePath    # Referencia al ascensor
    trigger_reference: NodePath # Referencia al trigger del ascensor
    lift_center_reference: NodePath  # Referencia al LiftCenter asociado
```

### 12.2 Tipos de SemanticPoint

| Tipo | Propósito | Atributos especiales |
|------|-----------|---------------------|
| `PATH` | Nodo de ruta genérico | — |
| `AMBUSH` | Punto de emboscada | `look_direction`, `sight_radius`, `is_sniper_spot` |
| `DEFENSE` | Punto de defensa por equipo | `team`, `priority`, `fort_tag` |
| `ALTERNATE` | Ruta alternativa (CTF) | `team`, `selection_weight`, `is_one_way` |
| `LIFT_CENTER` | Centro de ascensor | `lift_reference`, `trigger_reference` |
| `LIFT_EXIT` | Salida de ascensor | `lift_center_reference` |
| `ITEM` | Punto donde aparece un item | `item_type`, `respawn_time` |
| `SNIPER` | Punto de francotirador | `look_direction`, `sight_radius`, `min_skill` |

### 12.3 Integración con NavigationServer3D

```
Los SemanticPoints se superponen como capa semántica sobre el navmesh.

Flujo de pathfinding semántico:
1. MovementSystem (en el bot) solicita ruta: A → B
2. NavigationServer3D calcula ruta geométrica (navmesh)
3. DecisionSystem consulta NavigationSystem:
   - "Dame el SemanticPoint más cercano a mi destino"
   - "¿Hay AlternatePaths para mi equipo?"
   - "¿El punto DEFENSE de mi base está bajo ataque?"
4. DecisionSystem decide estrategia:
   a) Ruta directa (más rápida)
   b) Ruta con flanqueo (ALTERNATE path)
   c) Ir a punto AMBUSH cercano para emboscar
   d) Ir a punto DEFENSE si está defendiendo
   e) Ir a punto SNIPER si es sniper y tiene skill suficiente
5. MovementSystem ejecuta la ruta geométrica
```

### 12.4 Costos Dinámicos (ExtraCost / SpecialCost)

```
NavigationSystem.get_adjusted_cost(semantic_point, bot_context) -> float:
    base = semantic_point.extra_cost

    # Contexto del bot
    if bot_context.health < 30:
        base += 10.0  # Evitar zonas peligrosas si está herido
    if bot_context.has_flag:
        base -= 5.0 if semantic_point.point_type == ALTERNATE else 10.0
        # Preferir rutas alternativas si lleva la bandera
    if bot_context.is_retreating:
        base -= 15.0 if semantic_point.team == bot_context.team else 0
        # Preferir rutas hacia la base si se retira

    # Contexto del mapa
    if is_under_enemy_fire(semantic_point.position):
        base += 15.0  # Punto bajo fuego enemigo

    # GameMode hook
    base += ObjectiveSystem.get_path_cost_modifier(semantic_point, bot_context)

    return base
```

### 12.5 AlternatePath System (CTF)

```
Flujo de selección de ruta alternativa (UT99 exacto):
1. Bot tiene orden ATTACK en CTF
2. DecisionSystem consulta NavigationSystem:
   "¿Hay AlternatePaths para mi equipo?"
3. Si sí:
   - Cada AlternatePath tiene selection_weight (0.0-1.0)
   - Distribución probabilística entre bots del equipo
   - Algunos bots van por ruta directa, otros por alterna
   - El peso evita que todos elijan la misma ruta
4. Si el bot lleva la bandera (return):
   - Prefiere AlternatePath con team=bot.team
   - Mayor extra_cost para rutas directas (más riesgo de perder bandera)
```

---

## 13. OBJECTIVE SYSTEM — GAMEMODE

### 13.1 Responsabilidad Única
Definir los objetivos del equipo y del bot. **NO dice cómo cumplirlos.** Comunica a los bots solo a través de señales y consultas.

### 13.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `team_objectives: Array[Objective]` | **ObjectiveSystem** | DecisionSystem (solo lectura) |
| `match_phase: MatchPhase` | **ObjectiveSystem** | Todos (solo lectura) |
| `team_scores: Array[int]` | **ObjectiveSystem** | UI, Scoreboard |
| `match_timer: float` | **ObjectiveSystem** | UI, Scoreboard |

### 13.3 Objective (Resource)

```
Objective:
    objective_id: String
    objective_type: Enum { CAPTURE, DEFEND, ATTACK, RETURN, ESCORT, HOLD }
    target_node: NodePath          # Nodo objetivo (bandera, core, punto de control)
    position: Vector3              # Posición del objetivo
    team: int                      # Equipo al que pertenece
    priority: float                # Prioridad (0.0-1.0)
    completion_radius: float       # Radio de completitud
    is_completed: bool
    fallback_objective: String     # Objetivo al que ir si este está completado
    expires_at: float              # Tiempo de expiración (-1 = no expira)
    assigned_bots: Array[int]      # IDs de bots asignados a este objetivo
```

### 13.4 MatchPhase

```
enum MatchPhase {
    WARMUP,     # Calentamiento — bots deambulan sin combate
    ACTIVE,     # Partida activa — bots siguen objetivos
    OVERTIME,   # Tiempo extra
    COMPLETED,  # Partida terminada
}
```

### 13.5 API Pública

```
# Objetivos
get_objectives_for_team(team: int) -> Array[Objective]
get_objectives_for_bot(bot: Bot) -> Array[Objective]
get_primary_objective(bot: Bot) -> Objective
is_objective_completed(objective_id: String) -> bool

# Hooks de IA (los GameModes concretos sobrescriben)
find_special_attraction_for(bot: Bot) -> Vector3
    # ¿Hay algo interesante para este bot? Retorna posición o Vector3.INF
get_threat_modifier(bot: Bot, candidate: Sighting) -> float
    # Modificador de amenaza específico del GameMode
get_path_cost_modifier(semantic_point: SemanticPoint, bot: Bot) -> float
    # Modificador de costo de pathfinding

# Eventos
on_bot_killed(victim: Bot, killer: Node3D)
on_objective_captured(objective_id: String, team: int)
on_bot_picked_up_flag(bot: Bot)
on_flag_returned(team: int)
on_flag_captured(team: int)
```

### 13.6 Integración con GameModes

Cada GameMode extiende ObjectiveSystem y sobrescribe los hooks:

```
GameMode_Deathmatch:
    - Sin objetivos de equipo
    - find_special_attraction_for: siempre null
    - get_threat_modifier: sin modificador (0.0)
    - get_path_cost_modifier: sin modificador

GameMode_TeamDeathmatch:
    - find_special_attraction_for:
        si hay aliado siendo atacado cerca → posición del aliado
    - get_threat_modifier:
        +0.2 si el enemigo está matando aliados (últimos 5s)
    - get_path_cost_modifier: sin modificador

GameMode_CTF:
    - Objetivos:
        CAPTURE — bandera enemiga
        DEFEND — bandera propia
        RETURN — bandera caída (propia)
    - find_special_attraction_for:
        1. bandera caída propia → ir a recogerla
        2. bandera enemiga visible → ir a capturarla
        3. enemigo con bandera propia visible → perseguirlo
    - get_threat_modifier:
        +0.5 si el enemigo lleva la bandera propia
        +0.3 si el enemigo está cerca de bandera enemiga
    - get_path_cost_modifier:
        +20 si lleva bandera y el punto es ruta directa
        -20 si lleva bandera y el punto es ALTERNATE de su equipo

GameMode_Domination:
    - Objetivos:
        CAPTURE — puntos de control neutrales
        DEFEND — puntos de control propios
        ATTACK — puntos de control enemigos
    - find_special_attraction_for:
        punto neutral más cercano sin capturar
        punto propio bajo ataque
    - get_threat_modifier:
        +0.3 cerca de punto de control disputado
    - get_path_cost_modifier:
        +10 si el punto está lejos de cualquier punto de control

GameMode_Assault:
    - Objetivos:
        ATTACK — fortaleza activa (la más cercana no destruida)
        DEFEND — fortaleza activa (defensores)
    - find_special_attraction_for:
        fortaleza activa (atacantes)
        DefensePoints de la fortaleza activa (defensores)
    - get_threat_modifier:
        +0.4 si el enemigo está en la fortaleza actual
        -0.2 si la fortaleza actual está destruida
```

### 13.7 FindSpecialAttraction — Patrón Strategy

```
Este es el mecanismo por el cual el GameMode "secuestra" la decisión del bot.

El bot llama a FindSpecialAttractionFor() durante ChooseAttackMode().
Si retorna una posición, el bot va ALLÍ, ignorando su decisión normal.

Esto permite:
  - CTF: "ve a recoger la bandera caída"
  - DOM: "ve a capturar el punto de control"
  - AS: "ve a la fortaleza"
  - TDM: "ve a apoyar a tu aliado que está siendo atacado"

El bot NO escribe nada. Solo recibe una posición y decide ir allí.
```

### 13.8 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `objective_updated(objective, bot_id)` | Objetivo cambió |
| `objective_completed(objective_id, team)` | Objetivo completado |
| `match_phase_changed(new_phase)` | Fase de partida cambió |
| `threat_modifier(bot_id, threat_value)` | Modificador de amenaza para un bot |
| `special_attraction(bot_id, position)` | Atracción especial para un bot |

---

## 14. ORDER SYSTEM

### 14.1 Responsabilidad Única
Gestionar órdenes por bot, jerarquía líder→seguidor, y separación RealOrders vs Orders.

### 14.2 Data Ownership
| Variable | Propietario | Lectores |
|----------|-------------|----------|
| `current_orders: Dictionary[bot_id, Order]` | **OrderSystem** | DecisionSystem |
| `real_orders: Dictionary[bot_id, Order]` | **OrderSystem** | DecisionSystem (init) |
| `leaders: Dictionary[team_id, bot_id]` | **OrderSystem** | DecisionSystem |
| `order_givers: Dictionary[bot_id, Node3D]` | **OrderSystem** | DecisionSystem |

### 14.3 Order (Resource)

```
Order:
    order_type: OrderType    # FREELANCE, ATTACK, DEFEND, FOLLOW, HOLD, POINT
    target: NodePath         # A quién/apuntar la orden
    position: Vector3        # Posición asociada
    giver: Node3D            # Quién dio la orden (GameMode, líder, jugador)
    timestamp: float         # Cuándo se dio
    is_temporary: bool       # Si es temporal (Orders) o persistente (RealOrders)
    priority: int            # Prioridad (para resolver conflictos)
```

### 14.4 Tipos de Órdenes (UT99 exacto)

| Orden | Comportamiento |
|-------|----------------|
| `FREELANCE` | Sin órdenes específicas. El bot decide según su perfil y rol táctico. |
| `ATTACK` | Atacar objetivo del equipo (core, bandera, punto de control, fortaleza). |
| `DEFEND` | Defender un punto específico. Usa DefensePoint. Se queda dentro del radio. |
| `FOLLOW` | Seguir a un líder (otro bot o jugador). Mantener distancia de 5-10 unidades. |
| `HOLD` | Mantener posición fija. No moverse del punto. Solo responde a daño directo. |
| `POINT` | Apoyar a un jugador específico (escolta/refuerzo). Mantenerse cerca. |

### 14.5 Separación RealOrders vs Orders (UT99 exacto)

```
RealOrders: orden original y persistente.
  - Se asigna al inicio de partida por MatchManager
  - Se cambia solo por GameMode o líder
  - Es la "misión" del bot

Orders: orden actual (puede cambiar TEMPORALMENTE).
  - "Vi un enemigo" → Orders cambia a ATTACK (temporal)
  - "Me están atacando" → Orders cambia a RETREAT (temporal)
  - "Escuché un ruido" → Orders cambia a HUNT (temporal)

REGLA FUNDAMENTAL:
  Cuando el bot completa su acción temporal, llama:
    SetOrders(RealOrders, OrderGiver, true)
  Esto restaura la orden original.

FLUJO COMPLETO:
  1. Inicio de partida → MatchManager asigna RealOrders según GameMode y rol
  2. Durante la partida → El bot puede desviarse temporalmente
  3. Cuando termina → Restaura RealOrders
  4. Cambio permanente → GameMode/líder actualiza RealOrders
```

### 14.6 Jerarquía Líder→Seguidor

```
1. Cada equipo tiene un líder (primer bot asignado, o el de mayor skill)
2. El líder NO ordena directamente — el OrderSystem gestiona las órdenes
3. El líder es un "punto de referencia" para FOLLOW:
   - Los bots con orden FOLLOW siguen al líder
   - Distancia de seguimiento: 5-10 unidades
   - Si el líder muere, reasignar seguidores al nuevo líder
4. bLeading flag: el líder sabe que otros le siguen
   - Puede esperar si el seguidor se queda atrás
   - Puede cambiar de ruta si el seguidor está atascado
```

### 14.7 API

```
set_orders(bot_id: int, orders_type: OrderType, target: Node3D, position: Vector3)
get_current_orders(bot_id: int) -> Order
get_real_orders(bot_id: int) -> Order
restore_real_orders(bot_id: int)
set_leader(team_id: int, leader_bot_id: int)
get_leader(team_id: int) -> Node3D
is_leading(bot_id: int) -> bool
set_supporting_player(bot_id: int, player_id: int)
get_supporting_player(bot_id: int) -> int
```

---

## 15. TEAM COORDINATOR

### 15.1 Responsabilidad Única
Coordinar acciones entre bots del mismo equipo. Sustituye a team_ai.gd (actualmente vacío).

### 15.2 Data Ownership
| Variable | Propietario |
|----------|-------------|
| `team_composition: Dictionary[team_id, Array[bot_id]]` | **TeamCoordinator** |
| `role_assignment: Dictionary[team_id, Dictionary[bot_id, TacticalRoleType]]` | **TeamCoordinator** |
| `squad_formations: Dictionary[team_id, Formation]` | **TeamCoordinator** |
| `recent_help_requests: Array[HelpRequest]` | **TeamCoordinator** |

### 15.3 Asignación de Roles

```
assign_roles(team_id: int):
    1. Obtener bots vivos del equipo
    2. Determinar roles necesarios según GameMode:
       CTF: 2 DEFENDER, 2 ASSAULT, 1 FLANKER, 1 PATROLLER
       DOM: 2 DEFENDER (puntos propios), 2 ASSAULT (puntos neutrales), 2 FLANKER
       TDM: 3 ASSAULT, 2 FLANKER, 1 PATROLLER
       AS (atacantes): 3 ASSAULT, 2 FLANKER, 1 PATROLLER
       AS (defensores): 3 DEFENDER, 2 PATROLLER, 1 FLANKER
    3. Asignar según:
       - Perfil del bot (combat_style, aggressiveness)
       - skill (snipers necesitan skill >= 4)
       - Rol anterior (evitar cambios innecesarios)
    4. Si un bot muere:
       - Reasignar roles inmediatamente
       - El rol del muerto lo cubre el bot más cercano
       - NOTA crítica: no sobrecargar — si no hay suficientes bots, priorizar los roles más importantes
```

### 15.4 Coordinación de Ataques

```
coordinate_attack(objective: Objective, team_id: int):
    1. Identificar bots disponibles (no en combate, no huyendo)
    2. Calcular cuántos bots están atacando ya este objetivo
    3. Si 3+ bots ya atacan: los demás buscan otro objetivo
       (evitar saturación)
    4. Si el objetivo requiere flanqueo:
       - 2 bots atacan de frente (distracción)
       - 2 bots flanquean por ruta alternativa
    5. Timing: idealmente todos atacan simultáneamente
       - Sincronizar con timer de 2-3s
```

### 15.5 Solicitud de Ayuda

```
request_help(bot_id: int, severity: float):
    1. Registrar solicitud (posición, severidad, tiempo)
    2. Evaluar:
       - ¿Hay algún bot libre asignable?
       - ¿El bot libre está más cerca que otros?
       - Máximo 2 bots por solicitud
    3. Asignar refuerzo:
       - Bot más cercano con órdenes FREELANCE o PATROLLER
       - NO interrumpir bots con orden DEFEND (dejarían posición)
       - NO interrumpir bots con orden ATTACK a punto de completar objetivo
    4. Emitir help_dispatched(helper_id, target_id)

help_priority:
    1. Salud del solicitante (< 20 HP → urgente)
    2. Importancia del rol (DEFENDER de base > PATROLLER)
    3. Proximidad del enemigo
```

### 15.6 Liderazgo

```
1. Cada equipo tiene un líder (primer bot asignado)
2. Si el líder muere → nuevo líder es el bot vivo con mayor skill
3. El líder coordina, NO da órdenes directas:
   - El GameMode da las órdenes a través de ObjectiveSystem
   - El líder solo influye en la asignación de roles (TeamCoordinator)
   - TeamCoordinator escucha al líder para reasignaciones
```

### 15.7 Señales que Emite
| Señal | Cuándo |
|-------|--------|
| `role_changed(bot_id, new_role)` | Rol de un bot cambió |
| `help_requested(bot_id, position, severity)` | Bot pide ayuda |
| `help_dispatched(helper_id, target_id)` | Refuerzo asignado |
| `formation_updated(team, formation)` | Formación del equipo cambió |
| `leader_changed(team, new_leader_id)` | Nuevo líder del equipo |

---

## 16. SKILL SYSTEM

### 16.1 Responsabilidad Única
Definir y gestionar perfiles de habilidad y personalidad de cada bot. Es un Autoload global.

### 16.2 Data Ownership
| Variable | Propietario |
|----------|-------------|
| `bot_profiles: Dictionary[int, BotProfile]` | **SkillSystem** |
| `difficulty_table: Dictionary[int, DifficultyConfig]` | **SkillSystem** |
| `match_history: Dictionary[int, MatchRecord]` | **SkillSystem** |

### 16.3 BotProfile (Resource)

```
BotProfile:
    # Identidad
    bot_name: String
    team: int
    voice_type: String
    skin: String

    # Habilidad base
    skill: int                    # 0-7 (UT99 exacto)
    accuracy: float               # 0.0-1.0
    strafing_ability: float       # 0.0-1.0

    # Personalidad
    combat_style: float           # -1.0 sniper / +1.0 agresivo
    aggressiveness: float         # 0.0-1.0
    alertness: float              # -1.0 distraído / +1.0 alerta
    camping_rate: float           # 0.0-1.0
    jumpy: bool
    b_devious: bool               # tácticas engañosas

    # Preferencias
    favorite_weapon: String
    lead_target: bool

    # Dificultad
    difficulty_tier: String       # novice / standard / veteran / elite
```

### 16.4 Perfiles de Dificultad (Skill Tiers)

| Tier | Skill | accuracy | strafing | alertness | camping | lead_target | Descripción |
|------|-------|----------|----------|-----------|---------|-------------|-------------|
| NOVICE | 0-1 | 0.1-0.2 | 0.0 | -0.5 | 0.0 | false | Dispara sin puntería, se queda quieto, no strafea |
| STANDARD | 2-3 | 0.3-0.5 | 0.3 | 0.0 | 0.2 | false | Bot promedio de UT99, strafe básico |
| VETERAN | 4-5 | 0.6-0.7 | 0.6 | 0.5 | 0.3 | true | Strafing competente, predice movimiento |
| ELITE | 6-7 | 0.8-1.0 | 0.9 | 1.0 | 0.4 | true | Precisión máxima, tácticas engañosas (bDevious) |

### 16.5 MatchRecord (para dificultad dinámica)

```
MatchRecord:
    games_played: int               # Partidas jugadas contra este jugador
    wins_against_player: int        # Veces que el bot le ganó al jugador
    losses_against_player: int      # Veces que el bot perdió contra el jugador
    current_streak: int             # Racha actual (+ = derrotas, - = victorias)
    last_adjustment_time: float     # Último ajuste de skill
    total_kills: int                # Kills totales del bot
    total_deaths: int               # Muertes totales del bot
```

### 16.6 API

```
get_profile(bot_id: int) -> BotProfile
get_random_profile_for_team(team: int) -> BotProfile
initialize_skill(bot: Bot, difficulty_level: int) -> void
adjust_skill(bot_id: int, won_against_player: bool) -> void
get_difficulty_config(skill: int) -> DifficultyConfig
get_match_record(bot_id: int) -> MatchRecord
```

---

## 17. MATRIZ DE DATA OWNERSHIP

### 17.1 Tabla Completa

| Variable | Propietario (ESCRIBE) | Lectores | Prohibido escribir |
|----------|----------------------|----------|-------------------|
| `velocity` | **MovementSystem** | Physics engine | DecisionSystem, CombatSystem, WeaponSystem, PerceptionSystem |
| `global_position` | **Physics engine** | Todos leen | Nadie escribe directamente |
| `target_entity` | **DecisionSystem** | CombatSystem, PerceptionSystem | MovementSystem, WeaponSystem |
| `movement_command` | **DecisionSystem** | MovementSystem | CombatSystem, WeaponSystem |
| `combat_command` | **DecisionSystem** | CombatSystem | MovementSystem, WeaponSystem |
| `aim_rotation` | **CombatSystem** | Model/Arma (visual) | DecisionSystem, MovementSystem |
| `weapon_status` | **WeaponSystem** | CombatSystem, DecisionSystem | MovementSystem, PerceptionSystem |
| `ammo_count` | **WeaponSystem** | DecisionSystem, CombatSystem | MovementSystem |
| `health` | **HealthSystem** | DecisionSystem, UI | MovementSystem, CombatSystem |
| `sensor_data` | **PerceptionSystem** | DecisionSystem, MemorySystem | MovementSystem, CombatSystem |
| `memory_store` | **MemorySystem** | DecisionSystem | PerceptionSystem (solo emite señal) |
| `stuck_state` | **MovementSystem** | DecisionSystem | CombatSystem, WeaponSystem |
| `navigation_path` | **MovementSystem** | — (interno) | Todos los demás |
| `objectives` | **ObjectiveSystem** | DecisionSystem | Todos los bots |
| `orders` | **OrderSystem** | DecisionSystem | MovementSystem, CombatSystem |
| `bot_profile` | **SkillSystem** | DecisionSystem (init) | MovementSystem, CombatSystem |
| `damage_history` | **HealthSystem** | DecisionSystem | CombatSystem, MovementSystem |
| `navigation_mesh` | **NavigationSystem** | NavigationServer3D | Todos los bots |
| `semantic_points` | **NavigationSystem** | DecisionSystem (vía query) | Todos los bots |
| `match_phase` | **ObjectiveSystem** | Todos | Todos los bots |
| `role_assignment` | **TeamCoordinator** | DecisionSystem | MovementSystem, CombatSystem |
| `current_state` | **DecisionSystem** | Debug overlay | Todos los demás |
| `focus_point` | **DecisionSystem** | CombatSystem | MovementSystem |

### 17.2 Reglas de Acceso por Sistema

| Sistema | Puede escribir | Puede leer | Prohibido escribir |
|---------|---------------|------------|-------------------|
| PerceptionSystem | sensor_data | Posiciones globales, collision shapes | velocity, target, commands, memory |
| MemorySystem | memory_store | sensor_data (vía señal) | velocity, target, commands |
| DecisionSystem | target_entity, movement_command, combat_command, focus_point, current_state | sensor_data, memory, objectives, orders, weapon_status, health, stuck_state, aim_rotation | velocity, aim_rotation, weapon_status |
| MovementSystem | velocity, navigation_path, stuck_state | movement_command | target_entity, combat_command, aim_rotation |
| CombatSystem | aim_rotation, dodge_state, engagement_data | combat_command, weapon_status, target_entity | velocity, movement_command |
| WeaponSystem | weapon_status, ammo, cooldown | combat_command.fire_request | velocity, target, commands |
| HealthSystem | health, damage_history | — | velocity, target, commands |
| NavigationSystem | navmesh, semantic_points | Geometría del mapa | TODO del bot |
| ObjectiveSystem | objectives, match_phase | Estado global | TODO del bot (solo señales) |
| OrderSystem | orders, leaders | objectives | TODO del bot |
| SkillSystem | bot_profiles, match_history | — | TODO del bot |
| TeamCoordinator | role_assignment | objectives, scores | TODO del bot |

---

## 18. FLUJO DEL FRAME — ORDEN ESTRICTO

```
┌──────────────────────────────────────────────────────────────────────────────┐
│              FRAME COMPLETO (delta ~ 1/60)                                    │
│              Llamado desde NpcBase._physics_process(delta)                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ FASE 0: SISTEMAS GLOBALES (orden fijo, 1 vez por frame)                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ [0.1] ObjectiveSystem.process(delta)                                          │
│   ├── Verificar estado de objetivos (completados? nuevos?)                    │
│   ├── Actualizar match_phase si corresponde                                  │
│   └── Emitir señales (objective_updated, match_phase_changed)                 │
│                                                                                │
│ [0.2] NavigationSystem.process(delta)                                         │
│   └── Solo actualizar estructuras internas si cambió el mapa                  │
│       (navmesh rebuild, semántic points)                                      │
│                                                                                │
│ [0.3] TeamCoordinator.process(delta)                                          │
│   ├── Re-evaluar roles si algún bot murió/respawnió                           │
│   ├── Procesar solicitudes de ayuda pendientes                                │
│   └── Coordinar ataques si es necesario                                       │
│                                                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ FASE 1: SENSORES (por cada bot, orden fijo)                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ [1.1] PerceptionSystem.update(delta)                                          │
│   ├── Escanear Area3D (zona de visión) por cuerpos                            │
│   ├── Verificar LOS con RayCast3D desde Head                                  │
│   ├── ESCRIBIR: sensor_data.visible, .heard, .threats                         │
│   └── Emitir: entity_detected, entity_lost, noise_heard, threat_assessed      │
│                                                                                │
│ [1.2] MemorySystem.update(delta)                                              │
│   ├── Escuchar señales de PerceptionSystem (conectar este frame)              │
│   ├── Integrar nuevos datos en memory_store (append/update/merge)             │
│   ├── Decaer: reducir confidence de memorias viejas                           │
│   ├── Expirar: memorias con age > duration                                    │
│   ├── ESCRIBIR: memory_store                                                  │
│   └── Emitir: memory_updated, memory_expired                                  │
│                                                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ FASE 2: DECISIÓN (por cada bot)                                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ [2.1] DecisionSystem.process(delta)                                           │
│   ├── [2.1a] FSM.evaluate_transitions()                                       │
│   │   ├── Leer: sensor_data, memory_store, objectives, orders                 │
│   │   ├── Leer: health, weapon_status, stuck_state, engagement_data           │
│   │   ├── Evaluar condiciones de transición (prioridad 110 → 0)              │
│   │   └── Si cambia de estado → emitir state_changed, llamar exit() / enter() │
│   │                                                                           │
│   ├── [2.1b] FSM.state.execute(delta)                                        │
│   │   ├── El estado activo ejecuta su lógica específica                       │
│   │   ├── ESCRIBIR: movement_command, combat_command                          │
│   │   ├── ESCRIBIR: target_entity (si aplica)                                 │
│   │   ├── ESCRIBIR: focus_point                                               │
│   │   └── REGLA: el estado NO escribe velocity, NO escribe weapon            │
│   │                                                                           │
│   ├── [2.1c] TargetEvaluator.evaluate()                                      │
│   │   ├── Si hay nuevos candidatos → evaluar amenaza                          │
│   │   ├── Aplicar: inercia, venganza, remate                                 │
│   │   └── Decidir si cambiar de objetivo                                      │
│   │                                                                           │
│   └── [2.1d] CommandValidator.validate()                                     │
│       ├── Validar movement_command (destino válido? modo correcto?)           │
│       ├── Validar combat_command (target vivo? engage coherente?)             │
│       └── Si inválido → resetear a NONE / engage=false                        │
│                                                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ FASE 3: EJECUCIÓN (por cada bot)                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ [3.1] CombatSystem.process(delta)                                             │
│   ├── Leer: combat_command (de DecisionSystem)                                │
│   ├── Leer: target_entity.position (de la escena)                             │
│   ├── Leer: weapon_status, ai_profile (de WeaponSystem)                       │
│   ├── Calcular: aim_rotation = adjust_aim(target, weapon_profile)             │
│   ├── Calcular: should_fire = decisión de disparo                             │
│   ├── ESCRIBIR: aim_rotation                                                  │
│   ├── ESCRIBIR: engagement_analysis (para DecisionSystem)                     │
│   └── Emitir: weapon_fired, target_in_range, target_lost                       │
│                                                                                │
│ [3.2] MovementSystem.process(delta)                                           │
│   ├── Leer: movement_command (de DecisionSystem)                              │
│   ├── Consultar: NavigationAgent3D (ruta actual)                              │
│   ├── Calcular: desired_velocity según modo y comandos                        │
│   ├── Aplicar: evitación entre NPCs                                           │
│   ├── Aplicar: gravedad (ÚNICO lugar)                                         │
│   ├── ESCRIBIR: velocity                                                      │
│   └── Emitir: stuck signals (solo detecta, NO cambia destino)                 │
│                                                                                │
│ [3.3] WeaponSystem.process(delta)                                             │
│   ├── Leer: combat_command.engage (de CombatSystem)                           │
│   ├── Procesar: cooldown_timer -= delta                                       │
│   ├── Procesar: reload_state (si está recargando)                             │
│   ├── Si should_fire y can_fire() → ejecutar fire()                           │
│   ├── ESCRIBIR: weapon_status, ammo_count, cooldown                           │
│   └── Emitir: weapon_ready, weapon_empty, reload_started, etc.                │
│                                                                                │
│ [3.4] HealthSystem.process(delta) [solo si hay daño continuo]                 │
│   └── Procesar: efectos de zona (lava, ácido, zonas de daño ambiental)        │
│                                                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ FASE 4: FÍSICA (por cada bot)                                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ [4.1] Physics engine (move_and_slide)                                         │
│   ├── LEE: velocity (ya escrita por MovementSystem)                           │
│   ├── Aplica: colisiones, fricción, restitución                               │
│   ├── ESCRIBE: global_position (actualizada por física)                       │
│   └── ESCRIBE: is_on_floor, is_on_wall, is_on_ceiling                         │
│                                                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ FASE 5: POST-PROCESAMIENTO (por cada bot)                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ [5.1] MovementSystem.post_process(delta)                                      │
│   ├── Verificar: stuck post-movimiento (comparar posición real vs esperada)   │
│   ├── Verificar: llegada a destino                                            │
│   └── Emitir: destination_reached, stuck_detected, path_blocked               │
│                                                                                │
│ [5.2] CombatSystem.post_process(delta)                                        │
│   ├── Aplicar: aim_rotation al modelo/arma (solo visual)                      │
│   └── REGLA: NO toca velocity, NO toca posición                               │
│                                                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ FASE 6: SEÑALES DIFERIDAS (por cada bot, del frame anterior)                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ [6.1] Procesar cola de señales entrantes                                      │
│   ├── DecisionSystem.on_destination_reached(pos)                              │
│   ├── DecisionSystem.on_stuck_detected(phase, cause)                          │
│   ├── DecisionSystem.on_stuck_resolved()                                      │
│   ├── DecisionSystem.on_damage_taken(amount, attacker, type)                  │
│   ├── DecisionSystem.on_target_lost(entity_id)                                │
│   ├── DecisionSystem.on_orders_changed(new_order)                             │
│   ├── DecisionSystem.on_special_attraction(position)                          │
│   ├── DecisionSystem.on_weapon_ready()                                        │
│   ├── DecisionSystem.on_weapon_empty()                                        │
│   └── DecisionSystem.on_ammo_changed(current, reserve)                        │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 18.1 Justificación de Timing

| Sistema | Orden | Por qué este orden |
|---------|-------|-------------------|
| ObjectiveSystem | 0 | Los objetivos deben estar definidos ANTES de que los bots decidan |
| NavigationSystem | 0 | El navmesh debe estar listo ANTES de que los bots lo consulten |
| TeamCoordinator | 0 | Los roles deben estar asignados ANTES de que los bots decidan |
| PerceptionSystem | 1 | Los datos sensoriales deben estar listos para memoria y decisión |
| MemorySystem | 2 | La memoria se actualiza con los datos sensoriales del MISMO frame |
| DecisionSystem | 3 | Decide basado en percepción + memoria del mismo frame |
| CombatSystem | 4 | Calcula puntería basado en la decisión del frame actual |
| MovementSystem | 5 | Calcula velocity basado en la decisión del frame actual |
| WeaponSystem | 6 | Dispara basado en la decisión de combate + aim del frame actual |
| HealthSystem | 7 | Daño continuo es lo menos urgente |
| Physics | 8 | move_and_slide usa la velocity FINAL del frame |
| Post-process | 9 | Verifica resultados del movimiento después de la física |
| Señales | 10 | Procesa señales del frame anterior (nunca re-entrante) |

---

## 19. MAPA COMPLETO DE SEÑALES

### 19.1 Conexiones Internas del Bot

```
PerceptionSystem ──entity_detected──────────────────▶ DecisionSystem
PerceptionSystem ──entity_lost──────────────────────▶ DecisionSystem
PerceptionSystem ──threat_assessed──────────────────▶ DecisionSystem
PerceptionSystem ──noise_heard──────────────────────▶ MemorySystem
PerceptionSystem ──noise_heard──────────────────────▶ DecisionSystem

MemorySystem ──────memory_updated───────────────────▶ DecisionSystem
MemorySystem ──────memory_expired───────────────────▶ DecisionSystem

MovementSystem ────destination_reached──────────────▶ DecisionSystem
MovementSystem ────stuck_detected───────────────────▶ DecisionSystem
MovementSystem ────stuck_resolved───────────────────▶ DecisionSystem
MovementSystem ────path_blocked─────────────────────▶ DecisionSystem

CombatSystem ──────weapon_fired─────────────────────▶ WeaponSystem
CombatSystem ──────target_in_range──────────────────▶ DecisionSystem
CombatSystem ──────target_lost──────────────────────▶ DecisionSystem
CombatSystem ──────out_of_ammo──────────────────────▶ DecisionSystem
CombatSystem ──────dodge_performed──────────────────▶ MovementSystem (cómosignal)

WeaponSystem ──────weapon_ready─────────────────────▶ CombatSystem
WeaponSystem ──────weapon_ready─────────────────────▶ DecisionSystem
WeaponSystem ──────weapon_empty─────────────────────▶ CombatSystem
WeaponSystem ──────weapon_empty─────────────────────▶ DecisionSystem
WeaponSystem ──────reload_started───────────────────▶ CombatSystem
WeaponSystem ──────reload_completed─────────────────▶ CombatSystem
WeaponSystem ──────reload_completed─────────────────▶ DecisionSystem
WeaponSystem ──────ammo_changed─────────────────────▶ DecisionSystem

HealthSystem ──────damage_taken─────────────────────▶ DecisionSystem
HealthSystem ──────damage_taken─────────────────────▶ MemorySystem
HealthSystem ──────health_changed───────────────────▶ DecisionSystem
HealthSystem ──────death────────────────────────────▶ DecisionSystem
HealthSystem ──────death────────────────────────────▶ MatchManager
HealthSystem ──────death────────────────────────────▶ TeamCoordinator
```

### 19.2 Conexiones Globales

```
ObjectiveSystem ───objective_updated────────────────▶ TeamCoordinator
ObjectiveSystem ───objective_updated────────────────▶ DecisionSystem (cada bot)
ObjectiveSystem ───objective_completed──────────────▶ TeamCoordinator
ObjectiveSystem ───match_phase_changed──────────────▶ MatchManager
ObjectiveSystem ───match_phase_changed──────────────▶ HUD
ObjectiveSystem ───orders_changed───────────────────▶ DecisionSystem (bot específico)
ObjectiveSystem ───special_attraction───────────────▶ DecisionSystem (bot específico)
ObjectiveSystem ───threat_modifier──────────────────▶ DecisionSystem (bot específico)

TeamCoordinator ───role_changed─────────────────────▶ DecisionSystem (bot específico)
TeamCoordinator ───help_requested───────────────────▶ DecisionSystem (bots cercanos)
TeamCoordinator ───help_dispatched──────────────────▶ DecisionSystem (helper + target)
TeamCoordinator ───leader_changed───────────────────▶ OrderSystem
TeamCoordinator ───leader_changed───────────────────▶ DecisionSystem (bots del equipo)

MatchManager ──────match_started────────────────────▶ ObjectiveSystem
MatchManager ──────match_started────────────────────▶ SkillSystem
MatchManager ──────match_started────────────────────▶ TeamCoordinator
MatchManager ──────match_started────────────────────▶ HUD
MatchManager ──────bot_respawned────────────────────▶ ObjectiveSystem
MatchManager ──────bot_respawned────────────────────▶ SkillSystem (AdjustSkill)
MatchManager ──────bot_spawned──────────────────────▶ DecisionSystem (del bot)

GameState ─────────match_ended──────────────────────▶ MatchManager
GameState ─────────match_ended──────────────────────▶ HUD
GameState ─────────match_ended──────────────────────▶ ObjectiveSystem
GameState ─────────match_ended──────────────────────▶ SkillSystem
```

### 19.3 BotSignalBus (Autoload)

```
BotSignalBus (Autoload)
├── Señales de broadcast a TODOS los bots
├── Útil para comunicación que no necesita destinatario específico
├── Ejemplos:
│   ├── team_objective_updated(objective_id, team)
│   ├── global_alert(position, type, intensity)
│   └── match_phase_changed(phase)
└── Los bots se conectan en _ready() y se desconectan en _exit_tree()
```

---

## 20. COMANDOS — MOVEMENT Y COMBAT

### 20.1 MovementCommand (Resource Transitorio)

```
class MovementCommand:
    enum Mode { NONE, NAVIGATE, DIRECT, DODGE, STOP }

    mode: Mode = NONE

    # Para NAVIGATE
    target_position: Vector3        # Destino del pathfinding

    # Para DIRECT y DODGE
    direction: Vector3              # Vector de movimiento
    speed: float = 0.0              # Velocidad deseada

    # Para DODGE
    dodge_impulse: float = 0.0      # Fuerza del dodge
    jump: bool = false              # ¿Saltar?
    jump_velocity: float = 0.0      # Velocidad de salto

    # Modificadores generales
    sprint: bool = false            # ¿Correr a máxima velocidad?
    use_advanced_tactics: bool = false  # ¿Usar flanqueo/wall-dodge?
    suppress_stuck_detection: bool = false  # Suprimir stuck (en combate)

    # Opcional: a quién mirar mientras se mueve
    face_target: NodePath
    face_position: Vector3
```

### 20.2 CombatCommand (Resource Transitorio)

```
class CombatCommand:
    engage: bool = false            # ¿Disparar este frame?
    target_id: int = -1             # ID del objetivo
    fire_mode: int = 0              # 0 = primario, 1 = alterno

    # Control de puntería
    aim_at_position: Vector3        # Posición exacta para apuntar
    aim_at_entity: NodePath         # O ruta a la entidad
    aim_override: bool = false      # Ignorar aim automático?

    # Control de fuego
    force_fire: bool = false        # Ignorar refire rate (quickFire de UT99)
    cease_fire: bool = false        # Dejar de disparar explícitamente

    # Solicitud de dodge (CombatSystem pide, DecisionSystem decide)
    wants_dodge: bool = false
    dodge_direction: Vector3
    dodge_impulse: float = 0.0
```

### 20.3 Reglas de los Comandos
1. **Se crean nuevos cada frame** — DecisionSystem los escribe en FASE 2
2. **Se consumen una vez** — MovementSystem/CombatSystem los leen en FASE 3
3. **Estado por defecto** = "no hacer nada" (NONE / engage=false)
4. **Si no se escribe un comando** el frame actual, el sistema ejecutor no hace nada
5. **El CommandValidator** verifica coherencia antes de que los ejecutores lean
6. **No persisten entre frames** — el estado "no hacer nada" es la ausencia de comando

---

## 21. PERFILES DE BOT — BOTPROFILE + TACTICALROLE

### 21.1 Sistema de Dos Capas

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

El BotProfile es ESTÁTICO (se asigna al inicio de partida).
El TacticalRole puede CAMBIAR (TeamCoordinator reasigna según necesidades).
```

### 21.2 TacticalRole Configuration Matrix (UT99-auténtica)

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

## 22. PERFILES DE ARMA — WEAPONAIPROFILE

### 22.1 WeaponAIProfile (Resource)

```
class WeaponAIProfile extends Resource:
    # Rating general
    ai_rating: float                    # 0.0-1.0

    # Rango
    preferred_range_min: float
    preferred_range_max: float
    optimal_range_falloff: float        # Caída fuera de rango óptimo

    # Splash
    splash_damage: bool
    splash_radius: float

    # Predicción
    lead_target: bool
    projectile_speed: float

    # Cadencia
    refire_rate: float                  # 0.0-1.0
    base_dps: float

    # Puntería
    aim_error_base: int                 # 500-2500
    is_instant_hit: bool
    is_melee: bool

    # Estilo
    attack_style_modifier: float        # -1.0 a 1.0
    defense_style_modifier: float       # -1.0 a 1.0
    prefers_alt_fire: bool
    height_advantage: float             # -1 abajo mejor, +1 arriba mejor

    # Métodos
    func effective_dps(distance, ammo_ratio, height_delta) -> float
    func situational_rating(distance, context) -> float
    func get_recommended_fire_mode(distance, target_info) -> int
```

### 22.2 Integración con el Bot

```
1. WeaponSystem carga el WeaponAIProfile desde el Resource asociado al arma
2. CombatSystem consulta el profile para:
   - Decidir modo de fuego (primario/alterno)
   - Calcular error de puntería adaptativo
   - Determinar si debe predecir posición (lead_target)
   - Elegir entre apuntar al cuerpo o al suelo (splash)
3. DecisionSystem consulta el profile para:
   - Evaluar RelativeStrength (via effective_dps)
   - Decidir distancia de engagement ideal (preferred_range)
   - Elegir arma de la cadena de inventario (SwitchToBestWeapon)
4. SkillSystem usa el profile para escalar por dificultad:
   - Bots NOVICE: ignoran lead_target, aim_error ×3
   - Bots VETERAN: usan refire_rate completo, aim_error ×1
   - Bots ELITE: aim_error ×0.5, usan tácticas avanzadas
```

---

## 23. DIFICULTAD DINÁMICA — ADJUSTSKILL

### 23.1 Algoritmo (UT99 exacto modernizado)

```
AdjustSkill(bot_id: int, won_against_player: bool):
    1. profile = bot_profiles[bot_id]
    2. match_record = match_history[bot_id]
    3. match_record.games_played += 1

    4. if won_against_player:
         # Bot GANÓ contra el jugador → fue demasiado difícil → BAJAR
         match_record.current_streak = max(0, match_record.current_streak - 1)
         adjustment = -2.0 / min(match_record.games_played, 10)
       else:
         # Bot PERDIÓ contra el jugador → fue demasiado fácil → SUBIR
         match_record.current_streak += 1
         adjustment = 2.0 / min(match_record.games_played, 10)

    5. profile.skill = clamp(profile.skill + adjustment, 0, 7)
    6. profile.accuracy = clamp(profile.accuracy + adjustment * 0.05, 0.0, 1.0)
    7. profile.strafing_ability = clamp(profile.strafing_ability + adjustment * 0.03, 0.0, 1.0)

    8. # Recalcular tier
       if profile.skill < 2: profile.difficulty_tier = "novice"
       elif profile.skill < 4: profile.difficulty_tier = "standard"
       elif profile.skill < 6: profile.difficulty_tier = "veteran"
       else: profile.difficulty_tier = "elite"

    9. Emitir: skill_adjusted(bot_id, profile.skill)
```

### 23.2 Impacto del Skill en el Comportamiento

| Atributo | Skill 0 (Novice) | Skill 3 (Standard) | Skill 5 (Veteran) | Skill 7 (Elite) |
|----------|-----------------|-------------------|-------------------|-----------------|
| accuracy | 0.1 | 0.4 | 0.65 | 0.9 |
| strafing_ability | 0.0 | 0.3 | 0.6 | 0.9 |
| alertness | -0.5 | 0.0 | 0.5 | 1.0 |
| camping_rate | 0.0 | 0.2 | 0.3 | 0.4 |
| lead_target | false | false | true | true |
| b_devious | false | false | false | true |
| Aim error mult | ×3.0 | ×1.5 | ×1.0 | ×0.5 |
| Reaction time | +0.5s | +0.2s | normal | -0.2s |
| Weapon switch | lento | normal | rápido | instantáneo |
| Refire rate max | 0.4 | 0.6 | 0.8 | 1.0 |
| Strafe change | 3.0s | 2.0s | 1.5s | 0.8s |

### 23.3 Dificultad por Mapa/GameMode

```
Cada mapa y GameMode puede definir un modificador de dificultad base:
  - Mapa pequeño (DM-Deathmatch-small): +0 skill (fácil encontrar enemigos)
  - Mapa grande (CTF-Face): +2 skill (difícil navegar)
  - Contra jugador humano: +1 skill (bonus por ser humano)
  - Contra múltiples bots aliados: -1 skill (compensar número)
```

---

## 24. PERSONALIDAD Y VOCES

### 24.1 Componentes de Personalidad

```
BotProfile.personality:
    aggressiveness: 0.0-1.0    # ¿Busca pelea o la evita?
    alertness: -1.0 a 1.0      # ¿Nota cosas o está distraído?
    camping_rate: 0.0-1.0      # ¿Le gusta quedarse quieto?
    jumpy: bool                # ¿Salta constantemente?
    b_devious: bool            # ¿Usa tácticas engañosas?
    combat_style: -1.0 a 1.0   # Sniper vs Agresivo
```

### 24.2 Modificadores de Personalidad en Combate

```
Agresividad ALTA (0.8+):
  - Prefiere CHARGING sobre TACTICAL_MOVE
  - Menor umbral de retirada (solo se retira al 15% HP)
  - Mayor refire_rate (dispara constantemente)
  - Busca combate cuerpo a cuerpo
  - Usa menos cobertura
  - Strafe más agresivo (menos componente lateral)

Agresividad BAJA (0.2-):
  - Prefiere TACTICAL_MOVE sobre CHARGING
  - Se retira al 50% HP
  - Menor refire_rate (dispara con cautela)
  - Busca mantener distancia
  - Usa cobertura frecuentemente
  - Strafe más evasivo

Alertness ALTA (0.8+):
  - Menor tiempo de reacción a estímulos (0.1s vs 0.5s)
  - Detecta enemigos en ángulos más amplios (visión periférica)
  - Cambia de objetivo más rápido (menor inercia)
  - Memorias duran +5s más

Alertness BAJA (-0.5):
  - Mayor tiempo de reacción (+0.5s)
  - Visión más estrecha (ángulo reducido)
  - Persiste más en objetivo actual (no se distrae)
  - Memorias duran -5s menos

Camping_rate ALTA (0.7+):
  - Prefiere STAKE_OUT sobre HUNTING
  - Se queda más tiempo en posiciones ventajosas
  - Busca SemanticPoints de tipo AMBUSH/SNIPER
  - Mayor probabilidad de esperar en lugar de perseguir

bDevious (ELITE only):
  - Usa fintas: simula ir a un lugar, va a otro
  - Busca BlockedPath para flanqueos
  - Cambia de dirección impredeciblemente
  - Usa AlternatePath en CTF
  - Finge retirada para emboscar
```

### 24.3 Sistema de Voces (UT99 style)

```
VoiceType Resource:
    name: String                       # "MaleSoldier", "FemaleCommando", etc.
    sound_bank: Dictionary             # evento → Array[AudioStream]

    # Eventos de voz
    kill_phrases: Array[String]        # "Headshot!" "Gotcha!"
    death_phrases: Array[String]       # "I'm down!" "No way!"
    order_ack_phrases: Array[String]   # "On my way!" "Copy that!"
    enemy_spotted_phrases: Array[String] # "Enemy spotted!" "Target acquired!"
    help_phrases: Array[String]        # "I need backup!" "Help!"
    taunt_phrases: Array[String]       # "Is that all you got?"
    objective_phrases: Array[String]   # "I have the flag!" "Flag captured!"

    func play_event(event_type: String) -> void:
        # Los ELITE hablan más frecuentemente
        # Los NOVICE solo hablan en eventos críticos
        # Tasa de habla: 0.3 (novice) a 0.9 (elite)
        if randf() < bot_profile.speech_rate:
            play_random(sound_bank[event_type])
```

---

## 25. INTEGRACIÓN CON GAMEMODES

### 25.1 Arquitectura GameMode

```
ObjectiveSystem (base) — en el mapa
├── find_special_attraction_for(bot) -> Vector3
├── get_threat_modifier(bot, candidate) -> float
├── get_path_cost_modifier(semantic_point, bot) -> float
├── get_objectives_for_team(team) -> Array[Objective]
├── get_objectives_for_bot(bot) -> Array[Objective]
└── on_bot_killed(victim, killer)

Los GameModes concretos heredan y SOBRESCRIBEN estos métodos:

GameMode_Deathmatch
GameMode_TeamDeathmatch
GameMode_CTF
GameMode_Domination
GameMode_Assault
```

### 25.2 MatchManager y GameState

```
MatchManager (Autoload) — GESTIONA la partida
  - Pool de bots, spawn, respawn, auto-balance
  - Registro centralizado de PlayerData
  - Inicia/termina la partida
  - NO tiene lógica de IA — solo gestión de partida

GameState (Autoload) — ESTADO de la partida
  - match_active, winner_team, cores
  - Configuración global (sensibilidad, mapa seleccionado)
  - NO tiene lógica de gameplay — solo estado

ObjectiveSystem (en el mapa) — OBJETIVOS de la partida
  - Define qué deben hacer los bots
  - Se instancia según el GameMode seleccionado
  - Contiene OrderSystem como hijo

MatchManager = "cómo se juega" (reglas de partida)
GameState = "qué está pasando" (estado global)
ObjectiveSystem = "qué deben hacer los bots" (objetivos de IA)
```

---

## 26. ESTRUCTURA DE ESCENA — NODE TREE

### 26.1 Nodo Bot (CharacterBody3D)

```
npc.tscn:
EnemyBot (CharacterBody3D)
├── CollisionShape3D
├── NavigationAgent3D (Godot nativo)
├── AreaVision (Area3D) — zona de detección visual
├── RaycastVision (RayCast3D) — línea de visión
├── Head (Node3D) — punto de origen para raycast visual
│   └── WeaponPivot (Node3D) — punto de anclaje del arma (animado)
│       └── Weapon (Weapon) — instancia del arma actual
├── AI (Node)
│   ├── PerceptionSystem (Node)
│   │   └── SightCone (Area3D) — opcional, cono de visión
│   ├── MemorySystem (Node)
│   ├── DecisionSystem (Node)
│   │   ├── StateMachine (Node)
│   │   │   ├── State_StartUp (BotState)
│   │   │   ├── State_Roaming (BotState)
│   │   │   ├── State_Wandering (BotState)
│   │   │   ├── State_Attacking (BotState) — padre virtual
│   │   │   │   ├── State_TacticalMove (BotState)
│   │   │   │   ├── State_Charging (BotState)
│   │   │   │   ├── State_RangedAttack (BotState)
│   │   │   │   └── State_Retreating (BotState)
│   │   │   ├── State_Hunting (BotState)
│   │   │   ├── State_StakeOut (BotState)
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
│   │   └── WeaponAIProfile (Resource) — vinculado
│   └── HealthSystem (Node)
├── BotProfile (Resource) — asignado por SkillSystem al spawn
└── TeamIdentifier (Node) — color de equipo, rol visual
```

### 26.2 Sistemas Globales

```
Mapa (escena del nivel):
├── NavigationRegion3D — navmesh del mapa
├── NavigationSystem (Node) — gestor de navegación + puntos semánticos
├── ObjectiveSystem (Node) — gestor de objetivos (GameMode concreto)
│   └── OrderSystem (Node) — gestor de órdenes
├── TeamCoordinator (Node) — coordinación entre bots del equipo
├── SpawnPoints (Node) — puntos de spawn de jugadores y bots
│   ├── PlayerSpawn (Marker3D)
│   └── BotSpawn (Marker3D)
└── SemanticPoints (Node)
    ├── AmbushPoint01 (Marker3D) — con script SemanticPoint.gd
    ├── AmbushPoint02 (Marker3D)
    ├── DefensePointRed (Marker3D)
    ├── DefensePointBlue (Marker3D)
    ├── AlternatePathRed (Marker3D)
    └── ...

Autoloads:
├── MatchManager (Autoload) — gestión de partida
├── GameState (Autoload) — estado global
├── SkillSystem (Autoload) — perfiles de bots
├── BotSignalBus (Autoload) — bus de señales globales
└── PickupManager (Autoload) — gestión de items recogibles
```

---

## 27. BUGS DE UT99 Y CÓMO SE EVITAN

### 27.1 Bugs de UT99 Identificados y Corregidos

| # | Bug de UT99 | Síntoma | Corrección en esta arquitectura |
|---|-------------|---------|-------------------------------|
| 1 | **OldEnemy sobrescrito con candidatos rechazados** | Se pierde el contexto del enemigo anterior silenciosamente | `enemy_history` solo se actualiza con cambios reales de enemigo. Push solo cuando hay cambio confirmado. |
| 2 | **Salud promediada en RelativeStrength** | Enemigo con 1 HP se ve como saludable (promedia 1+100=50.5) | Usar salud REAL del enemigo. `effective_health` = health + armor × 0.6 |
| 3 | **Cortes duros de distancia (800, 1200)** | 799 vs 801 unidades es diferencia drástica | Curvas continuas con `Curve` Resource de Godot. Sin bordes. |
| 4 | **Corte duro de salud (< 20)** | 19 vs 20 HP es diferencia drástica | Función continua `1.0 - health/max_health`. Sin bordes. |
| 5 | **Sleep() en StakeOut** | Bot no responde a daño ni estímulos durante el sueño | Timer no-bloqueante. El bot sigue procesando señales. |
| 6 | **StakeOut sin timeout para snipers** | Sniper espera indefinidamente en StakeOut | Timeout global incluso para snipers. Tiempo máximo configurable. |
| 7 | **FindViewSpot dirección duplicada** | Ambas ramas del if hacen lo mismo (Location - 2.5*Y*CollisionRadius) | Probar izquierda Y derecha realmente. No duplicar código. |
| 8 | **numHuntPaths por intentos** | Mapas pequeños: bot abandona prematuramente | Contar tiempo REAL en estado, no intentos de pathfinding. |
| 9 | **bKamikaze prematuro en Retreating** | Bot asume que no hay recursos si están fuera de radio fijo | Radio basado en distancia al enemigo. Verificar reachabilidad real con NavigationServer3D. |
| 10 | **Loop ChooseAttackMode→WhatToDoNext** | Loop infinito de transiciones si no hay enemigo válido | Validación de precondiciones. `can_enter_state()` evita transiciones inválidas. |
| 11 | **Ventaja de altura invertida** | UT99 considera que estar más bajo es mejor (compare -= 0.15) | Altura contextual: estar más alto es ventaja. WeaponAIProfile.height_advantage define el factor. |
| 12 | **Arma sin munición evaluada como poderosa** | RateSelf no considera munición | `effective_dps()` incluye `ammo_ratio`. Munición baja → DPS reducido. |
| 13 | **Retirada hacia el enemigo** | Bot corre hacia el enemigo por un pickup que está detrás | Filtrar pickups en hemisferio OPUESTO al enemigo. RetreatPlanner prioriza dirección segura. |
| 14 | **Timer de retirada reseteado con sightings** | Si enemigo aparece/desaparece, bot huye indefinidamente | Timer con histéresis: cada sighting extiende 2s, máximo 20s. No reseteo completo. |
| 15 | **StakeOut apuntando a pared** | FindNewStakeOutDir elige punto que mira a pared | Validar que el vector dirección no intersecte geometría. Elegir segundo mejor si es necesario. |

### 27.2 Bugs de Arquitectura Actual (Proyecto) y Cómo se Corrigen

| # | Problema Actual | Corrección |
|---|-----------------|------------|
| 1 | Múltiples escritores de `velocity` (NavigationSystem, BotBrain, BehaviorCombat, NpcBase, gravedad) | MovementSystem es el ÚNICO escritor de velocity. Todos los demás sistemas se comunican via MovementCommand. |
| 2 | Múltiples escritores de `target_enemy` (PerceptionSystem sugiere, NpcBase escribe, BotBrain lee) | DecisionSystem es el ÚNICO escritor de target_entity. PerceptionSystem solo escribe sensor_data. |
| 3 | NpcBase como clase Dios (1112 líneas) | Dividir en sistemas especializados. NpcBase solo orquesta la ejecución en orden. |
| 4 | NavigationSystem hinchado (1399 líneas) | NavigationSystem solo gestiona navmesh + puntos semánticos. MovementSystem maneja movimiento y stuck. |
| 5 | Behaviors escriben velocity directamente | Behaviors son estados de FSM. Escriben movement_command. Nunca velocity. |
| 6 | Sin FSM real (prioridades planas sin persistencia) | FSM jerárquica con estados como Nodos. Prioridades, enter()/exit(), transiciones validadas. |
| 7 | team_ai.gd vacío | TeamCoordinator completo con asignación de roles, coordinación de ataques, solicitud de ayuda. |
| 8 | Sin sistema de órdenes (SetOrders, líder→seguidor) | OrderSystem con RealOrders/Orders, jerarquía líder→seguidor, tipos ATTACK/DEFEND/FOLLOW/HOLD/POINT/FREELANCE. |
| 9 | Sin ambush/defense points | SemanticPoints con jerarquía AMBUSH/DEFENSE/ALTERNATE/LIFT/SNIPER/ITEM. Integrados con NavigationServer3D. |
| 10 | Sin perfiles de IA en armas (rate_self, suggest_style, ai_rating) | WeaponAIProfile Resource con effective_dps, situational_rating, refire_rate, lead_target, aim_error. |

---

## 28. PLAN DE MIGRACIÓN

### Fase 0: Auditoría (COMPLETADA) ✓
- Mapear todos los escritores de velocity → ✓
- Mapear todos los escritores de target_enemy → ✓
- Documento de arquitectura actual → ✓
- Ingeniería inversa de UT99 → ✓
- Análisis de modernización → ✓

### Fase 1: Resources y Data Types (1-2 días)
1. Crear `BotProfile.gd` (Resource) — extraer de npc_base.gd
2. Crear `WeaponAIProfile.gd` (Resource) — nuevo
3. Crear `SemanticPoint.gd` (Resource) — nuevo
4. Crear `MovementCommand.gd` (Resource) — refactorizar desde DecisionContext
5. Crear `CombatCommand.gd` (Resource) — refactorizar desde DecisionContext
6. Crear `Objective.gd` (Resource) — nuevo
7. Crear `Order.gd` (Resource) — nuevo
8. Crear `BotState.gd` (base class para estados de FSM) — nuevo
9. Crear `TacticalRole.gd` (RefCounted) — nuevo
10. Crear `VoiceType.gd` (Resource) — nuevo

### Fase 2: MovementSystem (3-5 días)
1. Crear nuevo `MovementSystem.gd` como Nodo independiente
2. MovementSystem es el ÚNICO escritor de velocity
3. MovementSystem recibe MovementCommand (no escribe en NpcBase.velocity directamente)
4. MovementSystem usa NavigationAgent3D nativo de Godot
5. StuckDetector es interno a MovementSystem y SOLO emite señales
6. AutoJumper es interno a MovementSystem y SOLO emite señales
7. MovementSystem NO cambia destino por su cuenta
8. MovementSystem NO cambia target_entity por su cuenta
9. Implementar evitación entre NPCs

### Fase 3: PerceptionSystem + MemorySystem (2-3 días)
1. Consolidar PerceptionSystem existente (ya está modular)
2. PerceptionSystem SOLO escribe sensor_data (no target_enemy en NpcBase)
3. Agregar NoiseEvent y PositionRecord a sensor_data
4. Consolidar MemorySystem existente (ya está modular)
5. Agregar tipos de memoria faltantes (DAMAGE_SOURCE, OBJECTIVE_PROGRESS, ENEMY_HISTORY)
6. Conectar señales Perception → Memory
7. Implementar merge por cercanía y decay de confidence

### Fase 4: DecisionSystem + FSM (5-7 días)
1. Crear DecisionSystem con StateMachine
2. Implementar BotState base con enter()/execute()/exit()/evaluate_transitions()
3. Implementar todos los estados: StartUp, Roaming, Wandering, Attacking (padre), TacticalMove, Charging, RangedAttack, Retreating, Hunting, StakeOut, Holding, TakingHit, Falling
4. DecisionSystem es el ÚNICO escritor de: target_entity, movement_command, combat_command, focus_point
5. Implementar TargetEvaluator (AssessThreat modernizado con curvas)
6. Implementar CommandValidator
7. Implementar RelativeStrength modernizado (poder efectivo real)

### Fase 5: CombatSystem (3-5 días)
1. Crear nuevo `CombatSystem.gd` como Nodo independiente
2. CombatSystem es el ÚNICO escritor de aim_rotation
3. CombatSystem NUNCA escribe velocity
4. CombatSystem usa WeaponAIProfile para decisiones de puntería
5. Implementar AdjustAim con lead_target, aim_error, splash
6. Implementar ShouldFire con refire_rate
7. CombatSystem SOLO solicita dodge (wants_dodge) — DecisionSystem decide si concede

### Fase 6: WeaponSystem + WeaponAIProfile (2-3 días)
1. Extraer WeaponAIProfile de Weapon.gd a Resource independiente
2. WeaponSystem expone effective_dps(distance, ammo) para RelativeStrength
3. WeaponSystem expone situational_rating(distance, context) para ChooseAttackMode
4. Integrar refire_rate, lead_target, aim_error en el cálculo de puntería
5. Implementar SwitchToBestWeapon con rating contextual

### Fase 7: ObjectiveSystem + OrderSystem (4-5 días)
1. Implementar ObjectiveSystem como base de GameMode
2. Implementar OrderSystem como subsistema de ObjectiveSystem
3. Separación RealOrders vs CurrentOrders
4. Jerarquía líder→seguidor
5. Implementar GameMode_Deathmatch, GameMode_TeamDeathmatch
6. Implementar FindSpecialAttractionFor() por GameMode
7. Implementar GameThreatAdd() por GameMode

### Fase 8: Navegación Semántica (3-4 días)
1. Implementar SemanticPoints como Resources
2. Colocar puntos en mapas existentes (Ambush, Defense, Alternate, Sniper, Lift)
3. Integrar con NavigationServer3D para costos dinámicos
4. Sistema de AlternatePath para CTF
5. Sistema de puntos de defensa por equipo y prioridad
6. Implementar SpecialCost (costos contextuales por estado del bot)

### Fase 9: SkillSystem + Dificultad Dinámica (2-3 días)
1. Implementar SkillSystem como Autoload
2. Implementar BotProfile con 32 slots (como UT99)
3. Algoritmo AdjustSkill con persistencia entre partidas
4. InitializeSkill con dificultad base + modificadores por mapa/GameMode
5. Tabla de impacto de skill en comportamiento

### Fase 10: TeamCoordinator (3-4 días)
1. Asignación dinámica de roles (DEFENDER, ASSAULT, FLANKER, PATROLLER)
2. Coordinación de ataques en equipo (evitar saturación)
3. Sistema de solicitud de ayuda entre bots
4. Sistema de liderazgo (elección, sucesión, bLeading)
5. Integración con TacticalRole de cada bot

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
3. Calibrar TacticalRole matrix para cada GameMode
4. Playtesting con diferentes GameModes (DM, TDM, CTF, DOM, AS)
5. Ajustar SemanticPoints en mapas para mejor flujo táctico
6. Balance de dificultad dinámica (AdjustSkill)
7. Verificar que los bugs de UT99 listados en sección 27 NO se reproduzcan

---

## 29. GLOSARIO

| Término | Significado |
|---------|------------|
| **FSM** | Finite State Machine. Máquina de estados con transiciones explícitas entre estados. |
| **Command** | Resource transitorio que un sistema escribe y otro lee (MovementCommand, CombatCommand). |
| **Signal** | Evento de Godot. Un sistema emite, otro escucha. Comunicación desacoplada. |
| **Data Owner** | Único sistema que puede escribir una variable específica (Single Writer Principle). |
| **SWP** | Single Writer Principle. Cada variable tiene exactamente un escritor. |
| **CQS** | Command-Query Separation. Sistemas se comunican por comandos (escritura) y consultas (lectura). |
| **SemanticPoint** | Punto de navegación con significado táctico (emboscada, defensa, ruta alterna, ascensor, sniper). |
| **Objective** | Meta que el GameMode asigna. Los bots solo leen objectives, nunca los escriben. |
| **Order** | Instrucción de equipo (FreeLance, Attack, Defend, Follow, Hold, Point). |
| **RealOrders** | Orden persistente original. El bot puede desviarse temporalmente pero siempre vuelve. |
| **CurrentOrders** | Orden actual (puede cambiar temporalmente). Cuando se completa, se restaura RealOrders. |
| **TacticalRole** | Perfil de comportamiento táctico (DEFENDER, ASSAULT, FLANKER, PATROLLER). Define cómo se mueve y pelea. |
| **BotProfile** | Resource con identidad, habilidad y personalidad del bot. Estático por partida. |
| **WeaponAIProfile** | Resource con datos de IA para un arma (rating, rango, splash, predicción, cadencia). |
| **Engagement** | Estado de combate activo contra un enemigo específico. |
| **TacticalMove** | Movimiento evasivo en combate (strafe, retroceso, cobertura). |
| **Strafing** | Movimiento lateral manteniendo el frente hacia el enemigo. |
| **SplashDamage** | Daño por área. Cambia la puntería (apuntar al suelo, no al cuerpo). |
| **LeadTarget** | Predecir posición futura del enemigo para acertar con proyectiles. |
| **RefireRate** | Probabilidad de seguir disparando después de cada disparo. Varía por skill y arma. |
| **LOS** | Line of Sight. Línea de visión sin obstáculos entre dos puntos. |
| **Acquisition** | Estado de transición al detectar un enemigo (UT99: el bot "adquiere" al enemigo). |
| **StakeOut** | Esperar en la última posición conocida del enemigo. |
| **bDevious** | Flag de UT99: el bot usa tácticas engañosas (fintas, rutas falsas, flanqueos). Solo ELITE. |
| **bKamikaze** | Flag de UT99: el bot se rinde y carga sin importar las consecuencias. |
| **bGathering** | Flag de UT99: el bot está yendo a recoger un item y no debe distraerse. |
| **bLeading** | Flag de UT99: este bot es líder y otros bots le siguen. |
| **SpecialHandling** | Hook de navegación de UT99: un nodo intercepta la ruta del bot (ej: ascensor). |
| **SpecialCost** | Costo dinámico de un nodo de navegación según contexto (salud, bandera, equipo). |
| **AdjustSkill** | Algoritmo de dificultad dinámica: sube skill si pierde contra jugador, baja si gana. |
| **RelativeStrength** | Comparación de poder relativo entre dos entidades (-1 a 1). |
| **AssessThreat** | Evaluación multi-factor de nivel de amenaza de un candidato. |
| **FindSpecialAttraction** | Hook de GameMode: qué debe hacer este bot específicamente (Strategy Pattern). |
| **RateSelf** | Método de arma que devuelve su efectividad en el contexto actual. |
| **SupportingPlayer** | A qué jugador/bot está apoyando este bot. |
| **ContinueStakeOut** | Decisión de UT99: ¿seguir esperando o abandonar el punto de emboscada? |
| **RecoverEnemy** | Comportamiento de UT99: asomarse, disparar rápido, cubrirse. |
| **GiveUpTactical** | Decisión de UT99: abandonar TacticalMove si no hay progreso. |
| **TryToward** | Función de UT99: intentar moverse hacia un punto, con verificación de reachabilidad. |
| **bMustHunt** | Flag de UT99: forzar Hunting aunque las condiciones normales digan StakeOut. |
| **Hysteresis** | Técnica de control: el timer de retirada se extiende pero no se resetea completamente. |
| **Choke Point** | Punto estrecho del mapa donde el combate es inevitable. |
| **Flanking** | Estrategia de ataque por los lados o por detrás del enemigo. |
| **Pincer** | Ataque coordinado desde dos frentes opuestos. |

---

## APÉNDICE A: COMPARACIÓN CON SISTEMA ACTUAL

| Sistema Actual (problema) | Sistema Nuevo (solución) |
|--------------------------|-------------------------|
| Múltiples escritores velocity | MovementSystem es ÚNICO escritor |
| NpcBase: 1112 líneas (clase dios) | 12 sistemas especializados (~100-200 líneas c/u) |
| Behaviors escriben velocity | Estados FSM escriben MovementCommand |
| Sin FSM real | FSM jerárquica con enter()/exit()/transiciones |
| team_ai.gd vacío | TeamCoordinator completo |
| Sin órdenes (SetOrders) | OrderSystem con RealOrders/Orders |
| Sin puntos semánticos | SemanticPoints + jerarquía completa |
| Sin perfiles de arma IA | WeaponAIProfile Resource |
| NavigationSystem escribe bots | NavigationSystem es solo servicio |
| Sin dificultad dinámica | AdjustSkill + persistencia |
| Sin sistema de voces | VoiceType Resource |
| Sin memoria de daño | MemorySystem con DAMAGE_SOURCE |

---

## APÉNDICE B: COMPARACIÓN UT99 ↔ GODOT 4.7

| Concepto UT99 | Equivalente Godot 4.7 | Notas |
|--------------|----------------------|-------|
| Pawn | CharacterBody3D | Base física del personaje |
| Bot | DecisionSystem + FSM | La IA, no el cuerpo |
| NavigationPoint | SemanticPoint | Ahora con significado táctico |
| ReachSpec | NavigationServer3D | Pathfinding nativo de Godot |
| State (labels) | BotState (Nodes) | Estados como nodos hijos de StateMachine |
| MoveToward | NavigationAgent3D | Movimiento con pathfinding |
| LineOfSightTo | RayCast3D | Línea de visión desde Head |
| Enemy | target_entity | Propiedad de DecisionSystem |
| Orders | OrderSystem | Con separación RealOrders |
| Skill | BotProfile.skill | 0-7, con perfil completo |
| CombatStyle | BotProfile.combat_style | -1 a 1 |
| RateSelf() | WeaponAIProfile.effective_dps() | DPS contextual |
| RefireRate | WeaponAIProfile.refire_rate | 0.0-1.0 |
| SpecialHandling | SemanticPoint (LIFT) | Hooks de navegación |
| SpecialCost | NavigationSystem.get_adjusted_cost() | Costos dinámicos |
| bNovice | skill < 2 | Flag implícito en el skill |
| GameInfo | ObjectiveSystem | Objetivos del modo de juego |
| TeamAI | TeamCoordinator | Coordinación entre bots |
| ChallengeBotInfo | SkillSystem | Perfiles y dificultad |
| AmbushPoint | SemanticPoint (AMBUSH) | Punto de emboscada con lookdir |
| DefensePoint | SemanticPoint (DEFENSE) | Punto de defensa por equipo |
| AlternatePath | SemanticPoint (ALTERNATE) | Ruta alternativa con weight |
| LiftCenter/LiftExit | SemanticPoint (LIFT) | Ascensores navegables |
| FindBestInventoryPath | GoalEvaluator | Evaluación de objetivos multi-factor |
| bDevious | BotProfile.b_devious | Tácticas engañosas (solo ELITE) |
| bLeading | TeamCoordinator.leaders | Liderazgo de equipo |
| PlayerReplicationInfo | PlayerData | Datos del jugador |
| BotReplicationInfo | OrderSystem.orders | Órdenes replicadas |
| GameReplicationInfo | GameState | Estado de partida replicado |

---

> **Este documento constituye la especificación oficial y vinculante del proyecto.**
> Todo el código futuro debe adherirse a las reglas, estructuras y algoritmos aquí definidos.
> Cualquier desviación debe ser aprobada mediante actualización de este documento.
>
> **Próximo paso:** Implementar Fase 1 (Resources y Data Types) según el plan de migración.
