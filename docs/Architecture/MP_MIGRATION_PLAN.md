# Plan de migración a `Scripts/MP` — Cierre de Fase 2

> **Estado:** Fase 2 completada el 2026-07-11. Los Bloques 1–6 se ejecutaron; la bitácora final está en la sección 6.1 y en `CHANGELOG_REFACTOR.md`.
>
> **Aprobación de ejecución:** recibida y consumida para esta fase.
>
> **Principio aplicado:** preservar comportamiento. Los movimientos se validaron con árboles de escena, búsquedas de rutas y playtests; el rollback debe tratar la Fase 2 como una serie coherente de rutas/autoloads/recursos.

## 1. Objetivo

Centralizar solo el código **exclusivo del modo actual de equipos/bots** dentro de la estructura solicitada, sin mover gameplay compartido, UI general, armas, Player, configuración global ni sistemas reutilizables.

La estructura no convierte el proyecto en multijugador de red: hoy no existen RPCs, peers ni sincronización. La carpeta `MP` seguirá significando temporalmente **modo de partida local por equipos con bots/CoreAttack**. El diseño de red deberá ser una iniciativa separada.

## 2. Convención de rutas y riesgo de capitalización

Al inicio, el proyecto usaba rutas serializadas `res://scripts/...` aunque el objetivo requerido era `res://Scripts/MP/...`. En Fase 2 se aplicó el rename intermedio y las rutas activas quedaron normalizadas a `res://Scripts/...`. Sigue pendiente una validación de export/checkout en Linux/macOS o CI case-sensitive.

**Decisión propuesta:** adoptar exactamente la convención solicitada:

```text
res://Scripts/MP/
```

con todas las carpetas internas y nombres de archivos en minúscula.

**Medida obligatoria:** un rename solo de capitalización puede ser invisible para Git/Windows. En Fase 2 debe hacerse como operación en dos pasos y mediante FileSystem de Godot cuando sea posible:

```text
scripts -> __scripts_case_tmp -> Scripts
```

No se debe ejecutar ese rename amplio como primer bloque; primero hay que corregir todas las rutas y confirmar que no hay referencias externas pendientes. Si el riesgo de capitalización no puede validarse en un entorno case-sensitive, se recomienda mantener temporalmente la raíz física `res://scripts` y aplicar la taxonomía interna, documentando la desviación. La aprobación humana decide entre cumplimiento estricto y riesgo operativo.

## 3. Estructura actual relevante

```text
res://scripts/
├── MP/Bots/
│   ├── npc_base.gd
│   ├── tactical_role.gd
│   ├── freeze_cube*.gd
│   └── *_jump_controller.gd
├── ai/
│   ├── navigation/
│   ├── states/
│   ├── perception_system.gd
│   ├── movement_system.gd
│   ├── combat_system.gd
│   └── [pipeline BotBrain legacy]
├── match_manager.gd
├── map_manager.gd
├── team_ai.gd
├── spawner.gd
├── core.gd
├── player_data.gd
├── scoreboard.gd
├── team_weapon_selector.gd
├── green_cube.gd
└── yellow_cube.gd
```

## 4. Estructura objetivo propuesta

```text
res://Scripts/MP/
├── debug/
│   └── bots/                       # reservado; no mover BotDebugOverlay aún
├── nav/
│   ├── bots/
│   │   ├── navigation_system.gd
│   │   ├── movement_system.gd
│   │   ├── movement_command.gd
│   │   ├── semantic_point.gd
│   │   ├── semantic_point_marker.gd
│   │   └── route_diversifier.gd    # solo si se reactiva/retiene
│   └── freeze_cube/
│       ├── freeze_cube.gd
│       ├── freeze_cube_role.gd
│       ├── freeze_cube_yellow.gd
│       ├── role_jump_controller.gd
│       ├── yellow_jump_controller.gd
│       ├── green_cube.gd
│       └── yellow_cube.gd
├── game_modes/
│   └── core_attack/
│       └── core.gd
├── ai/
│   ├── enemy_types/                # vacío inicialmente: no hay tipo de enemigo activo confirmado
│   ├── bot_behaviors/
│   │   ├── npc_base.gd
│   │   ├── bot_state.gd
│   │   ├── decision_system.gd
│   │   ├── perception_system.gd
│   │   ├── memory_system.gd
│   │   ├── combat_system.gd
│   │   ├── combat_command.gd
│   │   ├── weapon_system.gd
│   │   ├── state_roaming.gd
│   │   ├── state_hunting.gd
│   │   ├── state_combat.gd
│   │   └── state_retreating.gd
│   └── bot_tactics/
│       └── tactical_role.gd
└── match/
    ├── teams/
    │   ├── team_ai.gd
    │   └── objective.gd
    ├── multiplayer/
    │   ├── match_manager.gd
    │   ├── player_data.gd
    │   ├── spawner.gd
    │   ├── scoreboard.gd
    │   └── team_weapon_selector.gd
    └── match_state/
        └── map_manager.gd
```

### Por qué `match/multiplayer` vs `match/match_state`

- `match/multiplayer`: entidades de sesión que administran participantes, spawn, equipos, player data, UI de selección y tabla de resultados.
- `match/match_state`: bootstrap y transición del mundo de match: mapa cargado, cores presentes, spawners configurados, NavMesh y puntos semánticos.

Aunque los nombres contienen multiplayer, no se debe añadir networking durante esta migración.

## 5. Matriz de movimientos propuestos

### 5.1 Movimientos con alta confianza, sujetos a validación de referencias

| Ruta actual | Ruta destino propuesta | Justificación | Referencias que deben actualizarse |
|---|---|---|---|
| `scripts/MP/Bots/npc_base.gd` | `Scripts/MP/ai/bot_behaviors/npc_base.gd` | Orquestador exclusivo de bots de partida. | `scenes/npcs/npc.tscn`, `npc_base.tscn`, wrappers `scripts/npc_base.gd`, cargas dinámicas de estados dentro de NpcBase, documentación. |
| `scripts/ai/bot_state.gd` | `Scripts/MP/ai/bot_behaviors/bot_state.gd` | Base de FSM exclusiva de bots activos. | Scripts State*, DecisionSystem, UID/class cache. |
| `scripts/ai/decision_system.gd` | `Scripts/MP/ai/bot_behaviors/decision_system.gd` | FSM actual exclusiva de bot. | NpcBase y tipos `DecisionSystem`. |
| `scripts/ai/perception_system.gd` | `Scripts/MP/ai/bot_behaviors/perception_system.gd` | Percepción de NpcBase. | NpcBase, BotState/estados, UID/class cache. |
| `scripts/ai/memory_system.gd` | `Scripts/MP/ai/bot_behaviors/memory_system.gd` | Memoria de NpcBase. | NpcBase, Perception/State*, UID/class cache. |
| `scripts/ai/combat_system.gd` | `Scripts/MP/ai/bot_behaviors/combat_system.gd` | Combate del bot. | NpcBase, Decision/StateCombat, UID/class cache. |
| `scripts/ai/combat_command.gd` | `Scripts/MP/ai/bot_behaviors/combat_command.gd` | DTO del sistema de bot. | DecisionSystem, CombatSystem, BotState. |
| `scripts/ai/weapon_system.gd` | `Scripts/MP/ai/bot_behaviors/weapon_system.gd` | Gestión de armas propia de bot. | NpcBase, CombatSystem/DecisionSystem. |
| `scripts/ai/states/state_roaming.gd` | `Scripts/MP/ai/bot_behaviors/state_roaming.gd` | Estado actual de bot. | Carga `load()` de NpcBase; referencias a nombre interno State_Roaming. |
| `scripts/ai/states/state_hunting.gd` | `Scripts/MP/ai/bot_behaviors/state_hunting.gd` | Estado actual de bot. | `load()` de NpcBase. |
| `scripts/ai/states/state_combat.gd` | `Scripts/MP/ai/bot_behaviors/state_combat.gd` | Estado actual de bot. | `load()` de NpcBase. |
| `scripts/ai/states/state_retreating.gd` | `Scripts/MP/ai/bot_behaviors/state_retreating.gd` | Estado actual de bot. | `load()` de NpcBase. |
| `scripts/MP/Bots/tactical_role.gd` | `Scripts/MP/ai/bot_tactics/tactical_role.gd` | Define agresividad/defensa/flanqueo/roles. | Wrapper, NpcBase, Perception, StateRoaming, TeamAI, MatchManager. |
| `scripts/ai/movement_command.gd` | `Scripts/MP/nav/bots/movement_command.gd` | Comando exclusivo de movimiento de bot. | DecisionSystem, MovementSystem, estados. |
| `scripts/ai/movement_system.gd` | `Scripts/MP/nav/bots/movement_system.gd` | Navegación, vault y anti-stuck de bot. | NpcBase, BotState/Decision, test_stuck_detection. |
| `scripts/ai/navigation/navigation_system.gd` | `Scripts/MP/nav/bots/navigation_system.gd` | NavigationAgent/semántica de bots. | NpcBase, StateRoaming, FreezeCube0, marker. |
| `scripts/ai/navigation/semantic_point.gd` | `Scripts/MP/nav/bots/semantic_point.gd` | DTO exclusivo de rutas bot. | Marker, NavigationSystem, StateRoaming, MapSemanticPoints legacy. |
| `scripts/ai/navigation/semantic_point_marker.gd` | `Scripts/MP/nav/bots/semantic_point_marker.gd` | Marcadores usados por rutas bot. | 4 escenas `Puntossem/*point.tscn`, NavigationSystem. |
| `scripts/MP/Bots/freeze_cube.gd` | `Scripts/MP/nav/freeze_cube/freeze_cube.gd` | Solo llama `NpcBase.freeze()`. | Escena `Puntossem/freeze_cube.tscn`, wrapper. |
| `scripts/MP/Bots/freeze_cube0.gd` | `Scripts/MP/nav/freeze_cube/freeze_cube_role.gd` | Solo bots y salto de rol. | Escena `freeze_cube0.tscn`, wrapper. |
| `scripts/MP/Bots/freeze_cube2.gd` | `Scripts/MP/nav/freeze_cube/freeze_cube_yellow.gd` | Solo bots/yellow route. | Escena `freeze_cube2.tscn`, wrapper. |
| `scripts/MP/Bots/role_jump_controller.gd` | `Scripts/MP/nav/freeze_cube/role_jump_controller.gd` | Helper exclusivo de FreezeCube0. | Wrapper, FreezeCube0. |
| `scripts/MP/Bots/yellow_jump_controller.gd` | `Scripts/MP/nav/freeze_cube/yellow_jump_controller.gd` | Helper exclusivo de FreezeCube2. | Wrapper, FreezeCube2. |
| `scripts/green_cube.gd` | `Scripts/MP/nav/freeze_cube/green_cube.gd` | Solo grupo/objetivo de freeze bot. | Escena `green_cube.tscn`, NpcBase. |
| `scripts/yellow_cube.gd` | `Scripts/MP/nav/freeze_cube/yellow_cube.gd` | Solo grupo/objetivo de freeze bot. | Escena `yellow_cube.tscn`, NpcBase, FreezeCube2. |
| `scripts/core.gd` | `Scripts/MP/game_modes/core_attack/core.gd` | Exclusivo del objetivo de CoreAttack. | `objectives/core.tscn`, MapManager preload, GameState/TeamAI por class_name. |
| `scripts/team_ai.gd` | `Scripts/MP/match/teams/team_ai.gd` | Órdenes y objetivos por equipo. | `project.godot` autoload, NpcBase, StateRoaming, Core. |
| `scripts/ai/objective.gd` | `Scripts/MP/match/teams/objective.gd` | Recurso exclusivo de TeamAI/CoreAttack actual. | TeamAI y class cache. |
| `scripts/match_manager.gd` | `Scripts/MP/match/multiplayer/match_manager.gd` | Autoridad local de sesión, participantes y respawns. | `project.godot`, HUD, Player, selector, DevMenu, Core/NpcBase por singleton. |
| `scripts/player_data.gd` | `Scripts/MP/match/multiplayer/player_data.gd` | DTO exclusivo de MatchManager/scoreboard. | MatchManager, Scoreboard y class cache. |
| `scripts/spawner.gd` | `Scripts/MP/match/multiplayer/spawner.gd` | Spawns de equipos del match. | 5 mapas, MapManager preload. |
| `scripts/scoreboard.gd` | `Scripts/MP/match/multiplayer/scoreboard.gd` | UI atada a PlayerData/MatchManager. | `scenes/scoreboard.tscn`, HUD instancia la escena. |
| `scripts/team_weapon_selector.gd` | `Scripts/MP/match/multiplayer/team_weapon_selector.gd` | Inicio de equipo/arma de match. | `scenes/team_weapon_selector.tscn`, 5 mapas instancian esa escena. |
| `scripts/map_manager.gd` | `Scripts/MP/match/match_state/map_manager.gd` | Bootstrap del mapa y estado de partida. | `project.godot`, `GameState.match_ended`, preload de Core/Spawner. |

### 5.2 Archivos que deliberadamente no se mueven

| Archivo | Razón |
|---|---|
| `game_state.gd` | Mezcla estado de partida con preferencias persistentes. Requiere una extracción futura, no una mudanza. |
| `player.gd`, `weapon.gd`, `vault_controller.gd` | Gameplay humano/bot y posible SP; clave para futura red. |
| `weapon_ai_profile.gd` + `config/ai_profiles/*.tres` | Perfil de arma reutilizable; moverlo acoplaría datos compartidos al modo actual. |
| `pickup*.gd`, `resupply_box.gd`, `projectiles/*`, `effects/*`, `props/*` | Mecánicas genéricas. |
| `hud.gd`, `options_menu.gd`, `main_menu.gd` | UI híbrida/general; separar responsabilidades antes de mover. |
| `bot_debug_overlay.gd` | También se instancia desde Player. No es exclusivo de bots. |
| `dev_menu.gd` | Herramienta transversal; decisión pendiente sobre builds de desarrollo. |
| Pipeline `BotBrain` legacy y wrappers | Primero decidir eliminación/migración; no mover código probablemente obsoleto para “ordenarlo”. |

### 5.3 Rutas que no deben crearse con scripts todavía

- `Scripts/MP/ai/enemy_types/`: vacío. No hay enemy type activo y válido que pueda moverse.
- `Scripts/MP/debug/bots/`: vacío. BotDebugOverlay sigue compartido con Player.
- No se deben crear duplicados o adaptadores solo para llenar carpetas.

## 6. Orden exacto de ejecución por bloques reversibles

### Bloque 0 — Preflight y línea base (sin movimiento)

1. Hacer commit de Fase 1 y confirmar árbol limpio.
2. Reabrir/reindexar editor y capturar errores actuales.
3. Ejecutar menu y los 5 mapas de `MPMapList.json`; registrar carga, selección, spawn, combate, muerte, respawn, cambio de equipo y salida.
4. Buscar rutas exactas, UIDs, autoloads, `load/preload`, escenas, recursos y grupos de cada archivo candidato.
5. Confirmar si `map_dust2` dispone de cores funcionales antes de usarlo como test de CoreAttack.

**Rollback:** no hay modificación.

### Bloque 1 — Reparar/controlar la convención de capitalización

1. Elegir explícitamente la estrategia `Scripts` vs `scripts` después de validar export o checkout case-sensitive.
2. Si se adopta `Scripts`, usar rename intermedio para evitar que Windows/Git ignore el cambio.
3. Reindexar y buscar todo `res://scripts/`/`res://Scripts/` residual.

**Validación:** abrir escenas y verificar que no se rompen recursos; no continuar con case mismatch.

**Rollback:** revertir únicamente el commit de rename de carpeta; no mezclar con movimientos de scripts.

### Bloque 2 — Navegación bot y marcadores

Mover juntos: `movement_command`, `movement_system`, `navigation_system`, `semantic_point`, `semantic_point_marker`.

1. Mover con FileSystem de Godot.
2. Actualizar scripts internos, `MapManager` preload si corresponde, escenas `Puntossem/*point.tscn`, UIDs y documentación.
3. Validar carga de mapas 1, 2, 3 y Guerra; revisar rutas de NavigationAgent y puntos semánticos.

**Rollback:** revertir este commit; no toca IA de decisión aún.

### Bloque 3 — FSM y comportamiento de bot

Mover juntos: `npc_base`, `bot_state`, `decision_system`, `perception_system`, `memory_system`, `combat_system`, `combat_command`, `weapon_system`, los cuatro estados, `tactical_role`.

1. Actualizar `load()` de estados dentro de NpcBase.
2. Actualizar escenas `npc.tscn`/`npc_base.tscn` y wrappers conservados.
3. Reindexar `class_name` y resolver el error BotDebugOverlay si persiste, sin alterar API pública innecesariamente.
4. Playtest: 2 bots, luego cantidad configurada; verificar FSM, target, disparo, recarga, muerte y respawn.

**Rollback:** revertir el commit de bloque completo; no eliminar wrappers.

### Bloque 4 — FreezeCube y navegación especial

Mover FreezeCube, variantes, controladores y Green/Yellow cubes.

1. Actualizar 5 escenas `Puntossem` relevantes y wrappers.
2. Playtest de `map_3` y `Mapa_de_guerra`: trigger, congelación, saltos, descongelación y bots vivos/muertos.

**Rollback:** revertir el commit de bloque; no tocar comportamiento ni parámetros.

### Bloque 5 — CoreAttack y equipos

Mover Core, Objective, TeamAI, Spawner, MapManager.

1. Actualizar `project.godot` autoloads de TeamAI y MapManager.
2. Actualizar `core.tscn`, 5 mapas por Spawner y preloads de MapManager.
3. Antes de mover, corregir solamente si es necesario para ejecución el orden de refresh de TeamAI; si afecta comportamiento, separar en un bloque aprobado posterior.
4. Playtest CoreAttack completo: inicio, objetivos, core, victoria, reset, reintento y cambio de mapa.

**Rollback:** revertir el commit; volver rutas de autoload y escenas en la misma reversión.

### Bloque 6 — Sesión/UI de match

Mover MatchManager, PlayerData, Scoreboard y TeamWeaponSelector.

1. Actualizar autoload `MatchManager` en `project.godot`.
2. Actualizar `scoreboard.tscn`, `team_weapon_selector.tscn`, mapas que instancian selector y todas las referencias a PlayerData.
3. Playtest selector de equipo, armas, scoreboard, respawn, auto-balance y salida a menú.

**Rollback:** revertir el bloque completo, incluidas rutas de autoload.

### Bloque 7 — Documentación, wrappers y limpieza diferida

1. Actualizar `SCRIPTS_AUDIT.md`, este plan, handoff y changelog con rutas reales.
2. Los wrappers y legacy se **mantienen**. Abrir tickets/commits independientes para su retirada posterior.
3. Solo después de evidencia y aprobación, abordar candidatos de eliminación por bloques.

## 6.1 Ejecución final registrada — 2026-07-11

> **Estado:** Fase 2 completada. Los Bloques 1–6 se ejecutaron. La raíz canónica se renombró mediante paso intermedio a `res://Scripts/`; se actualizaron autoloads, escenas, recursos, `load()`/`preload()` y perfiles de arma para eliminar referencias activas a la raíz anterior.

### Bloque 1 completado — capitalización segura

- Rename físico en dos pasos: `scripts → __scripts_case_tmp → Scripts`.
- Raíz final: `res://Scripts/`.
- Autoloads actualizados: `ConfigManager`, `GameState`, `InputManager`, `PickupManager`, `TeamAI`, `MapManager` y `MatchManager`.
- Rutas serializadas de escenas, scripts y perfiles AI normalizadas a `res://Scripts/...`.
- La prueba se realizó sobre Windows case-insensitive; sigue recomendándose validar el export final en Linux/macOS o CI case-sensitive.

### Bloque 2 completado — navegación bot y marcadores

Movidos a `res://Scripts/MP/nav/bots/`:

- `movement_command.gd`, `movement_system.gd`, `navigation_system.gd`
- `semantic_point.gd`, `semantic_point_marker.gd`

Las escenas reutilizables de `scenes/Puntossem/` usan el marcador migrado.

### Bloque 3 completado — FSM y comportamiento activo

Movidos a `res://Scripts/MP/ai/bot_behaviors/`:

- `npc_base.gd`, `bot_state.gd`, `decision_system.gd`
- `perception_system.gd`, `memory_system.gd`
- `combat_system.gd`, `combat_command.gd`, `weapon_system.gd`
- `state_roaming.gd`, `state_hunting.gd`, `state_combat.gd`, `state_retreating.gd`

Movido a `res://Scripts/MP/ai/bot_tactics/tactical_role.gd`.

### Bloque 4 completado — FreezeCube y navegación especial

Movidos a `res://Scripts/MP/nav/freeze_cube/`:

- `freeze_cube.gd`, `freeze_cube_role.gd`, `freeze_cube_yellow.gd`
- `role_jump_controller.gd`, `yellow_jump_controller.gd`
- `green_cube.gd`, `yellow_cube.gd`

Se actualizaron las cinco escenas base de `Puntossem` y se conservaron wrappers de compatibilidad de FreezeCube/saltos.

### Bloque 5 completado — CoreAttack, equipos y mapa

Movidos:

- `core.gd` → `Scripts/MP/game_modes/core_attack/`
- `team_ai.gd`, `objective.gd` → `Scripts/MP/match/teams/`
- `spawner.gd` → `Scripts/MP/match/multiplayer/`
- `map_manager.gd` → `Scripts/MP/match/match_state/`

Se actualizaron los autoloads TeamAI/MapManager, los cinco mapas que usan Spawner, `core.tscn`, el override de Core de `Mapa_de_guerra` y el preload dinámico de Spawner en MapManager.

### Bloque 6 completado — sesión y UI de partida

Movidos a `res://Scripts/MP/match/multiplayer/`:

- `match_manager.gd`, `player_data.gd`, `scoreboard.gd`, `team_weapon_selector.gd`

Se actualizaron las dos entradas de MatchManager en `project.godot`, `scoreboard.tscn` y `team_weapon_selector.tscn`. HUD continúa fuera de MP y consume las escenas migradas por composición.

### Validación registrada

- Búsquedas estáticas: no quedan rutas activas hacia los scripts migrados en su ubicación pre-Fase 2.
- Árbol de escena y recursos verificados para NPC, puntos semánticos, FreezeCube, Core, HUD, selector y scoreboard.
- Playtests de los cinco mapas configurados: `map_1`, `map_2`, `map_3`, `Mapa_de_guerra` y `map_dust2`.
- En los escenarios validados: selección equipo/arma, 23 bots (12 Azul/11 Rojo), objetivos de Core, navegación semántica, combate y respawn funcionaron sin errores de parseo/runtime.
- `map_dust2` confirmó cores y respawn funcionales; la advertencia histórica de que carecía de cores queda descartada. Sigue sin marcadores semánticos embebidos equivalentes a los otros mapas.
- Se saneó el UID inválido de la escena compartida `bot_debug_overlay.tscn` durante Bloques 2–3.

### Estado posterior a Fase 2

La organización de rutas está completa. Lo que queda es deliberadamente **fuera de la migración**: validación de export case-sensitive, reparación o retiro separado de escenas/NPC legacy rotos, evaluación de pipeline BotBrain y wrappers, baseline de rendimiento y posibles bugfixes funcionales ya documentados.

**Excepción de compatibilidad registrada:** el wrapper legacy `res://Scripts/role_jump_controller.gd` no tiene consumidores activos detectados, pero conserva internamente una ruta histórica en minúsculas. No afecta los playtests Windows actuales; debe corregirse o retirarse únicamente junto con la validación case-sensitive/decisión de wrappers, nunca borrar por apariencia.

## 7. Checklist de validación posterior a cada bloque

- [x] Editor/recursos principales reabiertos sin errores nuevos de parseo.
- [x] Playtests posteriores sin rutas antiguas que fallen ni recursos faltantes.
- [x] Autoloads de Fase 2 actualizados y cargados en playtests.
- [x] Escenas afectadas verificadas con árbol de escena.
- [x] Rutas de origen de los scripts migrados sin consumidores activos.
- [x] Rutas de destino verificadas en escenas, wrappers y cargas dinámicas.
- [x] Escenarios de regresión de los cinco mapas ejecutados.
- [x] Capitalización normalizada a `res://Scripts/` mediante rename intermedio.
- [ ] Crear commit(s) atómicos en el repositorio del usuario y validar export/checkout case-sensitive.

## 8. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Cambio de capitalización rompe export Linux/macOS | Rename en dos pasos, búsqueda global de rutas, prueba en FS case-sensitive si es posible. |
| Escenas mantienen path/UID antiguo | Mover desde FileSystem de Godot y reabrir/revalidar cada escena afectada. |
| `load()` de estados se rompe silenciosamente | Actualizar rutas como parte del mismo commit de NpcBase; test de bot spawning/FSM. |
| Autoloads dejan de cargar | Actualizar `project.godot` en el mismo bloque que MatchManager/TeamAI/MapManager; validar singleton. |
| Uso indirecto de wrappers/legacy | No borrar wrappers; conservar compatibilidad hasta export/búsqueda exhaustiva posterior. |
| Cambio organizativo altera mecánicas | No cambiar nombres de clase, señales, grupos, enums, InputMap ni valores de export durante movimientos. |
| Mapa Dust2 carece de puntos semánticos embebidos | CoreAttack y respawn ya fueron validados; no usarlo para comparar rutas semánticas de los otros mapas. |
| TeamAI escanea antes del mapa | Tratar como bug funcional separado, no esconderlo dentro de migración de rutas. |
| Confundir “MP” con red | Prohibido añadir RPC, sincronizadores o autoridad en esta migración. |

## 9. Plan de rollback

Cada bloque tiene un commit atómico. Para revertir:

1. Detener la escena en ejecución.
2. Revertir **solo** el commit del bloque afectado.
3. Reabrir editor para reimportar scripts/UIDs.
4. Abrir las escenas afectadas y ejecutar el checklist del bloque anterior.
5. Registrar el motivo y resultado en `CHANGELOG_REFACTOR.md`.

No hacer rollback manual parcial de rutas porque puede dejar `.tscn`, autoloads, `load()` y wrappers en estados incompatibles.

## 10. Acciones expresamente fuera de alcance

- Añadir multijugador de red/RPC.
- Reescribir MatchManager, NpcBase, MovementSystem o Weapon por estética.
- Eliminar BotBrain, wrappers, NPC legacy o herramientas.
- Mover Player, Weapon, HUD, Projectiles, Pickups o configuración a MP.
- Optimizar sin perfil y sin una prueba antes/después.
