# GUÍA RÁPIDA - SISTEMAS DE NAVEGACIÓN Y MOVIMIENTO

**Actualizado:** 7 de Julio 2026 (Post-Limpieza)

---

## 🗺️ ARQUITECTURA DE NAVEGACIÓN (DIAGRAMA)

```
Game Start
    ↓
MapManager._setup_match()
    ├─ _replace_cores() — Instanciar objetivos
    ├─ _configure_spawners() — Configurar puntos spawn
    ├─ _update_navigation() — Hornear NavMesh
    └─ _instantiate_semantic_points() → carga puntos semánticos
            ↓
NavigationSystem.load_semantic_points()
    ├─ Busca nodos SemanticPointMarker en el árbol (grupo "semantic_points")
    ├─ Convierte cada marker a SemanticPoint usando to_semantic_point()
    └─ Almacena en NavigationSystem.all_semantic_points (ESTÁTICO)

Cuando NpcBase spawn:
    ├─ NpcBase._ready()
    ├─ MovementSystem._ready()
    │   └─ Se conecta a agent.velocity_computed signal (RVO avoidance)
    ├─ BotBrain: toma decisiones
    │   └─ Emite MovementCommand al MovementSystem
    └─ MovementSystem.process(delta)
        └─ Ejecuta el comando de movimiento

Cada frame:
    1. DecisionSystem/BotBrain evalúa estado
    2. DecisionSystem.set_movement_command()
    3. MovementSystem.process() → lee command y asigna velocity
    4. NpcBase.move_and_slide() → aplica velocity + física
    5. MovementSystem.post_process() → verifica stuck, etc.
```

---

## 📁 ESTRUCTURA DE ARCHIVOS (DESPUÉS DE LIMPIEZA)

### Sistema de Navegación

```
res://scripts/ai/navigation/
├── navigation_system.gd .................. 193 LOC
│   ├─ Gestión estática de puntos semánticos
│   ├─ Búsqueda de puntos por tipo/equipo
│   └─ Interfaz de consulta (get_nearest_point, get_points_sorted)
│
├── semantic_point.gd .................... 195 LOC ✅ ÚNICO
│   ├─ Enum: ASSAULT, DEFENSE, ALTERNATE, PATH, OBJECTIVE, DUAL, TERCER
│   ├─ Propiedades: position, team, secondary_position
│   └─ Métodos: get_type_name(), _to_string()
│
└── semantic_point_marker.gd ............ 108 LOC ✅ ÚNICO
    ├─ Extends Marker3D (para editor)
    ├─ Propiedades @export para configurar puntos
    └─ Método: to_semantic_point() → convierte a SemanticPoint
```

### Sistema de Movimiento

```
res://scripts/ai/
├── movement_system.gd ................... 918 LOC (cleanest version)
│   ├─ Ejecución de comandos: NAVIGATE, DIRECT, HOLD, DODGE, STOP
│   ├─ Detección de atasco (stuck detection)
│   ├─ Manejo de rampas y escalones
│   ├─ Integración VaultController
│   └─ RVO avoidance nativo de Godot
│
├── [otros sistemas]
│   └─ bot_behavior.gd, bot_brain.gd, decision_system.gd, etc.
```

### Mapa y Configuración

```
res://scripts/
├── map_manager.gd ........................ 309 LOC
│   ├─ Reemplaza cores CSGBox3D
│   ├─ Configura spawners
│   ├─ Hornea NavMesh mejorado
│   └─ Carga puntos semánticos
│
└── [otros managers]
```

### ARCHIVADO (No activo pero recuperable)

```
res://scripts/
└── _unused_route_diversifier.gd ........ 255 LOC 📦
    └─ Sistema de diversificación de rutas (experimental)
        ├─ Rutas: DIRECT, LEFT, RIGHT, WIDE_LEFT, WIDE_RIGHT
        └─ Nunca fue integrado en comportamientos
```

---

## 🎮 TIPOS DE PUNTOS SEMÁNTICOS

**Definidos en:** `SemanticPoint.PointType` (enum en `semantic_point.gd`)

| Tipo | Valor | Uso | Bots que lo usan |
|------|-------|-----|------------------|
| **ASSAULT** | 0 | Puntos de asalto hacia base enemiga | ASSAULT bots |
| **DEFENSE** | 1 | Puntos defensivos para proteger base | DEFENDER bots |
| **ALTERNATE** | 2 | Rutas alternas de flanqueo | FLANKER bots |
| **PATH** | 3 | Puntos de patrulla | PATROLLER bots |
| **OBJECTIVE** | 4 | Punto objetivo azul (+ salto al cyan) | ASSAULT, FLANKER |
| **DUAL** | 5 | Punto compartido (verde oscuro) | ASSAULT, FLANKER |
| **TERCER** | 6 | Tercer camino (verde oscuro) | ASSAULT, FLANKER |

**Cómo crear un punto en el mapa:**
1. Añadir nodo `Marker3D` al mapa
2. Attachar script `SemanticPointMarker` (desde res://scripts/ai/navigation/)
3. Configurar propiedades:
   - `point_type`: seleccionar del enum
   - `team`: -1 (cualquier equipo) o 0, 1, 2... (equipo específico)
   - `point_name`: nombre descriptivo para debug
   - `punto_final_salto_path`: si es OBJECTIVE, enlazar nodo destino
4. El punto se registrará automáticamente en `_ready()`

---

## 🚀 FLUJO DE MOVIMIENTO

### 1. COMANDO DE MOVIMIENTO

**Generado por:** BotBrain / DecisionSystem

**Estructura:**
```gdscript
class MovementCommand:
    enum Mode { NAVIGATE, DIRECT, HOLD, DODGE, STOP, NONE }
    
    var mode: int = Mode.NONE
    var target_position: Vector3 = Vector3.ZERO
    var direction: Vector3 = Vector3.ZERO
    var speed: float = 5.0
    var jump: bool = false
    var jump_velocity: float = 7.0
    var dodge_direction: Vector3 = Vector3.ZERO
    var dodge_impulse: float = 15.0
```

**Uso:**
```gdscript
var cmd: MovementCommand = MovementCommand.new()
cmd.mode = MovementCommand.Mode.NAVIGATE
cmd.target_position = enemy_position
cmd.speed = 6.0
movement_system.command = cmd
```

### 2. EJECUCIÓN EN MovementSystem

**Método:** `process(delta)`

Según el `command.mode`:
- **NAVIGATE:** Usar NavigationAgent3D hacia target
- **DIRECT:** Movimiento directo por vector
- **HOLD:** Frenar gradualmente
- **DODGE:** Impulso lateral
- **STOP:** Parada inmediata
- **NONE:** Sin comando (legacy compatibility)

### 3. APLICACIÓN DE FÍSICA

**Después de asignar velocity:**
1. Gravedad se aplica (si no está en piso)
2. Auto-jump si hay escalón detectado
3. Vault si hay obstáculo
4. move_and_slide() aplica los cambios

---

## 🔍 BÚSQUEDA DE PUNTOS SEMÁNTICOS

**API estática en NavigationSystem:**

```gdscript
# Obtener el punto más cercano de un tipo
var point: SemanticPoint = NavigationSystem.get_nearest_point(
    point_type: int,           # SemanticPoint.PointType.ASSAULT
    from_pos: Vector3,         # bot.global_position
    team_filter: int = -1,     # -1 = cualquier equipo
    max_dist: float = INF      # radio máximo
)

# Obtener todos los puntos de un tipo, ordenados por distancia
var points: Array[SemanticPoint] = NavigationSystem.get_points_sorted(
    point_type: int,
    from_pos: Vector3,
    team_filter: int = -1,
    max_dist: float = INF
)

# Verificar si hay punto cercano
var has_point: bool = NavigationSystem.has_point_nearby(
    point_type: int,
    from_pos: Vector3,
    team_filter: int = -1,
    radius: float = 8.0
)
```

---

## 🛑 DETECCIÓN DE ATASCO (STUCK)

**Ubicación:** `MovementSystem._check_stuck()`, `_handle_stuck_recovery()`

**Fases de recovery:**
1. **Fase 1 (0.4s):** Retroceder para encontrar espacio libre
2. **Fase 2 (0.4s):** Movimiento lateral para evitar bloqueo
3. **Fase 3:** Recalcular camino y continuar

**Señales emitidas:**
- `stuck_detected(phase, cause)` - Cuando se detecta atasco
- `stuck_resolved()` - Cuando se resuelve

**Thresholds por comportamiento:**
```gdscript
const STUCK_PROGRESS_THRESHOLD = {
    "idle":   8.0,
    "patrol": 2.5,
    "combat": 2.5,
    "hunt":   2.0,
}
```

---

## 🏔️ MANEJO DE RAMPAS Y ESCALONES

**Constantes en MovementSystem:**

```gdscript
CLIMB_HEIGHT_THRESHOLD = 0.05      # Altura mín. para subir
AUTO_JUMP_HEIGHT = 0.55            # Altura para saltar escalones
AUTO_JUMP_MAX_HEIGHT = 1.8         # Altura máxima permitida
STEP_ASSIST_VELOCITY = 3.5         # Velocidad de step-up
STEP_DOWN_MAX_HEIGHT = 1.8         # Bajada máxima
```

**Lógica:**
1. Detectar altura del siguiente waypoint (`height_diff`)
2. Si es rampa: aplicar velocidad Y para escalar (`climb_y`)
3. Si es escalón: auto-jump si entra en rango
4. Si es bajada: aplicar step-down assist

---

## ⚙️ CONFIGURACIÓN PARA NUEVOS MAPAS

### Paso 1: Preparar NavMesh

El `MapManager` automáticamente:
1. Hornea NavMesh mejorado
2. Excluye techos
3. Verifica cobertura en spawn y cores

### Paso 2: Colocar puntos semánticos

Patrón de puntos típico para asalto:

```
Spawner Azul
    ↓
Punto ASSAULT (hacia centro)
    ↓
Centro del mapa
    ├─ Punto OBJECTIVE (cubo azul)
    └─ Punto DUAL/TERCER (flanqueos alternativos)
    ↓
Punto ASSAULT (hacia core rojo)
    ↓
Core Rojo (DEFENSE)
    ├─ Punto DEFENSE (proteger)
    └─ Punto ALTERNATE (retaguardia)
```

### Paso 3: Testing

1. Ejecutar escena del mapa
2. Verificar `[MapManager]` logs de puntos cargados
3. Colocar bot y verificar NavigationAgent3D funciona
4. Ejecutar `playtest` y observar movimiento

---

## 🐛 DEBUGGING

### Visualización de puntos en editor

Todos los `SemanticPointMarker` son visibles en editor:
- Verde claro = PATH
- Azul claro = DEFENSE
- Naranja = AMBUSH
- Magenta = ALTERNATE
- etc.

### Logs útiles

```gdscript
# En _ready() de NpcBase:
print("[NPC] NavigationSystem tiene %d puntos cargados" % 
      NavigationSystem.all_semantic_points.size())

# Cuando busca punto:
var point = NavigationSystem.get_nearest_point(...)
print("[NPC] Punto más cercano: %s" % point)

# Estado de stuck:
if movement_system.is_stuck_flag:
    print("[NPC] ATASCADO - Fase: %d" % movement_system.stuck_recovery_phase)
```

### Dev Menu (Q)

Presionar **Q** en juego para abrir menú de debug que muestra:
- Decisiones del bot
- Comandos de movimiento actual
- Estado de navegación

---

## 🚨 PROBLEMAS COMUNES Y SOLUCIONES

### Problema: "NavMesh muy pequeño, bots no se mueven"
**Causa:** NavMesh no cubre toda el área jugable
**Solución:** Verificar logs de MapManager sobre cobertura

### Problema: "Bot se queda pegado en esquina"
**Causa:** Stuck detection activado, pero recovery falla
**Solución:** Verificar que hay espacio para fase 1 (retroceso)

### Problema: "Bot saltando constantemente"
**Causa:** AUTO_JUMP_HEIGHT demasiado bajo
**Solución:** Aumentar de 0.55 a 0.7-0.8 si hay falsos positivos

### Problema: "Puntos semánticos no se cargan"
**Causa:** Nodos no en grupo "semantic_points" o sin script
**Solución:** Usar SemanticPointMarker de navigation/ folder

---

## 📚 REFERENCIAS CLAVE

**Archivos CORE:**
- `res://scripts/ai/navigation/navigation_system.gd` - Gestor de puntos
- `res://scripts/ai/navigation/semantic_point.gd` - Definición de punto
- `res://scripts/ai/navigation/semantic_point_marker.gd` - Editor tool
- `res://scripts/ai/movement_system.gd` - Movimiento físico
- `res://scripts/map_manager.gd` - Setup de mapa

**Archivos COMPORTAMIENTO:**
- `res://scripts/ai/bot_brain.gd` - IA principal
- `res://scripts/ai/decision_system.gd` - Toma de decisiones
- `res://scripts/ai/behaviors/behavior_*.gd` - Comportamientos específicos

**ESTADO ACTUAL POST-LIMPIEZA:**
- ✅ Duplicados eliminados
- ✅ Código legacy removido
- ✅ Sistema estable y limpio
- ✅ Listo para refactoring futuro

---

**Última actualización:** 7 de Julio 2026
**Limpieza ejecutada por:** Ziva Refactoring Agent
**Status:** ✅ PRODUCCIÓN

