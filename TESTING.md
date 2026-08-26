# Test list

Everything below is on branch `claude/arbiter-and-fixes` in each repo. `main` is
untouched everywhere — `git checkout main` reverts any of it.

Nothing here has been compile-checked. There is no ZScript compiler available
outside the engine, so **the first load IS the first test.** If the game refuses
to start, the fault is in one of these commits and the list below is the bisect
order.

## 0. Does it load at all

```
E:\UZDXREMA\build-dxr\Debug\doomxr.exe -iwad E:\UZDXREMA\build-dxr\Debug\doom2.wad -file <pk3s>
```

A ZScript error is fatal AND global — it stops every pk3 later in the load order
compiling, so a failure here says nothing about *which* pk3 is at fault until you
load them one at a time.

**Load order for bisecting, riskiest last:** RS_Hands → RS_Holsters →
RS_HardPoints → RS_Reload.

---

## 1. RS_Reload — the one real behaviour change ⚠

**`RR_Point.Pit()` now negates.** It returned raw `AttackPitch` while
`RS_Reach.HandPitch` (RS_Hands) negates — and both feed the same `RS_Basis`.

| | |
|---|---|
| **Test** | Reload with the gun held **level**, then **steeply up**, then **steeply down**. |
| **Expected** | The magwell target point tracks the gun in all three. |
| **Before this fix** | Level was correct; pitched up/down was **mirrored** — which is why it survived. |
| **Watch for** | The reload dot landing above the gun when you aim down, or below when you aim up. That means the sign is now wrong in the other direction — tell me and I'll revert this one commit. |
| **Then** | The per-archetype `rr_len_*` / `rr_grip_*` tuning may need a pass, since it was tuned against the broken basis. |

This is the single most likely thing on the list to feel different.

## 2. RS_Reload — the draw sound comes back

`rr/magdraw` was swallowed by a prose comment block and never registered. It's
`SndDraw()`'s **default** return.

- **Test:** reload a **pistol, rifle, chaingun and rocket launcher** (feeds BOX,
  BOLT, BELT, POD).
- **Expected:** a draw sound when the magazine appears in your off hand. Those
  four were **silent** before.
- Shotgun and plasma (SHELL/CELL) had their own sounds and should be unchanged.

---

## 3. RS_Holsters — your binds will be reset ⚠

The key section was renamed from `RS HardPoints` / `RSHardPoints` to
`RS Holsters` / `RSHolsters`, because both mods declared the *same* section and
shared one bind file.

- **You must re-bind the holster keys once** under Customize Controls.
- **Expected afterwards:** holster binds and hardpoint binds now **survive a
  restart independently.** Previously whichever mod loaded first had its binds
  overwritten on every config save.
- **Test:** bind both, quit, relaunch, confirm both survived. That has not been
  true since 2026-08-23.

## 4. RS_Holsters + RS_HardPoints — packaging

- **Test:** rebuild both (`.\build.ps1`) and open the zips.
- **Expected:** `RS_Holsters.zip` = 53 entries (was 57), `RS_HardPoints.zip` = 21
  (was 22). No `README.md`, no `.claude/`, no `holsterideas.txt`.
- *Already verified by rebuild — listed so you can confirm independently.*

---

## 5. RS_HardPoints — ModelSwapper weapons on arm mounts

Five call sites now use `level.GetActorModelClass(w)` instead of `w.GetClass()`,
matching RS_Holsters.

- **Test:** load **ModelSwapper**, swap a weapon's model, then store that weapon
  on an **arm hardpoint**.
- **Expected:** the mount shows the **swapped** model — the same one a torso
  holster already showed correctly.
- **Before:** torso holster right, arm mount wrong or blank.
- **Also test a non-swapped weapon** on a mount to confirm the common path is
  unchanged. This is a strict superset of the old behaviour, so nothing should
  regress.

## 6. RS_HardPoints — console spam is gone

- **Expected:** using the wrist tier no longer prints ~7 lines a second.
- **Test the diagnostic still works:** Options → RS HardPoints → Diagnostics →
  **Wrist pitch live dump** = On. Tilt the wrist. Numbers should appear.
- That dump is how the **open wrist-pitch question** gets settled — see §9.

---

## 7. RS_Hands — three fixes

**`rs_hands_blend = 0`**
- Set it to 0. Poses should **snap** with no interpolation.
- Before, 0 caused the cvar not to be read at all, so it kept blending at the 4.0
  default. `CVARINFO.txt:43` promised snapping.

**Beams no longer wiped level-wide**
- **Test:** turn `rs_dgrab_beam` (or `rs_dgrab`) **off** while something else in
  the level is drawing beams.
- **Expected:** only the two hand beams vanish. Previously `SetBeamCount(0,0,0)`
  destroyed **every beam in the level**, including other mods'.

**Walk-over no longer resurrects hidden items**
- **Test:** toggle `rs_grab_nowalkover` off and on in a map with hidden or
  deliberately non-pickup items.
- **Expected:** items that were never pickups stay non-pickups. Normal pickups
  behave normally.
- Before, switching walk-over back on granted `SPECIAL` to everything qualifying,
  including things that shipped without it.

---

## 8. Regression sweep — things that should NOT have changed

Nothing below was touched. If any of it behaves differently, something in the
list above had a side effect I didn't predict.

- Holster store/draw, all 8 torso anchors
- Hardpoint store/draw, forearm and wrist tiers
- Near grab, distance grab, throw, two-hand stabilize
- The reload gesture itself — pouch entry, carry, all four exits
- Headshot detection and the laser tint *(your lane, separate branch)*

---

## 9. Open questions the headset has to answer

Not bugs to verify — genuine unknowns nobody can settle from source.

**The wrist-pitch hypothesis.** `handBasisPose` reads `OffhandPitch` **raw**
while every other consumer in the family negates it. That would invert the
vertical response of wrist anchors 3–5. **Deliberately not fixed blind** — this
file's rotation math has been hand-derived wrongly twice, and the three wrist
slots have different offsets so one prediction may not hold for all three. Turn
on the dump from §6, tilt the wrist, read the numbers.

**The reach volume.** `RS_Reach.Score` treats the scale cvars as **map units**;
`CVARINFO.txt:129` and the `0.005–4.0` menu slider say **viewmodel space**. They
can't both be right, and the mod's load-bearing claim is "the drawn volume is the
tested volume." Also the `_ofs_x/y/z` axes are **permuted** between the tested
centre and the drawn oval, so the slider labelled "Forward / back" moves them in
different directions. **Not fixed** — which of the two spaces is correct is a
headset question.

---

## Still to come

The **grip arbiter** and its conversions are not in this list yet. When they
land, the headline test is the live bug they exist to fix:

> Load RS_Hands and RS_Holsters together. Pick a **health pack** up off the
> floor, nowhere near your chest, with the ammo pouch **disabled**. Your weapon
> currently turns into a fist. It should not.
