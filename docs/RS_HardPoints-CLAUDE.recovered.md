# RS HardPoints — project context

Claude Code auto-loads this file for any session opened in this repo. If
you're a fresh agent reading this cold: this is the handoff doc, written so
you don't have to rediscover any of it. Not a user-facing doc — see README.md
for that.

Six mount points on the player's own off arm: three along the forearm, three
around the wrist. Reach over with the other hand, grip, and what's mounted
there is in your hand. Utility slots — grenades, a flashlight, a tool.

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
- **Be careful consulting existing documentation — verify against actual
  code, and ask rather than guess when unsure.** Comments and docs in this
  codebase have repeatedly been stale or simply wrong: a three-file "requires
  RS_Main" claim that was never true in code, a renamed asset reference that
  silently pointed at a file that didn't exist. Docs describe intent and
  history; code is ground truth. Cross-check before repeating a doc's claim
  as fact, and surface genuine uncertainty to the owner instead of resolving
  it with a guess.

**Split history.** This repo was split out of `E:\RS_Holsters` on 2026-08-23.
That mod began as `RS_Holsters`, was renamed wholesale to `RS_HardPoints` when
the forearm/wrist feature landed, then split: the arm rig (old indices 8-13)
became THIS repo and kept the `RS_HardPoint*` / `rs_hardpoint_*` naming, while
the 8 torso holsters stayed there and reverted to `RS_Holster*`.

The two are designed to be **loaded at the same time**, so everything that could
collide is separated: class names, cvars, netevents, MENUDEF option ids, KEYCONF
section, MODELDEF class blocks, sprite name (`RSHP` here, `RSHM` there), model
and skin filenames (`rs_hp_*` here), and the saved profile file
(`hardpoint_layout` here, `holster_*` there -- they previously both wrote plain
`seated`/`standing` and would have overwritten each other's tuning with a table
of a different length).

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
`dumpOneHolsterProp()` -- plus prose comments using "holster" as an English
word. They are private, never referenced across pk3 boundaries, and sweeping
them buys nothing but risk. A "holster" in this file's identifiers means "one
of the six arm mounts." `HolsterClaimMain/Off` and `GripContextMain/Off` are
engine-native (`E:\UZDXREMA`) and this mod only reads/writes them.

**No flashlight lives here.** `RS_HolsterFlashlight` (the test weapon built to
prove any plain `Weapon` fits the store/draw pipeline) stayed in `E:\RS_Holsters`
after the split -- see that repo's notes. The real, full-featured flashlight
lives in a third repo, GlowInTheDark (`GITD_Flashlight`), and is not part of
either Holsters repo. RS_HolsterFlashlight is a throwaway test fixture, not a
feature meant to ship long-term; safe to delete once it's done its job, since
it is self-contained (own file, own copied assets, touches no shared code).

## Architecture, in one picture

`RS_HardPointManager` (EventHandler, `RS_HardPoints.zs`) is the only stateful
owner. It runs the whole loop every tic: calibrate -> body yaw -> grabs ->
claims -> props. `GetHolster(idx, ...)` is the compile-time table of all 6
anchor definitions -- a switch, not an array of structs, because ZScript dynamic
arrays only accept integral/object types. Everything else (`edFwd`/`edSide`/
`edFrac`/`edPitch`/`edYaw`/`edRoll`) is the LIVE, tunable copy of that table,
seeded from it once and then overwritten by Edit Mode dragging or a loaded JSON
profile.

Indices 0-2 are `Forearm1/2/3`, 3-5 are `WristBelow/Knuckle/Joint`. **Both
origin and basis are always the OFF hand's own live pose** (`OffhandPos/Angle/
Pitch/Roll`), unconditionally, via `handBasisPose`. It does not matter which
hand is holding a weapon or whether either hand is holding one at all -- this is
the off-arm's own hardpoint rig, not something that tracks a weapon.

**"Off hand" is already handedness-agnostic, and that matters for the
planned dual-arm work below.** `OffhandPos`/`Angle`/`Pitch`/`Roll` are the
engine's LOGICAL non-dominant hand, whichever physical hand the player's own
handedness setting makes that -- this mod never assumes "off hand" means
"left hand." A player who plays left-handed already gets this rig on their
right arm for free, no code change needed. What's NOT yet built is a rig on
BOTH arms at once; see Open/not done.

`hsFwd`/`hsSide`/`hsFrac` are raw map-unit (inch) offsets along the OFF HAND's
own forward/right/up axes, and `hsPitch`/`hsYaw`/`hsRoll` are **TRIMS on top of
that basis, not absolute angles**. The inherited table defaulted them to 90/0/0
(meaning "barrel down" in the torso holsters' absolute-angle world); that is now
0/0/0, because a nonzero default here silently cants every mount off the arm.

**`isHandAnchored()` is always true here** (`HAND_HOLSTER_START` is 0). It is
kept as a predicate rather than torn out because it is what anchor placement,
orientation, edit-mode dragging and claim arbitration all branch on -- one
constant is a far smaller risk surface than edits scattered through all of that,
in a codebase with no way to test-compile. The torso branches it guards are
unreachable, deliberately. `worldToBody` and the `bodyYaw`/eye-height machinery
are dead for the same reason. **Dead code still has to compile** -- do not
delete a constant while leaving its consumer standing; that only surfaces as a
load failure in the headset.

**REJECTED APPROACH**, kept so it does not get re-tried: a mid-session version
had Forearm1-3 track the MAIN hand's aim (`AttackAngle/Pitch/Roll`), on the
theory that the off hand's own orientation would be unreliably canted by
gripping a foregrip. In headset this changed nothing visible and the owner
rejected the premise outright -- "it doesn't matter what hand i have a gun in,
just put three hardpoints on the offhand behind the controller position." If
forearm placement still looks wrong after a full game restart (not just a
rebuilt zip -- a real code change once appeared to do nothing, and it was a
stale loaded pk3), look for a sign/axis bug in `handAnchorPos`'s forward vector
before reaching for a different-hand theory again.

**The off hand can never claim its own gear**, and that is not tuning: an anchor
here is a fixed offset from that same hand's own live pose, so the distance from
the off hand to it is constant every tic no matter how the player moves. It
would be a permanent self-claim or permanent dead code, never a proximity test.
The MAIN hand reaches over and uses the rig; see the guard in `updateClaims`.
A consequence worth knowing: the off hand can therefore never store or draw
anything in this mod at all.

**No seated/standing profiles**, unlike RS_Holsters. Posture is a variable for
anchors placed relative to a body; these are bolted to a tracked controller, so
two slots would be two names for the same numbers. One `hardpoint_layout`.

**`rs_hardpoint_arm_active_count` is a MODE, not a count** (0 off, 1 forearm
only, 2 wrist only, 3 both) -- `armMode()`/`holsterActive()`. Wrist-only has
to be a mode: the wrist trio (3-5) is never the low end of the anchor table,
so a simple "first N active" count could never express it alone. Defaults to
1 (forearm only), not 0. OFF was right when this rig sat beside 8 already-tuned
torso holsters and switching on unproven anchor math should not have been a
side effect of installing something else. Standalone it is the whole mod, and 0
would mean loading the pk3 and seeing
nothing at all.

Two visible actor classes, both in `RS_HardPointProp.zs`:
- `RS_HardPointMarker` (+ `_Blue`/`_Red`/`_Gold`/`_Purple`/`_Orange`/`_Green`/
  `_Cyan`/`_Pink`) -- the always-present ring at every hardpoint. Cold and hot
  are INDEPENDENT color cvars; a hot/cold toggle respawns the marker (color is a
  class, not a field) and `updateProps` carries fade state across that respawn
  so it reads as instant rather than re-fading in on every hand enter/leave.
- `RS_HardPointProp` -- the stored item's model, invisible when empty.

Both are parked at the anchor and repositioned every tic from
`RS_HardPointManager.updateProps` (not parented -- the anchor moves with the
hand every frame, and there is nothing to parent to). Both fade in/out rather
than hard-cutting `bINVISIBLE`.

The system does not exist without engine support. `HolsterClaimMain/Off` are
engine-owned fields the native grip arbiter (`vk_openxrdevice.cpp`) reads every
frame to decide whether a hand's grip button means "holster" this frame -- this
mod SETS those fields (`updateClaims`), the ENGINE reads them to redirect grip
input. If that field ever stops existing or stops being read, grip silently
reverts to its non-holster meaning everywhere, with no error.

**No RS_Main dependency, and no dependency on any specific weapon pack.** Every
weapon lookup goes through `GetClassName()` / inventory search / the engine's
own base `Weapon`. It needs SOME pack loaded to have a model to show and does
not care which -- confirmed against `RS_Lance`'s `LNC_Lance`, a plain `Weapon`
in an unrelated pk3. The two confirm sounds (`rs_fx_holster`,
`rs_allclear_ready`) are looked up by name and resolve to silence if undefined,
so they are not hard dependencies either.

## The engine dependency — read this before touching anything

RS_HardPoints is built on native fields/functions added to the UZDXREMA
engine fork (`E:\UZDXREMA`). None of this exists in stock GZDoom or in a
different DoomXR build. If you're extending this mod and find yourself
wanting a new piece of engine-level data or behavior, it probably needs a
new native, not a script workaround. **Standing authorization from the
owner (2026-08-23): engine work is pre-approved whenever it makes something
easier, more extensible, more advanced, or more fun -- don't hold back
proposing a native because it means touching UZDXREMA.**

**Fields on AActor** (`src/playsim/actor.h` + ZScript decl in
`wadsrc/static/zscript/actors/actor.zs` + binding in
`src/scripting/vmthunks_actors.cpp`):
- `HmdPos` (DVector3), `HmdYaw/HmdPitch/HmdRoll` (DAngle) -- head pose
- `OffhandPos/Angle/Pitch/Roll` and the matching `Attack*` pair -- the two
  hands' own live tracked poses, whichever hand is logically "off" per the
  player's handedness setting, not fixed to physical left or right
- `VRTurnYaw` (double) -- mirrors the engine's internal snap-turn accumulator
- `HolsterClaimMain/Off` (bool) -- script writes, engine's grip arbiter reads
- `GripContextMain/Off` (int) -- published by the arbiter for diagnostics

**Functions on FLevelLocals** (`src/scripting/vmthunks.cpp` + ZScript decl
in `wadsrc/static/zscript/doombase.zs`):
- `VRHaptic(hand, intensity, durationMs)` -- pre-existing, hand 0=main 1=off
- `GetModelOrientationHint(cls, sprite, frame)` -> found, mirrored,
  angleoffset, pitchoffset, rolloffset -- measures a weapon's baked MODELDEF
  rotation quirks instead of guessing them
- `GetModelOffsetHint(cls, sprite, frame, pixelstretch)` -> found, x, y, z --
  the model's baked local position offset
- `GetModelWorldOffset(cls, sprite, frame, pixelstretch, angle, pitch,
  roll, scaleX, scaleY)` -> found, dx, dy, dz -- replays RenderModel's actual
  rotation AND scale math to give the true world-space correction. Do NOT
  hand-derive this kind of thing again; it took three wrong attempts before
  landing on "just replay the engine's own matrix" (see Lessons below).
- `JSONProfileBegin/SetDouble/GetDouble/Save(name)/Load(name)` -- the only
  file I/O ZScript has. Flat key->double documents only; see the big comment
  block above these in vmthunks.cpp for the full protocol and the name
  sanitization rules.

**Engine build**: `E:\UZDXREMA\build-dxr\DoomXR.slnx`, MSBuild,
`Configuration=RelWithDebInfo /Platform=x64`. Output lands directly at
`E:\UZDXREMA\build-dxr\RelWithDebInfo\doomxr.exe` + `doomxr.pk3` -- that IS
the launch location, no separate copy step for the engine itself.

## Build & deploy checklist (mod side)

- `RS_HardPoints`: run `E:\RS_HardPoints\build.ps1`. It always deletes the old
  zip first -- `7z a` on an EXISTING archive only adds/updates, never removes
  entries whose source file is gone. `RS_HardPoints.zip` at the repo root IS
  the load path; nothing else to copy. Same pattern for
  `E:\RS_Holsters\build.ps1` -> `RS_Holsters.zip`.
- **The exclusion list must name EVERY sibling zip, not just the one being
  written**, or a stale zip from a sibling repo gets packed INSIDE the build
  as dead weight -- this happened once in RS_Holsters (2026-08-23) and cost a
  rebuild to catch.
- **After EVERY pk3 rebuild, before trusting it**: check MODELDEF, KEYCONF,
  CVARINFO, SNDINFO, MAPINFO, TEXTURES, ZSCRIPT -- must show EXACTLY ONE entry
  each in the zip. GZDoom builds a lump's short name by stripping the
  extension, so a stray `.bak`/`.bak2`/`.old` file anywhere in the tree
  registers under the SAME short name as the real lump and can silently win
  the lookup. This actually happened once in this mod's history and cost a
  full debugging cycle -- a backup file created BY a fix script shadowed the
  fix it was supposed to ship.

## Hard-won lessons (read before you hit these again)

**MODELDEF**: `USEACTORPITCH`/`USEACTORROLL`/`Rotating` and friends MUST
appear BEFORE the `FrameIndex` lines in a `Model` block. Each `FrameIndex`
immediately pushes a snapshot of the flags-so-far into the render table
(`r_data/models.cpp:1204`) -- flags written after the last `FrameIndex`
parse cleanly and apply to nothing.

**RenderModel's offset math**: the model's baked Offset gets multiplied by
the ACTOR's own Scale (not just the MODELDEF's own xscale, which cancels
out) -- because the offset `translate()` happens after the `scale()` call in
source order, and later calls apply to raw vertices FIRST. Also: the
`stretch`/pixelstretch variable used in that same translate is 1.0 unless
`MDL_CORRECTPIXELSTRETCH` is explicitly set on that block -- do not divide
by pixelstretch there.

**`+FORCEXYBILLBOARD`** only affects the sprite rendering pipeline
(`hw_sprites.cpp`). `RenderModel` never looks at it. Once `A_ChangeModel`
binds a real model, that flag is inert -- full angle/pitch/roll control is
available, unconstrained by billboarding.

**`FindModelFrameRaw` matches by EXACT class pointer** -- a subclass does
NOT inherit its parent's MODELDEF binding. This is why the marker color
subclasses work at all: `SetHot()`'s `A_ChangeModel` call hardcodes the
PARENT class's literal name as the `modeldef` argument, regardless of which
subclass the actual instance is, redirecting model lookup to the one block
that exists no matter which color got spawned.

**ZScript language limits found by hitting them** (none of these have any
precedent anywhere in this codebase, so don't reintroduce them without
verifying first -- there is no way to test-compile from here):
- `const` is a CLASS-level declaration only. A `const X = ...;` inside a
  method body is not something this codebase does anywhere, and it may not
  even parse.
- No confirmed `Min()`/`Clamp()` builtin (`Max()` is real and used in
  stock wadsrc). Write comparisons by hand.
- No confirmed `double(x)`-style cast-as-function-call. To force int->double
  promotion, multiply by a double literal (`x * 1.0`) instead -- that's
  ordinary operator promotion, not a cast, and every C-family language
  agrees on it.
- No field initializers (`private int x = 5;`). Rely on the zero-default
  and set explicitly before first use.
- `Actor.Spawn` takes `class<Actor>`, not a string/name -- a literal string
  auto-resolves at compile time in that context, but a runtime `string`
  variable will not. Where a runtime-selected class was needed (marker
  color), the pattern is a function returning `class<Actor>` with each
  `case` returning its own literal -- resolved per-literal at compile time,
  no runtime cast involved.

**Store/draw**: `player.PendingWeapon` is ONE field shared by both hands --
anything that lets one hand's switch overwrite it while the other hand's is
still resolving will misdeliver a weapon. Every weapon here carries
`+WEAPON.NOHANDSWITCH`, so `MoveWeaponToHand` SILENTLY no-ops on a hand
mismatch (check `weap.bOffhandWeapon` yourself before calling it, don't
trust it to fail loudly). The engine's own `CheckWeaponSwitch` can re-arm a
holstered weapon on any ammo pickup, since holstering never removes it from
inventory -- `bNoAutoSwitchTo` is what stops that.

## Where to extend things

- **A 7th hardpoint**: bump `HOLSTER_COUNT`, add a `GetHolster` case (the last
  case is `default:`, so a new one goes above it). If it belongs to neither
  existing group, `holsterActive()`/`armMode()` need a real fourth group, not
  just an index bump -- they currently only know forearm (below
  `FOREARM_HOLSTER_END`) and wrist (at or above it). Also extend the
  `RS_HardPointArmActiveCount` `OptionValue` block.
- **Anything on the torso**: wrong repo -- that is `E:\RS_Holsters`.
- **A new marker shape**: author a new unit-radius `.obj` (feature distance from
  origin = 1.0, so MODELDEF's `Scale 3.0 3.0 3.0` keeps mapping correctly), add
  a shape enum value, extend `SetHot()`'s `modelWanted` selection. **Check the
  filename twice**: `SetHot` passes it to `A_ChangeModel` as a bare string,
  MODELDEF names it separately, and a mismatch fails SILENTLY -- the default
  bracket shape shipped broken exactly this way after an earlier rename.
- **A new marker color**: add a subclass with its own `Translation "0:255=
  %[...]:[...]"` (desaturate-then-tint syntax), extend
  `holsterMarkerColorClass()`'s switch -- it takes a `bool hot` and picks between
  the cold and hot cvars, so a new color appears in both automatically. Also
  extend the `RS_HardPointMarkerColor` `OptionValue` block, shared by both menu
  entries.
- **A third mod in this family**: listen for `rs-vrhp-grab-main`/`-off`
  alongside your own netevents, bind your own alias, ship no default F13/F14
  bind. See Split history above.

## Open / not done

- **DUAL-ARM SUPPORT -- requested 2026-08-23, not yet built.** Owner wants a
  rig on BOTH arms at once, not just whichever is logically "off." Quoted
  request: "assume i want left hand support for people who want to use this
  with their right arm, too." Read alongside the Architecture note above: this
  mod is already handedness-AGNOSTIC (it follows the engine's logical off
  hand, not a hardcoded physical side), so a left-handed player already gets
  the existing rig on their right arm for free. What's missing is a SECOND,
  independent rig on the main-hand arm, running at the same time as this one --
  the mirror extension already scoped in this file's predecessor's notes: a
  parallel `handAnchorPos`/`worldToHand` pair reading `Attack*` instead of
  `Offhand*`, its own index range (12 total mounts, not 6), its own
  active-count tier, and `updateClaims`' off-hand self-claim exclusion mirrored
  for the main hand (a main-hand rig must not let the main hand claim its own
  gear, same reasoning). Likely shape: don't parameterize the existing
  functions with a hand argument threaded through everything -- clone the
  6-index block into a second bank of 6, since the existing pattern (one
  bank, hardcoded off-hand) is already proven and a hand-parameterized version
  would touch far more call sites for equivalent risk. Owner has also given
  standing authorization for engine work on this if it turns out easier as a
  native than as doubled script logic (see engine dependency section above).

- **GESTURE-CAST -- the wrist rig's actual point, and the next real feature.**
  Fire-button layout confirmed by the owner 2026-08-23, mapped to physical
  position around the off-hand controller once the arming pose is held:
  - **HP1 (left of controller) -> Grip**
  - **HP2 (below controller) -> Pad / A / X**
  - **HP3 (right of controller) -> Fire / Trigger**

  Owner's framing for what this is worth building toward: *"four weapons in
  one hand -- one held in the hand itself and three mounted around it, fired
  with fire / altfire / grip while the controller is held a certain way."*

  - **Arming pose**: arm outstretched, palm rotating up "like Dr. Strange."
    Owner's reference is a hand holding a pistol with the pistol at the top of
    the hand. As of 2026-08-23 the owner had not yet specified the actual
    detection thresholds (how far rolled counts as "armed") -- ask rather than
    guess a number when this gets built.
  - **Fires IN PLACE.** No draw into the hand. Closer to RS_Main's
    `RS_GrenadeThrower` (hold-to-charge, button-driven, never puts its weapon
    in-hand) than to a holster store/draw.
  - **Not-yet-armed visual**: small solid squares that expand once the hand
    rolls into the correct orientation -- key the marker's existing
    proximity-pulse off orientation-correctness instead of hand-distance.
  - **Firing lines**: fire each mount along its OWN already-computed forward
    vector (`handAnchorPos`'s basis, free reuse) rather than converging on the
    held weapon's aim line, with a per-slot toggle for convergence. A grenade or
    a flashlight has no business snapping onto a pistol's hitscan line; a
    secondary hitscan weapon plausibly does want to converge at range.
  - **Expect an empirical correction.** The arming pose (palm up) is not a
    natural AIMING pose, so raw "forward" from the wrist basis probably is not
    where the shot should go. Same shape of problem `FOREARM_YAW_CORRECTION`
    already solved once -- find the number in headset, do not derive it on
    paper.
  - **Blocker**: there are no real ability implementations to dispatch to yet.
    The manager-side half (pose detection, armed/unarmed visual, the three
    button bindings above dispatching to a stub netevent) can be built before
    they exist.
  - **Interacts with dual-arm support above**: if that ships first, decide
    whether gesture-cast applies to one arm's rig or both -- don't assume,
    ask.

- **THE WRIST-PITCH LEAD.** GlowInTheDark's `GITD_Flashlight` documents, against
  real engine source (`g_game.cpp:1237`, `hw_vrmodes.cpp:1170/1192`), that
  `OffhandPitch`/`AttackPitch` are stored **NEGATED** and `OffhandAngle`/
  `AttackAngle` as world yaw **minus 90** -- every other consumer corrects on
  read, and their flashlight not doing so is a bug they spent a page describing.
  `handBasisPose` here reads `OffhandPitch` **raw**. Through `handAnchorPos`'
  `fz = -sin(pit)` that would invert the vertical response of the wrist anchors
  (3-5; Forearm 0-2 force pitch to 0, so they never see it). A throttled console
  dump is already wired in `WorldTick`, gated on `armMode()` being 2 (wrist
  only) or 3 (all six): raw pitch/roll/angle plus all three wrist anchor
  positions. **Deliberately not
  "fixed" blind** -- this file's rotation math has been hand-derived wrongly
  twice before, and the three wrist slots have different offsets so one
  prediction does not obviously hold for all three. Read the numbers against an
  actual physical tilt. This matters more for gesture-cast than for placement:
  a wrong pitch sign would put the fire vector somewhere the player is not
  pointing.

- **Roll is not in the anchor basis.** Built from the off hand's yaw+pitch only.
  A stored item's own orientation tracks live roll correctly; the anchor
  POSITION does not swing around the arm when the off hand rolls. Fix, if it
  reads wrong: rotate `handAnchorPos`/`worldToHand`'s right/up vectors around
  forward by the roll `handBasisPose` already returns (Rodrigues rotation).
  Note this one is squarely in gesture-cast's path -- the arming pose IS a roll.

- **Real IK / elbow tracking**, planned once the pending UZDXREMA engine update
  lands. Every position here is a fixed offset from the off hand's own pose --
  there is no elbow sensor, so "where the forearm actually is" is approximated,
  and the empirical corrections above (the 90-degree forearm yaw offset, the
  forearm pitch lockout) are exactly what real IK would remove the need for.
  Almost certainly a new engine native, not a script trick.

- **Paged/scrollable forearm inventory** -- treat a Forearm slot as a row you
  cycle through rather than one fixed item, with a "card" visual that fades out
  as it activates. A data/UI layer on top of the 3 physical anchors, not a
  replacement: the anchor a hand reaches toward does not care whether it holds
  one fixed item or the top of a paged stack.

- Positions are placeholders meant to be dragged in edit mode, not measured.

- **Nothing has been loaded in the engine since the 2026-08-23 split.** Both
  pk3s build clean and every symbol was verified to both define and resolve, but
  that is not the same as a successful ZScript compile. First headset run after
  the split is the real test.
