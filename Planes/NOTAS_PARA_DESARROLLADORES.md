# NOTAS PARA DESARROLLADORES - POST LIMPIEZA

**Fecha:** 7 de Julio 2026  
**Cambios:** Limpieza de duplicados y código muerto en navegación  
**Status:** ✅ COMPLETADO

---

## ⚠️ CAMBIOS IMPORTANTES QUE AFECTAN TU TRABAJO

### 1. Archivos que YA NO EXISTEN

❌ **NO USES ESTOS:**
```gdscript
// ELIMINADO - NO EXISTE
res://scripts/ai/semantic_point.gd

// ELIMINADO - NO EXISTE  
res://scripts/ai/semantic_point_marker.gd
```

✅ **USA ESTOS EN SU LUGAR:**
```gdscript
// CORRECTO - ÚNICA VERSIÓN
res://scripts/ai/navigation/semantic_point.gd
res://scripts/ai/navigation/semantic_point_marker.gd
```

**¿Por qué?**
- Los archivos antiguos eran duplicados no mantenidos
- Causaban confusión de class_name
- La versión en `navigation/` es la correcta

---

### 2. Archivos que FUERON MOVIDOS

❌ **NO IMPORTES:**
```gdscript
res://scripts/route_diversifier.gd
```

📦 **AHORA ESTÁ AQUÍ (archivado, no activo):**
```gdscript
res://scripts/_unused_route_diversifier.gd
```

**¿Por qué?**
- Código completamente sin usar
- Se movió a `_unused` para marcar que está inactivo
- Si lo necesitas: puedes recuperarlo, pero reconsideralo primero

---

### 3. Cambios en MovementSystem

**SE REMOVIERON ESTAS VARIABLES:**
```gdscript
// ❌ YA NO EXISTEN
var _yield_timer: float = 0.0
var _is_yielding: bool = false
const YIELD_DURATION: float = 0.5
```

**¿Por qué?**
- Nunca se asignaba `_is_yielding = true`
- Estado nunca se ejecutaba
- Código legacy abandonado

**Impacto:** NINGUNO - el código nunca se ejecutaba

---

### 4. Cambios en NavigationSystem

**SE REMOVIÓ ESTE MÉTODO:**
```gdscript
// ❌ YA NO EXISTE
func reset() -> void:
    pass
```

**¿Por qué?**
- Método completamente vacío
- Nunca se llamaba desde ningún lado
- No hacía nada

**Impacto:** NINGUNO - nunca se llamaba

---

## ✅ CÓMO VERIFICAR QUE TODO FUNCIONA

### Test 1: Compilación limpia
```bash
# En el editor de Godot
F9  # Recarga proyecto

# Verificar en consola que:
# - Sin errores de import
# - Sin errores de class_name duplicados
# - Sin warnings de métodos no encontrados
```

### Test 2: Carga de puntos semánticos
```bash
# Ejecuta un mapa que tenga bots

# En los logs busca:
# [NavigationSystem] Cargados 23 puntos semánticos desde SemanticPointMarker
```

### Test 3: Movimiento de bots
```bash
# En una partida de bots vs bots:
# - Bots deben moverse normalmente
# - Bots deben usar puntos semánticos
# - Bots deben evitar atascarse
# - Bots deben escalar rampas correctamente
```

---

## 🗂️ ESTRUCTURA ACTUAL (POST-LIMPIEZA)

### Acceso correcto a clases de navegación:

```gdscript
# CORRECTO - En scripts de comportamiento o sistemas
extends Node
class_name MiScript

func usar_navegacion():
    # Importar la versión correcta
    var point: SemanticPoint = NavigationSystem.get_nearest_point(...)
    
    # SemanticPoint y SemanticPointMarker vienen del:
    # res://scripts/ai/navigation/
```

### Estructura de carpetas navegación:

```
res://scripts/ai/navigation/
├── navigation_system.gd              ← Gestor estático
├── semantic_point.gd                 ← Definición (ÚNICA)
└── semantic_point_marker.gd          ← Editor tool (ÚNICA)
```

---

## 🔍 SI ENCUENTRAS ERRORES

### Error: "Unknown class 'SemanticPointMarker'"
**Causa:** Importaste de ruta antigua
**Solución:** Cambiar de `res://scripts/ai/` a `res://scripts/ai/navigation/`

### Error: "Method 'reset' not found"
**Causa:** Llamaste a NavigationSystem.reset() que no existe
**Solución:** Remover esa llamada (nunca hacía nada)

### Error: "Cannot find file 'semantic_point.gd'"
**Causa:** Importaste de `res://scripts/ai/semantic_point.gd`
**Solución:** Cambiar a `res://scripts/ai/navigation/semantic_point.gd`

### Error: "Unknown reference to '_is_yielding'"
**Causa:** Código antigua que referenciaba yield state
**Solución:** Remover la referencia (feature nunca estaba activa)

---

## 🚀 PRÓXIMAS MEJORAS PLANEADAS

### Corto plazo (1-2 semanas):
- [ ] Monitorear si RouteDiversifier se necesita
- [ ] Si no: eliminar `_unused_route_diversifier.gd`

### Mediano plazo (1-2 meses):
- [ ] Dividir MovementSystem en submódulos
  - `ClimbingSystem` (manejo de rampas)
  - `StuckDetectionSystem` (detección de atasco)
  - `VaultIntegration` (saltos y bóvedas)
  
- [ ] Dividir MapManager en submódulos
  - `CoreSetup` (objetivos)
  - `SpawnerConfiguration` (spawn)
  - `NavMeshBuilder` (navegación)
  - `SemanticPointLoader` (puntos semánticos)

### Largo plazo (2-3 meses):
- [ ] Mejorar testabilidad del sistema
- [ ] Agregar tests unitarios para navegación
- [ ] Documentación en wiki del equipo

---

## 📚 DOCUMENTACIÓN DISPONIBLE

### Para referencia rápida:
- **`GUIA_RAPIDA_NAVEGACION.md`** ← Empieza por aquí
  - Tipos de puntos semánticos
  - APIs disponibles
  - Ejemplos de uso

### Para entender cambios:
- **`ANALISIS_NAVEGACION_Y_MOVIMIENTO.md`**
  - Problema inicial
  - Análisis detallado
  - Recomendaciones

- **`CAMBIOS_REALIZADOS.md`**
  - Qué cambió exactamente
  - Por qué se cambió
  - Verificaciones realizadas

### Para contexto completo:
- **`REPORTE_FINAL_LIMPIEZA.md`**
  - Antes/después
  - Estadísticas
  - Beneficios

---

## ⚡ QUICK START - Si trabajas con navegación

### 1. Crear un nuevo punto semántico

```gdscript
# En el editor:
1. Añade un Marker3D al mapa
2. Asigna el script: res://scripts/ai/navigation/semantic_point_marker.gd
3. Configura en inspector:
   - point_type: selecciona el enum
   - team: -1 (cualquier equipo) o 0/1/... (equipo específico)
   - point_name: "Punto de asalto izquierda"
4. ¡Listo! Se registrará automáticamente

# En código (si lo necesitas dinámicamente):
var point = SemanticPoint.new(
    SemanticPoint.PointType.ASSAULT,
    Vector3(10, 0, 20),
    -1,  # team
    "Dinámico"
)
```

### 2. Buscar punto más cercano

```gdscript
var nearest = NavigationSystem.get_nearest_point(
    SemanticPoint.PointType.ASSAULT,
    bot.global_position,
    team_filter: -1,  # cualquier equipo
    max_dist: 50.0    # radio máximo
)

if nearest:
    print("Punto más cercano: %s" % nearest)
else:
    print("No hay puntos disponibles")
```

### 3. Obtener todos los puntos ordenados

```gdscript
var all_points = NavigationSystem.get_points_sorted(
    SemanticPoint.PointType.DEFENSE,
    bot.global_position,
    team_filter: bot.team,
    max_dist: 100.0
)

for point in all_points:
    var distance = bot.global_position.distance_to(point.position)
    print("Punto %s a %.1f unidades" % [point.name, distance])
```

---

## 🎮 MOVIMIENTO - Cambios que NO afectan tu código

### Lo que SIGUE IGUAL:
```gdscript
# Estos funcionan igual que antes
bot.velocity = new_velocity
agent.target_position = target
movement_system.command = my_command
```

### Lo que CAMBIÓ INTERNAMENTE:
```gdscript
# Estos ya no existen pero NO los usabas:
movement_system._is_yielding = true        # ← No existía
NavigationSystem.reset()                    # ← Nunca se llamaba
RouteDiversifier.get_approach_waypoint()   # ← No se usaba
```

**IMPACTO:** Ninguno en tu código existente

---

## 🐛 DEBUGGING

### Ver qué puntos están cargados:

```gdscript
func debug_semantic_points():
    var all = NavigationSystem.all_semantic_points
    print("Total puntos cargados: %d" % all.size())
    
    for sp in all:
        print("  - %s (tipo=%s, team=%d, pos=%s)" % [
            sp.name,
            sp.get_type_name(),
            sp.team,
            sp.position
        ])
```

### Ver estado de navegación:

```gdscript
func debug_navigation():
    if not agent.is_navigation_finished():
        var next_pos = agent.get_next_path_position()
        var remaining = agent.distance_to_target
        print("Camino: %d unidades restantes" % remaining)
    else:
        print("Destino alcanzado")
```

### Ver estado de atasco:

```gdscript
func debug_stuck():
    if movement_system.is_stuck_flag:
        print("ATASCADO - Fase: %d" % movement_system.stuck_recovery_phase)
        print("Intentos: %d" % movement_system.stuck_reroute_count)
    else:
        print("Movimiento normal")
```

---

## 📞 CONTACTO

Si encuentras errores o confusiones:

1. **Verificar:** ¿El error está relacionado con semantic_point, semantic_point_marker, o route_diversifier?
2. **Consultar:** `GUIA_RAPIDA_NAVEGACION.md` o `CAMBIOS_REALIZADOS.md`
3. **Revisar:** El archivo afectado en `res://scripts/ai/navigation/`
4. **Preguntar:** Si no está claro, consulta los documentos generados

---

## ✅ RESUMEN

| Acción | Estado | Impacto |
|--------|--------|--------|
| Duplicados eliminados | ✅ Hecho | Tu código: NINGUNO |
| Código legacy removido | ✅ Hecho | Tu código: NINGUNO |
| Código experimental archivado | ✅ Hecho | Tu código: NINGUNO |
| APIs sin cambios | ✅ Garantizado | Tu código: FUNCIONA IGUAL |

**→ No debería afectar tu trabajo**

---

**Última actualización:** 7 de Julio 2026  
**Preparado para:** Todos los desarrolladores  
**Si tienes dudas:** Consulta los documentos de análisis

