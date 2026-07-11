# Plan de refactor dirigido — Fase 3A

> **Estado:** auditoría y planificación completadas el 2026-07-11. **No se movió, renombró, eliminó ni modificó ningún script, escena, recurso, autoload o ajuste funcional en esta fase.**
>
> **Puerta de ejecución:** este documento es la línea base para Fase 3B. No se ejecutará ningún bloque hasta recibir exactamente: `APROBADO FASE 3B`.

## 1. Resumen confirmado de Fase 2 y restricciones heredadas

### Fase 2 confirmada

- La raíz canónica activa es `res://Scripts/` — capital **S** obligatoria.
- El código exclusivo del modo local de equipos/bots quedó bajo `res://Scripts/MP/`:
  - `ai/bot_behaviors/`, `ai/bot_tactics/`
  - `nav/bots/`, `nav/freeze_cube/`
  - `game_modes/core_attack/`
  - `match/teams/`, `match/multiplayer/`, `match/match_state/`
- Se actualizaron escenas, recursos, autoloads, `load()`/`preload()` y perfiles de armas para las rutas activas migradas.
- Playtests históricos posteriores a Fase 2 en `map_1`, `map_2`, `map_3`, `Mapa_de_guerra` y `map_dust2` validaron selector, equipos, pool de 23 bots (12 Azul/11 Rojo), spawners, cores, CoreAttack, FSM, navegación, combate y respawn, sin rutas ni recursos faltantes reportados.
- No existe networking real: no se debe añadir `@rpc`, peers, autoridad, sincronización ni código multiplayer de red. En este proyecto, `MP` sigue significando el modo local de equipos con bots.

### Restricciones heredadas que permanecen fuera de alcance

1. Validar export/check-out en filesystem sensible a mayúsculas/minúsculas.
2. Capturar baseline real con Profiler/Monitors antes de optimizar IA, navegación, combate o render.
3. `res://scenes/npcs/npc_base.tscn` sigue sin `AreaVision` ni `RaycastVision`; las escenas NPC heredadas dependen de ella.
4. Árbol legacy `enemies` roto y `EnemyBase` ausente.
5. Timer de pickups potencialmente desalineado en `StateRoaming`/`NpcBase`.
6. Posible refresh demasiado temprano de `TeamAI`.
7. Fallback `semantic_points_<map>.tscn` sin archivos correspondientes.
8. Decisión futura sobre BotBrain, wrappers, scripts legacy y candidatos a borrado.

No se mezclará ninguno de esos temas con movimientos puramente organizativos, salvo que un archivo objetivo resulte ser la causa directa y exista evidencia reproducible.

## 2. Versión y compatibilidad detectadas

| Fuente | Resultado |
|---|---|
| `project.godot` | `config/features=PackedStringArray("4.7", "Forward Plus")` |
| Editor/proyecto | Godot **4.7-stable (Steam)** |
| Física 3D | **Jolt Physics** |
| Plataforma auditada | Windows x64 / D3D12 |

Toda implementación posterior deberá usar exclusivamente APIs y sintaxis compatibles con Godot 4.7. No se cambiarán APIs públicas, `class_name`, autoloads, señales, grupos, InputMap, RPCs inexistentes, rutas de recursos ni contratos de escenas sin un mapa de consumidores y una prueba del bloque.

## 3. Alcance e inventario de scripts solicitados

### Nota de conteo

La enumeración entregada contiene **31 rutas únicas**, aunque el enunciado dice «32 scripts». No se infirió ni se agregó un script número 32. El inventario siguiente cubre exactamente las 31 rutas provistas; cualquier ruta adicional debe aprobarse de forma explícita antes de incluirse.

### Leyenda

- **Categoría:** MP, compartido, legacy, debug/test, UI, jugador o configuración.
- **Mover / Refactor / Eliminar:** B=bajo, M=medio, A=alto.
- **Destino `mantener`:** decisión deliberada de no mover todavía; no equivale a código muerto.
- Los consumidores citados son estáticos o estructurales confirmados; la ausencia de grep no descarta cargas externas, `class_name`, recursos de usuario o escenas no versionadas.

| # | Ruta actual | Responsabilidad y dependencias directas | Consumidores conocidos | Categoría | Ruta destino propuesta | Riesgo mover / refactor / eliminar |
|---:|---|---|---|---|---|---|
| 1 | `Scripts/bot_debug_overlay.gd` | Overlay 3D con `SubViewport` para `NpcBase` y `Player`; lee arma, vida, rol, FSM y orden. | `bot_debug_overlay.tscn`; preload en `Player` y `MP/.../npc_base.gd`; botones de `DevMenu`. | Debug compartido | `Scripts/shared/debug/bot_debug_overlay.gd` **solo** con actualización atómica de escena/preloads. | M / M / A |
| 2 | `Scripts/check_nav.gd` | Herramienta `SceneTree` que lista propiedades de `NavigationMesh` y llama `quit()`. | Ninguna escena, autoload o carga estática encontrada. | Debug/test genérico | `Scripts/tests/tools/check_nav.gd`. | B / B / M |
| 3 | `Scripts/config_manager.gd` | Autoload que carga `config/skill.json`; expone salud, multiplicadores y datos de armas. | `[autoload]`; Player, Weapon, HUD, DevMenu, MatchManager, NpcBase, selector y legacy. | Configuración compartida | `Scripts/shared/core/config_manager.gd`, en un bloque atómico con `project.godot` y consumidores. | A / M / A |
| 4 | `Scripts/dev_menu.gd` | UI de desarrollo: spawn manual, invisibilidad, armas, equipo, TeamAI y overlays. | Nodo `DevMenu` de `hud.tscn`; HUD abre con InputMap `dev_menu`. | UI/debug híbrida | `Scripts/shared/ui/debug/dev_menu.gd`; desactivación de release es tema separado. | M / M / A |
| 5 | `Scripts/dropped_weapon.gd` | Implementación alternativa `DroppedWeapon : RigidBody3D`, con pickup automático y visual propio. | No hay consumidor activo; la escena `pickups/dropped_weapon.tscn` usa `WeaponPickup`, no este script. | Legacy / candidato a deduplicación | Mantener durante Fase 3B; futuro condicional `Scripts/legacy/pickups/dropped_weapon.gd`. | M / M / A |
| 6 | `Scripts/enemy_pistolero.gd` | Tipo legacy que hereda de `EnemyBase` y usa APIs antiguas. | Sin instancia o escena activa encontrada; `EnemyBase` no está presente. | Legacy | Mantener; futuro condicional `Scripts/legacy/ai/enemy_pistolero.gd`. | A / A / A |
| 7 | `Scripts/enums.gd` | Contrato global `Enums`: equipos, experiencia, estado táctico y rol. | GameState, Player, HUD, menús y toda la arquitectura MP. | Compartido / configuración | `Scripts/shared/core/enums.gd`, con actualización integral de tipos y cargas. | A / A / A |
| 8 | `Scripts/freeze_cube.gd` | Wrapper de compatibilidad hacia `MP/nav/freeze_cube/freeze_cube.gd`. | Sin consumidores activos; escena base ya usa implementación canónica MP. | Legacy de compatibilidad / MP | **Mantener en ruta actual** como endpoint de compatibilidad. | M / B / M |
| 9 | `Scripts/freeze_cube0.gd` | Wrapper hacia `freeze_cube_role.gd` canónico. | Sin consumidores activos; `freeze_cube0.tscn` apunta a MP. | Legacy de compatibilidad / MP | **Mantener en ruta actual**. | M / B / M |
| 10 | `Scripts/freeze_cube2.gd` | Wrapper hacia `freeze_cube_yellow.gd` canónico. | Sin consumidores activos; `freeze_cube2.tscn` apunta a MP. | Legacy de compatibilidad / MP | **Mantener en ruta actual**. | M / B / M |
| 11 | `Scripts/game_state.gd` | Autoload que mezcla selección de mapa/arma, preferencias persistentes, equipos, cores y resultado. | `[autoload]`; menú, HUD, Player, Options, DevMenu, Core, MapManager, TeamAI y MatchManager. | Configuración/estado compartido | `Scripts/shared/core/game_state.gd` solo como movimiento de ruta; separar preferencias/match es trabajo futuro independiente. | A / A / A |
| 12 | `Scripts/hud.gd` | HUD humano: pausa, muerte, input, prompt de pickup, CoreAttack, scoreboard y UI de match. | `hud.tscn`, instanciada por los mapas; usa Player/GameState/MatchManager/Options/DevMenu. | UI compartida | `Scripts/shared/ui/hud.gd`; **no** mover a MP. | A / M / A |
| 13 | `Scripts/iaskill.gd` | Extensión legacy de `NpcBase` con hooks y miembros del modelo previo. | No se encontró instancia; APIs no coinciden con NpcBase modular vigente. | Legacy IA | Mantener; futuro condicional `Scripts/legacy/ai/iaskill.gd`. | A / A / A |
| 14 | `Scripts/input_manager.gd` | Autoload que crea/rebindea acciones y persiste `user://key_bindings.cfg`. | `[autoload]`; OptionsMenu. Acciones consumidas por Player/HUD/DevMenu. | Configuración/input compartido | `Scripts/shared/input/input_manager.gd`, en bloque atómico con autoload. | A / M / A |
| 15 | `Scripts/main_menu.gd` | Entrada general: lista `MPMapList.json`, selección de mapa, máximo de jugadores y opciones. | Escena principal `main_menu.tscn`; `project.godot`. | UI global | `Scripts/shared/ui/main_menu.gd`; no MP aunque hoy inicie mapas MP. | A / M / A |
| 16 | `Scripts/npc_base.gd` | Wrapper de compatibilidad hacia `MP/ai/bot_behaviors/npc_base.gd`. | Sin escena activa; `npc.tscn` y `npc_base.tscn` apuntan al canónico. | Legacy de compatibilidad / MP | **Mantener en ruta actual**. | M / B / M |
| 17 | `Scripts/npc_escopetero.gd` | Archivo vacío/deprecado; escena heredada le asigna el script. | `scenes/npcs/npc_escopetero.tscn` lo adjunta y deriva de `npc_base.tscn`. | Legacy | Mantener junto a su escena; futuro `Scripts/legacy/npcs/`. | A / A / A |
| 18 | `Scripts/npc_melee.gd` | Archivo vacío/deprecado; escena heredada le asigna el script. | `scenes/npcs/npc_melee.tscn`. | Legacy | Mantener junto a su escena; futuro `Scripts/legacy/npcs/`. | A / A / A |
| 19 | `Scripts/npc_pistolero.gd` | Archivo vacío/deprecado; escena heredada le asigna el script. | `scenes/npcs/npc_pistolero.tscn`. | Legacy | Mantener junto a su escena; futuro `Scripts/legacy/npcs/`. | A / A / A |
| 20 | `Scripts/options_menu.gd` | UI global de equipo, audio, vídeo, mouse y rebinding. | `options_menu.tscn`; instanciada por HUD y MainMenu; usa InputManager/GameState/MatchManager. | UI/configuración compartida | `Scripts/shared/ui/options_menu.gd`; no MP. | A / M / A |
| 21 | `Scripts/pickup.gd` | Base `Pickup : RigidBody3D`; registro, despawn, física y contrato de recogida. | Base de `WeaponPickup`; Player y NpcBase lo consumen por contrato. | Gameplay compartido | `Scripts/shared/gameplay/pickups/pickup.gd`. | A / M / A |
| 22 | `Scripts/pickup_manager.gd` | Autoload que registra y consulta pickups. | `[autoload]`; Pickup por `/root/PickupManager`; NpcBase. | Gameplay compartido | `Scripts/shared/gameplay/pickups/pickup_manager.gd`, con autoload y accesos root actualizados. | A / M / A |
| 23 | `Scripts/player.gd` | `Player : CharacterBody3D`: input, cámara, movimiento, vault, armas, daño, respawn, pickups y overlay. | `player.tscn`; cinco mapas; HUD, MatchManager, selector, armas, pickups, resupply y proyectiles. | Jugador / compartido | `Scripts/player/player.gd` **solo con aprobación específica del bloque de jugador**. No MP. | A / A / A |
| 24 | `Scripts/resupply_box.gd` | Área reutilizable que repone Player y se reactiva por cooldown. | `resupply_box.tscn`; mapas 1/2/3/Guerra. | Gameplay compartido | `Scripts/shared/gameplay/pickups/resupply_box.gd`. | M / M / A |
| 25 | `Scripts/role_jump_controller.gd` | Wrapper de `RoleJumpController`; contiene una ruta `res://scripts/...` en minúsculas. | Sin consumidor activo encontrado; implementación canónica es creada por FreezeCube de rol. | Compatibilidad / MP | **Mantener en ruta actual**; corregir capitalización interna solo tras validar caso sensible. | M / B / M |
| 26 | `Scripts/tactical_role.gd` | Wrapper hacia `MP/ai/bot_tactics/tactical_role.gd`. | Sin consumidor directo; canónico lo usan NpcBase, estados, percepción, TeamAI y MatchManager. | Compatibilidad / MP | **Mantener en ruta actual**. | M / B / M |
| 27 | `Scripts/test_stuck_detection.gd` | Herramienta `SceneTree` de stuck detection desalineada con `MovementSystem`. | No está integrado en `run_tests`, escena ni autoload. | Test legacy de bots | `Scripts/MP/debug/bots/test_stuck_detection.gd` tras reescritura de test-only contra `MovementSystem`. | B / M / M |
| 28 | `Scripts/vault_controller.gd` | `VaultController : RefCounted` reutilizable para Player y MovementSystem de bots. | `Player.new()` y `MP/nav/bots/movement_system.gd`. | Movimiento compartido | `Scripts/shared/movement/vault_controller.gd`; no MP. | A / A / A |
| 29 | `Scripts/weapon.gd` | `Weapon : Node3D`: hitscan, proyectiles, melee, munición, VFX, reload y perfil AI. | `weapon_placeholder.tscn`; Player, NpcBase, CombatSystem, WeaponSystem, pickups y proyectiles. | Gameplay compartido | `Scripts/shared/gameplay/weapons/weapon.gd`; no MP. | A / A / A |
| 30 | `Scripts/weapon_pickup.gd` | `WeaponPickup : Pickup`, flujo activo de drop y recogida por Player/NpcBase. | `pickups/dropped_weapon.tscn`; preload de NpcBase; Player. | Gameplay compartido | `Scripts/shared/gameplay/pickups/weapon_pickup.gd`. | A / M / A |
| 31 | `Scripts/yellow_jump_controller.gd` | Wrapper hacia controlador canónico Yellow. | Sin consumidor directo; FreezeCube amarillo lo instancia desde MP. | Compatibilidad / MP | **Mantener en ruta actual**. | M / B / M |

## 4. Movimientos propuestos

### Estructura compartida mínima propuesta

No existe una jerarquía `Shared/Common` consolidada. Para evitar duplicación y carpetas MP artificiales, la propuesta mínima fuera de MP es:

```text
res://Scripts/
├── shared/
│   ├── core/                 # enums, configuración y estado global
│   ├── input/                # InputManager
│   ├── ui/                   # HUD, menús y opciones
│   │   └── debug/            # DevMenu
│   ├── debug/                # overlay compartido Player/Bot
│   ├── gameplay/
│   │   ├── weapons/
│   │   └── pickups/
│   └── movement/             # VaultController
├── player/                   # Player humano, de alto riesgo
├── tests/tools/              # herramientas genéricas no cargadas por gameplay
└── MP/                       # ya canónico; no se duplica ni se vuelve a mover
```

Las rutas `Scripts/legacy/` y `Scripts/compat/` **no se crearán ni se usarán automáticamente** durante Fase 3B: mover wrappers exigiría dejar wrappers nuevos en sus rutas históricas y mover scripts legacy exigiría tocar escenas heredadas. Ambos resultados contradicen el objetivo de no duplicar ni romper compatibilidad. Los wrappers actuales de raíz tienen responsabilidad clara de compatibilidad y se mantienen hasta una decisión de eliminación aprobada.

| Ruta actual | Ruta destino propuesta | Justificación | Referencias que se actualizarían en el bloque | Pruebas mínimas requeridas |
|---|---|---|---|---|
| `Scripts/check_nav.gd` | `Scripts/tests/tools/check_nav.gd` | Herramienta genérica, no runtime ni MP. | Documentación/comandos de herramienta si aparecieran en barrido final. | Ejecutar herramienta manual; abrir proyecto y comprobar ausencia de referencias antiguas. |
| `Scripts/test_stuck_detection.gd` | `Scripts/MP/debug/bots/test_stuck_detection.gd` | Test exclusivo del anti-stuck de bots, separado del runtime. | Documentación y comando de prueba; no escenas. | Primero actualizar test contra API real; ejecutar test y verificar que no altera gameplay. |
| `Scripts/bot_debug_overlay.gd` | `Scripts/shared/debug/bot_debug_overlay.gd` | También se instancia sobre Player, por tanto no es MP exclusivo. | `bot_debug_overlay.tscn`, preload de Player/NpcBase y cualquier ruta literal. | Toggle desde DevMenu con jugador + bots; overlay OFF/ON; no parser error de clase. |
| `Scripts/dev_menu.gd` | `Scripts/shared/ui/debug/dev_menu.gd` | Herramienta UI transversal: Player, armas, bots y TeamAI. | `hud.tscn` y referencias de escena. | Q/acción `dev_menu`, spawn manual, toggles y salida/pausa. |
| `Scripts/config_manager.gd` | `Scripts/shared/core/config_manager.gd` | Configuración global de armas y salud, compartida. | `[autoload]`, rutas, scripts que lo precarguen/carguen. | Autoload, menús, carga de armas Player/NPC, JSON válido. |
| `Scripts/enums.gd` | `Scripts/shared/core/enums.gd` | Contrato transversal, no exclusivo de MP. | Escenas/scripts por path y caché de clases. | Abrir proyecto, cargar menú/mapa, Player/NPC/TeamAI. |
| `Scripts/game_state.gd` | `Scripts/shared/core/game_state.gd` | Estado persistente mixto; mover ruta sin dividir responsabilidades. | `[autoload]`, todos los consumidores por ruta y escenas si corresponde. | Preferencias mouse, cores, resultado y regreso a menú. |
| `Scripts/input_manager.gd` | `Scripts/shared/input/input_manager.gd` | Input y rebinding son globales. | `[autoload]`, OptionsMenu. | InputMap, rebind, guardar/cargar `user://key_bindings.cfg`. |
| `Scripts/main_menu.gd` | `Scripts/shared/ui/main_menu.gd` | Punto de entrada general; iniciar MP no lo hace exclusivo de MP. | `main_menu.tscn`, escena principal. | Menú, lista de mapas, opciones, selección y cambio de escena. |
| `Scripts/hud.gd` | `Scripts/shared/ui/hud.gd` | HUD de jugador incluye pausa, muerte, pickup y composición de match. | `hud.tscn` y mapas que la instancian. | HUD, pausa, muerte/respawn, scoreboard, core bars y prompt pickup. |
| `Scripts/options_menu.gd` | `Scripts/shared/ui/options_menu.gd` | Ajustes globales de usuario y UI híbrida. | `options_menu.tscn`, MainMenu, HUD. | Audio, vídeo, mouse, rebinding, abrir/cerrar desde ambos contextos. |
| `Scripts/pickup.gd` | `Scripts/shared/gameplay/pickups/pickup.gd` | Base reutilizable para Player y bots. | `WeaponPickup`, escena/pickups y class cache. | Caída, área, despawn y recogida Player/NPC. |
| `Scripts/pickup_manager.gd` | `Scripts/shared/gameplay/pickups/pickup_manager.gd` | Servicio de pickups reutilizable. | `[autoload]`, `/root/PickupManager`, NpcBase/Pickup. | Registro/unregister, nearest pickup y transiciones de escena. |
| `Scripts/resupply_box.gd` | `Scripts/shared/gameplay/pickups/resupply_box.gd` | Pickup reutilizable del jugador. | `resupply_box.tscn`, cuatro mapas. | Reponer vida/munición y cooldown visual. |
| `Scripts/weapon_pickup.gd` | `Scripts/shared/gameplay/pickups/weapon_pickup.gd` | Drop activo compartido entre Player y bots. | `dropped_weapon.tscn`, NpcBase preload, Player. | Drop NPC, auto-ammo, confirmación E, pickup NPC y despawn. |
| `Scripts/weapon.gd` | `Scripts/shared/gameplay/weapons/weapon.gd` | Arma genérica consumida por humano y bots. | `weapon_placeholder.tscn`, Player/NpcBase, VFX/proyectiles/perfiles. | Hitscan, perdigones, melee, proyectiles, recarga, HUD y bot. |
| `Scripts/vault_controller.gd` | `Scripts/shared/movement/vault_controller.gd` | Reutilizado por Player y `MovementSystem`. | Player y MovementSystem. | Vault de Player y bot, escalón, rampa, colisión y HUD indicator. |
| `Scripts/player.gd` | `Scripts/player/player.gd` | Organización fuera de MP, pero archivo de máximo riesgo. | `player.tscn`, cinco mapas, HUD, MatchManager, selector, pickups y armas. | Requiere autorización específica; movimiento/cámara/input/vault/armas/daño/respawn completos. |

### Rutas que no se moverán en la primera ejecución de Fase 3B

| Ruta | Motivo técnico |
|---|---|
| `Scripts/freeze_cube.gd`, `freeze_cube0.gd`, `freeze_cube2.gd`, `role_jump_controller.gd`, `tactical_role.gd`, `yellow_jump_controller.gd`, `npc_base.gd` | Son wrappers de compatibilidad ya mínimos. Moverlos obligaría a recrear wrappers en sus rutas actuales para mantener consumidores externos desconocidos; no aporta orden neto ni reduce riesgo. |
| `Scripts/dropped_weapon.gd` | Existe un flujo activo distinto con `WeaponPickup`; mover antes de resolver la duplicidad solo oculta una decisión funcional pendiente. |
| `Scripts/enemy_pistolero.gd`, `iaskill.gd`, `npc_escopetero.gd`, `npc_melee.gd`, `npc_pistolero.gd` | Legacy de alto riesgo y/o escenas dependientes. No deben moverse ni borrarse sin pruebas de carga y aprobación por archivo. |

## 5. Archivos que deben mantenerse fuera de MP

| Archivo | Razón para no mover a `Scripts/MP/` |
|---|---|
| `config_manager.gd`, `enums.gd`, `game_state.gd`, `input_manager.gd` | Son contratos/autoloads globales. GameState además mezcla preferencias persistentes con estado de match. |
| `main_menu.gd`, `options_menu.gd`, `hud.gd`, `dev_menu.gd` | UI global, de jugador o híbrida; una pantalla puede componer UI de match sin convertirse en código MP exclusivo. |
| `bot_debug_overlay.gd` | Se instancia tanto sobre `Player` como sobre `NpcBase`. |
| `player.gd` | Mecánicas humanas y base futura para single player/online; no debe acoplarse a la partida local actual. |
| `weapon.gd`, `vault_controller.gd` | Se comparten entre Player y bots. |
| `pickup.gd`, `pickup_manager.gd`, `weapon_pickup.gd`, `resupply_box.gd` | Sistema de gameplay reutilizable para humano, bots y futuro single player. |
| `dropped_weapon.gd` | Aunque sea legacy, representa una mecánica de gameplay genérica, no una regla exclusiva de match. |
| `check_nav.gd` | Herramienta genérica de NavigationMesh, no comportamiento exclusivo de bots. |

## 6. Candidatos de fusión, deduplicación o eliminación

| Archivos involucrados | Evidencia | Riesgo | Cambio mínimo propuesto | Alternativa conservadora |
|---|---|---|---|---|
| `dropped_weapon.gd` vs `weapon_pickup.gd` | El flujo activo de drop es `NpcBase` → `pickups/dropped_weapon.tscn` → `WeaponPickup`; `DroppedWeapon` no tiene consumidor estático. Ambos implementan datos, visual de caja/material y suma/equipo de munición. | A: difieren en pickup automático vs confirmación actual del Player. | Ninguno en Fase 3B inicial; caracterizar ambos flujos y pedir aprobación por archivo antes de retirar uno. | Conservar ambos y documentar `WeaponPickup` como canónico activo. |
| `freeze_cube_role.gd` + `role_jump_controller.gd` vs `freeze_cube_yellow.gd` + `yellow_jump_controller.gd` | Los controladores comparten interpolación parabólica y rotación; las variantes difieren en destino, duración, reinicio de roaming y contrato de descongelación. | A: altera física, cooldown, ruta y FSM. | No extraer base en esta fase. | Mantener las variantes explícitas y comparar por pruebas de mapa 3/Guerra antes de cualquier helper interno. |
| `NpcBase` canónico: saltos green/yellow vs controladores Role/Yellow | Hay código parabólico parecido en NpcBase y en dos controladores. Cada flujo se dispara desde un FreezeCube diferente. | A: comportamiento y ownership de freeze distintos. | No consolidar. | Mantener por contrato de cubo hasta una batería de pruebas de trayectorias. |
| Wrappers de raíz: `npc_base`, `tactical_role`, `freeze_cube*`, `role_jump_controller`, `yellow_jump_controller` | Son redirecciones mínimas a rutas canónicas MP; no se detectaron consumidores internos activos. `role_jump_controller` conserva ruta con `scripts` minúscula. | M: posibles consumidores externos/case-sensitive. | Corregir solo el case de `role_jump_controller` si el preflight case-sensitive lo habilita. | Mantener todos en sus rutas históricas y no eliminar. |
| `npc_escopetero.gd`, `npc_melee.gd`, `npc_pistolero.gd` + sus escenas | Scripts declaran deprecación, pero sus tres escenas los adjuntan y derivan de `npc_base.tscn`, escena que ya es incompleta para NpcBase actual. | A. | Ninguno sin probar carga de cada escena y decidir destino del árbol legacy. | Conservar scripts y escenas intactos. |
| `enemy_pistolero.gd` | Hereda `EnemyBase`, clase no encontrada; sin instancia activa. | A. | Ninguno; primero prueba explícita de carga y revisión de assets externos. | Mantener como evidencia histórica. |
| `iaskill.gd` | Usa API de NpcBase anterior (`EstadoTactico`, target y helpers ausentes) y no tiene consumidor confirmado. | A. | Ninguno; no adaptar a FSM nueva dentro de una fase de orden. | Mantener hasta decidir si se elimina o se reescribe como módulo nuevo. |
| `check_nav.gd` | Herramienta de una sola ejecución sin consumidor. | B. | Mover a tools y documentar cómo ejecutarla. | Mantener en raíz hasta tener runner de herramientas. |
| `test_stuck_detection.gd` | Consulta `NpcBase.STUCK_PROGRESS_THRESHOLD`, mientras el contrato actual está en `MovementSystem` con claves string. | M. | Reescribir únicamente el test, no gameplay, antes de moverlo/ejecutarlo. | Mantenerlo marcado como no confiable. |

**Regla de eliminación:** no se eliminará ningún archivo en Fase 3B sin aprobación explícita **por archivo**, evidencia de referencias directas/indirectas nulas, prueba de carga/export aplicable y rollback exacto.

## 7. Auditoría de rendimiento

### Estado de medición

No existe baseline de Profiler/Monitors aportada. Por ello, no se declara ningún cuello de botella de frame time confirmado. La única evidencia runtime reciente es **spam repetido de Output** con mensajes de rutas de roaming y cooldown de cubos; el log actual termina con «Debugging process stopped» y no reporta parse errors nuevos.

| Problema | Archivo / función | Clasificación | Evidencia | Cambio propuesto (solo tras aprobación/medición) | Métrica antes/después |
|---|---|---|---|---|---|
| Logging repetitivo de navegación/cooldowns | Dependencias directas: `MP/.../state_roaming.gd`; `NpcBase._debug()` | **CONFIRMADA** como spam de consola; impacto en ms no medido. | Output actual contiene numerosas líneas `[roaming] Cubo en cooldown` y `Punto de Asalto/Flanqueo`; NpcBase imprime desde `_debug`. | Añadir categoría/flag de debug o limitar logs por evento solo en bloque aislado. | Líneas/minuto, Script/Idle time, tamaño de Output, frame p95. |
| Persistencia duplicada de ajustes de mouse | `game_state.gd` setters + `options_menu.gd::_on_sensitivity_changed/_on_invert_y_toggled` | **CONFIRMADA** como doble llamada a guardado por interacción; coste de I/O no medido. | El setter de GameState llama `save_mouse_settings()` y OptionsMenu vuelve a llamarlo después de asignar la propiedad. | Eliminar una sola llamada conservando persistencia, únicamente tras prueba de guardar/cargar. | Número de escrituras en `user://`, tiempo de interacción con slider. |
| Overlay por entidad y `SubViewport` por frame cuando está activado | `bot_debug_overlay.gd::_process` | **PROBABLE** | Actualiza textos, stylebox, datos dinámicos y visibilidad por frame; se instancia en Player y bots al activar. | Mantener OFF por defecto; medir antes de throttle/event-driven. | CPU/GPU frame time, draw calls, memoria, overlay OFF vs ON. |
| Cadena completa IA/física por bot | Dependencia directa `MP/.../npc_base.gd::_physics_process` | **PROBABLE** | Por tick encadena percepción, memoria, TeamAI, core, FSM, movimiento, combate, arma y `move_and_slide`. | No optimizar sin profiler; considerar scheduling/LOD solo si se demuestra coste. | Script/Physics self/inclusive, p95/p99 con 2/23/máximo configurado. |
| LOS, física y allocs en percepción | Dependencia `perception_system.gd::update` | **PROBABLE** | Area overlaps, RayCast forzado, `intersect_ray`, dictionaries y sort por candidatos. | Medir primero; cache/tick-rate solo si preserva targeting. | Raycasts/tick, Script self, GC/allocs, precisión de target. |
| Raycasts/vault/anti-stuck de navegación | Dependencia `movement_system.gd::_execute_navigate`, `vault_controller.gd` | **PROBABLE** | Step front puede ejecutarse más de una vez por tick; step down, ramp, vault y recuperación lanzan raycasts. Vault se usa tanto Player como bots. | Cache por tick únicamente tras caracterización de trayectorias. | Physics time, raycasts/tick, stuck recoveries, pruebas de rampas/vault. |
| `get_nodes_in_group` de cubos | `freeze_cube_yellow.gd::_find_nearest_yellow_cube`; NpcBase green/yellow | **OPCIONAL** | Búsqueda lineal ocurre por activación de cubo/freeze, no por frame. | Cachear solo si el profiler muestra activaciones masivas. | Tiempo de handler, cantidad de cubos, tasa de activación. |
| Pickup manager lineal | `pickup_manager.gd::get_nearby_pickups/get_nearest_pickup` | **OPCIONAL** | Consulta O(N); NpcBase pretende limitar escaneo a dos segundos. | No introducir spatial hash sin medición. | Cantidad de pickups, Script self, decisiones pickup. |
| Movimiento Player | `player.gd::_physics_process` + `vault_controller.gd::can_vault` | **PROBABLE** | Consulta de vault y dos raycasts step-up al moverse; un Player local reduce escala. | Solo medir; no cambiar sensación de movimiento. | Physics self, input-to-motion, pruebas vault/escalón. |
| Disparo, trails, proyectiles y timers | `weapon.gd::_fire_*`, `_spawn_bullet_trail`, `show_muzzle_flash`, reload | **PROBABLE** | Raycast por pellet, instanciación de trail/proyectil y SceneTreeTimer por disparo/recarga. | Pooling o reducción solo con benchmark de combate y validación visual. | Frame p95/p99, nodos vivos, memoria, draw calls, cadencia/daño. |
| Materiales/meshes de pickups | `weapon_pickup.gd::_update_visual`, `dropped_weapon.gd::_update_mesh`, `resupply_box.gd` | **OPCIONAL** | Crea recursos por evento de spawn/actualización, no per-frame. | No cambiar hasta medir spam de drops. | Pico de spawn, objetos/memoria y GC. |
| Match UI/session refresh | Dependencias `match_manager.gd::_process`, scoreboard; `hud.gd::_process` | **PROBABLE** | Respawn/data sync por frame; scoreboard se consulta por input. | Priorizar solo tras medición con scoreboard visible y bots altos. | Script self, UI updates, players_data_changed/minuto. |
| Configuración y menús | `config_manager.gd`, `input_manager.gd`, `main_menu.gd`, `dev_menu.gd` | **OPCIONAL** | Carga JSON/construye controles en eventos o ready, no loop crítico. | No optimizar. | Tiempo de carga de menú y memoria UI. |

### Escenarios de baseline obligatorios antes de una optimización

1. Menú principal y Options: 60 s.
2. Mapa vacío después de carga: 60 s.
3. Partida de 2 bots: 120 s.
4. Pool histórico de 23 bots y, si la configuración lo permite, máximo configurable: 180 s.
5. Combate intenso con arma de perdigones, proyectiles y pickups: 120 s.
6. `map_3` y `Mapa_de_guerra`: FreezeCube, verde, amarillo y salto: 120 s.
7. Muerte/respawn/cambio de equipo y CoreAttack hasta victoria.
8. Overlay OFF frente a ON.

Se registrarán mediana/p95/p99 de frame time, Script/Physics/Idle time, memoria/nodos, draw calls, errores y líneas de Output. Ninguna optimización de IA, navegación, combate, input, cámara, daño o física se ejecutará sin comparación reproducible.

## 8. Plan de implementación por bloques pequeños y reversibles

Cada bloque requiere aprobación previa, un estado Git inspeccionado y una pausa posterior para revisión humana. Un bloque no incluirá limpieza o cambios funcionales no indicados.

### Bloque 0 — Preflight de Fase 3B, sin cambios

1. Leer `git status --short` y `git diff --`.
2. Separar y no tocar cambios preexistentes del usuario.
3. No crear commit ni stash sin autorización expresa.
4. Capturar baseline/logs y abrir las escenas afectadas por el primer bloque.
5. Confirmar que no hay escena ejecutándose y limpiar logs solo si se desea una línea base nueva.

### Bloque 1 — Herramientas debug/test y compatibilidad de navegación

Alcance potencial, sin tocar gameplay:

- Mover `check_nav.gd` a `Scripts/tests/tools/` si el barrido final confirma referencias nulas.
- Reescribir `test_stuck_detection.gd` como test-only contra `MovementSystem` actual; moverlo a `Scripts/MP/debug/bots/` solo si pasa.
- Corregir el case de `Scripts/role_jump_controller.gd` **solo** tras validar que el filesystem/export case-sensitive requiere la ruta correcta y que no hay consumidor que dependa de la forma incorrecta.
- No mover `bot_debug_overlay.gd` a MP: se documenta como shared.

### Bloque 2 — FreezeCube y controladores de salto

- No modificar parámetros físicos, señales, capas, cooldowns, interpolación ni rutas tácticas.
- Confirmar escenas `freeze_cube.tscn`, `freeze_cube0.tscn`, `freeze_cube2.tscn`, `green_cube.tscn`, `yellow_cube.tscn` y sus instancias en `map_3`/Guerra.
- Mantener los wrappers en raíz.
- La fusión de controladores queda explícitamente fuera del bloque hasta disponer de pruebas de trayectoria.

### Bloque 3 — IA, NPC legacy, roles y wrappers

- Mantener NpcBase y TacticalRole canónicos donde ya están bajo MP.
- Mantener wrappers de raíz.
- Caracterizar carga de `IaSkill`, `EnemyPistolero` y las tres escenas NPC legacy antes de cualquier traslado o eliminación.
- No adaptar el pipeline BotBrain ni escenas legacy dentro de este bloque.

### Bloque 4 — Estado/configuración y servicios compartidos

- Solo tras validación de rutas/autoloads: mover de forma atómica `ConfigManager`, `Enums`, `GameState`, `InputManager` y `PickupManager` a la estructura shared propuesta.
- Actualizar `project.godot`, rutas literales, autoloads y consumidores en el mismo bloque.
- No dividir GameState ni cambiar nombres de singleton, métodos, señales o persistencia.

### Bloque 5 — UI compartida y herramientas de desarrollo

- Mover atómicamente MainMenu, HUD, OptionsMenu, DevMenu y BotDebugOverlay a `Scripts/shared/ui`/`debug`.
- Actualizar MainMenu/HUD/options/overlay scenes y preloads del Player/NpcBase.
- No modificar reglas de pausa, scoreboard, core bars, selección de equipo, acciones ni DevMenu funcional.

### Bloque 6A — Armas, pickups y movimiento compartido

- Mover en operaciones separadas y reversibles: Weapon; después Pickup/PickupManager/WeaponPickup/ResupplyBox; después VaultController.
- Actualizar escenas, autoload, preloads, Player, NpcBase y `MovementSystem` en cada subbloque.
- No fusionar `DroppedWeapon` ni modificar daño, recarga, física o pickup.

### Bloque 6B — Player de alto riesgo

- Ejecutar solo tras una aprobación explícita que confirme el movimiento de `player.gd`.
- Movimiento de ruta únicamente, con actualización de `player.tscn`, cinco mapas, HUD, selector, MatchManager, weapon/pickup y grupos conservados.
- No tocar mecánicas de input, cámara, vault, daño, armas, pickup, equipo, respawn o networking.

### Bloque 7 — Limpieza aprobada y optimizaciones confirmadas

- Cada eliminación requiere aprobación explícita por archivo y evidencia documentada.
- Una optimización por commit/bloque, con baseline y comparación antes/después.
- Candidatos iniciales de menor alcance: limitar logs de desarrollo y eliminar guardado duplicado de mouse, después de pruebas específicas.

## 9. Plan de rollback por bloque

| Bloque | Unidad de rollback | Acción de rollback |
|---|---|---|
| 0 | Ningún archivo | No aplica. Conservar capturas/logs como baseline. |
| 1 | Commit exclusivo de herramientas/wrapper | Revertir commit; restaurar rutas de herramienta/documentación. No tocar scripts de navegación canónicos. |
| 2 | Commit exclusivo FreezeCube | Revertir rutas/escenas/scripts del bloque de forma completa. No revertir parcialmente controladores y cubos. |
| 3 | Commit exclusivo de caracterización o cambios legacy aprobados | Revertir el bloque íntegro; restaurar escenas legacy junto a su script si se hubieran movido. |
| 4 | Commit de autoloads/shared-core | Revertir simultáneamente `project.godot`, scripts y referencias de consumidores. Reabrir editor para reindexar autoloads. |
| 5 | Commit UI/debug | Revertir escenas UI, preloads y scripts juntos; verificar MainMenu/HUD. |
| 6A | Un commit por subdominio: weapon, pickups, vault | Revertir el subdominio completo con sus escenas/preloads/autoload. |
| 6B | Commit exclusivo Player | Revertir Player, escena y cinco mapas en una sola operación. |
| 7 | Un commit por eliminación/optimización | Revertir exclusivamente el commit del archivo o optimización aprobada; no mezclar con organización. |

**Regla:** no se hará rollback manual parcial de rutas. Las rutas de scripts, escenas, autoloads, `load()`/`preload()`, UIDs y recursos deben volver de forma coherente.

## 10. Checklist de regresión por bloque

### Común a todo bloque que modifique rutas

- [ ] El proyecto abre sin parse errors, recursos faltantes ni rutas antiguas rotas.
- [ ] Los autoloads continúan cargando con sus nombres públicos: ConfigManager, GameState, InputManager, PickupManager, TeamAI, MapManager y MatchManager.
- [ ] Se verifica búsqueda de la ruta antigua y de la ruta nueva en `.gd`, `.tscn`, `.tres`, `.res` y `project.godot`.
- [ ] No aparece spam de consola nuevo.
- [ ] Se actualiza `CHANGELOG_REFACTOR.md` con archivos, pruebas, resultado y rollback.

### Bloque 1 — herramientas

- [ ] `check_nav` termina correctamente si se ejecuta de forma manual.
- [ ] El test anti-stuck refleja `MovementSystem.STUCK_PROGRESS_THRESHOLD` y no toca runtime.
- [ ] Verificación de mayúsculas/minúsculas para el wrapper role jump, si se modifica.

### Bloque 2 — FreezeCube

- [ ] `map_3` y `Mapa_de_guerra`: cubo base congela y descongela.
- [ ] Cubo de rol respeta ASSAULT/FLANKER, destino semántico, arco y retorno a roaming.
- [ ] Cubo amarillo encuentra YellowCube, mantiene arco/duración y descongela.
- [ ] Cubos verde/amarillo, capas, grupos, cooldowns y señales se preservan.

### Bloque 3 — IA/legacy

- [ ] `npc.tscn` mantiene AreaVision, RaycastVision, NavigationAgent y FSM activa.
- [ ] Spawn de bots, navegación, percepción, combate, roles y respawn se prueban en un mapa de combate.
- [ ] Las escenas legacy se prueban separadamente si se tocan; no se usan como spawn activo sin reparar sus nodos.
- [ ] Wrappers siguen resolviendo las clases canónicas.

### Bloque 4 — estado/configuración

- [ ] Menú principal, selección de mapa y máximo de jugadores.
- [ ] InputMap y rebinding persisten en `user://`.
- [ ] Sensibilidad/invert Y persisten tras reiniciar escena.
- [ ] Cores, equipos, CoreAttack, resultado y retorno a menú preservados.
- [ ] Carga de `skill.json` y equipamiento Player/NPC.

### Bloque 5 — UI/debug

- [ ] MainMenu, OptionsMenu y HUD se abren/cierra correctamente.
- [ ] Pausa, muerte/respawn, scoreboard, core bars, auto-balance y prompt de arma.
- [ ] DevMenu: acción Q, spawn manual, selección arma/equipo, invisibilidad y toggles.
- [ ] Overlay de Player y bots OFF/ON sin duplicados ni error de clase global.

### Bloque 6A — gameplay compartido

- [ ] Armas: hitscan, perdigones, proyectiles, melee, recarga, HUD y daño.
- [ ] Drops, WeaponPickup, confirmación E, NPC pickup, despawn y PickupManager.
- [ ] ResupplyBox: recarga, cooldown, luz/material y reutilización.
- [ ] Vault Player y bots: escalón, rampa, obstáculo vaultable, colisiones y HUD indicator.

### Bloque 6B — Player

- [ ] Input/movimiento/cámara/crouch/jump sin diferencia observable.
- [ ] Vault, disparo, daño, muerte, respawn, equipos y pickups.
- [ ] Prueba al menos en un mapa con combate y respawn; revisar las cinco escenas de mapa por la ruta Player.

### Bloque 7 — limpieza/optimización

- [ ] Prueba concreta antes/después del archivo eliminado u optimización.
- [ ] Métricas comparables: escenario, conteo de bots, duración, configuración y p95/p99.
- [ ] Evidencia de ausencia de referencias incluidas en changelog para cada borrado.
- [ ] Prueba completa de mapa con combate/respawn y, si afecta match, CoreAttack.

## 11. Hallazgos de seguridad y decisiones de Fase 3A

1. **No se detectó un parse error actual** en el estado reciente del editor; el único estado runtime fue «Sesión de depuración cerrada». El warning histórico de BotDebugOverlay se tratará como una comprobación de caché/clase al mover su escena, no como permiso para quitar `class_name`.
2. El log reciente sí confirma spam repetido de navegación/cooldown. Se documenta como evidencia para una futura optimización de logging, no como cambio aplicado.
3. `Scripts/role_jump_controller.gd` conserva una referencia `res://scripts/...` en minúsculas; es evidencia directa de riesgo case-sensitive, pero no tiene consumidor activo confirmado. Su corrección queda condicionada al preflight de portabilidad.
4. `npc_base.tscn` carece de `AreaVision` y `RaycastVision`, mientras `npc.tscn` sí los posee. Las tres escenas NPC heredadas se mantienen fuera de movimientos/eliminaciones automáticas.
5. `DroppedWeapon` no es el drop activo; el flujo canónico usa `WeaponPickup`. No se fusionan ni se borran en Fase 3A.
6. `IaSkill`, `EnemyPistolero` y `test_stuck_detection` tienen contratos desalineados con la arquitectura actual. Se clasifican como legacy/test no confiable hasta una prueba específica.
7. `Player`, Weapon, Vault y pickups se mantienen fuera de MP por ser compartidos. El movimiento de Player necesita aprobación específica en Fase 3B.

## Resultado de Fase 3A

- Inventario de las 31 rutas solicitadas completado.
- Rutas canónicas MP verificadas como ya consolidadas; no se crearán duplicados MP/Shared.
- Estructura shared mínima propuesta, sin crearla todavía.
- Se preservan wrappers, scripts legacy, variantes FreezeCube y escenas heredadas.
- No se aplicó ningún cambio funcional, de rutas, autoload, escena, recurso, input, física, IA, UI, combate, pickup ni red.
- El siguiente paso permitido es recibir exactamente: **`APROBADO FASE 3B`**.
