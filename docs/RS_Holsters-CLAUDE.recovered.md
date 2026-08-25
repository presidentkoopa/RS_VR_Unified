# RS Holsters — project context

Claude Code auto-loads this file for any session opened in this repo — that
is deliberate, not a rename of convenience. If you're a fresh agent reading
this cold: this is the handoff doc, written so you don't have to rediscover
any of it. Not a user-facing doc — see README.md for that.

## Working with the owner

- **No test-compile exists here.** Don't burn turns manually re-verifying
  ZScript syntax (brace counting, re-reading a whole file to eyeball it) —
  run the build and find out from a real load/headset error instead. Owner's
  own words: "if there are syntax errors we will find out on compile, i
  can't spare 500k tokens for it."
- **Don't bounce confirmations back as questions.** When the owner reports
  what they're seeing in headset (a position, an angle, "X is left of Y"),
  that's ground truth, not an invitation to ask "does that look right to
  you?" — take it as given and either act on it or move to the next thing.
  Asking them to re-confirm what they just told you reads as not listening,
  and it makes them angry. If there's a genuine fork in what to BUILD (e.g.
  which hand an anchor should track), that's worth asking about; whether an
  already-reported observation is "good" is not.
- Owner tests live in a headset mid-session and reports back in real time,
  including mid-turn while you're still working — expect rapid, informal,
  sometimes sharp corrections, and expect to revise a just-shipped design
  based on one screenshot. That's the normal workflow here, not a sign
  something went wrong.

**Split history.** This mod started as `RS_Holsters`, was renamed wholesale to
`RS_HardPoints` when the forearm/wrist feature landed, then **split in two** on
2026-08-23. The arm rig (the 6 off-hand-anchored forearm/wrist anchors, old
indices 8-13) moved to its own repo at `E:\RS_HardPoints`, which keeps the
`RS_HardPoint*` / `rs_hardpoint_*` naming. This repo kept the 8 torso holsters
and reverted to `RS_Holster*` / `rs_holster_*` / `rs-holster-*`.

The two are designed to be **loaded at the same time**, so everything that could
collide is separated: class names, cvars, netevents, MENUDEF option ids, KEYCONF
section, MODELDEF class blocks, sprite name (`RSHM` here, `RSHP` there), model
and skin filenames, and the saved profile files (`holster_*` here,
`hardpoint_layout` there -- they previously both wrote plain `seated`/`standing`
and would have overwritten each other's tuning with a table of a different
length).

**The one real coupling is grip, and it is solved.** The engine synthesises
F13/F14 for a holster-context grip, and a key binds to exactly ONE alias -- so
two mods each claiming F13 means the second one loaded silently wins and the
other never sees a grip press again. Both mods bind their own alias name and
both aliases fire the SAME `rs-vrhp-grab-main` / `rs-vrhp-grab-off` netevent,
which every handler receives. Arbitration needs no coordination because it
already existed: `doSwap` returns immediately unless the hand is inside one of
that mod's own anchors, and a hand is only ever in one place. **If you add a
third mod in this family, listen for `rs-vrhp-grab-*` too.** Neither mod ships
a default bind for F13/F14 -- owner binds them by hand.

**NOT renamed, on purpose:** bare internal identifiers with no `RS_`/`rs_`
prefix -- `GetHolster()`, `HOLSTER_COUNT`, `holsterActive()`,
`holsterPropScale()`, `dumpOneHolsterProp()` -- plus prose comments using
"holster" as an English word. Both repos share these; they are private, never
referenced across pk3 boundaries, and sweeping them buys nothing but risk.
`HolsterClaimMain/Off` and `GripContextMain/Off` are engine-native
(`E:\UZDXREMA`) and this mod only reads/writes them.

## Architecture, in one picture

`RS_HolsterManager` (EventHandler, `RS_Holsters.zs`) is the only stateful
owner. It runs the whole loop every tic: calibrate -> body yaw -> grabs ->
claims -> props. `GetHolster(idx, ...)` is the compile-time table of all 8
anchor definitions (position, radius, base orientation) -- a switch, not an
array of structs, because ZScript dynamic arrays only accept integral/object
types. Everything else (`edFwd`/`edSide`/`edFrac`/`edPitch`/`edYaw`/`edRoll`)
is the LIVE, tunable copy of that table, seeded from it once and then
overwritten by Edit Mode dragging or a loaded JSON profile.

All 8 indices are torso anchors, positioned off `HmdPos` + `bodyYaw`: the hip
pair, head pair, pectoral pair, and second hip pair, tiered on by
`rs_holster_active_count` (2/4/6/8).

**DEAD-BUT-COMPILING ARM-RIG CODE, and why it is still here.** The arm rig
moved out, but `isHandAnchored()`, `handBasisPose()`, `handAnchorPos()`,
`worldToHand()`, `FOREARM_YAW_CORRECTION` and `FOREARM_HOLSTER_END` all remain.
`HAND_HOLSTER_START` stays 8 while `HOLSTER_COUNT` is now 8, so every valid
index is below it and `isHandAnchored()` is always false -- every branch those
guard is unreachable. That is deliberate, not an oversight: `isHandAnchored` is
the predicate that anchor placement, orientation, edit-mode dragging and claim
arbitration all branch on, and tearing out its every call site by hand, in a
codebase with no way to test-compile, is a far larger risk surface than one
constant pointing past the end of the table. **Dead code still has to compile**
-- that is why `FOREARM_YAW_CORRECTION` was restored after being deleted:
`handBasisPose` still references it, and removing the constant while leaving its
consumer standing would only have surfaced as a load failure in the headset.

If you want it genuinely gone, delete it as its own commit with nothing else in
it, and expect a load-error round trip or two. The live copy of all of it is in
`E:\RS_HardPoints`.

Two visible actor classes, both in `RS_HolsterProp.zs`:
- `RS_HolsterMarker` (+ `_Blue`/`_Red`/`_Gold`/`_Purple`/`_Orange`/`_Green`/
  `_Cyan`/`_Pink`) -- the always-present ring/reticle at every holster. Cold and
  hot are INDEPENDENT color cvars; a hot/cold toggle respawns the marker (color
  is a class, not a field) and `updateProps` carries fade state across that
  respawn so it reads as instant.
- `RS_HolsterProp` -- the stored weapon's model, invisible when empty.

Both are parked at the anchor and repositioned every tic from
`RS_HolsterManager.updateProps` (not parented -- the anchor moves with the
player's head every frame, and there is nothing to parent to). Both fade
in/out rather than hard-cutting `bINVISIBLE`.

`RS_HolsterFlashlight` (`zscript/weapons/`) is an ordinary `Weapon`, built as a
utility test fixture -- it needs no support from the holster system at all,
which is the point: it proves any plain `Weapon` fits. Model/skin/sprite/sounds
are COPIED from GlowInTheDark's `GITD_Flashlight`, not referenced, so this pk3
does not depend on that mod. Its beam-aim ports GITD's `ResolveMount` including
the correction documented there against real engine source: `AttackAngle`/
`OffhandAngle` are stored as world yaw MINUS 90, and `AttackPitch`/
`OffhandPitch` are stored NEGATED.

**That last fact is an open lead, not just trivia.** `handBasisPose` reads
`OffhandPitch` raw, with no negation -- now RS_HardPoints' problem rather than
this repo's, but the same code lineage. See that repo's notes.

The system does not exist without engine support. `HolsterClaimMain/Off` are
engine-owned fields the native grip arbiter (`vk_openxrdevice.cpp`) reads every
frame to decide whether a hand's grip button means "holster" this frame -- this
mod SETS those fields (`updateClaims`), the ENGINE reads them to redirect grip
input. If that field ever stops existing or stops being read, grip silently
reverts to its non-holster meaning everywhere, with no error.

**No RS_Main dependency.** This was claimed in three places (README, MENUDEF,
zscript.txt) and was never true in code -- verified by grep, then confirmed
against `RS_Lance`'s `LNC_Lance`, a plain `Weapon` in an unrelated pk3, which
holsters identically. Every weapon lookup goes through `GetClassName()` /
inventory search / the engine's own base `Weapon`. It needs SOME weapon pack
loaded to have a model to show, and does not care which. The two confirm sounds
(`rs_fx_holster`, `rs_allclear_ready`) are looked up by name and resolve to
silence if undefined -- not a hard dependency either.

## The engine dependency — read this before touching anything

RS_Holsters is built on native fields/functions added to the UZDXREMA
engine fork (`E:\UZDXREMA`). None of this exists in stock GZDoom or in a
different DoomXR build. If you're extending this mod and find yourself
wanting a new piece of engine-level data or behavior, it probably needs a
new native, not a script workaround. **Standing authorization from the
owner (2026-08-23): engine work is pre-approved whenever it makes something
easier, more extensible, more advanced, or more fun — don't hold back
proposing a native because it means touching UZDXREMA.**

**Fields on AActor** (`src/playsim/actor.h` + ZScript decl in
`wadsrc/static/zscript/actors/actor.zs` + binding in
`src/scripting/vmthunks_actors.cpp`):
- `HmdPos` (DVector3), `HmdYaw/HmdPitch/HmdRoll` (DAngle) — head pose
- `VRTurnYaw` (double) — mirrors the engine's internal snap-turn
  accumulator; this is what body yaw tracks the DELTA of, not raw HmdYaw,
  which is what fixed the snap-turn drift bug
- `HolsterClaimMain/Off` (bool) — script writes, engine's grip arbiter reads
- `GripContextMain/Off` (int) — published by the arbiter for diagnostics

**`Weapon.bHolsterHidden`** (`wadsrc/static/zscript/actors/inventory/
weapons.zs`, base `Weapon` class, NOT a holster-mod field) — the universal
weapon-cycling exclusion. `doSwap` sets it true on store, false on draw.
`Weapon.CheckAmmo` refuses a holstered weapon as a candidate at all (so
weapnext/weapprev/slot-select skip straight past it), `hw_vrwheel.cpp`'s
`IsWheelWeaponUsable` refuses to let the native VR wheel select it into a
hand, and `alt_hud.zs`'s `DrawOneWeapon` refuses to draw it in the
weapon-switch HUD strip. All three read the SAME field, so there is one
source of truth for "is this weapon stowed" across every selection path in
the engine, not three separate opinions.

**Functions on FLevelLocals** (`src/scripting/vmthunks.cpp` + ZScript decl
in `wadsrc/static/zscript/doombase.zs`):
- `VRHaptic(hand, intensity, durationMs)` — pre-existing, hand 0=main 1=off
- `GetModelOrientationHint(cls, sprite, frame)` → found, mirrored,
  angleoffset, pitchoffset, rolloffset — measures a weapon's baked MODELDEF
  rotation quirks instead of guessing them
- `GetModelOffsetHint(cls, sprite, frame, pixelstretch)` → found, x, y, z —
  the model's baked local position offset
- `GetModelWorldOffset(cls, sprite, frame, pixelstretch, angle, pitch,
  roll, scaleX, scaleY)` → found, dx, dy, dz — replays RenderModel's actual
  rotation AND scale math to give the true world-space correction. Do NOT
  hand-derive this kind of thing again; it took three wrong attempts before
  landing on "just replay the engine's own matrix" (see Lessons below).
- `JSONProfileBegin/SetDouble/GetDouble/Save(name)/Load(name)` — the only
  file I/O ZScript has. Flat key→double documents only; see the big comment
  block above these in vmthunks.cpp for the full protocol and the name
  sanitization rules.
- `GetActorModelClass(act)` → `class<Actor>` — added 2026-08-24. What class's
  MODELDEF a live actor INSTANCE actually resolves against right now
  (`modelData->modelDef` if something set a per-instance override via
  `A_ChangeModel` called on that instance, else the actor's own class).
  `RS_HolsterProp.ShowWeapon` uses this instead of `w.GetClass()` so a
  weapon another mod has model-swapped per-instance (ModelSwapper is the
  motivating case — it never gives the swapped weapon's own class a MODELDEF
  entry, only the live held instance) still shows correctly when holstered.
  **Built, engine-rebuilt, mod-side rebuilt, both committed — NOT yet
  confirmed against a real ModelSwapper weapon in headset.**

**Engine build**: `E:\UZDXREMA\build-dxr\DoomXR.slnx`, MSBuild. Two configs
exist, `RelWithDebInfo` and `Debug` — the owner's ACTUAL launch config as of
2026-08-24 is `Debug` (confirmed from a real crash log: paths were
`E:/UZDXREMA/build-dxr/Debug/doomxr.pk3` etc.), so build that one unless told
otherwise: `/p:Configuration=Debug /p:Platform=x64`. Output lands directly at
`E:\UZDXREMA\build-dxr\Debug\doomxr.exe` (or `RelWithDebInfo\` for that
config) — that IS the launch location, no separate copy step for the engine
itself.

MSBuild.exe's real path is NOT the "obvious" one — `C:\Program Files\
Microsoft Visual Studio\2022\...` does not exist on this machine. Use
`vswhere` to find it rather than guessing:
`& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
-latest -products * -requires Microsoft.Component.MSBuild -find
MSBuild\**\Bin\MSBuild.exe`. On 2026-08-24 that resolved to VS "18" (not
"2022"), at `C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\
Current\Bin\MSBuild.exe` — do not assume that path is stable either, re-run
vswhere.

**UZDXREMA is a live, multi-tenant tree.** Other lanes build and leave
uncommitted work in this same checkout at any time — as of 2026-08-24 there
was a large unrelated pile sitting there (`p_physics.cpp/h`, `models_iqm.cpp`,
`vk_openxrdevice.*`, `CMakeLists.txt`, untracked `ENGINE_DELTA.md`/
`IQM_ENGINE_NOTES.md`/`VR_INTERACTION_PLAN.md`/`tools/fbx2iqm/`, an
`hw_vrwheel.cpp` change adding a `wr_suppress_native_wheel` cvar check for
RS_WeaponWheel). None of it is this mod's — before committing here, `git
status` and stage ONLY the specific files this mod's own work touched, never
`-A`/`.`. Before building, check for a live `MSBuild.exe`/`mspdbsrv.exe`
process first (`tasklist | grep -i msbuild`) — two builds against the same
tree can produce a genuine link collision, not just wasted time; wait for it
to clear rather than raced.

## Build & deploy checklist (mod side)

- `RS_Holsters`: run `E:\RS_Holsters\build.ps1`. It always deletes the old zip
  first — `7z a` on an EXISTING archive only adds/updates, never removes
  entries whose source file is gone. `RS_Holsters.zip` at the repo root IS
  the load path; nothing else to copy. Same pattern for
  `E:\RS_HardPoints\build.ps1` → `RS_HardPoints.zip`.
- **The exclusion list must name EVERY sibling zip, not just the one being
  written.** It only ever named its own output, so the leftover
  `RS_Holsters.zip` from before the rename was being packed INSIDE every
  build — 56KB of dead weight riding along silently. Fixed on 2026-08-23,
  but the shape of the bug recurs any time a repo grows a second zip.
- `RS_Main`: no build script. Manual: delete `RS_Main.zip`, then
  `7z a -tzip -mx=1 RS_Main.zip . -r -xr!.git -x!.gitattributes
  -x!.gitignore -x!RS_Main.zip -xr!.claude`. Deploy by copying to
  `D:\SteamLibrary\steamapps\common\DooM VR\__CurrentRotationDONOTDELETE\RS_MAIN.pk3`.
- **After EVERY pk3 rebuild, before trusting it**: `7z l <pk3> | grep -i
  <lumpname>` for MODELDEF, KEYCONF, CVARINFO, SNDINFO — must show EXACTLY
  ONE entry each. GZDoom builds a lump's short name by stripping the
  extension, so a stray `.bak`/`.bak2`/`.old` file anywhere in the tree
  registers under the SAME short name as the real lump and can silently
  win the lookup. This actually happened once this session and cost a full
  debugging cycle — a backup file created BY a fix script shadowed the fix
  it was supposed to ship.

## Hard-won lessons (read before you hit these again)

**MODELDEF**: `USEACTORPITCH`/`USEACTORROLL`/`Rotating` and friends MUST
appear BEFORE the `FrameIndex` lines in a `Model` block. Each `FrameIndex`
immediately pushes a snapshot of the flags-so-far into the render table
(`r_data/models.cpp:1204`) — flags written after the last `FrameIndex`
parse cleanly and apply to nothing.

**RenderModel's offset math**: the model's baked Offset gets multiplied by
the ACTOR's own Scale (not just the MODELDEF's own xscale, which cancels
out) — because the offset `translate()` happens after the `scale()` call in
source order, and later calls apply to raw vertices FIRST. Also: the
`stretch`/pixelstretch variable used in that same translate is 1.0 unless
`MDL_CORRECTPIXELSTRETCH` is explicitly set on that block (nothing in this
MODELDEF sets it) — do not divide by pixelstretch there.

**`+FORCEXYBILLBOARD`** only affects the sprite rendering pipeline
(`hw_sprites.cpp`). `RenderModel` never looks at it. Once `A_ChangeModel`
binds a real model, that flag is inert — full angle/pitch/roll control is
available, unconstrained by billboarding.

**`FindModelFrameRaw` matches by EXACT class pointer** — a subclass does
NOT inherit its parent's MODELDEF binding. This is why the marker color
subclasses work at all: `SetHot()`'s `A_ChangeModel` call hardcodes the
PARENT class's literal name as the `modeldef` argument, regardless of which
subclass the actual instance is, redirecting model lookup to the one block
that exists no matter which color got spawned.

**ZScript language limits found by hitting them** (none of these have any
precedent anywhere in this codebase, so don't reintroduce them without
verifying first — there is no way to test-compile from here):
- `const` is a CLASS-level declaration only. A `const X = ...;` inside a
  method body is not something this codebase does anywhere, and it may not
  even parse.
- No confirmed `Min()`/`Clamp()` builtin (`Max()` is real and used in
  stock wadsrc). Write comparisons by hand.
- No confirmed `double(x)`-style cast-as-function-call. To force int→double
  promotion, multiply by a double literal (`x * 1.0`) instead — that's
  ordinary operator promotion, not a cast, and every C-family language
  agrees on it.
- No field initializers (`private int x = 5;`). Rely on the zero-default
  and set explicitly before first use.
- `Actor.Spawn` takes `class<Actor>`, not a string/name — a literal string
  auto-resolves at compile time in that context, but a runtime `string`
  variable will not. Where a runtime-selected class was needed (marker
  color), the pattern is a function returning `class<Actor>` with each
  `case` returning its own literal — resolved per-literal at compile time,
  no runtime cast involved.

**Store/draw**: `player.PendingWeapon` is ONE field shared by both hands —
anything that lets one hand's switch overwrite it while the other hand's is
still resolving will misdeliver a weapon. Every weapon here carries
`+WEAPON.NOHANDSWITCH`, so `MoveWeaponToHand` SILENTLY no-ops on a hand
mismatch (check `weap.bOffhandWeapon` yourself before calling it, don't
trust it to fail loudly). The engine's own `CheckWeaponSwitch` can re-arm a
holstered weapon on any ammo pickup, since holstering never removes it from
inventory — `bNoAutoSwitchTo` is what stops that.

## Where to extend things

- **A 9th/10th holster**: bump `HOLSTER_COUNT` **and** `HAND_HOLSTER_START`
  together -- `isHandAnchored()` must stay false for every valid index, or the
  dead arm-rig branches described above come back to life on the new one. Add a
  `GetHolster` case (the last case is `default:`, so a new one goes above it),
  extend `activeCount()`'s snap-to-tier logic, extend the
  `RS_HolsterActiveCount` `OptionValue` block in MENUDEF.
- **Anything on the arm or wrist**: wrong repo -- that is `E:\RS_HardPoints`.
- **A new marker shape**: author a new unit-radius `.obj` (corner/feature
  distance from origin = 1.0, so MODELDEF's existing `Scale 3.0 3.0 3.0`
  keeps mapping correctly) -- see
  `E:\Tools\...\Generate-BracketReticle.ps1`-style generator scripts rather
  than hand-typing vertex/face lines. Add a shape enum value, extend
  `SetHot()`'s `modelWanted` selection. **Check the filename twice**: `SetHot`
  passes it to `A_ChangeModel` as a bare string, MODELDEF names it separately,
  and a mismatch fails SILENTLY -- the default bracket shape shipped broken
  exactly this way after the rename, asking for `rs_hardpoint_bracket.obj`
  while the file on disk was still `rs_holster_bracket.obj`.
- **A new marker color**: add a subclass with its own `Translation "0:255=
  %[...]:[...]"` (desaturate-then-tint syntax, see RS_Main's
  `RS_Archvile.zs` for more examples), extend `holsterMarkerColorClass()`'s
  switch -- it takes a `bool hot` and picks between the cold and hot cvars, so
  a new color appears in both automatically. Also extend the
  `RS_HolsterMarkerColor` `OptionValue` block, which both menu entries share.
- **Per-holster sound identity**: `doSwap`'s sound choice is currently one
  global pick (`rs_holster_sound_style`). Per-holster identity would mean
  threading a sound name through `GetHolster`'s table instead.
- **A third mod in this family**: listen for `rs-vrhp-grab-main`/`-off`
  alongside your own netevents, bind your own alias name, and ship no default
  F13/F14 bind. See Split history above for why.

## Miscellany

`holsterideas.txt` at the repo root is the owner's own personal notes file
(untracked, deliberately never added to git) — a running brainstorm of
holster-mode ideas. If a fresh session is asked to brainstorm more, that
file is where prior ideas (and whatever the owner jotted down separately)
actually live; check it before assuming a clean slate.

## Open / not done

- Seated and standing profiles exist as a system (save/load/switch, all
  working) but have not actually been tuned and saved yet -- tabled by the
  owner, not blocked on anything. The files are now named `holster_seated` /
  `holster_standing`, so any profile saved before 2026-08-23 is orphaned.
- Centering is "close enough" per the owner but was never chased to a literal
  0.00 drift for every weapon in the arsenal, only spot-checked on a couple.
- **"Guns store backwards."** Reported in headset, never resolved -- the plan
  was for the owner to live-tune `rs_holster_prop_yaw` / `_pitch` and report
  the working numbers back to bake in as new defaults. Still open.
- The dead arm-rig code described in Architecture could be removed properly.
  Its own commit, nothing else in it, and expect a load-error round trip.
- `RS_HolsterFlashlight` is granted automatically on spawn
  (`RS_HolsterStartLoadout`, a `StaticEventHandler` registered in
  MAPINFO's `AddEventHandlers`) -- not a map placement or a startitem on
  any player class. It is slot 7. A second test weapon,
  `RS_HolsterFlamethrower` (cloned from RS_Main's `RS_GH_Flamethrower`),
  was built and then removed at the owner's request (2026-08-23) -- if
  something references it, that's stale, not a sign it should exist.
- **First real launch after the split (2026-08-24) crashed, but not on
  anything here.** `Could not submit command buffer: device lost` — a
  Vulkan/GPU-driver failure at the main menu, before a level loaded or a
  player pawn existed, i.e. before a single tic of this mod's code could
  have run. Also running the `Debug` engine config, which is slower/less
  stable than `RelWithDebInfo`. Not a ZScript compile failure and not
  evidence this mod's changes are bad — but also means the split STILL has
  not been confirmed working end-to-end in headset. That confirmation is
  still the real open item, now stacked with confirming the
  `GetActorModelClass`/ModelSwapper fix at the same time.
- **The wrist-pitch hypothesis is still just a hypothesis.** See
  `E:\RS_HardPoints\CLAUDE.md` for the actual claim and the debug dump built
  to test it (`rs_hardpoint_arm_active_count` = 2 or 3, tilt the wrist, read
  the console). Nothing in either repo has been changed based on it yet.
- **The `GetActorModelClass` engine commit is local-only, not pushed** to
  UZDXREMA's remote — deliberately, since that tree has other lanes' work
  sitting in it and pushing shared infra wasn't asked for. The mod-side
  commit using it (this repo) IS pushed as part of a separate v0.3.0-era
  release; re-check `git log`/`git status` before assuming either state,
  since both may have moved by the time you read this.
