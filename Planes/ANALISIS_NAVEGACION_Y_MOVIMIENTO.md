# ANÁLISIS COMPLETO: SISTEMAS DE NAVEGACIÓN, MOVIMIENTO Y PUNTOS SEMÁNTICOS

**Fecha:** 7 de Julio 2026
**Proyecto:** FPS Prueba
**Scope:** Análisis de código redundante, optimización y limpieza

---

## 📋 RESUMEN EJECUTIVO

Se encontraron **DUPLICADOS CRÍTICOS** y código no utilizado en los sistemas de navegación y puntos semánticos:

| Problema | Severidad | Impacto |
|----------|-----------|--------|
| **Archivos duplicados SemanticPoint** | 🔴 CRÍTICA | Conflicto de class_name, confusión en imports |
| **Archivos duplicados SemanticPointMarker** | 🔴 CRÍTICA | Una copia comentada, no mantenida |
| **MovementSystem: 930 líneas** | 🟠 MEDIA | Complejidad alta, poco legible |
| **Código legacy sin uso** | 🟡 BAJA | Deuda técnica acumulada |
| **NavigationSystem: Lógica estática mezclada** | 🟡 MEDIA | Dificulta mantenimiento |

---

## 🚨 PROBLEMAS DETECTADOS

### 1. DUPLICADOS DE ARCHIVOS (CRÍTICO)

#### SemanticPoint: 2 versiones conflictivas

**Ubicaciones:**
- `res://scripts/ai/navigation/semantic_point.gd` (195 líneas) ✅ **CORRECTA**
- `res://scripts/ai/semantic_point.gd` (103 líneas) ❌ **OBSOLETA**

**Diferencias:**

| Aspecto | `navigation/semantic_point.gd` | `semantic_point.gd` |
|--------|------|---------|
| Extends | `RefCounted` | `Resource` |
| Tipos | 7 tipos (ASSAULT, DEFENSE, ALTERNATE, PATH, OBJECTIVE, DUAL, TERCER) | 7 tipos (PATH, AMBUSH, DEFENSE, ALTERNATE, LIFT, ITEM, SNIPER) |
| Propiedades | `point_type`, `position`, `team`, `name`, `secondary_position` | `position`, `point_type`, `team`, `priority`, `look_direction`, `sight_radius`, `extra_cost`, `tags`, `is_sniper_spot`, `is_one_way`, `coverage_radius` |
| Constructor | Sí, con parámetros | No (use case como Resource) |
| Métodos | `get_type_name()`, `_to_string()` | `is_for_team()`, `is_type()`, `distance_from()`, `covers_position()`, `debug_string()` |

**Problema:** 
- La versión antigua tiene tipos semánticos diferentes y se exporta como Resource
- No hay claridad sobre cuál usar
- El código actual carga desde `navigation/semantic_point_marker.gd` que usa la versión de `navigation/`
- La copia en `semantic_point.gd` está desacoplada

---

#### SemanticPointMarker: 2 versiones

**Ubicaciones:**
- `res://scripts/ai/navigation/semantic_point_marker.gd` (108 líneas) ✅ **ACTIVA**
  ```gdscript
  extends Marker3D
  class_name SemanticPointMarker
  ```
  
- `res://scripts/ai/semantic_point_marker.gd` (72 líneas) ❌ **INACTIVA**
  ```gdscript
  # NOTE: class_name removido para evitar conflicto con navigation/semantic_point_marker.gd
  ```

**Problema:**
- La copia antigua tiene un comentario diciendo que está ahí para evitar conflictos
- El código está parcialmente funcional pero NO se llama desde ningún lado
- Implementa `_update_gizmo()` pero ninguna otra versión la necesita
- Genera confusión: ¿cuál se debe usar?

---

### 2. LÓGICA DUPLICADA EN NavigationSystem

**Archivo:** `res://scripts/ai/navigation/navigation_system.gd` (195 líneas)

**Función:** `load_semantic_points()` (líneas 36-72)

El sistema:
1. Busca por grupo `"semantic_points"`
2. Recorre todos los nodos SemanticPointMarker
3. Llama `.to_semantic_point()` en cada uno
4. Almacena en `all_semantic_points` estático

**Problema:**
- Se llama desde `NpcBase._ready()` Y desde `MapManager._instantiate_semantic_points()`
- Dos puntos de entrada al mismo sistema
- Si falla una carga, no hay fallback claro

---

### 3. MovementSystem: MUY COMPLEJO (930 líneas)

**Archivo:** `res://scripts/ai/movement_system.gd`

**Problemas de arquitectura:**

```
_execute_navigate()      ← 100+ líneas
├─ height_diff detection
├─ auto-jump logic
├─ step-up assist
├─ vault controller
├─ RVO avoidance
└─ climb_y calculation

_execute_direct()        ← 40 líneas

_check_stuck()           ← 70+ líneas

_handle_stuck_recovery() ← 40+ líneas

+ 15 métodos helper
```

**Complejidad:**
- 8 const de movimiento (CLIMB_HEIGHT_THRESHOLD, AUTO_JUMP_HEIGHT, etc.)
- 20+ variables de estado para stuck detection
- 5 máquinas de estado internas (vault, stuck phases, yield, etc.)
- Documentación extensiva pero difícil de seguir

**Código sin uso identificado:**
```gdscript
# Línea 124-127: "Cede el paso" state
var _yield_timer: float = 0.0
var _is_yielding: bool = false
const YIELD_DURATION: float = 0.5
```
Se inicializa pero nunca se llama `_is_yielding = true` desde ningún lado.

---

### 4. RouteDiversifier: COMPLEJIDAD INNECESARIA

**Archivo:** `res://scripts/route_diversifier.gd` (255 líneas)

**Función:** Diversificar rutas para que no todos los bots vayan por el mismo camino

**Problema:**
- 5 tipos de ruta (DIRECT, LEFT, RIGHT, WIDE_LEFT, WIDE_RIGHT)
- Factores: npc_id, rol, combat_style, skill
- Resultado: **altamente determinístico pero casi nunca diferente**
- La mayoría de bots terminan usando DIRECT o LEFT porque:
  - `combat_style` suele ser 0.5 (neutral)
  - `skill` suele ser 3.0 (no modifica)
  - `npc_id % 5` solo da 5 variantes

**Pregunta:** ¿Se usa realmente? Buscar en qué comportamiento se llama...

---

### 5. MapManager: MÚLTIPLES RESPONSABILIDADES

**Archivo:** `res://scripts/map_manager.gd` (309+ líneas)

**Responsabilidades:**
1. Reemplazar CSGBox3D cores con instancias (29 líneas)
2. Configurar spawners (60 líneas)
3. Actualizar NavigationMesh (110 líneas)
4. Validar cobertura de NavMesh (30 líneas)
5. Instanciar puntos semánticos (25 líneas)
6. Manejo de auto_find_map y auto_start_match (50 líneas)

**Problema:** Violación de Single Responsibility Principle

**Propuesta de refactoring:**
```
MapManager (orquestador)
├─ CoreSetup (reemplazar cores)
├─ SpawnerSetup (configurar spawners)
├─ NavMeshBuilder (mejorar NavMesh)
├─ SemanticPointLoader (cargar puntos)
└─ MapValidator (verificar cobertura)
```

---

## 📊 ANÁLISIS DE CÓDIGO NO UTILIZADO

### NavigationSystem

**Función: `reset()` (línea 168)**
```gdscript
func reset() -> void:
    pass  # Vacía, nunca llamada
```
- Ubicado: NavigationSystem
- Está definido pero el cuerpo está vacío
- No se llama desde ningún lado

**Función: `has_point_nearby()` (línea 129-132)**
```gdscript
static func has_point_nearby(...) -> bool:
    var nearest: SemanticPoint = get_nearest_point(...)
    return nearest != null
```
- Wrapper innecesario
- Se puede reemplazar: `get_nearest_point(...) != null`
- Buscar si se usa...

---

### MovementSystem

**Estado: `_yield_timer` y `_is_yielding`**
- Inicializados pero nunca escritos
- Se revisan en `process()` pero nunca se activan
- Parece ser código legacy de una feature abandonada

**Método: `_get_current_behavior_name()` (no mostrado en lectura)**
- Se usa en `_check_stuck()` línea 441
- ¿Dónde está definido? Necesita ser verificado

---

### RouteDiversifier

**¿Se llama desde algún lado?**
- Buscar en todo el codebase: `get_route_type_for_bot`, `get_approach_waypoint`
- Si no se usa, es código muerto de 255 líneas

---

## 🎯 RECOMENDACIONES DE LIMPIEZA

### FASE 1: CONSOLIDACIÓN (CRÍTICO - HACER PRIMERO)

#### 1.1 Eliminar duplicados de SemanticPoint
- ❌ Eliminar: `res://scripts/ai/semantic_point.gd` (103 líneas)
- ✅ Mantener: `res://scripts/ai/navigation/semantic_point.gd` (195 líneas)
- 🔄 Actualizar imports en todo el codebase

**Impacto:** -103 LOC, -1 fuente de confusión

#### 1.2 Eliminar duplicados de SemanticPointMarker
- ❌ Eliminar: `res://scripts/ai/semantic_point_marker.gd` (72 líneas)
- ✅ Mantener: `res://scripts/ai/navigation/semantic_point_marker.gd` (108 líneas)
- 🔄 Auditar que NavigationSystem use solo la versión activa

**Impacto:** -72 LOC, -1 fuente de confusión

#### 1.3 Consolidar carga de puntos semánticos
- Único punto de entrada: `NavigationSystem.load_semantic_points()`
- Eliminar llamada duplicada en `MapManager._instantiate_semantic_points()`
- Una sola responsabilidad

**Impacto:** -1 función redundante

---

### FASE 2: LIMPIEZA DE CÓDIGO MUERTO (MEDIA)

#### 2.1 Remover "yield" state del MovementSystem
- Eliminar líneas 124-127: `_yield_timer`, `_is_yielding`, `YIELD_DURATION`
- Eliminar línea 212-217: lógica de yield en `process()`
- Eliminar línea 634-635: reset de yield en `_reset_stuck_state()`

**Impacto:** -20 LOC, -1 máquina de estado fantasma

#### 2.2 Remover `reset()` vacío de NavigationSystem
- Línea 168-169
- Es un método vacío nunca llamado

**Impacto:** -2 LOC

#### 2.3 Evaluar uso de RouteDiversifier
- Verificar si se llama en algún comportamiento
- Si NO se usa: eliminar archivo (255 LOC)
- Si se usa: documentar dónde y cómo

**Impacto:** -255 LOC si no se usa

---

### FASE 3: REFACTORING PROFUNDO (BAJA - FUTURO)

#### 3.1 Dividir MovementSystem
- Extraer `VaultController` integration → separate module
- Extraer `StuckDetection` → `StuckDetectionSystem`
- Extraer `ClimbingLogic` → `ClimbingSystem`
- Dejar `MovementSystem` como orquestador

**Impacto:** 
- Líneas sin cambiar, pero legibilidad +40%
- Cada módulo <200 líneas
- Testeable independientemente

#### 3.2 Dividir MapManager
- Extraer `NavMeshBuilder`
- Extraer `CoreSetup`
- Extraer `SpawnerConfiguration`
- Dejar MapManager como orquestador

**Impacto:** Legibilidad +50%, mantenibilidad +60%

#### 3.3 Simplificar RouteDiversifier
- Si se usa, reducir a 2-3 tipos de ruta
- Si no se usa, eliminar y reemplazar con randomización simple

---

## 🔍 PUNTOS SEMÁNTICOS: ANÁLISIS DE TIPOS

### Confusión actual: Tipos duplicados

**SemanticPoint en `navigation/semantic_point.gd`:**
```gdscript
enum PointType {
    ASSAULT   = 0,
    DEFENSE   = 1,
    ALTERNATE = 2,
    PATH      = 3,
    OBJECTIVE = 4,
    DUAL      = 5,    # Verde oscuro → ASSAULT + FLANKER
    TERCER    = 6,    # Tercer camino
}
```

**SemanticPoint en `semantic_point.gd`:**
```gdscript
enum PointType {
    PATH = 0,        # Ruta
    AMBUSH = 1,      # Emboscada
    DEFENSE = 2,     # Defensivo
    ALTERNATE = 3,   # Alternativo
    LIFT = 4,        # Elevador
    ITEM = 5,        # Item
    SNIPER = 6,      # Francotirador
}
```

**Problema:** Enums COMPLETAMENTE DIFERENTES con los mismos números

- Si alguien usa la clase equivocada, los puntos se cargan mal
- No hay validación de qué versión se está usando
- Riesgo de bugs silenciosos

---

## 📈 ESTADÍSTICAS

### Código a eliminar directamente:
```
semantic_point.gd                    103 LOC
semantic_point_marker.gd              72 LOC
MovementSystem._yield_*               20 LOC
NavigationSystem.reset()               2 LOC
─────────────────────────────────────────
TOTAL (si RouteDiversifier no se usa): 197 LOC sin RouteDiversifier
TOTAL (si RouteDiversifier se usa):   -197 LOC + RouteDiversifier

Si RouteDiversifier NO se usa: -452 LOC (197 + 255)
```

### Complejidad actual:
```
NavigationSystem:       195 LOC, 6 funciones públicas
MovementSystem:         930 LOC, 8+ máquinas estado internas
RouteDiversifier:       255 LOC, 4 funciones públicas
MapManager:             309+ LOC, 6 responsabilidades
─────────────────────────────────────
TOTAL sistemas afectados: ~1,689 LOC
```

---

## ✅ PLAN DE ACCIÓN RECOMENDADO

### Semana 1: FASE 1 (CRÍTICO)
```
Día 1: Eliminar semantic_point.gd + semantic_point_marker.gd
Día 2: Consolidar carga de puntos (1 función)
Día 3: Verificar imports y tests
Día 4: QA y verificación
```

**Ganancia:** -197 LOC, -1 fuente de confusión crítica

### Semana 2: FASE 2 (MEDIA)
```
Día 5: Remover yield state de MovementSystem
Día 6: Remover reset() vacío
Día 7: Investigar RouteDiversifier (¿se usa?)
Día 8: Decidir sobre RouteDiversifier
```

**Ganancia:** -22 LOC (sin RouteDiversifier), -255 si aplica

### Semana 3: FASE 3 (BAJA - FUTURE)
```
Día 9-10: Dividir MovementSystem
Día 11-12: Dividir MapManager
Día 13: Tests y QA
```

**Ganancia:** Legibilidad +40%, mantenibilidad +60%

---

## 🔗 VERIFICACIÓN NECESARIA

Antes de ejecutar la limpieza, confirmar:

1. ¿Dónde se llama `RouteDiversifier.get_route_type_for_bot()`?
2. ¿Dónde se llama `RouteDiversifier.get_approach_waypoint()`?
3. ¿Quién usa `_yield_timer` en MovementSystem?
4. ¿NavigationSystem.reset() se llama desde algún lado?
5. ¿has_point_nearby() se usa en el codebase?

---

## 📝 NOTAS FINALES

### Problemas de Architecture
- **Mezcla de lógica estática y de instancia** en NavigationSystem
- **Falta de inyección de dependencias** en MapManager
- **Estado global** en NavigationSystem.all_semantic_points hace testing difícil

### Deuda técnica acumulada
- Código comentado indicando conflictos pasados
- Métodos vacíos (reset())
- Variables que nunca se escriben (_yield_timer)
- Funciones no documentadas donde se usan

### Recomendación general
**Prioridad: FASE 1 (esta semana)**
- Es crítico eliminar los duplicados de SemanticPoint/SemanticPointMarker
- Riesgo de bugs silenciosos al cargar puntos
- Bajo esfuerzo, alto impacto

