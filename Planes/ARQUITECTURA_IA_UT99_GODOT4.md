# ARQUITECTURA DE IA INSPIRADA EN UNREAL TOURNAMENT 1999 PARA GODOT 4

## Diagnóstico de la arquitectura actual (problemas identificados)

| Problema | Gravedad | Descripción |
|----------|----------|-------------|
| Múltiples escritores de `velocity` | CRÍTICO | NavigationSystem, BotBrain, BehaviorCombat, NpcBase y gravedad escriben `velocity` sin coordinación |
| Múltiples escritores de `target_enemy` | CRÍTICO | PerceptionSystem sugiere, NpcBase escribe, BotBrain lee — origen difuso |
| NpcBase como clase Dios | ALTO | 1112 líneas mezclando movimiento, combate, percepción, armas, navegación |
| NavigationSystem hinchado | ALTO | 1399 líneas: pathfinding + stuck + auto-jump + avoidance + steering |
| Behaviors escriben en velocity directamente | ALTO | BehaviorComast salta escribiendo `brain.bot.velocity.y = 5.0` |
| Sin FSM real | MEDIO | Sistema de prioridades plano sin persistencia de estado |
| Sin perfiles de IA en armas | MEDIO | Weapon no tiene `rate_self()`, `suggest_style()`, `ai_rating` |
| team_ai.gd vacío | ALTO | No hay GameMode que impulse objetivos de IA |
| Sin sistema de órdenes | MEDIO | No hay `SetOrders()` ni jerarquía líder→seguidor |
| Sin ambush/defense points | MEDIO | No hay puntos tácticos en el mapa |

---

## PARTE 1: SISTEMAS EXISTENTES Y SUS RESPONSABILIDADES

### Sistema 1: PerceptionSystem (Nodo en Bot)

**Responsabilidad única:** Producir datos sensoriales crudos del mundo. NO decide qué hacer con ellos.

**Qué datos produce:**
- Lista de entidades visibles (`visible_entities: Array[Sighting]`)
- Lista de ruidos escuchados (`heard_noises: Array[NoiseEvent]`)
- Lista de amenazas detectadas (`threats: Array[ThreatAssessment]`)
- Última posición conocida de cada entidad
- Línea de visión calculada (raycasts)

**Propietario de:** `sensor_data` (sightings, noises, threats)

**Solo lectura de:** Posiciones globales, collision shapes, NavigationAgents ajenos

**NUNCA escribe:** `velocity`, `target`, `enemy`, `movement_intent`, `combat_intent`

**Eventos que emite:**
- `entity_detected(entity_id: int, position: Vector3, confidence: float)`
- `entity_lost(entity_id: int, last_known_position: Vector3)`
- `threat_assessed(entity_id: int, threat_level: float)`
- `noise_heard(position: Vector3, loudness: float, source: Node)`

---

### Sistema 2: MemorySystem (Nodo en Bot)

**Responsabilidad única:** Almacenar, consolidar y hacer expirar información a lo largo del tiempo.

**Propietario de:** `memory_store` (diccionario de recuerdos con timestamp)

**Solo lectura de:** `sensor_data` (de PerceptionSystem)

**NUNCA escribe:** ningún campo que no sea su propio `memory_store`

**Eventos que emite:**
- `memory_updated(memory_type: String, entity_id: int)`
- `memory_expired(memory_type: String, entity_id: int)`

**Reglas de propiedad:**
- MemorySystem escribe TODOS los datos de memoria
- Ningún otro sistema puede escribir en `memory_store`
- Cualquier sistema puede leer memoria (pero solo a través de métodos públicos query)

---

### Sistema 3: DecisionSystem (Nodo en Bot) — EL FSM

**Responsabilidad única:** Tomar decisiones. Es el único sistema que decide QUÉ hacer.

**Propietario de:**
- `current_state: State` (el estado activo de la FSM)
- `target_entity: Node3D` (el enemigo/objetivo actual)
- `movement_command: MovementCommand` (qué tipo de movimiento, hacia dónde)
- `combat_command: CombatCommand` (disparar o no, a quién apuntar)
- `focus_point: Vector3` (punto de interés visual)

**Solo lectura de:**
- `memory_store` (MemorySystem)
- `sensor_data` (PerceptionSystem)
- `objectives` (GameMode)
- `weapon_status` (WeaponSystem)
- `health_status` (HealthSystem)
- `navigation_query_results` (NavigationSystem)

**NUNCA escribe:**
- `velocity` (es propiedad de MovementSystem)
- `navigation_path` (es propiedad de NavigationSystem)
- `weapon_state` (es propiedad de WeaponSystem)
- `memory_store` (es propiedad de MemorySystem)

**Eventos que emite:**
- `state_changed(old_state: State, new_state: State)`
- `command_issued(movement: MovementCommand)`
- `command_issued(combat: CombatCommand)`
- `target_selected(entity_id: int)`
- `objective_updated(objective_id: String)`

---

### Sistema 4: MovementSystem (Nodo en Bot)

**Responsabilidad única:** Ejecutar movimiento. Traduce comandos de movimiento en velocity.

**Propietario de:**
- `velocity: Vector3`
- `navigation_path: Array[Vector3]`
- `stuck_state: StuckState`
- `current_speed: float`
- `movement_mode: MovementMode`

**Solo lectura de:**
- `movement_command` (de DecisionSystem)
- NavigationAgent3D (Godot interno)
- Collision state (move_and_slide)

**NUNCA escribe:**
- `target_entity` (propiedad de DecisionSystem)
- `combat_command` (propiedad de DecisionSystem)
- `weapon_state` (propiedad de WeaponSystem)
- `aim_rotation` (propiedad de CombatSystem)

**Regla fundamental:** MovementSystem recibe UN MovementCommand por frame, ejecuta exactamente ese comando, y produce velocity.

**Eventos que emite:**
- `destination_reached(position: Vector3)`
- `path_blocked(remaining_distance: float)`
- `stuck_detected(phase: int)`
- `stuck_resolved()`
- `movement_interrupted(cause: String)`

---

### Sistema 5: CombatSystem (Nodo en Bot)

**Responsabilidad única:** Manejar combate. Ejecuta comandos de combate, maneja puntería y selección de modo de fuego.

**Propietario de:**
- `aim_rotation: Quaternion`
- `preferred_fire_mode: FireMode` (primario/alterno)
- `dodge_state: DodgeState`
- `current_target_position: Vector3`
- `engagement_analysis: EngagementData`

**Solo lectura de:**
- `combat_command` (de DecisionSystem)
- `weapon_status` (de WeaponSystem)
- `target_entity` (de DecisionSystem)

**NUNCA escribe:**
- `velocity` (propiedad de MovementSystem)
- `movement_command` (propiedad de DecisionSystem)
- `navigation_path` (propiedad de NavigationSystem)

**Eventos que emite:**
- `weapon_fired(hit_result: Array)`
- `target_in_range(entity_id: int, distance: float)`
- `target_lost(entity_id: int)`
- `out_of_ammo(weapon_type: String)`
- `dodge_performed(direction: Vector3)`
- `aim_updated(new_rotation: Quaternion)`

---

### Sistema 6: WeaponSystem (Nodo en Bot, o Resource)

**Responsabilidad única:** Gestionar estado del arma, cadencia, munición, recarga. Proveer rating de IA.

**Propietario de:**
- `weapon_status: WeaponStatus` (tipo, munición, cadencia)
- `ammo_count: int`
- `reserve_ammo: int`
- `cooldown_timer: float`
- `reload_state: ReloadState`
- `ai_profile: WeaponAIProfile` (Resource)

**Solo lectura de:**
- `combat_command.fire_request` (de CombatSystem)

**NUNCA escribe:**
- `velocity`
- `target_entity`
- `movement_command`
- `aim_rotation`

**WeaponAIProfile (Resource):** Cada arma tiene un Resource que describe:
- `ai_rating: float` (0.0-1.0) — poder general
- `preferred_range: Vector2` (min, max distancia óptima)
- `splash_damage: bool` — si debe apuntar al suelo
- `suggested_attack_style: float` (-1.0 defensivo, +1.0 agresivo)
- `suggested_defense_style: float`
- `lead_target: bool` — si debe predecir posición
- `refire_rate: float` — probabilidad de seguir disparando
- `prefers_alt_fire: bool`
- `aim_error_multiplier: float` — multiplicador de error base

**Eventos que emite:**
- `weapon_ready()`
- `weapon_empty()`
- `reload_started(duration: float)`
- `reload_completed()`
- `ammo_changed(current: int, reserve: int)`

---

### Sistema 7: HealthSystem (Nodo en Bot)

**Responsabilidad única:** Gestionar salud, daño, muerte.

**Propietario de:**
- `health: float`
- `max_health: float`
- `armor: float`
- `damage_history: Array[DamageEvent]`
- `is_alive: bool`
- `last_damage_time: float`
- `last_attacker: Node3D`

**NUNCA escribe:** ningún campo fuera de salud/daño.

**Eventos que emite:**
- `damage_taken(amount: float, attacker: Node3D, type: String)`
- `health_changed(new_health: float)`
- `death(attacker: Node3D)`
- `armor_depleted()`

---

### Sistema 8: NavigationSystem (Nodo Global o en Mapa)

**Responsabilidad única:** Gestionar el grafo de navegación. NO decide qué ruta tomar. NO mueve al bot.

**Propietario de:**
- `navigation_mesh: NavigationMesh`
- `semantic_points: Array[SemanticPoint]` (AmbushPoint, DefensePoint, etc.)
- `navigation_region: NavigationRegion3D`

**Solo lectura de:** La geometría del mapa.

**NUNCA escribe:**
- `velocity`
- `target_entity`
- `movement_command`
- `combat_command`
- `bot_state`

**Regla fundamental:** NavigationSystem es un proveedor de servicios. Los bots le preguntan "dame un camino de A a B" y él responde. NO orquesta movimiento.

**SemanticPoint (Resource):** Un nodo de navegación con significado táctico:
- `position: Vector3`
- `point_type: Enum` (PATH, AMBUSH, DEFENSE, ALTERNATE, LIFT, ITEM)
- `team: int` (Dueño del punto, -1 para neutral)
- `priority: int` (Prioridad de selección)
- `look_direction: Vector3` (dirección de mirada para ambush)
- `sight_radius: float` (radio de visión desde este punto)
- `extra_cost: float` (costo adicional para pathfinding)
- `tags: Array[String]` (etiquetas para búsqueda)
- `connections: Array[SemanticPointLink]`

---

### Sistema 9: ObjectiveSystem (GameMode — Autoload o Nodo Raíz)

**Responsabilidad única:** Definir los objetivos del equipo y del bot. NO dice cómo cumplirlos.

**Propietario de:**
- `team_objectives: Array[Objective]`
- `bot_orders: Dictionary` (orden por bot)
- `team_scores: Array[int]`
- `match_phase: MatchPhase`

**Solo lectura de:** Estado global de la partida.

**NUNCA escribe:**
- `target_entity`
- `movement_command`
- `combat_command`
- `velocity`

**Objective (Resource):**
- `objective_id: String`
- `objective_type: Enum` (CAPTURE, DEFEND, ATTACK, RETURN, ESCORT, HOLD)
- `target_node: NodePath`
- `position: Vector3`
- `team: int`
- `priority: float`
- `completion_radius: float`
- `is_completed: bool`
- `fallback_objective: String`

**Eventos que emite:**
- `objective_updated(objective: Objective, bot_id: int)`
- `objective_completed(objective_id: String, team: int)`
- `match_phase_changed(new_phase: MatchPhase)`
- `orders_changed(bot_id: int, new_orders: String, target: NodePath)`

---

### Sistema 10: OrderSystem (Subsistema de ObjectiveSystem)

**Responsabilidad única:** Gestionar órdenes por bot: FreeLance, Attack, Defend, Follow, Hold.

**Propietario de:**
- `current_orders: Dictionary[bot_id, Order]`
- `real_orders: Dictionary[bot_id, Order]` (orden persistente original)
- `leader: Dictionary[team_id, bot_id]`

**Tipos de órdenes (estilo UT99):**
- `FREELANCE` — sin órdenes específicas, el bot decide
- `ATTACK` — atacar objetivo del equipo
- `DEFEND` — defender un punto específico
- `FOLLOW` — seguir a un líder
- `HOLD` — mantener posición fija
- `POINT` — apoyar a un jugador específico

**Separación Orders vs RealOrders (tomado de UT99):**
- `real_orders` es la orden original persistente
- `current_orders` puede cambiar temporalmente (ej: "vi un enemigo, lo persigo")
- Cuando el bot termina su acción temporal, vuelve a `real_orders`

---

### Sistema 11: SkillSystem (Resource Global)

**Responsabilidad única:** Definir perfiles de habilidad y personalidad de cada bot.

**Propietario de:**
- `bot_profiles: Dictionary[bot_id, BotProfile]`

**BotProfile (Resource):**
- `bot_name: String`
- `skill: int` (0-7)
- `accuracy: float` (0.0-1.0)
- `combat_style: float` (-1.0 sniper, +1.0 agresivo)
- `aggressiveness: float` (0.0-1.0)
- `alertness: float` (-1.0 distraído, +1.0 alerta)
- `camping_rate: float` (0.0-1.0, propensión a acampar)
- `strafing_ability: float` (0.0-1.0)
- `favorite_weapon: String`
- `jumpy: bool` (propensión a saltar)
- `lead_target: bool`
- `b_devious: bool` (tácticas engañosas)
- `voice_type: String`
- `team: int`
- `difficulty_tier: String` (novice/standard/veteran/elite)

**Algoritmo de dificultad dinámica (tomado de ChallengeBotInfo.AdjustSkill):**
```
Si el bot GANA contra el jugador → baja dificultad
Si el bot PIERDE contra el jugador → sube dificultad
Factor de ajuste: 2/min(partidas_jugadas, 10)
```

---

## PARTE 2: DIAGRAMA DE DEPENDENCIAS

```
┌──────────────────────────────────────────────────────────────┐
│                    OBJECTIVE SYSTEM (GameMode)                │
│  Propietario: objectives, orders, scores, match_phase        │
│  NO lee nada de los bots                                     │
└──────────────┬───────────────────────────────────────────────┘
               │ Escribe: objectives (solo lectura para bots)
               │ Escribe: orders (solo lectura para bots)
               ▼
┌──────────────────────────────────────────────────────────────┐
│                     DECISION SYSTEM (FSM)                    │
│  Propietario: current_state, target_entity,                  │
│               movement_command, combat_command, focus_point   │
│                                                              │
│  Lee DE: PerceptionSystem (sensor_data)                      │
│  Lee DE: MemorySystem (memory_store)                         │
│  Lee DE: ObjectiveSystem (objectives, orders)                │
│  Lee DE: WeaponSystem (weapon_status, ai_profile)            │
│  Lee DE: HealthSystem (health, last_damage)                  │
│  Lee DE: MovementSystem (stuck_state, position)              │
│                                                              │
│  ESCRIBE: movement_command → lo lee MovementSystem           │
│  ESCRIBE: combat_command  → lo lee CombatSystem              │
│  ESCRIBE: target_entity   → lo lee CombatSystem              │
└─────┬───────────────┬───────────────┬────────────────────────┘
      │               │               │
      ▼               ▼               ▼
┌──────────┐   ┌──────────┐   ┌──────────────┐
│MOVEMENT  │   │ COMBAT   │   │ PERCEPTION   │
│SYSTEM    │   │ SYSTEM   │   │ SYSTEM       │
│          │   │          │   │              │
│Prop:     │   │Prop:     │   │Prop:         │
│ velocity │   │ aim_rot  │   │ sensor_data  │
│ path     │   │ dodge    │   │              │
│ stuck    │   │ fireMode │   │No escribe    │
│          │   │          │   │ nada fuera   │
│Lee:      │   │Lee:      │   │              │
│ move_cmd │   │combat_cmd│   │              │
│ nav_agent│   │weapon_st │   │              │
│          │   │target_ent│   │              │
│NO escribe│   │NO escribe│   │              │
│ combat   │   │ velocity │   │              │
│ target   │   │ movement │   │              │
└────┬─────┘   └────┬─────┘   └──────┬───────┘
     │              │                │
     │              ▼                │
     │   ┌──────────────────┐        │
     │   │  WEAPON SYSTEM   │        │
     │   │  Prop: ammo,     │        │
     │   │  cooldown, state │        │
     │   │  ai_profile(R)   │        │
     │   │  Lee: fire_request│       │
     │   └──────────────────┘        │
     │                               │
     ▼                               ▼
┌────────────────────────────────────────┐
│          HEALTH SYSTEM                 │
│  Prop: health, armor, damage_history   │
│  Lee: nada (solo recibe daño)          │
└────────────────────────────────────────┘

SISTEMAS GLOBALES (NO en el bot):
┌──────────────────────┐  ┌──────────────────────┐
│  NAVIGATION SYSTEM   │  │  SKILL SYSTEM         │
│  (en el mapa)        │  │  (Resource global)    │
│  Prop: navmesh,      │  │  Prop: bot_profiles   │
│        semantic_pts   │  │                       │
│  Servicio: pathfind  │  │  Servicio: get_profile │
│  NO escribe bots     │  │  NO escribe bots      │
└──────────────────────┘  └──────────────────────┘
```

---

## PARTE 3: FLUJO COMPLETO DE UN FRAME

```
Frame N (delta = 1/60)

FASE 0: GLOBAL SYSTEMS (orden fijo)
├── NavigationSystem.process(delta)
│   └── Solo actualiza estructuras internas si cambió el mapa
│   └── NO toca ningún bot
├── ObjectiveSystem.process(delta)
│   └── Verifica estado de objetivos
│   └── Emite signals si cambian

FASE 1: SENSORES (por cada bot)
├── PerceptionSystem.update(delta)
│   ├── Raycasts para visión
│   ├── Colisiones de audio (si hay)
│   ├── Escribe: sensor_data.visible, sensor_data.heard, sensor_data.threats
│   └── Emite: entity_detected, entity_lost, noise_heard
│
├── MemorySystem.update(delta)
│   ├── Integra nuevos sensor_data
│   ├── Decae memorias viejas
│   ├── Escribe: memory_store (append/update/expire)
│   └── Emite: memory_updated, memory_expired

FASE 2: DECISIÓN (por cada bot)
├── DecisionSystem.process(delta)
│   ├── FSM.evaluate_transitions()
│   │   ├── Lee: sensor_data, memory_store, objectives, health, weapon_status
│   │   ├── Decide si cambiar de estado
│   │   └── Si cambia: emite state_changed, llama exit() / enter()
│   │
│   ├── FSM.state.execute(delta)
│   │   ├── El estado activo ejecuta su lógica
│   │   ├── Escribe: movement_command, combat_command, target_entity
│   │   └── El estado NO escribe velocity, NO escribe weapon
│   │
│   └── FSM.validate_commands()
│       └── Asegura coherencia (no disparar sin target, no moverse a null)

FASE 3: EJECUCIÓN (por cada bot)
├── MovementSystem.process(delta)
│   ├── Lee: movement_command (de DecisionSystem)
│   ├── Consulta: NavigationAgent.GetNextPathPosition()
│   ├── Calcula: desired_velocity = compute_steering(movement_command)
│   ├── Escribe: velocity, navigation_path, stuck_state
│   └── Verifica stuck: guarda historial de posiciones
│
├── CombatSystem.process(delta)
│   ├── Lee: combat_command (de DecisionSystem)
│   ├── Lee: target_entity.position (de la escena)
│   ├── WeaponAIProfile → decide modo de fuego, predicción, splash
│   ├── Calcula: aim_rotation = adjust_aim(target, weapon_profile)
│   ├── Calcula: fire_request = should_fire(combat_command, weapon_status)
│   └── Escribe: aim_rotation (sin tocar velocity)
│
├── WeaponSystem.process(delta)
│   ├── Lee: fire_request (de CombatSystem)
│   ├── Procesa: cooldown, recarga, munición
│   ├── Si fire_request && can_fire() → ejecuta fire()
│   └── Escribe: weapon_status, ammo, cooldown
│
├── HealthSystem.process(delta) [solo si hay daño continuo]
│   └── Procesa efectos de zona (lava, ácido)

FASE 4: FÍSICA (por cada bot)
├── CharacterBody3D (internamente)
│   ├── apply_gravity() → modifica velocity.y
│   ├── apply_velocity() → velocity de MovementSystem
│   └── move_and_slide() → Godot aplica físicas
│
└── MovementSystem.post_process(delta)
    ├── Verifica stuck post-movimiento
    ├── Verifica llegada a destino
    └── Emite: destination_reached, stuck_detected, path_blocked

FASE 5: VISUAL (por cada bot)
├── CombatSystem.post_process(delta)
│   ├── Aplica aim_rotation al modelo/arma
│   ├── No toca velocity, no toca posición
│   └── Solo rotación de la cabeza/arma
```

---

## PARTE 4: VARIABLES PROPIETARIAS (DATA OWNERSHIP)

TABLA COMPLETA DE QUIÉN ESCRIBE CADA VARIABLE:

| Variable | Propietario (ESCRIBE) | Lectores | Prohibido escribir |
|----------|----------------------|----------|-------------------|
| `velocity` | **MovementSystem** | Physics engine | DecisionSystem, CombatSystem, WeaponSystem, PerceptionSystem |
| `global_position` | **Physics engine** (move_and_slide) | Todos leen | Nadie escribe directamente |
| `target_entity` | **DecisionSystem** (FSM) | CombatSystem, PerceptionSystem | MovementSystem, WeaponSystem, HealthSystem |
| `movement_command` | **DecisionSystem** (FSM) | MovementSystem | CombatSystem, PerceptionSystem |
| `combat_command` | **DecisionSystem** (FSM) | CombatSystem | MovementSystem, WeaponSystem |
| `aim_rotation` | **CombatSystem** | Modelo/Arma (visual) | DecisionSystem, MovementSystem |
| `weapon_status` | **WeaponSystem** | CombatSystem, DecisionSystem | MovementSystem, PerceptionSystem |
| `ammo_count` | **WeaponSystem** | DecisionSystem | CombatSystem (solo lee) |
| `health` | **HealthSystem** | DecisionSystem | MovementSystem, CombatSystem |
| `sensor_data` | **PerceptionSystem** | DecisionSystem, MemorySystem | MovementSystem, CombatSystem |
| `memory_store` | **MemorySystem** | DecisionSystem | PerceptionSystem (solo lee) |
| `stuck_state` | **MovementSystem** | DecisionSystem | CombatSystem |
| `navigation_path` | **MovementSystem** | — (interno) | DecisionSystem (solo consulta) |
| `objectives` | **ObjectiveSystem** | DecisionSystem | Bots en general |
| `orders` | **OrderSystem** (subsistema) | DecisionSystem | MovementSystem, CombatSystem |
| `bot_profile` | **SkillSystem** | DecisionSystem (init) | MovementSystem, CombatSystem |
| `damage_history` | **HealthSystem** | DecisionSystem | CombatSystem |

---

## PARTE 5: QUÉ SISTEMA NUNCA DEBE MODIFICAR A OTRO

### Regla de Oro #1: DecisionSystem es el UNICO que escribe comandos
```
MovementSystem NUNCA escribe movement_command
CombatSystem NUNCA escribe combat_command
WeaponSystem NUNCA escribe combat_command
```

### Regla de Oro #2: MovementSystem es el UNICO que escribe velocity
```
DecisionSystem NUNCA escribe velocity
CombatSystem NUNCA escribe velocity  
WeaponSystem NUNCA escribe velocity
PerceptionSystem NUNCA escribe velocity
HealthSystem NUNCA escribe velocity
```
Incluso la gravedad se aplica COMO PARTE de MovementSystem, no externamente.

### Regla de Oro #3: CombatSystem es el UNICO que escribe aim_rotation
```
DecisionSystem NUNCA escribe aim_rotation (escribe focus_point, no la rotación final)
MovementSystem NUNCA escribe aim_rotation
```

### Regla de Oro #4: PerceptionSystem es el UNICO que escribe sensor_data
```
DecisionSystem NUNCA escribe sensor_data
MemorySystem NUNCA escribe sensor_data
```

### Regla de Oro #5: MemorySystem es el UNICO que escribe memory_store
```
DecisionSystem NUNCA escribe memory_store
PerceptionSystem NUNCA escribe memory_store
```

### Regla de Oro #6: ObjectiveSystem es el UNICO que escribe objectives y orders
```
Los bots SOLO LEEN objectives y orders. NUNCA los escriben.
```

---

## PARTE 6: CÓMO EVITAR QUE NAVEGATION MODIFIQUE DECISIONES DEL BOT

### Problema actual:
NavigationSystem (1399 líneas) tiene lógica de stuck recovery que cambia el destino del bot, anulando la decisión del Brain.

### Solución arquitectónica:

**Principio:** NavigationSystem es un PROVEEDOR DE SERVICIOS, no un sistema de decisión.

```
MovementSystem (en el bot) es el CLIENTE de NavigationSystem (global)

MovementSystem.process():
  1. Lee movement_command de DecisionSystem (contiene: destino, modo, velocidad)
  2. Consulta NavigationSystem.get_path(origen, destino) → obtiene camino
  3. MovementSystem gestiona el stuck INTERNAMENTE:
     - Si detecta stuck, emite señal "stuck_detected(cause)"
     - DecisionSystem escucha la señal y decide qué hacer:
       a) Recalcular ruta con NavigationSystem
       b) Cambiar a estado HUNTING con ruta alternativa
       c) Ignorar y seguir
       d) Cambiar a estado RETREATING
  4. MovementSystem NUNCA cambia el destino por su cuenta
```

**Flujo de stuck recovery:**
```
1. MovementSystem detecta stuck (progreso insuficiente)
2. MovementSystem → emite señal "stuck_detected(phase, cause)"
3. DecisionSystem (FSM) → recibe señal
4. FSM decide qué hacer:
   - Si está en ROAMING: solicita nueva ruta aleatoria
   - Si está en HUNTING: cambia a estado ALTERNATE_PATH
   - Si está en COMBAT: cambia a TACTICAL_MOVE con strafe
   - Si está en RETREATING: solicita nueva ruta hacia health
5. FSM → escribe nuevo movement_command
6. MovementSystem → ejecuta el nuevo comando
```

**Lo que NUNCA pasa:**
```
MovementSystem.set_destination(x)  ← PROHIBIDO
MovementSystem.cancel_current_path()  ← PROHIBIDO
```

---

## PARTE 7: CÓMO EVITAR QUE COMBAT MODIFIQUE MOVEMENT

### Problema actual:
BehaviorCombat escribe `brain.bot.velocity.y = 5.0` para saltar durante strafe.

### Solución arquitectónica:

**Principio:** CombatSystem NUNCA toca velocity. Si necesita un salto, lo SOLICITA.

```
Flujo correcto para un salto táctico:

1. CombatSystem.process(delta):
   - Detecta que sería ventajoso saltar (enemigo cerca, necesita evadir)
   - NO escribe velocity
   - Escribe en campos SOLO LECTURA de combate: 
     combat_state.wants_dodge = true
     combat_state.dodge_direction = "left"

2. DecisionSystem.process(delta) LOOP:
   - Lee combat_state.wants_dodge
   - Decide:
     a) Concede el dodge → escribe movement_command con dodge
     b) No concede → ignora (ej: si está al borde de un precipicio)

3. MovementSystem.process(delta):
   - movement_command incluye: {mode: DODGE, direction: left, jump: true}
   - MovementSystem calcula velocity incluyendo el salto
   - MovementSystem escribe velocity
```

**Otra alternativa (más UT99):**
```
CombatSystem puede escribir en "movement_adjustment" 
(un Vector3 de ajuste de movimiento, no velocity directo)
MovementSystem SUMA este adjustment a su velocity calculada
PERO MovementSystem puede limitar/ignorar el adjustment
```

**Regla estricta:**
```
CombatSystem.NUNCA.velocity = x  ← no existe en el código
CombatSystem.SIEMPRE.solicita → MovementSystem.ejecuta
```

---

## PARTE 8: CÓMO EVITAR MÚLTIPLES ESCRITORES SOBRE VELOCITY

### Problema actual:
6+ lugares escriben velocity: NavigationSystem, BotBrain, BehaviorCombat, movimiento directo legacy, gravedad, move_and_slide.

### Solución arquitectónica:

**Patrón: SINGLE WRITER + COMMAND QUEUE**

```
MovementSystem es el ÚNICO escritor de velocity.

MovementSystem.process(delta):
  1. Acumula comandos pendientes (máximo 1 por frame)
  2. El comando contiene TODO lo necesario:
     - Modo: NAVIGATE / DIRECT / DODGE / STOP
     - Destino o dirección
     - Velocidad deseada
     - Flags: jump, crouch, sprint
  3. MovementSystem calcula velocity:
     - Si modo NAVIGATE: steering hacia waypoint + avoidance
     - Si modo DIRECT: dirección directa + avoidance
     - Si modo DODGE: impulso + gravedad
     - Si modo STOP: frenado
  4. MovementSystem.apply_gravity(): modifica velocity.y
  5. MovementSystem.apply_stuck_prevention(): ajusta si hay atasco
  6. MovementSystem.finalize(): la velocidad está lista para move_and_slide

NADIE más escribe velocity:
  - DecisionSystem escribe movement_command (no velocity)
  - CombatSystem.escribe combat_state (no velocity)
  - Physics engine escribe nada (solo ejecuta move_and_slide)
```

**Implementación en CharacterBody3D:**
```
extends CharacterBody3D

var movement_system: MovementSystem

func _physics_process(delta):
    # FASE 1-3: Perception, Decision, Combat (escriben commands)
    perception_system.update(delta)
    memory_system.update(delta)
    decision_system.process(delta)
    combat_system.process(delta)
    
    # FASE 4: MovementSystem escribe velocity
    movement_system.process(delta)
    
    # FASE 5: move_and_slide LEE velocity de MovementSystem
    move_and_slide()
    
    # FASE 6: Post-move
    movement_system.post_process(delta)
```

**Si se necesita gravedad personalizada:**
```
MovementSystem.process() contiene:
    if not is_on_floor():
        velocity.y -= gravity * delta
    Este es el ÚNICO lugar donde se modifica velocity.y por gravedad.
```

---

## PARTE 9: CÓMO EVITAR MÚLTIPLES ESCRITORES SOBRE TARGET

### Problema actual:
PerceptionSystem sugiere, NpcBase escribe `target_enemy`, BotBrain lee, core_attack escribe otro target.

### Solución arquitectónica:

**Principio: DecisionSystem (FSM) es el ÚNICO que escribe target_entity.**

```
¿Quién sugiere targets?
- PerceptionSystem → emite señal "entity_detected(id, pos, confidence)"
- MemorySystem → emite señal "memory_recalled(entity_id, last_pos)"
- ObjectiveSystem → escribe objectives (el FSM los lee)
- CombatSystem → emite señal "target_in_range(id, dist)"

¿Quién decide el target?
EXCLUSIVAMENTE DecisionSystem.process():
  1. Evalúa estado actual
  2. Consulta sugerencias (señales entrantes, memorias, objetivos)
  3. Decide target según:
     - Prioridad del objetivo (UT99: AssessThreat)
     - Estado actual (combate, roaming, etc.)
     - Órdenes actuales
     - Distancia, salud, armas
  4. Escribe: target_entity = node_reference
  5. Si cambia target: emite señal "target_selected(entity_id)"

¿Quién LEE target_entity?
- CombatSystem: para apuntar y decidir disparo
- MovementSystem: para navegar hacia él (si el comando es "sígueme")
- PerceptionSystem: para mantener atención prioritaria

Lo que NUNCA pasa:
- CombatSystem.set_target(x) ← PROHIBIDO
- MovementSystem.set_target(x) ← PROHIBIDO
- PerceptionSystem escribe directamente target_enemy ← PROHIBIDO
```

**Mecanismo de prioridad de target (tomado de UT99 AssessThreat):**
```
DecisionSystem.internal._assess_threat(candidate):
    score = relative_strength(candidate)  # salud + armas
    if candidate.health < 20: score += 0.3
    if distance < 800: score += 0.3
    if candidate != current_target:
        score -= 0.25  # penalizar cambio
        score -= 0.2
    if candidate is PlayerPawn: score += 0.15
    score += objective_system.game_threat_add(self, candidate)
    return score
```

---

## PARTE 10: FSM ESTILO UT99 EN GODOT 4

### Estructura general

La FSM de UT99 es una máquina de estados JERÁRQUICA donde cada estado maneja TODOS los eventos relevantes (SeePlayer, HearNoise, TakeDamage, HitWall, Timer, Bump, EnemyNotVisible).

**Implementación en Godot 4:**

```
DecisionSystem (Node)
├── StateMachine (Node)
│   ├── State_Acquisition (Node)
│   ├── State_Combat (Node) ─── padre de sub-estados
│   │   ├── State_TacticalMove (Node)
│   │   ├── State_Charging (Node)
│   │   └── State_RangedAttack (Node)
│   ├── State_Hunting (Node)
│   ├── State_StakeOut (Node)
│   ├── State_Retreating (Node)
│   ├── State_Roaming (Node)
│   ├── State_Wandering (Node)
│   ├── State_Holding (Node)
│   ├── State_Falling (Node)
│   └── State_TakingHit (Node)
```

### Contrato de cada estado

```
class_name BotState extends Node

# === PROPIETARIO DE (escribe en DecisionSystem) ===
# Puede modificar: decision_system.movement_command
# Puede modificar: decision_system.combat_command
# Puede modificar: decision_system.target_entity
# Puede modificar: decision_system.focus_point
# NUNCA modifica: velocity, weapon_state, sensor_data, memory_store

# === CICLO DE VIDA ===
func enter(previous_state: BotState) -> void:
    # Inicializar el estado
    # NO escribe velocity, NO escribe weapon
    # Escribir comandos iniciales si es necesario
    pass

func execute(delta: float) -> void:
    # Lógica principal del estado
    # Leer: sensor_data, memory, health, weapon_status, objectives
    # Escribir: movement_command, combat_command, target_entity
    pass

func exit(next_state: BotState) -> void:
    # Limpiar recursos del estado
    # NO resetear comandos (eso lo hace el siguiente estado)
    pass

# === MANEJADORES DE EVENTOS ===
func on_see_player(seen_player: Node3D) -> void:
    pass  # Cada estado decide si responde al evento

func on_hear_noise(loudness: float, source: Vector3) -> void:
    pass

func on_take_damage(amount: float, attacker: Node3D) -> void:
    pass

func on_hit_wall(normal: Vector3, wall: Node) -> void:
    pass

func on_bump(other: Node) -> void:
    pass

func on_enemy_not_visible() -> void:
    pass

func on_stuck_detected(phase: int, cause: String) -> void:
    pass

func on_destination_reached() -> void:
    pass

func on_heal_pickup_nearby(item: Node3D) -> void:
    pass

func on_weapon_pickup_nearby(item: Node3D, rating: float) -> void:
    pass

func on_orders_changed(new_orders: String, target: NodePath) -> void:
    pass

func on_objective_updated(objective: Objective) -> void:
    pass
```

### Transiciones entre estados (tomadas de UT99)

```
ACQUISITION:
  → COMBAT (si tiene enemigo y está listo)
  → ROAMING (si perdió el enemigo)

COMBAT (elegido por ChooseAttackMode):
  → TACTICAL_MOVE (default, con enemigo visible)
  → CHARGING (si arma melee o agresividad alta)
  → RANGED_ATTACK (si está listo para disparar)
  → HUNTING (si perdió visión del enemigo)
  → RETREATING (si tiene miedo del enemigo)
  → STAKEOUT (si perdió visión y tiene paciencia)
  → ROAMING (si murió el enemigo)

TACTICAL_MOVE:
  → RANGED_ATTACK (cuando timer dispara)
  → CHARGING (si decide cargar)
  → HUNTING (si pierde visión)
  → RETREATING (si recibe mucho daño)
  → COMBAT (al terminar el strafe)

CHARGING:
  → RANGED_ATTACK (cuando timer dispara o está en melee range)
  → TACTICAL_MOVE (si no alcanza al enemigo)
  → HUNTING (si pierde visión)
  → COMBAT (al terminar)

HUNTING:
  → COMBAT (si encuentra al enemigo)
  → STAKEOUT (si llega a última posición conocida)
  → ROAMING (si se rinde)

STAKEOUT:
  → COMBAT (si ve al enemigo)
  → HUNTING (si decide seguir buscando)
  → ROAMING (si se cansa)

RETREATING:
  → COMBAT (si ya no tiene miedo)
  → ROAMING (si no hay enemigo)

ROAMING:
  → COMBAT (si aparece enemigo)
  → WANDERING (si decide deambular)
  → HOLDING (si tiene orden Hold y llegó)
  → Cada estado pedido por FindSpecialAttractionFor()

WANDERING:
  → ROAMING (después de un tiempo)
  → COMBAT (si aparece enemigo)
```

### Algoritmo de selección de ataque (tomado de UT99 Bot.ChooseAttackMode)

```
function choose_attack_mode():
    if enemy == null or enemy.health <= 0:
        what_to_do_next()
        return
    
    if weapon == null:
        switch_to_best_weapon()
    
    attitude = attitude_to(enemy)
    
    # Verificar atracción especial (bandera, control point, etc.)
    if game_mode.has_special_attraction(self):
        return  # El game_mode redirigió
    
    if attitude == FEAR:
        go_to(RETREATING)
        return
    elif attitude == FRIENDLY:
        what_to_do_next()
        return
    
    if not line_of_sight_to(enemy):
        # Evaluar si cambiar a old_enemy
        if old_enemy is valid and has_los_to(old_enemy):
            swap_enemy()
        else:
            if should_hunt():
                go_to(HUNTING)
            else:
                go_to(STAKEOUT)
        return
    
    if ready_to_attack:
        target = enemy
        reset_attack_timer()
    
    go_to(TACTICAL_MOVE)
```

---

## PARTE 11: ADAPTACIÓN A GODOT 4 — CharacterBody, NavigationAgent, Resources

### 11.1 Estructura de Nodos del Bot

```
EnemyBot (CharacterBody3D)
├── CollisionShape3D
├── Model (Node3D) — visual
│   └── WeaponModel (Node3D)
├── AI (Node)
│   ├── PerceptionSystem (Node)
│   │   └── SightCone (Area3D) — opcional
│   ├── MemorySystem (Node)
│   ├── DecisionSystem (Node)
│   │   ├── StateMachine (Node)
│   │   │   ├── State_Acquisition (BotState)
│   │   │   ├── State_Combat (BotState)
│   │   │   │   ├── State_TacticalMove (BotState)
│   │   │   │   ├── State_Charging (BotState)
│   │   │   │   └── State_RangedAttack (BotState)
│   │   │   ├── State_Hunting (BotState)
│   │   │   ├── State_StakeOut (BotState)
│   │   │   ├── State_Retreating (BotState)
│   │   │   ├── State_Roaming (BotState)
│   │   │   ├── State_Wandering (BotState)
│   │   │   ├── State_Holding (BotState)
│   │   │   ├── State_Falling (BotState)
│   │   │   └── State_TakingHit (BotState)
│   │   └── CommandValidator (Node)
│   ├── MovementSystem (Node)
│   │   ├── StuckDetector (Node) — lógica de stuck
│   │   ├── AutoJumper (Node) — lógica de saltos automáticos
│   │   └── NavigationAgent3D (Node) — Godot nativo
│   ├── CombatSystem (Node)
│   │   └── AimController (Node) — puntería
│   ├── WeaponSystem (Node)
│   │   ├── WeaponSlot (Node3D)
│   │   └── WeaponAIProfile (Resource) — desde arma actual
│   └── HealthSystem (Node)
│       └── ArmorSlot (Node)
├── BotProfile (Resource) — SkillSystem asigna al iniciar
└── TeamIdentifier (Node)
```

### 11.2 Uso de NavigationAgent3D (Godot nativo)

**NavigationAgent3D** reemplaza completamente el sistema de pathfinding custom. MovementSystem lo usa así:

```
MovementSystem.process(delta):
    var cmd: MovementCommand = decision_system.movement_command
    
    match cmd.mode:
        MovementMode.NAVIGATE:
            navigation_agent.target_position = cmd.target_position
            if navigation_agent.is_navigation_finished():
                decision_system.emit("destination_reached")
                return
            var next_pos = navigation_agent.get_next_path_position()
            var direction = (next_pos - global_position).normalized()
            desired_velocity = direction * cmd.speed
            # Aplicar avoidance suave
            desired_velocity = navigation_agent.avoidance(desired_velocity, delta)
            
        MovementMode.DIRECT:
            desired_velocity = cmd.direction.normalized() * cmd.speed
            
        MovementMode.DODGE:
            desired_velocity = cmd.direction * cmd.impulse
            desired_velocity.y = cmd.jump_velocity
            
        MovementMode.STOP:
            desired_velocity = Vector3.ZERO
    
    # MovementSystem es el UNICO que toca velocity
    velocity = desired_velocity
    
    # Gravedad (también MovementSystem)
    if not is_on_floor():
        velocity.y -= gravity * delta
```

### 11.3 Resources para datos (evitando nodos innecesarios)

**BotProfile (Resource):**
```
class_name BotProfile extends Resource
@export var bot_name: String
@export var skill: int = 4
@export var accuracy: float = 0.0
@export var combat_style: float = 0.0       # -1.0 a 1.0
@export var aggressiveness: float = 0.5
@export var alertness: float = 0.0          # -1.0 a 1.0
@export var camping_rate: float = 0.0
@export var strafing_ability: float = 0.0
@export var jumpy: bool = false
@export var favorite_weapon: String = ""
@export var team: int = 0
```

**WeaponAIProfile (Resource):**
```
class_name WeaponAIProfile extends Resource
@export var ai_rating: float = 0.5
@export var preferred_range_min: float = 2.0
@export var preferred_range_max: float = 30.0
@export var splash_damage: bool = false
@export var lead_target: bool = true
@export var refire_rate: float = 0.8
@export var aim_error_base: int = 2000
@export var attack_style_modifier: float = 0.0   # -1.0 a 1.0
@export var defense_style_modifier: float = 0.0
@export var prefers_alt_fire: bool = false
@export var is_melee: bool = false
@export var is_instant_hit: bool = true
```

**SemanticPoint (Resource):**
```
class_name SemanticPoint extends Resource
@export var position: Vector3
@export var point_type: SemanticPointType  # enum
@export var team: int = -1
@export var priority: int = 0
@export var look_direction: Vector3
@export var sight_radius: float = 50.0
@export var extra_cost: float = 0.0
@export var tags: Array[String]
@export var is_sniper_spot: bool = false
@export var is_one_way: bool = false
@export var is_return_only: bool = false
@export var is_player_only: bool = false
```

**MovementCommand (Resource, transitorio):**
```
class_name MovementCommand extends Resource
enum Mode { NONE, NAVIGATE, DIRECT, DODGE, STOP }
@export var mode: Mode = Mode.NONE
@export var target_position: Vector3
@export var direction: Vector3
@export var speed: float = 5.0
@export var jump: bool = false
@export var jump_velocity: float = 5.0
@export var sprint: bool = false
@export var dodge_impulse: float = 10.0
@export var use_advanced_tactics: bool = false
```

**CombatCommand (Resource, transitorio):**
```
class_name CombatCommand extends Resource
@export var engage: bool = false
@export var target_id: int
@export var fire_mode: int = 0  # 0=primario, 1=alterno
@export var aim_at_position: Vector3
@export var aim_at_entity_path: NodePath
@export var force_fire: bool = false
@export var cease_fire: bool = false
```

### 11.4 Sistema de eventos (Signal Bus)

Para comunicación limpia entre sistemas, se usa un Signal Bus centralizado o referencias directas.

**Conexiones recomendadas:**
```
# Perception → Memory
perception.entity_detected.connect(memory.on_entity_detected)
perception.entity_lost.connect(memory.on_entity_lost)

# Perception → Decision
perception.threat_assessed.connect(decision.on_threat_assessed)
perception.entity_detected.connect(decision.on_entity_detected)

# Memory → Decision
memory.memory_updated.connect(decision.on_memory_updated)

# Movement → Decision
movement.destination_reached.connect(decision.on_destination_reached)
movement.stuck_detected.connect(decision.on_stuck_detected)
movement.path_blocked.connect(decision.on_path_blocked)

# Combat → Decision
combat.target_in_range.connect(decision.on_target_in_range)
combat.target_lost.connect(decision.on_target_lost)
combat.out_of_ammo.connect(decision.on_out_of_ammo)

# Weapon → Combat
weapon.weapon_ready.connect(combat.on_weapon_ready)
weapon.weapon_empty.connect(combat.on_weapon_empty)
weapon.reload_completed.connect(combat.on_reload_completed)

# Health → Decision
health.damage_taken.connect(decision.on_damage_taken)
health.death.connect(decision.on_death)

# ObjectiveSystem → Decision (via signals globales)
ObjectiveSystem.objective_updated.connect(decision.on_objective_updated)
ObjectiveSystem.orders_changed.connect(decision.on_orders_changed)
```

### 11.5 Init del Bot (secuencia de arranque)

```
func _ready():
    # 1. SkillSystem asigna perfil
    var profile: BotProfile = SkillSystem.get_profile(bot_id)
    
    # 2. DecisionSystem init con perfil
    decision_system.init(profile)
    
    # 3. FSM empieza en ROAMING
    decision_system.fsm.start_state("State_Roaming")
    
    # 4. MovementSystem init
    movement_system.init(profile)
    
    # 5. CombatSystem init
    combat_system.init(profile)
    
    # 6. WeaponSystem init
    weapon_system.init(weapon_scene)
    
    # 7. PerceptionSystem init
    perception_system.init(sight_radius, peripheral_vision, hearing_threshold)
    
    # 8. Conectar todas las señales
    _connect_systems()
```

---

## PARTE 12: COMPARACIÓN — UT99 ORIGINAL vs NUEVA ARQUITECTURA

| Concepto UT99 | Equivalente en nueva arquitectura |
|--------------|----------------------------------|
| `Pawn` (clase base nativa) | `CharacterBody3D` + `HealthSystem` |
| `Bot` (7587 líneas FSM) | `DecisionSystem` + `StateMachine` con estados como nodos |
| `NavigationPoint` | `SemanticPoint` (Resource) + `NavigationRegion3D` |
| `ReachSpec` (C++ nativo) | NavigationServer3D + NavigationAgent3D |
| `AmbushPoint` | `SemanticPoint(type=AMBUSH)` |
| `DefensePoint` | `SemanticPoint(type=DEFENSE)` + `team` + `priority` |
| `AlternatePath` | `SemanticPoint(type=ALTERNATE)` + `selection_weight` |
| `LiftCenter/LiftExit` | NavigationLink + Area3D + señal de activación |
| `Inventory.BotDesireability()` | `PickupResource.get_desireability(bot_context)` |
| `Weapon.RateSelf()` | `WeaponAIProfile.ai_rating` |
| `Weapon.SuggestAttackStyle()` | `WeaponAIProfile.attack_style_modifier` |
| `Weapon.bRecommendSplashDamage` | `WeaponAIProfile.splash_damage` |
| `Skill` | `BotProfile.skill + accuracy` |
| `CombatStyle` | `BotProfile.combat_style` |
| `CampingRate` | `BotProfile.camping_rate` |
| `StrafingAbility` | `BotProfile.strafing_ability` |
| `RelativeStrength()` | `DecisionSystem._assess_threat()` |
| `SetEnemy()` | `DecisionSystem.target_entity` (único escritor) |
| `SetOrders()` | `OrderSystem` (subsistema de ObjectiveSystem) |
| `RealOrders` vs `Orders` | `OrderSystem.real_orders` vs `current_orders` |
| `WhatToDoNext()` | `FSM.evaluate_transitions()` |
| `FindSpecialAttractionFor()` | `ObjectiveSystem.get_objectives_for(bot)` |
| `GameThreatAdd()` | `ObjectiveSystem.modify_threat(bot, threat)` |
| `AdjustAim()` | `CombatSystem._adjust_aim(entity, weapon_profile)` |
| `Alertness` modificando visión | `PerceptionSystem.apply_alertness_modifier(alertness)` |
| `MoveToward()` (latente) | `MovementSystem` con `NavigationAgent3D` |
| `LineOfSightTo()` | `PerceptionSystem._has_los(target)` con RayCast |
| `PickWallAdjust()` | `MovementSystem._pick_wall_adjust()` con RayCast |
| `HearNoise()` | `PerceptionSystem._process_noise()` con Area3D |

---

## PARTE 13: REGLAS DE ARQUITECTURA (RESUMEN EJECUTIVO)

### 13.1 SISTEMAS Y SUS LÍMITES

```
┌──────────────────────────────────────────────────────────────────────┐
│                        REGLA DE ORO ÚNICA                            │
│                                                                      │
│  Cada sistema tiene EXACTAMENTE UNA variable que es SUYA.            │
│  Ningún otro sistema puede escribir en ella.                          │
│  Si necesitas que otro sistema haga algo: EMITE UN EVENTO.           │
│  Si necesitas saber algo de otro sistema: LEE SU VARIABLE.           │
│  Si necesitas cambiar algo de otro sistema: NO PUEDES.               │
└──────────────────────────────────────────────────────────────────────┘
```

### 13.2 TABLA DE PROPIEDADES (qué sistema es dueño de qué)

| Sistema | Variable Propietaria | Otros sistemas |
|---------|---------------------|----------------|
| PerceptionSystem | `sensor_data` | Solo lectura |
| MemorySystem | `memory_store` | Solo lectura |
| **DecisionSystem** | **`target_entity`**, **`movement_command`**, **`combat_command`**, **`focus_point`** | NADIE más escribe |
| MovementSystem | **`velocity`**, **`navigation_path`**, **`stuck_state`** | NADIE más escribe |
| CombatSystem | **`aim_rotation`**, **`dodge_state`** | NADIE más escribe |
| WeaponSystem | **`weapon_status`**, **`ammo_count`** | NADIE más escribe |
| HealthSystem | **`health`**, **`damage_history`** | NADIE más escribe |
| ObjectiveSystem | **`objectives`**, **`orders`**, **`scores`** | NADIE más escribe |
| NavigationSystem | **`navigation_mesh`**, **`semantic_points`** | NADIE más escribe |
| SkillSystem | **`bot_profiles`** | NADIE más escribe |

### 13.3 LO QUE NUNCA DEBE PASAR

```
❌ CombatSystem escribe velocity.y
❌ DecisionSystem escribe velocity
❌ MovementSystem escribe target_entity
❌ PerceptionSystem escribe weapon_state
❌ WeaponSystem escribe movement_command
❌ HealthSystem escribe sensor_data
❌ MemorySystem escribe combat_command
❌ NavigationSystem escribe algo en bots
❌ ObjectiveSystem escribe algo en bots (solo emite señales)
```

### 13.4 PATRÓN DE COMUNICACIÓN

```
Sistema A (productor) 
    → escribe su variable propietaria
    → emite señal "evento_ocurrió(datos)"
    
Sistema B (consumidor)
    → escucha señal de A
    → LEE variable propietaria de A (si necesita más datos)
    → decide si modifica SU variable propietaria
    → NUNCA escribe en variable de A
```

### 13.5 CÓMO VERIFICAR LA ARQUITECTURA EN CÓDIGO

Para cada archivo .gd nuevo, verificar:
1. ¿Cuál es la variable propietaria de este sistema?
2. ¿Algún otro sistema la escribe? → VIOLACIÓN
3. ¿Este sistema escribe en variable de otro? → VIOLACIÓN
4. ¿Este sistema modifica velocity? → Solo MovementSystem
5. ¿Este sistema modifica target? → Solo DecisionSystem
6. ¿Este sistema emite eventos? → Bien
7. ¿Este sistema responde a eventos? → Bien
8. ¿Este sistema llama move_and_slide()? → Solo NpcBase/CharacterBody

---

## PARTE 14: IMPLEMENTACIÓN PROGRESIVA (PLAN DE MIGRACIÓN)

### Fase 1: Limpieza (semana 1)
1. Identificar TODOS los lugares que escriben `velocity` → marcar
2. Identificar TODOS los lugares que escriben `target_enemy` → marcar
3. Identificar TODOS los lugares que escriben `weapon` → marcar
4. NO MODIFICAR nada todavía. Solo mapear.

### Fase 2: Infrastructure (semana 2)
1. Crear los Resources: BotProfile, WeaponAIProfile, SemanticPoint, MovementCommand, CombatCommand, Objective
2. Crear clases bot_state.gd (base de estados)
3. Crear signal_bus.gd (autoload para comunicación global)
4. Migrar Weapon a usar WeaponAIProfile (resource externo)

### Fase 3: MovementSystem (semana 3)
1. Crear MovementSystem NUEVO
2. MovementSystem es el ÚNICO que escribe velocity
3. MovementSystem recibe MovementCommand
4. MovementSystem usa NavigationAgent3D nativo
5. MovementSystem tiene StuckDetector interno que SOLO EMITE SEÑALES
6. NUNCA cambia destino por su cuenta

### Fase 4: DecisionSystem + FSM (semana 4-5)
1. Crear DecisionSystem con StateMachine
2. Implementar estados: ROAMING, COMBAT, HUNTING, RETREATING
3. DecisionSystem es el ÚNICO que escribe movement_command y combat_command
4. DecisionSystem es el ÚNICO que escribe target_entity
5. Cada estado es un nodo independiente

### Fase 5: CombatSystem (semana 5-6)
1. Crear CombatSystem
2. CombatSystem es el ÚNICO que escribe aim_rotation
3. CombatSystem NUNCA escribe velocity
4. CombatSystem usa WeaponAIProfile para decisiones de arma

### Fase 6: ObjectiveSystem + OrderSystem (semana 6-7)
1. Implementar team_ai.gd como ObjectiveSystem
2. Sistema de órdenes (FreeLance, Attack, Defend, Follow, Hold)
3. Separación RealOrders vs CurrentOrders
4. Jerarquía líder→seguidor

### Fase 7: Semantic Navigation (semana 7-8)
1. Implementar SemanticPoints como Resources
2. Colocar puntos en mapas (Ambush, Defense, Alternate)
3. Integrar con NavigationServer3D para costos dinámicos
4. Sistema de atracción especial (por GameMode)

### Fase 8: Eliminación de legacy (semana 8)
1. Eliminar métodos legacy de NpcBase
2. Eliminar Behaviors viejos
3. Eliminar DecisionContext
4. Eliminar NavigationSystem viejo
5. NpcBase queda como CharacterBody3D + referencias a sistemas

---

## PARTE 15: GLOSARIO DE TÉRMINOS

| Término | Significado |
|---------|------------|
| **FSM** | Finite State Machine. Máquina de estados con transiciones explícitas. |
| **Command** | Resource transitorio que un sistema escribe y otro lee. Ej: MovementCommand |
| **Signal** | Evento de Godot. Un sistema emite, otro escucha. |
| **Data Owner** | El único sistema que puede escribir una variable. |
| **SemanticPoint** | Punto de navegación con significado táctico (no solo geométrico). |
| **Objective** | Meta que el GameMode asigna. Los bots SOLO LEEEN objectives. |
| **Order** | Instrucción de equipo (FreeLance, Attack, Defend, Follow, Hold). |
| **RealOrders** | Orden persistente. El bot puede desviarse temporalmente pero vuelve. |
| **Proficiency** | Combinación de skill + traits que define la personalidad del bot. |
| **Engagement** | Estado de combate activo contra un enemigo. |
| **Tactical** | Relativo a decisiones de posicionamiento en combate. |
| **Strafing** | Movimiento lateral manteniendo frente al enemigo. |
| **Splash Damage** | Daño por área. Cambia la puntería (apuntar al suelo). |
| **Lead Target** | Predecir posición futura del enemigo para proyectiles. |
| **Refire Rate** | Probabilidad de seguir disparando (según skill). |
| **Acquisition** | Estado de transición: acaba de detectar enemigo. |
| **StakeOut** | Esperar en última posición conocida del enemigo. |
| **Line of Sight** | Trazo visual sin obstáculos entre dos puntos. |
