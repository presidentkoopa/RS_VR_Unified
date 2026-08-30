# RS_Grenade — new lane brief

Paste this into a fresh session to start. Written 2026-08-29 from the RS_Hands work.

## The goal

A **universal VR grenade** for DoomVR: pick it up, pull the pin, cook it, throw it
with your actual arm. It must work in vanilla Doom and in mods that already have
their own grenades (Brutal Doom, Project Brutality) without a per-mod patch.

"Universal" is the hard part and it is a design question, not a coding one —
see **Decide first** below.

## What already exists to build on

This is the point of doing it in RS_VR_Unified rather than from scratch. All of
it is live, tested in a headset, and documented in-file.

| System | File | What it gives a grenade |
|---|---|---|
| `RS_Held` | `zscript/hands/rs_held.zs` | Held-state machine. Borrows and restores actor flags safely, two-handed carry, hand-to-hand pass, per-hand ownership. A grenade in a hand is already a solved problem. |
| `RS_Swing` | `zscript/hands/rs_swing.zs` | Controller velocity and angular-rate tracking. **This is the throw.** Already feeds the existing throw path. |
| `RS_Reach` | `zscript/hands/rs_grab.zs` | Palm centre, `HandPitch`, grab-volume scoring, and the `Flag`/`Num`/`Opt` cvar helpers every subsystem uses. |
| `RS_Pull` / `RS_Cone` | `zscript/hands/rs_distance.zs` | Distance grab, arc flight, route-aware arc survey (`MeasureArc`). Lets you yank a grenade off a shelf. |
| `RS_GrabPolicy` | `zscript/hands/` | Per-class rules and weights deciding what is grabbable. A grenade needs an entry. |
| `RS_GripArbiter` | `zscript/arbiter/rs_griparbiter.zs` | Cross-pk3 grip claims via `Service`/`ServiceIterator`, so two subsystems never fight over one actor. |
| Holsters | `zscript/holsters/` | Belt storage. Grenades on a belt is the obvious home. |
| Throw path | `rs_held.zs` (`Release`) | Clearance step before `RestoreFlags` while `THRUACTORS` is still borrowed. Reuse it; do not write a second one. |

Engine fields added by this fork, both usable by a grenade:
- `AActor.VoxelOverride` — force a voxel on one actor, ignoring `r_drawvoxels`.
- `AActor.ForceModelAngles` — honour this actor's pitch/roll even when its
  MODELDEF does not opt in. Needed by anything wearing a borrowed model.

## Decide first (these change the whole shape)

1. **Adopt or provide?** BD and PB ship grenades already. Does RS_Grenade
   *replace* them, *wrap* them (find the mod's grenade class and give it VR
   handling), or only provide its own when the host mod has none? Wrapping is
   the "universal" answer and the hardest.
2. **Pin gesture.** Two-handed pull is the obvious VR answer and it is also the
   one that requires both hands free. Alternative: grip + trigger on the same
   hand. Needs a real decision, not a default.
3. **Cook timer.** Does holding it after the pin start a fuse? Does releasing
   the grip while cooked drop it at your feet? That is a genuine VR danger
   moment and probably the best thing about the whole feature.
4. **Bounce.** A grenade that slides is wrong. This is the same problem as
   "give thrown objects real physics" — see **Physics** below.

## Physics (relevant and unbuilt)

The fork has a solver (`src/playsim/p_physics.cpp`, `vr_physics_*` cvars) that
already models the hands as solid bodies. Its header exposes only
`P_PhysicsFrame` / `LevelStart` / `LevelEnd` / `RemoveBody` — **there is no
public add-body call**, so nothing in ZScript can hand it an actor.

The fix is one small engine export, something like `P_PhysicsAdoptBody(AActor*)`,
called at release. No clone needed; the object stays the same actor and starts
being simulated. A grenade is the best possible reason to finally build it.

## Traps that will cost a day if rediscovered

- **There is no ZScript test-compile.** Only a real engine load validates syntax.
  `build.ps1` reporting `VERIFIED OK` means the pk3 is well-formed — it is NOT a
  compile check.
- **A ZScript error is fatal AND global.** It stops every pk3 later in the load
  order from compiling too. One bad line breaks unrelated mods.
- ZScript has **no `Name` constants** (int/float/string/bool only), **no 2D
  arrays** (flatten to `[player*COUNT + h]`), and `Array<Struct>` does not compile.
- **`AttackPitch` and `OffhandPitch` are stored pre-negated** by the VR backends.
  Use `RS_Reach.HandPitch(pmo, hand)`, which is where the tree undoes it. Do not
  write a private negation.
- **`AttackRoll` is zeroed every tic** inside `P_PlayerThink`. For real wrist roll
  read `MainHandRoll` / `OffhandRoll`.
- **Logs**: `E:\UZDXREMA\build-dxr\Debug\log-debug.txt` (gameplay `Console.Printf`)
  and `doomxr-log.txt` (load order). They **truncate on every launch** — read
  before relaunching. Mod-side hand diagnostics gate on `rs_hand_debug` (the
  noisy ones) and `rs_hand_trace` (weapon-slot and carry only).
- Build: `E:\mERGE\RS_VR_Unified\build.ps1`, no args.

## Suggested first step

Do not start with the grenade. Start by reading `rs_held.zs` `Release()` and
`RS_Swing`, and get a plain inert object throwing the way a grenade would need
to. If the throw is not right, nothing downstream matters.
