# Handoff para DeepSeek v4 Pro — Refactor seguro Godot

> **Fecha:** 2026-07-11
>
> **Estado de fase:** Fase 1 (auditoría) y Fase 2 (migración estructural) completadas y verificadas funcionalmente. La implementación activa usa la raíz canónica `res://Scripts/` y el código exclusivo del modo local de equipos/bots está centralizado bajo `res://Scripts/MP/`.
>
> **Siguiente puerta:** no iniciar borrados de legacy, cambios de comportamiento, optimizaciones ni networking sin una tarea y aprobación explícitas. La aprobación `APROBADO FASE 2` ya fue recibida y consumida por la migración concluida.

## 1. Resumen ejecutivo

Proyecto FPS 3D en Godot con jugador humano, bots, armas, pickups, navegación, puntos semánticos, equipos, respawn, CoreAttack, HUD y selección de armas/equipo.

El objetivo del trabajo es ordenar y preparar el código para ser mantenible/escalable, sobre todo para el modo de partida de equipos. El usuario exige, en orden:

1. No romper mecánicas.
2. No cambiar comportamiento sin autorización.
3. Optimizar solo con mediciones.
4. Eliminar solo código confirmado muerto/duplicado/innecesario.
5. Centralizar código exclusivo del modo de partida en `res://Scripts/MP/`.

El resultado de Fase 1 está documentado en:

- `res://Docs/Architecture/SCRIPTS_AUDIT.md`
- `res://Docs/Architecture/MP_MIGRATION_PLAN.md`
- `res://Docs/Architecture/PERFORMANCE_AUDIT.md`
- `res://Docs/Architecture/DEEPSEEK_HANDOFF.md`
- `res://Docs/Architecture/CHANGELOG_REFACTOR.md`

Leer esos cinco archivos como historial y estado de cierre antes de iniciar una tarea posterior a Fase 2.

## 2. Compatibilidad estricta

- Motor declarado: **Godot 4.7**, Forward Plus.
- Runtime/editor observado: **Godot 4.7-stable**.
- Física: **Jolt Physics**.
- Usar exclusivamente APIs/sintaxis Godot 4.x.
- No inventar nodos, señales, RPCs, propiedades ni métodos.
- La raíz canónica activa es `res://Scripts/...`, con el modo local de equipos/bots bajo `res://Scripts/MP/...`.
- La capitalización se migró en Fase 2; Windows no puede confirmar por sí solo el resultado de Linux/macOS. El export o checkout case-sensitive continúa siendo una validación pendiente.

## 3. Estado real de multiplayer

No hay networking real. No se detectaron `@rpc`, `rpc()`, `MultiplayerPeer`, ENet, autoridad, sincronizadores ni tráfico de red.

Hoy `MP` significa **modo local de equipos con bots**, no multijugador online. No añadir netcode mientras se migra estructura. Una futura implementación online requerirá diseño independiente de autoridad, replicación, seguridad, predicción, reconciliación y bandwidth budget.

## 4. Estructura objetivo

```text
res://Scripts/MP/
├── debug/
│   └── bots/
├── nav/
│   ├── bots/
│   └── freeze_cube/
├── game_modes/
│   └── core_attack/
├── ai/
│   ├── enemy_types/
│   ├── bot_behaviors/
│   └── bot_tactics/
└── match/
    ├── teams/
    ├── multiplayer/
    └── match_state/
```

No crear scripts vacíos para completar carpetas. `enemy_types` y `debug/bots` deben permanecer vacías hasta que exista una clasificación exclusiva confirmada.

## 5. Sistemas importantes y estado actual

### 5.1 Match y equipos

- `MatchManager` es autoload de sesión: pool, bots, respawn, equipos, auto-balance, PlayerData.
- `TeamAI` es autoload: objetivos Core, órdenes por rol y scores de equipos.
- `MapManager` es autoload: busca el mapa, configura cores/spawners, hornea NavMesh y carga puntos semánticos dinámicos si existen.
- `PlayerData` sirve a MatchManager y Scoreboard.
- `Spawner` registra `Marker3D` de Blue/Red spawners.

Destino propuesto:

```text
Scripts/MP/match/multiplayer/: MatchManager, PlayerData, Spawner, Scoreboard, TeamWeaponSelector
Scripts/MP/match/teams/: TeamAI, Objective
Scripts/MP/match/match_state/: MapManager
```

### 5.2 CoreAttack

- `core.gd` define objetivo destruible y estado de victoria.
- `GameState` registra cores y ganador.
- `MapManager` configura/reemplaza cores.

Destino propuesto: `Scripts/MP/game_modes/core_attack/core.gd`.

### 5.3 Bots e IA actual

Ruta activa:

```text
MatchManager -> scenes/npcs/npc.tscn -> NpcBase
NpcBase -> PerceptionSystem + MemorySystem + NavigationSystem + MovementSystem
       -> DecisionSystem + StateRoaming/Hunting/Combat/Retreating
       -> CombatSystem + WeaponSystem
```

- `NpcBase` está en `res://Scripts/MP/ai/bot_behaviors/npc_base.gd` y es un orquestador grande.
- La FSM `DecisionSystem + State*` es la ruta activa.
- Existe pipeline legacy `BotBrain + BotBehavior + Behavior* + DecisionContext`; no se detectó instancia desde NpcBase actual y sus APIs parecen desalineadas. No eliminar sin test y aprobación.
- `TacticalRole` contiene perfiles tácticos.

Destino propuesto:

```text
Scripts/MP/ai/bot_behaviors/: NpcBase, DecisionSystem, Perception, Memory, Combat, WeaponSystem, commands, states
Scripts/MP/ai/bot_tactics/: TacticalRole
```

### 5.4 Navegación

- `MovementSystem` controla velocidad, NavigationAgent, RVO, vault, raycasts de step/ramp/down y anti-stuck.
- `NavigationSystem` carga `SemanticPointMarker` mediante grupo `semantic_points`.
- `SemanticPoint` es DTO.
- `StateRoaming` hace selección de rutas semánticas y consulta paths.

Destino: `Scripts/MP/nav/bots/`.

### 5.5 FreezeCube y salto

- `FreezeCube`, `FreezeCube0`, `FreezeCube2` son triggers Area3D para bots.
- `GreenCube` y `YellowCube` son destinos registrados en grupos.
- Role/YellowJumpController hacen trayectorias de salto.

Estos scripts parecen exclusivos de bots del modo actual; destino `Scripts/MP/nav/freeze_cube/`.

### 5.6 Scripts compartidos que no se mueven

No mover:

```text
config_manager.gd
input_manager.gd
enums.gd
game_state.gd
main_menu.gd
player.gd
weapon.gd
vault_controller.gd
pickup.gd
pickup_manager.gd
weapon_pickup.gd
resupply_box.gd
projectiles/*
effects/*
props/*
weapon_ai_profile.gd
hud.gd
options_menu.gd
bot_debug_overlay.gd (también lo usa Player)
```

Motivo: son gameplay, UI, datos globales o funcionalidad reutilizable para humano/single player/futuro online. `GameState` mezcla preferencias de usuario con estado de match, por lo que moverlo sería incorrecto sin dividirlo primero.

## 6. Registro histórico de Fase 1

### Realizados en esta fase

- Auditoría de 82 scripts.
- Auditoría de escenas, autoloads, rutas, recursos, grupos, conexiones y riesgos.
- Creación de los cinco Markdown de arquitectura.

### No realizados en esta fase

- Ningún script fue modificado.
- Ningún archivo fue movido, renombrado ni borrado.
- No se añadió multiplayer de red.
- No se optimizó código.
- No se borraron candidatos legacy/wrappers.

Advertencia: existen documentos históricos bajo `res://Planes/` que declaran cambios previos de otros trabajos. Son contexto histórico, no prueba suficiente para borrar archivos hoy. En particular, `CAMBIOS_REALIZADOS.md` afirma que RouteDiversifier no estaba activo, pero `TacticalRole` aún referencia sus enums; conservarlo hasta comprobar el contrato completo.

## 6.1 Actualización de cierre — Fase 2 completada

### Estructura activa final

```text
res://Scripts/
├── MP/
│   ├── nav/bots/                 # Movement, Navigation y puntos semánticos
│   ├── nav/freeze_cube/          # FreezeCube, cubos y controladores de salto
│   ├── game_modes/core_attack/   # Core
│   ├── ai/bot_behaviors/         # NpcBase, FSM, percepción, memoria, combate, armas
│   ├── ai/bot_tactics/           # TacticalRole
│   └── match/
│       ├── teams/                # TeamAI, Objective
│       ├── multiplayer/          # MatchManager, PlayerData, Spawner, Scoreboard, selector
│       └── match_state/          # MapManager
├── ai/                           # Pipeline BotBrain legacy y WeaponAIProfile compartido
└── gameplay/UI/shared            # Player, Weapon, HUD, pickups, props, etc.
```

### Fase 2 ejecutada

- Bloque 1: `scripts` se renombró a `Scripts` mediante carpeta temporal y las referencias activas se actualizaron.
- Bloques 2–3: navegación semántica y FSM activa de bots migradas.
- Bloque 4: FreezeCube, Green/YellowCube y controladores de salto migrados.
- Bloque 5: CoreAttack, TeamAI, Objective, Spawner y MapManager migrados; autoloads actualizados.
- Bloque 6: MatchManager, PlayerData, Scoreboard y TeamWeaponSelector migrados; autoload/escenas actualizados.
- No se añadió red, no se modificaron grupos, señales, enums o reglas de juego intencionalmente y no se borró legacy.

### Validación ejecutada

Se completaron playtests funcionales en `map_1`, `map_2`, `map_3`, `Mapa_de_guerra` y `map_dust2`, incluyendo selector de equipo/arma, pool de 23 bots, equipos 12 Azul/11 Rojo, cores, navegación semántica, combate y respawn. No se reportaron errores de parseo/runtime ni recursos faltantes en estas corridas.

`map_dust2` sí contiene Core Azul y Core Rojo en su estado actual; su flujo de CoreAttack y respawn fue verificado. Mantiene la diferencia de no tener el conjunto de puntos semánticos embebidos de los otros mapas.

### Próximo trabajo permitido

La fase de organización está terminada. El siguiente trabajo debe ser una tarea separada: export/check en filesystem case-sensitive, baseline de performance, bugfixes reproducidos o decisión de legacy. No mezclar esas actividades con borrados masivos.

## 7. Riesgos, errores conocidos y dudas abiertas

### Críticos

1. `npc_base.tscn` tiene el script NpcBase pero no los nodos `AreaVision` y `RaycastVision` requeridos. Variantes NPC heredadas dependen de esa escena. No usarla para spawns activos; el MatchManager usa `scenes/npcs/npc.tscn`, que sí contiene los nodos requeridos.
2. El árbol legacy de enemies continúa roto: `enemy_melee.tscn` referencia dependencias ausentes y `enemy_pistolero.gd` hereda de `EnemyBase`, clase inexistente. No se tocó durante Fase 2.
3. La capitalización ya se normalizó a `res://Scripts/` mediante rename intermedio y actualización de rutas activas. Falta validar export/checkout en filesystem case-sensitive; Windows no prueba esa condición. El wrapper legacy sin consumidores detectados `Scripts/role_jump_controller.gd` conserva una ruta histórica en minúsculas y debe resolverse solo dentro de esa validación/decisión de wrappers.
4. El warning histórico de UID inválido en `bot_debug_overlay.tscn` fue saneado durante Fase 2. Si el editor vuelve a mostrar un conflicto de clase global `BotDebugOverlay`, investigar caché/duplicados antes de modificar `class_name`.

### Altos/medios

5. TeamAI puede escanear el menú antes de que existan cores. Los playtests de Fase 2 registraron objetivos correctamente tras cargar cada mapa, pero no se cambió la arquitectura de refresh; conservar como riesgo de ciclo de vida.
6. MapManager busca `semantic_points_<map>.tscn`, pero no existen. Mapas 1/2/3/Guerra tienen marcadores embebidos; Dust2 no. Es un fallback fallido preexistente, no parte de la migración.
7. `map_dust2` está habilitado y **sí tiene cores**; Fase 2 verificó CoreAttack y respawn. La falta pendiente es de marcadores semánticos equivalentes, no de cores.
8. `StateRoaming._check_pickups()` pasa `0.0` a `_check_for_pickups`, por lo que el timer de pickup puede no decrementar. Tratar como bug funcional separado y reproducir antes de tocar.
9. `skill.json` usa `MultiplicadoresDanio`; ConfigManager consulta `MultiplicadoresDano`. Los defaults hoy ocultan el problema.
10. `bot_chatter.json` referencia audio inexistente; no hay consumidor activo encontrado.

## 8. Tareas pendientes priorizadas

### Tarea 0 — Validar distribución case-sensitive

- **Archivos:** sin cambios de gameplay; revisar `project.godot`, rutas `res://Scripts/` y exportación.
- **Objetivo:** confirmar que el rename de capitalización de Fase 2 funciona también en Linux/macOS o CI case-sensitive.
- **Paso:** checkout/export limpio en filesystem sensible a mayúsculas; ejecutar menú y los cinco mapas.
- **Riesgo:** medio/alto: Windows no puede probar esta condición.
- **Prueba:** export y carga sin rutas faltantes/case mismatch.

### Tarea 1 — Baseline y diagnóstico de carga

- **Archivos:** ninguno inicialmente; `project.godot`, mapas, Output.
- **Objetivo:** reproducir errores y línea base antes de movimiento.
- **Pasos:** playtest menú y cada mapa; medir carga/bots; registrar errores; validar selectors, cores, spawners, respawn.
- **Riesgo:** bajo.
- **Prueba:** Profiler/Monitors + checklist de `PERFORMANCE_AUDIT.md`.

### Tarea 2 — Resolver legacy con evidencia

- **Archivos:** BotBrain/behaviors, wrappers, dropped_weapon, MapSemanticPoints, NPC legacy, EnemyPistolero y herramientas.
- **Objetivo:** decidir mantener, migrar a `legacy/`/tests o eliminar.
- **Pasos:** búsqueda de dependencias, playtest, revisión de recursos externos y cambios por bloque; nunca borrar por apariencia.
- **Riesgo:** alto.
- **Prueba:** carga de escenas, búsqueda global, export y escenarios documentados.

### Tarea 3 — Reparar bugs funcionales aislados

- **Archivos iniciales posibles:** `StateRoaming`, TeamAI, MapManager, config de skill y escenas NPC legacy.
- **Objetivo:** reproducir y corregir, por separado, el timer de pickups, ciclo de refresh de TeamAI, fallback de puntos semánticos o nodos faltantes de `npc_base.tscn`.
- **Regla:** una hipótesis reproducida y un cambio funcional por tarea; no mezclar con limpiezas de ruta.
- **Prueba:** escenario manual/automatizado específico antes y después.

### Tarea 4 — Optimizar solo tras perfil

- **Archivos prioritarios:** NpcBase, PerceptionSystem, MovementSystem, StateRoaming, MapManager, Weapon, Scoreboard.
- **Objetivo:** reducir frame time probado sin cambio de comportamiento.
- **Pasos:** ejecutar auditoría de performance, recoger p95/p99, elegir una intervención, medir después.
- **Riesgo:** alto para IA/movimiento.
- **Prueba:** mismas escenas/input/quantidades antes-después.

## 9. Reglas de seguridad operativa

1. Nunca borrar por apariencia o ausencia de grep.
2. Nunca eliminar `.uid` aislados.
3. Nunca alterar nombres públicos de `class_name`, señales, grupos, InputMap, autoloads, RPCs, escenas o rutas sin mapa completo de consumidores.
4. Usar FileSystem de Godot para movimientos si es posible.
5. Actualizar simultáneamente scripts, `.tscn`, `.tres/.res`, `project.godot`, `preload/load`, autoloads y documentación.
6. Un bloque por commit. Validar y documentar antes del siguiente.
7. No mezclar un bugfix funcional con una migración de ruta, salvo que el script no cargue sin él; si ocurre, detener y pedir/registrar aprobación.
8. No optimizar por intuición.
9. Antes de una intervención destructiva, crear/actualizar pruebas o checklist manual reproducible.
10. Registrar cada cambio real en `CHANGELOG_REFACTOR.md`: fecha, archivos, razón, pruebas, resultado y rollback.

## 10. Validación disponible

- Abrir escenas y revisar árbol/recursos del editor.
- Ejecutar juego/escena y leer Output/Debugger.
- `Debugger > Profiler`, Monitors y Visual Profiler.
- Búsqueda global de `res://Scripts/`, rutas legacy residuales, `load`, `preload`, `class_name`, grupos, señales y autoloads.
- Validar estos mapas de `config/maps/MPMapList.json`:
  - `map_1.tscn`
  - `map_2.tscn`
  - `map_3.tscn`
  - `Mapa_de_guerra.tscn`
  - `map_dust2.tscn`
- Scripts de herramienta existentes: `check_nav.gd`, `test_stuck_detection.gd` (este último está desalineado; no confiar en él hasta arreglarlo).

## 11. Prompt breve listo para DeepSeek v4 Pro

```text
Fase 2 de migración estructural está completada en Godot 4.7. Lee primero los cinco Markdown de `res://Docs/Architecture/` y toma como canónicas las rutas `res://Scripts/` y `res://Scripts/MP/`. El proyecto sigue sin networking real: MP significa modo local de equipos/bots/CoreAttack. Antes de tocar gameplay, legacy o rendimiento, define una tarea separada y una prueba reproducible. No borres BotBrain, wrappers, NPC legacy ni herramientas sin evidencia de consumidores nulos y validación de carga/export. Prioridades posteriores: validar export case-sensitive, medir baseline de rendimiento, reproducir bugs documentados y decidir legacy por bloques.
```
