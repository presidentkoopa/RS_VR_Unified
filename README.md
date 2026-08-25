# RS_VR_Unified

Merge audit of five UZDXREMA VR Doom mods — **RS_Hands**, **RS_Holsters**, **RS_HardPoints**, **RS_Reload**, **Headshots** — and the merged package built from them.

`43 agents · 190 findings · 26 adversarially verified · 10,960 lines of ZScript · engine UZDXREMA 5.0.0-rc.2`

---

## Verdict

**The merge is viable, and it is the right move. But it is not a merge — it is an integration.**

Every one of the 22 merge-blockers is mechanical: colliding root lump names, one `zscript.txt` version line, one `AddEventHandlers` list. All of them are resolved, and the merged package builds and verifies clean.

The real work is the **seam**. Three mods write `GripClaim*` using an ownership test that compares *values* rather than *owners*, and two of them write the same value. Two keep mutually invisible backup stacks for one `OffhandWeapon` slot. Two answer the same netevent on an exclusion assumption nothing enforces. None of the fourteen handlers declares `Order`. Those bugs exist *because* these are five separate pk3s — merging is what makes them fixable at all.

And one finding settles the question on its own: Holsters and HardPoints are not two mods. They are **one anchor rig sawn in half and maintained twice**, with each half carrying a complete, dead copy of the other's live direction.

---

## ⚠ The single biggest risk

**Merging turns the `GripClaim` race from intermittent into certain.**

- `RS_Holsters.zs:1017` reads the claim and, on that alone, swaps the hand's real weapon for a fist.
- `rs_held.zs:453` sets that claim the moment RS_Hands closes a hand on *any* world object.
- The claim-**set** half honours the pouch-enable cvar. The **swap** half has no pouch gate at all.

In separate pk3s a player might not run Hands and Holsters together. Merged, they always load together — so picking any weapon or barrel up off the floor reliably makes the holster mod think you reached into the ammo pouch and takes your gun away, with the pouch disabled and nothing near your chest.

The merge does not cause this bug. It removes the only thing making it occasional. **The grip arbiter must land in the same phase as the merge, not a phase later.**

---

## Census

| Severity | Count |
|---|---:|
| Critical | 18 |
| High | 39 |
| Medium | 76 |
| Low | 57 |
| **Merge blockers** | **22** |

> **Read this number honestly.** All 26 verified findings came back CONFIRMED — zero refuted. A 26-for-26 adversarial pass says as much about the verifiers as about the findings. Treat the criticals as high-confidence, not proven; each carries a file and line.

---

## Scorecard

| Package | Solidity | LOC | Commits | The honest read |
|---|:--:|--:|--:|---|
| **ModelSwapper** *(not in merge)* | 8/10 | 4,983 | 141 | Mature. Every non-obvious decision names the mod that forced it. Its build script is the only one of six that verifies its own output. |
| **RS_Holsters** | 6/10 | 3,051 | 31 | Core anchor math is an 8 — careful, heavily iterated, past wrong turns written down in-file. Zero lifecycle handling drags it down: no death, respawn, or level-change path anywhere. |
| **RS_Hands** | 6/10 | 3,805 | 17 | Best ownership discipline of the five; `RS_Basis` verified correct column by column. But "the drawn volume is the tested volume" is the package's load-bearing claim and it is not currently true. |
| **Headshots** | 6/10 | 246 | 3 | Clean, correct, zero coupling — the only member with no seam. Held back because both highest-impact gameplay paths are wrong. |
| **RS_HardPoints** | 5/10 | 2,874 | 6 | Two different halves. Store/draw core is a 7–8 and has clearly been through a headset. Gesture-cast is a 2: ships armed-at-rest by default, hours before a five-way merge. |
| **RS_Reload** | 4/10 | 984 | 1 | Scaffolding 8/10, payload 1/10. As shipped it is a gesture demo with no gameplay effect, not a reload system. |

---

## The two that change your plans

### `Refill()` is an empty stub — seating a magazine transfers no ammo
`RS_Reload/zscript/rr_sequence.zs:209`

The function body is the comment `// slice 5.` and nothing else. The whole reload interaction runs, plays its beats, and ends — and no ammunition moves. **RS_Reload currently has no gameplay effect at all.** The single most important finding in the audit.

### `RR_Point.Pit()` feeds raw `AttackPitch` into `RS_Basis`, which negates it
`RS_Reload/zscript/rr_point.zs:46`

The engine stores pitch negated; every RS_Hands call site corrects on read and this one does not. The magwell is mirrored the moment the gun is pitched — so the geometry function the mod is named for targets the wrong point. Same bug class flagged for wrist anchors 3–5: a family-wide pattern, not a one-off.

---

## Merge blockers — all mechanical, all resolved

| Blocker | Where | Resolution |
|---|---|---|
| **Merging at 4.14 cannot compile** | `rs_grab.zs:123` calls a `version("4.15.1")`-gated native | Unified at `version "5.0.0"`. Never a judgement call — 4.14 fails outright and the engine is already 5.0.0-rc.2. The three 4.14 packages lift with **zero code changes** (all 21 `const` methods checked against the SafeConst rule). |
| **Duplicate `addkeysection`** | `RS_Holsters/KEYCONF:1` and `RS_HardPoints/KEYCONF:1`, byte-identical | Both opened `addkeysection "RS HardPoints" RSHardPoints`. A copy-paste survivor of the 2026-08-23 split, never renamed on the Holsters side — the two have shared one section file, **quietly overwriting each other's binds on every config save since**. Now one section, `RSVRUnified`. |
| **10 root lump-name groups collide** | MODELDEF ×4 · TEXTURES ×3 · SNDINFO ×3 · KEYCONF ×2 · README ×5 | Hand-merged with provenance headers. Clean underneath: all 16 MODELDEF actor blocks uniquely named, the three SNDINFO namespaces don't overlap by a single name, no MENUDEF block name duplicated. |
| **Five `AddEventHandlers` lists collapse to one — and no handler declares `Order`** | `RS_Reload/MAPINFO.txt:8` | Separately these appended across pk3s. Merged, the list *is* the ordering — previously an accident of load order rather than a decision. Now one deliberate 14-handler list; the claim-ownership fix remains open. |

---

## The seam — what merging is actually for

- **`RS_Holsters.zs:1019`** — fists a hand on ANY `GripClaim`. Picking up a medikit disarms you.
- **`RS_HardPoints.zs:1484`** — gesture arming is armed-at-rest by default, ungated, pinning `HardpointClaimOff` true forever, aliasing a field a sibling mod reads for hand pose.
- **`RS_HardPoints.zs:1729`** — `fireGesture` omits `doSwap`'s wrong-hand guard, then `SetPsprites` a foreign weapon's Fire state. The same file documents that guard 700 lines away as a VM abort.
- **`RS_Holsters.zs:1858` · `RS_HardPoints.zs:56`** — a level change permanently bricks any stowed weapon. `bHolsterHidden` outlives the per-level handler that clears it.
- **`RS_HardPoints.zs:1600` · `RS_Holsters.zs:1606`** — one netevent, two `doSwap` handlers. "A hand is only ever in one place" is enforced nowhere, and edit mode lets you violate it by dragging a wrist mount onto a hip.
- **`RS_HardPointProp.zs:538, 573, 585, 595, 603`** — the `GetActorModelClass` fix landed in RS_Holsters after the split and never reached here. Five call sites. A ModelSwapper-swapped weapon renders correctly in a torso holster and wrong on an arm mount.

---

## The fork, measured

Normalising `HardPoint→Holster` and `rs_hp_→rs_` and diffing:

| | |
|---|---:|
| Differing manager lines | **852** / 4,338 |
| Differing prop lines | **61** / 1,299 |
| Cross-package type refs in 11k lines | **1** |
| cvar / class / menu collisions | **0** |

The only symbol crossing package boundaries anywhere is `RR_Point → RS_Basis`. Headshots contains zero `RS_`/`RR_` identifiers at all.

### `isHandAnchored()` is a compile-time constant — in opposite directions in each fork

```
RS_Holsters.zs:28,50    HOLSTER_COUNT = 9    HAND_HOLSTER_START = 9   -> idx >= 9  ALWAYS FALSE
RS_HardPoints.zs:58,74  HOLSTER_COUNT = 6    HAND_HOLSTER_START = 0   -> idx >= 0  ALWAYS TRUE

both files, identically:
    private bool isHandAnchored(int idx) const { return idx >= HAND_HOLSTER_START; }
```

Eleven call sites each. Every fork compiles a complete, dead implementation of the other's live direction — `RS_Holsters.zs:581-700` is an entire dead `handBasisPose`/`handAnchorPos`/`worldToHand`. **Both files' own comments admit it** (`RS_Holsters.zs:43-47`: "stays always-false and every hand-anchored…"). This is the merge's justification, written by the author, in the source.

### Two files in ONE repo disagree about the pitch/yaw convention

```
RS_HolsterFlashlight.zs:184   ang = OffhandAngle + 90;   pit = -OffhandPitch;   CORRECT
RS_Holsters.zs:583            ang = OffhandAngle;        pit =  OffhandPitch;   RAW
                              (+90 and pit=0 for the FOREARM trio only)
```

So the **wrist trio (3–5) has no yaw correction and un-negated pitch** — rotated ~90° and vertically inverted against every other package's convention, with the tuned `ed*` values having silently absorbed both errors. `RS_HolsterFlashlight.zs:30-34` names the divergence explicitly and defers it, *because there was nowhere shared to fix it*.

---

## ⚠ Do not delete or rename a single asset

Model filenames are hardcoded as `A_ChangeModel` string literals — `RS_HolsterProp.zs:155` and `RS_HardPointProp.zs:158-160` name five `.obj` files reached by the marker-shape cvar. Those files appear in MODELDEF **only inside comments**, which is exactly what led two of three independent design proposals to conclude they were dead and schedule them for deletion.

A missing model in GZDoom is a log line and an invisible actor, not an error — the hardest regression class to notice. Total duplicate waste is ~60 KB in a 6 MB pk3. Keep every byte. *All nine literals verified present in the built pk3.*

---

## The architecture that won

Three architects proposed independently and were scored against verified engine source. The winner — *one tree, blockers first, then a published frame and grip arbiter, then the anchor de-fork*:

- **One compile unit, anchor fork actually collapsed.** The only end state that stops a fix having to be applied twice and being applied once.
- **`RS_VRFrame` at `SetOrder(-1000)`, `RS_GripArbiter` at `-900`.** Verified against `events.cpp`: `OnRegister()` runs on the line *before* the insertion sort, so `SetOrder` inside it is honoured. The only tick-order guarantee that doesn't rest on string order in a merged MAPINFO.
- **The arbiter ships in shadow mode first** — logging where its resolution differs from what actually landed in `GripClaim*`, before it writes anything. Every logged divergence is a race that has been happening in silence.
- **Compute the head/hand basis once** and publish it, instead of five mods recomputing it every tic. But publish raw controller point *and* trimmed palm under different names — the grab trims were authored for grabbing and must not silently start moving holster proximity tests.
- **Import via `git subtree` without `--squash`** so history and push-back survive while the trees are still byte-identical, then declare that contract dead in writing at the restructure boundary.

---

## RS_Reload × ModelSwapper

**They play well mechanically, and badly semantically. Nothing crashes; the reload dot just stops landing on the gun.**

On every axis that breaks a GZDoom load order they are clean, verified name by name: **zero** shared cvar names (34 `rr_*` vs 23 `rs_foreignmodels_*`/`ms_pu_*`), zero shared ZScript class names (12 `RR_*` vs 68 `MS_*`/`RS_Foreign*`), zero shared MODELDEF block names, zero shared MENUDEF block names, and both append via `AddOptionMenu`. RS_Reload ships no KEYCONF and no netevents at all. The one shared basename, `chaingun.png`, is not a collision — both are skins under a MODELDEF `Path`, which GZDoom resolves fully.

ModelSwapper writes nothing to a foreign weapon except `A_ChangeModel`, the state-frame table, and floor-item sprite/frame — no ammo type, no flags, no slot. **So RS_Reload's archetype/feed inference is untouched.**

The problem is calibration. RS_Reload's entire geometry is 15 hand-tuned length/grip pairs describing a gun it cannot see, and ModelSwapper's whole purpose is changing which gun that is — with a persisted player override, an "any" family, and a one-press Randomize. Donors vary **3.08×** in size inside a single shelf. A tuning-table problem, not an architectural one, and there is a clean fix through an API ModelSwapper already exposes.

---

## Built and verified

```
RS_VR_Unified.pk3  --  115 entries, 7379.4 KB
  backslash entries : 0
  stray files       : 0
  #includes         : 22 checked, 0 unresolved
  event handlers    : 14 registered, 0 undefined
  classes           : 65 declared, 0 duplicated
  VERIFIED OK
```

ZScript namespaced per subsystem, root lumps hand-merged with provenance headers, assets unioned. One asset collision in the entire merge (`models/rs_wiresphere.obj`, byte-identical, unioned losslessly — not deleted).

**What this does not prove:** this is static verification, not a ZScript compile. The Debug build initialises Vulkan/OpenXR *before* ZScript compiles, so a headless load test could seize the display — none was run. The first real test is a headset run.

```
E:\UZDXREMA\build-dxr\Debug\doomxr.exe -iwad E:\UZDXREMA\build-dxr\Debug\doom2.wad -file E:\mERGE\RS_VR_Unified\RS_VR_Unified.pk3
```

---

## Sequencing — iterate, or develop the merge?

Both, split by **bug class** rather than by mod. A bug that lives inside one package gets fixed in that repo, where it keeps its history and stays pushable. A bug that lives *between* packages is only fixable in the merge — and those are the ones currently breaking gameplay.

1. **Lift the three 4.14 packages to 5.0.0 — separately, before merging.** Three characters in three still-separate pk3s that each still load on their own. A strictly better version-lift test than proving it inside a merge where everything else moved too.
2. **Fix `Refill()` in RS_Reload's own repo.** Everything else about that mod is moot until ammunition moves. While there: `rr_magazines` ships as a working menu toggle for a feature that doesn't exist — fix the row and the README in the same commit, or the merged package gets blamed for it.
3. **Gate gesture arming — it is an arbiter *input*.** A pinned-true `HardpointClaimOff` doesn't merely force a pose; once the arbiter routes the grab netevent by claim, it hands the off hand's grip to the arm rig permanently, in preference to holsters. Prerequisite, not cleanup.
4. **Fix the pouch swap gate — same phase as the merge, not after.** The swap half needs the pouch-enable gate its own claim-set half already honours.
5. **Land the frame and the arbiter with the merge.** Ship the merge and its arbitration together, or the merge is a regression.
6. **Then collapse the anchor fork.** One `RS_AnchorRig`, two concrete rigs. Prove the two-EventHandler-subclasses-of-one-base pattern with a throwaway pair *before* writing 1,700 lines against it — no instance of it exists in these five repos. Fallback: a plain `play` class held by composition, one field, every benefit kept.
7. **Re-tune the wrist trio deliberately, behind an adapter.** Unifying the basis relocates every tuned arm anchor, because the `ed*` values absorbed the ~90° and the inverted pitch. Legacy-basis path default-on with a cvar to switch. The file warns this math has been hand-derived wrongly twice — do not flip signs blind.
8. **Budget the tic.** Fourteen handlers at 35 Hz on Quest-class hardware will not absorb what's there: `RS_Reach.Centre` walks the whole thinker list per call and is invoked per blockmap candidate, and `RS_GrabViz` duplicates a scan its own comment forbids duplicating.

**One question the source cannot settle:** what should happen when a hand already carrying a magazine grabs a world object? The pouch's contract is explicit and Holsters defers to it, which is why reload outranks held. But nothing states the reverse. Today `RS_Held` overwrites the magazine claim and the reload abort declines to clear it, leaving the hand posed for a magazine it no longer holds. An arbiter makes that deterministic — it does not tell you which answer is *right*.

---

## Also worth knowing

- **Your architecture docs were deleted.** `CLAUDE.md` was removed from HEAD of both Holsters and HardPoints by their most recent commits, and neither commit message says so. 830 lines recovered from history into `docs/` — they contain the ZScript dialect limits and the `PendingWeapon` hazard. Four files still reference the deleted path.
- **The packagers were leaking.** `RS_Holsters.zip` shipped `.claude/settings.local.json`, `holsterideas.txt` and `README.md`; `RS_HardPoints.zip` shipped `README.md`. Both used exclusion lists, so anything nobody thought to exclude shipped. The new packer uses an allowlist and cannot fail that way. Contents were benign — hygiene, not exposure.
- **One doc claim is stale:** `GetActorModelClass` *is* pushed — commit `97e77ce33e` on `mine/main`.
- **Sound bugs already live in shipped builds:** `rr/magdraw` is commented out under a header comment asserting the opposite, and two sound names the code treats as owned live only in RS_Main — which is not in the merge.
- **The committed build artifacts are a loaded gun.** All five pk3/zip artifacts are tracked in their own repos. Staging any one puts a complete copy of a mod inside the merged pk3 — a duplicate-class fatal, and the exact hazard RS_Holsters' own build header was written about.
- **Profile keys will collide across rigs and fail silently** once the two rigs share a save path: both write the identical `h%d_` schema, kept apart today only by differing profile names and counts. Loading an arm layout onto torso holsters would *succeed*, seating six arm offsets onto six torso anchors, because the loader falls back per-field to defaults rather than erroring.
- **The arbiter will be reported as a regression.** Today's winner of a claim contest is whoever ticks last — WAD load order, since there are zero `SetOrder` calls anywhere in the five. The pouch swap currently fires for RS_Hands' grabs too, so a player may have been unknowingly using barrel-grabs to stow a weapon. Shadow mode exists so this is discovered in a log rather than in a headset.

---

## Repository layout

```
RS_VR_Unified/
  build.ps1              verifying packer (allowlist, not exclusion list)
  zscript.txt            one version line: 5.0.0
  MAPINFO.txt            one AddEventHandlers list, 14 handlers, deliberately ordered
  KEYCONF                one key section (duplicate addkeysection bug fixed)
  CVARINFO.txt           178 cvars, zero collisions
  MENUDEF.txt            31 menu blocks, zero collisions
  MODELDEF.txt  TEXTURES.txt  SNDINFO.txt  TRNSLATE.txt
  zscript/
    hands/       10 files    foundation - RS_Basis, everything reads from it
    holsters/     4 files    torso anchors + chest ammo pouch
    hardpoints/   2 files    arm anchors (sibling fork of holsters)
    reload/       4 files    needs hands' basis AND holsters' pouch
    headshots/    2 files    independent, no seam
  models/ graphics/ sprites/ sounds/
  docs/                  recovered CLAUDE.md architecture notes (830 lines)
```

Build: `.\build.ps1` — writes `RS_VR_Unified.pk3` and fails the build on unresolved includes, undefined handlers, duplicate classes, stray non-lump files, or a wrong version line.
