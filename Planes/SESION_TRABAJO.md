# SESIÓN DE TRABAJO: Ingeniería Inversa UT99 + Análisis de 17 Archivos Fuente

## Objetivo Principal
Hacer ingeniería inversa completa de la IA de Unreal Tournament 1999 basándose en el documento `res://config/ARQUITECTURA_IA_UT99_GODOT4.md`.
NO escribir código. NO diseñar arquitectura nueva. Solo descubrir cómo funciona UT99.

## Tareas Completadas

### 1. Lectura del Documento Fuente
- [x] Leer `res://config/ARQUITECTURA_IA_UT99_GODOT4.md` completo (1417 líneas)
- [x] Identificar todas las referencias a UT99 (Bot, Pawn, NavigationPoint, etc.)
- [x] Auditar código actual del proyecto (npc_base.gd, bot_brain.gd, behaviors, etc.)

### 2. Creación de `UT99_AI_REVERSE_ENGINEERING.md`
- [x] **SECCIÓN 1**: Análisis sistema por sistema (15 sistemas documentados)
  - Pawn, Bot, NavigationPoint, ReachSpec, AmbushPoint, DefensePoint, AlternatePath
  - LiftCenter/LiftExit, Inventory, Weapon, Skill, GameInfo, TeamAI, Orders
  - Cada uno con 22 preguntas respondidas
- [x] **SECCIÓN 2**: Matriz completa de dependencias
  - 6 relaciones principales + relaciones internas + 7 manejadores de eventos
- [x] **SECCIÓN 3**: Flujo completo de un frame (Tick del bot)
  - 6 fases: Entrada → Sensores → Decisión → Ejecución de Estado → Física → Post-movimiento
  - Todos los estados: ROAMING, TACTICAL_MOVE, CHARGING, RANGED_ATTACK, HUNTING, STAKEOUT, RETREATING, WANDERING, HOLDING
- [x] **SECCIÓN 4**: Flujos de casos específicos (17 casos)
  - Patrullando, ve enemigo, combate, pierde visión, escucha ruido, recibe daño
  - Se retira, busca vida, recoge arma, cambia arma, usa ascensor
  - Captura bandera, defiende bandera, sigue líder, recibe orden, muere, respawnea
- [x] **SECCIÓN 5**: Documento de responsabilidades (18 preguntas respondidas)
  - Quién decide, mueve, dispara, apunta, calcula rutas, busca enemigos, etc.
- [x] **SECCIÓN 6**: Algoritmos documentados (4 algoritmos completos)
  - WhatToDoNext, ChooseAttackMode, AssessThreat, AdjustSkill
- [x] **APÉNDICE A**: Tabla completa de eventos de UT99 (9 eventos)
- [x] **APÉNDICE B**: Comparación conceptos UT99 vs Godot (19 equivalencias)

## Archivos Clave
- `res://config/ARQUITECTURA_IA_UT99_GODOT4.md` — Fuente principal de información
- `res://config/SESION_TRABAJO.md` — Este archivo de recuperación
- `res://config/UT99_AI_REVERSE_ENGINEERING.md` — Documento de salida (COMPLETADO ✓)
  - 1654 líneas, 6 secciones + 2 apéndices
  - Cubre todos los sistemas, dependencias, flujos, casos, responsabilidades y algoritmos de UT99

---

## Sesión 2: Análisis Directo de Código Fuente UT99 (30-Jun-2026)

### Resumen
Se analizaron directamente los 17 archivos de código fuente de UT99 en `res://config/Prioridad/` para extraer conocimiento puro, sin traducir ni adaptar. El objetivo era entender la arquitectura original antes de diseñar nada para Godot.

### Archivos Analizados

| Archivo | Líneas | Rol |
|---------|--------|-----|
| Bot.txt | 7587 | Núcleo de la IA: FSM completa con 12 estados |
| Pawn.txt | 2001 | Clase base de todo ser controlable |
| Assault.txt | 1132 | GameMode Asalto con lógica de fortalezas |
| Inventory.txt | 859 | Sistema de inventario con `BotDesireability()` |
| ChallengeBotInfo.txt | 836 | Perfiles de bots y dificultad dinámica |
| CTFGame.txt | 767 | GameMode Captura la Bandera con lógica de IA |
| Domination.txt | 559 | GameMode Dominación con puntos de control |
| TournamentWeapon.txt | 708 | Armas con `RefireRate`, `RateSelf()`, `FireAdjust` |
| NavigationPoint.txt | 154 | Nodo base de navegación con grafos de ReachSpec |
| AmbientLight.uc | — | — |
| DefensePoint.txt | 16 | Punto de defensa (hereda de AmbushPoint) |
| Ambushpoint.txt | 29 | Punto de emboscada con `lookdir`, `SightRadius`, `bSniping` |
| AlternatePath.txt | 16 | Ruta alternativa por equipo |
| LiftCenter.txt | 128 | Centro de ascensor con `SpecialHandling()` |
| LiftExit.txt | 56 | Salida de ascensor |
| PathNode.txt | 12 | Nodo de ruta simple |
| Pickup.txt | 169 | Objetos recogibles |

### Hallazgos Clave

#### Sistema de Navegación (NavigationPoint + ReachSpec)
- Grafo de nodos con `Paths[16]` (índices de ReachSpec, manejado por C++ nativo)
- `upstreamPaths[16]` para caminos inversos
- `VisNoReachPaths[16]`: caminos visibles pero no accesibles directamente
- `cost` y `ExtraCost` para pesos dinámicos
- `SpecialCost()`: función de evento para costos contextuales
- `bOneWayPath`, `bPlayerOnly`, `bNeverUseStrafing`: flags de restricción
- `bSpecialCost`: si true, navigation code llama a SpecialCost()

#### Jerarquía de Navegación Táctica
```
NavigationPoint (base)
├── PathNode (nodo simple)
├── AmbushPoint (emboscada con lookdir, SightRadius, bSniping)
│   └── DefensePoint (herencia directa, team + priority + FortTag)
├── LiftCenter (ascensor con SpecialHandling y trigger)
├── LiftExit (salida de ascensor)
└── AlternatePath (rutas alternativas por equipo)
```

#### Arquitectura de la FSM (Bot.txt)
- Estados como etiquetas `state Nombre { ... }` en UnrealScript
- **12 estados** distintos: StartUp, Holding, Hold, Roaming, Wandering, Acquisition, Attacking, Retreating, Fallback, Charging, TacticalMove, Hunting, StakeOut, RangedAttack, FallingState, TakeHit
- Cada estado maneja TODOS los eventos: `SeePlayer`, `HearNoise`, `TakeDamage`, `HitWall`, `Timer`, `Bump`, `EnemyNotVisible`, `EnemyAcquired`, `AnimEnd`, `Landed`, `SetFall`
- No hay FSM engine separado — cada estado es un bloque con labels (`Begin:`, `Moving:`, `SpecialNavig:`, `AdjustFromWall:`)
- Movimiento latente: funciones nativas `MoveToward()`, `MoveTo()`, `StrafeFacing()` que pausan el script hasta completar

#### Sistema de Órdenes
- `Orders`: orden actual (FreeLance, Attack, Defend, Follow, Hold, Point)
- `RealOrders`: orden persistente original (separación crucial, replicada a clientes via `BotReplicationInfo`)
- `OrderObject`: a quién/apuntar la orden
- `SetOrders(NewOrders, OrderGiver)`: función central que reconfigura el bot
- `bLeading`: true si es líder (otros bots le siguen)
- `SupportingPlayer`: a qué jugador está apoyando

#### Algoritmos de Decisión

**ChooseAttackMode()**: 
  - Evalúa si enemigo existe y está vivo
  - Llama `FindSpecialAttractionFor()` (modo de juego específico)
  - Actitud FEAR → Retreating
  - Actitud FRIENDLY → WhatToDoNext
  - Sin línea de visión → Hunting o StakeOut
  - Con línea de visión → TacticalMove

**AssessThreat(Pawn NewThreat)**:
  - `RelativeStrength(NewThreat)` como base (compara salud, armas, skill)
  - Bonos: +0.3 si < 20 health (desesperado), +0.3 si < 800 unidades
  - Penalizaciones: -0.25 si no es enemigo actual, -0.2 general
  - +0.2 si no hay LOS a enemigo actual y amenaza está cerca
  - +5 si `SpecialPause > 0` (DISPARO INMINENTE)
  - +/- por PlayerPawn y team game
  - + `GameThreatAdd()` del GameMode

**WhatToDoNext()**: 
  - Resetea estado: detiene disparo, limpia `bDevious`, `bKamikaze`
  - Restaura `RealOrders` vía `SetOrders(RealOrders, OrderGiver, true)`
  - Recupera `OldEnemy` como nuevo enemigo
  - Si hay enemigo → Attacking
  - Si Orders = 'Hold' + buena arma + salud > 70 → Hold
  - Si no → Roaming

**SwitchToBestWeapon()**:
  - Recorre cadena de inventario llamando `RecommendWeapon(rating, usealt)`
  - Compara con FavoriteWeapon (con bonus +0.22)
  - Retorna si debe usar modo alterno

**Skill Dinámico**:
  - `InitializeSkill(Difficulty + BotSkills[n])` ajusta skill base
  - `bNovice` si skill < 4 (comportamiento más simple)
  - `AdjustSkill(bWinner)`: sube/baja según rendimiento vs jugador
  - Factor de ajuste: `2/min(partidas_jugadas, 10)`

#### Sistema de Perfiles (ChallengeBotInfo)
- 32 slots de bots con: nombre, equipo, skill, accuracy, combat style, alertness, camping, strafing, arma favorita, voz, skin
- `CHIndividualize()` aplica el perfil completo al bot
- `AdjustSkill()` modifica dificultad dinámicamente
- `ChooseBotInfo()` selecciona slot disponible (orden aleatorio o secuencial)

### Decisiones para la Nueva IA en Godot
1. **NO** copiar el sistema de estados como labels de UnrealScript (obsoleto)
2. **NO** copiar las funciones latentes de movimiento (obsoleto, Godot usa _process)
3. **SÍ** mantener la separación RealOrders vs Orders (excelente para 2026)
4. **SÍ** mantener el sistema de perfiles de bot (ChallengeBotInfo → BotProfile Resource)
5. **SÍ** mantener la jerarquía NavigationPoint táctico (excelente, no existe en Godot)
6. **SÍ** mantener el algoritmo AssessThreat con pesos relativos
7. **SÍ** mantener SetOrders con OrderGiver y OrderObject
8. **SÍ** mantener GameThreatAdd para personalización por GameMode
9. **SÍ** mantener FindSpecialAttractionFor (patrón Strategy en GameMode)
10. **SÍ** mantener la separación de modos de juego (CTFGame, Domination, Assault)

## Notas para Retomar
- El documento fuente contiene TODO lo que se sabe de UT99
- Cada sistema de UT99 está descrito con sus variables, métodos y eventos
- Las tablas de comparación (Parte 12) son clave para entender equivalencias
- NO hay que inventar nada — solo extraer lo que el documento ya dice
- El error fue "upstream_failed" al intentar generar el .md grande
- Intentar generar el archivo en partes si es necesario
