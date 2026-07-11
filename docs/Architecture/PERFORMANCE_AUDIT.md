# Auditoría de rendimiento — Fases 1 y 2

> **Estado:** Auditoría estática de rendimiento; la Fase 2 terminó una migración de rutas/estructura sin optimizaciones intencionales.
>
> **Validación funcional posterior a Fase 2:** se ejecutaron partidas con pool de 23 bots en `map_1`, `map_2`, `map_3`, `Mapa_de_guerra` y `map_dust2`. Se confirmaron creación de bots, navegación semántica, equipos, CoreAttack, combate y respawn. Esto **no sustituye** una captura de Profiler/Monitors ni establece métricas de rendimiento.
>
> **Regla:** ningún hallazgo se etiqueta `CUELLO_DE_BOTELLA_CONFIRMADO` sin perfil/medición reproducible.

## 1. Línea base obligatoria antes de cambiar código

### Entorno fijo

Registrar en cada corrida:

- Fecha, commit/estado del proyecto y versión Godot: **4.7 Forward Plus, Jolt Physics**.
- GPU, CPU, RAM, SO, resolución, VSync y renderer.
- Mapa, máximo configurado de jugadores/bots, arma elegida y duración de la captura.
- Debug overlay y DevMenu: activo/inactivo.
- Calidad gráfica, ventana y stretch mode: usar el mismo viewport entre comparaciones.

### Herramientas Godot 4.7

1. **Debugger > Profiler**: iniciar manualmente mientras corre el juego; capturar Frame Time, Physics Time, Idle Time y funciones Script (vista inclusive y self).
2. **Debugger > Monitors**: FPS, frame time, memoria, objetos/nodos, draw calls y monitores de física disponibles.
3. **Debugger > Visual Profiler**: CPU/GPU de render; no usarlo para atribuir tiempo de script/física.
4. **Debugger > Errors**: capturar warnings, parser/runtime errors y prints excesivos.
5. **Debugger > Network Profiler**: registrar cero tráfico/llamadas hoy; usarlo cuando exista networking real.
6. Para aislar una zona después del profiler: instrumentación temporal con `Time.get_ticks_usec()` bajo flag de debug, nunca dejar `print()` por frame en producción.

### Criterio de comparación

- Hacer al menos tres repeticiones por escenario.
- Comparar mediana, p95 y p99 de frame time, no solo FPS promedio.
- Mantener mismo input/ruta/tiempo de prueba.
- Aceptar una optimización solo si reduce coste medido y no cambia mecánicas, errores ni resultados funcionales.

## 2. Escenarios de prueba

| ID | Escenario | Duración mínima | Qué observar |
|---|---|---:|---|
| P0 | Menú principal | 60 s | Idle CPU, UI, errores de autoload. |
| P1 | Mapa vacío tras carga | 60 s | Pico de carga, NavMesh bake, nodos/memoria. |
| P2 | Partida mínima | 120 s | 2 bots, percepción, navegación, arma, HUD. |
| P3 | Partida con máximo configurado | 180 s | Escalado bot × tick físico × contactos. |
| P4 | Combate intenso | 120 s | Pellets, hitscan, trails, proyectiles, explosiones y logs. |
| P5 | FreezeCube/jump pads | 120 s en `map_3` y Guerra | Timers, controladores, grupos Green/Yellow, movimiento. |
| P6 | Muerte y respawn repetidos | 120 s | Pool, weapon instantiation, pickups, PlayerData y timers. |
| P7 | Cambio de mapa/reintento | 3 ciclos | Liberación de bots, referencias inválidas y leaks lógicos. |
| P8 | CoreAttack completo | hasta victoria | Cores, TeamAI, MatchManager y reset. |
| P9 | Multiplayer futuro | N/A hoy | Registrar como 0 RPC/0 tráfico; definir baseline antes de integrar red. |

**Nota:** `map_dust2` debe validarse primero porque no contiene cores/puntos semánticos embebidos como los otros mapas; no usarlo para concluir rendimiento de CoreAttack sin comprobar funcionalidad.

## 3. Métricas a registrar

| Área | Métricas |
|---|---|
| Fluidez | FPS promedio/mínimo, frame time promedio/p95/p99, stutters. |
| CPU | Frame Time, Idle Time, Physics Time, Script Time; top funciones inclusive/self. |
| Render | CPU/GPU render, draw calls, Video RAM, sombras/VFX. |
| Memoria | RAM, objetos, nodos, crecimiento tras respawn/cambio de mapa. |
| IA | Cantidad de bots, cuerpos en AreaVision, enemies visibles/bot, path queries, raycasts/tick, stuck recoveries, navmesh bake time. |
| Gameplay | Proyectiles/trails/explosiones activos, pickups registrados, timers activos. |
| Networking futuro | RPC entrantes/salientes, paquetes/s, bytes/s, broadcast count, RTT/jitter, desyncs. Actualmente debe ser 0. |
| Calidad | Errores de consola, warnings, rutas faltantes, referencias inválidas. |

## 4. Hallazgos

### 4.1 `CUELLO_DE_BOTELLA_CONFIRMADO`

**Ninguno.** No se aportó perfil, métrica ni captura reproducible que pruebe un cuello de botella.

### 4.2 `RIESGO_PROBABLE`

| Prioridad | Archivo / función | Evidencia estática | Cambio propuesto solo tras medir | Impacto esperado | Riesgo de regresión | Prueba antes/después |
|---:|---|---|---|---|---|---|
| 1 | `Scripts/MP/ai/bot_behaviors/npc_base.gd::_physics_process` | Por bot/tick encadena percepción, memoria, TeamAI, core, FSM, movimiento, combate, weapon, `move_and_slide` y postproceso. Escala con bots activos. | Medir primero; si domina, escalonar percepción/decisión por LOD temporal sin romper reactividad. | Alto con muchos bots. | Alto: modifica respuestas IA. | P2/P3/P4, mismo bot count. |
| 2 | `Scripts/MP/ai/bot_behaviors/perception_system.gd::update` | Itera AreaVision; por candidato fuerza RayCast3D y hace `intersect_ray`; ordena arrays de Dictionary cada tick. | Reducir frecuencia o cachear LOS solo si profiler atribuye coste. | Alto con grupos numerosos. | Alto: detección/targeting puede cambiar. | P3/P4, medir Script+Physics y precisión de target. |
| 3 | `Scripts/MP/nav/bots/movement_system.gd::_execute_navigate` + helpers | Path follow, RVO, step/ramp/down raycasts, vault; `_detect_step_front` puede ser llamado más de una vez en tick. | Medir raycasts y Self time; cache por tick únicamente si no cambia resultado. | Alto en mapas complejos. | Alto: navegación/rampas/atasco. | P3/P5, rutas de rampas y escaleras. |
| 4 | `Scripts/MP/match/match_state/map_manager.gd::_update_navigation` | Crea bodies/shapes temporales, parsea CSG y hornea NavigationMesh runtime en carga. | Medir wall-clock de carga; evaluar NavMesh prehorneado/caching por mapa si pico es relevante. | Alto para stutter de carga. | Medio: cobertura de navegación. | P1/P7 por los cinco mapas. |
| 5 | `Scripts/MP/ai/bot_behaviors/state_roaming.gd` selección semántica | Filtra, crea Arrays/Dictionary/String keys y llama `NavigationServer3D.map_get_path()` en `_requires_backtrack` para candidatos. | Perfilar estados de rutas semánticas; limitar consultas solo si se demuestra coste. | Medio/alto según puntos/mapa. | Alto: diversidad de rutas. | P3/P5 en mapas con muchos puntos. |
| 6 | `weapon.gd::_fire_hitscan/_fire_hitscan_multi_pellet` | Un raycast forzado por pellet y un BulletTrail instanciado incluso al fallar; pellets multiplican coste. | Medir combate; pool VFX o reducir actualización solo si conserva presentación. | Medio/alto en shotgun/fuego rápido. | Medio: VFX y timing visual. | P4 con arma de pellets. |
| 7 | `weapon.gd::_fire_projectile`, `projectile_base`, `effects/explosion` | Instanciación/destrucción frecuente de RigidBody, explosiones y VFX. | Medir nodos/memoria/frame spikes; considerar pool solo con evidencia. | Medio en spam explosivo. | Medio/alto: física/colisiones. | P4, P6 y cambio de mapa. |
| 8 | `Scripts/MP/match/multiplayer/match_manager.gd::_process` | Cada frame recorre timers y sincroniza todos `PlayerData`; con 100 máximo configurado escala lineal, y scoreboard puede refrescar. | Medir Self/inclusive; emitir cambios solo al variar estado si está probado. | Medio con muchos bots. | Medio: scoreboard/respawn. | P3/P6 con 24/50/100 si el equipo lo permite. |
| 9 | `Scripts/MP/match/multiplayer/scoreboard.gd::_process` | Mientras visible refresca filas y busca labels por jugador cada frame. | Usar `players_data_changed`/throttle, solo tras medir scoreboard visible. | Medio condicional. | Bajo/medio: UI stale. | P3 con tablero abierto/cerrado. |
| 10 | `bot_debug_overlay.gd::_process` | Actualiza textos/estilos por unidad por frame; se instancia sobre Player y bots cuando enabled. | Mantener off en release; medir separado. | Medio condicional. | Bajo: solo debug visual. | P3 overlay off vs on. |
| 11 | `ai/memory_system.gd::update/_decay_all` | Construye arrays de memorias válidas por bot/tick. | Cambiar solo si profiler muestra GC/asignaciones relevantes. | Bajo/medio. | Medio: expiración/memoria. | P3 Script self/memoria. |
| 12 | Logging en `MatchManager`, `MapManager`, `NpcBase`, `Core`, `WeaponSystem` | Muchos `print`, algunos en spawn/respawn y eventos de gameplay; coste depende de frecuencia/editor. | Flag/logger por categoría, después de medir logs. | Bajo/medio, puede ser alto si hay spam. | Bajo: visibilidad diagnóstica. | P4/P6 con consola abierta/cerrada. |

### 4.3 `OPTIMIZACION_OPCIONAL`

| Archivo / función | Evidencia | Propuesta si se necesita | Riesgo |
|---|---|---|---|
| `player.gd::_physics_process` | Vault availability y dos raycasts step-up por input/física; un jugador local. | Medir solo si P0/P2 muestra script/physics relevante. | Medio: sensación de movimiento. |
| `pickup_manager.gd::get_nearest_pickup` | Búsqueda lineal; NpcBase tiene timer de 2 s, por lo que el coste parece acotado con pocos pickups. | Spatial hash solo si hay muchísimos pickups y perfil lo demuestra. | Medio. |
| `NpcBase._find_nearest_green/yellow_cube` | `get_nodes_in_group` y búsqueda lineal al activar freeze, evento no por frame. | Cache de grupos solo si FreezeCube se dispara masivamente. | Bajo/medio. |
| `TeamAI.assign_orders_for_team` | `get_nodes_in_group("npc")` en asignación de órdenes, no cada frame detectado. | Usar MatchManager pool si se muestra frecuente. | Medio: asignación de órdenes. |
| `ResourceLoader.load` arma en Player/NpcBase | Usa `CACHE_MODE_REUSE`; sólo equipar/respawn, no cada tick. | `preload` cuando se resuelva motivo de compilación, solo si perfiles de respawn lo muestran. | Bajo/medio. |

## 5. Riesgos funcionales que parecen rendimiento pero requieren corrección separada

1. `StateRoaming._check_pickups()` llama `NpcBase._check_for_pickups(0.0)`. El temporizador de 2 s no se decrementa en ese camino; puede impedir rescaneos de pickups. Es un riesgo lógico, no una optimización.
2. `TeamAI` puede escanear cores antes de cargar mapa; no tratarlo como problema de performance.
3. `MapManager` busca escenas de puntos semánticos inexistentes; no optimizar hasta arreglar/confirmar flujo.
4. Debug Overlay presenta un parser error actual de clase global duplicada/oculta; resolver antes de medir comparativas estables.

## 6. Top 10 de prioridades

| # | Prioridad | Impacto potencial | Esfuerzo | Riesgo |
|---:|---|---|---|---|
| 1 | Capturar baseline P1/P2/P3/P4 antes de tocar IA. | Alto | Bajo | Bajo |
| 2 | Perfilar cadena completa de `NpcBase._physics_process`. | Alto | Bajo | Bajo |
| 3 | Atribuir coste real de percepción y LOS. | Alto | Bajo | Bajo |
| 4 | Medir navegación/step/vault/RVO y raycasts. | Alto | Medio | Bajo |
| 5 | Medir bake runtime de NavMesh en cada mapa. | Alto | Bajo | Bajo |
| 6 | Medir projectile/hitscan/VFX en combate intenso. | Medio/alto | Bajo | Bajo |
| 7 | Comparar debug overlay off/on. | Medio condicional | Bajo | Bajo |
| 8 | Medir MatchManager + scoreboard con conteos altos. | Medio | Bajo | Bajo |
| 9 | Revisar crecimiento de nodos/memoria en respawn/map switching. | Medio | Medio | Bajo |
| 10 | Definir presupuesto de red antes de implementar RPCs. | Alto futuro | Medio | Bajo ahora |

## 7. Criterios para optimizaciones futuras

Una optimización se prioriza si cumple:

1. Perfil muestra coste significativo o picos repetibles.
2. Tiene impacto alto, riesgo bajo/medio y comportamiento observable idéntico.
3. Posee prueba automatizada o escenario manual documentado.
4. Puede revertirse en un commit aislado.

No aprobar micro-optimizaciones de legibilidad baja (por ejemplo sustituir código claro por caching global mutable) sin un resultado medido.

## 8. Preparación para multiplayer futuro

Actualmente tráfico/RPC=0. Antes de añadir red, medir y presupuestar:

- Frecuencia por entidad para transform, aim, disparo, daño, respawn, pickups, Core y estado de match.
- Tamaño de payload y broadcasts por segundo.
- Autoridad del servidor/host y validación de daño.
- Interest management para bots, proyectiles y eventos de VFX.
- Separación entre estado fiable (score/core/equipo) y efímero (VFX/aim).

No usar Network Profiler para declarar rendimiento de red hasta que exista una implementación real.
