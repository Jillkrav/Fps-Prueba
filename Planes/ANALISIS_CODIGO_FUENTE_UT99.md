# ANÁLISIS DE CÓDIGO FUENTE: UNREAL TOURNAMENT 1999 — IA COMPLETA

> Documento generado a partir de la lectura DIRECTA de 17 archivos fuente de UT99.
> Propósito: Extraer CONOCIMIENTO PURO — no traducir código, no adaptar funciones.
> Fecha: 2026-06-30
> Fuentes: `res://config/Prioridad/*.txt`

---

## ÍNDICE DE ARCHIVOS ANALIZADOS

1. [NavigationPoint.txt](#1-navigationpointtxt) — Navegación base + ReachSpec
2. [PathNode.txt](#2-pathnodetxt) — Nodo simple
3. [Ambushpoint.txt](#3-ambushpointtxt) — Punto de emboscada
4. [DefensePoint.txt](#4-defensepointtxt) — Punto de defensa
5. [AlternatePath.txt](#5-alternatepathtxt) — Ruta alternativa
6. [LiftCenter.txt](#6-liftcentertxt) — Centro de ascensor
7. [LiftExit.txt](#7-liftexittxt) — Salida de ascensor
8. [Pawn.txt](#8-pawntxt) — Clase base de toda entidad
9. [Bot.txt](#9-bottxt) — Núcleo de la IA (FSM completa)
10. [Inventory.txt](#10-inventorytxt) — Sistema de inventario
11. [Pickup.txt](#11-pickuptxt) — Objetos recogibles
12. [TournamentWeapon.txt](#12-tournamentweapontxt) — Armas
13. [ChallengeBotInfo.txt](#13-challengebotinfotxt) — Perfiles de bots
14. [BotReplicationInfo.txt](#14-botreplicationinfotxt) — Replicación de estado
15. [CTFGame.txt](#15-ctfgametxt) — GameMode: Captura la Bandera
16. [Domination.txt](#16-dominationtxt) — GameMode: Dominación
17. [Assault.txt](#17-assaulttxt) — GameMode: Asalto

---

## 1. NavigationPoint.txt

### ¿Qué responsabilidad tiene?
Es la clase base de **todo el sistema de navegación**. Define un nodo en el grafo de navegación del mapa. No es solo un punto geométrico — contiene un array de conexiones (ReachSpecs) que forman el grafo de rutas. Su contraparte C++ nativa maneja el pathfinding real.

### ¿Qué problema resuelve?
Resuelve la pregunta fundamental de navegación en un mapa 3D: "¿cómo llego del punto A al punto B?". Proporciona la estructura de datos (nodos + arcos) sobre la que el motor C++ ejecuta búsqueda de caminos. También permite pesos dinámicos por nodo.

### ¿Cómo se comunica con otros sistemas?
- **Con el motor C++**: a través de arrays nativos `Paths[16]` y `upstreamPaths[16]` que contienen índices de ReachSpecs (estructuras de datos internas del motor)
- **Con Pawn/Bot**: vía función `SpecialCost(Pawn Seeker)` — el Pawn solicita un costo modificado para este nodo, y el NavigationPoint puede alterar el costo según contexto
- **Con el nivel**: `AllActors` iterator para encontrar conectividad
- **Con otros NavigationPoints**: lista enlazada global `nextNavigationPoint` para recorrer todo el grafo

### ¿Qué algoritmos utiliza?
- **Búsqueda de caminos en grafo** (implementada en C++ nativo): usa ReachSpecs (arcos) conectando NavigationPoints (nodos)
- **Cálculo de costo**: `cost` + `ExtraCost` se suman al peso base; si `bSpecialCost == true`, llama a `SpecialCost(Pawn Seeker)` para costo contextual
- **Prunning**: `PrunedPaths[16]` permite podar caminos (rutas inválidas temporalmente)
- **Visibilidad vs Accesibilidad**: `VisNoReachPaths[16]` — nodos que se ven pero no son alcanzables (para hunting/búsqueda visual)

### ¿Qué ideas siguen siendo excelentes en 2026?
- **Costo dinámico por nodo** (`ExtraCost` y `SpecialCost`): permite que el pathfinding evite zonas peligrosas o prefiera rutas seguras
- **Separación visibilidad/accesibilidad** (`VisNoReachPaths`): el bot sabe que ve un punto pero no puede llegar — crucial para hunting
- **Navegación direccional** (`bOneWayPath`): caminos de un solo sentido (útil en mapas tácticos con caídas)
- **Costos por contexto** (`SpecialCost` callback): el Pawn puede modificar el costo según su estado (herido, con bandera, etc.)

### ¿Qué ideas están obsoletas?
- **Arrays fijos de 16 slots** (`Paths[16]`, `upstreamPaths[16]`, etc.): límite artificial que no escala
- **Lista enlazada global** (`nextNavigationPoint`): frágil, difícil de depurar, no escalable
- **Pathfinding implementado en C++ nativo hardcodeado**: en Godot el NavigationServer es extensible y configurable
- **`bEndPointOnly`**: concepto extraño — nodos que solo son destino, nunca origen

### ¿Qué ideas vale la pena implementar en Godot?
- **Sistema de pesos contextuales**: sobreescribir el costo de NavigationRegion3D links basado en estado del bot
- **Separación visibilidad vs accesibilidad**: para que los bots puedan "saber dónde buscar" aunque no tengan ruta directa
- **Nodos de navegación táctica con costos modificables**: como NavigationLinks con costo dinámico
- **Flags de restricción por equipo/clase**: `bPlayerOnly`, `bOneWayPath` → traducción a capas de navegación

---

## 2. PathNode.txt

### ¿Qué responsabilidad tiene?
Es la subclase más simple de NavigationPoint. Representa un nodo de ruta genérico sin comportamiento adicional. Solo hereda y establece valores por defecto (textura y volumen de sonido).

### ¿Qué problema resuelve？
Provee un nodo de navegación básico para usar en mapas cuando no se necesita comportamiento táctico. Es el "nodo default" que el sistema PATH BUILD coloca automáticamente.

### ¿Cómo se comunica con otros sistemas?
Hereda toda la comunicación de NavigationPoint. No añade ninguna interfaz nueva. Se usa como nodo genérico en el grafo.

### ¿Qué algoritmos utiliza?
Ninguno propio. Usa los de NavigationPoint + ReachSpec (C++ nativo).

### ¿Qué ideas siguen siendo excelentes en 2026?
La idea de tener un tipo de nodo "simple" vs nodos "tácticos" es buena — permite sistemas de pathfinding que entienden contexto sin necesidad de que todo sea especial.

### ¿Qué ideas están obsoletas?
PathNode como clase separada no aporta nada — un enum `NavigationPointType.PATH` sería suficiente.

### ¿Qué ideas vale la pena implementar en Godot?
La diferenciación entre nodos de navegación simples y nodos con comportamiento táctico. En Godot, NavigationPolygonInstance ya provee navegación básica; los SemanticPoints serían el equivalente de Ambush/Defense/Alternate.

---

## 3. Ambushpoint.txt

### ¿Qué responsabilidad tiene?
Define un punto táctico donde un bot puede apostarse para emboscar. Es un NavigationPoint especializado que dice: "párate aquí, mira hacia allá, y espera".

### ¿Qué problema resuelve？
Evita que los bots se posicionen aleatoriamente. Les da **posiciones tácticas inteligentes** donde tienen ventaja: cobertura, campo de visión hacia zonas de paso, y dirección de mirada predefinida.

### ¿Cómo se comunica con otros sistemas?
- **Con Bot**: el bot almacena `AmbushSpot` — una referencia al AmbushPoint que está usando. El bot lee `lookdir` para saber hacia dónde mirar, y `SightRadius` para saber su alcance visual
- **Con el sistema de patrol/camping**: usado en estado Roaming cuando `bCamping == true` y `bWantsToCamp == true`
- **Con DefensePoint (subclase)**: DefensePoint hereda y añade `team` y `priority`

### ¿Qué algoritmos utiliza?
No tiene algoritmos propios. Es puramente una estructura de datos. Su lógica de uso está en Bot.Roaming.PickDestination() que decide si tomarlo.

### ¿Qué ideas siguen siendo excelentes en 2026?
- **`bSniping`**: flag que hace que los bots usen armas de francotirador desde esta posición
- **`lookdir`**: la dirección de mirada precalculada permite que el bot mire exactamente al punto de interés (puerta, corredor) sin necesidad de calcularlo cada frame
- **`SightRadius` por punto**: diferentes puntos tienen diferentes alcances visuales (una torre ve lejos, una esquina ve cerca)

### ¿Qué ideas están obsoletas?
- **`survivecount`**: usado para persistencia de selección entre rondas; en 2026 se manejaría con un sistema de datos persistente

### ¿Qué ideas vale la pena implementar en Godot?
- **Puntos tácticos direccionales**: un punto + dirección de mirada + radio de visión es una herramienta de diseño de niveles extremadamente poderosa
- **Per-ambush sight radius**: permite diseñar zonas de visión específicas
- **`bSniping` como flag de nodo**: detectar automáticamente si un punto permite francotirador

---

## 4. DefensePoint.txt

### ¿Qué responsabilidad tiene?
Define un punto de defensa para juegos por equipos. Hereda de AmbushPoint y añade asignación por equipo y prioridad.

### ¿Qué problema resuelve？
Resuelve "¿dónde debe posicionarse un defensor?". En CTF, Asalto o Dominación, los defensores necesitan posiciones específicas cerca de objetivos.

### ¿Cómo se comunica con otros sistemas?
- **Con Assault GameMode**: `FortTag` asocia el DefensePoint con una fortaleza específica en el modo Asalto. Cuando una fortaleza es destruida, los DefensePoints asociados se marcan como `taken = true`
- **Con Bot**: el sistema de órdenes `SetOrders('Defend')` asigna un DefensePoint via `OrderObject`

### ¿Qué algoritmos utiliza?
Ninguno propio. Los bots eligen DefensePoints basado en `priority` (mayor prioridad = más probable).

### ¿Qué ideas siguen siendo excelentes en 2026?
- **Prioridad dinámica**: cuando una fortaleza es atacada, su prioridad de defensa sube
- **Asociación a objetivos**: `FortTag` conecta puntos de defensa con objetivos del mapa

### ¿Qué ideas están obsoletas?
Ninguna en particular. DefensePoint es un diseño limpio y simple.

### ¿Qué ideas vale la pena implementar en Godot?
- **Puntos de defensa con prioridad y team**: sistema para que modos de juego asignen posiciones defensivas
- **Asociación defensa→objetivo**: un punto defiende algo específico en el mapa

---

## 5. AlternatePath.txt

### ¿Qué responsabilidad tiene?
Provee una ruta alternativa entre bases para juegos CTF. Un AlternatePath permite a bots atacantes llegar a la base enemiga por una ruta secundaria.

### ¿Qué problema resuelve？
Evita que los bots siempre tomen el mismo camino (predecible). En CTF, sin rutas alternativas, los defensores siempre saben por dónde vendrá el atacante.

### ¿Cómo se comunica con otros sistemas?
- **Con CTFGame**: `CTFGame.FindPathToBase()` verifica si el bot tiene un AlternatePath asignado y si puede alcanzarlo
- **Con Bot**: el bot almacena `AlternatePath` como referencia. `SelectionWeight` influye en si un bot lo usa
- **Por equipo**: `Team` determina qué equipo puede usar esta ruta. `bReturnOnly` limita a solo retorno

### ¿Qué algoritmos utiliza?
`CTFGame.FindPathToBase()`: si el bot tiene AlternatePath, intenta pathfinding hacia él; si no es alcanzable, cae a ruta normal.

### ¿Qué ideas siguen siendo excelentes en 2026?
- **Rutas alternativas por equipo**: concepto fundamental para diseño de niveles en juegos competitivos
- **`SelectionWeight`**: permite control probabilístico de qué ruta toma cada bot
- **`bReturnOnly`**: rutas que solo se usan al volver (con la bandera)

### ¿Qué ideas están obsoletas?
Ninguna. El concepto es atemporal.

### ¿Qué ideas vale la pena implementar en Godot?
- **Rutas preferenciales por equipo**: NavigationLinks con tags de equipo
- **Pesos de selección probabilística**: para distribuir bots en diferentes rutas
- **Sistema de rutas de retorno**: caminos especiales para cuando llevas un objetivo (bandera, paquete)

---

## 6. LiftCenter.txt

### ¿Qué responsabilidad tiene?
Maneja la interacción entre bots y ascensores (plataformas móviles). Un LiftCenter se coloca sobre la plataforma y el bot lo usa como destino de navegación para subirse.

### ¿Qué problema resuelve？
Los ascensores en UT99 son Mover (plataformas animadas). Los bots necesitan saber: (1) pararse sobre la plataforma, (2) activar el trigger para subir, (3) salir en el punto correcto arriba. Sin esto, los bots ignorarían ascensores.

### ¿Cómo se comunica con otros sistemas?
- **Con Mover (ascensor)**: `MyLift` referencia al Mover. `SetBase(MyLift)` hace que el nodo siga al ascensor. `HandleDoor(Other)` activa el ascensor
- **Con LiftExit**: El LiftCenter llama a `LiftExit.SpecialHandling()` para coordinar entrada/salida
- **Con Trigger**: `RecommendedTrigger` — dice al bot qué trigger presionar para llamar al ascensor
- **Con Bot**: vía `SpecialHandling(Pawn Other)` — función llamada por el sistema de navegación cuando el bot está cerca. Retorna el siguiente destino para el bot
- **Con otros LiftCenters**: `LiftOffset` mantiene la posición relativa al Mover

### ¿Qué algoritmos utiliza?
**`SpecialHandling(Pawn Other)`**: el algoritmo más complejo de navegación táctica en UT99:
1. Si el bot YA está sobre el ascensor → devuelve `RecommendedTrigger` o `self` (sigue en él)
2. Si el bot está cerca de LiftExit y quiere subir → activa trigger desde arriba
3. Calcula distancia 2D y diferencia de altura: si el bot está en posición de subirse, devuelve `self` (el bot viene hacia aquí)
4. Si no puede alcanzar, llama `MyLift.HandleDoor(Other)` para activar el ascensor
5. Maneja `BumpType` — si el ascensor es `BT_PlayerBump`, solo jugadores humanos pueden activarlo

### ¿Qué ideas siguen siendo excelentes en 2026?
- **`SpecialHandling()` como hook de navegación**: los nodos de navegación pueden interceptar la ruta y modificarla. Es un patrón Visitor/Strategy que permite comportamiento complejo sin acoplar código al bot
- **Coordinación LiftCenter + LiftExit**: entrada y salida como puntos separados pero conectados
- **Trigger recomendado**: el ascensor sabe qué botón presionar
- **LiftOffset**: mantiene posición relativa al Mover, permitiendo que el nodo se mueva con la plataforma

### ¿Qué ideas están obsoletas?
- **`BumpType` check manual**: en Godot, los Area3D pueden detectar quién entra sin necesidad de flags
- **Advertencia hardcodeada sobre `BumpOpenTimed`**: el diseño del ascensor está acoplado al estado inicial del Mover

### ¿Qué ideas vale la pena implementar en Godot?
- **Sistema de plataformas móviles para IA**: NavigationLinks + Area3D que los bots entienden como "subir/bajar"
- **`SpecialHandling` pattern**: nodos de navegación que pueden interceptar rutas de bots para comportamiento contextual
- **Punto de activación**: decirle al bot exactamente dónde pararse para activar algo

---

## 7. LiftExit.txt

### ¿Qué responsabilidad tiene?
Define dónde sale un bot después de usar un ascensor. Complemento de LiftCenter. Sin LiftExit, el bot subiría pero no sabría por dónde salir.

### ¿Qué problema resuelve？
El bot necesita saber: "cuando el ascensor llegue arriba, ¿hacia dónde voy?". LiftExit es el destino post-ascensor. También maneja el trigger para llamar al ascensor desde arriba.

### ¿Cómo se comunica con otros sistemas?
- **Con LiftCenter**: coordinación via `LiftTag` (mismo tag = mismo ascensor)
- **Con Mover**: `HandleDoor(Other)` activa el ascensor cuando el bot está arriba
- **Con Bot**: `SpecialHandling()` verifica si el bot está sobre el ascensor y lo redirige al LiftCenter
- **Con Trigger**: `RecommendedTrigger` (desde arriba)

### ¿Qué algoritmos utiliza?
**`SpecialHandling(Pawn Other)`** (más simple que LiftCenter):
1. Si el bot está sobre el ascensor (`Other.Base == MyLift`) y puede ver el LiftExit → lo redirige aquí (self)
2. Si no → establece `SpecialGoal = MyLift.myMarker` (el LiftCenter) para que el bot espere en el ascensor

### ¿Qué ideas siguen siendo excelentes en 2026?
- La misma `SpecialHandling()` pattern que LiftCenter
- La coordinación bidireccional LiftCenter↔LiftExit

### ¿Qué ideas están obsoletas?
Ninguna.

### ¿Qué ideas vale la pena implementar en Godot?
Sistema de navegación vertical con puntos de entrada/salida enlazados.

---

## 8. Pawn.txt

### ¿Qué responsabilidad tiene?
Es la clase base de TODO actor controlable por IA o jugador. Proporciona: movimiento (nativo), línea de visión, detección de sonido, inventario, salud, animación, replicación de red. TODO ser vivo en UT99 es un Pawn.

### ¿Qué problema resuelve？
Provee la capa fundamental para cualquier entidad interactiva: físico, sensorial, inventario y comunicación. Sin Pawn no hay juego.

### ¿Cómo se comunica con otros sistemas?
- **Con el motor**: funciones nativas para movimiento (`MoveTo`, `MoveToward`, `StrafeFacing`), línea de visión (`LineOfSightTo`, `CanSee`), pathfinding (`FindPathTo`, `FindPathToward`)
- **Con Bot**: Bot hereda de Pawn y añade la FSM. Bot llama funciones de Pawn constantemente
- **Con GameInfo**: `TakeDamage()`, `Died()`, `Killed()` activan reglas del modo de juego
- **Con Inventory**: cadena enlazada de inventory items; `Weapon`, `PendingWeapon`, `SelectedItem`
- **Con NavigationPoint**: `FindPathTo()`, `FindPathToward()`, `actorReachable()`, `pointReachable()`
- **Con otros Pawns**: `nextPawn` lista global; comunicación por voz (`SendVoiceMessage`)
- **Con sonido**: `noise1spot`, `noise1time`, `noise1loudness` — el motor escribe estos cuando el Pawn hace ruido

### ¿Qué algoritmos utiliza?
- **Movimiento**: funciones nativas latentes (`MoveToward`, `StrafeFacing`) que pausan el script hasta completar. Usan `MoveTarget`, `Destination`, `Focus` como variables de control
- **Línea de visión**: `LineOfSightTo()` (nativa) traza rayos a múltiples puntos del objetivo (origen, cabeza, pies)
- **Campo visual**: `CanSee()` = LineOfSightTo + `PeripheralVision`
- **Detección de ruido**: manejada por el motor, escribe `noise1spot/time/loudness`
- **Pathfinding**: `FindPathTo()` (nativa) busca camino en el grafo de NavigationPoints
- **Puntería**: `PickTarget()` (nativa) evalúa múltiples enemigos y retorna el mejor basado en aim y distancia
- **Evasión de paredes**: `PickWallAdjust()` (nativa) intenta navegar alrededor de obstáculos
- **Altura de salto automático**: `EAdjustJump()` (nativa)

### ¿Qué ideas siguen siendo excelentes en 2026?
- **Arquitectura de capas**: Pawn (capacidades físicas) → Bot (capacidades de IA). Separación limpia
- **Eventos sensoriales integrados**: `SeePlayer()`, `HearNoise()`, `TakeDamage()` son eventos que el Pawn recibe automáticamente del motor
- **`LastSeenPos` y `LastSeeingPos`**: auto-actualizados por el motor cuando el enemigo deja de ser visible. El bot sabe dónde vio al enemigo por última vez y desde dónde lo vio
- **Atributos de percepción por Pawn**: `SightRadius`, `PeripheralVision`, `HearingThreshold` — cada entidad tiene su propio perfil sensorial
- **`Enemy` como variable, no como comando**: el enemigo es estado, no instrucción. Clean ownership
- **`Intelligence` enum**: BRAINS_NONE, REPTILE, MAMMAL, HUMAN. Escala de capacidades cognitivas
- **`EAttitude` enum**: Fear, Hate, Frenzy, Threaten, Ignore, Friendly, Follow. Para relaciones entre entidades
- **Funciones de movimiento nativas latentes**: idea poderosa aunque obsoleta técnicamente (ver abajo)

### ¿Qué ideas están obsoletas?
- **Funciones latentes de movimiento**: pausan el script hasta completar el movimiento. En Godot no existe este modelo — todo es _process() con delta. Las funciones latentes son incompatibles con el modelo de frames de Godot
- **Variables sensoriales escritas por el motor** (`noise1*`): el motor escribe directamente en las variables del Pawn. En Godot, los sensores son sistemas separados
- **Lista enlazada global** (`nextPawn`): frágil, no type-safe, difícil de mantener
- **Variables booleanas masivas (flags)**: decenas de `b*` flags en lugar de estados/structs
- **Redundancia Pawn → Bot**: muchas variables en Pawn son solo relevantes para bots (como `Skill`, `Intelligence`)

### ¿Qué ideas vale la pena implementar en Godot?
- **Arquitectura base de entidad con capacidades**: CharacterBody3D (Pawn) + sistemas separados (Bot)
- **Sensores como eventos integrados**: señales `damage_taken`, `enemy_detected`, `noise_heard`
- **LastSeenPos/LastSeeingPos auto-actualizados**: el sistema de percepción debería mantener estas posiciones automáticamente
- **Atributos de percepción configurables**: SightRadius, PeripheralVision, HearingThreshold como recursos por entidad
- **Jerarquía de inteligencia**: enum de capacidades cognitivas (simple → complejo)
- **Sistema de actitudes hacia otros**: Fear, Hate, Ignore, Friendly → sistema de facciones/relaciones

---

## 9. Bot.txt

### ¿Qué responsabilidad tiene?
Es el cerebro de la IA. Una FSM enorme (7587 líneas) con ~20 estados que manejan TODO el comportamiento de un bot. Es la implementación concreta de la IA de UT99.

### ¿Qué problema resuelve？
Resuelve "¿qué hace el bot en cada momento?" — desde patrullar hasta combatir, pasando por emboscar, huir, usar ascensores, recoger objetos, seguir órdenes, y morir.

### ¿Cómo se comunica con otros sistemas?
- **Con Pawn**: hereda todas las capacidades físicas (movimiento, sensores, inventario)
- **Con GameInfo/GameMode**: llama funciones como `FindSpecialAttractionFor()`, recibe eventos como `Killed()`, consulta reglas
- **Con NavigationPoints**: usa PathFinding nativo de Pawn para navegar
- **Con Inventory**: recorre cadena de inventario para `SwitchToBestWeapon()`
- **Con BotReplicationInfo**: replica estado de órdenes a clientes
- **Con otros bots**: comunicación por voz (`SendTeamMessage`, `SendGlobalMessage`), mensajes de equipo (`BotVoiceMessage`)
- **Con ChallengeBotInfo**: recibe perfil de personalidad vía `CHIndividualize()`
- **Con Trigger/Mover**: interactúa con ascensores, puertas, triggers del mapa

### ¿Qué algoritmos utiliza?

#### FSM Completa (12 estados + sub-estados)

**Estados principales:**

| Estado | Propósito | Eventos que maneja |
|--------|-----------|-------------------|
| **StartUp** | Inicialización | BeginState → WhatToDoNext |
| **Roaming** (~650 lines) | Patrullaje por defecto | TakeDamage, EnemyAcquired, HitWall, Timer, HearPickup, SetOrders, PickDestination |
| **Wandering** | Deambular sin rumbo fijo | TakeDamage, EnemyAcquired, HitWall, SetOrders, PickDestination |
| **Holding** | Mantener posición fija | TakeDamage, Timer, EnemyAcquired, ShootTarget |
| **Acquisition** | Transición al detectar enemigo | TakeDamage, SeePlayer, HearNoise, WarnTarget |
| **Attacking** | Evaluar cómo atacar | ChooseAttackMode, EnemyNotVisible, Timer |
| **Charging** | Cargar contra el enemigo | TakeDamage, HitWall, Timer, EnemyNotVisible, MayFall |
| **TacticalMove** | Movimiento táctico en combate | TakeDamage, HitWall, Timer, EnemyNotVisible, FearThisSpot |
| **RangedAttack** | Disparar a distancia | TakeDamage, StopFiring, EnemyNotVisible, AnimEnd |
| **Hunting** | Buscar enemigo perdido | TakeDamage, HearNoise, SetEnemy, HitWall, CheckBumpAttack |
| **StakeOut** | Esperar en última posición conocida | TakeDamage, HearNoise, Timer, SetEnemy |
| **Retreating** | Huir | TakeDamage, SeePlayer, HearNoise, HitWall, PickDestination |
| **FallingState** | Caer/recuperarse de caída | Landed, TakeDamage, BaseChange, ZoneChange |
| **TakeHit** | Animación de recibir daño | Timer, Landed (transición inmediata a NextState) |

#### ChooseAttackMode() — Decisión central de combate
```
1. Si enemigo no existe o está muerto → WhatToDoNext()
2. Si no hay arma → SwitchToBestWeapon()
3. Llama FindSpecialAttractionFor() (modo de juego puede redirigir)
4. Si actitud = FEAR → Retreating
5. Si actitud = FRIENDLY → WhatToDoNext()
6. Si no hay línea de visión al enemigo:
   a. Verifica OldEnemy (cambiar si es más importante)
   b. Orders 'Hold' + 5s sin ver → StakeOut
   c. Si debe cazar (skill + distancia) → Hunting
   d. Sino → StakeOut
7. Si hay línea de visión + readyToAttack → TacticalMove
```

#### AssessThreat(Pawn NewThreat) — Evaluación de amenazas
```
threatValue = RelativeStrength(NewThreat)  // salud + arma + skill, normalizado 0-1+
if NewThreat.Health < 20:   threatValue += 0.3    // rematar herido
if distance < 800:          threatValue += 0.3    // cercano
if NewThreat != current_enemy:
	if dist > current_enemy_dist * 0.7:  threatValue -= 0.25
	else:                                  threatValue -= 0.2
if no LOS to current enemy AND NewThreat < 1200:  threatValue += 0.2
if SpecialPause > 0:        threatValue += 5.0   // DISPARO INMINENTE
if is Player:               threatValue += 0.15
if team_game:               threatValue += GameThreatAdd(bot, NewThreat)
return threatValue
```

#### RelativeStrength(Pawn Other) — Comparación de poder
Compara salud, weapon.AIRating y skill del bot vs el objetivo. No usa variables de entorno — solo stats del bot y del objetivo. Retorna un valor normalizado.

#### WhatToDoNext() — Qué hacer cuando no hay enemigo
```
1. Destruir si demasiados bots en el servidor
2. Reset: BlockedPath = None, bDevious = false, stop firing, bKamikaze = false
3. Restaurar RealOrders vía SetOrders(RealOrders, OrderGiver, true)
4. Enemy = OldEnemy (recuperar enemigo anterior), OldEnemy = None
5. Si Enemy existe → GotoState('Attacking')
6. Si Orders = 'Hold' AND buena arma AND salud > 70 → GotoState('Hold')
7. Sino → GotoState('Roaming')
```

#### SetOrders() — Sistema de órdenes (crucial)
```
1. Si NewOrders != RealOrders → interrumpe estado actual
2. Si NewOrders = 'Point' → se convierte en 'Attack' + SupportingPlayer
3. Si bSniping AND NewOrders != 'Defend' → bSniping = false
4. Actualiza Aggressiveness según el tipo de orden
5. Según el tipo de orden:
   - 'Hold' → Spawn HoldSpot, Aggressiveness++
   - 'Follow' → OrderObject = OrderGiver, Aggressiveness++
   - 'Defend' → OrderObject = SetDefenseFor(), CampingRate = 1.0
   - 'Attack' → bLeading si tiene seguidores
6. Replica: BotReplicationInfo.RealOrders = NewOrders
```

#### PickDestination() — Navegación autónoma (cada estado tiene la suya)
- Roaming.PickDestination: 400+ líneas que integran órdenes, atracción especial, inventario cercano, camping, hunting, pathfinding
- Hold.PickDestination: verifica HoldSpot, decide si está cerca (→Holding) o lejos (→Roaming)
- Retreating.PickDestination: busca inventario cercano o huye hacia base

### ¿Qué ideas siguen siendo excelentes en 2026?
- **Máquina de estados reactiva**: cada estado maneja TODOS los eventos relevantes. No hay un dispatcher central — el estado sabe qué hacer con cada estímulo
- **Transiciones por evento**: `EnemyAcquired()` (evento) → `GotoState('Acquisition')`. Las transiciones ocurren como respuesta a eventos, no por polling
- **Separación RealOrders/Orders**: el bot puede desviarse temporalmente de su orden pero siempre puede volver. Patrón invaluable para IA reactiva pero con propósito
- **`ChooseAttackMode()` como state machine embebida**: el estado Attacking no hace nada él mismo — solo decide a qué sub-estado ir basado en contexto
- **Sistema de líderes y seguidores**: `bLeading`, `SupportingPlayer` — IA de equipo sin hardcode
- **Alertness modificando percepción**: `SetAlertness()` altera PeripheralVision y HearingThreshold dinámicamente
- **Evaluación de amenazas con pesos**: AssessThreat no es un simple check — considera salud, distancia, cambio vs actual, tipo de juego, special moves
- **`FindSpecialAttractionFor()` como hook de GameMode**: el modo de juego puede inyectar comportamiento al bot sin modificar Bot. Patrón Strategy implícito

### ¿Qué ideas están obsoletas?
- **7587 líneas en un solo archivo**: monstruoso, imposible de mantener. En Godot serían ~20+ archivos
- **Estados como etiquetas en lugar de objetos**: `state Roaming { ... }` en UnrealScript es un bloque dentro de la clase, no un objeto independiente. En Godot cada estado debe ser su propio script
- **Variables booleanas como flags de estado**: `bCanFire`, `bStrafeDir`, `bChangeDir`, `bFiringPaused`, etc. Docenas de flags sin estructura
- **Variables de comunicación temporal**: `NextState` y `NextLabel` usadas para pasar el estado destino a FallingState o TakeHit. Extremadamente frágil
- **Operadores de salto temprano (`GotoState`)**: el cambio de estado puede ocurrir en medio de un tick, causando problemas de consistencia
- **Funciones latentes nativas**: `MoveToward()` pausa el script hasta llegar al destino. No hay equivalente en Godot y no debería haberlo
- **Acoplamiento perfiles de bot al modo de juego**: ChallengeBotInfo maneja skins, nombres, voces, skill y personalidad en UNA sola clase con arrays de 32 posiciones

### ¿Qué ideas vale la pena implementar en Godot?
- **Arquitectura de estados como nodos individuales**: cada estado en su propio script, con métodos `enter()`, `execute(delta)`, `exit()`
- **Transiciones basadas en eventos**: usar señales de Godot para las transiciones entre estados
- **Sistema de órdenes con separación real/current**: fundamental para IA reactiva con propósito
- **`ChooseAttackMode()` como patrón**: un estado "evaluador" que solo decide y delega
- **AssessThreat con pesos contextuales**: el algoritmo de evaluación de amenazas como función reutilizable
- **`FindSpecialAttractionFor()` como interfaz de GameMode**: Strategy pattern para que cada modo de juego personalice comportamiento de bot
- **`SetAlertness()` modificando percepción**: sistema de "estado de alerta" que modifica sensores
- **Sistema de líder/seguidor**: para IA de equipo sin acoplamiento
- **StakeOut como estado**: espera en última posición conocida — estado simple pero esencial para IA creíble

---

## 10. Inventory.txt

### ¿Qué responsabilidad tiene？
Clase base de todo objeto que puede ser recogido y llevado por un Pawn. Define la cadena de inventario, armadura, munición, y — crucial para IA — la función `BotDesireability()`.

### ¿Qué problema resuelve？
Provee la estructura de datos del inventario (cadena enlazada) y — más importante — permite que CADA objeto evalúe cuánto lo desea un bot.

### ¿Cómo se comunica con otros sistemas？
- **Con Pawn**: el Pawn tiene un puntero `Inventory` al inicio de la cadena. `FindInventoryType()` recorre la cadena buscando por clase
- **Con Bot**: `BotDesireability(Pawn Bot)` es llamado por el sistema de pathfinding para saber qué tan atractivo es este objeto para el bot
- **Con Weapon**: `RecommendWeapon()` recorre la cadena para encontrar la mejor arma
- **Con Pickup**: Pickup hereda de Inventory y añade la lógica de recogida

### ¿Qué algoritmos utiliza？
**`BotDesireability(Pawn Bot)`**: algoritmo de evaluación de deseo por ítem:
```
desire = MaxDesireability  (valor base configurable)
if RespawnTime < 10:  // ítems que respawn rápido
	if ya_tiene_el_mismo AND charge >= actual:  return -1  (no lo quiere)
if es_armadura:
	if ya_tiene: desire *= (1 - charge_actual * absorcion * 0.00003)
	desire *= (Charge * 0.005)
	desire *= (ArmorAbsorption * 0.01)
	return desire
else: return desire (valor base)
```

**`RecommendWeapon(rating, useAltMode)`**: recorre la cadena de inventario hacia adelante llamando a `RateSelf()` de cada arma. Retorna la mejor.

### ¿Qué ideas siguen siendo excelentes en 2026？
- **`BotDesireability()` por ítem**: cada objeto sabe cómo evaluar su propio valor para un bot. Esto permite que cada arma, armadura, powerup decida su atractivo sin necesidad de un sistema central de evaluación
- **`MaxDesireability` como valor base**: permite a los level designers ajustar qué tan atractivo es un ítem
- **Evaluación contextual de armadura**: si ya tienes armadura, el deseo por más se reduce proporcionalmente
- **Chain of Responsibility**: `RecommendWeapon()` recorre la cadena — cada ítem decide si puede recomendar un arma o pasa al siguiente

### ¿Qué ideas están obsoletas？
- Cadena enlazada manual de inventario: frágil, propensa a errores (bucles, pérdidas)
- Funciones con nombres genéricos como `Activate()`

### ¿Qué ideas vale la pena implementar en Godot？
- **Sistema de deseabilidad por ítem**: cada pickup resource tiene un método `get_desireability(bot_context)` que el bot consulta para decidir prioridades
- **Chain of Responsibility para recomendación de armas**: las armas se evalúan en cadena, cada una puede recomendar o pasar
- **Contexto del bot pasado al ítem**: el ítem ve la salud, armas, munición actual del bot para decidir su valor

---

## 11. Pickup.txt

### ¿Qué responsabilidad tiene？
Maneja los objetos recogibles del mundo. Controla el ciclo de vida: aparecer, ser recogido, desaparecer, respawnear.

### ¿Qué problema resuelve？
Resuelve "¿qué pasa cuando un jugador/bot toca un ítem?" — incluyendo validación de si debe recogerse, replicación de red, y manejo de copias múltiples.

### ¿Cómo se comunica con otros sistemas？
- **Con Pawn**: via `Touch(Other)` cuando un Pawn colisiona con el pickup
- **Con Inventory**: hereda SpawnCopy() para crear una copia en el inventario del Pawn
- **Con GameMode**: notifica al Log (WorldLog/LocalLog) para estadísticas

### ¿Qué algoritmos utiliza？
- **`Touch()` → `ValidTouch()` → `SpawnCopy()`**: secuencia de recogida
- **`HandlePickupQuery()`**: el inventario existente del Pawn puede rechazar el pickup si ya tiene uno igual con carga suficiente
- **`SetRespawn()`**: maneja el timer de respawn

### ¿Qué ideas vale la pena implementar en Godot？
El sistema de pickup por touch con validación de inventario existente. El patrón de `HandlePickupQuery()` es útil para evitar duplicados.

---

## 12. TournamentWeapon.txt

### ¿Qué responsabilidad tiene？
Clase base de TODAS las armas en UT99 (hereda de Weapon). Define el ciclo de disparo, la recarga, la sincronización cliente/servidor, y aspectos críticos para IA como `RefireRate` y `FireAdjust`.

### ¿Qué problema resuelve？
Resuelve cómo las armas se comportan en manos de bots vs jugadores. Es especialmente importante para IA porque maneja la cadencia de disparo automática y la decisión de seguir disparando.

### ¿Cómo se comunica con otros sistemas？
- **Con Pawn**: `Pawn(Owner).bFire`, `Pawn(Owner).bAltFire` — el bot "presiona" estos botones y el arma responde
- **Con Bot**: bot llama `FireWeapon()`; el arma decide si realmente dispara basado en `RefireRate`
- **Con TournmentPickup**: `Affector` para efectos especiales

### ¿Qué algoritmos utiliza？
**`Finish()`**: ciclo de disparo para IA (crítico):
```
if (AmmoType != None AND AmmoType.AmmoAmount <= 0):
	PawnOwner.StopFiring()
	PawnOwner.SwitchToBestWeapon()  // CAMBIA DE ARMA AUTOMÁTICAMENTE
	GotoState('DownWeapon')
else if (PawnOwner.bFire != 0 AND FRand() < RefireRate):
	Global.Fire(0)  // SIGUE DISPARANDO
else if (PawnOwner.bAltFire != 0 AND FRand() < AltRefireRate):
	Global.AltFire(0)  // SIGUE CON FUEGO ALTERNO
else:
	PawnOwner.StopFiring()
	GotoState('Idle')
```

**`BecomeItem()`**: ajuste post-recogida:
```
FireAdjust = bot_skill * 0.5  // bots novatos tienen peor puntería
// Avisa a otros bots sobre el pickup (solo high skill)
if skill_check:
	for each bot:
		if VSize(bot - pickup_owner) < 800 + 100 * bot.Skill:
			B.HearPickup(Instigator)  // OTRO BOT SABE QUE ALGUIEN RECOGIÓ UN ARMA
```

### ¿Qué ideas siguen siendo excelentes en 2026？
- **`RefireRate` como probabilidad**: no es un timer fijo, es una probabilidad de seguir disparando. Esto produce comportamiento natural y variado
- **FireAdjust por skill**: bots novatos disparan peor
- **`HearPickup()` al recoger armas**: los bots de alto skill "oyen" cuando alguien recoge un arma — sistema de inferencia auditiva
- **Auto-cambio de arma al quedarse sin munición**: `SwitchToBestWeapon()` automático
- **Separación Fire/AltFire con RefireRate independiente**

### ¿Qué ideas están obsoletas？
- Sincronización manual cliente/servidor con flags `bCanClientFire`, `bForceFire`
- `FireAdjust = skill * 0.5` como hardcode

### ¿Qué ideas vale la pena implementar en Godot？
- **RefireRate como probabilidad de seguir disparando**: en lugar de cooldowns fijos
- **FireAdjust automático por skill**: las armas ajustan su precisión según el perfil del bot
- **Evento de pickup audible para otros bots**: sistema de inferencia por sonido
- **Auto-switch de arma al vaciarse**

---

## 13. ChallengeBotInfo.txt

### ¿Qué responsabilidad tiene？
Gestiona los perfiles completos de hasta 32 bots. Define nombre, equipo, skill, precisión, estilo de combate, alertness, camping, strafing, arma favorita, voz, apariencia. También implementa el ajuste dinámico de dificultad.

### ¿Qué problema resuelve？
Resuelve "¿cómo creo bots variados y convincentes?" — sin perfiles, todos los bots se comportarían igual. Con perfiles, cada bot tiene personalidad única y la dificultad se ajusta dinámicamente según el rendimiento del jugador.

### ¿Cómo se comunica con otros sistemas？
- **Con Bot**: `CHIndividualize(Bot, n, NumBots)` aplica el perfil completo al bot: skill, armas, comportamiento, apariencia, voz
- **Con GameInfo**: consulta `Difficulty` del juego para escalar skill
- **Con config system**: datos persistentes via `config(User)`
- **Con sistema de skins**: aplica skins y faces

### ¿Qué algoritmos utiliza？
**`AdjustSkill(Bot B, bool bWinner)`**: ajuste dinámico de dificultad:
```
if B ganó (mató al jugador):
	PlayerKills++
	AdjustedDifficulty -= 2 / min(PlayerKills, 10)
	if B.skill > AdjustedDifficulty: B.skill = AdjustedDifficulty
	if B.skill < 4: bNovice = true (comportamiento simple)
	else: B.skill -= 4 (normalizar a 0-3)
else (jugador mató al bot):
	PlayerDeaths++
	AdjustedDifficulty += min(7, 2 / min(PlayerDeaths, 10))
	if B.skill < AdjustedDifficulty: B.skill = AdjustedDifficulty
	if B.skill < 4: bNovice = true
	else: B.skill -= 4
```

**`CHIndividualize()`**: aplicación de perfil:
```
NewBot.InitializeSkill(Difficulty + BotSkills[n])  // skill = difficulty global + personal
NewBot.Accuracy = BotAccuracy[n]
NewBot.CombatStyle = default + 0.7 * ConfigCombatStyle[n]
NewBot.BaseAggressiveness = 0.5 * (default_Aggressiveness + CombatStyle)
NewBot.BaseAlertness = Alertness[n]
NewBot.CampingRate = Camping[n]
NewBot.StrafingAbility = StrafingAbility[n]
NewBot.bJumpy = (BotJumpy[n] != 0)
```

### ¿Qué ideas siguen siendo excelentes en 2026？
- **Perfiles con personalidad multidimensional**: nombre, skill, precisión, estilo, alertness, camping, strafing, jumpy — todo combinado crea bots únicos
- **Ajuste dinámico de dificultad**: el juego sube/baja la dificultad según rendimiento del jugador. Factor de ajuste 2/min(10, partidas) — elegante
- **Separación skill global + skill personal**: `Difficulty + BotSkills[n]` permite que un bot sea fácil en dificultad alta o viceversa
- **`CombatStyle` como combinación linear**: `0.5 * (default_Aggressiveness + CombatStyle)` produce valores naturales

### ¿Qué ideas están obsoletas？
- **Array fijo de 32 slots**: límite innecesario
- **Configuración persistente en clase**: `config(User)` en la definición misma de la clase
- **Selección secuencial de slots**: frágil, usa índices que pueden desincronizarse

### ¿Qué ideas vale la pena implementar en Godot？
- **BotProfile como Resource**: con todas las dimensiones de personalidad
- **Sistema de ajuste dinámico de dificultad**: el algoritmo AdjustSkill移植ado a Godot
- **Separación skill global + personal**: dificultad del modo + perfil individual
- **Combinación de atributos para emergent behavior**: aggressiveness + combatStyle + camping + strafing producen comportamientos únicos
- **`CHIndividualize()` como patrón de inicialización**: aplicar perfil completo en _ready()

---

## 14. BotReplicationInfo.txt

### ¿Qué responsabilidad tiene？
Replica información de estado del bot a los clientes. Específicamente: las órdenes reales del bot, quién las dio, y el objeto de la orden.

### ¿Qué problema resuelve？
En UT99, las órdenes de los bots se replican a clientes para que el HUD de equipo muestre qué está haciendo cada bot. También permite que el jugador vea las órdenes de los bots.

### ¿Cómo se comunica con otros sistemas？
- **Con Bot**: `BotReplicationInfo(PlayerReplicationInfo)` casteo directo para acceder a RealOrders, OrderObject
- **Con Client**: replicación via `replication { ... }` block (UnrealScript nativo)
- **Con GameMode**: CTFGame y Assault usan BotReplicationInfo para restaurar órdenes después de eventos (flag capture, fort destroy)

### ¿Qué algoritmos utiliza？
`SetRealOrderGiver(Pawn P)`: guarda quién dio la orden y su PlayerReplicationInfo.

### ¿Qué ideas vale la pena implementar en Godot？
La necesidad de replicar órdenes de IA al cliente es real — en juegos multiplayer con IA visible, los clientes deben saber qué hacen los bots. En Godot, usar RPC o state sync.

---

## 15. CTFGame.txt

### ¿Qué responsabilidad tiene？
Implementa el modo de juego Captura la Bandera. Proporciona la lógica de puntuación, manejo de banderas, y — crucial para IA — las funciones que los bots consultan para comportamiento específico de CTF.

### ¿Qué problema resuelve？
Resuelve cómo la IA debe comportarse en CTF: cómo evaluar amenazas (portador de bandera = amenaza máxima), cómo asignar defensores, cómo encontrar rutas a la base.

### ¿Cómo se comunica con otros sistemas？
- **Con Bot**: vía funciones sobrescritas: `SetDefenseFor()`, `GameThreatAdd()`, `FindPathToBase()`, `AssessBotAttitude()`
- **Con CTFFlag**: maneja eventos de captura, retorno, pérdida
- **Con BotReplicationInfo**: restaura órdenes después de eventos de bandera

### ¿Qué algoritmos utiliza？
**`GameThreatAdd(Bot, Pawn Other)`**: modifica la evaluación de amenaza del bot:
```
if Other.PlayerReplicationInfo.HasFlag != None:
	return 10  // portador de bandera = prioridad MÁXIMA
else:
	return 0
```

**`AssessBotAttitude(Bot, Pawn Other)`**: determina actitud:
```
if same team: return TEAMMATE (ignorar)
if Other has flag OR bot has flag: return ATTACK (prioridad combate)
else: super() (delegar a la clase base)
```

**`SetDefenseFor(Bot)`**: asigna objetivo de defensa:
```
return CTFReplicationInfo.FlagList[aBot.Team].HomeBase  // defender la bandera propia
```

**`FindPathToBase(Bot, FlagBase)`**: navegación con rutas alternativas:
```
if bot has AlternatePath AND reachable:
	MoveTarget = AlternatePath (ruta alternativa)
else:
	MoveTarget = normal path to base
```

**Manejo de flag capture**: restaura órdenes de TODOS los bots del equipo:
```
for each teammate Bot:
	Bot.SetOrders(BotReplicationInfo.RealOrders, RealOrderGiver, true)
```

### ¿Qué ideas siguen siendo excelentes en 2026？
- **`GameThreatAdd()`**: el modo de juego puede modificar la evaluación de amenaza del bot. Portador de bandera = threat +10. Es un hook limpio
- **`SetDefenseFor()` como polimorfismo**: cada GameMode define QUÉ defender (base, control point, fortaleza)
- **Restauración de órdenes post-evento**: después de una captura, todos los bots recuperan sus órdenes originales
- **Rutas alternativas por GameMode**: CTF proporciona su propia lógica de pathfinding

### ¿Qué ideas vale la pena implementar en Godot？
- **GameMode como Strategy de IA**: funciones hook como `game_threat_add()`, `set_defense_for()`, `find_special_attraction_for()` que cada modo de juego implementa
- **Evaluación contextual de amenazas**: portador de bandera = amenaza 10x
- **Sistema de restauración de órdenes**: post-evento global

---

## 16. Domination.txt

### ¿Qué responsabilidad tiene？
Implementa el modo de juego Dominación. Gestiona puntos de control, su captura, y la IA específica para defenderlos.

### ¿Qué problema resuelve？
Resuelve cómo los bots priorizan objetivos en Dominación: qué punto controlar, cómo distribuir defensores, cómo reaccionar a pérdidas.

### ¿Cómo se comunica con otros sistemas？
- **Con ControlPoint**: itera todos los ControlPoints del mapa para scoring y asignación
- **Con Bot**: `SetDefenseFor()` retorna un ControlPoint; `FindSpecialAttractionFor()` maneja la lógica de captura
- **Con Bot Orders**: al respawnear, si un bot tenía orden 'Defend', se cambia a 'Freelance' para evitar quedarse defendiendo un punto ya capturado

### ¿Qué algoritmos utiliza？
**`SetDefenseFor(Bot)`**: selecciona un ControlPoint para defender:
```
if bot ya tiene OrderObject (ControlPoint): return ese
while iterando ControlPoints:
	if control point está controlado por el equipo del bot:
		selecciónalo con probabilidad 1/i (reservoir sampling)
return el seleccionado
```

**`FindSpecialAttractionFor(Bot)`**: decide si el bot debe ir a un punto:
Maneja asignación de bots a puntos basado en distancia, si están bajo ataque, y cuántos bots del equipo están cerca.

### ¿Qué ideas vale la pena implementar en Godot？
Misma idea que CTFGame: GameMode como Strategy. Reservoir sampling para selección de objetivos. Transición de órdenes post-respawn.

---

## 17. Assault.txt

### ¿Qué responsabilidad tiene？
Implementa el modo de juego Asalto (atacantes vs defensores con fortalezas). Gestiona fortalezas, líderes de equipo, y la IA específica de ataque/defensa.

### ¿Qué problema resuelve？
Resuelve cómo los bots atacan y defienden fortalezas en secuencia, con líderes de equipo que coordinan la estrategia.

### ¿Cómo se comunica con otros sistemas？
- **Con FortStandard**: itera, aleatoriza, asigna defensores a fortalezas
- **Con DefensePoint**: cuando una fortaleza cae, sus DefensePoints se marcan `taken = true`
- **Con Bot**: `SetDefenseFor()`, `FindSpecialAttractionFor()`, `BestFortFor()`, `AttackFort()`, `SendBotToGoal()`
- **Con Leader system**: `Leader[4]` referencias al líder de cada equipo
- **Con SpectatorCam**: transiciones de cámara al final de la partida

### ¿Qué algoritmos utiliza？
**`BestFortFor(Bot, oldFort, currentFort)`**: compara qué fortaleza es mejor para un bot:
```
if currentFort.priority > oldFort.priority → currentFort (prioridad más alta)
OR (misma prioridad AND (currentFort sin defensor OR currentFort asignado a este bot OR oldFort tenía otro))
```

**`AttackFort(Bot, out bMultiSame)`**: elige la mejor fortaleza para atacar:
```
BestFort = Fort[0] (la primera, aleatorizada)
for each fort:
	if priority > BestFort → actualizar
	if same priority AND bot tiene LOS → actualizar (el que puede ver)
```

**`FindSpecialAttractionFor(Bot)`** (~200 líneas): maneja la lógica completa de ataque/defensa:
```
if bot es atacante:
	usa AttackFort() para elegir objetivo
	si está cerca, ataca la fortaleza como enemigo
	usa FindPathToFortFor() para navegar
if bot es defensor:
	defiende fortaleza actual
	si la fortaleza cae, reasigna
```

**`SetDefenseFor(Bot)`**: asigna fortaleza a defender:
```
if bot no es del equipo defensor → SetOrders('Attack')
if bot es defensor:
	elige la mejor fortaleza via BestFortFor()
	asigna F.Defender = aBot
```

**Liderazgo**: `ElectNewLeaderFor(Bot)` cuando el líder muere. `Leader[team]` usado por FindSpecialAttractionFor.

**Ajuste de skill para atacantes**: `RestartPlayer()` sube el skill de bots atacantes para compensar la desventaja.

### ¿Qué ideas siguen siendo excelentes en 2026？
- **Líderes de equipo elegidos automáticamente**: IA coordinada sin necesidad de jugador
- **Prioridad dinámica de fortalezas**: cuando una fortaleza es atacada, su prioridad sube
- **Aleatorización de orden de ataque**: para que la IA no siempre ataque en el mismo orden
- **Compensación de skill por rol**: atacantes reciben boost de skill (ventaja ofensiva)
- **Fortaleza como enemigo**: `aBot.SetEnemy(Fort)` — tratar estructuras como enemigos

### ¿Qué ideas vale la pena implementar en Godot？
- **Sistema de líderes de equipo**: un bot por equipo coordina a los demás
- **Objetivos como enemigos**: estructuras/objetivos tratados como entidades para la IA
- **Prioridad dinámica de objetivos**: según contexto del juego
- **Compensación de IA por rol**: ajustar skill según si eres atacante/defensor

---

# ANÁLISIS TRANSVERSAL: PATRONES ARQUITECTÓNICOS DE UT99

## 1. Sistema de Eventos

UT99 no usa un event bus explícito. En su lugar, CADA ESTADO maneja los eventos que le interesan:

```
state Roaming {
	function SeePlayer(Pawn Seen) {
		// manejar
	}
	function HearNoise(...) { ... }
	function TakeDamage(...) { ... }
}
```

Un estado simplemente SOBRESCRIBE los eventos que le importan. Los que no sobrescribe son ignorados. Esto es **event-driven architecture** descentralizada.

**En Godot**: señales conectadas por estado. Cada BotState Node conecta/desconecta señales en enter()/exit().

## 2. Separación Datos vs Lógica

- **NavigationPoint**: datos (posición, conexiones, costos). No tiene lógica de pathfinding (eso es C++).
- **Bot**: lógica de decisión. Usa NavigationPoint como datos.
- **Inventory**: datos (cadena de items). BotDesireability() es lógica del item, no del bot.
- **ChallengeBotInfo**: datos (perfiles). CHIndividualize() aplica esos datos.

## 3. GameMode como Proveedor de Estrategia

CTFGame, Domination, Assault NO modifican Bot. En su lugar, proporcionan funciones hook:
- `SetDefenseFor(Bot)` → qué defender
- `GameThreatAdd(Bot, Pawn)` → modificar amenaza
- `FindSpecialAttractionFor(Bot)` → comportamiento específico
- `FindPathToBase(Bot, Base)` → navegación específica

Esto es **Strategy Pattern** puro, 20 años antes de que se popularizara el término en gamedev.

## 4. Jerarquía de Navegación

```
NavigationPoint (base: nodo + conexiones)
├── PathNode (simple, default)
├── AmbushPoint (táctico: lookdir, SightRadius, bSniping)
│   └── DefensePoint (equipo: team, priority, FortTag)
├── LiftCenter (ascensor: SpecialHandling, triggers)
├── LiftExit (salida: coordinación con LiftCenter)
└── AlternatePath (ruta alternativa: team, weight, bReturnOnly)
```

Cada subclase añade UNA responsabilidad. Clean single-responsibility.

## 5. Separación Órdenes

```
RealOrders (persistente, replicada a clientes)
	↓ se restaura via SetOrders() cuando:
	└── WhatToDoNext() (bot terminó lo que hacía)
	└── ScoreKill() (evento de captura/respawn)
	└── RemoveFort() (fortaleza destruida)

Orders (actual, puede cambiar temporalmente)
	└── 'Attack' cuando ve enemigo
	└── 'Follow' cuando sigue líder
	└── 'Defend' cuando defiende punto
```

## 6. Flujo de Decisión

```
Evento externo (SeePlayer, TakeDamage, HearNoise, Timer)
	→ Estado actual lo maneja
	→ Decide: GotoState(new_state)
	→ Nuevo estado: PickDestination() + MoveToward/StrafeFacing
	→ Mientras se mueve, sigue recibiendo eventos
	→ ¿Nuevo evento? Vuelta al inicio
```

No hay "árbol de comportamiento" ni "sistema de prioridades". Hay EVENTOS y el estado sabe qué hacer con cada uno.

---

# MATRIZ DE COMUNICACIÓN ENTRE SISTEMAS

| Sistema | Escribe | Lee | Eventos que recibe |
|---------|---------|-----|-------------------|
| NavigationPoint | cost, taken | ReachSpecs (C++) | SpecialCost(Pawn) |
| AmbushPoint | (solo datos) | lookdir, SightRadius | — |
| DefensePoint | (solo datos) | team, priority, FortTag | — |
| LiftCenter | LastTriggerTime | LiftTag, MyLift, RecommendedTrigger | SpecialHandling(Pawn) |
| Pawn | Velocity, Location, Health | Todo el mundo | SeePlayer, HearNoise, TakeDamage, HitWall, Bump, etc. |
| Inventory | (la cadena) | Owner | BotDesireability(Pawn) |
| TournamentWeapon | bFire, bAltFire | Owner, AmmoType | Finish() (timer) |
| Bot | Enemy, Orders, MoveTarget | Pawn, GameInfo, NavigationPoints | Todos los eventos de Pawn + Timer + BotVoiceMessage |
| BotReplicationInfo | RealOrders, OrderGiverPRI | Client | SetRealOrderGiver() |
| CTFGame | Score, flag states | Bot, CTFFlag | ScoreFlag, Killed, Logout |
| Domination | Score, ControlPoints | Bot, ControlPoint | Timer, Logout, RestartPlayer |
| Assault | Defender, Attacker, Fort[] | Bot, FortStandard | Killed, RemoveFort, RestartPlayer |
| ChallengeBotInfo | Bot profiles (config) | Bot | AdjustSkill, CHIndividualize |

---

# LO QUE VALE LA PENA IMPLEMENTAR EN GODOT (RESUMEN)

## Prioridad Alta (núcleo de la IA)
1. **FSM reactiva**: cada estado como nodo que maneja eventos específicos
2. **Separación RealOrders/Orders**: IA reactiva con propósito
3. **AssessThreat con pesos contextuales**: algoritmo de evaluación de amenazas
4. **GameMode como Strategy**: hooks para `game_threat_add()`, `set_defense_for()`, `find_special_attraction_for()`
5. **BotProfile Resource**: personalidad multidimensional del bot
6. **Ajuste dinámico de dificultad**: algoritmo AdjustSkill

## Prioridad Media (navegación y tácticas)
7. **NavigationPoints tácticos**: AmbushPoint con lookdir, SightRadius, bSniping
8. **DefensePoint con prioridad y team**: asignación de defensa
9. **Rutas alternativas por equipo**: AlternatePath con SelectionWeight
10. **Sistema de líder/seguidor**: IA de equipo coordinada
11. **`BotDesireability()` por ítem**: cada pickup con auto-evaluación
12. **RefireRate probabilístico**: en lugar de cooldowns fijos

## Prioridad Baja (refinamiento)
13. **`SpecialHandling()` pattern**: nodos de navegación que interceptan rutas
14. **StakeOut state**: espera en última posición conocida
15. **LiftCenter/LiftExit**: navegación vertical con plataformas
16. **Evaluación de armadura contextual**: deseo por armadura según carga actual
17. **Restauración de órdenes post-evento**: para modos de juego

---

# LO QUE NO SE DEBE IMPLEMENTAR EN GODOT (OBSOLETO)

1. **Funciones latentes de movimiento**: `MoveToward()` que pausa el script
2. **Estados como bloques monolíticos**: 7587 líneas en un archivo
3. **Listas enlazadas globales**: `nextPawn`, `nextNavigationPoint`
4. **Arrays fijos**: `Paths[16]`, `upstreamPaths[16]`
5. **Variables de comunicación temporal**: `NextState`/`NextLabel`
6. **Docenas de boolean flags**: `bCanFire`, `bStrafeDir`, `bChangeDir`, etc.
7. **Operadores de salto temprano**: `GotoState()` en mitad de ejecución
8. **Variables de motor escritas directamente**: `noise1spot`, `noise1loudness`
