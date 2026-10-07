# 2.5D Platform RPG - Developer README

A cozy-but-urgent fantasy village RPG. 3D world, mostly top-down 3/4 camera ("2.5D"),
with a village hub that will eventually lead out into goblin-infested fields and
side-scrolling interior segments.

This document is the single source of truth for picking the project up cold. It
describes the current architecture, every system, every entity, the conventions
that must not be broken, and what is still missing.

---

## 1. Quick start

- **Engine:** Godot 4.7, GDScript only.
- **Entry scene:** `res://ui/main_menu.tscn` (set in `project.godot` as
  `application/run/main_scene`) - the start screen. New Game loads
  `res://main.tscn`, the gameplay entry point: a `Node3D` root named `Main` that
  instances `res://scenes/village.tscn` plus the in-game pause menu.
- **Play:** press Play in the editor -> start screen -> New Game -> `Village`.
  See section 16 for the menus and saving.
- **Renderer:** Forward+, D3D12 on Windows, Jolt physics, MSAA 4x,
  physics interpolation ON (see section 12).

Design intent lives in `res://.summer/GameSoul.md` (the onboarding vision).
Binding project rules live in `res://.summerrules`. Read both before adding
features; the rules file is authoritative on input and structure.

---

## 2. Controls

Every action is an InputMap action and every one of them is rebindable in-game.

| Action | Keyboard | Gamepad | Notes |
|---|---|---|---|
| `move_up` | W / Up arrow | left stick up (axis 1 -) | |
| `move_down` | S / Down arrow | left stick down (axis 1 +) | |
| `move_left` | A / Left arrow | left stick left (axis 0 -) | |
| `move_right` | D / Right arrow | left stick right (axis 0 +) | |
| `run` | Shift (hold) | B (button 1) | sprint, 1.8x speed |
| `jump` | Space | A (button 0) | gravity-based hop |
| `dash` | Q | X (button 2) | 3.0 s cooldown; invulnerable for the whole dash |
| `attack` | Left mouse | RB (button 10) | arc in facing direction |
| `parry` | Right mouse | LB (button 9) | timing window, negates damage |
| `interact` | E | - | talk to NPCs. **E only, never Space** |
| `settings` | Tab | Start (button 6) | opens the rebind overlay |

**Movement default is the left stick on a gamepad, never face buttons.** WASD must
not be mirrored onto the D-pad or face buttons. This is deliberate and recorded in
`res://.summerrules`.

`interact` intentionally has no Space binding: Space is `jump`, and Space used to
double as interact, which made jumping next to an NPC start a conversation.

---

## 3. Folder structure

```
res://
  main.tscn                  entry point - instances the village, nothing else
  project.godot              main scene, autoloads, input map, physics, render
  README.md                  this file
  .summerrules               binding project rules
  .summer/GameSoul.md        creative vision (do not edit)

  scenes/
	village.tscn             THE world hub: ground, lane, fields, structures,
							 dressing, actors, checkpoints, UI

  entities/
	player/    player.tscn + player_controller.gd
	npcs/      npc.tscn + npc.gd            base villager
			   villager.tscn + villager.gd  fetch-quest giver (extends npc.gd)
			   wander_npc.gd                shared drift locomotion (no scene)
	animals/   sheep.tscn + sheep.gd
	monsters/  goblin.tscn + goblin.gd
	props/     herb.tscn + herb_pickup.gd

  structures/                reusable buildings, instanced many times
	cottage.tscn   fence.tscn   gate.tscn   pen.tscn   lamppost.tscn

  scripts/                   shared logic and systems
	dialogue_manager.gd      DialogueManager autoload
	input_remap.gd           InputRemap autoload
	health.gd                Health (class_name) shared by player + enemies
	follow_camera_3d.gd      camera rig
	occluder_fader.gd        player-behind-building transparency driver
	checkpoint.gd            per-lamp-post respawn marker
	checkpoint_manager.gd    active respawn point + save file

  ui/
	dialogue_box.tscn + dialogue_box.gd      typewriter dialogue
	settings_screen.tscn + settings_screen.gd  rebind overlay (autoload)

  shaders/  occluder_fade.gdshader
  materials/ wall thatch beam window stone wood wood_opaque gate_beam iron (.tres)
  assets/library/rpg-fantasy-lowpoly/        imported library props (see section 13)
```

**Conventions**
- One entity per file: `res://entities/<type>/<name>.tscn` + `.gd`.
- One reusable scene instanced many times over duplicated scenes. Tune per
  instance with exported values.
- Shared/reusable logic in `res://scripts/`. Buildings in `res://structures/`.
  UI in `res://ui/`.
- `main.tscn` stays thin. Never put world content in it.
- Lowercase file names. Paths are case-sensitive on Linux and in exports.

**Autoloads** (in `project.godot`)

| Name | Path | Purpose |
|---|---|---|
| `DialogueManager` | `res://scripts/dialogue_manager.gd` | line queue + signals |
| `InputRemap` | `res://scripts/input_remap.gd` | binding store, save/load, de-dupe |
| `SettingsScreen` | `res://ui/settings_screen.tscn` | rebind overlay, always reachable |

---

## 4. World layout (`scenes/village.tscn`)

Root `Village` (Node3D). Coordinates are metres; **+X = east, -X = west, -Z =
north / screen-up, +Z = south / toward the camera.** Origin is village centre.
The gate sits on the NORTH edge, straight up the screen from the player's spawn.

The world was turned 90 degrees left (gate east -> gate north) by rotating the
groups rather than by re-authoring every node: `Structures`, `Dressing` and
`Checkpoints`, plus the `Lane` and `Fields` meshes, each carry a 90 degree Y
rotation. A transform written *inside* one of those groups is therefore in the
group's own pre-turn frame - its local +X still points at where the gate used to
be (east), which is now world north. The fence run names (`FenceN01`, `FenceE03`,
...) date from the pre-turn layout and no longer describe the side they sit on.

- `WorldEnvironment` - procedural sky, warm ambient 0.45, tonemap filmic.
- `Sun` (DirectionalLight3D) - warm 1.0/0.92/0.78, energy 1.15, shadows on with
  `shadow_bias 0.04`, `shadow_normal_bias 2.5`, `directional_shadow_blend_splits`,
  `directional_shadow_max_distance 70`.
- `OccluderFader` - see section 11.
- `Ground` (StaticBody3D) - 180x180 grass slab at y=0, with collision.
- `Lane` - 52x4 dirt strip, now running north-south along Z at x=0 (centred
  z=-2), so it leads straight from the village centre out through the gate.
- `Fields` - 50x50 darker green patch centred at world (0, -55), north of the
  gate.
- `Structures/` - `Cottage1..Cottage5`, `Gate` (world 0, 0, -26: on the north
  edge, spanning the lane), `Pen` (world 12, 0, 25 - south-east of centre, holds
  the sheep), and fence runs `FenceN01..N12`, `FenceS01..S12`, `FenceW01..W08`,
  `FenceE01..E06` forming the village boundary with the gap on the NORTH side for
  the gate. Cottages 1-3 sit west of centre at world (-9, 12), (-11, 2) and
  (-9, 8); 4 and 5 are at world (13, 14) and (12, -6).
- `Dressing/` - library props: `BarrelA`, `BarrelB`, `BarrelsByPen`, `Bench`,
  `Anvil`, `Banner`, `Chest`, and a `Market` StaticBody3D holding `Cart` + `Stall`.
  `Dressing/Barrels` is a StaticBody3D holding the collision shapes for the
  barrels (`ByPenBlock`, `BarrelABlock`, `BarrelBBlock`) - the barrel meshes
  themselves are children of `Dressing` but their colliders live here.
- `Actors/` - `Player`, `Villager`, `OldMan`, `Mother`, `Child`, `Sheep1..4`,
  `Goblin1..3`, `Herb`. `Actors` is NOT one of the rotated groups, so these
  transforms are plain world coordinates.
- `Checkpoints/` - checkpoint manager + `LampPostMid`, `LampPostDeep`
  (section 10). This group IS rotated, so a post's local transform is pre-turn.
- `UI` - the `dialogue_box.tscn` instance.

Approximate actor placement (world x, z): Player (6,0) spawn; Villager (2,4);
OldMan (7,-9); Mother (6,15); Child (7,14); Sheep inside the fenced pen at
(9.5..14.5, 21.5..28); Goblins north of the gate, out in the field, at (-6,-34),
(8,-48), (-3,-60); Herb (4,-44) - the quest item is out in the field too.

---

## 5. Player

`res://entities/player/player.tscn` + `player_controller.gd`.

**Scene:** `Player` (CharacterBody3D, **grounded motion mode**), children:
`Visual` (Node3D, holds `Body` capsule + `Front` marker and rotates to face),
`Collision` (CapsuleShape3D r0.35 h1.7), `CameraRig` (follow camera script),
`Camera3D` (current, fov 55), `Health` (the shared Health component, max 5).

> **Motion mode matters.** The player MUST stay on grounded motion mode. In
> floating mode `is_on_floor()` is never true, gravity accumulates forever and
> jams the body into the ground, so the player cannot move at all. This was a real
> bug; do not "simplify" it away.

**Groups:** adds itself to `player`.

**Public API other systems use**
- `apply_damage(amount, source)` - the ONLY way to hurt the player. Checked in
  this order: an active dash negates the hit (i-frames, pale flash, no damage);
  an open parry negates the hit and shoves the player back; otherwise the damage
  reaches the `Health` child.
- `is_alive()`, `facing_dir()`, `has_herb()`.

**Exported tunables**

| Group | Export | Value | Meaning |
|---|---|---|---|
| Movement | `speed` | 4.2 | walk m/s |
| | `turn_speed` | 14.0 | Visual turn rate |
| | `run_multiplier` | 1.8 | sprint multiplier while `run` held |
| | `gravity` | 24.0 | |
| | `jump_velocity` | 7.0 | |
| Dash | `dash_speed` | 16.0 | |
| | `dash_duration` | 0.18 | this whole window is invulnerable |
| | `dash_cooldown` | 3.0 | hard; a press during cooldown does nothing |
| | `invulnerable_while_dashing` | true | i-frames for the entire dash |
| Attack | `attack_damage` | 12.0 | |
| | `attack_cooldown` | 0.5 | |
| | `arc_reach` | 2.0 | arc radius in front of facing |
| | `arc_half_angle_deg` | 60.0 | either side of facing |
| | `attack_visual_time` | 0.18 | how long the wedge shows |
| Parry | `parry_window` | 0.4 | open window |
| | `parry_cooldown` | 0.7 | |
| | `parry_knockback_distance` | 0.5 | metres pushed back on a successful parry |
| | `parry_knockback_time` | 0.15 | |

**Death / respawn**
`Health.died` -> the player freezes for `respawn_delay` (0.4 s), then moves to the
active checkpoint (or back to its scene position if no checkpoint has been
reached) and is revived to full health. There is no death animation or game-over
screen yet.

**Dash i-frames**
For the whole of `dash_duration` - from the frame the dash starts to the frame it
ends - the player cannot be hurt. `apply_damage()` returns early and flashes the
attack wedge pale (`DASH_IFRAME_COLOR`) so a working i-frame does not read as a
broken enemy. This is checked BEFORE parry, so a dash is never punished by a hit
that lands mid-burst. Set `invulnerable_while_dashing` to false if some future
enemy is meant to be able to hit through a dash.

**Attack arc**
The damage test and the visible wedge use the SAME numbers (`arc_reach`,
`arc_half_angle_deg`), so what you see is what you hit. Enemies are found through
the `goblin` group on the swing - never a per-frame scene-tree walk. It was once
a thin sideways rectangle that did not match the damage region; the wedge is built
as a triangle fan opening along -Z.

---

## 6. Goblins

`res://entities/monsters/goblin.tscn` + `goblin.gd` (extends `wander_npc.gd`).

**Scene:** `Goblin` (CharacterBody3D), `Visual` (Body/Head/Snout), `Collision`,
`Health` (max 30). Adds itself to group `goblin`.

**State machine**

| State | Behaviour |
|---|---|
| `WANDER` | slow drift around its patch at `speed` (base class) |
| `CHASE` | closes on the player at `chase_speed` once inside `watch_radius` |
| `ATTACK` | a 1 s swiping animation; damage only inside the hit window |
| `RETREAT` | runs `retreat_distance` after the swipe |
| `STUNNED` | hit by the player: the swipe is CANCELLED, shoved, held still |

**When a swipe may start:** the player is inside `attack_range` AND either the
goblin just chased them there, or it is already facing them within
`facing_angle_deg`.

**The swipe** is a narrow blade mesh parented to `Visual` that sweeps across the
arc over `attack_duration`. Damage can land only between `hit_window_start` and
`hit_window_end` (0.2 - 0.85 s of the animation), once per swipe, and only inside
`swipe_half_angle_deg`. Outside the window it is pure animation. Being hit at any
point cancels the swipe and discards the pending hit, so a goblin that was just
hit cannot attack.

**Exports:** `hostile` (false = peaceful, wanders and stares only),
`watch_radius` 6, `lose_radius` 9, `chase_speed` 1.8, `attack_range` 1.2,
`facing_angle_deg` 50, `attack_duration` 1.0, `hit_window_start` 0.2,
`hit_window_end` 0.85, `swipe_half_angle_deg` 60, `blade_half_angle_deg` 16
(cosmetic only), `swing_grace` 0.35, `swing_damage` 1.0, `retreat_distance` 4.0,
`retreat_speed` 2.8, `stun_time` 0.35, `knockback_speed` 4.0, `knockback_time`
0.12.

> **Why the knockback is split from the stun.** Shoving for the whole stun threw
> the goblin out of the player's reach and the follow-up swing whiffed, which made
> a kill take four hits instead of three. The shove is short (`knockback_time`)
> and the rest of the stun is spent standing still.

All three goblins share `goblin.tscn` and `max_health = 30`; they have identical
health. Damage 12 means three clean hits.

---

## 7. NPCs

**`wander_npc.gd`** (no scene) - the shared locomotion base. Drifts around a spawn
point, freezes while `DialogueManager` is active, and exposes `face_dir()` which
turns the `Visual` child so its -Z points along a direction. NPCs, sheep and
goblins all inherit it. Exports: `speed`, `wander_radius`, `pause_min`,
`pause_max`.

**`npc.tscn` + `npc.gd`** - the base villager (extends `wander_npc.gd`). One scene
covers every villager; variants are made by overriding exports per instance:
`speaker_name`, `body_color`, `body_scale`, `lines` (PackedStringArray),
`face_player_when_talking`. It has an `InteractionArea` (Area3D); when the player
is inside and presses `interact` it starts a dialogue. Override `get_lines()` in a
subclass to change what is said.

Village variants using `npc.tscn` directly: `OldMan`, `Mother`, `Child` - each
just overrides name, colour, scale, lines and drift.

**`villager.tscn` + `villager.gd`** - the fetch-quest giver (extends `npc.gd`).
Overrides only `get_lines()`: if the player's `has_herb` meta is set she plays the
thank-you lines, otherwise the ask lines. This is the quest loop with the herb
(section 9).

---

## 8. Animals and props

**Sheep** - `sheep.tscn` + `sheep.gd` (extends `wander_npc.gd`). All behaviour is
the inherited drift, tuned small, so the flock grazes inside the pen. Adds group
`sheep`. Four instances live under `Actors/`.

**Herb** - `herb.tscn` + `herb_pickup.gd` (Area3D). Walking into it sets the
player's `has_herb` meta and frees itself. The quest flag deliberately lives on
the player, not on the pickup, so the dialogue loop survives the pickup being
freed. Exports `herb_meta` and `spin_speed`.

---

## 9. Structures

| Scene | What it is | Notes |
|---|---|---|
| `cottage.tscn` | one cottage | StaticBody3D + walls/roof/black doorhole/two windows/chimney + a box collider, plus a `DoorTrigger` in the doorway. Instanced 5x. Uses the shared fade materials. |
| `fence.tscn` | one 5 m fence run | three posts, two rails, box collider. Instanced ~38x for the boundary. Uses `wood_opaque.tres`. |
| `gate.tscn` | the village gate | wooden gate spanning the lane at world z=-26, the north edge. Uses the fade materials. |
| `pen.tscn` | the sheep pen | a 10x10 enclosure built from fence instances, with an opening. |
| `lamppost.tscn` | checkpoint lamp post | see section 10. The lantern stays dark until this post is the active save point. |

> Fence and pen deliberately use `res://materials/wood_opaque.tres`, NOT the fade
> shader: they are only 1.15 m tall, shorter than the player, so they must never
> go transparent.

### Interiors and doorways

The vision's side-view segments: inside a building the view flattens to a side-on
read and the room is walked left-to-right, like a platformer level. This is the
project's first switch from the 3D village to that 2.5D mode.

- `res://scenes/interior_cottage.tscn` and `res://scenes/interior_house.tscn` are
  the two interiors, reached through the black doorholes of `Structures/Cottage3`
  (north-west) and `Structures/Cottage5` (north-east). Each is one room - floor,
  back and side walls, ceiling plus furniture, all primitives - lit by a warm
  hearth light and a cool one by the door. They differ in width, furniture and
  lighting, so the two houses do not read as the same room.
- **Which cottages can be entered is per instance, not baked into the shared
  scene.** `res://structures/cottage.tscn` carries
  `res://scripts/enterable_cottage.gd`, whose `enterable` and `interior_scene`
  exports are set per instance in `village.tscn` - the same pattern as a lamp
  post's `checkpoint_id`. An enterable cottage hides its brown `Door` and shows
  the black `DoorHole`; a shut one does the opposite and switches its
  `DoorTrigger.monitoring` OFF, so bumping a shut wall can never change scene.
- `RoomCamera` is a `Camera3D` 21 m in front of the room at `fov 22`. That narrow
  field of view is what flattens the real 3D room into a side-on view.
  `res://scripts/interior_cottage.gd` levels it first - an authored yaw is only a
  few degrees, but at that distance it swings the view far enough sideways to push
  one side wall, and the doorway in it, clean off the screen - then pans it along
  X to keep the player framed, clamped so it never looks past a side wall. An
  arriving player is placed `entry_inset` inside the door rather than against it,
  so they are on screen immediately instead of at the very edge of the frame.
- **The room shell is solid.** `Floor`, `BackWall`, `SideWallLeft` and
  `SideWallRight` are each a `StaticBody3D` with a `MeshInstance3D` and a matching
  `CollisionShape3D` child, so the player is stopped by every wall and can only
  leave through the doorway. An invisible `FrontBarrier` `StaticBody3D` - a
  `CollisionShape3D` with no mesh, so it cannot be seen against the camera - closes
  the open fourth side that the camera looks through, so the room cannot be walked
  out of that way either. Each wall keeps its mesh and its collider as separate
  children rather than one node, because a `MeshInstance3D` carries no collision of
  its own.
- **The doorway** is `res://scripts/door_trigger.gd`, an `Area3D` with a
  `target_scene` and a `leads_inside` flag that says which of its two jobs it does.
  - `leads_inside = true` (the cottage's `DoorTrigger`) fires as soon as the player
    touches it - the building wall stops them at the door anyway - and remembers
    the spot just outside plus the direction they were moving.
  - `leads_inside = false` (the interior's `ExitDoor`) fires only when the player
    is HEADING OUT, moving along its `outward`. Touching the doorway from the deep
    side does nothing, so brushing past it is not mistaken for leaving. It needs no
    run-up: the room's own wall is what the player walks into.
  - The inside test runs **every frame while the player overlaps**, not only on
    `body_entered`, and it accepts the way the player is FACING when the wall has
    already cancelled their velocity. Both matter now that the walls are solid: the
    player is placed about a metre inside the door, which can already overlap the
    trigger the moment the room loads, so an entry-only test would fire while they
    were still standing at the spawn - and once they walked into the wall their
    velocity would be zero and it would never fire at all. A `_has_moved` guard
    keeps a fresh spawn from firing the exit merely by facing outwards.
- **Which wall the interior door sits on comes from the way the player came in**,
  not from the room's own layout. `interior_cottage.gd` reads the travel direction
  out of the payload and moves `ExitDoor`, `ExitDoorHole` and `DoorLight` onto that
  wall (setting `outward` to match), so walking on carries the player deeper into
  the house and turning back takes them out the way they came.
- **Leaving puts the player beside the door they used**, not at a scene spawn. The
  exit builds its arrival from the doorway remembered on the way in -
  `exit_clearance` beyond it, plus `lateral_clearance` to the opposite side when the
  player left sideways - and hands it to `res://scripts/entry_spawn.gd` in the
  village, which applies it one frame later.
- **The player keeps the facing they left with.** That same travel direction is
  handed to the player's `set_facing()` on arrival - by `entry_spawn.gd` when
  leaving a building, and by `interior_cottage.gd` when entering one - so walking
  out of a door facing left leaves you facing left on the street instead of
  snapping back to the player scene's default facing.
- `res://scripts/scene_router.gd` (`class_name SceneRouter`) carries that payload
  across the scene change as static state, so no autoload was needed and
  `project.godot` is untouched.
- The cottage's `DoorHole` uses the fade shader with a near-black albedo, so it
  fades along with the rest of the cottage when the player walks behind it.

> A door trigger sits IN the doorway, so the arrival point has to be clear of the
> trigger box or the player bounces straight back through it. The interior enters
> the player 1.4 m inside its door, and the village arrival lands 1.2 m beyond the
> cottage doorway - clear of a box that is only 1 m deep.

---

## 10. Checkpoints and saving

Two small scripts plus one reusable scene.

**`res://scripts/checkpoint.gd`** - on `lamppost.tscn`. When the player enters its
`CheckpointArea` (a sphere, `radius = 4.0` - the requested 4 m radius) it tells the
manager to activate itself. Exports `checkpoint_id` and `respawn_offset`
(default `(0, 0, 1.6)`, i.e. the player is placed just south of the post).
It skips work if it is already the active post, so walking back and forth does not
re-save.

**`res://scripts/checkpoint_manager.gd`** - the `Checkpoints` node in the village.
Holds the active respawn point and writes it to `user://checkpoint.cfg`
immediately on activation. Loads it again at startup, so the recorded point
survives quitting. `respawn_position(fallback)` returns the fallback (where the
village placed the player) until a checkpoint has actually been reached.

**Placed posts:** `LampPostMid` id `field_mid` at world (-8, 0, -50) and
`LampPostDeep` id `field_deep` at world (12, 0, -64), both out in the field north
of the gate. The most recently reached post is the respawn. (The old
`LampPostField` id `field_gate` has been removed.)

**The lit lamp.** `res://scripts/lamppost.gd` extends `checkpoint.gd` and
overrides its `set_lit()` hook, so the lamp post scene still carries ONE script:
while this post is the active save point the lantern glass glows (emission on,
albedo up) and its `Glow` OmniLight3D shines; as soon as another post takes over
it goes back to dark glass with the light off. Exactly one lamp in the village
burns at a time.
The manager announces every change with the `checkpoint_activated(id)` signal.
A post is a CHILD of the `Checkpoints` group, so its `_ready` runs BEFORE the
manager's - looking the manager up on that same frame finds nothing, which is
why no lamp lit at all to begin with. `checkpoint.gd` therefore defers the
lookup by one frame and then also reads `current_id()`, so the point restored
from `user://checkpoint.cfg` lights its lamp on a fresh boot rather than leaving
every post dark.
Nothing is wired per instance: the `Lantern` mesh and `Glow` light are found by
name, and the glass material is duplicated before it is touched, so posts never
share one material.

**Adding a post:** instance `lamppost.tscn` under `Checkpoints` and give it a
unique `checkpoint_id`. Nothing else is needed - posts find the manager through
the `checkpoint_manager` group.

---

## 11. Systems reference

### `dialogue_manager.gd` (autoload `DialogueManager`)
A tiny line queue with signals. `start(lines, speaker)`, `advance()`,
`current_speaker_name()`, and the boolean `active`. Signals:
`dialogue_started`, `dialogue_ended`, `line_shown(text)`.
It holds no quest state: the quest flag lives as metadata on the player.

### `dialogue_box.tscn` + `dialogue_box.gd` (`res://ui/`)
CanvasLayer with a name plate and a RichTextLabel. Types the current line out at
`CHARS_PER_SECOND = 45`. Pressing `interact` once finishes the line early, again
advances. Freezing the world during dialogue is not done here - every actor
listens to `dialogue_started` / `dialogue_ended` and freezes itself.

### `input_remap.gd` (autoload `InputRemap`)
The single owner of bindings.
- **Startup always uses the project defaults.** `_ready()` only runs
  `_sanitize_defaults()`; it deliberately does NOT call `load_bindings()`, so an
  in-game rebind is never permanent - relaunching the game comes back up on the
  defaults. `load_bindings()` is kept for the future "apply" button that will
  make an in-game change stick.
- `ACTIONS` - the ordered list of the 11 rebindable actions with display labels.
- `rebind_action(action, event)` - replaces that action's events, removes the event
  from any other game action using it (newest binding wins), then saves.
- `save_bindings()` / `load_bindings()` - ConfigFile at
  `user://input_bindings.cfg`. Loading happens once in `_ready()`, before the
  first scene runs.
- `binding_text(action)`, `event_to_text(event)`, `action_entries()` - used by the
  settings screen.
- `_sanitize_defaults()` - runs BEFORE the saved bindings load, and drops
  duplicate events inside an action and any event already claimed by an
  earlier-listed action. Jump is listed before interact, which is what strips
  Space off `interact`. A deliberate player rebind still wins because it loads
  afterwards.

### `settings_screen.tscn` + `settings_screen.gd` (autoload `SettingsScreen`)
Modal rebind overlay toggled by the `settings` action. Lists all 11 actions,
shows the live binding, and rebinds on click-then-press. While open it pauses the
tree (it is `PROCESS_MODE_ALWAYS`) so gameplay gets no input, and it consumes the
events it handles. `Esc` cancels a capture or closes. Rebinding wins over the
toggle, so Tab itself can be rebound. It talks to the singleton by node path
(`/root/InputRemap`) and calls it dynamically.

### `health.gd` (`class Health`)
The one health implementation, shared by the player and every enemy. Add it as a
`Health` child, set `max_health`. API: `take_damage(amount, source) -> bool`,
`heal()`, `is_alive()`, `ratio()`, `revive()`. Signals `damaged(amount, source)`
and `died`. `invulnerable` ignores damage.

> **Gotcha fixed here:** once health hit 0, `take_damage` used to bail because the
> target was "no longer alive", which made anything at 0 hp permanently immune.
> `revive()` and the death flow exist because of that.

### `follow_camera_3d.gd`
Fixed 3/4 follow rig. It only ever PITCHES - roll is hard-locked to 0 and it
never yaws with the player - so the 3D world stays locked to the screen like a 2D
view. It is meant to be a child of what it follows (empty `target_path` = follow
the parent). Exports: `pitch_degrees` (-40, the cozy "lowered" angle; -50 reads as
flat top-down, -30 sits almost behind), `distance` 12, `height` 1,
`follow_smoothing` 8 (higher = tighter). `set_target()` / `target_node()` are
available.

### `occluder_fader.gd` + `shaders/occluder_fade.gdshader`
Makes a building become see-through when the player walks behind it.
- Lives on the `OccluderFader` node. Exports: `player_path`, `fade_objects`
  (NodePaths to cottage instances and the gate), `screen_radius` 0.36 (a fraction
  of viewport height - this is the reveal circle size), `min_alpha` 0.12,
  `softness` 0.35, `center_offset_y`, `behind_margin` 0.
- A structure may fade only when BOTH hold: the player is genuinely behind it
  (past its far footprint edge along the camera's horizontal view direction), and
  the fragment is inside the screen-space circle around the player's projected
  feet AND nearer the camera than the player.
- **Cost model:** player, camera, structures, their AABBs and their duplicated
  material lists are resolved once in `_ready`. Per frame it early-returns unless
  the player or camera moved, projects the feet once, runs four XZ dot products
  per structure, and writes only what changed. No traversal, no raycasts, no
  physics queries per frame.
- Each structure gets its own duplicated ShaderMaterial, because the materials
  are shared between all five cottages.
- `fade_objects` is `Array[NodePath]` rather than `Array[Node3D]` because the
  `.tscn` parser rejects a NodePath inside an Array of Objects and loads the array
  empty. The paths resolve in `_ready`.
- `behind_margin` is 0 for a reason: it was 0.35, exactly the player's collider
  radius, so pressing against a north wall landed precisely on the gate boundary
  and the reveal dropped out.

### `shaders/occluder_fade.gdshader`
Spatial shader with `blend_mix` and **`depth_draw_always`**. It carries the albedo
/ roughness / metallic / emission uniforms so it replaces the structures' original
StandardMaterial3D, plus `fade_active`, `fade_screen_center`, `fade_screen_radius`,
`fade_screen_aspect`, `fade_min_alpha`, `fade_softness`, `fade_depth_margin`,
`fade_center`.

> **Why `depth_draw_always`:** without it the material never wrote depth, so a
> cottage's own parts (wall, roof, window, chimney) were ordered purely by draw
> order, which flips at grazing angles - producing the window/chimney pop-in at
> the screen edges.

---

## 12. Rendering and project settings

- **Materials** (`res://materials/`) are shared `ShaderMaterial` `.tres` files
  using the fade shader, preserving the original colours: `wall`, `thatch`,
  `beam`, `window` (emissive), `stone`, `wood`, `gate_beam`, `iron`. Plus
  `wood_opaque.tres`, a plain StandardMaterial3D used by the fence and pen so they
  never fade.
- **Anti-aliasing:** `rendering/anti_aliasing/quality/msaa_3d = 2` (4x). Without
  it every edge looks jagged.
- **Shadows:** `rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality = 4`
  (Soft Ultra). This engine build has no per-light `shadow_filter` property, so
  PCF quality is set globally. Per-light `shadow_bias` / `shadow_normal_bias` live
  on the `Sun` in the village scene.
- **Physics interpolation** is ON (`physics/common/physics_interpolation = true`)
  so movement is smooth rather than stepped.
- Ground, lane and field keep plain opaque materials on purpose.

---

## 13. Assets

The game uses ONE pinned library collection: **`rpg-fantasy-lowpoly`** (stylized,
handpainted). Library assets must all come from it. Imported props live in
`res://assets/library/rpg-fantasy-lowpoly/`: barrel, barrels, bench, cart,
stall-cart-empty, banner-1, chest-closed, anvil.

The collection has no characters and no monsters - those are placeholder
primitive shapes for now. Several are CC-BY and must be credited before shipping:
append the attribution lines to `res://LICENSES_SUMMER_ASSETS.md` if it exists.

---

## 14. Known gaps / good next steps

- **No HUD.** Player health is not shown anywhere; it exists on the Health node.
- **No death feedback.** Death is a 0.4 s freeze and a teleport. No animation, no
  game-over screen, no invulnerability window after respawn.
- **Goblins have no real AI** beyond wander/chase/swipe/retreat. No aggro tiers, no
  group behaviour, no ranged attacks.
- **Placeholder art.** Player, NPCs, sheep and goblins are primitive meshes.
  `player_controller.gd` already drives an `AnimatedSprite3D` named
  `AnimatedSprite3D` with `walk_<dir>` / `idle_<dir>` clips if you add one, with
  no code changes.
- **Only one interior** so far (the cottage behind Cottage1). The rest of the
  side-scrolling segments the vision calls for do not exist yet.
- **Only one enemy type** and one quest loop.
- **The `[input]` section of `project.godot` contains duplicated events.** The
  editor's bind operation only appends and there is no remove; a raw text edit to
  `[input]` is blocked by an engine guard. `InputRemap._sanitize_defaults()` strips
  them at runtime so they do not cause double input, and the settings screen reads
  the cleaned live bindings. To clean the file itself, remove the repeated rows in
  the editor's Input Map panel.

---

## 15. Gotchas learned the hard way

- **CharacterBody3D motion mode.** Grounded for anything using gravity and
  `is_on_floor()`. The player sat in floating mode and could not move at all.
- **Bind operation appends.** `InputMapBind` adds events and never removes, so
  binding the same action twice duplicates it.
- **`interact` must never include Space.** Space is jump.
- **`InputEventKey` has no `set_modifiers_mask()`.** `InputEventWithModifiers`
  exposes only `get_modifiers_mask()`; a saved binding's modifiers are restored
  through `shift_pressed` / `ctrl_pressed` / `alt_pressed` / `meta_pressed`. The
  old call in `input_remap.gd` threw "Invalid call. Nonexistent function" inside
  the `InputRemap` autoload's `_ready`, so the game errored on every startup that
  had a saved `user://input_bindings.cfg`.
- **The `.tscn` parser refuses a NodePath inside `Array[Object]`.** Use
  `Array[NodePath]` and resolve in `_ready`.
- **Transparent materials need `depth_draw_always`** or their own parts z-fight at
  grazing angles.
- **`writeFile` refuses to overwrite a file you have not read in full this
  session** - read first, then write.
- **Duplicate-export declarations are a hard parse error.** When adding exports to
  a large script, check the file does not already declare them.
- **Stale diagnostics.** The console keeps old parse errors from earlier loads in
  the same session. Per-file `state:script-errors` is the truth. The project index
  also still lists `res://scripts/player_controller.gd` and
  `res://scripts/quest_npc.gd` as canonical - those files were deleted during the
  3D restructure and do not exist. The live player controller is
  `res://entities/player/player_controller.gd`.

---

## 16. Menus and saving

**Start screen** `res://ui/main_menu.tscn` (the main scene). Title "Skadoosh!"
plus New Game / Load / Settings / Quit. New Game calls `SaveGame.new_game()`
(which erases the previous run's lamp-post checkpoint so state never carries
over) and then loads `res://main.tscn`. Load and Settings are pages inside the
same scene; each raises `back_requested`, and Escape or the bottom-left Back
button goes up one level.

**Settings** `res://ui/settings_menu.tscn` is instanced by both the start screen
and the pause menu. It lists Gameplay / Audio / Video / Input; the category pages
are placeholders except Input, which opens the `SettingsScreen` overlay - the
rebind list driven by the `InputRemap` autoload.

**In-game menu** `res://ui/pause_menu.tscn`, instanced by `res://main.tscn` so it
only exists while playing. From the top: "Save & Quit", then "Settings". It opens
and closes on `ui_cancel` (Escape) and on the `settings` action (Tab / gamepad
START). One press opens it and it STAYS open: a release lock ignores the actions
until every bound key is physically up, so a held key cannot flicker it shut.
Opening pauses the tree and closing restores the previous paused state.

**Saving** `res://scripts/save_game.gd` (autoload `SaveGame`) owns slots in
`user://saves/<id>.cfg`. `new_game()` starts a fresh slot, `set_checkpoint(id,
pos)` records the lamp post (called by the checkpoint manager and each lamp post),
and `save_active()` (Save & Quit) stamps the slot's time. `list_saves(n)` returns
the newest first as `{id, name, date}` with the date formatted
`YYYY/MM/DD HH:MM:SS` in local time; the name is the placeholder "Unnamed" until
a naming screen exists. `load_slot(id)` writes the point back into
`user://checkpoint.cfg`, which the village's checkpoint manager already restores -
so the loaded lamp lights and the player respawns there. The manager also places
the player at that point on scene entry (deferred one frame, via
`consume_pending_spawn()`), so Load starts you at your last lamp post.
