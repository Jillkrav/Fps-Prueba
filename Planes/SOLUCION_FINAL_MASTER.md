# 🎯 SOLUCIÓN FINAL — Proyecto UT99-Inspired en Godot 4.2+
## Documento Maestro de Fases (Copy-Paste Ready)

---

## 📋 CONTEXTO GENERAL DEL PROYECTO (incluir en CADA fase)

### Visión
Recrear la experiencia de **Unreal Tournament 1999** en **Godot 4.2+**, modernizada para estándares indie 2026. Movimiento fluido, armas variadas, mapas tácticos, combate frenético, IA modular, optimizado y sin bugs heredados del original.

### Estado actual del proyecto (Junio 2026)
- **Player**: FPS completo con movimiento, salto, crouch, disparo, muerte, respawn, sistema de armas, pickups
- **NPC (npc_base.gd)**: 1112 líneas — clase god class con problemas de múltiples escritores de `velocity` y `target_enemy`
- **AI Modular (parcial)**: PerceptionSystem, MemorySystem, BotBrain con behaviors existen pero aún no están completamente desacoplados
- **Dev Menu**: Funcional con spawn de NPCs configurable, cambio de equipo, AI toggle, debug overlay, selector de armas, propiedades de unidad
- **MatchManager**: Gestión de partida, equipos, respawn, auto-balance
- **Mapas**: 3 mapas (map_1.tscn activo) con bases Azul/Roja, cores, spawn points, coberturas
- **Armas**: Sistema de armas vía JSON (skill.json), 6+ categorías (Pistolas, Escopetas, Subfusiles, Rifles, Francotiradores, Melee)
- **ConfigManager**: Autoload que lee skill.json con stats de armas, NPCs, objetos, salud
- **GameState**: Autoload global con estado de partida, equipos, equipos disponibles (0:Espectador, 1:Azul, 2:Rojo, 3:Amarillo, 4:Verde)

### Enums globales (Enums.gd — class_name Enums)
```gdscript
enum Equipo { ESPECTADOR = 0, AZUL = 1, ROJO = 2, AMARILLO = 3, VERDE = 4 }
enum Experiencia { BAJA = 0, MEDIA = 1, ALTA = 2 }
enum EstadoTactico { IDLE, PATRULLANDO, BUSCANDO, ALERTA, ATACANDO, ARRANSE, BUSCANDO_ITEM, CUBRIENDO }
enum Rol { SOLDADO = 0, FRANCOTIRADOR = 1, APOYO = 2, EXPLORADOR = 3, COMANDANTE = 4 }
```

### Arquitectura objetivo (RESUMEN — leer ARQUITECTURA_IA_UT99_GODOT4.md para detalle completo)
Cada sistema tiene **UNA variable propietaria** que solo él escribe. Comunicación vía señales.

| Sistema | Variable Propietaria | Solo lectura de |
|---------|---------------------|-----------------|
| PerceptionSystem | `sensor_data` | Posiciones globales |
| MemorySystem | `memory_store` | sensor_data |
| **DecisionSystem (FSM)** | **`target_entity`, `movement_command`, `combat_command`, `focus_point`** | Todo lo demás |
| **MovementSystem** | **`velocity`, `navigation_path`, `stuck_state`** | movement_command |
| **CombatSystem** | **`aim_rotation`, `dodge_state`** | combat_command, target_entity |
| WeaponSystem | `weapon_status`, `ammo_count` | fire_request |
| HealthSystem | `health`, `damage_history` | Nada |
| ObjectiveSystem | `objectives`, `orders`, `scores` | Estado global |
| NavigationSystem | `navigation_mesh`, `semantic_points` | Geometría del mapa |
| SkillSystem | `bot_profiles` | Nada |

### Reglas de oro (NUNCA violar)
❌ CombatSystem escribe `velocity.y`  
❌ DecisionSystem escribe `velocity`  
❌ MovementSystem escribe `target_entity`  
❌ PerceptionSystem escribe `weapon_state`  
❌ WeaponSystem escribe `movement_command`  
❌ NavigationSystem escribe algo en bots  
❌ Cualquier sistema escribe variable de otro sistema  
❌ Cualquier sistema llama `move_and_slide()` excepto el CharacterBody3D raíz

### Estructura de nodos del NPC (objetivo final)
```
Npc (CharacterBody3D)
├── CollisionShape3D
├── MeshInstance3D (visual)
├── Head (Node3D)
│   ├── HeadMesh (MeshInstance3D)
│   └── HeadHitbox (Area3D)
├── NavigationAgent3D
├── AI (Node) ← TODOS LOS SISTEMAS MODULARES
│   ├── PerceptionSystem (Node)
│   │   ├── AreaVision (Area3D)
│   │   └── RaycastVision (RayCast3D)
│   ├── MemorySystem (Node)
│   ├── DecisionSystem (Node) ← LA FSM
│   │   └── StateMachine (Node)
│   │       ├── State_Roaming (BotState)
│   │       ├── State_Combat (BotState)
│   │       ├── State_Hunting (BotState)
│   │       ├── State_Retreating (BotState)
│   │       ├── State_StakeOut (BotState)
│   │       ├── State_TacticalMove (BotState)
│   │       ├── State_Charging (BotState)
│   │       └── State_RangedAttack (BotState)
│   ├── MovementSystem (Node)
│   ├── CombatSystem (Node)
│   ├── WeaponSystem (Node)
│   └── HealthSystem (Node)
├── AreaAudio (Area3D)
└── BotProfile (Resource)
```

### Archivos existentes clave (39 scripts .gd, 15 .tscn)
```
res://scripts/
├── player.gd                    # Jugador FPS
├── npc_base.gd                  # NPC god class (1112 lines) ← REFACTORIZAR
├── dev_menu.gd                  # Menú de desarrollo (433 lines)
├── match_manager.gd             # Gestión de partida (1170 lines)
├── game_state.gd                # Estado global (autoload)
├── config_manager.gd            # Config desde JSON (autoload)
├── enums.gd                     # Enumeraciones globales
├── weapon.gd                    # Sistema de armas (136 lines)
├── core.gd                      # Core objetivo
├── hud.gd / main_menu.gd / options_menu.gd / scoreboard.gd
├── spawner.gd / pickup.gd / pickup_manager.gd / weapon_pickup.gd
├── dropped_weapon.gd / resupply_box.gd
├── map_manager.gd / input_manager.gd / player_data.gd / tactical_role.gd
├── team_ai.gd                   # VACÍO — hay que implementarlo
├── team_weapon_selector.gd / route_diversifier.gd / bot_debug_overlay.gd
├── test_stuck_detection.gd / check_nav.gd
├── ai/
│   ├── perception_system.gd     # Percepción modular (287 lines)
│   ├── memory_system.gd         # Memoria modular (339 lines)
│   ├── bot_brain.gd             # Cerebro por prioridades (493 lines)
│   ├── bot_behavior.gd          # Clase base behavior
│   ├── decision_context.gd      # Contexto de decisión
│   ├── behaviors/
│   │   ├── behavior_combat.gd   # Comportamiento combate
│   │   ├── behavior_hunt.gd     # Comportamiento cacería
│   │   ├── behavior_idle.gd     # Comportamiento idle
│   │   └── behavior_patrol.gd   # Comportamiento patrulla
│   └── navigation/
│       └── navigation_system.gd # Sistema de navegación (1399 lines)
├── config/
│   ├── ARQUITECTURA_IA_UT99_GODOT4.md   ← DOCUMENTO CLAVE (1417 lines)
│   ├── UT99_AI_REVERSE_ENGINEERING.md
│   ├── ANALISIS_CODIGO_FUENTE_UT99.md
│   ├── ARQUITECTURA_DEFINITIVA.md
│   ├── ESPECIFICACION_ARQUITECTURA_DEFINITIVA.md
│   └── MODERNIZACION_ALGORITMOS_IA.md
└── scenes/
	├── maps/map_1.tscn (activo), map_2.tscn, map_3.tscn
	├── player.tscn
	├── npcs/npc.tscn
	├── weapons/weapon_placeholder.tscn
	├── hud.tscn / main_menu.tscn / options_menu.tscn / scoreboard.tscn
	├── pickups/dropped_weapon.tscn, resupply_box.tscn
	├── objectives/core.tscn
	├── team_weapon_selector.tscn
	└── npcs/bot_debug_overlay.tscn
```

### Flujo de un frame (orden de ejecución)
```
FASE 0: GLOBAL SYSTEMS — NavigationSystem, ObjectiveSystem
FASE 1: SENSORES — PerceptionSystem.update(), MemorySystem.update()
FASE 2: DECISIÓN — DecisionSystem.process() (FSM escribe commands)
FASE 3: EJECUCIÓN — MovementSystem.process() (escribe velocity),
					 CombatSystem.process() (escribe aim),
					 WeaponSystem.process() (dispara)
FASE 4: FÍSICA — CharacterBody3D.move_and_slide() interno
FASE 5: POST — MovementSystem.post_process() (stuck check, arrival)
```


---

## ══════════════════════════════════════════════════════════════
## 🟢 FASE 0 — AUDITORÍA Y MAPEO DE VIOLACIONES
## ══════════════════════════════════════════════════════════════

**Propósito:** Antes de refactorizar, identificar TODOS los lugares en el código actual donde se violan las reglas de arquitectura (múltiples escritores de velocity, target_enemy, etc.).

### Contexto para el prompt
El proyecto tiene una arquitectura objetivo definida en `config/ARQUITECTURA_IA_UT99_GODOT4.md`. Actualmente `npc_base.gd` (1112 líneas) es una god class donde múltiples sistemas escriben `velocity` y `target_enemy` sin coordinación. Necesitamos un mapa completo de violaciones antes de mover cualquier cosa.

### Qué hacer
1. Leer **todos** los scripts relevantes: npc_base.gd, bot_brain.gd, behaviors (combat, hunt, patrol, idle), perception_system.gd, navigation_system.gd, decision_context.gd
2. Buscar TODAS las referencias a:
   - `velocity` (asignaciones directas: `velocity =`, `velocity.x =`, `velocity.y =`, `velocity.z =`)
   - `target_enemy` (asignaciones directas)
   - `movement_command` (asignaciones)
   - `combat_command` (asignaciones)
   - `aim_rotation` (asignaciones)
   - `move_and_slide()` (quién lo llama)
3. Para cada hallazgo, documentar: archivo, línea, contexto, qué sistema lo escribe, y clasificar como:
   - `[VIOLACIÓN]` — hay que moverlo al sistema correcto
   - `[LEGACY]` — será eliminado al migrar al nuevo sistema
   - `[OK]` — ya cumple con la arquitectura

### Output esperado
Crear archivo `config/AUDITORIA.md` con el listado completo:
```md
# Auditoría de Violaciones Arquitectónicas

## velocity (propietario: MovementSystem)
| Archivo | Línea | Contexto | Tipo |
|---------|-------|----------|------|
| npc_base.gd | 245 | gravedad en _physics_process | LEGACY |
| behavior_combat.gd | 88 | salto táctico directo | VIOLACIÓN |

## target_enemy (propietario: DecisionSystem)
...
```

### Criterios de éxito
- Auditoría completa documentada en `config/AUDITORIA.md`
- No modificar NINGÚN archivo de código en esta fase
- Tener claridad total de qué hay que migrar y a dónde

### Dev Menu disponible
- `Q` abre/cierra el Dev Menu
- Botón "AI Disable" pausa todos los NPCs
- Botón "Bot Debug Info" muestra overlay de debug en NPCs
- Botón "Propiedades de unidad" muestra stats

---

## ══════════════════════════════════════════════════════════════
## 🟢 FASE 1 — REFACTOR: PERCEPTIONSYSTEM + MEMORYSYSTEM
## ══════════════════════════════════════════════════════════════

**Propósito:** Completar el desacoplamiento de PerceptionSystem y MemorySystem del npc_base.gd. Estos sistemas YA EXISTEN como nodos modulares (res://scripts/ai/perception_system.gd y memory_system.gd) pero aún hay código legacy en npc_base.gd que escribe datos que pertenecen a estos sistemas.

### Estado actual
- `PerceptionSystem` (287 lines): Ya es un nodo hijo de NpcBase. Escanea AreaVision, verifica línea de visión, calcula prioridad de enemigos. **Problema:** Todavía escribe `target_enemy` y `last_seen_position` directamente en NpcBase (violación — eso debe ser solo sugerencia para DecisionSystem).
- `MemorySystem` (339 lines): Ya es un nodo hijo. Almacena memorias con expiración. **Problema:** Aún no está completamente integrado — algunos behaviors acceden a datos de percepción directamente desde NpcBase en lugar de MemorySystem.
- `NpcBase` todavía tiene lógica de percepción y memoria dispersa.

### Qué hacer
1. **Limpiar PerceptionSystem:**
   - Eliminar que PerceptionSystem escriba `target_enemy` y `last_seen_position` en NpcBase
   - En su lugar, solo emitir señales: `entity_detected`, `entity_lost`, `threat_assessed`
   - PerceptionSystem produce `sensor_data` (visible_enemies, heard_noises) — NADIE más escribe eso
2. **Limpiar MemorySystem:**
   - Asegurar que MemorySystem es el ÚNICO que escribe `memory_store`
   - Todos los behaviors deben leer memorias a través de métodos de MemorySystem, no directamente de NpcBase
3. **Actualizar NpcBase:**
   - Eliminar código duplicado de percepción/memoria
   - NpcBase solo debe INICIALIZAR los sistemas y conectar señales
   - NpcBase NO debe tener variables como `target_enemy` (eso es de DecisionSystem)

### Output esperado
- PerceptionSystem limpio: solo produce `sensor_data` + emite señales
- MemorySystem limpio: único escritor de `memory_store`
- NpcBase: ~100-200 líneas menos
- Behaviors actualizados para usar MemorySystem en lugar de acceso directo a NpcBase

### Criterios de verificación
1. ✅ El proyecto carga sin errores
2. ✅ Al spawinear un NPC (Dev Menu > Generar > configurar > Spawn), el NPC patrulla/idle sin errores
3. ✅ Cuando un NPC ve al jugador, PerceptionSystem detecta pero NO escribe target_enemy directamente
4. ✅ MemorySystem almacena y expira memorias correctamente
5. ✅ El overlay de debug (Bot Debug Info) sigue funcionando

### Cómo probar
```gdscript
# Desde el Dev Menu:
# 1. Spawnea un NPC en equipo ROJO
# 2. Activa Bot Debug Info para ver qué detecta
# 3. Acércate al NPC — debe detectarte (PerceptionSystem funciona)
# 4. Aléjate — debe recordar tu última posición (MemorySystem funciona)
```


---

## ══════════════════════════════════════════════════════════════
## 🟡 FASE 2 — EXTRACCIÓN DE MOVEMENTSYSTEM
## ══════════════════════════════════════════════════════════════

**Propósito:** Extraer toda la lógica de movimiento del NpcBase a un **MovementSystem** dedicado que sea el **ÚNICO escritor de `velocity`**. Esto elimina el problema crítico de múltiples escritores documentado en la arquitectura.

### Estado actual
- velocity es escrita desde al menos 4 lugares: NpcBase._physics_process (gravedad), _process_movement (dirección), behaviors (behavior_combat escribe velocity.y = 5.0), y posiblemente navigation_system
- No hay un sistema centralizado que gestione el movimiento
- La detección de stuck está mezclada en NpcBase con variables como `_stuck_timer`, `_stuck_progress_timer`, etc.
- NavigationAgent3D se usa directamente desde NpcBase

### Qué hacer

#### 1. Crear `res://scripts/ai/movement_system.gd`
```gdscript
class_name MovementSystem extends Node

# ── PROPIETARIO DE (solo él escribe) ──
var velocity: Vector3           # ← la velocity del CharacterBody3D
var navigation_path: Array[Vector3]
var stuck_state: StuckState     # enum: NONE, STUCK, RECOVERING

# ── LECTURA DE ──
# movement_command (de DecisionSystem)
# NavigationAgent3D (Godot nativo)

# ── NUNCA ESCRIBE ──
# target_entity, combat_command, weapon_state

# ── EVENTOS QUE EMITE ──
signal destination_reached(position: Vector3)
signal stuck_detected(phase: int, cause: String)
signal stuck_resolved()
signal path_blocked(remaining_distance: float)

# ── MÉTODOS ──
func process(delta: float) -> void:
	# 1. Leer movement_command de DecisionSystem
	# 2. Elegir modo: NAVIGATE / DIRECT / DODGE / STOP
	# 3. Consultar NavigationAgent3D si NAVIGATE
	# 4. Calcular desired_velocity
	# 5. Aplicar gravedad SOLO AQUÍ (único lugar)
	# 6. ESCRIBIR velocity (único lugar en todo el bot)
	pass

func post_process(delta: float) -> void:
	# Después de move_and_slide()
	# 1. Verificar stuck por progreso
	# 2. Emitir stuck_detected si aplica
	# 3. Verificar llegada a destino
	pass
```

#### 2. MovementCommand Resource
Crear `res://scripts/ai/movement_command.gd`:
```gdscript
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
```

#### 3. Migrar desde NpcBase
- ✅ Mover toda la lógica de `_process_movement()` a MovementSystem
- ✅ Mover toda la lógica de gravedad a MovementSystem (único lugar que modifica velocity.y)
- ✅ Mover toda la lógica de stuck detection (variables `_stuck_*`) a MovementSystem
- ✅ MovementSystem emite `stuck_detected` — NO decide cómo resolverlo (eso es de DecisionSystem)
- ✅ Eliminar `behavior_combat.gd` línea que hace `velocity.y = 5.0`

#### 4. Flujo en NpcBase._physics_process()
```gdscript
func _physics_process(delta: float) -> void:
	# FASE 1-2: Percepción y memoria (sin cambios)
	perception_system.update(delta)
	memory_system.update(delta)
	
	# FASE 3: Decisión (escribe movement_command, combat_command)
	brain.process(delta)  # o decision_system.process(delta)
	
	# FASE 4: Movimiento (MovementSystem ESCRIBE velocity)
	movement_system.process(delta)
	
	# FASE 5: Combate (escribe aim_rotation)
	combat_system.process(delta)
	
	# FASE 6: Física (move_and_slide LEE velocity)
	move_and_slide()
	
	# FASE 7: Post-movimiento (stuck check, arrival check)
	movement_system.post_process(delta)
```

### Criterios de verificación
1. ✅ El proyecto carga sin errores
2. ✅ NPCs se mueven correctamente (patrulla, persiguen, etc.)
3. ✅ Solo MovementSystem escribe `velocity` — verificar con grep que ningún otro .gd asigna velocity
4. ✅ La detección de stuck emite señales pero NO cambia destinos
5. ✅ El NPC respeta gravedad y navegación igual que antes
6. ✅ Botón "AI Disable" del Dev Menu sigue funcionando

### Cómo probar
```gdscript
# Spawnea 2 NPCs de equipos opuestos
# Activa Bot Debug Info
# Observa que el NPC se mueve normalmente
# Verifica en output que no hay "velocity" siendo escrita desde otros lugares
```

---

## ══════════════════════════════════════════════════════════════
## 🟠 FASE 3 — DECISIONSYSTEM + FSM (la pieza central)
## ══════════════════════════════════════════════════════════════

**Propósito:** Implementar el DecisionSystem con una FSM jerárquica estilo UT99 que sea el **ÚNICO escritor de `target_entity`, `movement_command` y `combat_command`**. Reemplaza el sistema actual de BotBrain + Behaviors por prioridades.

### Estado actual
- BotBrain (493 lines) evalúa behaviors por prioridad cada frame — es un sistema de prioridades plano, sin persistencia de estado
- Behaviors escriben directamente en velocity (violación)
- No hay una máquina de estados real con transiciones, enter/exit, persistencia
- `target_enemy` es escrito por PerceptionSystem Y NpcBase (violación múltiple)

### Qué hacer

#### 1. Clase base BotState
Crear `res://scripts/ai/bot_state.gd`:
```gdscript
class_name BotState extends Node

# Estados posibles de la FSM
enum StateType {
	ACQUISITION, COMBAT, TACTICAL_MOVE, CHARGING, RANGED_ATTACK,
	HUNTING, STAKEOUT, RETREATING, ROAMING, WANDERING, HOLDING, FALLING, TAKING_HIT
}

# Referencias a sistemas
var decision_system: DecisionSystem
var bot: NpcBase
var movement: MovementSystem
var combat: CombatSystem
var perception: PerceptionSystem
var memory: MemorySystem

# Ciclo de vida de estado
func enter(previous_state: BotState) -> void: pass
func execute(delta: float) -> void: pass
func exit(next_state: BotState) -> void: pass

# Manejadores de eventos (cada estado decide si responde)
func on_see_player(player: Node3D) -> void: pass
func on_hear_noise(loudness: float, source: Vector3) -> void: pass
func on_take_damage(amount: float, attacker: Node3D) -> void: pass
func on_hit_wall(normal: Vector3) -> void: pass
func on_stuck_detected(phase: int, cause: String) -> void: pass
func on_destination_reached() -> void: pass
```

#### 2. DecisionSystem (FSM)
Crear `res://scripts/ai/decision_system.gd`:
```gdscript
class_name DecisionSystem extends Node

# ── PROPIETARIO DE (solo él escribe) ──
var target_entity: Node3D
var movement_command: MovementCommand
var combat_command: CombatCommand
var focus_point: Vector3
var current_state: BotState

# ── LECTURA DE ──
# sensor_data (PerceptionSystem)
# memory_store (MemorySystem)
# health, armor (HealthSystem)
# weapon_status (WeaponSystem)
# objectives (ObjectiveSystem)
# stuck_state (MovementSystem)

# ── NUNCA ESCRIBE ──
# velocity, weapon_state, sensor_data, memory_store

# ── EVENTOS ──
signal state_changed(old: BotState, new: BotState)
signal target_selected(entity_id: int)
signal command_issued(cmd_type: String)

func process(delta: float) -> void:
	# 1. Evaluar transiciones de la FSM
	# 2. Ejecutar estado actual: current_state.execute(delta)
	# 3. El estado escribe: movement_command, combat_command, target_entity
	# 4. Validar comandos (no disparar sin target, no navegar a null)
	pass
```

#### 3. Resources adicionales
Crear `res://scripts/ai/combat_command.gd`:
```gdscript
class_name CombatCommand extends Resource
@export var engage: bool = false
@export var target_id: int
@export var fire_mode: int = 0  # 0=primario, 1=alterno
@export var aim_at_position: Vector3
@export var force_fire: bool = false
@export var cease_fire: bool = false
```

#### 4. Estados a implementar (orden recomendado)
1. **State_Roaming** — deambular por el mapa, ir a objetivos del equipo
2. **State_Combat** — raíz de combate, elige sub-estado (TacticalMove, Charging, RangedAttack)
3. **State_Hunting** — perseguir última posición conocida del enemigo
4. **State_Retreating** — huir cuando la salud es baja
5. **State_TacticalMove** — strafe lateral manteniendo frente al enemigo
6. **State_Charging** — cargar directamente hacia el enemigo (escopeta/

---

## ══════════════════════════════════════════════════════════════
## 🔴 FASE 4 — COMBATSYSTEM
## ══════════════════════════════════════════════════════════════

**Propósito:** Crear CombatSystem como el **ÚNICO escritor de `aim_rotation`** y gestor de puntería, modos de fuego y evasión. CombatSystem NUNCA escribe `velocity` — si necesita un salto/evasión, lo solicita a DecisionSystem que decide si concede el dodge.

### Qué hacer

#### 1. Crear `res://scripts/ai/combat_system.gd`
```gdscript
class_name CombatSystem extends Node

# ── PROPIETARIO DE (solo él escribe) ──
var aim_rotation: Quaternion
var dodge_state: DodgeState      # enum: NONE, DODGING, COOLDOWN
var current_target_position: Vector3
var engagement_analysis: EngagementData
var wants_dodge: bool            # Solicitud a DecisionSystem
var dodge_direction: Vector3     # Dirección solicitada

# ── LECTURA DE ──
# combat_command (de DecisionSystem)
# target_entity (de DecisionSystem)
# weapon_status (de WeaponSystem)

# ── NUNCA ESCRIBE ──
# velocity, movement_command, target_entity

signal weapon_fired(hit_result: Array)
signal target_in_range(entity_id: int, distance: float)
signal target_lost(entity_id: int)
signal dodge_requested(direction: Vector3)

func process(delta: float) -> void:
	# 1. Leer combat_command de DecisionSystem
	# 2. Si engage=true: calcular aim hacia target
	# 3. Aplicar error de puntería (según skill/bot profile)
	# 4. Ajustar por tipo de arma (splash → apuntar al suelo, lead → predecir)
	# 5. ESCRIBIR aim_rotation (único lugar)
	# 6. Si aplica: marcar wants_dodge = true (NO escribir velocity)
	# 7. Emitir fire_request a WeaponSystem
	pass
```

#### 2. Migrar desde NpcBase y behavior_combat.gd
- ✅ Toda la lógica de puntería (mirar al enemigo) → CombatSystem
- ✅ Cálculo de aim_rotation → CombatSystem (único escritor)
- ✅ Lógica de dodge/evasión → CombatSystem SOLO solicita (wants_dodge), no ejecuta
- ✅ Eliminar `behavior_combat.gd` línea que hace `velocity.y = 5.0` (ya se eliminó en Fase 2, verificar)
- ✅ CombatSystem NUNCA llama `move_and_slide()` ni escribe `velocity`

#### 3. CombatSystem + MovementSystem coordinación
```
CombatSystem detecta que sería bueno esquivar:
  → combat_system.wants_dodge = true
  → combat_system.dodge_direction = Vector3.LEFT

DecisionSystem.process() ve wants_dodge:
  → Si concede: movement_command = {mode: DODGE, direction: left}
  → Si no concede (ej: al borde de precipicio): ignora

MovementSystem.process() ejecuta el dodge:
  → movement_command.mode == DODGE
  → Calcula velocity con impulso lateral
  → MovementSystem escribe velocity (único lugar)
```

### Criterios de verificación
1. ✅ NPCs apuntan al jugador correctamente (aim_rotation)
2. ✅ NPCs disparan según modo de fuego (primario/alterno)
3. ✅ El error de puntería varía según skill del bot
4. ✅ CombatSystem NUNCA escribe velocity (verificar con grep)
5. ✅ Los NPCs strafean durante combate (TacticalMove dodge)
6. ✅ El overlay de debug muestra aim direction

---

## ══════════════════════════════════════════════════════════════
## 🔴 FASE 5 — WEAPONSYSTEM + AI PROFILES
## ══════════════════════════════════════════════════════════════

**Propósito:** Completar el WeaponSystem con AI Profiles para que los bots elijan armas inteligentemente según distancia, situación y perfil. Cada arma tiene un `WeaponAIProfile` (Resource) que describe su uso táctico.

### Estado actual
- `weapon.gd` (136 lines): Sistema básico de armas con stats desde JSON
- No hay AIProfile — los bots no pueden evaluar qué arma usar
- La selección de armas es manual o por defecto

### Qué hacer

#### 1. Crear `res://scripts/ai/weapon_ai_profile.gd`
```gdscript
class_name WeaponAIProfile extends Resource

@export var weapon_name: String
@export var ai_rating: float = 0.5            # Poder general del arma
@export var preferred_range_min: float = 2.0   # Distancia mínima óptima
@export var preferred_range_max: float = 30.0  # Distancia máxima óptima
@export var splash_damage: bool = false        # ¿Daño por área?
@export var lead_target: bool = true           # ¿Predecir posición?
@export var refire_rate: float = 0.8           # Probabilidad de seguir disparando
@export var aim_error_base: int = 2000         # Error base de puntería
@export var attack_style_modifier: float = 0.0 # -1.0 defensivo, +1.0 agresivo
@export var prefers_alt_fire: bool = false     # ¿Usar modo alterno?
@export var is_melee: bool = false
@export var is_instant_hit: bool = true        # ¿Hit scan o proyectil?
```

#### 2. Integrar con Weapon existente
- Weapon.load_ai_profile() — cargar el perfil desde un recurso .tres
- Weapon.get_ai_rating(context) — evaluar el arma según distancia, cobertura, etc.
- Weapon.suggest_attack_style() — qué tan agresivo usar esta arma

#### 3. Sistema de selección de armas para bots
El bot debe poder:
- Evaluar todas sus armas disponibles
- Elegir la mejor según: distancia al enemigo, salud del bot, cobertura, munición restante
- Cambiar de arma cuando la situación cambia (WeaponSystem emite señal)

#### 4. WeaponSystem como gestor
```gdscript
class_name WeaponSystem extends Node

var weapon_status: Dictionary    # Estado actual del arma
var ammo_count: int
var reserve_ammo: int
var available_weapons: Array[Weapon]
var current_weapon: Weapon
var ai_profiles: Dictionary      # nombre_arma → WeaponAIProfile

signal weapon_ready()
signal weapon_empty()
signal reload_started(duration: float)
signal reload_completed()
signal ammo_changed(current: int, reserve: int)
signal weapon_switched(new_weapon: String, rating: float)

func get_best_weapon_for(target_distance: float, context: Dictionary) -> Weapon:
	# Evaluar todas las armas disponibles
	# Usar WeaponAIProfile.ai_rating + preferred_range
	# Devolver la mejor opción
	pass
```

### Criterios de verificación
1. ✅ Cada arma tiene su WeaponAIProfile configurado
2. ✅ Los bots eligen armas según distancia al enemigo
3. ✅ Los bots cambian de arma cuando el enemigo se acerca/se aleja
4. ✅ El rating del arma se muestra en el overlay de debug
5. ✅ Armas con splash damage apuntan al suelo (no directo al enemigo)
6. ✅ Armas con lead_target predicen posición futura

---

## ══════════════════════════════════════════════════════════════
## 🔵 FASE 6 — OBJECTIVESYSTEM + ORDERSYSTEM (Team AI)
## ══════════════════════════════════════════════════════════════

**Propósito:** Implementar el sistema de objetivos de equipo y órdenes de bots. El archivo `team_ai.gd` actualmente está **VACÍO** y necesita implementación completa.

### Estado actual
- `team_ai.gd`: VACÍO — sin implementación
- No hay un sistema que asigne objetivos a los bots
- Los bots actúan individualmente sin coordinación de equipo
- Los cores existen en el mapa pero no hay lógica de ataque/defensa organizada

### Qué hacer

#### 1. Implementar ObjectiveSystem (en team_ai.gd o como autoload)
```gdscript
# Propietario de: objectives, orders, scores
# NUNCA escribe en bots (solo emite señales)

signal objective_updated(objective: Objective, bot_id: int)
signal objective_completed(objective_id: String, team: int)
signal orders_changed(bot_id: int, new_orders: String, target: NodePath)

func get_objectives_for_team(team: int) -> Array[Objective]:
	# Devolver objetivos activos para el equipo
	# Ej: "Atacar Core Rojo", "Defender Core Azul"
	pass

func assign_order(bot_id: int, order_type: String, target: NodePath) -> void:
	# Asignar orden a un bot específico
	pass
```

#### 2. Crear Objective Resource
```gdscript
class_name Objective extends Resource
@export var objective_id: String
@export var objective_type: String  # CAPTURE, DEFEND, ATTACK, RETURN, ESCORT, HOLD
@export var target_node: NodePath
@export var position: Vector3
@export var team: int
@export var priority: float
@export var completion_radius: float
@export var is_completed: bool
@export var fallback_objective: String
```

#### 3. Implementar OrderSystem (subsistema)
```gdscript
# Tipos de órdenes (estilo UT99):
# FREELANCE — sin órdenes, el bot decide
# ATTACK — atacar objetivo del equipo
# DEFEND — defender un punto específic

o
# DEFEND — defender un punto específico
# FOLLOW — seguir a un líder
# HOLD — mantener posición fija

# Separación RealOrders vs CurrentOrders:
# real_orders: orden original persistente
# current_orders: puede cambiar temporalmente (ej: "vi enemigo, lo persigo")
# Cuando el bot termina su acción temporal, vuelve a real_orders
```

#### 4. Integrar con la FSM (Fase 3)
- Los estados de la FSM deben leer `objectives` y `orders` del ObjectiveSystem
- State_Roaming: si tiene orden ATTACK, navegar hacia objetivo del equipo
- State_Combat: si tiene orden DEFEND, no alejarse del punto defendido
- State_Retreating: si tiene orden FOLLOW, retirarse hacia el líder

### Criterios de verificación
1. ✅ team_ai.gd implementado con ObjectiveSystem funcional
2. ✅ Los bots reciben órdenes al iniciar la partida
3. ✅ Los bots atacan el core enemigo si tienen orden ATTACK
4. ✅ Los bots defienden su core si tienen orden DEFEND
5. ✅ Un bot con orden FREELANCE actúa por su cuenta
6. ✅ Un bot puede desviarse temporalmente de su orden pero vuelve a ella
7. ✅ El Dev Menu puede mostrar la orden actual de cada bot

---

## ══════════════════════════════════════════════════════════════
## 🟣 FASE 7 — SEMANTIC NAVIGATION
## ══════════════════════════════════════════════════════════════

**Propósito:** Implementar puntos de navegación semántica (AmbushPoints, DefensePoints, AlternatePaths) que los bots usen para tomar decisiones tácticas avanzadas.

### Estado actual
- `navigation_system.gd` (1399 lines): Sistema legacy demasiado grande que necesita refactor
- No hay puntos tácticos en los mapas
- Los bots navegan pero no tienen conceptos de "buen punto de emboscada" o "posición defensiva"

### Qué hacer

#### 1. Crear SemanticPoint Resource
```gdscript
class_name SemanticPoint extends Resource
@export var position: Vector3
@export var point_type: String  # PATH, AMBUSH, DEFENSE, ALTERNATE, LIFT, ITEM
@export var team: int = -1     # -1 = neutral
@export var priority: int = 0
@export var look_direction: Vector3
@export var sight_radius: float = 50.0
@export var extra_cost: float = 0.0
@export var tags: Array[String]
@export var is_sniper_spot: bool = false
@export var is_one_way: bool = false
```

#### 2. Colocar puntos en el mapa activo (map_1.tscn)
- Marcar posiciones de cobertura como AMBUSH
- Marcar entradas de base como DEFENSE
- Marcar rutas alternativas como ALTERNATE
- Marcar spawns de items como ITEM

#### 3. Integrar con NavigationSystem (refactorizado)
- NavigationSystem se reduce a: gestionar navmesh + semantic_points
- NavigationSystem NUNCA escribe en bots
- Los bots consultan: "dame el ambush point más cercano al enemigo"
- MovementSystem usa NavigationAgent3D nativo para pathfinding
- La vieja lógica de stuck y auto-jump se elimina (ya en MovementSystem)

#### 4. Integrar con DecisionSystem
- State_TacticalMove: puede elegir moverse hacia un ambush point
- State_Defend (nuevo): moverse al defense point asignado
- State_Roaming: puede incluir visitar puntos estratégicos

### Criterios de verificación
1. ✅ SemanticPoints colocados en map_1.tscn (al menos 5-10 puntos)
2. ✅ Los bots pueden consultar puntos por tipo y equipo
3. ✅ Un bot con orden DEFEND se posiciona en un DefensePoint
4. ✅ Un bot en combate puede usar AmbushPoints para flanquear
5. ✅ NavigationSystem legacy se reduce significativamente
6. ✅ El overlay de debug muestra los semantic points cercanos

---

## ══════════════════════════════════════════════════════════════
## ⚪ FASE 8 — LIMPIEZA DE LEGACY
## ══════════════════════════════════════════════════════════════

**Propósito:** Eliminar todo el código legacy una vez que los nuevos sistemas están funcionando. Dejar NpcBase como un CharacterBody3D limpio que solo inicializa y conecta sistemas modulares.

### Qué hacer

#### 1. Limpiar NpcBase (~150 líneas final)
```gdscript
extends CharacterBody3D
class_name NpcBase

var perception_sys: PerceptionSystem
var memory_sys: MemorySystem
var decision_sys: DecisionSystem
var movement_sys: MovementSystem
var combat_sys: CombatSystem
var weapon_sys: WeaponSystem
var health_sys: HealthSystem

func _ready() -> void:
	_init_systems()
	_connect_signals()
	_load_profile()

func _physics_process(delta: float) -> void:
	if is_dead: return
	perception_sys.update(delta)
	memory_sys.update(delta)
	decision_sys.process(delta)
	movement_sys.process(delta)
	combat_sys.process(delta)
	weapon_sys.process(delta)
	move_and_slide()
	movement_sys.post_process(delta)

func take_damage(...) -> void:
	health_sys.take_damage(...)
```

#### 2. Eliminar behaviors legacy
- behavior_combat.gd, behavior_hunt.gd, behavior_patrol.gd, behavior_idle.gd → ELIMINAR
- bot_behavior.gd → ELIMINAR (clase base ya no necesaria)
- BotBrain.gd → ELIMINAR (reemplazado por DecisionSystem)

#### 3. Refactorizar NavigationSystem legacy (1399 → ~200 lines)
- Eliminar lógica de stuck, auto-jump, avoidance
- Mantener solo: gestión de navmesh + semantic_points

#### 4. Eliminar código muerto
- decision_context.gd, check_nav.gd → evaluar si siguen siendo necesarios
- test_stuck_detection.gd → actualizar tests para nueva arquitectura

### Criterios de verificación
1. ✅ NpcBase reducido de 1112 a ~150 líneas
2. ✅ Cero violaciones de arquitectura
3. ✅ Proyecto compila sin errores
4. ✅ NPCs se comportan IGUAL o MEJOR que antes
5. ✅ Dev Menu funciona al 100%
6. ✅ grep de "velocity =" solo muestra MovementSystem

---

## 🧪 DEV MENU — MEJORAS CONTINUAS POR FASE

### En Fase 2 (MovementSystem)
- Mostrar "MovementMode" actual del NPC
- Botón "Mostrar Path" — DebugDraw3D del camino actual

### En Fase 3 (DecisionSystem/FSM)
- Mostrar "Estado FSM" actual en el overlay
- Botón "Forzar Estado" — cambiar manualmente el estado de un NPC

### En Fase 4 (CombatSystem)
- Mostrar "Aim Direction" como línea 3D en debug
- Mostrar "Fire Mode" actual

### En Fase 5 (WeaponSystem)
- Mostrar "Arma actual" y "Mejor arma según distancia"
- Botón "Dar todas las armas" al NPC seleccionado

### En Fase 6 (ObjectiveSystem)
- Mostrar "Orden actual" de cada NPC
- Botón "Asignar Orden" (ATTACK, DEFEND, FOLLOW, HOLD)

### En Fase 7 (Semantic Navigation)
- Mostrar SemanticPoints en el mapa como marcadores 3D
- Botón "Ir al punto"

---

## 📐 REFERENCIA RÁPIDA DE RESOURCES

| Resource | Archivo | Escribe | Lee | Fase |
|----------|---------|---------|-----|------|
| MovementCommand | movement_command.gd | DecisionSystem | MovementSystem | 2 |
| CombatCommand | combat_command.gd | DecisionSystem | CombatSystem | 3 |
| BotState | bot_state.gd | DecisionSystem | — (base class) | 3 |
| WeaponAIProfile | weapon_ai_profile.gd | Config/Weapon | CombatSystem | 5 |
| Objective | objective.gd | ObjectiveSystem | DecisionSystem | 6 |
| SemanticPoint | semantic_point.gd | NavigationSystem | DecisionSystem | 7 |
| BotProfile | bot_profile.gd | SkillSystem | DecisionSystem | 3+ |

---

## ✅ CHECKLIST GENERAL POR FASE

Cada fase debe pasar esto antes de considerar completa:
1. ✅ Escena `npc.tscn` carga sin errores
2. ✅ Escena `map_1.tscn` carga sin errores
3. ✅ Dev Menu funcional (Q abre/cierra)
4. ✅ Spawn de NPC configurable funciona
5. ✅ AI Disable toggle funciona
6. ✅ Bot Debug Info muestra datos relevantes
7. ✅ grep de "velocity =" solo en MovementSystem
8. ✅ grep de "target_enemy =" solo en DecisionSystem
9. ✅ Sin errores en output de Godot
10. ✅ Playtest de 30s sin crashes

---

*Documento generado el 30 de Junio, 2026*
*Próximo paso: Elegir fase, copiar su contenido, pegar en chat nuevo, comenzar.*
