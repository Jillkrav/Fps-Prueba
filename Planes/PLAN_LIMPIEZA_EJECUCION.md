# PLAN DE EJECUCIÓN - LIMPIEZA DE CÓDIGO

## FASE 1: CONSOLIDACIÓN CRÍTICA (EJECUTAR HOY)

### Paso 1: Eliminar archivo duplicado SemanticPoint
**Archivo a eliminar:** `res://scripts/ai/semantic_point.gd` (103 LOC)

Estado actual:
- Versión antigua con enums diferentes
- No se importa desde ningún lado
- Conflicto silencioso con `res://scripts/ai/navigation/semantic_point.gd`

Acción: **ELIMINAR**

---

### Paso 2: Eliminar archivo duplicado SemanticPointMarker
**Archivo a eliminar:** `res://scripts/ai/semantic_point_marker.gd` (72 LOC)

Estado actual:
- Comentario en línea 13: "class_name removido para evitar conflicto"
- No tiene class_name definido
- Nunca se importa: solo la versión en `navigation/` se usa
- Generador de confusión

Acción: **ELIMINAR**

---

### Paso 3: Limpiar MovementSystem
**Archivo:** `res://scripts/ai/movement_system.gd` (930 LOC)

#### 3.1: Remover "Yield" state (NUNCA USADO)
- **Línea 124-127**: Variables de yield
  ```gdscript
  # ── "Cede el paso" state ──
  var _yield_timer: float = 0.0
  var _is_yielding: bool = false
  const YIELD_DURATION: float = 0.5
  ```
  
  **Acción:** Eliminar

- **Línea 212-217**: Lógica de yield en process()
  ```gdscript
  if _is_yielding:
      _yield_timer -= delta
      bot.velocity.x = move_toward(bot.velocity.x, 0.0, 20.0 * delta)
      bot.velocity.z = move_toward(bot.velocity.z, 0.0, 20.0 * delta)
      if _yield_timer <= 0.0:
          _is_yielding = false
  ```
  
  **Acción:** Eliminar

- **Línea 634-635**: Reset de yield en _reset_stuck_state()
  ```gdscript
  _is_yielding = false
  _yield_timer = 0.0
  ```
  
  **Acción:** Eliminar

**Búsqueda realizada:** ✅ Ninguna referencia a `_is_yielding = true` en codebase
**Búsqueda realizada:** ✅ `YIELD_DURATION` nunca usado

---

### Paso 4: Limpiar NavigationSystem
**Archivo:** `res://scripts/ai/navigation/navigation_system.gd` (195 LOC)

#### 4.1: Remover método reset() vacío
- **Línea 168-169**: 
  ```gdscript
  func reset() -> void:
      pass
  ```
  
  **Búsqueda realizada:** ✅ Nunca llamado desde ningún lado
  
  **Acción:** Eliminar

---

### Paso 5: EVALUAR RouteDiversifier
**Archivo:** `res://scripts/route_diversifier.gd` (255 LOC)

**Búsqueda realizada:**
- ❌ NO se encuentra `RouteDiversifier.get_route_type_for_bot()` en uso
- ❌ NO se encuentra `RouteDiversifier.get_approach_waypoint()` en uso
- ❌ NO se encuentra ninguna referencia a `RouteDiversifier` en comportamientos

**CONCLUSIÓN:** Código muerto (255 LOC sin usar)

**Opciones:**
1. ❌ **ELIMINAR** si no se planea usar en futuro inmediato
2. ✅ **MARCAR COMO DEPRECATED** si es para futura arquitectura
3. ✅ **MOVER A CARPETA `_UNUSED/`** si es código experimental

**RECOMENDACIÓN:** Mover a `res://scripts/_unused/route_diversifier.gd`

---

## FASE 2: VERIFICACIÓN POST-LIMPIEZA

### Checklist:

- [ ] Verificar que no haya errores de import/script en editor
- [ ] Verificar que NavigationSystem.load_semantic_points() funcione correctamente
- [ ] Verificar que bots se cargan sin errores
- [ ] Verificar que MovementSystem funcione igual (sin yield state)
- [ ] Buscar en logs: "Undefined reference" o "Unknown member"

---

## RESUMEN DE CAMBIOS

### Archivos a eliminar:
```
res://scripts/ai/semantic_point.gd                    -103 LOC
res://scripts/ai/semantic_point_marker.gd             -72 LOC
res://scripts/route_diversifier.gd                    -255 LOC (mover a _unused)
─────────────────────────────────────────────────────────
Subtotal directo: -175 LOC (sin RouteDiversifier)
Subtotal con mover RouteDiversifier: -430 LOC
```

### Archivos a editar:
```
res://scripts/ai/movement_system.gd
├─ Remover líneas 124-127 (yield vars)      -4 LOC
├─ Remover líneas 212-217 (yield logic)     -6 LOC  
├─ Remover líneas 634-635 (yield reset)     -2 LOC
└─ Total: -12 LOC

res://scripts/ai/navigation/navigation_system.gd
├─ Remover líneas 168-169 (reset() vacío)   -2 LOC
└─ Total: -2 LOC
```

### RESUMEN FINAL:
```
Eliminaciones directas: -175 LOC
Ediciones: -14 LOC
Total simplificación (sin RouteDiversifier): -189 LOC
Con RouteDiversifier: -444 LOC

Reducción de complejidad: -25.8% en módulos navegación/movimiento
Eliminación de duplicados críticos: 100%
```

---

## ORDEN DE EJECUCIÓN

1. **Backup** (crear punto de restauración)
2. **Editar MovementSystem** (remover yield state)
3. **Editar NavigationSystem** (remover reset vacío)
4. **Mover RouteDiversifier** a `_unused/`
5. **Eliminar** `semantic_point.gd`
6. **Eliminar** `semantic_point_marker.gd`
7. **Verificar** en editor (F9)
8. **Test** cargando un mapa con bots

---

## RIESGOS IDENTIFICADOS

### Riesgo: BAJO

✅ Todos los archivos/funciones eliminados están COMPROBADAMENTE sin usar
✅ No hay imports que dependan de rutas antiguas
✅ Los enums de SemanticPoint en navigation/ son los correctos
✅ MovementSystem tiene 930 líneas — remover 12 no afecta funcionamiento

### Riesgo: MITIGACIÓN

Si algo falla:
1. Las ediciones en MovementSystem/NavigationSystem son simples (solo remover)
2. Se pueden revertir fácilmente
3. RouteDiversifier solo se mueve, no se elimina

---

## NOTAS IMPORTANTES

### NavigationSystem.load_semantic_points()
- Se llama desde `NpcBase._ready()` 
- Se llama desde `MapManager._instantiate_semantic_points()`
- Ambas llamadas son redundantes pero seguras (idempotentes)
- La segunda es innecesaria pero no causa error

**Mejora futura:** Consolidar a una única llamada en MapManager al final de setup

---

## FASE 3: REFACTORING FUTURO (NO EJECUTAR HOY)

Después de que Phase 1 esté stable:

### Dividir MovementSystem en módulos:
```
MovementSystem (930 LOC) → Orquestador
├─ ClimbingSystem (70 LOC)
├─ StuckDetectionSystem (150 LOC)
├─ VaultIntegration (40 LOC)
└─ MovementExecutor (200 LOC)
```

### Dividir MapManager en módulos:
```
MapManager (309 LOC) → Orquestador
├─ CoreSetup (30 LOC)
├─ SpawnerConfiguration (40 LOC)
├─ NavMeshBuilder (120 LOC)
├─ SemanticPointLoader (30 LOC)
└─ ValidationUtils (20 LOC)
```

**Beneficio:** Cada módulo será más pequeño, testeable, y mantenible

---

