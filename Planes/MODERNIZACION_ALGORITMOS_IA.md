# MODERNIZACIÓN DE ALGORITMOS UT99 — INGENIERÍA DE IA PARA GODOT 4.5

**Propósito:** Este documento toma cada algoritmo del Bot.uc de Unreal Tournament 1999, analiza qué preservar, qué eliminar, qué modernizar, y cómo implementarlo en Godot 4.5 manteniendo la sensación original pero con arquitectura limpia.

**Premisa:** No copiamos código. Copiamos comportamiento. La implementación es nueva, la sensación es vieja.

---

## 1. `SetEnemy()` — SELECCIÓN DE OBJETIVO

### 1.1 ¿Qué parte copiarías exactamente?

La **estructura jerárquica de decisión** y el concepto de **inercia de objetivo**:

```
1. ¿Es el mismo enemigo? → no hacer nada (estabilidad)
2. ¿Es inválido? → rechazar (filtro de entrada)
3. ¿Actitud? → Fear/Hate/Ignore/Friendly define el trato
4. Si ya tengo enemigo → comparar amenaza, no reemplazar sin razón
5. Si no tengo enemigo → aceptar inmediato
```

Copiar también:
- **El concepto de OldEnemy**: guardar el enemigo anterior para recuperar contexto.
- **La cascada social en team games**: un bot adopta el enemigo de un compañero.
- **El filtro de entrada**: NewEnemy == Self, Health <= 0, FlockPawn -> rechazar.
- **La actualización de LastSeenPos/LastSeenTime/LastSeeingPos** al cambiar de enemigo.

### 1.2 ¿Qué parte eliminarías?

- **El manejo de Friendly dentro de SetEnemy**: La lógica de "si es friendly, toma su enemigo" es responsabilidad del sistema de comunicación entre bots, no de SetEnemy. SetEnemy debe decidir si ACEPTA un enemigo, no DERIVARLO de un amigo.
- **La asignación directa de `OldEnemy = NewEnemy` cuando el nuevo no es aceptado**: Esto es un side-effect oculto. OldEnemy debería solo actualizarse cuando realmente hay un cambio de enemigo, no como "rechazo storage".
- **La dependencia directa de `AttitudeTo()` hacia el GameMode**: AttitudeTo es un concepto de política del juego, la IA debería recibir la actitud como input, no calcularla.
- **El manejo de `bNotSeen`**: Es un hack para compartir información visual entre bots. Debe ser reemplazado por un sistema de comunicaciones dedicado.

### 1.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Inercia progresiva en lugar de penalización plana**: En lugar de un -0.2 fijo para el nuevo enemigo, usar una curva: cuanto más tiempo ha estado el bot enfocado en el enemigo actual, más penalización hay para cambiar. Esto evita "enemy switching" frívolo pero permite cambios rápidos al inicio del combate.

- **Threshold de compromiso por salud del enemigo**: Si el enemigo actual tiene menos de 30 HP, multiplicar la inercia por 3x. El bot debe rematar, no distraerse.

- **Evaluación de daño recibido**: Si el enemigo actual me acaba de infligir daño (últimos 2 segundos), gana un bonus de amenaza significativo. Esto crea comportamiento de "venganza" y hace que el bot responda a quien le dispara, no al primero que ve.

- **Prioridad por arma visible**: Integrar el tipo de arma que el enemigo está sosteniendo visiblemente. Un Rocket Launcher visible a media distancia es más amenazante que un Sniper Rifle a la misma distancia (porque el rocket no necesita línea de visión continua).

### 1.4 ¿Qué parte reemplazarías completamente?

- **La comparación directa `AssessThreat(NewEnemy) > AssessThreat(Enemy)`**: Reemplazar por un **sistema de puntuación multi-factor con pesos configurables**. Cada factor (distancia, salud, daño recibido, arma, tiempo de compromiso) tiene un peso. La puntuación final es una suma ponderada. Esto permite ajustar finamente qué tan "inercial" es el bot sin cambiar la lógica.

- **El concepto de OldEnemy único**: Reemplazar por una **cola de últimos N enemigos** (tamaño configurable, default 3). El bot recuerda los últimos enemigos. Si el actual muere, puede evaluar cuál de los recientes es más relevante, no solo el inmediato anterior.

### 1.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug del enemigo con 1 HP ignorado**: RelativeStrength promedia la salud del enemigo con su salud máxima. Un enemigo con 1 HP de 100 se evalúa como `0.5*(1+100)=50.5`. El bot NO lo ve como débil y no remata. Esto es un bug de diseño, no de implementación.

- **Bug de OldEnergy overwrite**: Si el bot tiene OldEnemy y recibe un nuevo candidato que NO supera al enemigo actual, SOBREESCRIBE OldEnemy con el candidato rechazado. Esto significa que si había un OldEnemy importante, se pierde silenciosamente.

- **Bug de team game con Friendly sin enemigo**: Si un compañero friendly no tiene enemigo, SetEnemy retorna false sin actualizar nada. El bot que pidió ayuda se queda sin respuesta.

- **Bug de LastSeenTime con bNotSeen**: Cuando el bot adopta el enemigo de un compañero (bNotSeen), usa `Friend.LastSeenTime`, pero el enemigo podría haberse movido. El bot persigue una posición desactualizada.

### 1.6 ¿Cómo evitarías esos bugs?

- **No promediar salud en RelativeStrength**: La evaluación de amenaza debe usar la salud ACTUAL del enemigo, no un promedio. Un enemigo con 1 HP es 1 HP. Punto.
- **OldEnemy como pila, no como slot único**: Array de máximo 3 enemigos recientes. Push cuando hay cambio. Pop cuando el actual muere.
- **Comunicación entre bots usando signals**: En lugar de que SetEnemy maneje la lógica de "amigo me pasó su enemigo", usar un sistema de `team_spotting` donde los bots comparten posiciones de enemigos detectados a través de un canal de comunicación.
- **Timestamp asociado a cada posición conocida**: LastSeenPos siempre viaja con su timestamp. El bot sabe si la posición tiene 0.5s o 5s de antigüedad y puede decidir si ir allí o no.

### 1.7 ¿Cómo lo implementarías usando Godot 4.5?

- `DecisionSystem` es el único propietario de `target_entity`.
- `DecisionSystem` expone un método `evaluate_target_candidates(candidates: Array[EntitySighting]) -> EntitySighting` que implementa toda la lógica de SetEnemy modernizada.
- `PerceptionSystem` produce `EntitySighting` (entity, position, health, weapon_visible, timestamp, confidence) y se los pasa a DecisionSystem.
- `MemorySystem` mantiene el **enemy_history: Array[EntityRecord]** con los últimos N enemigos.
- `TargetEvaluationSystem` (subsistema dentro de DecisionSystem) calcula la puntuación multi-factor usando un **Resource de configuración** (`TargetEvaluationProfile`) con pesos exportables.
- El GameMode inyecta la actitud (Fear/Hate/Ignore) a través de signals, no por consulta directa.
- Godot 4.5 permite usar `@export var target_weights: TargetEvaluationProfile` para ajustar desde el Inspector.

### 1.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **Inercia calibrada para que se sienta como UT99**: El peso del "tiempo de compromiso" debe calibrarse para que, en promedio, el bot cambie de enemigo con la misma frecuencia que en UT99. Esto se logra con playtesting y ajuste de pesos.
- **OldEnemy como pila de 1 por defecto** (configurable a 3). Para mantener la sensación exacta, configurar tamaño 1.
- **Penalización plana de -0.2 al nuevo enemigo** como valor por defecto en TargetEvaluationProfile, con opción de cambiarlo a inercia progresiva.
- **La cascada social** se mantiene pero a través de `team_spotting` channel, no dentro de SetEnemy. El bot recibe un "enemy_spotted" event y lo evalúa igual que si él mismo lo hubiera visto.

---

## 2. `AssessThreat()` — EVALUACIÓN DE AMENAZA

### 2.1 ¿Qué parte copiarías exactamente?

- **El concepto de múltiples factores combinados**: Amenaza no es una sola métrica. Es la combinación de fuerza relativa, distancia, salud, y modificadores de contexto.
- **El modificador de SpecialPause +5**: La idea de que ciertos estados del bot deben ser "interrumpibles" es excelente. Un bot que está haciendo una maniobra especial DEBE reaccionar a nuevas amenazas.
- **El bonus por enemigo con poca salud (+0.3)**: Priorizar rematar enemigos heridos es un instinto correcto.
- **El bonus por cercanía (+0.3 si distancia < 800)**: La inmediatez geográfica es un factor real de amenaza.
- **La penalización de estabilidad cuando el enemigo actual no es visible (-0.25 si el nuevo está más lejos, -0.2 plano)**: Correcto. No abandonar una persecución por una distracción.
- **El modificador por PlayerPawn**: Diferenciar entre bots y humanos es un detalle fino que mejora la experiencia.

### 2.2 ¿Qué parte eliminarías?

- **Los cortes duros de distancia (800, 1200)**: Reemplazar con funciones continuas. Un enemigo a 799 unidades no debería ser drásticamente diferente que uno a 801.
- **El corte duro de salud (< 20)**: Reemplazar con una curva continua. Un enemigo con 25 HP no debería ser completamente diferente a uno con 19 HP.
- **El hack de SpecialPause +5 como entero directo**: Es efectivo pero frágil. Debería ser una "interrupción por prioridad" explícita.
- **La dependencia directa de `LineOfSightTo(Enemy)` dentro de AssessThreat**: AssessThreat evalúa amenazas, no debería hacer raycasts. La línea de visión debe venir precalculada de PerceptionSystem.

### 2.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Funciones de decaimiento continuo en lugar de cortes**:
  - Distancia: `threat_distance = exp(-dist^2 / sigma^2)` en lugar de `if dist < 800`
  - Salud: `threat_health = 1.0 - (health / max_health)` en lugar de `if health < 20`
  - Ambas se multiplican por pesos, no se suman como valores planos.

- **Factor de daño recibido histórico**: Si el enemigo me ha infligido daño en los últimos 3 segundos, la amenaza escala con el daño total recibido. Esto hace que el bot responda a quien le está disparando activamente.

- **Factor de DPS estimado**: Usar `WeaponAIProfile.rate_self(distance_to_target)` para estimar cuánto daño puede hacer el enemigo por segundo a esta distancia. Un Rocket Launcher a 200 unidades tiene alto DPS. Un Sniper Rifle a 200 tiene bajo.

- **Factor de precisión del enemigo**: Si el enemigo es un bot con alta precisión (skill alto), la amenaza debe escalar. Si es un novato, la amenaza baja.

- **Factor de visibilidad mutua**: Si el enemigo PUEDE verme (línea de visión desde su posición a la mía), la amenaza es mayor que si NO puede verme (incluso si yo puedo verlo).

### 2.4 ¿Qué parte reemplazarías completamente?

- **La fórmula lineal `ThreatValue = FMax(0, NewStrength) + sum(bonuses)`**: Reemplazar por un **sistema de pesos multiplicativos**. Amenaza base = RelativeStrength. Luego se multiplica por factores (distancia, salud, daño recibido, etc.) cada uno con su propio peso y curva. Esto permite que factores extremos (enemigo con 1 HP a 50 unidades que me está disparando) tengan más impacto que la suma lineal permitiría.

- **El modificador de PlayerPawn (±0.15)**: Reemplazar por un perfil de habilidad que evalúa al enemigo basado en su desempeño observado (kills, precisión, movimientos). Un humano que lleva 10 kills merece más amenaza que uno que lleva 0.

### 2.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug del corte de 800**: Si dos enemigos están a 799 y 801 unidades respectivamente, el de 799 recibe +0.3 y el de 801 no. La diferencia es imperceptible para el jugador pero el bot los trata como casos radicalmente diferentes.
- **Bug de SpecialPause**: Si el bot entra en SpecialPause mientras evalúa amenazas y aparece cualquier enemigo, el +5 lo fuerza a cambiar siempre, incluso si el nuevo enemigo es irrelevante (ej: un espectador o un enemigo al otro lado del mapa).
- **Bug de ThreatValue negativa**: `FMax(0, NewStrength)` convierte fuerzas negativas en 0, pero luego se suman +0.3, +0.3, etc. Esto significa que un enemigo MUCHO más débil que el bot puede terminar con ThreatValue positiva solo por estar cerca y tener poca salud, cuando en realidad no es una amenaza real.
- **Bug de GameThreatAdd sin control**: El GameMode puede añadir cualquier valor a la amenaza, sin límite. Un GameMode mal implementado puede hacer que el bot cambie de enemigo por razones de game design (ej: "este enemigo tiene la bandera") pero sin visibilidad ni contexto.

### 2.6 ¿Cómo evitarías esos bugs?

- **Funciones continuas**: Implementar `distance_factor = smoothstep(0, 2000, dist)` con curva de usuario. No hay cortes, no hay bordes.
- **SpecialPause como prioridad explícita**: No es un +5 numérico. Es un flag `interrupt_priority` que el sistema de evaluación respeta: si el bot está en SpecialPause, solo interrumpe para amenazas con severidad > UMBRAL_ALTO.
- **Amenaza base nunca negativa, pero factores multiplicativos**: Si el enemigo es mucho más débil, `distance_factor * health_factor * weapon_factor` se multiplica por 1.0 (neutral) o menos. Un enemigo débil pero cercano puede ser una molestia, pero no una amenaza de muerte.
- **GameThreatAdd con límite**: El GameMode puede aportar hasta ±0.5 a la amenaza, no cualquier valor. Si necesita más, debe cambiar el estado del bot directamente, no manipular la evaluación.

### 2.7 ¿Cómo lo implementarías usando Godot 4.5?

- `ThreatEvaluator` como un **Node separado** dentro de DecisionSystem. Toma inputs de PerceptionSystem (sightings) y produce puntuaciones.
- Usar **Curve resources** de Godot para los factores de distancia y salud:
  - `@export var distance_threat_curve: Curve` — define cómo la distancia afecta la amenaza
  - `@export var health_threat_curve: Curve` — define cómo la salud del enemigo afecta
  - `@export var damage_received_weight: float` — peso del daño recibido
  - `@export var commitment_inertia: float` — penalización por cambiar de objetivo
- Usar **Callables** para que el GameMode inyecte modificadores personalizados sin romper la encapsulación.
- El sistema de **DamageHistory** de HealthSystem alimenta el factor de daño recibido.
- WeaponSystem expone `estimate_dps(weapon_type: String, distance: float) -> float` para que ThreatEvaluator pueda usarlo.

### 2.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **Calibrar las curvas para emular los cortes originales**: La `distance_threat_curve` debe valer ~0.3 en distancia=800 y ~0 en distancia=1200, replicando el comportamiento de cortes pero con transiciones suaves.
- **El peso total de la amenaza debe operar en el mismo rango que UT99**: 0.0 a ~2.0, para que las decisiones de SetEnemy se comporten igual.
- **El factor de "nuevo enemigo" debe sumar aproximadamente -0.45** (como en UT99: -0.25 por distancia y -0.2 plano) para mantener la misma inercia.
- **El perfil de dificultad debe escalar los mismos factores**: bots novatos ignoran más el daño recibido, bots hábiles ponderan más el arma del enemigo.

---

## 3. `RelativeStrength()` — PODER RELATIVO

### 3.1 ¿Qué parte copiarías exactamente?

- **El concepto de que el poder es una combinación de vida + arma + posición**: Los tres factores son correctos.
- **La idea de que el arma tiene un `RateSelf()` que el arma misma define**: El arma conoce su propia efectividad. Esto permite que armas personalizadas tengan IA sin modificar el bot.
- **El factor de altura (Z)**: Estar más alto o más bajo que el enemigo es un factor táctico real. La implementación es simple pero el concepto es sólido.
- **El rango de salida**: -1.0 a 1.0 es perfecto para un sistema de decisión basado en umbrales probabilísticos.
- **El concepto de DamageScaling por dificultad**: Bots más hábiles son más efectivos con sus armas.

### 3.2 ¿Qué parte eliminarías?

- **El promedio de salud del enemigo (`0.5 * (Other.health + Other.Default.Health)`)**: Es un bug. La salud actual es la salud actual. No hay razón para promediar con la máxima.
- **La penalización fija por tener AIRating < 0.5 (+0.3, +0.35)**: No es que el arma sea mala; es que el arma no es la ideal para esta situación. RateSelf ya debería devolver un valor bajo si el arma es inapropiada para el contexto.
- **El corte de 400 unidades para altura**: Reemplazar con función continua. 399 unidades no es diferente a 401.

### 3.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Incluir armadura**: La armadura en UT99 absorbía 60% del daño. RelativeStrength debe calcular `effective_health = health + armor * 0.6` para ambos lados.
- **Incluir munición**: Si el bot tiene Rocket Launcher pero 0 cohetes, el arma no contribuye a su fuerza. WeaponSystem debe exponer `has_ammo() -> bool`.
- **Distancia de efectividad del arma**: Una escopeta a 500 unidades no es efectiva. RateSelf debe aceptar la distancia como parámetro: `RateSelf(distance_to_enemy)`.
- **Factor de estado del arma**: Si el arma está recargando o en cooldown, no contribuye a la fuerza.
- **Factor de DPS sostenido**: En lugar de AIRating como valor fijo, calcular DPS real considerando: daño por disparo × cadencia × precisión del bot × probabilidad de acierto a esta distancia.
- **Factor de habilidades especiales**: Si el bot tiene Translocator, o puede hacer saltos con splash damage, estos son multiplicadores de poder.
- **Altura con dirección**: Estar más alto que el enemigo es ventajoso si tienes un arma de proyectil (puedes disparar hacia abajo). Es menos ventajoso si tienes un arma hitscan.

### 3.4 ¿Qué parte reemplazarías completamente?

- **La fórmula lineal plana**: Reemplazar por un **modelo de poder efectivo**:

```
self_power = effective_health * weapon_dps(distance) * situational_modifiers
enemy_power = enemy_effective_health * enemy_weapon_dps(distance) * enemy_situational_modifiers
relative_strength = clamp((enemy_power - self_power) / (enemy_power + self_power + EPSILON), -1, 1)
```

Esta fórmula produce un valor entre -1 y 1, igual que UT99, pero basado en poder efectivo real, no en sumas arbitrarias. Cuando ambos son iguales, da 0. Cuando uno es el doble de poderoso, da ~0.33. Cuando uno es 10x más poderoso, da ~0.82.

### 3.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug del enemigo con 1 HP**: Ya documentado. El promedio hace que enemigos casi muertos se vean como saludables.
- **Bug del arma sin munición**: RateSelf no considera munición. Un bot con Rocket Launcher vacío se evalúa como poderoso.
- **Bug de la altura inversa**: Si el enemigo está más alto, el bot se considera MÁS fuerte (compare -= 0.15). En realidad, tener la altura es una ventaja, no una desventaja. Esto está al revés en muchos contextos.
- **Bug de DamageScaling no recíproco**: DamageScaling del bot afecta cómo evalúa su propia arma, pero el DamageScaling del enemigo también afecta. Si ambos tienen el mismo scaling, el efecto se cancela, pero si uno es bot novato y otro veterano, el cálculo se desbalancea.
- **Bug de armas con AIRating = 0.5**: Un arma con AIRating exactamente 0.5 no activa ninguna penalización ni bonificación. El arma es "neutral" incluso si es muy diferente en poder real.

### 3.6 ¿Cómo evitarías esos bugs?

- **Usar salud real, no promediada**: `adjustedOther = Other.health`
- **WeaponSystem debe exponer `effective_power(distance: float, ammo_remaining: int) -> float`**: La munición es parte del cálculo.
- **Altura contextual**: La ventaja de altura depende del arma. Un Rocket Launcher desde arriba es devastador. Un Minigun desde arriba es igual que desde abajo. WeaponAIProfile debe incluir `height_advantage_multiplier: float`.
- **DamageScaling como modificador de DPS, no como factor lineal**: El skill del bot debe multiplicar su DPS efectivo, no sumarse a una comparación.
- **AIRating abolido**: Reemplazar por `effective_dps()` y `situational_rating()`. Cada arma sabe su poder en cada situación.

### 3.7 ¿Cómo lo implementarías usando Godot 4.5?

- `CombatSystem` (o un `PowerEvaluator` subsistema) calcula `relative_strength`.
- **WeaponAIProfile Resource** tiene:
  - `@export var base_dps: float` — daño por segundo base
  - `@export var optimal_range_min: float`
  - `@export var optimal_range_max: float`
  - `@export var height_advantage: float` (-1.0 mejor desde abajo, +1.0 mejor desde arriba)
  - `@export var splash_dps_bonus: float` — multiplicador cuando el enemigo está en espacio cerrado
  - `func effective_dps(distance: float, ammo_ratio: float, height_delta: float) -> float`
- **HealthSystem** expone `effective_health: float` (health + armor * absorption_rate).
- El resultado `relative_strength` se almacena en `DecisionSystem` como variable evaluada cada N frames (no cada frame, para optimización).
- Godot 4.5 permite usar `@export_tooltip` para documentar cada peso en el Inspector.

### 3.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **La escala de salida debe ser idéntica**: -1 a 1. Un valor de 0.3 debe significar "el enemigo es moderadamente más fuerte" como en UT99.
- **El perfil de dificultad debe revertir a los valores de UT99**: skill=0-3, con los mismos multiplicadores de DamageScaling y precisión.
- **La altura debe tener el mismo peso que en UT99**: ~0.15 de impacto en el resultado final, pero con la dirección corregida (estar más alto es ventaja, no desventaja).
- **Las armas deben RateSelf() igual que en UT99** para que la sensación sea la misma, pero RateSelf internamente debe usar los nuevos cálculos de DPS y distancia.

---

## 4. `ChooseAttackMode()` — SELECCIÓN DE MODO DE ATAQUE

### 4.1 ¿Qué parte copiarías exactamente?

- **TODO EL ÁRBOL DE DECISIÓN**. Es casi perfecto. La secuencia es:

```
1. ¿Todavía existe el enemigo? (si no, salir)
2. ¿Tengo arma? (si no, conseguir una)
3. [TeamGame] ¿Hay atracción especial del modo de juego?
4. ¿Actitud? Fear → Retreat. Friendly → Salir.
5. ¿Enemigo visible?
   - No → ¿Intercambiar con OldEnemy? ¿Cazar? ¿Esperar?
   - Sí → TacticalMove (por defecto)
```

Este orden es lógico, cubre todos los casos, y es difícil de mejorar en estructura.

- **El intercambio Enemy/OldEnemy cuando el enemigo se pierde de vista**: Elegante solución para no perder el contexto.
- **La separación Hunting vs StakeOut basada en distancia y sniper status**: Correcta. Bots agresivos cazan, bots pasivos/snipers esperan.
- **La llamada a FindSpecialAttractionFor()**: Permite al GameMode inyectar objetivos override.
- **El concepto de bMustHunt**: Un flag externo puede forzar a Hunting aunque las condiciones normales digan StakeOut. Permite que otros sistemas (daño recibido, orden de equipo) overrideen la decisión.

### 4.2 ¿Qué parte eliminarías?

- **La dependencia de `LineOfSightTo(Enemy)` dentro de ChooseAttackMode**: La línea de visión debe venir precalculada de PerceptionSystem, no calcularse en el momento de la decisión.
- **El chequeo de `Weapon == None`**: Debe ser responsabilidad de otro sistema asegurar que el bot siempre tenga arma antes de llegar a ChooseAttackMode.
- **La redundancia de llamar `FindSpecialAttractionFor()` dos veces** (una al inicio, otra dentro del bloque de enemigo no visible): Una sola llamada al inicio es suficiente.
- **El seteo de `Target = Enemy`**: Target no debería existir como variable separada. El sistema de combate debe usar `target_entity` directamente.

### 4.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Probabilidad basada en personalidad en lugar de FRand() puro**: La decisión Hunting vs StakeOut usa `FRand() * RelativeStrength(Enemy) - CombatStyle) * 600`. Esto es correcto pero puede refinarse: usar una **distribución normal** centrada en el valor de CombatStyle, no uniforme. Esto hace que bots con CombatStyle=0.7 carguen ~70% del tiempo, no que tengan 70% de probabilidad plana.

- **Evaluación de cansancio/tiempo en estado**: Si el bot ha estado en TacticalMove por más de 8 segundos sin progreso visible (no ha infligido daño, no se ha acercado), debería considerar cambiar a Hunting (flanquear) o Retreating (reagruparse). En UT99, un bot puede quedarse en TacticalMove indefinidamente strafeando.

- **Evaluación de cobertura disponible**: Antes de decidir TacticalMove, el bot debería saber si HAY cobertura cerca. Si no hay cobertura, TacticalMove es menos efectivo y debería preferir Charging o RangedAttack.

- **Evaluación de recursos del equipo**: En team games, un bot con poca vida y arma débil no debería cazar (Hunting) aunque el enemigo esté lejos y sea visible. Debería preferir StakeOut o buscar a un compañero.

- **Memoria de fracaso**: Si el bot intentó Hunting hacia esta posición hace 30 segundos y no encontró al enemigo, debería evitar cazar al mismo lugar otra vez.

### 4.4 ¿Qué parte reemplazarías completamente?

- **La llamada directa a `GotoState('Retreating')`**: Reemplazar por un **sistema de transición de estados con validación**. Antes de transicionar, el sistema verifica que el estado destino puede manejar la situación actual. Si Retreating no tiene un destino válido (no hay pickup reachable), el bot debería poder abortar la transición y elegir otra opción.

- **El manejo de `bWillHunt`**: Reemplazar por un **sistema de prioridades con contexto**. En lugar de un flag binario, usar una pila de intenciones. El bot puede tener intención de "cazar a X" y "recoger salud" simultáneamente, y el estado Hunting puede integrar ambas.

### 4.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug de ChooseAttackMode loop infinito**: Si ChooseAttackMode llama a WhatToDoNext(), y WhatToDoNext() vuelve a Attacking, y Attacking llama a ChooseAttackMode otra vez, puede haber loops de estado si no hay enemigo válido. UT99 manejaba esto con `bMustHunt` reseteándose, pero hay casos donde el bot entra en un ciclo Attacking → ChooseAttackMode → WhatToDoNext → Attacking.

- **Bug de sniper que nunca caza**: Si un bot sniper pierde de vista al enemigo y el enemigo está a distancia media, el sniper elige StakeOut pero el enemigo nunca vuelve a aparecer. El sniper se queda esperando indefinidamente porque no hay timeout en StakeOut para sniper (solo para no-snipers).

- **Bug de OldEnemy intercambiado pero no actualizado**: Cuando ChooseAttackMode intercambia Enemy y OldEnemy (líneas 3985-3987), no actualiza LastSeenPos/LastSeenTime para el nuevo enemigo. El bot puede tener información de posición incorrecta.

- **Bug del Weapon == None**: Si el bot no tiene arma en ChooseAttackMode, llama SwitchToBestWeapon() pero no verifica si realmente obtuvo una. Si no hay armas en el mapa, el bot entra en TacticalMove sin arma, causando comportamientos erráticos.

### 4.6 ¿Cómo evitarías esos bugs?

- **Transiciones de estado con guard clause**: Cada transición debe verificar una precondición. `can_enter_state(state_name) -> bool`. Si no se cumple, el bot no transiciona.
- **StakeOut con timeout global**: Incluso para snipers, si pasan X segundos sin ver al enemigo, forzar transición a Hunting o WhatToDoNext.
- **Actualización de LastSeenPos al intercambiar enemigos**: Cualquier intercambio Enemy/OldEnemy debe refrescar LastSeenPos del nuevo enemigo activo.
- **SwitchToBestWeapon() con validación**: Si después de llamarlo el bot sigue sin arma, debe priorizar buscar un arma (ir a un weapon pickup) antes de entrar en combate.

### 4.7 ¿Cómo lo implementarías usando Godot 4.5?

- **DecisionSystem** contiene una **FSM formal** con estados como nodos hijos:
  - `StateRetreating`, `StateHunting`, `StateStakeOut`, `StateTacticalMove`, `StateCharging`, `StateRangedAttack`
  - Cada estado tiene:
    - `func get_transition_conditions() -> Array[TransitionCondition]`
    - `func enter()`, `func exit()`, `func update(delta)`
    - `func can_enter(context: DecisionContext) -> bool`
  - `ChooseAttackMode()` es reemplazado por `StateAttacking.update()` que evalúa transiciones.
- **PerceptionSystem** actualiza `last_seen_positions: Dictionary[entity_id, PositionRecord]` que la FSM consulta.
- **ObjectiveSystem** expone `get_special_attraction(bot_id: int) -> ObjectiveOverride` que puede forzar un cambio de estado.
- Godot 4.5 permite usar **@icon** en los estados de la FSM para visualizar el árbol en el editor.

### 4.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **La secuencia de decisión debe ser idéntica**: Fear → Retreat, Friendly → Ignore, No visible → (Hunting o StakeOut), Visible → TacticalMove. El orden y las condiciones son sagradas.
- **Los umbrales deben ser configurables pero con defaults de UT99**: Por defecto, `600 + (FRand() * RelativeStrength - CombatStyle) * 600` es la fórmula exacta, pero implementada como expresión configurable.
- **CombatStyle y Aggressiveness como variables de perfil**: Exactamente los mismos rangos y efectos que en UT99.
- **La FSM debe soportar el mismo patrón de "ignores SeePlayer"**: Ciertos estados deben ignorar ciertos estímulos sensoriales para evitar loops. En Godot, esto se logra con flags en cada estado: `ignored_stimuli: Array[StimulusType]`.

---

## 5. `PickDestination()` — SELECCIÓN DE DESTINO

### 5.1 ¿Qué parte copiarías exactamente?

- **La priorización por deseabilidad/distancia**: `BotDesireability / VSize(Inv.Location - Location)` es una fórmula simple y efectiva para ordenar objetivos.
- **La separación de PickDestination por estado**: Cada estado tiene SU versión de PickDestination porque las prioridades cambian según el contexto. Retreating busca salud. TacticalMove busca flanqueo. Roaming busca exploración.
- **El cooldown de búsqueda (LastInvFind)**: No evaluar inventario cada frame. Solo cada (3 - 0.5*skill) segundos. Esto evita micro-oscillaciones en la decisión.
- **TryToward() con verificación de reachabilidad**: Antes de comprometerse con un destino, verificar con trace que se puede llegar. Esto evita que el bot intente caminar hacia un pickup al otro lado de una pared.
- **PickRegDestination() con strafe vector**: Calcular destino como combinación de movimiento hacia el enemigo y movimiento lateral, ponderado por Aggression.
- **El sistema de segundo mejor (SecondInv, SecondWeight)**: Si el mejor destino falla, tener un backup listo sin re-evaluar.

### 5.2 ¿Qué parte eliminarías?

- **El corte de altura en la búsqueda de inventario**: `Inv.Location.Z < FMin(Location.Z, Enemy.Location.Z) - CollisionHeight` — esto excluye pickups que están en plataformas más altas. Es una limitación artificial que hace que los bots ignoren powerups importantes.
- **La restricción de "visiblecollidingactors"**: Limita la búsqueda a lo que el bot puede ver directamente. Un pickup detrás de una esquina pero reachable no se considera. Debería usar el sistema de navegación.
- **El manejo de bGathering**: Es un flag que evita distracciones, pero su implementación es frágil (se resetea en PickDestination, no cuando el bot llega al destino).
- **Las variables globales Home y SpecialGoal**: Son redundantes con un sistema de objetivos bien diseñado.

### 5.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Búsqueda usando NavigationServer3D en lugar de actores visibles**: En lugar de `visiblecollidingactors`, usar `NavigationServer3D.map_get_path()` para encontrar rutas a pickups. El bot sabe si un pickup es reachable aunque no sea visible.

- **Deseabilidad dinámica con contexto de equipo**: Si un compañero está más cerca de un health pack, el bot debe priorizar otro. La deseabilidad debe ajustarse basada en las necesidades del equipo, no solo individuales.

- **Strafe vector con predicción de movimiento del enemigo**: En lugar de calcular strafe basado en la posición actual del enemigo, predecir su posición futura (considerando su velocidad y dirección). Esto hace que el strafe evite anticipadamente los rockets.

- **Evaluación de peligro del destino**: Antes de elegir un destino, evaluar si está en línea de visión del enemigo. Si lo está, es un destino peligroso. El bot debería preferir destinos que NO sean visibles al enemigo.

- **Pathfinding con costo táctico**: Asignar costo adicional a NavigationPolygons que están expuestos al enemigo. Así el pathfinding naturalmente evita rutas peligrosas.

### 5.4 ¿Qué parte reemplazarías completamente?

- **FindBestInventoryPath()**: Reemplazar por un **sistema de objetivos basado en utilidad** que considera:
  1. Distancia de navegación real (no lineal)
  2. Deseabilidad del item
  3. Peligro del camino (exposición al enemigo)
  4. Necesidad del equipo
  5. Tiempo estimado de llegada
  6. Probabilidad de que el item siga allí cuando llegue

- **PickLocalInventory()**: Reemplazar por un **sistema de sondeo de NavigationPoints con InventorySpot**. En lugar de buscar actores visibles, el bot consulta los NavigationPoints cercanos que tienen inventario asociado.

### 5.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug de pickup inalcanzable pero visible**: Si un pickup es visible pero está en una plataforma inalcanzable (ej: al otro lado de un abismo), el bot lo marca como destino y camina hacia la pared.
- **Bug de SecondInv no verificado**: Si SecondInv no es reachable pero BestInv sí, el código intenta BestInv y si falla, prueba SecondInv sin verificar. Pero si SecondInv tampoco es reachable, el bot se queda sin destino.
- **Bug de bGathering persistente**: Si el bot entra en TacticalMove con bGathering=true y luego el pickup desaparece, bGathering sigue siendo true, evitando que el bot busque nuevos pickups hasta que PickDestination lo resetea.
- **Bug de LastInvFind en Retreating**: El timer de búsqueda se resetea pero la búsqueda solo considera inventario en un rango de altura limitado. Si todos los pickups están en altura, el bot nunca encuentra nada y eventualmente entra en bKamikaze.

### 5.6 ¿Cómo evitarías esos bugs?

- **Reachabilidad por navegación, no por línea de visión**: Usar NavigationServer3D para verificar si el destino es reachable. No confiar en traces.
- **Backup chain**: Guardar una lista ordenada de candidatos, no solo primero y segundo. Si falla el primero, probar el segundo, luego el tercero, etc.
- **bGathering como parte del MovementCommand**: El MovementCommand tiene un flag `is_gathering` que se resetea cuando el bot llega al destino o cuando recibe un nuevo comando. No es una variable global persistente.
- **Búsqueda en 3D real**: No filtrar por altura Z. Usar la navegación del mapa para determinar si un pickup es alcanzable.

### 5.7 ¿Cómo lo implementarías usando Godot 4.5?

- **GoalEvaluator** (subsistema de DecisionSystem): Evalúa todos los posibles destinos y produce un `MovementCommand` con el mejor.
- **WorldState** (consolidación de PerceptionSystem + MemorySystem): Proporciona una vista unificada de pickups conocidos, posiciones de enemigos, y puntos de interés.
- **NavigationServer3D** para reachabilidad: `NavigationServer3D.map_get_path(map, from, to, true).size() > 0` para verificar si un destino es reachable.
- **GoalWeights Resource**: Configuración de pesos para cada tipo de objetivo:
  - `health_pickup_weight: float`
  - `weapon_pickup_weight: float`
  - `armor_pickup_weight: float`
  - `ammo_pickup_weight: float`
  - `enemy_flanking_weight: float`
  - `team_objective_weight: float`
- Cada estado registra sus propios GoalWeights con el GoalEvaluator al entrar.

### 5.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **GoalEvaluator debe producir resultados equivalentes a PickDestination de UT99** para los mismos inputs. Las diferencias solo deben aparecer cuando la nueva información (reachabilidad real, peligro) cambia la decisión.
- **La frecuencia de re-evaluación debe ser la misma**: Cada (3 - 0.5*skill) segundos en combate, igual que el LastInvFind timer.
- **El orden de prioridad debe ser idéntico**: 1) Objetivos del modo de juego 2) Inventario cercano 3) Inventario lejano 4) Flanqueo táctico 5) Movimiento aleatorio.
- **El strafe vector en PickRegDestination debe ser el mismo**: La fórmula `2 * (CombatStyle + FRand()) - 1.1` debe reproducirse exactamente.

---

## 6. `TacticalMove()` — MOVIMIENTO TÁCTICO

### 6.1 ¿Qué parte copiarías exactamente?

- **El strafe vector**: La combinación de componente hacia el enemigo (`enemyPart`) y componente lateral (`pickdir`) ponderado por Aggression. Es un sistema elegante y simple.
- **La alternancia de dirección (bStrafeDir)**: Alternar el lado del strafe cada vez. Esto evita que el bot sea predecible sin necesidad de estado complejo.
- **RecoverEnemy**: El comportamiento de "asomarse, disparar, cubrirse" es la joya del movimiento táctico de UT99. Copiar:
  1. Guardar HidingSpot
  2. Moverse a LastSeeingPos
  3. Disparo rápido (bQuickFire)
  4. Volver a HidingSpot con cierta probabilidad
  5. Repetir
- **GiveUpTactical()**: Si no hay destino válido, no quedarse paralizado. Transicionar a Charging o RangedAttack.
- **El Timer que decide cuándo disparar**: No disparar cada frame. Esperar un timer. Si el timer se activa Y hay línea de visión, pasar a RangedAttack.
- **FearThisSpot()**: Capacidad de modificar el destino para alejarse de un punto peligroso (usado por otros bots que piden ayuda).

### 6.2 ¿Qué parte eliminarías?

- **El uso de `bAdvancedTactics` y `AlterDestination()`**: Modificar el destino con un cross product es un hack. El strafe vector ya proporciona movimiento lateral. No necesita modificación adicional.
- **El manejo de bGathering dentro de TacticalMove**: bGathering debe ser parte del sistema de objetivos, no un flag global que TacticalMove tiene que verificar.
- **La duplicación de lógica TryToward** (existe en TacticalMove y en Hunting). Debe ser una función compartida.
- **El chequeo constante de `bCanFire`**: Debería determinarse al entrar al estado, no verificarse múltiples veces.

### 6.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Strafing predictivo**: En lugar de strafe basado en la posición actual del enemigo, predecir dónde estará cuando el bot llegue al destino. Usar `enemy.velocity * estimated_time_to_reach` para ajustar el strafe. Esto hace que el bot evite cohetes antes de que sean disparados.

- **Ducking/evasión contextual**: UT99 tiene TryToDuck() con probabilidad fija del 35%. Mejora: detectar si el enemigo está apuntando al bot (dentro de un cono de error) y hacer duck en ese momento, no aleatoriamente.

- **Cobertura dinámica**: En lugar de guardar HidingSpot como un vector, identificar nodos de navegación cercanos que NO estén en línea de visión del enemigo. El bot se mueve entre puntos de cobertura, no a puntos arbitrarios.

- **Strafing adaptable al arma del enemigo**:
  - Si el enemigo usa Rocket Launcher → strafe lateral amplio e impredecible, con cambios bruscos de dirección.
  - Si el enemigo usa Minigun/Shock Rifle → strafe más pequeño pero con ducking frecuente.
  - Si el enemigo usa Sniper Rifle → movimiento vertical (saltos) y cobertura.

- **Pathfinding táctico**: En lugar de mover el bot directamente al destino del strafe, usar NavigationServer3D con un NavigationPolygon modificado donde las áreas expuestas al enemigo tienen mayor costo. El bot naturalmente elegirá rutas con cobertura.

- **Evaluación de la calidad del strafe**: Si el bot ha estado strafeando 5 segundos sin infligir daño y el enemigo le está acertando todos los disparos, debe reconocer que su estrategia actual está fallando y cambiar.

### 6.4 ¿Qué parte reemplazarías completamente?

- **El sistema de HitWall en TacticalMove**: En lugar de reaccionar a colisiones, el bot debería usar **navigation avoidance** de Godot y **predicción de obstáculos**. Si el mapa tiene una pared, el pathfinding ya debería evitarla antes de que el bot choque.

- **FearThisSpot()**: Reemplazar por un **sistema de peligro dinámico** donde ciertas áreas del mapa tienen un "heat value" que aumenta cuando un enemigo dispara desde allí. El bot evita naturalmente áreas calientes.

### 6.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug de strafe contra pared**: Si el destino del strafe está dentro de una pared, el bot choca, llama HitWall, y GiveUpTactical. Esto pasa seguido en corredores estrechos. El bot alterna entre TacticalMove y RangedAttack continuamente.
- **Bug de RecoverEnemy infinito**: Si el bot está en RecoverEnemy y nunca recupera línea de visión, sigue alternando entre HidingSpot y LastSeeingPos indefinidamente. No hay contador de intentos.
- **Bug de strafe con arma melee**: Si el bot tiene un arma melee equipada y entra en TacticalMove (por GiveUpTactical fallando), intenta strafe con arma melee, lo cual no tiene sentido táctico.
- **Bug de bCanFire inconsistente**: bCanFire se desactiva en BeginState y se activa en ciertos puntos, pero si el bot transiciona a otro estado sin pasar por EndState, bCanFire puede quedar en un estado incorrecto.

### 6.6 ¿Cómo evitarías esos bugs?

- **Validación de destino de strafe**: Antes de comprometerse con un destino, verificar con NavigationServer3B si es reachable. Si no, probar la dirección opuesta inmediatamente, no esperar a HitWall.
- **Contador de intentos en RecoverEnemy**: Máximo 3 ciclos de "asomarse y cubrirse". Si después de 3 intentos no hay progreso, transicionar a Hunting o WhatToDoNext.
- **Validación de arma**: Si el arma es melee, no entrar en TacticalMove. Forzar Charging directamente.
- **EndState como destructor garantizado**: Usar Godot's `_exit_tree()` o similar para asegurar que EndState se ejecute siempre, incluso en transiciones forzadas. O mejor: usar una FSM donde el estado actual es un Node que se remove/crea, garantizando cleanup.

### 6.7 ¿Cómo lo implementarías usando Godot 4.5?

- **StateTacticalMove** como Node en la FSM de DecisionSystem.
- **StrafeCalculator** como sub-sistema: Toma enemy_position, enemy_velocity, combat_style, weapon_profile y produce un `desired_position: Vector3` y `strafe_direction: Vector3`.
- **MovementCommand** incluye:
  - `target_position: Vector3`
  - `movement_mode: enum { DIRECT, STRAFE, RECOVER, SNEAK }`
  - `face_target: NodePath` (a quién mirar mientras se mueve)
  - `can_fire: bool`
  - `use_cover: bool`
  - `cover_nodes: Array[NodePath]`
- **RecoverEnemyLogic**: Implementado como una sub-FSM dentro de TacticalMove con sus propios sub-estados (PEEK, FIRE, RETREAT).
- **NavigationServer3D** para pathfinding táctico: Usar `NavigationRegion3D` con capas de navegación (navigation_layers) para que el bot pueda tener capas de "ruta segura" vs "ruta expuesta".
- Godot 4.5 permite usar **NavigationAgent3D.velocity** para movimiento suave sin reemplazar el sistema de velocity del bot.

### 6.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **El output de StrafeCalculator debe producir los mismos destinos que el código original** para los mismos inputs. La fórmula de Aggression, enemyPart, pickdir, strafeSize debe ser exactamente la misma.
- **RecoverEnemy debe tener la misma secuencia**: HidingSpot → LastSeeingPos → quickFire → volver. Los timings (0.2s para splash, 0.35-0.65s para otros) deben ser exactos.
- **La frecuencia de transición a RangedAttack debe ser la misma**: `FRand() > 0.5 + 0.17 * skill` para no-novatos, `FRand() > 0.4 + 0.18 * skill` para novatos.
- **El strafe debe alternar dirección con la misma frecuencia**: bStrafeDir toggle en cada PickRegDestination.

---

## 7. `Hunting()` — PERSECUCIÓN

### 7.1 ¿Qué parte copiarías exactamente?

- **El tiempo límite dinámico**: `26 - NumPlayers - NumBots`. Adaptar la paciencia del bot al tamaño de la partida. Más jugadores = menos tiempo buscando.
- **El contador numHuntPaths**: Límite de intentos antes de abandonar. 8+Skill para el primer control, 60 como límite absoluto.
- **El concepto de BlockedPath y bDevious**: Bloquear un pathnode visible al enemigo para forzar un rodeo. Esto crea flanqueo sin pathfinding complejo.
- **La verificación de CanStakeOut() como respaldo**: Si no hay camino al enemigo, verificar si se puede esperar en StakeOut antes de rendirse completamente.
- **FindViewSpot()**: Intentar moverse lateralmente para recuperar línea de visión. Es un comportamiento humano básico.

### 7.2 ¿Qué parte eliminarías?

- **La búsqueda de inventario dentro de Hunting (PickDestination)**: Cuando el bot está cazando, no debería distraerse con pickups. En UT99, tiene un cooldown de 2.5 - 0.4*skill y radio de 600, pero sigue siendo una distracción.
- **El uso de `bAvoidLedges` toggle**: Demasiado estado global para algo que debería ser propiedad del movimiento.
- **La comprobación de `bHunting`**: Es un flag redundante que indica "no puedo ver directamente al enemigo". La información ya está en PerceptionSystem.
- **El manejo de BlockedPath y RouteCache**: Depende de estructuras internas del pathfinding de Unreal Engine 1. En Godot, el pathfinding maneja costos diferentemente.

### 7.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Predicción de movimiento del enemigo**: No solo ir a LastSeenPos. Estimar hacia dónde se dirige el enemigo basado en:
  - Su velocidad y dirección en el momento de perderlo de vista
  - Los NavigationPoints cercanos (¿va hacia un pickup? ¿hacia un objetivo?)
  - El tiempo transcurrido desde que se perdió
  Esto permite que el bot corte camino en lugar de seguir la ruta exacta.

- **Búsqueda con exploración**: En lugar de ir directamente a LastSeenPos, planificar una ruta de búsqueda que cubra áreas por las que el enemigo podría haber pasado. Similar a cómo un humano buscaría: "si lo perdí aquí, pudo haber ido a la izquierda o a la derecha".

- **Búsqueda colaborativa en equipo**: En team games, los bots deberían coordinar la búsqueda. Si un bot busca al enemigo, otro cubre otra ruta. Si un bot ya buscó en un área, lo comunica.

- **Tiempo límite con contexto**: En lugar de `26 - NumPlayers - NumBots`, usar un tiempo base que se modifica por:
  - Importancia del enemigo (¿tiene la bandera? ¿está dominando la partida?)
  - Estado del bot (baja salud → menos tiempo buscando)
  - Presencia de mejores objetivos (si hay un pickup importante cerca, abandonar antes)

### 7.4 ¿Qué parte reemplazarías completamente?

- **FindBestPathToward(Enemy)**: Reemplazar por un **GoalEvaluator** que considera múltiples estrategias de aproximación:
  1. Ruta directa a LastSeenPos (si es reachable y segura)
  2. Ruta de flanqueo (rodear por un punto ciego)
  3. Ruta alternativa con cobertura
  4. Ruta a un punto de observación cercano (stakeout approach)
  El evaluador elige la mejor basada en seguridad, velocidad y sorpresa.

- **El concepto de BlockedPath**: Reemplazar por **DynamicNavigationCost** donde áreas recientemente visitadas o peligrosas tienen costo incrementado temporalmente.

### 7.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug de numHuntPaths en mapas pequeños**: Si el mapa es pequeño y el bot puede ver a través de varias zonas, numHuntPaths se incrementa rápidamente porque cada intento de pathfinding cuenta como un path. El bot abandona la búsqueda prematuramente.
- **Bug de BlockedPath con RouteCache**: RouteCache es un array de 16 navigation points. Si el enemigo está lejos, la ruta tiene más de 16 nodos y BlockedPath nunca se setea. bDevious se activa pero no bloquea nada.
- **Bug de FindViewSpot dirección duplicada**: El código (línea 6101-6103) tiene un bug donde ambas ramas del `if (FRand() < 0.5)` hacen lo mismo: `Location - 2.5 * Y * CollisionRadius`. La dirección opuesta nunca se prueba.
- **Bug de Hunting sin enemigo reachable**: Si el enemigo está detrás de una puerta cerrada, el pathfinding no encuentra ruta, el bot entra en StakeOut, y se queda esperando frente a la puerta. No intenta abrir la puerta.

### 7.6 ¿Cómo evitarías esos bugs?

- **numHuntPaths basado en tiempo, no en intentos**: En lugar de incrementar por cada PickDestination, contar tiempo real en estado Hunting. Si pasan X segundos sin ver al enemigo, abandonar.
- **BlockedPath con ruta completa**: Si la ruta tiene más de 16 nodos, seleccionar el nodo más cercano al enemigo que esté en línea de visión, no limitarse al RouteCache.
- **FindViewSpot con ambas direcciones**: Corregir el bug: probar izquierda y derecha realmente.
- **Puertas interactivas**: Godot 4.5 permite que NavigationServer3D actualice el mapa cuando las puertas se abren. Alternativamente, el bot debe saber que ciertas puertas se abren con disparos o presión y buscar activamente la interacción.

### 7.7 ¿Cómo lo implementarías usando Godot 4.5?

- **StateHunting** como Node en la FSM.
- **SearchPlanner**: Sub-sistema que planifica rutas de búsqueda. Usa el NavigationServer3D para encontrar múltiples caminos hacia LastSeenPos y áreas circundantes.
- **PredictionModule**: Estima la posición más probable del enemigo basado en speed, direction, navigation mesh topology.
- **HuntTimer**: Timer con la fórmula `26 - players - bots` como default, modificable por perfil del bot.
- **WorldState** proporciona una lista de "puntos calientes" donde es más probable encontrar enemigos (pickups importantes, objetivos del modo de juego).
- En vez de BlockedPath, usar `NavigationServer3D.region_set_connection_cost()` para aumentar temporalmente el costo de ciertas áreas.

### 7.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **El tiempo de búsqueda por defecto debe ser idéntico**: 24s para mapas vacíos, bajando con más jugadores.
- **La decisión entre Hunting y StakeOut debe usar la misma fórmula**: `VSize > 600 + (FRand() * relStr - CombatStyle) * 600`.
- **El flag bDevious debe activarse con la misma probabilidad**: `0.52 - 0.12 * numBots`.
- **El bot debe comportarse "obsesivamente" como en UT99**: Una vez que decide cazar, no se distrae fácilmente. Eso significa que en esta implementación moderna, Hunting NO debe buscar pickups (a diferencia de UT99 que sí lo hacía con cooldown).
- **La transición a StakeOut debe ocurrir en las mismas condiciones**: Si CanStakeOut() es true y la distancia es < 1200, el bot espera.

---

## 8. `StakeOut()` — EMBOSCADA

### 8.1 ¿Qué parte copiarías exactamente?

- **La condición CanStakeOut()**: Verificar que TANTO el bot como el enemigo pueden ver la última posición conocida. Esto asegura que el punto de emboscada esté en una posición tácticamente relevante.
- **ContinueStakeOut()**: La fórmula para decidir si seguir esperando:
  - Distancia: `VSize(Enemy - Bot) > 300 + (relStr - CombatStyle) * 350` → si el enemigo se aleja, salir.
  - Tiempo: `LastSeenTime > 2.5 + FMax(-1, 3 * (FRand + 2*(relStr - CombatStyle)))` → si pasa mucho tiempo, salir.
  - ClearShot: si no hay tiro claro, salir.
- **FindNewStakeOutDir()**: Buscar NavigationPoints cercanos (100-800 unidades) que estén en la dirección del enemigo y tengan línea de visión. El mejor punto se convierte en nuevo LastSeenPos.
- **La postura de espera**: Accélération = 0, apuntar hacia LastSeenPos, animación de idle.

### 8.2 ¿Qué parte eliminarías?

- **El manejo de AmbushSpot y bSniping**: No son responsabilidad de StakeOut. Deben ser configuraciones de perfil del bot que StakeOut consulta, no modifica.
- **La llamada a FindSpecialAttractionFor() dentro del loop**: La atracción especial debe evaluarse ANTES de entrar en StakeOut, no durante.
- **bClearShot calculado cada frame con trace**: El ClearShot debe ser proporcionado por PerceptionSystem, no calculado dentro del estado.
- **El reset de bSniping cuando AmbushSpot es None**: bSniping debe ser un perfil de bot, no un flag que se modifica por la presencia de AmbushSpot.

### 8.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Rotación de puntos de observación**: Si el bot está en StakeOut y no ve al enemigo en 3 segundos, debería rotar entre múltiples puntos de observación (FindNewStakeOutDir múltiples veces), no solo elegir uno y quedarse allí.
- **Angulo de visión**: En lugar de apuntar exactamente a LastSeenPos, barrer el área con un cono de visión. El bot mira a la izquierda, espera, mira a la derecha, espera. Esto es más humano.
- **Re-evaluación contextual**: Si el bot escucha disparos en otra dirección, podría reconsiderar si su punto de emboscada sigue siendo relevante.
- **Cobertura activa**: Un bot en StakeOut debería moverse entre puntos de cobertura dentro del mismo sector, no quedarse completamente quieto. Esto lo hace menos predecible para el enemigo.

### 8.4 ¿Qué parte reemplazarías completamente?

- **El loop principal con Sleep(1 + FRand())**: Reemplazar por un sistema de **timers con eventos**. El bot no debe "dormir". Debe tener un timer que se dispara cada 1-2 segundos para re-evaluar. Dormir bloquea la capacidad de respuesta.

### 8.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug de Sleep en StakeOut**: El bot duerme 1-2 segundos. Durante ese sleep, NO responde a daño ni a estímulos. Si el enemigo aparece durante el sleep, el bot no reacciona hasta que despierta.
- **Bug de FindNewStakeOutDir mirando hacia la pared**: Si el mejor punto está en una dirección donde el bot mira hacia una pared (porque la línea de visión al enemigo pasa por una esquina), el bot apunta a la pared.
- **Bug de ContinueStakeOut sin enemigo**: Si Enemy es None cuando se evalúa ContinueStakeOut, el código falla porque accede a Enemy.Location. No hay guard clause.
- **Bug de sniping sin ambush spot**: Si el bot es sniper pero no hay AmbushSpot en el mapa, bSniping se desactiva (linea 6354-6355). Esto hace que el sniper se comporte como un bot normal, perdiendo su especialización.

### 8.6 ¿Cómo evitarías esos bugs?

- **No usar Sleep() en Godot 4.5**. Usar Timer con timeout para re-evaluación periódica. El bot sigue responsive durante la espera.
- **Validar que FindNewStakeOutDir no apunte a una pared**: Después de elegir el punto, verificar que el vector dirección no intersecte geometría cercana. Si lo hace, elegir el segundo mejor.
- **Guard clause en ContinueStakeOut**: Verificar Enemy != None antes de acceder a Enemy.Location.
- **bSniping como perfil de bot, no como flag modificable**: El perfil del bot define si es sniper. AmbushSpot es un bonus, no un requisito.

### 8.7 ¿Cómo lo implementarías usando Godot 4.5?

- **StateStakeOut** como Node en la FSM con timers:
  - `@onready var evaluate_timer: Timer` para re-evaluación periódica
  - `@onready var look_timer: Timer` para cambio de dirección de mirada
- **PerceptionSystem** alimenta `has_clear_shot: bool` al estado.
- **StakeOutPositionFinder**: Sistema que encuentra NavigationPoints cercanos con ventaja táctica (línea de visión al LastSeenPos, cobertura disponible, distancia 100-800).
- **BotProfile** incluye:
  - `sniping_preference: float` (0.0 nunca sniper, 1.0 siempre sniper)
  - `patience: float` (multiplicador del tiempo de espera)
  - `look_scan_frequency: float` (cada cuánto cambia de dirección de mirada)
- Godot 4.5 permite usar **Tween** para animar la rotación de mirada suavemente, en lugar de instantánea.

### 8.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **El tiempo de espera por defecto debe ser el mismo**: `1 + FRand()` segundos entre evaluaciones.
- **ContinueStakeOut debe usar las mismas fórmulas**: Distancia, tiempo, ClearShot con los mismos umbrales.
- **FindNewStakeOutDir debe preferir el mismo tipo de puntos**: Cercanos (100-800), con dot product hacia el enemigo, con línea de visión.
- **La postura es la misma**: Quieto, mirando hacia LastSeenPos, animación de waiting/challenge.
- **La transición a Hunting debe ocurrir exactamente cuando en UT99**: Cuando ContinueStakeOut falla y el enemigo está lejos.

---

## 9. `Retreating()` — RETIRADA TÁCTICA

### 9.1 ¿Qué parte copiarías exactamente?

- **La definición de retirada**: "Ir hacia un item mientras aún estás enganchado con un enemigo, pero temiéndolo". Esto no es huir ciegamente. Es buscar recursos mientras mantienes conciencia del enemigo.
- **El timeout de miedo**: Si pasan 12s sin ver al enemigo (8s en team games), dejar de temerle y volver al ataque.
- **La búsqueda de inventario cercano durante la retirada**: El bot no solo corre. Busca health packs y armaduras en el camino.
- **La transición a TacticalMove con bKamikaze**: Si no hay recursos para recuperarse, el bot se rinde y vuelve a la lucha. Esto evita que huya indefinidamente.
- **La verificación de actitud**: Si AttitudeTo(Enemy) cambia de Fear a otra cosa, salir de Retreating inmediatamente.

### 9.2 ¿Qué parte eliminarías?

- **La restricción de altura en búsqueda de inventario**: `Inv.Location.Z < FMin(Location.Z, Enemy.Location.Z) - CollisionHeight` — igual que en PickDestination, esta restricción es dañina.
- **El radio de búsqueda fijo + skill**: En lugar de 500 + 70*skill, el radio debería basarse en la distancia al enemigo. Si el enemigo está a 200 unidades, buscar a 500 es peligroso.
- **La lógica de TeamGame con bKamikaze**: Es confusa y mezcla responsabilidades (retirada + táctica de equipo).
- **El manejo de Home/SpecialGoal**: Debe ser reemplazado por el sistema de objetivos.

### 9.3 ¿Qué parte mejorarías usando técnicas modernas?

- **Ruta de retirada segura**: No solo buscar el pickup más cercano. Calcular una ruta de retirada que:
  1. Maximice la distancia al enemigo
  2. Maximice la cobertura (áreas fuera de línea de visión)
  3. Priorice pickups en esa ruta
  4. Termine en un punto seguro (base aliada, un compañero, un choke point defendible)

- **Retirada con cobertura**: Si hay cobertura disponible, el bot debería moverse entre puntos de cobertura, no correr en línea recta. Alternar entre "correr" y "cubrirse".

- **Evaluación de cuándo dejar de retirarse**: Además del timeout de 12s, el bot debería evaluar:
  - ¿He recuperado suficiente salud? (salud > 70)
  - ¿He conseguido un arma mejor?
  - ¿Mi enemigo está enganchado con otro compañero? (puedo contraatacar)
  - ¿Hay un objetivo del equipo que requiere mi atención?

- **Retirada con granada/explosivo de cobertura**: Si el bot tiene un arma con splash, debería disparar hacia atrás mientras se retira para disuadir persecución.

### 9.4 ¿Qué parte reemplazarías completamente?

- **La búsqueda de inventario por visiblecollidingactors**: Reemplazar por **ruta de navegación a pickups con evaluación de peligro**. El bot calcula varias rutas a diferentes pickups y elige la que minimiza exposición al enemigo y maximiza ganancia de recursos.
- **PickDestination en Retreating**: Reemplazar por **RetreatPlanner** que produce un plan de retirada:
  1. Punto de retirada final (base, compañero, choke point)
  2. Waypoints intermedios (pickups en el camino)
  3. Puntos de cobertura intermedios
  4. Punto de "si me detectan, hacer stand aquí"

### 9.5 ¿Qué bugs conocidos tenía UT99 relacionados?

- **Bug de retirada hacia el enemigo**: Si el único pickup visible está DETRÁS del enemigo, el bot corre hacia el enemigo para agarrarlo, contradiciendo la retirada.
- **Bug de bKamikaze prematuro**: Si hay pickups pero todos están fuera del radio de 500+skill, el bot asume que no hay recursos disponibles y entra en bKamikaze. En mapas grandes con pickups distribuidos, esto pasa seguido.
- **Bug de retirada en lava/daño**: El bot huye del enemigo pero puede caer en zonas de daño (lava, ácido). No hay evaluación de peligro ambiental durante la retirada.
- **Bug de 12s sin ver al enemigo**: El timeout de 12s se resetea CADA VEZ que el bot ve al enemigo. Si el enemigo aparece y desaparece intermitentemente, el bot puede estar en Retreating indefinidamente.

### 9.6 ¿Cómo evitarías esos bugs?

- **Pickups en dirección OPUESTA al enemigo**: Filtrar pickups que estén en el hemisferio opuesto al enemigo. Si el único pickup está hacia el enemigo, ignorarlo y buscar otra estrategia.
- **Radio de búsqueda basado en distancia al enemigo**: `radio = min(500 + skill, distance_to_enemy * 0.8)`. Así el bot no busca más allá de donde es seguro.
- **Evaluación de peligro ambiental**: El mapa debe tener regiones marcadas con peligro. El RetreatPlanner debe evitarlas.
- **Timeout con histéresis**: No resetear el timeout cada vez que ves al enemigo. El timeout cuenta desde la PRIMERA vez que entraste en Retreating. Ver al enemigo extiende el timeout pero no lo resetea completamente.

### 9.7 ¿Cómo lo implementarías usando Godot 4.5?

- **StateRetreating** como Node en la FSM.
- **RetreatPlanner**: Sub-sistema que, al entrar en Retreating:
  1. Obtiene la posición del enemigo
  2. Consulta NavigationServer3D para pickups en el hemisferio opuesto
  3. Calcula ruta segura usando NavigationPolygons con capas de peligro
  4. Produce una secuencia de MovementCommands
- **HealthSystem** expone `retreat_threshold: float` (salud por debajo de la cual el bot huye).
- **ArmorSystem** (parte de HealthSystem) expone `effective_health` para la decisión.
- **DangerMap**: Sistema global que marca zonas con peligro (línea de visión del enemigo, zonas de daño, áreas abiertas). El RetreatPlanner consulta DangerMap para evitar rutas peligrosas.
- **FearTimer**: Timer que no se resetea completamente con sightings. Usa ventana de histéresis: cada sighting extiende el timer por 2s adicionales, máximo 20s totales.

### 9.8 ¿Cómo mantener exactamente la sensación de UT99 pero con arquitectura limpia?

- **La frecuencia de re-evaluación debe ser la misma**: Cada vez que el bot llega a un destino o cada 0.7s (el SetTimer de Retreating).
- **El radio de búsqueda por defecto debe ser 500 + skill** pero con el filtro de "solo pickups lejos del enemigo" añadido, no reemplazado.
- **bKamikaze debe activarse en las mismas condiciones**: Cuando no hay pickup reachable, el bot se rinde y contraataca.
- **El timeout de 12s (8s team) debe ser el mismo** pero con el mecanismo de histéresis para evitar el bug de reset infinito.
- **La retirada debe sentirse como "retirada táctica", no como "huida de pánico"**. El bot mira hacia atrás, dispara si puede, y busca cobertura.

---

## 10. RESUMEN DE PATRONES — Lo que NO cambia

### Inmutables (siempre igual que UT99)

1. **El orden jerárquico de decisiones**: Actitud → Visibilidad → Distancia → Agresividad → Acción
2. **Las fórmulas de umbral**: CombatStyle, Aggressiveness, FRand() combinados igual
3. **Los perfiles de bot por dificultad**: skill 0-3, novice flags, DamageScaling
4. **La inercia de objetivo**: No cambiar de enemigo sin razón de peso
5. **La separación por estados mentales**: Cada estado tiene su propia lógica de movimiento y decisión
6. **La sensación de "humanidad"**: FRand() en todas partes para evitar comportamientos deterministas
7. **La preferencia por pickups**: Ítem > flanqueo > posición aleatoria

### Eliminados (bugs y limitaciones)

1. **Promedio de salud en RelativeStrength**
2. **OldEnemy como slot único**
3. **Cortes duros de distancia/salud**
4. **Sleep() en estados**
5. **bNotSeen/bGathering como flags globales**
6. **Búsqueda por visiblecollidingactors**
7. **Dependencia directa de LineOfSightTo dentro de decisiones**

### Modernizados (mejora sobre el concepto original)

1. **RelativeStrength como poder efectivo total** (vida + armadura + DPS + distancia)
2. **AssessThreat como producto de factores con curvas continuas**
3. **PickDestination usando NavigationServer3D con costo táctico**
4. **Strafing predictivo basado en velocidad del enemigo**
5. **BlockedPath → DynamicNavigationCost**
6. **Retirada con RetreatPlanner y DangerMap**
7. **Búsqueda colaborativa en team games**

### Reemplazados (cambio completo de paradigma)

1. **FindBestInventoryPath → GoalEvaluator con utilidad multi-factor**
2. **visiblecollidingactors → NavigationServer3D query**
3. **Sleep/FRed → Timer events**
4. **State machine plana → FSM con estados como Nodes**
5. **Variables globales del bot → Sistemas con data ownership**

### La regla de oro

> Si el comportamiento se siente idéntico al de UT99, la implementación es correcta.
> Si el comportamiento es diferente pero mejor, debe ser porque el nuevo sistema maneja casos que UT99 manejaba mal.
> Si el comportamiento es diferente y es peor, es un bug de implementación.

Los playtests comparativos (bot moderno vs bot UT99 en el mismo escenario) deben producir trayectorias indistinguibles. La diferencia debe estar en cómo maneja los casos extremos, no en cómo maneja el caso normal.
