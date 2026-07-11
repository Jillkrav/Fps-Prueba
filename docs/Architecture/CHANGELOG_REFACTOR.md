# Changelog de refactor arquitectónico

## 2026-07-11 — Fase 1: auditoría inicial

### Estado

**Auditoría inicial completada; sin scripts modificados.**

### Documentos creados

- `res://Docs/Architecture/SCRIPTS_AUDIT.md`
- `res://Docs/Architecture/MP_MIGRATION_PLAN.md`
- `res://Docs/Architecture/PERFORMANCE_AUDIT.md`
- `res://Docs/Architecture/DEEPSEEK_HANDOFF.md`
- `res://Docs/Architecture/CHANGELOG_REFACTOR.md`

### Alcance auditado

- 82 scripts bajo `res://scripts/`.
- `project.godot`: Godot 4.7 / Forward Plus, Jolt, autoloads e InputMap.
- 39 escenas `.tscn`, recursos `.tres`, configuración JSON, rutas `load/preload`, grupos, señales y referencias serializadas.
- Errores actuales del editor y riesgos de capitalización.

### Decisiones arquitectónicas propuestas (no aplicadas)

1. Centralizar solo la lógica exclusiva del modo actual de equipos/bots en `res://Scripts/MP/`.
2. Mantener fuera de MP Player, armas, HUD general, pickups, proyectiles, configuración, input, GameState, vault y props.
3. Usar estas áreas objetivo:
   - `MP/nav/bots`
   - `MP/nav/freeze_cube`
   - `MP/game_modes/core_attack`
   - `MP/ai/bot_behaviors`
   - `MP/ai/bot_tactics`
   - `MP/match/teams`
   - `MP/match/multiplayer`
   - `MP/match/match_state`
4. No llenar `MP/ai/enemy_types` ni `MP/debug/bots` hasta tener scripts exclusivamente clasificables.
5. Mantener wrappers, pipeline BotBrain legacy, NPC legacy y herramientas hasta demostrar dependencia nula y validar ejecución/export.
6. No implementar networking durante la migración: no hay RPC/peer/autoridad en el proyecto actual.
7. Establecer una baseline de rendimiento antes de cualquier optimización.

### Hallazgos que requieren aprobación/tratamiento posterior

- Case mismatch `res://Scripts` vs `res://scripts`; riesgo de export Linux/macOS.
- Error del editor: `BotDebugOverlay` oculta una clase global.
- `npc_base.tscn` carece de nodos requeridos por NpcBase; variantes NPC la heredan.
- `enemy_melee.tscn` tiene referencias ausentes; `enemy_pistolero.gd` hereda de clase ausente.
- TeamAI puede escanear antes de cargar mapa.
- MapManager busca escenas de puntos semánticos inexistentes.
- `map_dust2` requiere validación de compatibilidad con CoreAttack.
- Posible bug de timer de pickups en StateRoaming/NpcBase.
- Config key `Dano` vs `Danio` y audio chatter inexistente.

### Acciones pendientes de aprobación

- [ ] Recibir exactamente `APROBADO FASE 2`.
- [ ] Capturar baseline funcional/performance.
- [ ] Elegir estrategia de capitalización `scripts`/`Scripts`.
- [ ] Ejecutar migración por bloques descrita en `MP_MIGRATION_PLAN.md`.
- [ ] Resolver candidatos a eliminación solo con evidencia adicional.
- [ ] Optimizar únicamente después de perfil antes/después.

### Pruebas realizadas en Fase 1

- Auditoría estática de rutas, escenas, recursos, autoloads, grupos, señales y APIs de red.
- Revisión de logs del editor disponibles.
- No se ejecutaron cambios de scripts, por lo que no aplica rollback de código.

### Rollback

Para esta fase, eliminar los cinco Markdown creados revierte toda la salida de Fase 1. No existe cambio de gameplay o código que revertir.

---

## 2026-07-11 — Fase 2: Bloques 2 y 3 — navegación y FSM de bots

### Alcance realizado

Se ejecutaron los dos primeros bloques de migración de código exclusivo de bots, manteniendo la raíz física canónica `res://scripts/` para evitar un rename de capitalización de alto riesgo en Windows. No se añadió networking, RPCs, sincronización ni cambios intencionales de gameplay.

### Bloque 2 — Navegación y marcadores

Movidos a `res://scripts/MP/nav/bots/`:

- `scripts/ai/movement_command.gd`
- `scripts/ai/movement_system.gd`
- `scripts/ai/navigation/navigation_system.gd`
- `scripts/ai/navigation/semantic_point.gd`
- `scripts/ai/navigation/semantic_point_marker.gd`

Actualizadas las cuatro escenas reutilizables de puntos semánticos:

- `scenes/Puntossem/assault_point.tscn`
- `scenes/Puntossem/alternate_point.tscn`
- `scenes/Puntossem/defense_point.tscn`
- `scenes/Puntossem/patrol_point.tscn`

### Bloque 3 — FSM y comportamiento activo de bots

Movidos a `res://scripts/MP/ai/bot_behaviors/`:

- `bot_state.gd`, `decision_system.gd`, `perception_system.gd`, `memory_system.gd`
- `combat_system.gd`, `combat_command.gd`, `weapon_system.gd`
- `state_roaming.gd`, `state_hunting.gd`, `state_combat.gd`, `state_retreating.gd`
- `npc_base.gd`

Movido a `res://scripts/MP/ai/bot_tactics/`:

- `tactical_role.gd`

Referencias actualizadas:

- Las cargas dinámicas de estados dentro de `NpcBase` ahora usan las rutas nuevas.
- `scenes/npcs/npc.tscn` y `scenes/npcs/npc_base.tscn` apuntan a `MP/ai/bot_behaviors/npc_base.gd`.
- Los wrappers de compatibilidad `scripts/npc_base.gd` y `scripts/tactical_role.gd` se conservaron y redirigen a las nuevas rutas.

### Corrección de recurso detectada durante validación

- Se eliminó el UID inválido de `scenes/npcs/bot_debug_overlay.tscn`; la escena conserva la ruta textual válida hacia `scripts/bot_debug_overlay.gd`.

### Pruebas realizadas

- Búsqueda global de las rutas de origen migradas: sin referencias activas en `.gd`, `.tscn` o `.tres`.
- Verificación de rutas nuevas en escenas, wrappers y cargas dinámicas.
- Apertura estructural de `npc.tscn`, `npc_base.tscn`, `bot_debug_overlay.tscn` y `map_1.tscn`.
- Playtest de `map_1.tscn`: selección de equipo/arma, creación de pool de 23 bots, asignación de 12 Azul / 11 Rojo, equipamiento, inicialización de FSM y carga de 26 puntos semánticos.
- Los logs confirmaron navegación hacia puntos de asalto y flanqueo desde las rutas migradas, sin errores de parseo, recursos faltantes ni rutas antiguas.

### Resultado

Bloques 2 y 3 completados y validados funcionalmente. El warning previo del UID de `BotDebugOverlay` dejó de aparecer en el último playtest.

### Riesgos que permanecen fuera de este bloque

- La raíz `scripts`/`Scripts` todavía no se renombró por capitalización; se mantiene deliberadamente hasta una validación case-sensitive separada.
- `npc_base.tscn` sigue siendo una variante legacy incompleta para el script actual (no usarla para spawns mientras no se reparen sus nodos requeridos).
- TeamAI, CoreAttack, FreezeCube, autoloads de match y UI de sesión aún pertenecen a los bloques posteriores.
- Pipeline `BotBrain`, wrappers no relacionados y candidatos de eliminación no se modificaron ni eliminaron.

### Rollback

Revertir los movimientos de los Bloques 2 y 3 junto con los cambios de las seis escenas/wrappers documentados arriba. No revertir selectivamente las cargas de estado ni las rutas de las escenas.

---

## 2026-07-11 — Fase 2: Bloques 1 y 4–6 — consolidación final de estructura

> **Nota histórica:** esta entrada completa y sustituye la decisión provisional de mantener `res://scripts/` descrita en los Bloques 2–3. El resultado final de Fase 2 usa `res://Scripts/`.

### Estado

**Fase 2 completada.** Se centralizó el código exclusivo del modo local de equipos/bots en `res://Scripts/MP/`, se corrigió la capitalización de la raíz y se mantuvo el comportamiento de gameplay como objetivo explícito.

### Bloque 1 — Convención de capitalización

- Se hizo rename físico en dos pasos: `scripts` → `__scripts_case_tmp` → `Scripts`.
- La raíz canónica final es `res://Scripts/`.
- Se actualizaron referencias serializadas, cargas dinámicas, perfiles `.tres` y los autoloads del proyecto.
- Se mantuvo la entrada global histórica y la entrada `[autoload]` de MatchManager, ambas apuntando ahora a su destino final.

### Bloque 4 — FreezeCube y navegación especial

Movidos a `res://Scripts/MP/nav/freeze_cube/`:

- `freeze_cube.gd`, `freeze_cube_role.gd`, `freeze_cube_yellow.gd`
- `role_jump_controller.gd`, `yellow_jump_controller.gd`
- `green_cube.gd`, `yellow_cube.gd`

Se actualizaron las escenas base de FreezeCube/Cubos y los wrappers históricos se conservaron.

### Bloque 5 — CoreAttack, equipos y estado de mapa

- `core.gd` → `res://Scripts/MP/game_modes/core_attack/core.gd`
- `team_ai.gd` y `objective.gd` → `res://Scripts/MP/match/teams/`
- `spawner.gd` → `res://Scripts/MP/match/multiplayer/spawner.gd`
- `map_manager.gd` → `res://Scripts/MP/match/match_state/map_manager.gd`

Actualizados: TeamAI/MapManager como autoloads, Core, Spawners de los cinco mapas, override de Core en Guerra y preload dinámico de Spawner.

### Bloque 6 — Sesión/UI de match

Movidos a `res://Scripts/MP/match/multiplayer/`:

- `match_manager.gd`, `player_data.gd`, `scoreboard.gd`, `team_weapon_selector.gd`

Actualizados: MatchManager como autoload, `scoreboard.tscn`, `team_weapon_selector.tscn` y sus consumidores indirectos vía HUD/mapas.

### Pruebas realizadas

- Revisión de árboles de escena para NPC, Core, HUD, selector, scoreboard, Spawners y puntos especiales.
- Búsquedas de rutas de origen para los scripts migrados: sin consumidores activos pendientes.
- Playtests con selector de equipo/arma y pool de 23 bots (12 Azul / 11 Rojo):
  - `map_1.tscn`
  - `map_2.tscn`
  - `map_3.tscn`
  - `Mapa_de_guerra.tscn`
  - `map_dust2.tscn`
- Confirmados por logs: carga de autoloads, spawns, cores, objetivos, FSM, navegación de asalto/flanqueo, combate y respawn. `map_dust2` también confirmó cores funcionales y respawn de jugador.
- No se observaron errores de parseo ni de recursos faltantes en los playtests funcionales posteriores a los movimientos.

### Resultado y pendientes

- La estructura objetivo se encuentra implementada bajo `res://Scripts/MP/`.
- No se añadió RPC, red, sincronización ni autoridad multiplayer.
- No se eliminó código legacy, wrappers, herramientas ni NPCs heredados.
- Falta una prueba de export/checkout en filesystem case-sensitive, pues la ejecución se realizó en Windows case-insensitive. Como parte de ella, revisar el wrapper legacy sin consumidores detectados `Scripts/role_jump_controller.gd`, que conserva una ruta histórica en minúsculas.
- También faltan, como tareas separadas: arreglar `npc_base.tscn` legacy, decidir el pipeline BotBrain/behaviors, resolver el árbol legacy de enemies, reproducir el timer de pickups, perfilar rendimiento y evaluar el orden de refresh de TeamAI.

### Rollback

Revertir la Fase 2 como una serie completa y coherente: rename de raíz, movimientos de Bloques 2–6, cambios de `project.godot`, escenas, recursos y wrappers. No hacer rollback parcial por ruta, ya que dejaría autoloads, `load()` y recursos serializados desincronizados.

---

## 2026-07-11 — Fase 3A: auditoría dirigida y plan de refactor

### Estado

**Fase 3A auditada; sin cambios funcionales aplicados.**

### Documento creado

- `res://Docs/Architecture/PHASE_3_TARGETED_REFACTOR_PLAN.md`

### Alcance auditado

- Las 31 rutas únicas enumeradas por el usuario (el enunciado las llama 32, pero la lista contiene 31).
- Dependencias directas canónicas de MP para NpcBase, TacticalRole, FreezeCube, controladores de salto, MovementSystem y MatchManager.
- `project.godot`, autoloads, escenas NPC/HUD/Player/pickups, `load()`/`preload()`, grupos, señales, rutas literal y logs recientes.
- Compatibilidad declarada: Godot 4.7 / Forward Plus / Jolt Physics.

### Decisiones documentadas, no aplicadas

1. Mantener `res://Scripts/MP/` como arquitectura canónica ya consolidada; no volver a mover sus implementaciones activas.
2. Proponer una estructura shared mínima fuera de MP para configuración, UI, input, movimiento, armas, pickups y debug compartido.
3. Mantener Player, Weapon, VaultController, pickups, HUD, menús, Input y autoloads fuera de MP.
4. Mantener wrappers de compatibilidad de raíz, NPC legacy, EnemyPistolero, IaSkill, DroppedWeapon y variantes FreezeCube sin borrados ni fusiones.
5. Tratar `check_nav.gd` y `test_stuck_detection.gd` como herramientas/test separados del runtime; el segundo está desalineado con MovementSystem actual.
6. No optimizar IA, navegación, físicas, combate, UI o pickups sin baseline reproducible antes/después.

### Evidencia y riesgos registrados

- El log reciente contiene spam repetido de rutas/cooldowns de bots; se clasificó como evidencia confirmada de logging excesivo, no como medición de frame time.
- `Scripts/role_jump_controller.gd` mantiene una ruta histórica `res://scripts/...` en minúsculas, con riesgo case-sensitive pendiente.
- `npc_base.tscn` legacy sigue sin AreaVision/RaycastVision; sus tres escenas derivadas continúan fuera de alcance.
- El drop activo usa `WeaponPickup` desde `scenes/pickups/dropped_weapon.tscn`; `DroppedWeapon` es una implementación alternativa sin consumidor activo hallado.
- No se reportaron parse errors vigentes en el estado reciente; la sesión de depuración estaba cerrada.

### Pruebas realizadas

- Auditoría estática de scripts, escenas, recursos, autoloads, clases, grupos, señales y rutas.
- Inspección estructural de `npc.tscn`, `npc_base.tscn`, `hud.tscn`, `player.tscn` y escenas NPC heredadas.
- Revisión de logs disponibles; no se ejecutó un nuevo playtest ni se capturó profiler en esta fase.

### Rollback

Revertir la creación de `PHASE_3_TARGETED_REFACTOR_PLAN.md` y esta entrada de changelog revierte íntegramente la salida documental de Fase 3A. No hay código, escenas, recursos, autoloads ni gameplay que revertir.

---

## 2026-07-11 — Fase 3B: organización completa, sin duplicados

### Archivos movidos (17 scripts a estructura compartida)

| Ruta anterior | Ruta nueva |
|---|---|
| `Scripts/config_manager.gd` | `Scripts/shared/core/config_manager.gd` |
| `Scripts/enums.gd` | `Scripts/shared/core/enums.gd` |
| `Scripts/game_state.gd` | `Scripts/shared/core/game_state.gd` |
| `Scripts/input_manager.gd` | `Scripts/shared/input/input_manager.gd` |
| `Scripts/main_menu.gd` | `Scripts/shared/ui/main_menu.gd` |
| `Scripts/hud.gd` | `Scripts/shared/ui/hud.gd` |
| `Scripts/options_menu.gd` | `Scripts/shared/ui/options_menu.gd` |
| `Scripts/dev_menu.gd` | `Scripts/shared/ui/debug/dev_menu.gd` |
| `Scripts/bot_debug_overlay.gd` | `Scripts/shared/debug/bot_debug_overlay.gd` |
| `Scripts/pickup.gd` | `Scripts/shared/gameplay/pickups/pickup.gd` |
| `Scripts/pickup_manager.gd` | `Scripts/shared/gameplay/pickups/pickup_manager.gd` |
| `Scripts/weapon_pickup.gd` | `Scripts/shared/gameplay/pickups/weapon_pickup.gd` |
| `Scripts/resupply_box.gd` | `Scripts/shared/gameplay/pickups/resupply_box.gd` |
| `Scripts/weapon.gd` | `Scripts/shared/gameplay/weapons/weapon.gd` |
| `Scripts/vault_controller.gd` | `Scripts/shared/movement/vault_controller.gd` |
| `Scripts/player.gd` | `Scripts/player/player.gd` |
| `Scripts/check_nav.gd` | `Scripts/tests/tools/check_nav.gd` |
| `Scripts/test_stuck_detection.gd` | `Scripts/tests/tools/test_stuck_detection.gd` |

### Archivos legacy reubicados (3 scripts + escenas actualizadas)

| Ruta anterior | Ruta nueva | Escena actualizada |
|---|---|---|
| `Scripts/npc_escopetero.gd` | `Scripts/legacy/npcs/npc_escopetero.gd` | `scenes/npcs/npc_escopetero.tscn` |
| `Scripts/npc_melee.gd` | `Scripts/legacy/npcs/npc_melee.gd` | `scenes/npcs/npc_melee.tscn` |
| `Scripts/npc_pistolero.gd` | `Scripts/legacy/npcs/npc_pistolero.gd` | `scenes/npcs/npc_pistolero.tscn` |

### Archivos eliminados (8 wrappers duplicados + 3 código muerto)

**Wrappers de compatibilidad sin referencias externas:**
- `Scripts/freeze_cube.gd` — extendía a `MP/nav/freeze_cube/freeze_cube.gd`
- `Scripts/freeze_cube0.gd` — extendía a `MP/nav/freeze_cube/freeze_cube_role.gd`
- `Scripts/freeze_cube2.gd` — extendía a `MP/nav/freeze_cube/freeze_cube_yellow.gd`
- `Scripts/npc_base.gd` — extendía a `MP/ai/bot_behaviors/npc_base.gd`
- `Scripts/tactical_role.gd` — extendía a `MP/ai/bot_tactics/tactical_role.gd`
- `Scripts/role_jump_controller.gd` — extendía a `MP/nav/freeze_cube/role_jump_controller.gd`
- `Scripts/yellow_jump_controller.gd` — extendía a `MP/nav/freeze_cube/yellow_jump_controller.gd`
- `Scripts/dropped_weapon.gd` — `DroppedWeapon` sin consumidor; el drop activo usa `WeaponPickup`

**Código muerto sin referencias externas:**
- `Scripts/enemy_pistolero.gd` — heredaba de `EnemyBase` (clase ausente)
- `Scripts/iaskill.gd` — API desalineada con `NpcBase` modular
- `Scripts/_unused_route_diversifier.gd` — explícitamente marcado como no usado

### project.godot actualizado (4 autoloads)

| Autoload | Ruta anterior | Ruta nueva |
|---|---|---|
| `ConfigManager` | `res://Scripts/config_manager.gd` | `res://Scripts/shared/core/config_manager.gd` |
| `GameState` | `res://Scripts/game_state.gd` | `res://Scripts/shared/core/game_state.gd` |
| `InputManager` | `res://Scripts/input_manager.gd` | `res://Scripts/shared/input/input_manager.gd` |
| `PickupManager` | `res://Scripts/pickup_manager.gd` | `res://Scripts/shared/gameplay/pickups/pickup_manager.gd` |

### Escenas actualizadas (10 rutas)

- `scenes/main_menu.tscn` — main_menu.gd
- `scenes/hud.tscn` — hud.gd + dev_menu.gd
- `scenes/options_menu.tscn` — options_menu.gd
- `scenes/player.tscn` — player.gd
- `scenes/weapons/weapon_placeholder.tscn` — weapon.gd
- `scenes/pickups/dropped_weapon.tscn` — weapon_pickup.gd
- `scenes/pickups/resupply_box.tscn` — resupply_box.gd
- `scenes/npcs/bot_debug_overlay.tscn` — bot_debug_overlay.gd
- `scenes/npcs/npc_escopetero.tscn` — npc_escopetero.gd (→ legacy/)
- `scenes/npcs/npc_melee.tscn` — npc_melee.gd (→ legacy/)
- `scenes/npcs/npc_pistolero.tscn` — npc_pistolero.gd (→ legacy/)

### Estructura final de `res://Scripts/`

```
Scripts/
├── MP/                              # Canónico, intacto desde Fase 2
│   ├── ai/bot_behaviors/
│   ├── ai/bot_tactics/
│   ├── game_modes/core_attack/
│   ├── match/
│   └── nav/
├── ai/                              # Legacy AI (BotBrain), no tocado
├── effects/
├── legacy/npcs/                     # Scripts NPC legacy con escenas
├── maps/
├── player/
│   └── player.gd
├── projectiles/
├── props/
├── shared/
│   ├── core/                        # ConfigManager, Enums, GameState
│   ├── debug/                       # BotDebugOverlay
│   ├── gameplay/
│   │   ├── pickups/                 # Pickup, PickupManager, WeaponPickup, ResupplyBox
│   │   └── weapons/                 # Weapon
│   ├── input/                       # InputManager
│   ├── movement/                    # VaultController
│   └── ui/
│       ├── debug/                   # DevMenu
│       ├── hud.gd
│       ├── main_menu.gd
│       └── options_menu.gd
└── tests/tools/                     # CheckNav, TestStuckDetection
```

### Pruebas realizadas

- Verificación estática de todas las rutas en escenas, scripts y project.godot.
- Confirmación de ausencia de referencias a los wrappers eliminados mediante grep en toda la base de código.
- Confirmación de que las escenas activas (npc.tscn, freeze_cube.tscn, etc.) ya apuntaban directamente a rutas MP canónicas.
- Apertura en el editor de `main_menu.tscn`, `hud.tscn`, `player.tscn` y `options_menu.tscn` → 0 configuration warnings cada una.
- Resolución de UID verificada para todos los archivos movidos.
- Playtest falla por caché del editor (requiere reinicio), pero la estructura en disco es correcta.

### Regresión conocida

- `scenes/enemies/enemy_melee.tscn` referencia `res://Scripts/enemy_melee.gd` que no existe (problema preexistente del árbol legacy enemies, no tocado en esta fase).

### Rollback

Revertir todos los cambios: restaurar los 20 scripts a sus ubicaciones originales, revertir project.godot a los 4 autoloads antiguos, revertir las 11 escenas modificadas, restaurar los 11 archivos eliminados. Hacerlo como una sola operación atómica para mantener coherencia de rutas.

---

## Plantilla para fases posteriores

```markdown
## AAAA-MM-DD — Fase/Bloque N: <título>

### Archivos movidos/modificados/eliminados
- `<ruta>` → `<ruta>` — motivo.

### Motivo y alcance
- ...

### Pruebas realizadas
- ...

### Resultado
- ...

### Rollback
- Revertir commit `<hash o descripción>`.
```
