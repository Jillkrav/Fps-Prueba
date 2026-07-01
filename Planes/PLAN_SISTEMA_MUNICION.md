# Plan de Refactorización: Sistema de Municiones y Tipos de Armas

## Situación Actual

El proyecto tiene un sistema de armas funcional pero limitado:

- **skill.json** (res://config/skill.json): Contiene 19 armas en 6 categorías (Pistolas, Escopetas, Subfusiles, Rifles, Francotiradores, Melee). Cada arma define daño, cargador, reserva, tiempo de recarga.
- **weapon.gd**: Clase base. Usa **RayCast3D** (hit-scan) para todas las armas. Propiedades: `pellets`, `spread`, `weapon_range`. El método `fire()` siempre hace raycast, sin distinción de tipo de proyectil.
- **weapon_ai_profile.gd**: Recurso que define perfil táctico (rango, splash, melee, hit-scan vs proyectil, etc.). Los profiles existen en `res://config/ai_profiles/*.tres`.
- **El problema**: Los bots no disparan porque el sistema actual es **100% hit-scan** y no hay diferenciación real entre tipos de munición.

## Objetivo

Crear un sistema de 5 categorías de armas con comportamientos distintos:

| Categoría | Comportamiento | Ejemplos |
|-----------|---------------|----------|
| **Balas** (Bullets) | Hit-scan instantáneo | Pistolas, Subfusiles, Rifles, Snipers |
| **Perdigones** (Pellet/Shotgun) | Múltiples proyectiles hit-scan con cono | Escopetas |
| **Arrojadizas** (Thrown) | Objetos físicos que viajan, se clavan/ruedan | Cuchillos, Granadas, Ballestas |
| **Explosivas** (Explosive) | Proyectiles que viajan y explotan al impactar | Lanza granadas, Bazooka |
| **Plasma** (Plasma) | Proyectiles que viajan (estilo Halo) | Armas de plasma |

---

# FASE 1: skill.json — Estructura de Datos

## Resumen
Agregar las armas faltantes y expandir el JSON con los nuevos campos necesarios para categorizar y parametrizar cada tipo de munición.

## Cambios en skill.json

### 1. Nuevas categorías y armas a agregar:

```json
"Arrojadizas": {
  "Cuchillo": { ... },
  "Granada": { ... },
  "Ballesta": { ... }
},
"Explosivas": {
  "LanzaGranadas": { ... },
  "Bazooka": { ... }
},
"Plasma": {
  "RiflePlasma": { ... },
  "PistolaPlasma": { ... }
}
```

### 2. Nuevos campos para CADA arma (en el JSON):

| Campo | Tipo | Propósito |
|-------|------|-----------|
| `CategoriaMunicion` | String | `"bala"`, `"perdigones"`, `"arrojadiza"`, `"explosiva"`, `"plasma"` |
| `VelocidadProyectil` | float | Velocidad del proyectil en unidades/seg (solo para proyectiles no hit-scan). 0 = hit-scan |
| `DanioArea` | float | Daño de área/radio (solo explosivas y granadas) |
| `RadioExplosion` | float | Radio de la explosión en unidades 3D |
| `GravedadProyectil` | float | Factor de gravedad aplicado al proyectil (arrojadizas = 1.0, plasma = 0) |
| `Penetracion` | int | ¿Puede atravesar enemigos? 0=no, 1=sí (para francotiradores y ballesta) |
| `SeClava` | bool | ¿El proyectil se queda clavado? (cuchillos, flechas de ballesta) |
| `ExplotaAlImpactar` | bool | ¿Explota al impactar? (granadas, explosivas) |
| `TiempoExplosion` | float | Si > 0, explota después de N segundos (granadas de tiempo) |
| `NumeroPerdigones` | int | Número de perdigones (solo escopetas) |
| `Rebota` | bool | ¿El proyectil rebota? (granadas) |
| `NumeroRebotes` | int | Máximo de rebotes |

### 3. Nuevas armas por categoría:

**Arrojadizas:**
- Cuchillo: 1 proyectil, se clava, daño medio-alto, sin rebote
- Granada: explota al impactar o por tiempo, rueda/rebota, daño de área
- Ballesta: proyectil rápido, se clava, alto daño, precisión

**Explosivas:**
- LanzaGranadas: proyectil arqueado, explota al impactar, daño de área grande
- Bazooka: proyectil rápido y recto, gran explosión, mucho daño

**Plasma:**
- RiflePlasma: proyectil brillante, velocidad media-alta, sin gravedad, daño sostenido
- PistolaPlasma: proyectil pequeño, rápida, sin gravedad

### 4. Armas existentes que se mantienen pero se actualizan:

Todas las armas actuales (USP, Glock, Deagle, M3, MP7, etc.) se les agrega `CategoriaMunicion: "bala"` (excepto escopetas que son `"perdigones"`) y `VelocidadProyectil: 0` (hit-scan).

## Archivos a modificar

- `res://config/skill.json`
- `res://config/ai_profiles/*.tres` (nuevos perfiles para las nuevas armas)

## Prompt para FASE 1

```
Eres un asistente experto en Godot 4.2+.

Necesito expandir el archivo res://config/skill.json de mi proyecto FPS para agregar nuevas categorías de armas y actualizar la estructura de datos.

Contexto:
- El JSON actual tiene: Pistolas, Escopetas, Subfusiles, Rifles, Francotiradores, Melee
- Cada arma tiene campos como: DanioAlJugador, DanioAlNPC, DanioPorSegundo, TamanoCargador, ReservaMunicionMaxima, TiempoRecargaSegundos, TipoRecarga, TipoMunicion

Necesito:
1. Agregar 3 nuevas categorías: "Arrojadizas", "Explosivas", "Plasma"
2. Agregar a CADA arma existente los campos: "CategoriaMunicion", "VelocidadProyectil", "DanioArea", "RadioExplosion", "GravedadProyectil", "Penetracion", "SeClava", "ExplotaAlImpactar", "TiempoExplosion", "NumeroPerdigones", "Rebota", "NumeroRebotes"
3. Las armas existentes tipo "bala" (pistolas, subfusiles, rifles, snipers): VelocidadProyectil=0 (hit-scan), CategoriaMunicion="bala"
4. Las escopetas existentes: CategoriaMunicion="perdigones", NumeroPerdigones=6-10 según el arma, VelocidadProyectil=0
5. Agregar las nuevas armas:
   - Arrojadizas: Cuchillo, Granada, Ballesta
   - Explosivas: LanzaGranadas, Bazooka  
   - Plasma: RiflePlasma, PistolaPlasma
6. Para las armas Melee existentes (Crowbar, Tonfa, Machete): CategoriaMunicion="cuerpo_a_cuerpo"

Lee el archivo actual primero, luego edítalo con todos los cambios. Asegúrate de que el JSON siga siendo válido.
```

---

# FASE 2: Sistema de Proyectiles (Nuevos Nodos)

## Resumen
Crear los nodos y scripts para los diferentes tipos de proyectiles. El sistema actual solo tiene `Weapon` con RayCast3D (hit-scan). Necesitamos crear proyectiles físicos.

## Nuevos archivos

### res://scripts/projectiles/projectile_base.gd
Clase base para todos los proyectiles (extends RigidBody3D o Area3D).

```gdscript
class_name ProjectileBase
extends RigidBody3D  # O Area3D con movimiento manual

# Propiedades comunes
var damage_vs_player: float
var damage_vs_npc: float
var shooter: Node3D          # Quien disparó
var weapon_name: String      # Nombre del arma origen
var categoria: String        # "arrojadiza", "explosiva", "plasma"
var speed: float             # Velocidad inicial
var lifespan: float = 5.0   # Tiempo máximo de vida

# Para físicas
var gravity_factor: float = 1.0
var bounces_left: int = 0    # Rebotes restantes
var sticks: bool = false     # ¿Se clava?
var sticks_to: Node = null   # ¿En qué se clavó?

# Para explosiones
var explosive: bool = false
var explosion_radius: float = 0.0
var explosion_damage: float = 0.0
var fuse_time: float = 0.0   # Para granadas de tiempo

# Penetración
var penetration: int = 0     # 0 = no penetra, >0 = penetra N objetivos
```

### res://scripts/projectiles/projectile_bullet.gd
Para proyectiles con velocidad (no hit-scan). Se mueve linealmente, puede tener gravedad.

### res://scripts/projectiles/projectile_explosive.gd
Para explosivos. Al impactar o al terminar el fuse, crea una explosión.

### res://scripts/projectiles/projectile_sticky.gd
Para objetos que se clavan (cuchillos, flechas). Al impactar, se quedan en el punto de impacto.

### res://scripts/effects/explosion.gd
Sistema de explosión con daño de área, efecto visual y de sonido.

### res://scenes/projectiles/ (nuevas escenas)
- `projectile_bullet.tscn` (RigidBody3D con MeshInstance + CollisionShape)
- `projectile_grenade.tscn` (RigidBody3D esférico)
- `projectile_knife.tscn` (RigidBody3D alargado)
- `projectile_rocket.tscn` (RigidBody3D con estela)
- `projectile_plasma.tscn` (Area3D con movimiento manual, sin gravedad)
- `explosion.tscn` (Area3D para daño de área + efectos)

## Cambios en weapon.gd

El método `fire()` debe bifurcar según `CategoriaMunicion`:

```gdscript
func fire() -> Array:
	if not can_fire():
		return []
	ammo_in_mag -= 1
	last_fire_time = Time.get_ticks_msec()
	weapon_fired.emit(ammo_in_mag, reserve_ammo)
	show_muzzle_flash()
	
	match categoria_municion:
		"bala", "perdigones":
			return _fire_hitscan()     # Comportamiento actual mejorado
		"arrojadiza", "explosiva", "plasma":
			return _fire_projectile()  # Instancia un proyectil
		"cuerpo_a_cuerpo":
			return _fire_melee()       # Ataque cuerpo a cuerpo
	return []
```

## Nuevos métodos en weapon.gd

```gdscript
# Cargar la escena de proyectil correspondiente
var bullet_scene: PackedScene = preload("res://scenes/projectiles/projectile_bullet.tscn")

func _fire_projectile() -> Array:
	# Instanciar proyectil desde el arma
	var projectile = bullet_scene.instantiate()
	get_tree().root.add_child(projectile)
	projectile.global_position = raycast.global_position
	projectile.global_transform.basis = raycast.global_transform.basis
	
	# Aplicar spread
	if spread > 0.0:
		var rx = randf_range(-spread, spread)
		var ry = randf_range(-spread, spread)
		# Rotar la dirección del proyectil
	
	# Configurar propiedades del proyectil desde el JSON
	projectile.damage_vs_player = damage_vs_player
	projectile.damage_vs_npc = damage_vs_npc
	projectile.speed = velocidad_proyectil
	# ... etc
	
	return []  # El daño se maneja cuando el proyectil impacta
```

## Prompt para FASE 2

```
Contexto del proyecto Godot 4.2+:
- shooter FPS en 3D con sistema de armas actual basado en hit-scan (RayCast3D)
- weapon.gd es la clase base de armas (extends Node3D, class_name Weapon)
- Se usa weapon_placeholder.tscn como escena de arma
- Los bots usan WeaponSystem y CombatSystem para disparar
- skill.json define las propiedades de cada arma (acaba de ser expandido en la FASE 1)

Ahora necesito crear el SISTEMA DE PROYECTILES. Esto incluye:

1. Crear la jerarquía de carpetas:
   - res://scripts/projectiles/
   - res://scripts/effects/
   - res://scenes/projectiles/

2. Crear projectiles/projectile_base.gd:
   - Clase base ProjectileBase extends RigidBody3D (con class_name)
   - Propiedades: damage_vs_player, damage_vs_npc, shooter (Node3D), weapon_name (String), categoria (String), speed (float), lifespan (float=5.0), gravity_factor (float=1.0), bounces_left (int=0), sticks (bool=false), explosive (bool=false), explosion_radius (float=0.0), explosion_damage (float=0.0), fuse_time (float=0.0), penetration (int=0)
   - Señales: hit_target(target: Node), exploded(position: Vector3)
   - Método _ready(): aplicar velocidad inicial en dirección forward * speed, iniciar timer de lifespan
   - Método _physics_process(): aplicar gravedad si gravity_factor > 0
   - Método _on_body_entered(body): detectar impacto, llamar a on_hit(body)
   - Método on_hit(body): virtual, maneja el impacto (penetración, clavado, explosión)

3. Crear projectiles/projectile_explosive.gd:
   - Extiende ProjectileBase
   - Si fuse_time > 0, espera y explota
   - on_hit(): si explota_al_impactar, llama a explode()
   - explode(): crea una instancia de la escena explosion.tscn, aplica daño de área
   - Si rebota, reduce bounces_left y rebota

4. Crear projectiles/projectile_sticky.gd:
   - Extiende ProjectileBase
   - on_hit(): si sticks=true, se clava en el body (reparent al body, desactiva physics)
   - Si es explosivo con fuse, cuenta regresiva y explota clavado

5. Crear projectiles/projectile_plasma.gd:
   - Extiende ProjectileBase
   - gravity_factor = 0 siempre (sin gravedad)
   - Sin rebote, sin clavado
   - Impacto visual tipo plasma (brillo)

6. Crear effects/explosion.gd:
   - Extiende Area3D (class_name Explosion)
   - Propiedades: damage, radius, shooter
   - Al _ready(): aplicar daño a todos los cuerpos en el área con un radius check
   - Efecto visual: OmniLight3D que se desvanece
   - Auto-destruirse después de 0.5s

7. Crear escenas de proyectiles en res://scenes/projectiles/:
   - projectile_placeholder.tscn (RigidBody3D con CollisionShape3D esférico, MeshInstance3D esférica, Timer para lifespan)
   - explosion.tscn (Area3D con CollisionShape3D, OmniLight3D)

8. Actualizar weapon.gd:
   - Agregar propiedades: categoria_municion (String), velocidad_proyectil (float), danio_area (float), radio_explosion (float), gravedad_proyectil (float), penetracion (int), se_clava (bool), explota_al_impactar (bool), tiempo_explosion (float), numero_perdigones (int), rebota (bool), numero_rebotes (int)
   - initialize_from_name(): cargar TODOS los nuevos campos del JSON
   - Modificar fire() para bifurcar según categoria_municion:
	 - "bala", "perdigones": usar el sistema actual de RayCast3D (hitscan) pero con soporte de múltiples perdigones
	 - "arrojadiza", "explosiva", "plasma": instanciar ProjectileBase configurado
	 - "cuerpo_a_cuerpo": ataque melee
   - Crear _fire_hitscan(): encapsular la lógica actual de raycast con pellets
   - Crear _fire_projectile(): instanciar proyectil 3D desde la posición del arma
   - El proyectil debe spawnearse delante del arma y ser hijo de la escena raíz

Lee los archivos existentes (weapon.gd, skill.json, weapon_placeholder.tscn) para entender la estructura actual antes de hacer cambios.
```

---

# FASE 3: Integración en Player (Sistema de Disparo del Jugador)

## Resumen
Actualizar `player.gd` para que use el nuevo sistema de proyectiles. Actualmente `player.gd` llama a `active_weapon.fire()` y procesa los hits manualmente.

## Cambios en player.gd

```gdscript
func shoot() -> void:
	if not active_weapon:
		return
	if active_weapon.can_fire():
		var hits: Array = active_weapon.fire()
		# Para hit-scan (balas, perdigones): procesar hits directamente
		if active_weapon.categoria_municion in ["bala", "perdigones"]:
			_process_hitscan_hits(hits)
		# Para proyectiles: el daño se maneja desde el proyectil al impactar
		# (projectile_base.gd llama a target.take_damage cuando colisiona)
```

## Prompt para FASE 3

```
Necesito integrar el nuevo sistema de proyectiles en el Player del proyecto Godot 4.2+.

Contexto:
- player.gd (CharacterBody3D, class_name Player) ya existe
- weapon.gd ha sido modificado en FASE 2 para bifurcar entre hit-scan y proyectiles
- ProjectileBase y sus derivados ya existen
- El jugador aprieta el botón de disparo → player.shoot() → weapon.fire()

Cambios necesarios en player.gd:

1. En el método shoot():
   - Si el arma dispara hit-scan ("bala", "perdigones"): procesar hits igual que ahora
   - Si el arma dispara proyectiles ("arrojadiza", "explosiva", "plasma"): 
	 el proyectil se instancia y se maneja solo. No procesar hits aquí.
   - Si el arma es melee ("cuerpo_a_cuerpo"): ataque cuerpo a cuerpo

2. Agregar método _get_shoot_position() -> Vector3:
   - Devuelve la posición desde donde sale el proyectil
   - Debe ser delante de la cámara, no desde el centro del jugador
   - Usar $Head/Camera3D.global_position + dirección forward * 0.5

3. El proyectil debe spawnear en la posición correcta:
   - Para proyectiles: usar _get_shoot_position()
   - El proyectil debe heredar la rotación de la cámara

4. Conectar señales: cuando el ProjectileBase emite hit_target, llamar a take_damage en el objetivo

Lee player.gd primero para ver el método shoot() actual, luego edita.
```

---

# FASE 4: Integración en Bots (CombatSystem + WeaponSystem)

## Resumen
Los bots actualmente NO disparan correctamente. Esta fase arregla el sistema de disparo de bots para ambos tipos de armas (hit-scan y proyectiles).

## Problemas actuales
1. CombatSystem._check_fire_weapon() llama a `weapon.fire()` pero el resultado no se maneja consistente
2. Los proyectiles necesitan spawnear desde la posición correcta del bot (no desde el centro)
3. Los bots necesitan calcular "lead" (predicción) para armas con proyectil

## Cambios

### CombatSystem (combat_system.gd)
- Agregar cálculo de "lead" para proyectiles (predecir posición futura del objetivo)
- Ajustar aim_rotation según velocidad del proyectil vs velocidad del objetivo
- Para splash damage: apuntar al suelo (ya existe la lógica)

## Prompt para FASE 4

```
Necesito arreglar el sistema de disparo de los bots para que funcione con ambos tipos de armas (hit-scan y proyectiles).

Contexto:
- combat_system.gd (CombatSystem) es el sistema que controla aim_rotation y llama a weapon.fire()
- weapon_system.gd (WeaponSystem) gestiona el estado del arma y la recarga
- npc_base.gd orquesta las fases de ejecución
- state_combat.gd llama a combat_cmd.set_engage() que activa el disparo en CombatSystem
- weapon.gd ya bifurca entre hit-scan y proyectiles en fire()
- CombatSystem._get_weapon() obtiene el arma actual del bot

Los bots NO están disparando. Esto puede deberse a que:
1. can_fire() retorna false por alguna razón
2. La verificación _is_aiming_at_target() falla
3. El raycast no colisiona

Cambios necesarios:

1. En combat_system.gd:
   - Verificar que _check_fire_weapon() se está llamando correctamente
   - Asegurar que weapon.can_fire() retorna true (debuggear)
   - Para armas con proyectil (VelocidadProyectil > 0):
	 - Calcular "lead" (predicción de posición futura del objetivo)
	 - Apuntar a la posición predicha en lugar de la posición actual
	 - NO usar _is_aiming_at_target() para proyectiles (son más tolerantes)
   - Agregar debug logging para ver si el bot intenta disparar

2. El spawn de proyectiles del bot:
   - Debe spawnear desde la posición del head del bot
   - ProjectileBase debe usar la rotación del aim_rotation del CombatSystem
   - El shooter del proyectil debe ser el bot (NpcBase)

3. Agregar método get_projectile_launch_position() en npc_base.gd:
   - Devuelve la posición desde donde sale el proyectil (head.global_position + forward)

4. Debuggear el flujo completo:
   - Verificar que weapon.fire() se llama
   - Verificar que los proyectiles se instancian
   - Verificar que los proyectiles colisionan correctamente

Lee combat_system.gd (especialmente _check_fire_weapon), weapon_system.gd, npc_base.gd y state_combat.gd para entender el flujo actual antes de modificar.
```

---

# FASE 5: Perfiles AI para Nuevas Armas

## Resumen
Crear los archivos .tres de perfiles AI para todas las armas nuevas.

## Archivos a crear en res://config/ai_profiles/

- `cuchillo.tres` (melee, corto alcance, agresivo)
- `granada.tres` (splash, rango medio, tiro parabólico)
- `ballesta.tres` (precisión, larga distancia, proyectil)
- `lanzagranadas.tres` (splash, rango medio-largo, parabólico)
- `bazooka.tres` (splash, rango medio, proyectil rápido)
- `rifleplasma.tres` (proyectil rápido, rango medio-largo)
- `pistolaplasma.tres` (proyectil rápido, rango medio, alta cadencia)

## Prompt para FASE 5

```
Necesito crear los perfiles AI (WeaponAIProfile) para las nuevas armas del proyecto.

Contexto:
- WeaponAIProfile es un Resource con class_name, guardado como .tres
- Los perfiles existen en res://config/ai_profiles/
- El WeaponSystem los carga automáticamente al iniciar
- Cada perfil define: weapon_name, ai_rating, preferred_range_min/max, splash_damage, lead_target, refire_rate, aim_error_base, attack_style_modifier, is_melee, is_instant_hit, category
- Ya existen perfiles para las armas originales (usp.tres, awp.tres, etc.)

Necesito crear estos archivos .tres nuevos:

1. cuchillo.tres: 
   - weapon_name="Cuchillo", category="Arrojadizas"
   - ai_rating=0.4, preferred_range_min=0.5, preferred_range_max=8.0
   - splash_damage=false, lead_target=true (proyectil)
   - is_melee=false, is_instant_hit=false
   - attack_style_modifier=0.8 (muy agresivo, hay que acercarse)

2. granada.tres:
   - weapon_name="Granada", category="Arrojadizas"
   - ai_rating=0.6, preferred_range_min=5.0, preferred_range_max=20.0
   - splash_damage=true, lead_target=true
   - is_melee=false, is_instant_hit=false
   - attack_style_modifier=-0.2 (uso táctico/defensivo)

3. ballesta.tres:
   - weapon_name="Ballesta", category="Arrojadizas"
   - ai_rating=0.7, preferred_range_min=15.0, preferred_range_max=50.0
   - splash_damage=false, lead_target=true (proyectil)
   - is_melee=false, is_instant_hit=false
   - refire_rate=0.2 (lenta), aim_error_base=500 (precisa)

4. lanzagranadas.tres:
   - weapon_name="LanzaGranadas", category="Explosivas"
   - ai_rating=0.65, preferred_range_min=8.0, preferred_range_max=30.0
   - splash_damage=true, lead_target=true
   - is_melee=false, is_instant_hit=false
   - attack_style_modifier=-0.1

5. bazooka.tres:
   - weapon_name="Bazooka", category="Explosivas"
   - ai_rating=0.75, preferred_range_min=10.0, preferred_range_max=40.0
   - splash_damage=true, lead_target=true
   - is_melee=false, is_instant_hit=false
   - refire_rate=0.15 (muy lenta), aim_error_base=1500

6. rifleplasma.tres:
   - weapon_name="RiflePlasma", category="Plasma"
   - ai_rating=0.7, preferred_range_min=10.0, preferred_range_max=35.0
   - splash_damage=false, lead_target=true (proyectil viajero)
   - is_melee=false, is_instant_hit=false
   - refire_rate=0.7

7. pistolaplasma.tres:
   - weapon_name="PistolaPlasma", category="Plasma"
   - ai_rating=0.5, preferred_range_min=5.0, preferred_range_max=20.0
   - splash_damage=false, lead_target=true
   - is_melee=false, is_instant_hit=false
   - refire_rate=0.8, aim_error_base=3000

Cada archivo debe ser un recurso .tres válido. Usa el formato:
[gd_resource type="WeaponAIProfile" load_steps=2 format=3 uid="uid://..."]

[ext_resource type="Script" path="res://scripts/ai/weapon_ai_profile.gd" id="1_xxx"]

[resource]
script = ExtResource("1_xxx")
weapon_name = "..."
ai_rating = ...
...
```

---

# FASE 6: UI/UX - HUD y Selector de Armas

## Resumen
Actualizar la interfaz de usuario para soportar las nuevas categorías y mostrar información relevante (tipo de munición, conteo de proyectiles, etc.).

## Cambios

### team_weapon_selector.gd
- Agregar las nuevas categorías a la lista de selección
- Mostrar icono o tag del tipo de arma (bala, perdigones, arrojadiza, explosiva, plasma)

### hud.gd
- Mostrar el tipo de munición actual
- Para armas con proyectil: mostrar el contador de proyectiles
- Para escopetas: mostrar perdigones por disparo

## Prompt para FASE 6

```
Necesito actualizar la UI para mostrar información sobre los nuevos tipos de armas y municiones.

Contexto:
- hud.gd (CanvasLayer) muestra: nombre del arma, munición actual/reserva, barra de vida
- team_weapon_selector.gd es la pantalla de selección de equipo + arma
- Las nuevas categorías son: Arrojadizas, Explosivas, Plasma
- skill.json ahora tiene categoria_municion en cada arma

Cambios:

1. En team_weapon_selector.gd:
   - Agregar las categorías "Arrojadizas", "Explosivas", "Plasma" al array de categorías
   - Mostrar junto al nombre del arma un pequeño tag del tipo (ej. "USP [Bala]", "M3 [Perdigones]", "Granada [Arrojadiza]")
   - Usar ConfigManager.get_arma() para leer categoria_municion

2. En hud.gd:
   - Agregar un Label para mostrar el tipo de munición del arma actual
   - Conectarse a la señal weapon_changed del Player para actualizar
   - Usar ConfigManager para leer categoria_municion del arma actual
   - Mostrar un texto como "Tipo: Bala" / "Tipo: Perdigones (x8)" / "Tipo: Explosiva"

3. La escena hud.tscn puede necesitar un nuevo Label en el VBox de munición

Lee hud.gd, team_weapon_selector.gd, y hud.tscn antes de modificar.
```

---

# FASE 7: Armas Cuerpo a Cuerpo (Melee) - Mejora

## Resumen
El sistema actual tiene armas melee (Crowbar, Tonfa, Machete) que funcionan como hit-scan de rango cero. Mejorarlas para que tengan un comportamiento más realista.

## Cambios
- Animación de swing
- Detección por área (Area3D frontal) en lugar de raycast
- Knockback al impactar
- Sonidos

## Prompt (breve)

Esta fase es opcional y se puede posponer. El prompt sería corto si se necesita.

---

# FASE 8: Balance y Ajustes

## Resumen
Ajustar valores de daño, velocidad, alcance, etc. para todas las armas basado en playtesting.

## Prompt

Esta fase la maneja el usuario haciendo pruebas y pidiendo ajustes específicos.

---

# FASE 9: Limpieza y Refactor

## Resumen
Eliminar código muerto, asegurar que todo funciona, verificar que no hay errores.

## Resumen Ejecutivo: 9 Fases

| Fase | Descripción | Archivos principales |
|------|-------------|---------------------|
| **1** | skill.json expandido | skill.json |
| **2** | Sistema de proyectiles | projectile_*.gd, explosion.gd, weapon.gd |
| **3** | Integración Player | player.gd |
| **4** | Integración Bots | combat_system.gd, npc_base.gd |
| **5** | Perfiles AI nuevos | *.tres en ai_profiles/ |
| **6** | UI/UX | hud.gd, team_weapon_selector.gd |
| **7** | Melee mejorado | (opcional) |
| **8** | Balance | skill.json + profiles |
| **9** | Limpieza | Varios |

## Dependencias entre fases

```
FASE 1 (skill.json)
	↓
FASE 2 (proyectiles + weapon.gd)
	↓
FASE 3 (player) ──── FASE 4 (bots) ──── FASE 5 (perfiles AI)
	↓                          ↓
FASE 6 (UI)          FASE 7 (melee - opcional)
	↓
FASE 8 (balance)
	↓
FASE 9 (limpieza)
```

Las fases 3, 4 y 5 pueden ejecutarse en paralelo después de la fase 2.
