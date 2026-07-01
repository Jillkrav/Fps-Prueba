# Plan de Solución: 3 Problemas de Bots

## Análisis y plan paso a paso para corregir el comportamiento de los bots

---

## 📋 Índice

1. [Problema 1: Bots atascados entre sí y en esquinas](#problema-1-bots-atascados-entre-sí-y-en-esquinas)
2. [Problema 2: Bots saltando constantemente](#problema-2-bots-saltando-constantemente)
3. [Problema 3: Bots ven a través de paredes](#problema-3-bots-ven-a-través-de-paredes)
4. [Orden de implementación recomendado](#orden-de-implementación-recomendado)
5. [Respaldo y seguridad](#respaldo-y-seguridad)

---

## Problema 1: Bots atascados entre sí y en esquinas

### Síntomas
- Dos o más bots se encuentran cara a cara en un pasillo y no logran separarse
- Los bots se quedan pegados al intentar doblar una esquina
- Aunque el NavMesh está bien separado de las paredes, los bots chocan con las esquinas

### Causas raíz identificadas

#### 1A. Sistema de avoidance demasiado simple
**Archivo:** `res://scripts/ai/movement_system.gd` — función `_apply_avoidance()` (línea 281)

El sistema actual usa un `PhysicsShapeQuery3D` con una esfera de radio `AVOIDANCE_RADIUS = 3.5` para detectar otros NPCs cercanos y aplica una fuerza de separación (`AVOIDANCE_FORCE = 3.0`). Pero esta separación es meramente reactiva: empuja a los bots en dirección opuesta sin considerar la ruta de navegación. En pasillos estrechos, dos bots empujándose mutuamente quedan atrapados en un punto muerto.

#### 1B. Detección de atasco y recuperación ineficaz en espacios estrechos
**Archivo:** `res://scripts/ai/movement_system.gd` — funciones `_check_stuck()` (línea 321), `_handle_stuck_recovery()` (línea 382)

Cuando se detecta un atasco, el bot ejecuta 3 fases:
1. **Fase 1** (0.4s): Retrocede en dirección contraria al objetivo + salta si hay otro bot cerca
2. **Fase 2** (0.3s): Se mueve lateralmente
3. **Fase 3**: Recalcula ruta

El problema es que la dirección de recuperación se calcula una sola vez al inicio y no se ajusta dinámicamente. En esquinas, retroceder en dirección contraria al objetivo puede meter al bot más en la pared.

#### 1C. Bots que se persiguen no usan el NavigationAgent para evitarse
**Archivo:** `res://scripts/ai/movement_system.gd` — función `_execute_navigate()` (línea 198)

El NavigationAgent3D de Godot calcula rutas individuales para cada bot, pero no tiene un sistema de avoidance integrado. Cada bot sigue su propia ruta sin saber dónde están los otros bots. Cuando dos rutas se cruzan en un punto estrecho, los bots chocan.

#### 1D. Parámetros del NavigationAgent3D
**Archivo:** `res://scenes/npcs/npc.tscn` — línea 61-62

```gdscript
target_desired_distance = 1.5
path_max_distance = 3.0
```

`path_max_distance = 3.0` significa que el agente no recalcula la ruta hasta que el bot se desvía 3 unidades del camino. En espacios estrechos, esto permite que los bots se desvíen bastante antes de re-planificar.

### Plan de solución (Paso 1)

#### Paso 1.1: Mejorar el avoidance con RVO (Optimal Reciprocal Collision Avoidance)

**Archivo a modificar:** `res://scripts/ai/movement_system.gd`

**Qué cambiar:**
- Reemplazar el avoidance esférico actual (`_apply_avoidance`) con un sistema basado en RVO utilizando la API de `NavigationServer3D`. Godot 4 tiene soporte nativo para RVO avoidance en los NavigationAgents.
- Activar `agent.enable_avoidance = true` en el NavigationAgent3D (actualmente debe estar en `false` o no configurado).
- Configurar `agent.radius`, `agent.max_speed` y `agent.agent_height_offset` en el NavigationAgent3D para que los bots se eviten entre sí durante la navegación.

**Por qué funciona:** RVO es un algoritmo probado donde cada agente asume que los demás también están evitando, lo que produce un movimiento fluido sin colisiones frontales. Godot's NavigationServer3D implementa RVO de forma nativa — no requiere物理引擎 queries.

**Archivos a tocar:**
1. `res://scenes/npcs/npc.tscn` — Configurar propiedades de avoidance en NavigationAgent3D
2. `res://scripts/ai/movement_system.gd` — Eliminar `_apply_avoidance()` esférico, activar avoidance del agente
3. `res://scripts/ai/navigation/navigation_system.gd` — Inicializar agente con avoidance config

**Riesgo:** Bajo. RVO es nativo de Godot y está diseñado para esto. La implementación actual es un workaround hecho a mano.

#### Paso 1.2: Mejorar stuck recovery con detección de entorno

**Archivo a modificar:** `res://scripts/ai/movement_system.gd`

**Qué cambiar:**
- En `_check_stuck()`: Añadir un RayCast3D lateral antes de decidir la dirección de recuperación para verificar que la dirección de retroceso no tenga una pared.
- En `_handle_stuck_recovery()`: En lugar de direcciones fijas, usar múltiples RayCast3D para encontrar una dirección libre antes de ejecutar cada fase.
- Reducir `STUCK_PROGRESS_THRESHOLD` para combat de 4.0 a 2.5 (detectar atasco más rápido en combate).
- En la fase 1 de recuperación: eliminar el salto automático (el salto se tratará en el Problema 2). En su lugar, el bot debería intentar rodear al obstáculo buscando una dirección alternativa.

**Por qué funciona:** En lugar de moverse a ciegas en direcciones predefinidas, el bot "mira" primero si hay espacio libre y se mueve hacia allí.

**Archivos a tocar:**
1. `res://scripts/ai/movement_system.gd` — Modificar `_init_recovery_direction()`, `_handle_stuck_recovery()`, constantes

**Riesgo:** Medio. Si los raycasts fallan (e.g., el bot está en una posición extraña), podría empeorar el atasco. Implementar con fallback a la dirección actual.

#### Paso 1.3: Ajustar NavigationAgent3D para mejor navegación en espacios estrechos

**Archivo a modificar:** `res://scenes/npcs/npc.tscn`

**Qué cambiar:**
- Reducir `path_max_distance` de 3.0 a **1.5** (recalcular ruta más rápido al desviarse)
- Mantener `target_desired_distance = 1.5`
- Añadir `radius = 0.8` (un poco más que el radio de la cápsula 0.4 para dar espacio)
- Añadir `enable_avoidance = true`

**Por qué funciona:** Un `path_max_distance` más pequeño hace que el NavigationAgent recalcule la ruta inmediatamente cuando el bot se desvía ligeramente (por ejemplo, al esquivar a otro bot o una esquina).

**Archivos a tocar:**
1. `res://scenes/npcs/npc.tscn` — Propiedades del NavigationAgent3D

**Riesgo:** Muy bajo. Solo cambios de configuración.

#### Paso 1.4: Hacer que bots bloqueados cedan el paso

**Archivo a modificar:** `res://scripts/ai/movement_system.gd`

**Qué cambiar:**
- En `_check_bot_blocking()`: Cuando dos bots están bloqueados mutuamente durante más de 1 segundo, el bot con menor prioridad (e.g., menor `_npc_id` o que no está en combate) debería detenerse y dejar pasar al otro.
- Añadir un temporizador de "cede el paso": si el bot ha estado bloqueado > 1.5s y hay otro bot enfrente, reducir su velocidad a 0 por 0.5s para que el otro pase.

**Por qué funciona:** Es el comportamiento humano natural: cuando dos personas se encuentran en un pasillo, una se detiene para dejar pasar a la otra.

**Archivos a tocar:**
1. `res://scripts/ai/movement_system.gd` — Modificar `_check_bot_blocking()`

**Riesgo:** Bajo. Fácil de desactivar si causa problemas.

---

## Problema 2: Bots saltando constantemente

### Síntomas
- Todos los bots saltan en intervalos de 5-10 segundos incluso sin necesidad
- El salto debería reservarse para desatascarse o esquivar

### Causas raíz identificadas

#### 2A. Jump_frequency demasiado alta en los TacticalRoles
**Archivo:** `res://scripts/tactical_role.gd` — configuraciones de roles (líneas 258, 305, 353, 401)

Cada rol tiene un `jump_frequency`:
| Rol       | jump_frequency | strafe_change_interval | Saltos por minuto (aprox) |
|-----------|---------------|----------------------|--------------------------|
| DEFENDER  | 0.1           | 3.5s                 | ~1.7/min                 |
| ASSAULT   | 0.3           | 1.5s                 | ~12/min                  |
| FLANKER   | 0.5           | 1.0s                 | ~30/min                  |
| PATROLLER | 0.2           | 2.5s                 | ~4.8/min                 |

Los ASSAULT saltan ~12 veces por minuto y los FLANKER ~30 veces por minuto. Esto es excesivo.

#### 2B. El salto por atasco también contribuye
**Archivo:** `res://scripts/ai/movement_system.gd` — línea 388-390

```gdscript
if bot.is_on_floor():
    bot.velocity.y = 8.0
```

Cuando un bot se atasca con otro bot, la fase 1 de recuperación SIEMPRE salta. Si el bot se atasca frecuentemente (lo cual ocurre con el Problema 1 sin resolver), salta constantemente.

#### 2C. El salto está en el strafe, no en eventos específicos
**Archivo:** `res://scripts/ai/states/state_combat.gd` — líneas 269-272

El salto táctico ocurre CADA VEZ que cambia la dirección de strafe. Para ASSAULT con `strafe_change_interval = 1.5`, el strafe cambia aproximadamente cada 1-3 segundos, y con `jump_frequency = 0.3`, el bot salta ~1 de cada 3 cambios.

### Plan de solución (Paso 2)

#### Paso 2.1: Reducir jump_frequency drásticamente

**Archivo a modificar:** `res://scripts/tactical_role.gd`

**Qué cambiar:**
- ASSAULT: 0.3 → **0.05** (5% por cambio de strafe ≈ 1 salto cada 30 segundos)
- FLANKER: 0.5 → **0.08** (8% ≈ 1 salto cada 12-15 segundos)
- DEFENDER: 0.1 → **0.02** (casi nunca salta en strafe)
- PATROLLER: 0.2 → **0.03**

**Por qué funciona:** El salto durante strafe debería ser un evento raro y táctico, no un comportamiento por defecto. Con estos valores reducidos, los bots solo saltarán en strafe cuando sea tácticamente relevante (esquivar un disparo).

**Archivos a tocar:**
1. `res://scripts/tactical_role.gd` — Valores de `jump_frequency` en los 4 roles

**Riesgo:** Muy bajo. Solo cambiar números.

#### Paso 2.2: Eliminar el salto automático en stuck recovery

**Archivo a modificar:** `res://scripts/ai/movement_system.gd` — línea 388-390

**Qué cambiar:**
- Eliminar o comentar el salto automático en la fase 1 de stuck recovery.
- En su lugar, si el bot está bloqueado por otro bot y en el suelo, simplemente debe esperar 0.2s adicionales antes de la fase 2 (lateral).
- El salto solo debería ocurrir si: (a) el bot lleva > 2s atascado, Y (b) no hay espacio a los lados verificado por RayCast3D.

**Por qué funciona:** El salto como solución primaria al atasco es contraproducente: el bot salta en el sitio sin moverse lateralmente, y al caer sigue atascado. Es mejor esperar y moverse lateralmente.

**Archivos a tocar:**
1. `res://scripts/ai/movement_system.gd` — Modificar `_handle_stuck_recovery` fase 1

**Riesgo:** Medio. Si se elimina el salto y el bot está realmente atascado en un hueco, podría no salir. Implementar como "salto solo tras 2s sin progreso lateral".

#### Paso 2.3: Mover el salto táctico a un sistema basado en eventos

**Archivo a modificar:** `res://scripts/ai/states/state_combat.gd`

**Qué cambiar:**
- En lugar de que el salto ocurra aleatoriamente durante strafe, moverlo a `CombatSystem._check_dodge_request()`.
- Cuando el bot recibe daño o detecta un proyectil entrante (futuro), solicitar un dodge que puede incluir salto.
- Mantener el salto en strafe pero solo cuando el bot está en rango de combate cerrado (< 5m) Y hay un cambio de dirección.

**Por qué funciona:** El salto debería ser una respuesta a estímulos (daño recibido, proyectil detectado), no un comportamiento aleatorio.

**Archivos a tocar:**
1. `res://scripts/ai/states/state_combat.gd` — Modificar `_execute_strafe()` salto
2. `res://scripts/ai/combat_system.gd` — Añadir verificación de salto en `_check_dodge_request()`

**Riesgo:** Medio. Cambia la lógica de cuándo saltan los bots en combate.

---

## Problema 3: Bots ven a través de paredes

### Síntomas
- Los bots detectan al jugador a través de paredes
- Un bot comienza a disparar inmediatamente cuando el jugador aparece, como si ya supiera que estaba ahí

### Causas raíz identificadas

#### 3A. RayCast3D sin `hit_from_inside = true`
**Archivo:** `res://scenes/npcs/npc.tscn` — línea 80-82

El RaycastVision no tiene configurado `hit_from_inside`. En Godot 4, `RayCast3D` por defecto tiene `hit_from_inside = false`. Esto significa que si el origen del rayo está DENTRO de un collider (por ejemplo, si el bot está ligeramente dentro de una pared por compresión de física), el rayo NO detectará esa pared y atravesará hacia el otro lado.

#### 3B. La detección usa AreaVision + RayCast, y el AreaVision tiene radio 30
**Archivo:** `res://scenes/npcs/npc.tscn` — línea 26-27

El AreaVision usa un `SphereShape3D` con radio 30. Cualquier cuerpo enemigo dentro de este radio es candidato a detección. Si el RayCast falla (ve a través de una pared), el enemigo es detectado.

#### 3C. El collider del RaycastVision puede estar mal configurado
**Archivo:** `res://scenes/npcs/npc.tscn` — línea 82

`collision_mask = 7` en el RaycastVision. En binario: `0b111` = capas 1, 2, 3.
- Capa 1: Jugador (CharacterBody3D por defecto) y paredes (CSGBox3D)
- Capa 2: NPCs (NpcBase)
- Capa 3: ? (no identificado en el mapa)

Esto DEBERÍA funcionar para detectar paredes. Pero si por alguna razón las paredes están en otra capa de colisión...

#### 3D. force_raycast_update() antes de move_and_slide()
**Archivo:** `res://scripts/ai/perception_system.gd` — línea 142

La percepción se ejecuta en `_physics_process()` ANTES de `move_and_slide()`. El `force_raycast_update()` fuerza al RayCast3D a calcular inmediatamente, pero el estado de físicas podría no estar completamente actualizado si los colliders se movieron en el frame anterior.

### Plan de solución (Paso 3)

#### Paso 3.1: Habilitar hit_from_inside en RaycastVision

**Archivo a modificar:** `res://scenes/npcs/npc.tscn`

**Qué cambiar:**
- Añadir `hit_from_inside = true` al nodo RaycastVision.

**Por qué funciona:** Con `hit_from_inside = true`, el RayCast3D detecta colliders incluso si el origen del rayo está dentro de ellos. Esto evita que bots parcialmente dentro de una pared (por compresión de física) atraviesen la pared con su rayo de visión.

⚠️ **Importante:** Esto no es suficiente por sí solo. Con `hit_from_inside = true`, si el bot está dentro de una pared, el rayo DETECTARÁ la pared inmediatamente (distancia 0) y el LOS fallará correctamente.

**Archivos a tocar:**
1. `res://scenes/npcs/npc.tscn` — Añadir `hit_from_inside = true` al RaycastVision

**Riesgo:** Bajo. Esto solo cambia cómo se comporta el rayo cuando comienza dentro de un collider.

#### Paso 3.2: Verificar y corregir collision_mask del RaycastVision

**Archivo a modificar:** `res://scenes/npcs/npc.tscn`

**Qué hacer:**
- Verificar que el `collision_mask = 7` incluya la capa de las paredes CSGBox3D.
- Las CSGBox3D del mapa usan `collision_layer = 1` por defecto.
- `collision_mask = 7` = capas 1, 2, 3 — la capa 1 SÍ está incluida.
- Pero para estar seguros, podemos cambiarlo a `collision_mask = 15` (capas 1-4) para cubrir TODAS las capas de物理. Esto asegura que cualquier obstáculo, sin importar su capa, bloquee la línea de visión.

**Por qué funciona:** Si alguna pared o cobertor usa una capa de colisión diferente a la 1 (por ejemplo, capa 4), el rayo no la detectaría. Usar máscara 15 (= 0b1111 = capas 1-4) cubre todos los casos.

⚠️ Opcional y más seguro: si queremos ser precisos, podemos determinar exactamente qué capas usan las paredes y cobertores del mapa y ajustar la máscara a solo esas. Pero usar 15 es más robusto.

**Archivos a tocar:**
1. `res://scenes/npcs/npc.tscn` — Cambiar `collision_mask = 7` a `collision_mask = 15`

**Riesgo:** Muy bajo. Una máscara más grande solo significa que el rayo choca con más cosas, lo cual es más restrictivo (menos falsos positivos de LOS).

#### Paso 3.3: Añadir un segundo RayCast3D de verificación

**Archivo a modificar:** `res://scripts/ai/perception_system.gd`

**Qué cambiar:**
- Después del LOS check principal, añadir un segundo RayCast3D de verificación desde una posición ligeramente diferente (e.g., desde la posición de la cabeza, o con un pequeño offset lateral).
- Solo considerar que hay LOS si AMBOS raycasts confirman la línea de visión.

**Por qué funciona:** Un solo RayCast3D puede tener falsos positivos si el rayo pasa por un hueco o si la geometría es compleja. Dos raycasts desde posiciones ligeramente diferentes reducen drásticamente la probabilidad de que ambos pasen a través de un hueco accidental.

**Implementación:**
```gdscript
# En perception_system.gd, dentro del LOS check:

# Raycast 1: desde el cuerpo (actual)
bot.raycast_vision.target_position = local_target
bot.raycast_vision.force_raycast_update()
var collider_1 = bot.raycast_vision.get_collider()

# Raycast 2: desde la cabeza (offset up)
var head_pos = bot.head.global_position if bot.head else bot.global_position + Vector3.UP * 0.9
var space_state = bot.get_world_3d().direct_space_state
var query = PhysicsRayQueryParameters3D.create(head_pos, target_pos + Vector3.UP * 1.5)
query.collision_mask = 15  # Misma máscara que el RaycastVision
query.exclude = [bot]  # Excluirse a sí mismo
var result = space_state.intersect_ray(query)
var collider_2 = result.get("collider") if result else null

# LOS requiere que AMBOS rayos impacten al enemigo
var has_los = _is_target(body, collider_1) and _is_target(body, collider_2)
```

**Archivos a tocar:**
1. `res://scripts/ai/perception_system.gd` — Añadir segundo rayo de verificación

**Riesgo:** Medio. Añade complejidad al LOS check y podría reducir la detección legítima en casos límite. Implementar como mejora opcional después de probar el Paso 3.1 y 3.2.

#### Paso 3.4: Postergar el LOS check hasta después de move_and_slide()

**Archivo a modificar:** `res://scripts/npc_base.gd` — `_physics_process()`

**Qué cambiar:**
- Mover la FASE 1 (percepción) para que ocurra DESPUÉS de la FASE 6 (move_and_slide), no antes.
- Esto asegura que el estado de las físicas esté completamente actualizado cuando se ejecute el RayCast3D.

**Por qué funciona:** Actualmente, la percepción ocurre antes de `move_and_slide()`. Aunque `force_raycast_update()` debería funcionar, moverlo después garantiza que todas las colisiones del frame anterior se hayan resuelto y los cuerpos estén en sus posiciones finales.

**Archivos a tocar:**
1. `res://scripts/npc_base.gd` — Reordenar el `_physics_process()`

**Riesgo:** Medio. Cambiar el orden de ejecución podría afectar la sincronización entre percepción y decisión. Si la percepción ocurre después del movimiento, el DecisionSystem usaría datos del frame anterior para la decisión. Alternativa: ejecutar percepción dos veces (antes y después), o simplemente confiar en `force_raycast_update()`.

✅ **Recomendación:** No cambiar el orden del `_physics_process()`. `force_raycast_update()` debería ser suficiente. Este paso es solo si los pasos 3.1-3.3 no resuelven el problema.

---

## Orden de implementación recomendado

### Fase 1: Problema 3 (Visión a través de paredes) — PRIORIDAD ALTA
Este es el problema más crítico porque afecta directamente a la jugabilidad (los bots hacen trampa).

| Paso | Archivo | Cambio | Riesgo |
|------|---------|--------|--------|
| 3.1 | `npc.tscn` | Añadir `hit_from_inside = true` en RaycastVision | Bajo |
| 3.2 | `npc.tscn` | Cambiar `collision_mask = 7` a `collision_mask = 15` | Bajo |
| 3.3 | `perception_system.gd` | Añadir segundo RayCast de verificación (opcional) | Medio |
| 3.4 | `npc_base.gd` | Reordenar physics process (solo si falla lo anterior) | Medio |

### Fase 2: Problema 1 (Bots atascados) — PRIORIDAD MEDIA

| Paso | Archivo | Cambio | Riesgo |
|------|---------|--------|--------|
| 1.3 | `npc.tscn` | Ajustar NavigationAgent3D (path_max_distance, avoidance) | Muy bajo |
| 1.1 | `movement_system.gd`, `npc.tscn` | Implementar RVO avoidance nativo | Bajo |
| 1.4 | `movement_system.gd` | Añadir sistema "cede el paso" | Bajo |
| 1.2 | `movement_system.gd` | Mejorar stuck recovery con raycasts laterales | Medio |

### Fase 3: Problema 2 (Saltos excesivos) — PRIORIDAD BAJA

| Paso | Archivo | Cambio | Riesgo |
|------|---------|--------|--------|
| 2.1 | `tactical_role.gd` | Reducir jump_frequency de todos los roles | Muy bajo |
| 2.2 | `movement_system.gd` | Eliminar salto automático en stuck recovery | Medio |
| 2.3 | `state_combat.gd`, `combat_system.gd` | Mover salto a sistema basado en eventos | Medio |

### Resumen de archivos a modificar

| Archivo | Pasos | Riesgo acumulado |
|---------|-------|-----------------|
| `res://scenes/npcs/npc.tscn` | 1.1, 1.3, 3.1, 3.2 | Bajo |
| `res://scripts/ai/movement_system.gd` | 1.1, 1.2, 1.4, 2.2 | Medio |
| `res://scripts/ai/perception_system.gd` | 3.3 | Medio |
| `res://scripts/ai/states/state_combat.gd` | 2.3 | Medio |
| `res://scripts/ai/combat_system.gd` | 2.3 | Medio |
| `res://scripts/tactical_role.gd` | 2.1 | Muy bajo |
| `res://scripts/npc_base.gd` | 3.4 (solo si necesario) | Medio |
| `res://scripts/ai/navigation/navigation_system.gd` | 1.1 (menor) | Bajo |

---

## Respaldo y seguridad

Antes de implementar cualquier cambio:

1. **Hacer backup de los archivos modificados** (Git o copia manual)
2. **Probar cada paso individualmente** antes de pasar al siguiente
3. **Usar el debug overlay** (`BotDebugOverlay`) para visualizar:
   - Estado FSM del bot
   - Stuck detection state
   - Enemigos visibles (debug de percepción)
4. **Configuración de prueba recomendada:**
   - Abrir `map_3.tscn`
   - Spawnear 2-3 bots en el equipo enemigo
   - El jugador debe poder moverse cerca de paredes y esquinas
   - Observar el comportamiento de los bots con el debug overlay activado

---

*Documento creado el 2026-07-01*
