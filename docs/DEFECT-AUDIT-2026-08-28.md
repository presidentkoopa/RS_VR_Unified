# Defect Audit -- RS_VR_Unified, 2026-08-28

Player-facing runtime defects across all five subsystems. Produced by a 69-agent
analysis pass in which every candidate finding was handed to an independent agent
whose sole instruction was to REFUTE it, defaulting to refuted when it could not be
positively confirmed.

**60 findings raised. 40 survived verification. 20 refuted.**

This audit deliberately excludes architecture commentary, refactor suggestions, and
"constrained by legacy Doom design" observations. Everything below is something that
produces a wrong or broken RESULT a player could observe, or that corrupts state.

## How to read a finding

- **Severity** is the reporting agent's call: `broken-at-defaults` (no unusual settings
  needed), `broken-in-common-case`, `broken-in-edge-case`, `latent`.
- **Verification** is the refuting agent's independent read. Where it found the original
  claim partly wrong, its **Correction** supersedes the Cause/Trigger above it -- several
  findings survived only in narrowed form, and the correction is the accurate version.
- Line numbers are as of 2026-08-28 and will drift as files are edited.

## Contents

- [Holsters](#holsters) -- 3 findings
- [Hands](#hands) -- 5 findings
- [Reload](#reload) -- 3 findings
- [HardPoints](#hardpoints) -- 3 findings
- [Wheel - Layout & Geometry](#wheel-layout-geometry) -- 4 findings
- [Wheel - Selection & Input](#wheel-selection-input) -- 5 findings
- [Wheel - Painting & Pools](#wheel-painting-pools) -- 7 findings
- [Wheel - Stat Resolver & Tracker](#wheel-stat-resolver-tracker) -- 4 findings
- [Wheel - Compatibility Shims](#wheel-compatibility-shims) -- 6 findings

---

## Holsters

### 1. Every store/draw dumps 5-7 lines of yellow debug text into the player's view

**File:** `E:\mERGE\RS_VR_Unified\zscript\holsters\RS_Holsters.zs (+ RS_HolsterProp.zs)`  
**Line:** RS_Holsters.zs 2324, 2391, 2400, 2418, 2460, 2536, 2640-2664, 2674, 2681; RS_HolsterProp.zs 746, 772  
**Severity:** `broken-at-defaults`

**Symptom**

Reaching into any holster and squeezing grip paints a block of yellow (\cy) console text across the HUD message area: "doSwap ENTER hand=off holsterIdx=1", "pre-commit i=0 slot=1 contents.Size()=72 contents[slot]-BEFORE=null", "post-commit contents[1]=VR_SMG", "about to seat fist=... BEFORE: Ready=... Offhand=...", "AFTER seating: Ready=... Offhand=... PendingWeapon==WP_NOCHANGE=1", then next tic "RS_HOLSTERPROP: A_ChangeModel(VR_SMG) for VR_SMG -- boundsFound=1 sprite=... frame=...". A single store is ~6 lines; a store+draw pair is ~12.

**Cause**

rs_holster_verbose defaults to false (CVARINFO.txt:670) and verboseDiag() correctly gates the *older* instrumentation (1288, 1296, 2355, 2508, 2613, 2699, 2787). None of the eleven Console.Printf calls added under the "TEMPORARY, 2026-08-26 / 2026-08-28" comments were put behind it. Line 2324 is explicitly documented as an "unconditional entry marker"; 2418/2536 fire on every commit; 2674/2681 fire on every empty-holster store; RS_HolsterProp.zs:772 fires on every class change, i.e. every store AND every draw. CVARINFO's own text for rs_holster_verbose says the point of the cvar was to stop "a PERMANENT INSTRUMENTATION LAYER shipped switched on in the default build" -- a different, larger such layer is switched on in the default build right now.

**Trigger**

DEFAULTS. rs_holster_verbose = false. Any grip press inside any holster claim volume.

**Verification**

I tried to refute this and could not. Every load-bearing point checks out.

(a) Cited lines say what is claimed â€” verified in RS_Holsters.zs:
- 2324: `Console.Printf("\cy RS_HOLSTER: doSwap ENTER  hand=%s  holsterIdx=%d", ...)` â€” no enclosing conditional, and the comment above it (2319) literally says "TEMPORARY, 2026-08-26: unconditional entry marker."
- 2391, 2400: unconditional, on the two cooldown-refusal returns.
- 2418: unconditional `pre-commit  i=%d  slot=%d  contents.Size()=%d  contents[slot]-BEFORE=%s`.
- 2460: unconditional no-op line.
- 2536: unconditional `post-commit  contents[%d]=%s`.
- 2640-2664: unconditional inventory dump; its own comment at 2637-2639 says "Not gated on rs_holster_verbose."
- 2674, 2681: unconditional "about to seat fist" / "AFTER seating".
None of these eleven are inside a `verboseDiag()` block. The gated calls really are only at 431, 1287, 1295, 2354, 2507, 2612, 2698, 2787 â€” the older instrumentation, exactly as the reporter split them.

(b) Defaults correct. CVARINFO.txt:670 `user bool rs_holster_verbose = false;`. Both gates (RS_Holsters.zs:2157 verboseDiag, RS_HolsterProp.zs:445 holsterVerbose) return false when the cvar is absent, so false is the effective default either way. No master enable/disable cvar for the holster system exists; rs_holster_active_count defaults to 8, so all anchors are live.

(c) Not guarded anywhere the reporter missed. NetworkProcess (2168) gates only on event name â€” no developer check, no dev-build flag. ZScript has no preprocessor. Both files are compiled into the shipped build (zscript.txt:82-83 `#include "zscript/holsters/RS_HolsterProp.zs"` and `RS_Holsters.zs`).

(d) Arithmetic mostly works out, with one overcount. Store into an empty holster = 2324 + 2418 + 2536 + 2674 + 2681 = 5 lines, plus the RS_HolsterProp print on the next tic = 6. That matches. But a DRAW is only 3 lines (2324 + 2418 + 2536): the prop's unconditional print sits after `if (wantClass != shownClass)` and the draw calls ShowWeapon(null), which takes the `w == null` branch and returns at RS_HolsterProp.zs:641 â€” long before the print. So a store+draw pair is ~9 lines, not ~12.

(e) Genuinely player-observable, and worse than reported. Console.Printf lands in the notify area over the HUD. Critically, line 2324 sits BEFORE the `if (holsterIdx < 0) return;` guard at 2327, and the same handler also receives RS_HardPoints' shared netevents (`rs-vrhp-grab-main` / `rs-vrhp-grab-off`, lines 2261/2266). So every grip press anywhere in the game â€” hands nowhere near a holster, and grips meant for hardpoints â€” emits "RS_HOLSTER: doSwap ENTER hand=main holsterIdx=-1". The comment at 2323 asserting it "cannot become spam" is wrong for exactly that reason.

Two cosmetic errors that do not touch the defect: the RS_HolsterProp line numbers are wrong (746 is a comment; the print there is at 764-766 and IS gated by holsterVerbose(). The genuinely unconditional one is at 791-792, and 772 is `mirrored = false;`), and `\cy` is sapphire/blue in GZDoom's color-escape table, not yellow (`\ck` is yellow).

**Correction (supersedes Cause/Trigger above)**

Confirmed, with corrections to line numbers, color, and counts.

Corrected claim: Eleven ungated `Console.Printf` diagnostics on the holster interaction path fire at default settings (`rs_holster_verbose = false`, CVARINFO.txt:670), painting sapphire-blue (`\cy`, not yellow â€” `\ck` is yellow) console text across the HUD notify area.

Corrected line citations:
- RS_Holsters.zs 2324, 2391, 2400, 2418, 2460, 2536, 2640/2660/2664, 2674, 2681 â€” all correct as reported, all unconditional.
- RS_HolsterProp.zs: the cited 746 and 772 are wrong. Line 764-766 IS correctly gated behind `holsterVerbose()`. The actual unconditional print is at **RS_HolsterProp.zs:791-792** (`"\cy RS_HOLSTERPROP: A_ChangeModel(%s) for %s -- boundsFound=%d sprite=%d frame=%d"`).

Corrected counts: a store into an empty holster is 6 lines (2324, 2418, 2536, 2674, 2681, plus RS_HolsterProp:791 on the following tic). A draw is only 3 lines (2324, 2418, 2536) â€” the prop print does NOT fire on a draw, because a draw calls `ShowWeapon(null)`, which takes the `w == null` branch and returns at RS_HolsterProp.zs:641 before reaching 791. A store+draw pair is therefore ~9 lines, not ~12.

The claim also understates the scope. Line 2324 sits BEFORE the `if (holsterIdx < 0) return;` guard at line 2327, and the handler at 2261/2266 also receives RS_HardPoints' shared `rs-vrhp-grab-main`/`rs-vrhp-grab-off` netevents. So the trigger is not "any grip press inside any holster claim volume" â€” it is ANY grip press anywhere in the game, including presses nowhere near a holster and presses intended for hardpoints, each emitting `RS_HOLSTER: doSwap ENTER  hand=main  holsterIdx=-1`. The in-code comment at line 2323 claiming it "cannot become spam" is incorrect for that reason.

---

### 2. Holstered weapon stays fully solid for 8 tics after you draw it -- the prop's whole fade system is inert

**File:** `E:\mERGE\RS_VR_Unified\zscript\holsters\RS_HolsterProp.zs`  
**Line:** 342-353 (Default block), 543-568 (Tick), 568 (`Alpha = fadeAlpha;`)  
**Severity:** `broken-at-defaults`

**Symptom**

Draw a gun out of a holster and for ~0.23 s you are holding it AND an identical solid copy is still sitting in the holster; it then blinks out instantly rather than fading. Same on death (contents[] cleared) and on `rs_holster_props 0`. Worse when both display switches are off or `rs_holster_active_count` is dialled down: updateProps `continue`s/returns before SetOrigin, so the affected props hang FROZEN in world space at full opacity for those 8 tics while the player keeps walking -- weapon models detach from the body and float.

**Cause**

RS_HolsterProp's Default block declares no RenderStyle, so it inherits Actor's `RenderStyle Normal`. renderstyle.cpp:38 defines STYLE_Normal with STYLEF_Alpha1, and hw_sprites.cpp:1639 does `else if (RenderStyle.Flags & STYLEF_Alpha1) trans = 1.f;` -- the actor's Alpha is discarded before the sprite/model draw. So `Alpha = fadeAlpha` (line 568) renders nothing; the only thing the ramp does is delay `bINVISIBLE = true` (line 558) by 1.0/FADE_STEP = 1.0/0.125 = 8 tics. Its sibling RS_HolsterMarker (line 39) declares `RenderStyle "Add"`, which has no STYLEF_Alpha1, so the identical fade code works there -- which is why the mismatch went unnoticed.

**Trigger**

DEFAULTS. Every draw, every death, every `rs_holster_props` toggle, every `rs_holster_active_count` change.

**Verification**

I tried to break this on all five axes and it survives every one.

(a) DO THE CITED LINES SAY IT? Yes, with ~11 lines of citation drift. `E:\mERGE\RS_VR_Unified\zscript\holsters\RS_HolsterProp.zs` line 342 `class RS_HolsterProp : Actor`, Default block 344-353: `+NOBLOCKMAP +NOGRAVITY +NOINTERACTION +DONTSPLASH +NOTONAUTOMAP Radius 1; Height 1;` â€” no RenderStyle, no Alpha. Tick is 554-595 (not 543-568); `bINVISIBLE = true;` is line 569 and `Alpha = fadeAlpha;` is line 579 (not 568). `const FADE_STEP = 0.125;` is line 524. Sibling `RS_HolsterMarker` does declare `RenderStyle "Add";` at line 39, exactly as claimed.

(b) ENGINE FACTS â€” verified against the actual fork source, not memory. `E:\UZDXREMA\src\common\engine\renderstyle.cpp:38`: `{ { STYLEOP_Add, STYLEALPHA_Src, STYLEALPHA_InvSrc, STYLEF_Alpha1 } }  /* STYLE_Normal */` â€” exact line cited, exact flag. Line 41 `/* STYLE_Add */` has flags `0`, so the marker's fade genuinely does work while the prop's cannot. `E:\UZDXREMA\src\rendering\hwrenderer\scene\hw_sprites.cpp:1639`: `else if (RenderStyle.Flags & STYLEF_Alpha1) { trans = 1.f; }` â€” exact line, and `trans = alpha` (from `thing->InterpolatedAlpha`, line 976/1612) is discarded there. `E:\UZDXREMA\wadsrc\static\zscript\actors\actor.zs:656`: `RenderStyle 'Normal';` is Actor's Default, so RS_HolsterProp inherits STYLE_Normal. `FRenderStyle::IsVisible` (renderstyle.cpp:87) also forces `alpha = 1.` under STYLEF_Alpha1, so a low Alpha cannot even cull the actor.

This path is confirmed to cover MODELS, not just sprites: hw_sprites.cpp:1679 branches on `(modelframe && thing->RenderStyle != DefaultRenderStyle())`, and 1665 lists `modelframe` in the solid-blend branch â€” a model actor left at the default render style is explicitly routed to STYLEHW_Solid.

Decisive corroboration: the engine's own fade helpers all clear the flag before touching Alpha â€” `p_actionfunctions.cpp:1442` (A_SetTranslucent), `1489` (A_FadeIn), `1523` (A_FadeOut), `1554` (A_FadeTo) each do `self->RenderStyle.Flags &= ~STYLEF_Alpha1;`. The prop's hand-rolled fade writes `Alpha` raw and never clears it.

(c) IS IT GUARDED ELSEWHERE? No. `grep -rn -i renderstyle E:\mERGE\RS_VR_Unified\` returns 11 hits total; the only A_SetRenderStyle in the whole mod is `zscript\wheel\zscript.zs:6125` on wheel card models. Nothing in `RS_Holsters.zs` touches RenderStyle, Alpha, bINVISIBLE, or any A_Fade* on props â€” the only prop visibility levers are `SetVisible()` calls at RS_Holsters.zs:1456, 1486 and inside ShowWeapon (633, 649, 654).

(d) DOES THE ARITHMETIC BREAK AT DEFAULTS? Yes. CVARINFO.txt:484 `rs_holster_props = true`, :498 `rs_holster_markers = true`, :609 `rs_holster_active_count = 8` â€” so at defaults the props are on and all 8 holsters live. Drawing from a holster with an empty hand hits RS_Holsters.zs:2532 `contents[slot] = (heldName != "") ? held : null;` â†’ null â†’ updateProps:1717-1718 `Weapon toShow = wantProps ? stored : null; p.ShowWeapon(toShow, ...)` â†’ RS_HolsterProp.zs:626 `wantClass != shownClass` â†’ 632-633 `pendingClear = true; SetVisible(false);`. fadeAlpha then walks 1.0 â†’ 0.0 at 0.125/tic = 8 tics (0.229 s at 35 Hz), with `bINVISIBLE` held false the whole way (569) and the weapon's model/sprite still bound because `pendingClear` deliberately defers `ClearModelStateFrames()` until the fade "finishes" (570-576). With trans pinned to 1.0 those 8 tics render at full opacity, then the model pops out in one frame. The feature is not merely cosmetically degraded â€” it is strictly worse than the `bINVISIBLE` cut it replaced, because it added an 8-tic delay and delivered none of the fade it was traded for. The fade-IN is equally inert (store a weapon and it appears at full opacity instantly rather than easing in).

(e) PLAYER-OBSERVABLE? Yes. 0.23 s is ~20 frames at VR framerate, at a hip/chest anchor that is in view while you draw. The freeze sub-claim also checks out and is correctly scoped: `!holsterActive(h)` â†’ `continue` at RS_Holsters.zs:1487 skips the `p.SetOrigin(placed, true)` at 1805, and both-switches-off `return`s at 1465 â€” so in those cases the still-opaque prop hangs in world space while the player walks away. The reporter correctly did NOT claim a freeze for `rs_holster_props 0` alone; I checked, and with markers still on the loop does keep running and SetOrigin still fires.

I found no way to make this finding wrong.

**Correction (supersedes Cause/Trigger above)**

The finding stands. Two precision fixes:

1. LINE NUMBERS drift by ~11: Tick() is RS_HolsterProp.zs:554-595, `bINVISIBLE = true;` is line 569, `Alpha = fadeAlpha;` is line 579, `const FADE_STEP = 0.125;` is line 524. The Default block citation (342-353) is correct as given.

2. The claim's "renderstyle.cpp:38 defines STYLE_Normal" was stated from memory but is literally correct in this fork's own tree (E:\UZDXREMA\src\common\engine\renderstyle.cpp:38 â€” note the path is common/engine, not common/rendering), as is hw_sprites.cpp:1639.

One addition the reporter did not mention: the same defect exists verbatim in the sibling subsystem. E:\mERGE\RS_VR_Unified\zscript\hardpoints\RS_HardPointProp.zs declares `class RS_HardPointProp : Actor` at line 288 with no RenderStyle, `const FADE_STEP = 0.125;` at 461, and `Alpha = fadeAlpha;` at 516 â€” while RS_HardPointMarker at line 39 has `RenderStyle "Add";`. Identical split, identical dead fade. The one-line fix (adding `RenderStyle "Translucent";` to the prop Default block, or `A_SetRenderStyle`/clearing STYLEF_Alpha1) should be applied to both prop classes, not just the holster one.

---

### 3. Two holsters ship at their debug position, floating 7 units in front of the player's face

**RESOLVED 2026-08-30** -- owner's call: not an issue, the positions are intended.

**File:** `E:\mERGE\RS_VR_Unified\zscript\holsters\RS_Holsters.zs`  
**Line:** 125-134 (GetHolster cases 2 and 3)  
**Severity:** `broken-at-defaults`

**Symptom**

On a fresh install two bracket markers hover in mid-air roughly 7 in front of and 10 to each side of the head, 3 in below eye level -- not on the body at all -- and each carries a live 6-inch grip-claim volume there. Because the engine treats a grip press that starts inside a holster claim as GRIPCTX_Holster, which outranks GRIPCTX_Object, GRIPCTX_Modifier and GRIPCTX_Stabilize (vk_openxrdevice.cpp:3710-3760), a grip squeezed with a hand up in that region stores/draws instead of doing whatever grip normally does there.

**Cause**

cases 2/3 read `hsFwd = 7.0; hsSide = -/+10.0; hsFrac = 0.95`. The comment immediately above them says this is "TEMPORARILY PLACED IN FRONT (positive hsFwd) so they are actually visible while being set up... Drag them back beside the head in edit mode once they work; roughly hsFwd -2, hsSide +/-8 is where they belong." That drag-back never happened, and rs_holster_active_count defaults to 8 (CVARINFO.txt:609, "Defaults to everything on"), so activeCount() returns 8 and holsterActive(2)/holsterActive(3) are true out of the box. MENUDEF.txt:490 additionally labels this tier "4 -- + Shoulder", which is neither what the table holds ("HeadLeft"/"HeadRight") nor where it puts them. At a calibrated eye height of 64, the anchors land at z = HmdPos.Z - 0.05*64 = 3.2 below the eyes, 7 forward, 10 lateral.

**Trigger**

DEFAULTS. rs_holster_active_count = 8 (also at 4 and 6). No profile loaded, or any profile saved before this was noticed.

**Verification**

I could not refute this; every checkable element holds.

(a) RS_Holsters.zs:125-134 reads verbatim as claimed: the comment "TEMPORARILY PLACED IN FRONT (positive hsFwd) so they are actually visible while being set up... Drag them back beside the head in edit mode once they work; roughly hsFwd -2, hsSide +/-8 is where they belong", followed by case 2 `hsName = "HeadLeft"; hsFwd = 7.0; hsSide = -10.0; hsFrac = 0.95; hsRadius = 3.0;` and case 3 the mirror at +10.0.

(b) CVARINFO.txt:609 is exactly `user int rs_holster_active_count = 8;` (comment above it: "Defaults to everything on"). activeCount() (1876-1884) snaps to 2/4/6/8 and returns 8. holsterActive(h) (1902-1907) is `h < activeCount()` for every non-pouch index, so indices 2 and 3 are live at 8, and also at 6 and 4 â€” only the "2 -- Hip" tier excludes them. MENUDEF.txt:490 is exactly `4, "4 -- + Shoulder"`, which does not match the table's HeadLeft/HeadRight names or their placement.

(c) No guard, clamp, or fix-up exists. Grepping every write to edFwd[] gives only two: ensureEdit() line 762 seeding directly from GetHolster, and loadProfile() line 1133, whose per-field fallback is the same GetHolster value. autoLoadProfile() (679-689) tries level.JSONProfileLoad("holster_standing") then "holster_seated"; no profile JSON ships anywhere in E:\mERGE\RS_VR_Unified (checked the full tree), so a fresh install runs the raw table. The "Reset offsets to defaults" netevent restores these same numbers. updateClaims (1229-1272) and updateProps (1481) gate only on holsterActive(h) â€” nothing tests distance-from-head, occupancy, or plausibility of the anchor.

(d) The arithmetic works out as claimed. anchorPos (823-846) computes HmdPos + edFwd*(cos yaw, sin yaw) + edSide*(sin yaw, -cos yaw), and z = (HmdPos.Z - eyeHeight) + eyeHeight*edFrac. With edFrac 0.95 that is HmdPos.Z - 0.05*eyeHeight = 3.2 below the eyes at a 64-unit eye height. Result: 7 forward, 10 lateral, 3.2 down â€” about 12.6 units from the eye at ~55 degrees off-axis and ~15 degrees below the horizon, following bodyYaw (which has a 50-degree neck deadzone, so a head turn swings the marker into direct view rather than moving it away).

(e) Genuinely player-observable, not theoretical. updateProps spawns and repositions an RS_HolsterMarker for every active index each tic; RS_HolsterProp.zs:271 gives a cold marker baseAlpha 0.85 and line 296 sets Alpha = fadeAlpha * baseAlpha, so these draw solid, not hidden. rs_holster_markers defaults true (CVARINFO.txt:498). The mesh is rs_holster_bracket.obj at MODELDEF Scale 3.0, i.e. the 6-inch claim volume drawn at true size ~12.6 inches from the eye. The claim volume is live too: updateClaims sets pawn.HolsterClaimMain/Off true for a hand within 3.0 of the anchor and records nearMain/nearOff = 2 or 3, and NetworkProcess (2261-2270) passes nearMain/nearOff straight into doSwap, so a grip press with a hand in that region stores or draws a weapon.

The one item I could not verify is the C++ citation: no vk_openxrdevice.cpp exists anywhere under E:\ at depth 6, so I cannot confirm vk_openxrdevice.cpp:3710-3760 or the GRIPCTX precedence order. That does not rescue the finding â€” this file's own header (lines 1-5) states the same mechanism ("this is the part that actually DRIVES the engine's HolsterClaimMain/HolsterClaimOff -- without this handler running... grip keeps its normal meaning everywhere"), and the ZScript side demonstrably sets those fields true and acts on the resulting press.

**Correction (supersedes Cause/Trigger above)**

Confirmed as reported, with three precision fixes:

1. The 3.2-unit drop is not fixed â€” it is 0.05 * calibrated eye height (edFrac 0.95). At the 64-unit eye height the reporter assumes it is 3.2; at the EYE_MIN/EYE_MAX bounds (36/96, lines 366-367) it ranges 1.8 to 4.8. The 7-forward and 10-lateral offsets are raw map units and do not scale.

2. "Beside the head" understates the position: the anchor is forward-and-outboard, ~12.6 units from the eye at ~55 degrees off-axis, i.e. at the edge of a typical headset FOV when facing forward. Because anchors follow bodyYaw with a 50-degree neck deadzone (lines 342, 810-811), a head turn toward the marker brings it to screen centre at arm's-length-minus rather than sweeping it away â€” which is what makes it unmissable rather than merely peripheral.

3. The engine-side precedence citation (vk_openxrdevice.cpp:3710-3760, GRIPCTX_Holster outranking Object/Modifier/Stabilize) is unverifiable here â€” that source is not present on this machine. The player-facing consequence does not depend on it: RS_Holsters.zs sets HolsterClaimMain/Off true for these anchors and NetworkProcess line 2264/2269 feeds nearMain/nearOff (2 or 3) into doSwap, so the grip performs a store/draw against a phantom head-side holster regardless of how the native arbiter ranks contexts.

---

## Hands

### 4. Pulled objects can never be caught beyond ~2 m -- they always slam into you instead

**RESOLVED 2026-08-30** -- the catch itself was fixed earlier by holding the object on the palm for CATCH_HOLD_TICS (the old test resolved against the BODY, closing the window before it opened). A missed catch now always just drops the object at your feet: the pickup/damage branch and `rs_dgrab_impact` are deleted outright, not merely defaulted off.

**File:** `E:\mERGE\RS_VR_Unified\zscript\hands\rs_distance.zs`  
**Line:** 500-637 (tic loop), 615-637 (Impact), 446-456 (CatchableBy); catch call site rs_grab.zs:868-891; order set by MAPINFO.txt AddEventHandlers  
**Severity:** `broken-at-defaults`

**Symptom**

Point at a barrel across the room, grip to lock, flick to pull it, then hold your hand out open/closed to catch it. It arcs over and thumps into you for 5 damage and drops at your feet -- it never lands in your hand. Debug prints "[RSPULL] hand N grabbed at X and missed" on the press edge and then "[RSPULL] X hit you -- 5 damage". A pulled medikit silently heals you instead of being carried. Catching only works for pulls launched from within roughly 50-70 map units (1.5-2 m), which is barely past arm's reach; the advertised range is rs_dgrab_reach = 512 (15 m).

**Cause**

Two things compound. (1) RS_GrabHandler is registered 4th and RS_Pull 7th, so RS_GrabHandler.WorldTick asks pull.CatchableBy() using the position RS_Pull wrote LAST tic. (2) RS_Pull's loop reaches t == 1.0, moves the object onto the palm, and calls Impact() in the same pass (rs_distance.zs:615 `if (t < 1.0) continue;` then :637 `Impact(...)`), so the object never survives a single tic sitting at the palm. The last position the catch test ever sees is therefore flyTic == flyTotal-1. With upt = 14.571 units/tic and e = t**1.6, the residual gap at that sample is (1-e)*dist which converges to 1.6*upt = 23.3 map units for any pull long enough that flyTotal = dist/upt, plus an arc lift of 4*(0.15*dist)*e*(1-e) = 0.96*upt = 13.3 units straight up. Worked example at dist=512: flyTotal=int(35.14)=35, t=34/35=0.97143, e=0.95468, remaining = 0.04532*512 = 23.2 units short and 13.3 units high. RS_Reach.ScoreAt is then run against semi-axes (2.2, 3.2, 1.6). For a barrel (Radius 10, Height 42) ClosestOn trims 10 units off the horizontal, leaving 13.2 units -> score (13.2/3.2)^2 = 17.0, versus the required <= 1.0. For a medikit (Radius 20, Height 16) the 13.3-unit lift puts the palm 5.3 units below the cylinder bottom -> fz = 5.3/1.6 = 3.3, score 11.9. Solving for score <= 1 gives dist <= ~52 for a barrel and dist <= ~70 for a radius-20 pickup.

**Trigger**

Pure defaults. rs_dgrab=true, rs_dgrab_speed=15.0, rs_dgrab_accel=1.6, rs_dgrab_arc=0.15, rs_dgrab_time_min=6, rs_grab_scale_space=0, rs_grab_m_scale=1.0, rs_grab_m_scale_x/y/z=2.2/3.2/1.6. Any pull launched from more than ~70 map units (2 m). Short pulls under ~50 units DO catch, which is probably why this survived a headset pass.

**Verification**

I read rs_distance.zs in full, rs_grab.zs:100-330 and :560-920, MAPINFO.txt:82, CVARINFO.txt, and rs_swing.zs:47-54, and grepped the whole tree for every RS_Pull consumer.

(a) Cited lines are accurate. rs_distance.zs:615 `if (t < 1.0) continue;` sits directly above :637 `Impact(a, pmo, p, h);`, after the SetZ/TryMove at :577-578 â€” so on the tic where t reaches 1.0 the object is placed on the palm and resolved in the same pass. rs_distance.zs:455 is `return (RS_Reach.ScoreAt(pmo, p, hand, RS_Reach.ClosestOn(a, c), c) <= 1.0) ? a : null;`. rs_grab.zs:617 sets nearTarget from CatchableBy, and :870 `if (grip && nearTarget[hand] && pull.Catch(hand, pmo, p)) continue;` is the ONLY Catch call site in the tree (verified by grep across zscript/). MAPINFO.txt:82 lists RS_GrabHandler 4th and RS_Pull 7th; both are plain `EventHandler` with no Order declared, and the file's own header note confirms WorldTick runs front-to-back.

(b) Defaults are exactly as claimed, all from CVARINFO.txt: rs_dgrab=true(:268), rs_dgrab_reach=512(:274), rs_dgrab_speed=15.0(:282), rs_dgrab_time_min=6.0(:285), rs_dgrab_time_max=70(:286), rs_dgrab_accel=1.6(:291), rs_dgrab_arc=0.15(:301), rs_dgrab_impact=5.0(:360), rs_grab_scale_space=0(:170), rs_grab_m_scale=1.0(:177), rs_grab_m_scale_x/y/z=2.2/3.2/1.6(:179-181), rs_hold_debug=true(:222). Nothing in MENUDEF.txt or KEYCONF presets different values. RS_Swing.MetresPerSecToUnitsPerTic is `m * 34.0/35.0`, so upt = 14.571 u/tic.

(c) Not guarded anywhere. rs_route.zs and rs_held.zs contain no RS_Pull references; rs_grabviz.zs only draws; rs_hands.zs:468-479 only selects a hand pose. rs_grab.zs:615-619 explicitly short-circuits the near/cone search while flying, so nothing else can widen or re-run the test. There is no grace window, no snap, no second sample.

(d) The arithmetic holds. flyTotal = int(clamp(dist/14.571, 6, 70)). At dist=512 that is int(35.14)=35, last catch sample at t=34/35=0.97143, e=t^1.6=0.95468, residual (1-e)*512=23.2 units and lift 4*(0.15*512)*e*(1-e)=13.3 units up. The residual converges to 1.6*upt=23.3 for any pull long enough that flyTotal=dist/upt, so range never helps. Barrel (R10 H42): ClosestOn z-clamps to the palm because the palm is inside the 42-tall cylinder, horizontal trims 23.2 to 13.2, fx=13.2/3.2=4.125, score 17.0 vs the required <=1.0. Radius-20/height-16 pickup: horizontal trims to 3.2 (fx^2=1.0) but the 13.3 lift puts the palm 5.3 below the cylinder bottom, fz=3.31, total ~12.0. I also checked that placing the residual on the LONGEST semi-axis (3.2, forward â€” the hand pointed at the incoming object) is the most favourable orientation, so no hand pose rescues it, and that a player running toward the object does not help either (arcH is frozen at launch distance, so the 13.3 lift persists while the horizontal gap shrinks).

(e) Player-observable at defaults: the advertised pull range is 512 units (~15 m) and catching stops working past roughly 50-80 units. That is the headline feature failing across ~85% of its own range.

Two refinements, neither of which refutes the finding. First, the handler-ordering half of the stated cause is not load-bearing: if RS_Pull ran FIRST, tic N would move the object to the palm and Impact would null flyActor in the same pass, so pull.Flying(hand) at rs_grab.zs:868 would already be false and the last sample would still be t=(N-1)/N. Cause (2) â€” Impact firing in the same pass that reaches the palm â€” is sufficient on its own. Second, the catchable ceiling for a radius-20 pickup is ~82 units rather than ~70 (at dist=80 flyTotal clamps to time_min=6, residual 20.2 trims to ~0 against radius 20, lift 9.07 gives fz^2=0.45, total under 1.0); the barrel figure of ~52 is correct.

I could not refute any element of this.

**Correction (supersedes Cause/Trigger above)**

The defect is real as described; two details need adjusting. (1) The stated cause should be attributed solely to rs_distance.zs:615-637 â€” the tic loop reaching t==1.0, moving the object onto the palm, and calling Impact() in the same pass, so the object never survives a tic sitting at the palm. The handler-registration order (RS_GrabHandler 4th, RS_Pull 7th in MAPINFO.txt:82) does NOT compound it: with the order reversed, Impact would null flyActor before RS_GrabHandler ran, so pull.Flying(hand) at rs_grab.zs:868 would be false and the last catch sample would still be flyTic == flyTotal-1. The fix must address the same-pass Impact, not the ordering. (2) The catchable ceiling for a radius-20/height-16 pickup (medikit, ammo box, most Doom items) is ~82 map units, not ~70, because rs_dgrab_time_min=6 clamps flyTotal to 6 for any launch under 87 units. The barrel figure of ~52 is correct.

---

### 5. Both hands can lock and launch the SAME object, permanently corrupting its flags

**File:** `E:\mERGE\RS_VR_Unified\zscript\hands\rs_distance.zs`  
**Line:** 70-100 (RS_Cone.Best candidate filter, line 76), 186-201 (Lock), 306-382 (Start, guard at line 309)  
**Severity:** `broken-in-edge-case`

**Symptom**

Flick a barrel toward one hand, then point the other hand at it in flight and grip+flick it too. Both arcs drive the same actor with TryMove each tic; it jitters between two homing paths. When the second flight ends, the barrel is left permanently +NOGRAVITY, +THRUACTORS, +ROLLSPRITE, +ROLLCENTER and +INTERPOLATEANGLES -- it hangs motionless in mid-air, you can walk straight through it, and nothing will ever put it back. Same outcome if both hands merely lock it at range first and then flick in sequence.

**Cause**

RS_Cone.Best skips only `held.IsHeld(a)` (line 76) -- it has no test for `pull.Flying`/`pull.Locked` on the other hand, so an object already in flight or already locked by hand 0 is a fully legal cone candidate for hand 1. RS_Pull.Lock's guards (:189-196) check only `flyActor[hand]` (this hand's) and RS_Held. RS_Pull.Start's guard is `if (!a || flyActor[hand]) return false;` (:309) -- again only THIS hand's slot; there is no per-actor 'already flying' test. So Start(1, a) captures flySavedSpecial/NoGrav/ThruActors and SaveTumble from the state hand 0's flight ALREADY imposed (NOGRAVITY true, THRUACTORS true, the three roll flags true). Whichever flight ends second calls Abort/Impact/Catch, which restores those captured-wrong values as if they were the object's originals. This is precisely the failure the flySaved* trio's own comment at :121-134 exists to prevent, defeated by a second concurrent owner rather than by ordering.

**Trigger**

rs_dgrab=true, rs_dgrab_flick=true, rs_flick_speed=2.5 m/s (defaults). Requires a second lock+flick on the same object inside the first flight's window -- 35 tics (1 s) for a 512-unit pull, up to 70 tics (2 s) at rs_dgrab_time_max.

**Verification**

I read E:\mERGE\RS_VR_Unified\zscript\hands\rs_distance.zs in full, plus rs_grab.zs:485-920, rs_grabpolicy.zs, rs_held.zs:85-120, rs_swing.zs:47-115 and CVARINFO.txt.

(a) Lines are accurate. rs_distance.zs:76 is `if (held && held.IsHeld(a)) continue;` and is the ONLY ownership filter in RS_Cone.Best. Lock (186-201) guards only flyActor[hand] (:189), held.HandIsFull(hand) (:191), held.IsHeld(a) (:196). Start's guard at :309 is verbatim `if (!a || flyActor[hand]) return false;` plus held.HandIsFull(hand) (:312) and held.IsHeld(a) (:315). No per-ACTOR "already in flight / already locked by the other hand" test exists anywhere in the file.

(c) Not guarded elsewhere. Every RS_Pull query in rs_grab.zs (GripSpokenFor :536, :615, :686, :782, :868) passes the loop's own `hand`. RS_Held.IsHeld (rs_held.zs:100-103) tests only hActor[0..1], which flight never populates, so a flying object is invisible to it. RS_GrabPolicy.Decide (rs_grabpolicy.zs:511-581) rejects on bNOINTERACTION, bMISSILE, a.player, zero radius/height, live monster â€” none of which flight sets â€” so an in-flight ExplosiveBarrel is a fully legal cone candidate (rule at :220, category 'Barrels', rs_grab_barrels default true). ValidateLock (:212-227) drops a lock only for a full hand or distance > reach*1.25; an inbound object gets CLOSER, so hand 1's lock survives hand 0's launch. Start nulls only lockActor[hand] (:332), so a co-lock on the other hand persists through the first launch. The holster/hardpoint stand-down (rs_grab.zs:743) is bypassed because GripSpokenFor is true once farTarget[1] or Locked(1) is set.

(d) The arithmetic/ordering works out. Start captures at :339-341, THEN sets bNOGRAVITY at :355 and bTHRUACTORS at :373, THEN SaveTumble/ArmTumble at :378 / :272-291 (tumble armed because rs_dgrab_tumble defaults 2.0, non-zero). So a second Start on the same actor reads NOGRAVITY=true, THRUACTORS=true, ROLLSPRITE/ROLLCENTER/INTERPOLATEANGLES=true as that actor's "originals". Every exit for the second flight â€” Abort (:465-468), Impact (:645-654), Catch (:404-410) â€” writes those poisoned values back. ExplosiveBarrel ships with all five flags false, so the object is left +NOGRAVITY +THRUACTORS +ROLLSPRITE +ROLLCENTER +INTERPOLATEANGLES with Vel zeroed: it floats where the arc ended (right in front of the player) and is walk-through. Nothing restores it â€” RS_GrabPolicy's sweep (ApplyOne :299-336) only touches bSPECIAL and only on Inventory actors, and a barrel is not Inventory. If the second flight ends in Catch instead, RS_Held.Take records the poisoned values as originals and re-applies them on release, which is exactly the failure the comment at :121-134 describes.

(b) Defaults verified in CVARINFO.txt: rs_dgrab=true (:268), rs_dgrab_flick=true (:329), rs_flick_speed=2.5 (:334), rs_dgrab_reach=512 (:274), rs_dgrab_spread=12 (:276), rs_dgrab_speed=15 (:282), rs_dgrab_time_min/max=6/70 (:285-286), rs_dgrab_tumble=2.0 (:318). RS_Swing.MetresPerSecToUnitsPerTic is m*34/35 (rs_swing.zs:51-54), so 15 m/s = 14.571 u/tic and a 512-unit pull is clamp(35.1, 6, 70) = 35 tics = 1.0 s. The reporter's flight-window figure is correct.

(e) Player-observable, and the repro is easier than the "catch it in flight" framing suggests: nothing prevents BOTH hands from locking the same stationary object at range (two independent Lock calls, rs_grab.zs:786-788), and ExplosiveBarrel is the one class in the table marked twohand=true, so pointing both hands at a barrel and yanking with both is the natural thing a player tries. If both grips open on the same tic, hand 0's Start runs first in the `for (hand = 0; hand < 2; hand++)` loop at rs_grab.zs:654 and hand 1's Start captures the poisoned flags in the same tic. I could not find any check that stops this.

**Correction (supersedes Cause/Trigger above)**

Confirmed, with two wording fixes. (1) The primary repro is not "flick, then catch it in flight with the other hand" â€” it is the second path the report mentions almost in passing: lock the same stationary object with BOTH hands (nothing in Lock or RS_Cone.Best prevents two hands locking one actor), then open both grips on a pull-back. Start(0) sets the flags and Start(1), in the same tic of the rs_grab.zs:654 loop, captures them as the object's originals. That needs no mid-flight tracking and no 1-second window. (2) "It jitters between two homing paths" is overstated: both arcs write the actor each tic, but hand 1's TryMove runs last and PrevPos is snapshotted before WorldTick, so the render interpolates smoothly along hand 1's arc. The visible defect is not the flight, it is the ending: the object is left floating in mid-air, walk-through (+THRUACTORS), and â€” when the second Start happened mid-flight rather than same-tic â€” permanently cocked at whatever roll it had at that instant, because flySavedRoll[1] captured a tumble angle rather than the original. Also, flySavedSpecial is captured correctly in both cases (flight deliberately never touches bSPECIAL, rs_distance.zs:343-355), so SPECIAL is not among the corrupted flags; the other five are.

---

### 6. Switching rs_grab off strands a distance lock lit and beamed for the rest of the level, and lets an in-flight object still hit you

**File:** `E:\mERGE\RS_VR_Unified\zscript\hands\rs_distance.zs`  
**Line:** 482-493 (RS_Pull.WorldTick gate)  
**Severity:** `broken-in-edge-case`

**Symptom**

Grip-lock something at range, open the menu and switch Hand Grab off. The object keeps pulsing orange/green and a green 'reeling' beam stays drawn from it to your palm for the rest of the level, with no input able to clear it -- the grip no longer does anything because RS_GrabHandler has returned early. If something was in flight when you flipped the switch, it finishes its arc and Impacts you for 5 damage with the whole grab system supposedly off.

**Cause**

RS_Pull.WorldTick gates only on `pmo.Health <= 0 || !RS_Reach.Flag("rs_dgrab", ...)` (line 488). It never reads rs_grab. RS_GrabHandler (rs_grab.zs:576-581) and RS_Held (rs_held.zs:436) both DO gate on rs_grab and both bail, so nothing is left that can call Unlock or Catch. ValidateLock (:212-227) only drops a lock when the hand fills or the object exceeds rs_dgrab_reach*1.25 = 640 units. RS_GrabViz.MarkConsidered reads `pull.Locked(h)` and DrawAimBeams checks only rs_dgrab_beam/rs_dgrab, so both keep painting it. This is the same fault class rs_grab.zs:559-575 and rs_held.zs:430-436 already document for GrabClaim* and for held objects; RS_Pull's lock was not included.

**Trigger**

rs_grab toggled off from the menu (a menu switch, the one control reachable from inside a headset) while pull.Locked or pull.Flying is non-null on either hand. Clears only on level change (WorldLoaded -> AbortAll) or by walking 640 units away.

**Verification**

I verified every cited line and every escape hatch. The claim is confirmed.

(a) Lines say what is claimed.
- E:\mERGE\RS_VR_Unified\zscript\hands\rs_distance.zs:488 is exactly `if (pmo.Health <= 0 || !RS_Reach.Flag("rs_dgrab", p, true))`. No read of `rs_grab` appears anywhere in rs_distance.zs (grep for `rs_grab"` across the tree returns only rs_grab.zs:576 and rs_held.zs:436).
- rs_grab.zs:576-581 early-returns on `!Flag("rs_grab")` after clearing GrabClaim*, before `let pull = RS_Pull.Get()` at :594 â€” so no pull code runs at all.
- rs_held.zs:436 `if (!Flag("rs_grab", p, true)) { ReleaseAll(); ClearClaims(pmo); return; }`. ReleaseAll (rs_held.zs:271-275) touches only its own slots; it never calls into RS_Pull.
- ValidateLock is rs_distance.zs:212-227 and drops a lock only on `held.HandIsFull(hand)` or distance > `reach * 1.25`.
- RS_GrabViz.MarkConsidered reads `pull.Locked(h)` at rs_grabviz.zs:307 and paints the orange/green lock pulse at :376. DrawAimBeams gates only on `rs_dgrab_beam` and `rs_dgrab` (rs_grabviz.zs:407-408), reads `pull.Locked(h)` at :477, and draws the reversed "reeling" beam at :507. Neither RS_GrabViz.WorldTick nor either helper ever reads `rs_grab`.

(b) Defaults correct. CVARINFO.txt: `rs_grab = true` (:112, exposed as MENUDEF.txt:177 "Grabbing (master)"), `rs_dgrab = true` (:268), `rs_dgrab_reach = 512.0` (:274) so `reach*1.25 = 640`, `rs_dgrab_beam = true` (:339), `rs_dgrab_beam_reel = true` (:463), `rs_grab_lightup = true` (:351), `rs_beam_lock_color = "50 ff 70"` (:444, the green), `rs_dgrab_impact = 5.0` (:360). RS_Reach.Flag (handworld.zs:179-183) reads the real cvar. All handlers including RS_Pull are registered (MAPINFO.txt:82).

(c) Not guarded elsewhere. Grepping the whole tree, the only callers of `pull.Unlock` / `AbortAll` are inside rs_distance.zs itself (ValidateLock, the rs_dgrab gate, WorldLoaded/WorldUnloaded) and rs_grab.zs:830 â€” which sits below the rs_grab early return and is therefore dead while the toggle is off. Since rs_held.zs:436 has just emptied both hands, `HandIsFull` is false, so ValidateLock's only remaining out is the 640-unit distance.

(d) Arithmetic works out. Lock survives; MarkConsidered's branch order puts `pull.Locked(h)` above `gh.TargetFor(h)` (which is null anyway, cleared at rs_grab.zs:549-553), so the object pulses green/orange forever. DrawAimBeams' `if (!gh) return` passes â€” the handler object still exists, it merely bailed out of its own tick â€” so the green beam keeps drawing objectâ†’palm. For the in-flight half, RS_Pull.WorldTick keeps driving the arc, RS_GrabHandler can no longer call Catch, so `t >= 1.0` reaches Impact (rs_distance.zs:637, 642-678) and `pmo.DamageMobj(..., 5, 'Crush', ...)`.

(e) Player-observable, and easier to hit than "in-flight" suggests: the playsim pauses while the menu is open (the codebase states this itself at rs_grabviz.zs:34-36), so a flying object hangs frozen mid-air for as long as you are in the menu and resumes into your face when you close it. There is a third visible symptom the reporter did not list: rs_hands.zs:481-482 forces POSE_FIST while `pl.Locked(hnd)`, so the hand is also stuck clenched.

This is the same discipline gap the code already documents at rs_grab.zs:559-575 and rs_held.zs:430-436 for GrabClaim* and for held objects; RS_Pull's lock was simply not included.

**Correction (supersedes Cause/Trigger above)**

The finding stands; one clause is overstated. "Clears only on level change or by walking 640 units away" omits three other exits I found: dying (rs_distance.zs:488 `pmo.Health <= 0` â†’ AbortAll), toggling rs_dgrab off (same line), and turning rs_grab back ON â€” because wasGrip[] is frozen true by the early return, the first tic after re-enabling sees `release == true` and rs_grab.zs:803-830 fires `pull.Unlock`. So the state is escapable, but only by re-enabling the feature you just switched off, dying, or a second unrelated toggle; none of that is discoverable, and while the switch is off the claim's "no input can clear it" is accurate.

---

### 7. Throwing or flicking with one hand de-compensates the OTHER hand's turn baseline for a tic

**RESOLVED** -- `turnPrimed` is cleared only in `ForgetAll` (rs_swing.zs:180); the per-hand `Forget` no longer touches the shared baseline, so the other hand keeps its turn compensation.

**File:** `E:\mERGE\RS_VR_Unified\zscript\hands\rs_swing.zs`  
**Line:** 96-109 (Forget; the offending line is 104 `turnPrimed = false;`)  
**Severity:** `broken-in-edge-case`

**Symptom**

Throw or flick with one hand and snap-turn on the same tic, and the other hand records a phantom velocity of roughly 24 m/s. Because PeakVelocity takes the MAXIMUM over the 7-tic window, that fiction survives for 0.2 s: for that window the other hand throws whatever it is holding across the map at absurd speed, and any release with a lock standing reads as a flick and fires a pull you did not ask for.

**Cause**

Forget(hand) is per-hand for the sample ring but clears the SHARED turn baseline `turnPrimed` (line 104). WorldTick's compensation is `if (turnPrimed) dTurn = turn - lastTurn;` -- so on the tic Forget ran, dTurn is forced to 0 and `if (dTurn != 0)` (line 174) skips rotating lastPalm for BOTH hands. The hand that called Forget is protected by its own `primed[h] == false` skip (lines 164-169); the other hand is not, and records the full uncompensated arc. With vr_snapTurn at 45 degrees and a palm ~30 units from the pawn origin that is 30 * 0.785 = 23.6 units/tic = 24 m/s, against rs_throw_min 1.2 m/s and rs_flick_speed 2.5 m/s. The justification in the comment ("keeping a stale lastTurn means the next tic computes a delta against a number from before the reset") does not apply to the per-hand call: lastTurn is rewritten unconditionally every tic at line 148, so it is never stale. Only the ForgetAll paths (WorldLoaded/WorldUnloaded) need the baseline dropped, and they get it from Forget(0)+Forget(1) anyway. Callers that hit this: rs_grab.zs:823 (after a flick) and rs_held.zs:262 (after a throw).

**Trigger**

Defaults. A flick or a throw on one hand in the same tic as a snap turn, with something held or locked in the other hand. Magnitude scales with turn rate -- a snap turn is the worst case; analog turning at 90 deg/s gives ~1.4 m/s, which still clears rs_throw_min.

**Verification**

I read E:\mERGE\RS_VR_Unified\zscript\hands\rs_swing.zs in full, plus rs_grab.zs (Centre at 201, Cone.Dir, the flick block at 802-834), rs_held.zs (Release at 223-269), rs_throw.zs (VelocityFor), and CVARINFO.txt. Every load-bearing element of the claim checks out.

(a) LINES SAY WHAT IS CLAIMED. rs_swing.zs:96-109 Forget(int hand): line 98 rejects hand != 0/1, line 104 is exactly `turnPrimed = false;`, lines 105-108 clear head/filled/primed/delta for that hand ONLY. `turnPrimed` (line 35) and `lastTurn` (line 34) are scalars, not per-hand arrays -- confirmed by the declarations. WorldTick line 147 `if (turnPrimed) dTurn = turn - lastTurn;`, line 148 `lastTurn = turn;` (unconditional, so the reporter is right that lastTurn is never stale on the per-hand path), line 149 `turnPrimed = true;`. Lines 164-169 are the `if (!primed[h]) { lastPalm[h] = palm; primed[h] = true; continue; }` skip that protects only the calling hand. Line 174 `if (dTurn != 0)` gates the yaw rotation of lastPalm at 176-179. So with dTurn forced to 0, the OTHER hand's lastPalm is not spun forward and line 182 `Vector3 d = palm - lastPalm[h];` captures the raw turn arc. Both cited callers are per-hand and confirmed: rs_grab.zs:823 `if (sw) sw.Forget(hand);` inside the successful-flick branch, rs_held.zs:262 `if (sw) sw.Forget(hand);` inside `if (v.Length() > 0)` after `a.Vel = v;`.

(b) DEFAULTS ARE CORRECT. CVARINFO.txt:334 rs_flick_speed = 2.5, :374 rs_throw_min = 1.2, :377 rs_throw_scale = 1.0, :368 rs_throw = true, :329 rs_dgrab_flick = true. All match. Samples are player-relative (line 162 `palm -= pmo.Pos;`) and Centre() returns a WORLD palm position (AttackPos/OffhandPos or the HANDPALM_joint bone), so it does rotate bodily with VRTurnYaw -- the compensation is genuinely load-bearing. That VRTurnYaw accumulates rather than being a per-frame delta is corroborated independently by RS_HardPoints.zs:951 and RS_Holsters.zs:792, which both compute `normalizeDeg(pawn.VRTurnYaw - lastTurnYaw[i])`.

(c) NOT GUARDED ANYWHERE. There is no speed clamp on the path: RS_Throw.VelocityFor (rs_throw.zs:34-51) returns `v * rs_throw_scale + pmo.Vel` with no ceiling, and rs_held.zs:260 writes it straight to `a.Vel`. Nothing in rs_held/rs_grab/rs_swing gates on VRTurnYaw. PeakVelocity (lines 59-72) takes the max over filled[] with no outlier rejection, so one phantom sample dominates the whole 7-tic window.

(d) ARITHMETIC WORKS OUT. The reporter used arc length (r*theta) where the code produces a chord (2r*sin(theta/2)); at 45 deg that is 0.785r vs 0.765r, a 2.6% overstatement -- immaterial. For a 45 deg snap at a conservative horizontal palm radius of 20-30 units: 15.3-23.0 units/tic = 15.7-23.6 m/s, against thresholds of 1.2 and 2.5 m/s. Even a 15 deg snap at r=20 gives 5.4 m/s, still clearing both. Centre() admits a palm up to 120 units from pmo.Pos, so the radius can be larger, not smaller.

(e) PLAYER-OBSERVABLE, with the caveats in the correction. The throw path has no directional gate at all: peak (phantom) >= 1.2 m/s wins the peak-vs-last selection at rs_throw.zs:43, and the object leaves at the phantom velocity. I could not find any path that suppresses it.

**Correction (supersedes Cause/Trigger above)**

The defect is real, but two details in the write-up should be tightened.

1. It is not "the same tic" -- it is the sample interval that follows the Forget. The phantom is recorded on the first WorldTick AFTER turnPrimed was cleared, so the turn must fall in the tic interval that WorldTick straddles, one tic offset from the Forget (which side depends on whether EventHandler.WorldTick runs before or after P_PlayerThink -- the bug exists either way, only the alignment differs). For a SNAP turn, which is a one-shot event, this is a 28.6 ms coincidence rather than a guaranteed one: if WorldTick already compensated the snap on the tic the release was pressed, the suppressed dTurn on the next tic is genuinely zero and nothing happens.

2. The reliable trigger is SMOOTH/analog turning, not snap. With the turn stick held, dTurn is non-zero on every tic, so the tic after any Forget is guaranteed uncompensated. At Doom's fast turn rate (~7 deg/tic) with r=25 units the phantom is 3.05 units/tic = 3.1 m/s, which clears BOTH rs_throw_min (1.2) and rs_flick_speed (2.5); at normal turn (~3.5 deg/tic) it is ~1.6 m/s, which clears rs_throw_min only. So the everyday symptom is "hold the turn stick, throw or flick with one hand, let go with the other within 0.2 s, and that object leaps a few metres instead of dropping" plus a spurious distance-pull -- not "across the map". The 20+ m/s across-the-map case needs the tighter snap-turn alignment.

3. The flick misfire is partially gated. rs_grab.zs:814-816 also requires `toward = -(v dot RS_Cone.Dir(pmo, hand)) > 0`. A turn-induced phantom is tangential, so whether it reads as "toward you" depends on hand geometry and turn direction -- roughly one of the two turn directions. The throw path (rs_held.zs:252-262) has no such gate and fires unconditionally.

---

### 8. Both hand debug traces ship on, printing to the player's view during ordinary play

**File:** `E:\mERGE\RS_VR_Unified\zscript\hands\rs_hands.zs`  
**Line:** 565-578 (the [HANDS] trace); defaults at CVARINFO.txt:23 and :222  
**Severity:** `broken-at-defaults`

**Symptom**

"[HANDS   ] MAIN grip=0 trigger=1 -> frame 9  READY (finger on trigger), thumb up" and similar scroll continuously in the notify area while holding any weapon, plus [RSGRIP]/[RSHELD]/[RSPULL]/[RSTAKE]/[RSTHROW]/[RSUSE] on every grab attempt. In a headset that is text floating in the middle of the view.

**Cause**

rs_hands_debug defaults to true (CVARINFO.txt:23) and rs_hold_debug defaults to true (CVARINFO.txt:222), while the sibling rs_handworld_debug defaults to false (CVARINFO.txt:106). The [HANDS] trace fires on any change of the selected pose, and PoseFor branches on the capacitive pads (`thumbDown`, `onTrigger`, rs_hands.zs:335-348) -- so merely resting and lifting your thumb on the stick or your index on the trigger flips POSE_POINT<->POSE_GRIP_TU and POSE_READY_TD<->POSE_READY_TU and prints, many times per second. It is not gated on a deliberate action.

**Trigger**

Defaults, holding any weapon in either hand. Console.Printf goes to the notify overlay, so it is on screen, not just in the log.

**Verification**

I could not refute this. All five checks pass, though two details of the symptom description are wrong and need correcting.

(a) Cited lines say what is claimed. E:\mERGE\RS_VR_Unified\zscript\hands\rs_hands.zs:565-578 is exactly the block described: `CVar cDbg = CVar.GetCVar("rs_hands_debug", player); if (cDbg != null && cDbg.GetBool())` guarding a `Console.Printf("[HANDS   ] %s grip=%s trigger=%s -> frame %d  %s", ...)`. The three-space padding after `[HANDS` and the PoseName strings quoted in the symptom both match (PoseName at rs_hands.zs:158-180; "READY (finger on trigger), thumb up" is line 170).

(b) Defaults are correct. E:\mERGE\RS_VR_Unified\CVARINFO.txt:23 `user bool rs_hands_debug = true;`, :222 `user bool rs_hold_debug = true;`, :106 `user bool rs_handworld_debug = false;`. I also extracted CVARINFO.txt from the shipped E:\mERGE\RS_VR_Unified\RS_VR_Unified.pk3 (built 11:29, newer than the loose file) and it carries the same three values, so this is what actually loads. The asymmetry is real and wider than the reporter noted: every other subsystem's trace ships off â€” rr_debug=false (:921), wr_debug=false (:1225), rs_handworld_debug=false (:106) â€” only these two ship on.

(c) Not guarded anywhere the reporter missed. I looked for every gate that could make the block unreachable at defaults: `rs_hands` defaults true (CVARINFO.txt:17) so the early `Clear`/return at rs_hands.zs:106-112 does not fire; RS_HandsAlwaysOn IS registered in MAPINFO.txt's AddEventHandlers list (first entry), so WorldTick runs every tic and calls Show for both hands (rs_hands.zs:133-140); and I read rs_hands.zs:420-564 â€” there is no early return between the pose computation and the debug block, only the forcepose/srcframe overrides (both default -1, so inert) and the blend. The only throttle is `if (pose != last)` at :570. rs_hold_debug is read through RS_Reach.Flag (rs_grab.zs:83), a plain `c ? c.GetBool() : d` with no master gate.

(d) The behaviour works out. PoseFor (rs_hands.zs:330-349) derives `thumbDown` from TOUCH_THUMB and `onTrigger` from TOUCH_INDEX off pawn.FingerTouchMain/Off, the capacitive-pad field. With a weapon held the three-way branch is trigger -> GRIPFIRE/FIRE_TU, onTrigger -> READY_TD/READY_TU, else POINT/GRIP_TU, so both a trigger press and a bare thumb/index contact change flip the pose and print. Each shot fired is at least two lines per hand (press and release). The rs_hold_debug prints are edge-gated, not per-tic â€” `press = grip && !wasGrip[hand]` at rs_grab.zs:668 â€” which matches the reporter's "on every grab attempt".

(e) Player-observable. Console.Printf is PRINT_HIGH, the same path GZDoom's own Inventory.PrintPickupMessage uses to put "Picked up a..." in the notify overlay, so this is text in the headset view, not log-only. Stated as reasoning from engine semantics, not observed: the two logs in the repo (doomxr-log.txt, log-debug.txt) are startup-only â€” both start and stop at 06:28:48 with no gameplay â€” so they contain no trace lines and are evidence in neither direction.

**Correction (supersedes Cause/Trigger above)**

The defect stands, but the symptom is overstated in two ways.

1. Rate. The [HANDS] trace is NOT a continuous per-tic scroll. rs_hands.zs:569-572 latches the last reported pose per hand in dbgMain/dbgOff and prints only when `pose != last`, so it is capped at one line per hand per pose CHANGE. A held trigger prints nothing (pose is constant while BT_ATTACK stays down), and a still hand prints nothing. The true rate is roughly two lines per hand per shot fired, plus one per thumb-on-stick or finger-on-trigger contact transition. That is still unprompted text appearing in the player's view during ordinary play, but "many times per second" and "scroll continuously" describe a mechanism that is not there.

2. The sample line is internally impossible. "[HANDS   ] MAIN grip=0 trigger=1 -> frame 9  READY (finger on trigger), thumb up" cannot be emitted: frame 9 is POSE_READY_TU, and PoseFor (rs_hands.zs:344-348) reaches READY_TU only on the `if (onTrigger)` branch, which is below `if (trigger) return thumbDown ? POSE_GRIPFIRE : POSE_FIRE_TU`. With trigger=1 the printed frame is 6 or 10, never 9. The quoted line is illustrative, not observed.

Corrected statement: rs_hands_debug (CVARINFO.txt:23) and rs_hold_debug (CVARINFO.txt:222) both ship enabled, out of step with every sibling diagnostic in the same file (rs_handworld_debug, rr_debug, wr_debug all false). At defaults the player sees a "[HANDS   ] ..." line in the notify overlay on every pose transition of either hand â€” each trigger pull and release, each time a thumb or index leaves or touches its capacitive pad â€” plus [RSGRIP]/[RSHELD]/[RSPULL]/[RSTAKE]/[RSTHROW]/[RSUSE] lines on grab-related edges. Fix is two words in CVARINFO.txt; both are already exposed as menu toggles (MENUDEF.txt:40 "Trace pose choice", MENUDEF.txt:379 "Log holding and grabbing"), so nothing is lost by defaulting them off. Note the file's own header warning at CVARINFO.txt:13-16 â€” a changed default will not take on any install where the value is already saved in the ini.

---

## Reload

### 9. Taking a level exit mid-carry jams the feeder hand's GripClaim at GRIPSUBJ_Magazine for the rest of the run

**RESOLVED 2026-08-30** -- `RR_Reload` now has `WorldUnloaded`/`WorldLoaded` that clear GripClaim* on every player, but only for the four subjects this package authors (Magazine, Shell, Round, Inserting). Same fix RS_Holsters used for its own travelling state.

**File:** `E:\mERGE\RS_VR_Unified\zscript\reload\rr_sequence.zs`  
**Line:** 94 (only override), 171 + 189 + 202 (Claim writes), 685-702 (Abort)  
**Severity:** `broken-at-defaults`

**Symptom**

Cross an exit line / hit an exit switch while a magazine is in the feeder hand and that hand is broken for the remainder of the game. On the next map: (a) the hand is posed permanently as POSE_HOLD_MAG -- fingers wrapped round nothing, because P_SetupPsprites destroyed the mag mesh at level start; (b) that hand can NEVER start another reload, ever; (c) the ammo pouch is dead for that hand; (d) reaching into the pouch with it swaps its weapon out for a fist and never gives the weapon back; (e) the dominant-grip modifier layer / stabilize stay stood down whenever that hand grips. Loading a savegame is the only cure, and nothing tells the player that.

**Cause**

RR_Reload overrides WorldTick and NOTHING else -- grep confirms line 94 is the only `override` in the file. It is a per-level EventHandler (MAPINFO AddEventHandlers -> EventManager::InitStaticHandlers(l, map=true), events.cpp:594-624), so it is destroyed and rebuilt on every map with `claimed` and `phase` back at zero. Abort() -- the only thing that clears GripClaim -- runs only from Release() (grip let go) or the health<1 branch, never on unload. Meanwhile pmo.GripClaimMain/Off is a native AActor int (actor.h:1878) that is NOT in AActor::Serialize and is never written by the engine (vk_openxrdevice.cpp:3625 only reads it), so it rides the travelling pawn to the next map still holding GRIPSUBJ_Magazine(4) / _Shell(2) / _Round(1) / _Inserting(3). The fresh RR_Reload then has `claimed == GRIPSUBJ_None`, so Abort's guard at line 688 `if (pmo && claimed != GRIPSUBJ_None)` can never fire. RS_Holsters cannot clean it either: its fresh instance has pouchClaimedMain/Off == false so the clear branch at RS_Holsters.zs:1339 `else if (!nowInPouch && claimedByUs)` is unreachable, its set branch at :1334 requires `curClaim == GRIPSUBJ_None`, and releasePlayer deliberately refuses to touch GripClaim (RS_Holsters.zs:615-621, "the claim protocol itself is the grip arbiter's, not this pass's"). The engine then reports GripSubject = claimed unconditionally (vk_openxrdevice.cpp: `if (claimed > 0) subj = claimed;`), so RR_Reload.InPouch (rr_sequence.zs:624-628, tests GripSubject == GRIPSUBJ_Pouch) is false forever for that hand, and RS_Holsters' fist-restore branch (:1408 `else if (!handClaimed && prev != null)`) can never run because handClaimed = (liveClaim != None) is permanently true. This is the exact bug RS_Holsters already found and fixed for bHolsterHidden -- see its own note at RS_Holsters.zs:460-471, "Every weapon you were carrying in a holster when you took the exit was permanently, silently bricked" -- which it fixed by adding WorldUnloaded (:527). rs_held.zs:498-517 documents the same failure mode for its own claims. RR_Reload is the one writer of GripClaim* in the tree with no unload path.

**Trigger**

AT DEFAULTS. phase == RR_CARRY (grip held on ammunition drawn from the pouch) at the moment the map changes -- an exit line, an exit switch, a teleport-to-exit, or `changemap`/`idclev` from the console. No cvar involved; rr_magazines is irrelevant because the claim is set by Begin() regardless.

**Verification**

CONFIRMED â€” I could not refute this. Every cited line says what the reporter claims, and the engine side checks out too.

(a) Cited lines are accurate. rr_sequence.zs:94 `override void WorldTick()` is the only `override` in the file (grep confirmed). Claim() at :678-683 writes GripClaimMain/Off, called from :171 (Begin), :189 and :202 (every carry tic). Abort() at :685-702 has the guard `if (pmo && claimed != GRIPSUBJ_None)` at :688 and is reachable only from Release() (:240) and the health<1 branch (:107). No WorldUnloaded, no WorldLoaded, no PlayerDied, no OnUnregister. MAPINFO.txt:82 registers RR_Reload via AddEventHandlers, so it is per-level (the file's own comment at :513 says so).

(b) Engine facts verified in E:\UZDXREMA, not taken on trust. `int GripClaimMain; int GripClaimOff;` at src/playsim/actor.h:1878-1879. A tree-wide grep for GripClaimMain returns exactly five hits: the actor.h declaration, DEFINE_FIELD in vmthunks_actors.cpp:2258, the ZScript native declaration in actor.zs:482, a comment in constants.zs:1620, and the single READ at vk_openxrdevice.cpp:3625. The engine never writes it. It does not appear in p_mobj.cpp at all, so it is not in AActor::Serialize. vk_openxrdevice.cpp:3820 is literally `if (claimed > 0) subj = claimed;` and :3845 publishes that into GripSubjectMain/Off â€” so the arbitrated subject is pinned to the stale claim.

Travel really does preserve the same AActor: FLevelLocals::StartTravel (g_level.cpp:1683) adds living players to the travelling list, and RemoveTravellingObjects (:1762+) re-links the travelling `mo`, sets `mo->player->mo = mo`, and destroys the map-spawned mapDoll. The pawn object is not rebuilt, so native ints ride across unchanged. Psprites are separately destroyed at level entry (p_mobj.cpp:6499-6501 -> p_pspr.cpp:1464 P_SetupPsprites -> DestroyPSprites), so the RR_Ammo layer at 900010/1900010 (rr_ammo.zs:122-123) is gone on the new map. Hand posed round nothing: confirmed.

(c) Not guarded anywhere. RS_Holsters.zs:1334 set-branch requires `curClaim == GRIPSUBJ_None` â€” false. :1339 clear-branch requires `claimedByUs`, which is false on a fresh per-level handler. releasePlayer (:615-621) explicitly refuses to touch GripClaim. WorldUnloaded (:527) and WorldLoaded (:536) only handle bHolsterHidden/contents/pouchPrevious. rs_held.zs ClearClaims (:517-537) skips any hand whose hClaimed is None, which a fresh handler's always is. No other file writes GripClaim*.

(d) The consequences work out. RR_Reload.InPouch (rr_sequence.zs:624-628) tests GripSubject == GRIPSUBJ_Pouch, and GripSubject is now pinned to Magazine(4)/Shell(2)/Round(1)/Inserting(3) â€” so Watch() can never start a reload with that hand, and RS_Holsters can never take the pouch claim. RS_Hands.PoseForSubject (rs_hands.zs:299-328) maps GRIPSUBJ_Magazine -> POSE_HOLD_MAG and its result OVERRIDES the button pose at :428-430; only GRIPSUBJ_Support is suppressed when the hand holds a weapon, so the wrong pose really does stick. Engine `objectHere` (vk_openxrdevice.cpp:3646) is `((claimed > 0) && !supporting) || grabHere`, and at :3729 that sets GRIPCTX_Object instead of the dominant-grip modifier layer â€” symptom (e) confirmed.

(e) Player-observable, at defaults, no cvar involved. Trigger is realistic: hold grip on ammo drawn from the pouch and cross an exit line or hit an exit switch.

TWO CORRECTIONS to the report, neither of which rescues it:
1. The weapon is NOT swapped for a fist at map start. RS_Holsters.zs:1390-1392 gates ENTRY on `pouchInvolved = nowInPouch || claimedByUs`, and both are false on a fresh map, so the :1392 branch does not fire until the hand next enters the pouch. Symptom (d) as worded ("reaching into the pouch with it swaps its weapon out and never gives it back") is exactly right; the implied "your gun is gone the moment you spawn" is not.
2. "Loading a savegame is the only cure" is wrong. Dying and respawning produces a brand-new pawn whose GripClaim* default to 0, and grabbing-then-releasing any world object with that hand overwrites the field via rs_held.zs:484-486 and then clears it in ClearClaims (:527-532) â€” rs_grab defaults to true (CVARINFO.txt:112). So the brick is persistent but self-heals on the first pickup with that hand, which softens "for the remainder of the game" to "until that hand next grabs something, dies, or reloads a save".

**Correction (supersedes Cause/Trigger above)**

Confirmed as reported, with two factual corrections to the symptom list. (1) The weapon is not taken at map start: RS_Holsters.zs:1390-1392 gates the fist swap's ENTRY on `pouchInvolved = nowInPouch || claimedByUs`, both false on a fresh map â€” the swap only fires when the bricked hand next enters the pouch, and only then is the weapon never returned (the :1408 restore needs !handClaimed, which the stale claim keeps false forever). (2) A savegame is not the only cure: dying and respawning yields a new pawn with GripClaim* at 0, and grabbing then releasing any world object with that hand clears it through rs_held.zs:484-486 plus ClearClaims (:527-532), with rs_grab defaulting to true (CVARINFO.txt:112). The correct severity statement is: after taking an exit mid-carry, that hand is posed POSE_HOLD_MAG round nothing, cannot start another reload, cannot claim the pouch, loses its grip-modifier layer, and loses its weapon permanently if it enters the pouch â€” until the player picks something up with it, dies, or loads a save, none of which is signalled.

---

### 10. The RETURNED exit is unreachable after any movement -- putting the magazine back in the pouch plays the DROP sound

**RESOLVED 2026-08-30** -- `pouchAt` is stored as an offset from the pawn plus the yaw it was taken at, and rebuilt against the live position each test, so the sphere travels and turns with the body instead of staying where the player used to be.

**File:** `E:\mERGE\RS_VR_Unified\zscript\reload\rr_sequence.zs`  
**Line:** 163 (pouchAt captured), 635-641 (InPouchGeom / POUCH_R), 207 + 212-236 (Release)  
**Severity:** `broken-in-common-case`

**Symptom**

One of the contract's four named exits is effectively dead. Walk anywhere while carrying a magazine, then put it back in the chest pouch and release -- you get "rr/drop" (DSBDCLOS) and a 0.3/30ms haptic instead of "rr/stow" (DSSWTCHN) and 0.4/40ms, and with rr_debug on the console prints "[RR] dropped" instead of "[RR] returned to pouch". The gesture reads as having fumbled the magazine onto the floor when the player deliberately stowed it.

**Cause**

Begin() stores `pouchAt = RR_Point.HandPos(pmo, h)` (line 163) -- a WORLD-space position, captured once. InPouchGeom (line 637) then tests `(HandPos(pmo, hand) - pouchAt).Length() <= POUCH_R` with POUCH_R = 3.5 map units. But the pouch is a BODY-RELATIVE anchor (RS_Holsters.zs:172, AmmoPouch hsFwd -1.0, hsSide 0.0, hsFrac 0.66) that travels with the player, while pouchAt does not. Doing the arithmetic: 3.5 map units is ~10cm at this fork's 34 units/metre, and a running Doom player covers roughly 16 map units per tic -- so a single tic of movement puts the hand permanently outside the stale sphere, and Release() is called with inPouch == false for the rest of the carry. Second-order error on top: pouchAt is the HAND's position at claim time, and RS_Holsters lets a hand claim the pouch anywhere within hsRadius 3.5 of the true anchor, so even standing perfectly still the tested sphere can be offset by up to 3.5 units from the pouch it is meant to represent. No ammunition is at stake (the debit is at Seat only, and both DROPPED and RETURNED just call Abort), so the damage is confined to the wrong audio/haptic feedback on a documented exit.

**Trigger**

AT DEFAULTS. Any player movement -- walking, running, strafing -- between gripping the magazine in the pouch and releasing it back there. Only a completely stationary player ever gets the RETURNED branch.

**Verification**

CONFIRMED. I read rr_sequence.zs, rr_point.zs, RS_Holsters.zs, CVARINFO.txt and SNDINFO.txt independently and every one of the five checks passes.

(a) The cited lines say exactly what is claimed. rr_sequence.zs:163 is `pouchAt = RR_Point.HandPos(pmo, h);` inside Begin(). Lines 635-641 are `return (RR_Point.HandPos(pmo, hand) - pouchAt).Length() <= POUCH_R;` with `private Vector3 pouchAt;` and `const POUCH_R = 3.5;   // matches RS_Holsters' AmmoPouch hsRadius`. Line 207 is `Release(p, pmo, onWell, InPouchGeom(pmo, feeder));`. Lines 225-227 (rr/stow, VRHaptic 0.4/40, "[RR] returned to pouch") and 233-235 (rr/drop, VRHaptic 0.3/30, "[RR] dropped") match.

(b) The values are correct. RS_Holsters.zs:172 AmmoPouch hsFwd=-1.0, hsSide=0.0, hsFrac=0.66, hsRadius=3.5. CVARINFO.txt:615 `user bool rs_holster_pouch_enabled = true` so the pouch is live at defaults and the gesture is reachable. SNDINFO.txt:74-75 map rr/stow to DSSWTCHN and rr/drop to DSBDCLOS -- genuinely different sounds.

The load-bearing premise -- that HandPos is WORLD space while the pouch anchor is BODY-relative -- is confirmed two independent ways. RR_Point.HandPos (rr_point.zs:71-74) returns pmo.AttackPos/OffhandPos. RS_Holsters.zs:823-846 anchorPos() builds the pouch anchor as `pawn.HmdPos.X + edFwd*fx + edSide*rx, ..., floorZ + eyeHeight*edFrac` -- an absolute world point RECOMPUTED EVERY TIC -- and :1252 subtracts pawn.AttackPos from it directly (`(pawn.AttackPos - anchor).Length() < mainR`). If AttackPos were pawn-relative the whole holster claim system would be broken, and per project notes holsters are confirmed working in headset. Second confirmation: rr_point.zs:159 Mark() does `level.Vec3Diff(pmo.Pos, world)` to turn a HandPos-derived point into a particle offset, which is only meaningful if world is absolute.

(c) It is not guarded, clamped or handled anywhere. `grep -rn "pouchAt"` over the entire repo returns exactly three hits: the declaration (:640), the single write (:163) and the single read (:637). It is never refreshed during Carry(). Carry() has no timeout and no movement-based abort -- its only mid-carry exit is the gun hand's weapon changing (:187), which itself routes to `Release(p, pmo, false, false)` i.e. DROPPED. Nothing in RS_Holsters touches it (it does not export the anchor at all, which is what the :630-634 comment is apologising for).

(d) The arithmetic works out. POUCH_R is 3.5 map units in the same coordinate space as AttackPos. Doom run speed is ~16 map units/tic and walk ~8/tic, so well under a quarter-second of locomotion moves the body-relative pouch further than 3.5 units from the frozen capture point, and Release() then sees inPouch == false.

(e) Player-observable: DSSWTCHN vs DSBDCLOS is an audible difference, plus the haptic amplitude/duration differs and the rr_debug console line differs. The damage is confined to feedback -- both branches fall through to Abort() and the ammo debit is at Seat only -- but a named contract exit producing the wrong audio is exactly a wrong result the player perceives.

Three small corrections, none of which change the verdict: (1) the scale figure is off -- RS_Holsters' own comment calls hsRadius 3.5 "a 7\" catch volume", i.e. ~1 map unit per inch (~39/m), so 3.5 units is ~9cm rather than the claim's 34 units/m; (2) the stationary offset is up to 4.9 units, not 3.5 -- updateClaims (:1206-1215) holds a claimed holster out to hsRadius * CLAIM_HYSTERESIS (const = 1.4, :364), and nowInPouch (:1329) reads that hysteresis-held claim, so Begin() can fire with the hand up to 4.9 units from the true anchor; (3) "permanently outside" is slightly overstated -- if the player walks back to the same world spot the exit works again -- the accurate statement is that the test is on net world displacement from the capture point, not on movement having occurred.

**Correction (supersedes Cause/Trigger above)**

Corrected claim: InPouchGeom (rr_sequence.zs:635-641) tests the feeder hand against `pouchAt`, a WORLD-space hand position frozen at Begin() (:163), with POUCH_R = 3.5 map units, while the pouch it represents is a body-relative anchor (RS_Holsters.zs:172, recomputed live in anchorPos() :823-846). Whenever the player's NET world displacement from the capture point exceeds ~3.5 units -- under a quarter-second of walking at Doom's ~8-16 units/tic -- Release() (:207, 212-236) takes the DROPPED branch instead of RETURNED, so stowing the magazine plays rr/drop (DSBDCLOS) with a 0.3/30 haptic instead of rr/stow (DSSWTCHN) with 0.4/40, and rr_debug prints "[RR] dropped". Two refinements to the original report: the scale is ~1 map unit per inch by RS_Holsters' own comment (3.5 units is ~9cm, not the claimed 34 units/metre), and the standing-still offset error is up to 4.9 units rather than 3.5, because updateClaims holds a pouch claim out to hsRadius * CLAIM_HYSTERESIS (1.4, RS_Holsters.zs:364, :1206-1215) and nowInPouch (:1329) reads that widened claim, so Begin() can capture pouchAt that far from the true anchor. The failure is not literally permanent -- returning to the same world spot restores the exit -- but it is the common case in play. Impact is feedback-only: both branches fall through to Abort() and the ammo debit is at Seat only, so no ammunition or state is corrupted.

---

### 11. Releasing ammunition without leaving the pouch locks that hand out of the next draw until it exits and re-enters the pouch volume

**RESOLVED 2026-08-30** -- RS_Holsters' pouch-renewal branch now re-asserts `GRIPSUBJ_Pouch` whenever the field has fallen to None while the hand is still inside and we still believe we own it. Repaired in the claim's owner rather than by asking the other mod not to clear it; only ever taken from None, so nobody else's claim is stolen.

**File:** `E:\mERGE\RS_VR_Unified\zscript\reload\rr_sequence.zs`  
**Line:** 240 (Abort in Release), 624-628 (InPouch)  
**Severity:** `broken-in-common-case`

**Symptom**

Draw a magazine, change your mind, let go while your hand is still in your chest pouch -- and gripping again does nothing. The hand has to be pulled clear of the pouch's 10cm sphere and put back before a second magazine can be drawn, with no feedback explaining why the first attempt was ignored.

**Cause**

Release() -> Abort() writes GripClaim* = GRIPSUBJ_None (rr_sequence.zs:693-694) while the hand is physically still inside the pouch. RS_Holsters only re-asserts GRIPSUBJ_Pouch on the entry EDGE -- `if (nowInPouch && !claimedByUs && curClaim == GRIPSUBJ_None)` (RS_Holsters.zs:1334) -- and pouchClaimedMain/Off stays true until the hand LEAVES (the clear branch at :1339 requires !nowInPouch). So claimedByUs is true, the re-claim is skipped, and GripClaim stays None. The engine then falls through to `else if (holsterHere) subj = GRIPSUBJ_Holster;` (vk_openxrdevice.cpp), publishing GRIPSUBJ_Holster (10) rather than GRIPSUBJ_Pouch (11), and RR_Reload.Watch's `if (!InPouch(pmo, h)) continue;` (line 133) rejects the hand. The 10-tic `guard` debounce masks the first ~0.3s of this, which is why it reads as sluggishness rather than as a lockout. The normal carry-to-gun loop is unaffected because that hand leaves the pouch on its way to the magwell.

**Trigger**

AT DEFAULTS. Any release of the grip while the feeder hand is still inside the pouch -- i.e. exactly the RETURNED exit the design names, plus any accidental grip slip during the draw.

**Verification**

I read all four sources independently and the mechanism holds.

(a) Cited lines say what is claimed. rr_sequence.zs:212-241 Release() ends every exit â€” including the in-pouch RETURNED branch at :218-228 â€” with `Abort(pmo); guard = 10;`. Abort (:686-699) writes GripClaimMain/Off = GRIPSUBJ_None at :693-694. InPouch() at :624-628 is exactly `int s = (hand==0)?pmo.GripSubjectMain:pmo.GripSubjectOff; return s == GRIPSUBJ_Pouch;`. Watch() gates on it at :134 (`if (!InPouch(pmo, h)) continue;`) â€” reporter said 133, off by one.

(b) Holster side confirmed. RS_Holsters.zs:1334 is literally `if (nowInPouch && !claimedByUs && curClaim == GRIPSUBJ_None)`, setting GripClaim*=GRIPSUBJ_Pouch and pouchClaimed*=true at :1336-1337. The only clear of pouchClaimed* outside respawn (:631-632) is the `else if (!nowInPouch && claimedByUs)` branch at :1339-1353. With the hand still inside, claimedByUs stays true and neither branch runs, so GripClaim stays None. Nothing else in the tree re-asserts GRIPSUBJ_Pouch (grepped GripClaimMain/Off across all of zscript/: only rs_held.zs:484-485/527-531 for grabbed actors, RS_Holsters :1336-1351, rr_sequence :680-694).

(c) Engine fallback confirmed in the real source. vk_openxrdevice.cpp:3820-3831: `int subj = GRIPSUBJ_None; if (claimed > 0) subj = claimed; else if (holsterHere) subj = GRIPSUBJ_Holster;` with holsterHere = HolsterClaimMain/Off (:3618-3619) and claimed = GripClaimMain/Off (:3624). GRIPSUBJ_Holster=10, GRIPSUBJ_Pouch=11 (constants.zs:1655-1668). The pouch counts as a holster for HolsterClaim: AMMO_POUCH_IDX=8, HOLSTER_COUNT=9 (RS_Holsters.zs:28,36), and updateClaims' scan (:1229-1272) sets mainClaimed/offClaimed for index 8 on proximity alone every tic (called unconditionally from WorldTick at :442). So the hand publishes subject 10, never 11, and InPouch() rejects it. Even if holsterHere were false the subject would be None â€” still not Pouch.

(d) Defaults check out: rs_holster_pouch_enabled = true (CVARINFO.txt:615); pouch hsRadius = 3.5 (RS_Holsters.zs:172) matching POUCH_R = 3.5 (rr_sequence.zs:641); CLAIM_HYSTERESIS = 1.4 (:364), so the hand must move 4.9 units off the sternum anchor to clear nowInPouch; guard = 10 tics = 0.29 s, which does mask the first fraction of a second. Recovery is exactly as described: exit (pouchClaimed* -> false; the GripClaim write is skipped because the standing value is None, not Pouch), re-enter (all three conditions of :1334 now hold), claim restored.

(e) Player-observable: yes. Grip in the pouch, release in place, grip again â€” no draw sound, no haptic, no RR_Ammo model, and no console line even with rr_debug on, because Watch() `continue`s before Begin.

One further corroborating detail the reporter did not mention: because InPouchGeom measures from pouchAt (the hand's position at Begin, itself up to 3.5 units off the anchor) with R=3.5 while RS_Holsters measures from the anchor with R=3.5/4.9, a release can score as DROPPED ("rr/drop") and still be inside RS_Holsters' proximity, so the lockout is not limited to releases that sound like a return.

**Correction (supersedes Cause/Trigger above)**

The defect is real but the TRIGGER is narrower than reported. It is NOT "exactly the RETURNED exit the design names." In a normal carry the hand leaves the pouch on the way to the magwell; that exit runs RS_Holsters.zs:1339's branch, which skips the GripClaim write (the standing value is GRIPSUBJ_Magazine, not Pouch) but does set pouchClaimedMain/Off = false. Carrying the magazine back into the pouch then fails :1334 on `curClaim == GRIPSUBJ_None` (it is Magazine), so the flag stays false. When Release -> Abort clears the claim to None, the very next tic satisfies all three conditions at :1334 and re-claims GRIPSUBJ_Pouch. The ordinary carry-out-and-return therefore recovers on its own with no lockout.

The lockout occurs only when the feeder hand never leaves the pouch's proximity volume (4.9 units from the chest anchor, hsRadius 3.5 x CLAIM_HYSTERESIS 1.4) between entering it and releasing the grip â€” i.e. an immediate change of mind, a grip slip during the draw, or the rarer case of a seat where the gun's magwell sits within 4.9 units of the pouch anchor. In that window pouchClaimedMain/Off was set on entry and never cleared, so after Abort writes GripClaim = None the re-claim at :1334 is skipped, the engine publishes GRIPSUBJ_Holster (10) instead of GRIPSUBJ_Pouch (11), and RR_Reload.Watch's `if (!InPouch(pmo, h)) continue;` (rr_sequence.zs:134) rejects the hand until it is moved ~5 inches clear of the chest anchor and brought back. Severity is closer to "confusing dead grip in a specific abort case" than "broken-in-common-case", since any natural hand movement away from the chest silently clears it.

---

## HardPoints

### 12. The main arm's three gesture-fire netevents have no alias, so mounts 0-2 can never be fired -- but the main arm still arms and still eats your grip

**File:** `E:\mERGE\RS_VR_Unified\zscript\hardpoints\RS_HardPoints.zs (with E:\mERGE\RS_VR_Unified\KEYCONF and MENUDEF.txt)`  
**Line:** RS_HardPoints.zs:2605-2607 (the three main-arm netevent names), 2381-2452 (updateGestureArmMain), 2848-2941 (fireGestureMain); KEYCONF:96-110 (only the three off-arm aliases exist)  
**Severity:** `broken-in-common-case`

**Symptom**

Turn gesture-cast on and the main hand arms (confirm haptic on controller 0, all three main reticles pulse) and its grip is permanently redirected -- but there is no key you can bind that fires anything on the main bank. Rolling the main wrist does nothing except cost you normal grip behaviour and lock the main hand into the splayed reach pose. Half the feature the menu advertises ("Each arm arms its OWN three mounts") has no input path at all.

**Cause**

The 2026-08-26 re-layout added the whole main-arm gesture half in ZScript -- gestureArmedMain, gesturePreviousMain, gestureSeatedMain, updateGestureArmMain, fireGestureMain, and NetworkProcess dispatch for rs-hardpoint-gesture-main-grip / -main-padx / -main-trigger at RS_HardPoints.zs:2605-2607 -- but neither KEYCONF nor MENUDEF was updated. KEYCONF:96-110 still defines exactly three aliases (rs_hardpoint_gesture_grip/padx/trigger -> the OFF-arm netevents -> indices 3/4/5) and its own header at KEYCONF:96 still reads "GESTURE-CAST fire. Off hand only, wrist trio only." With no alias, the three main netevents cannot appear in Customize Controls and no addmenukey row exists for them; nothing ships that can send them. Meanwhile updateGestureArmMain (2381) runs unconditionally every tic and ORs gestureArmedMain into mainClaimedFinal at RS_HardPoints.zs:1548, which pins pawn.HardpointClaimMain true at :1593. The engine reads that at vk_openxrdevice.cpp:3644: hardpointHere forces ctx = GRIPCTX_Hardpoint (:3721) so the main grip never reaches GRIPCTX_Object or GRIPCTX_Modifier, and forces subj = GRIPSUBJ_Holster (:3829), which rs_hands.zs PoseForSubject maps to POSE_REACH. So the main arm pays the entire cost of arming and has no way to collect the benefit.

**Trigger**

rs_hardpoint_gesture_enable 1 (the only way to use the feature at all). Everything else at defaults: rs_hardpoint_wrist_main = true, count 3, edit mode off, rs_hardpoint_gesture_roll_target 0.0 / tolerance 30.0 -- which arms the main arm immediately (see the roll-target finding).

**Verification**

Verified every citation directly against the files.

(a) Lines say what is claimed. RS_HardPoints.zs:2605-2607 are exactly the three main-arm dispatch lines (rs-hardpoint-gesture-main-grip/-padx/-trigger -> fireGestureMain(..., 0/1/2)). updateGestureArmMain is at :2381, fireGestureMain at :2848. Line 1548 reads `bool mainClaimedFinal = mainClaimed || gestureArmedMain[i];` and :1593 `pawn.HardpointClaimMain = mainClaimedFinal;` â€” verbatim as cited. KEYCONF:96-110 defines exactly three aliases, all off-arm, and its header at :96 reads "GESTURE-CAST fire. Off hand only, wrist trio only. Each alias is hardcoded to ONE hardpoint index: grip -> 3, pad/X -> 4, trigger -> 5."

(b) Defaults correct. CVARINFO.txt:815 rs_hardpoint_wrist_main = true; :816 rs_hardpoint_wrist_main_count = 3; :843 rs_hardpoint_gesture_enable = false; :859 roll_target = 0.0; :860 roll_tolerance = 30.0. ZScript accessors agree (gestureEnabled() false-fallback :2214-2218, gestureRollTarget() 0.0 :2243, gestureRollTolerance() 30.0 :2249, wristTierLive/wristCount true-fallback :2160-2182).

(c) No missed guard or alternate input path. Grepped the whole project tree for "rs-hardpoint-gesture": the ONLY hits are the three KEYCONF aliases (104/107/110) and the six ZScript NetworkProcess lines (2602-2607). No ZScript SendNetworkEvent for the main names, no other lump. MENUDEF.txt has no Control row for any hardpoint gesture alias (its only Control rows are the wheel's at 1216-1217 and 1257-1260) and no SafeCommand for them (I enumerated all 22 SafeCommand lines; the hardpoint ones are edit/table/reset/recalibrate/save-layout/load-layout/debug only). I also extracted the shipped RS_VR_Unified.pk3 and its embedded KEYCONF matches the source exactly â€” three off-arm aliases, no main ones. Nothing that ships can emit the three main netevents.

(d) Arithmetic produces the broken result. updateGestureArmMain runs unconditionally every tic at :552, immediately before updateClaims at :553 (with a comment stating the ordering is required precisely because updateClaims ORs the armed flags in). Its gate at :2385 is gestureEnabled() && wristTierLive(true) && !editMode[i]; at defaults with the enable flipped on, wristCount(true)=3>0 and edit mode is off, so allowed=true. Arming is abs(normalizeDeg(MainHandRoll - 0.0)) <= 30.0, and the mod's own MENUDEF text at :768-769 states "Arming is a roll test that a hand at rest already passes, so leaving this on pins that hand's grip claim permanently." So gestureArmedMain becomes true, ORs into mainClaimedFinal (:1548), pins HardpointClaimMain (:1593), and fires the channel-0 confirm haptic (:1572 and :2426). The reticle symptom also checks out: at :1778-1794 with gesture on the main markers switch from a distance feed to a roll feed, rollDelta=0 against rollSenseRange=90, giving proxValue=1.0 â€” all three main reticles read fully hot.

(e) Genuinely player-observable. MENUDEF.txt:770-771 advertises "Each arm arms its OWN three mounts: roll palm-out and they fire in place, without ever being drawn." Half of that has no input path, while KEYCONF:96 still asserts the opposite ("Off hand only") â€” the two shipped lumps contradict each other, ZScript having been updated on 2026-08-26 and KEYCONF/MENUDEF not. The player turns on the advertised feature, gets arming haptic and hot reticles on the main arm, loses normal main-hand grip behaviour to POSE_REACH, and has no shipped control that fires mounts 0-2.

Could not refute on any of the five checks.

**Correction (supersedes Cause/Trigger above)**

The finding is correct as reported; one wording refinement only. "There is no key you can bind that fires anything on the main bank" is slightly too absolute at the engine level: `netevent` is an ordinary console command, so a hand-edited ini (bind p "netevent rs-hardpoint-gesture-main-grip") would reach fireGestureMain. But that path is exactly what this project's own KEYCONF declares unreachable at :165-166 ("this is used in VR, where there is no reachable console, so an alias with no menu row is not 'advanced', it is unreachable"). Accurate phrasing: the three main-arm gesture netevents have no KEYCONF alias, no addmenukey row, and no MENUDEF Control/SafeCommand row, so they cannot be bound from Customize Controls and nothing that ships can send them â€” while updateGestureArmMain still arms the main arm every tic and pins HardpointClaimMain, costing normal main-hand grip behaviour with no way to collect the benefit. Also worth stating explicitly: normal store/draw on mounts 0-2 via rs-vrhp-grab-* is unaffected; it is specifically gesture-FIRE on the main bank that is unreachable.

---

### 13. Gesture-fired weapons are NOT hidden -- rs_hands overwrites the psprite's NoDraw every tic, so the mount's gun visibly teleports into your hand

**File:** `E:\mERGE\RS_VR_Unified\zscript\hardpoints\RS_HardPoints.zs (colliding with E:\mERGE\RS_VR_Unified\zscript\hands\rs_hands.zs)`  
**Line:** RS_HardPoints.zs:2821-2823 and 2936-2938 (psp.NoDraw = true); rs_hands.zs:281-283 (wpsp.NoDraw = fist)  
**Severity:** `broken-in-common-case`

**Symptom**

The whole point of the feature -- "a wrist mount fires its weapon IN PLACE, palm-out, without ever drawing it" -- does not happen. Within one tic of a gesture-fire the hardpoint weapon's model appears in the player's hand and stays there for the whole armed stretch, then swaps back out when they roll out of the pose. It reads as a broken weapon-swap, not a wrist cast. Conversely, with rs_hands turned off (rs_hands 0), or on any non-console player, nothing ever clears NoDraw: after ONE gesture-fire that hand's weapon model is invisible for the rest of the map even though the weapon still fires normally.

**Cause**

fireGesture (RS_HardPoints.zs:2821-2823) and fireGestureMain (:2936-2938) set psp.NoDraw = true once, on the assumption stated at :2650-2655 that it "stays hidden for as long as it stays seated". But RS_HandsAlwaysOn.WorldTick -> Show -> StandInForFist (rs_hands.zs:270-286) runs every tic for both layers and does an unconditional assignment, not a set: `let wpsp = player.FindPSprite(isMain ? PSprite.WEAPON : PSprite.OFFHANDWEAPON); if (wpsp != null) wpsp.NoDraw = fist;` where fist = rs_hands_fists && IsFist(current weapon). A hardpoint weapon is not a fist, so this writes false and un-hides it. Both handlers are registered in the same MAPINFO.txt:82 list (RS_HandsAlwaysOn first, RS_HardPointManager eleventh), so this is guaranteed collision, not a race. The reverse failure is real too: NoDraw is a plain DPSprite member (p_pspr.h:288, `bool NoDraw = false;`) that nothing in the engine ever resets. player_t::GetPSprite (p_pspr.cpp:356-424) reuses the existing DPSprite on a weapon change and resets only Flags and firstTic; PlayerPawn.TickPSprites (player.zs:597-604) only destroys the layer when Caller != ReadyWeapon/OffhandWeapon, which never happens because MoveWeaponToHand updates both in the same call. So with rs_hands' write removed, the hide is permanent.

**Trigger**

rs_hardpoint_gesture_enable 1, a weapon on a mount that clears the wrong-hand guard, and any gesture-fire key press. rs_hands = true and rs_hands_fists = true are both defaults, so the "weapon is visible" half is the default outcome. The "permanently invisible" half needs rs_hands 0 or a second player.

**Verification**

CONFIRMED, not refuted. I checked all five points independently.

(a) The cited lines are verbatim correct. RS_HardPoints.zs:2821-2823 (fireGesture) and :2936-2938 (fireGestureMain) are `let psp = pawn.player.GetPSprite(PSP_*); if (psp != null) psp.NoDraw = true;`. rs_hands.zs:270-286 StandInForFist ends with `let wpsp = player.FindPSprite(isMain ? PSprite.WEAPON : PSprite.OFFHANDWEAPON); if (wpsp != null) wpsp.NoDraw = fist;` where `fist = want && IsFist(w)` and `w` is the hand's CURRENT weapon. The assignment is unconditional; its own comment ("Cleared as well as set. Leaving NoDraw behind on a layer that later holds a gun would hide the gun.") states the clear is deliberate.

Same object, not two different layers: engine constants.zs:824 `PSP_OFFHANDWEAPON = 1000000` and player.zs:3080-3082 `WEAPON = 1, OFFHANDWEAPON = 1000000`. rs_hands' own hand layers are 900000/1900000 (rs_hands.zs:54-55), separate, so the write at :283 lands on exactly the psprite hardpoints hid.

Runs every tic: RS_HandsAlwaysOn.WorldTick (rs_hands.zs:94-140) gates only on consoleplayer validity and the rs_hands cvar, then calls Show() for LAYER_MAIN and LAYER_OFF unconditionally. Show (rs_hands.zs:366+) has only two early returns before line 422 (hand inventory item missing; Spawn state / psprite creation failure) â€” neither occurs in normal play. So StandInForFist writes both weapon layers every tic. A seated hardpoint weapon is not a fist, so IsFist is false and the write is `false` â€” un-hiding it â€” even when rs_hands_fists is off (want=false gives the same false).

(c) Not guarded anywhere. grep for NoDraw across the entire E:\mERGE\RS_VR_Unified\zscript tree returns exactly three writes: rs_hands.zs:283 and RS_HardPoints.zs:2823/:2938. Hardpoints never re-asserts the hide (no write in updateGestureArm/updateGestureArmMain or anywhere else), so the once-only set loses to the every-tic clear. Nothing in zscript/hands references hardpoints at all except rs_grab.zs's GRIPCTX_Hardpoint, which affects hand pose only.

Handler collision is real: MAPINFO.txt:82 registers both RS_HandsAlwaysOn and RS_HardPointManager. Ordering only decides whether the weapon is visible from the same tic or from the next one; either way rs_hands' per-tic write wins for the rest of the armed stretch.

(d)/(e) Player-observable: the whole reason StandInForFist exists is that a weapon psprite renders as a visible model alongside the hand layer, so NoDraw=false means the mount's weapon model is drawn in the hand. The documented design at RS_HardPoints.zs:2620-2655 ("fires its weapon IN PLACE, palm-out, and never draws it ... Stays hidden for as long as it stays seated") does not happen.

Reverse half also verified in the engine source at E:\UZDXREMA: p_pspr.h:288 `bool NoDraw = false;` is a fork-added plain member (DEFINE_FIELD at p_pspr.cpp:163, serialized at :1514); player_t::GetPSprite (p_pspr.cpp:356-424) reuses the layer's existing DPSprite and, on caller change, resets only Flags, State (STRIFEHANDS only) and firstTic â€” never NoDraw. So with rs_hands 0 the hide genuinely persists past the falling-edge restore.

The one thing I would not sign off on is the reporter's supporting sentence "MoveWeaponToHand updates both in the same call": player.zs:2605-2642 actually sets player.PendingWeapon and then calls DropWeapon() (returning early) or BringUpWeapon(). The conclusion still holds â€” the layer's DPSprite is reused by GetPSprite with NoDraw intact â€” but the mechanism described is not what that function does.

Wrong-hand guard does not block the path: it only fires when w.bNoHandSwitch is true, which is not the default for ordinary weapons.

**Correction (supersedes Cause/Trigger above)**

The defect stands as described; only the severity framing needs adjusting. rs_hardpoint_gesture_enable defaults to FALSE (CVARINFO.txt:843), and the three gesture netevents have no default binds (KEYCONF:103-110 are addmenukey aliases only). So this is not something a player hits at stock settings â€” it is broken in 100% of uses once the feature is turned on and a key is bound, which makes it "feature is inert whenever enabled" rather than "broken-in-common-case". Also, the supporting claim that "MoveWeaponToHand updates both [ReadyWeapon and OffhandWeapon] in the same call" is inaccurate â€” player.zs:2605-2642 sets PendingWeapon then calls DropWeapon()/BringUpWeapon() â€” but the conclusion it supports (the layer's DPSprite is reused and NoDraw survives) is correct for a different reason: GetPSprite (p_pspr.cpp:356-424) reuses the existing DPSprite for the layer and resets Flags/firstTic but never NoDraw.

---

### 14. The "Stored item up/down" slider moves the prop DOWN when you raise it

**File:** `E:\mERGE\RS_VR_Unified\zscript\hardpoints\RS_HardPoints.zs (slider at MENUDEF.txt:761)`  
**Line:** 1982-1984 (localUpX/Y/Z), applied at 2013-2016  
**Severity:** `broken-in-edge-case`

**Symptom**

In the Arm Hardpoints menu, dragging "Stored item up/down" to a positive value pushes every stored weapon model further DOWN out of its ring, and negative pushes it up. The player chases the setting in the wrong direction. The "fwd/back" and "side" sliders next to it are correct, so the one axis reads as broken rather than as an inverted convention.

**Cause**

updateProps builds the trim basis as `localUpX = -cos(finalAngle)*sin(finalPitch); localUpY = -sin(finalAngle)*sin(finalPitch); localUpZ = -cos(finalPitch);` (:1982-1984) -- the exact negative of the true up vector. At finalPitch = 0 that is (0, 0, -1), i.e. straight down. It is then applied as `+ (nUp * localUpX/Y/Z)` at :2014-2016 with nUp = RS_HardPointProp.holsterPropUp(). The correct up is computed 800 lines earlier in the same file, in handAnchorPos (:1149-1151): `upx = cos(ang)*sin(pit); upy = sin(ang)*sin(pit); upz = cos(pit)`, verified there as right x forward and matching RS_Basis.Up in rs_grab.zs:36-42. handAnchorPos' own comment at :1142-1147 notices the disagreement and dismisses it as "a symmetric bidirectional knob nobody would notice the polarity of" -- which is not true of a slider labelled "up/down" in a menu. The forward and side vectors on the same lines (:1979-1981, :1985-1986) are correctly signed, which is why only this axis is wrong.

**Trigger**

Any non-zero rs_hardpoint_prop_up. The cvar defaults to 0.0 (CVARINFO.txt:730) so nothing is visibly wrong until the player touches that one slider -- which the menu presents as the tool for centring a stored model in its ring, and which the file header (:433-439) calls the manual centring correction.

**Verification**

Confirmed on all five checks by reading the files directly.

(a) Cited lines are verbatim correct. RS_HardPoints.zs:1982-1984 reads `double localUpX = -cos(finalAngle) * sin(finalPitch); double localUpY = -sin(finalAngle) * sin(finalPitch); double localUpZ = -cos(finalPitch);`. It is consumed at :2014-2016 inside `Vector3 placed = (at.X - worldOffX + (nFwd*localFwdX) + (nUp*localUpX) + (nSide*rightX), ... at.Z - worldOffZ + (nFwd*localFwdZ) + (nUp*localUpZ))`, with `double nUp = RS_HardPointProp.holsterPropUp();` at :2009, then `p.SetOrigin(placed, true)` at :2018. handAnchorPos at :1149-1151 uses the opposite signs (`upx = cos(ang)*sin(pit); upy = sin(ang)*sin(pit); upz = cos(pit)`), and the comment at :1142-1147 exists verbatim, explicitly conceding the trim sliders "get away with being inverted."

(b) Defaults check out. CVARINFO.txt:730 `user float rs_hardpoint_prop_up = 0.0;`. MENUDEF.txt:761 `Slider "Stored item up/down", "rs_hardpoint_prop_up", -12.0, 12.0, 0.5, 1`. finalPitch at defaults is 0: basePitch is literally `0.0` for body-anchored mounts (:1686), edPitch[h] is 0 until edited, rs_hardpoint_prop_pitch defaults 0.0 (CVARINFO.txt:723), and bakedPitchOffset is 0 for any weapon whose MODELDEF omits PitchOffset.

(c) Not guarded. RS_HardPointProp.zs:440-444 is `static double holsterPropUp() { let cv = CVar.GetCVar("rs_hardpoint_prop_up", ...); return (cv != null) ? cv.GetFloat() : 0.0; }` â€” raw passthrough, no negation, no clamp. A grep for holsterPropUp across zscript/hardpoints finds exactly one call site (RS_HardPoints.zs:2009), so there is no second sign flip to cancel it.

(d) The arithmetic is broken, and more broadly than the report says. localUp is exactly -1x the true up at EVERY pitch, not only at zero: at finalPitch=0 it is (0,0,-1) versus true (0,0,1); at finalPitch=90 it is (-cos ang, -sin ang, 0) versus true (+cos ang, +sin ang, 0). The +Z-up convention is independently confirmed by RS_HardPoints.zs:274/:286, where WristBelow presets `hsFrac = -3.0` and are applied through `edFrac[idx] * upz` with `upz = cos(pit)` (:1151, :1162) â€” a negative frac with a +cos up is what puts the mount below the wrist, matching the name. The inverse projection used for drag-editing (:1183 `upz = cos(pit)`, :1196) also uses the true up. The RenderModel pitch-negation discussed in the :1967-1978 comment cannot rescue this: it affects how the model's baked offset is rotated about the actor origin, not the sign of a world-space translation added to that origin before SetOrigin.

(e) Player-observable. Opening Arm Hardpoints and dragging "Stored item up/down" toward +12 visibly drives every stored weapon model downward out of its ring; -12 drives it up. It is a self-correcting trim knob so the player can still reach a good value by dragging the other way, which is why severity broken-in-edge-case is the right call, but the first drag does move the wrong way relative to the label.

Two corrections to the report, neither substantive: (1) the "file header (:433-439)" citation is in the wrong file â€” that centring-nudge comment is RS_HardPointProp.zs:433-439, not RS_HardPoints.zs. (2) The identical inversion exists in the sibling holsters subsystem (RS_Holsters.zs:1769-1771, applied :1801-1803, fed by RS_HolsterProp.holsterPropUp at :1796, menu label "Stored weapon up/down" at MENUDEF.txt:588), so this is a uniform mod-wide convention rather than a hardpoints-only slip. That weakens the report's "the one axis reads as broken rather than as an inverted convention" framing slightly â€” but it does not make the label correct, and within RS_HardPoints.zs itself the mount-position up (:1151) and the prop-trim up (:1984) still disagree in sign. Note also that the comment at :1120 claims this basis shape is "already proven in updateProps' trim-slider math (localFwdX/localUpX/rightX there)" while :1142-1147 says the opposite â€” the file contradicts itself about which one is right, and :1151 is the one that is.

**Correction (supersedes Cause/Trigger above)**

The finding stands. Two citation fixes: the "manual centring correction" header comment is at RS_HardPointProp.zs:433-439, not RS_HardPoints.zs:433-439; and the same inverted up-basis is duplicated in the holsters subsystem (RS_Holsters.zs:1769-1771 applied at :1801-1803, slider "Stored weapon up/down" at MENUDEF.txt:588), so both "stored item up/down" sliders in the mod move the model the wrong way, rather than this being unique to hardpoints. Also broaden the cause: localUp is exactly the negative of the true up at every pitch, not just at finalPitch=0 (at 90 degrees it points backward-horizontal where true up points forward-horizontal), so the inversion is not limited to the default-pitch case. Fix is to drop the three leading minus signs at RS_HardPoints.zs:1982-1984 (and RS_Holsters.zs:1769-1771) to match handAnchorPos at :1149-1151; because the cvars default to 0.0, no existing saved value is silently reinterpreted except for players who already tuned the slider, who would need to negate their stored value.

---

## Wheel - Layout & Geometry

### 15. Fan sub-cards use the visible plate as their own hit target -- the exact trap spawnPanels' comment exists to prevent

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 3398-3404 (creation) and 4037-4040 (resize)  
**Severity:** `broken-in-common-case`

**Symptom**

On any card in an opened fan, the top and bottom edges and the extreme left/right of the visible plate do not answer the pointer. The card stays unlit, the beam drops back to COLOR_BEAM_IDLE, and because InputProcess early-returns `if (!mOpen || mHovered == 0) return false;` (line 763) the trigger press is NOT consumed -- so instead of taking the weapon, you fire the gun currently in your hand. Ring cards are deliberately forgiving in exactly that band; fan cards are the opposite.

**Cause**

spawnPanels states the rule at 5136-5153: "THE HIT QUAD IS NOT THE PICTURE. Billboards draw 1.2x taller than they are authored ... so a quad that is both the picture and the target is hittable across only the middle 83% of what you can see." The ring obeys it: mIds[i] is a separate alpha-0 quad sized `panelW * HIT_PAD, panelH * CARD_STRETCH * HIT_PAD` = 4.704 x 4.032 (line 6013-6014), and the visible plate mPlates[i] is BBFL_NOHIT. The fan never got the fix: mSubIds[i] is created with flag 0 (hittable) AND is the drawn plate (`SetBillboardGradient` on the same id, line 3402), and layoutExpansion resizes it to `panelW * spulse, panelH * spulse` = 4.2 x 3.0 -- no CARD_STRETCH, no HIT_PAD. Drawn height is 3.0 * 1.2 = 3.6, hit height is 3.0, so 0.3 units at the top and 0.3 at the bottom (8.3% each) of every fan card are visible but dead, and there is zero horizontal margin where a ring card gets 0.252 units on each edge. Every other fan billboard (mSubLabels, mSubIcons, mSubAccents, mSubAmmos, mSubGauges, mSubMarks, mSubShadows) is correctly BBFL_NOHIT, which is what makes the plate itself the target.

**Trigger**

DEFAULTS. wr_subcards_max 10 (fans on), any slot holding 2+ weapons, fan opened by dwell (DWELL_TO_EXPAND 7 tics) or +use. Fires whenever the pointer lands within ~8% of a fan card's top or bottom edge, or on its outer 6% horizontally.

**Verification**

I read zscript.zs directly and verified each link in the chain.

(a) Cited lines say what is claimed. 3398-3404: mSubIds is AddBillboardPersistent(..., srest, 0, 0, "") â€” BBFL argument is literal 0, i.e. hittable â€” and SetBillboardGradient(sid, ...) is called on that same id, so it is also the drawn plate. 4037-4040: ResizeBillboard(mSubIds[i], panelW * spulse, panelH * spulse) â€” no CARD_STRETCH, no HIT_PAD. Contrast the ring: hit quad 5148-5153 (COLOR_IDLE, 0, ...) + SetBillboardAlpha(id,0); visible plate 5198-5201 with LevelLocals.BBFL_NOHIT; hit resize 6013-6014 panelW*HIT_PAD, panelH*CARD_STRETCH*HIT_PAD; plate resize 6144 panelW*pulse, panelH*pulse. The spawnPanels rule at 5136-5147 is quoted accurately.

(b) Defaults check out. CVARINFO.txt: wr_panel_w 4.2, wr_panel_h 3.0, wr_touch 7.0, wr_sheet true, wr_subcards_max 10. Constants: HIT_PAD 1.12 (8653), CARD_STRETCH 1.2 (8720), FAN_FIRST_RING 1.6 (8903). Ring hit 4.704 x 4.032; fan hit 4.2 x 3.0 drawn 4.2 x 3.6.

(c) Not guarded anywhere. Grep of mSubIds|mSubHit shows no separate sub-card hit quad exists. tintCard (3772-3804) is decisive: the ring branch recolours mPlates[card], a DIFFERENT billboard from the hit id, while the sub branch calls UpdateBillboard(id, 0, ...) on the hit id itself â€” the code's own structure confirms the fan plate is the target. Every other fan billboard (3393, 3416, 3430, 3454, 3476, 3503, 3515) is BBFL_NOHIT. No rescue path: TouchBillboard (7476) is a 7.0-unit sphere around handPos and the fan sits cellW*FAN_FIRST_RING = 5.25*1.6 = 8.4 units beyond the parent card which is itself at ringR, so out of range; stickPick only answers ring bearings.

(d) Arithmetic works out vertically. The 1.2 premise is independently corroborated: RS_HardPoints.zs:1994 reads level.info.pixelstretch, GZDoom's vertical world stretch (Doom default 1.2). AimBillboard tests in map units, so a 3.0-unit quad covers 3.0/3.6 = 83.3% of the drawn 3.6 â€” 0.3 units dead at top and bottom.

(e) Player-observable. updateHover (8289-8310) sets mHovered = hit even when hit == 0 (it only declines to COLLAPSE the fan on hit==0, not to clear hover), so the dead band really does drop hover to zero, unlight the card, and idle the beam. InputProcess:763 `if (!mOpen || mHovered == 0) return false;` then leaves the trigger unconsumed and the shot reaches the gun.

Two parts of the claim are wrong and are corrected rather than fatal: the horizontal dead band does not exist (stretch is vertical only; fan hit width 4.2 exactly equals drawn width 4.2 â€” the ring's 0.252/side is lost forgiveness, not dead area, and plateShape() rounds the corners anyway), and the trigger condition is misstated (line 3144: mFansEnabled = countAdmissible(pmo) > max(0, cv("wr_subcards_max", 10.0)) â€” fans need MORE than 10 admissible weapons, so vanilla Doom's 9 never fans; routine in BD/PB-class loadouts).

**Correction (supersedes Cause/Trigger above)**

Fan sub-cards use their own visible plate as their hit target, in violation of the rule spawnPanels documents at zscript.zs:5136-5147. mSubIds is created hittable (BBFL argument 0, line 3401) and is simultaneously the drawn plate (SetBillboardGradient on the same id, 3402; recoloured directly by tintCard, 3800-3803; faded at 4131), and layoutExpansion sizes it panelW * spulse, panelH * spulse (4038) with neither CARD_STRETCH nor HIT_PAD. The ring does it correctly: separate alpha-0 quad at panelW * HIT_PAD, panelH * CARD_STRETCH * HIT_PAD (6013-6014) with the plate BBFL_NOHIT (5201).

The defect is VERTICAL ONLY. At defaults (wr_panel_w 4.2, wr_panel_h 3.0, wr_scale 1.0) a fan card is authored 4.2 x 3.0 and, because the renderer applies pixelstretch = CARD_STRETCH = 1.2 to world Z, draws 4.2 x 3.6. The hit test runs in map units against 3.0, so 0.3 units at the top and 0.3 at the bottom â€” 8.3% each of the visible height â€” are drawn but unhittable. Pointing there sets hit = 0, updateHover (8310) writes mHovered = 0, the card unlights, the beam falls back to idle, and InputProcess:763 early-returns without consuming the trigger, so the press fires the weapon currently in hand instead of taking the one on the card.

Corrections to the original report: (1) there is NO horizontal dead band â€” the stretch is vertical only, so the fan card's hit width (4.2) exactly equals its drawn width; the ring's extra 0.252 per side is forgiveness the fan lacks, not visible-but-dead area, and rounded plate corners give slack there. The claims about "the extreme left/right of the visible plate" and "its outer 6% horizontally" are wrong. (2) The trigger is not "any slot holding 2+ weapons at defaults": line 3144 sets mFansEnabled = countAdmissible(pmo) > max(0, cv("wr_subcards_max", 10.0)), so a fan can only open when the loadout holds MORE than 10 admissible weapons. Vanilla Doom (9 weapons) never fans; BD/PB-class loadouts do, routinely.

Related, outside the claim: mSheetHit is likewise sized exactly to the plate (sw, sh at 2560-2561) with no CARD_STRETCH, giving the centre sheet the same 83% vertical coverage.

---

### 16. Honeycomb ring-by-ring arrival never runs: outer cards sit balled up at the centre for the whole animation, then teleport

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 5930-5936  
**Severity:** `broken-in-common-case`

**Symptom**

With wr_hex on, opening the wheel with 8 or more weapons shows every card from the 8th onward stacked on top of the centre card, motionless, for six tics -- then all of them snap to their cells in a single frame. The 2nd-through-7th cards travel only about half way and then jump the rest. The advertised effect ("the centre lands, then the six around it, then the twelve around those") never happens.

**Cause**

`cardGrow = clamp((grow * span - lead) / span, 0.0, 1.0)` treats `grow` as elapsed tics, but growFactor() (5478-5486) returns an already-normalized ease-out cubic in 0..1. So `grow * span` maxes out at exactly `span`. At defaults span = max(wr_growtics 6.0, 1.0) = 6 and lead = hexRingOf(i) * wr_hex_stagger 3. For hex ring 2 lead = 6 = span, so `(grow*6 - 6)/6 = grow - 1 <= 0` -> cardGrow is 0 for every tic of the animation; then at mOpenTics = 6 growFactor() returns exactly 1.0, the `grow < 1.0` guard goes false, and cardGrow jumps straight to 1.0. hexRingOf (4212-4218) puts index 7 onward in ring 2, so any hive of 8+ cards is affected -- a normal Doom loadout. Ring 1 (indices 1-6) gets cardGrow = grow - 0.5, which per tic is 0, 0, 0.204, 0.375, 0.463, 0.495, then 1.0: half the travel in the last frame. The correct idiom is three hundred lines away in the same file -- lineGrow() at 3560-3568 staggers off raw `mFanTics` (`(mFanTics - lead)/span`), not off an eased fraction.

**Trigger**

wr_hex 1 (not the default) with wr_hex_stagger 3 and wr_growtics 6 (both defaults) and 8 or more cards. At 2-7 cards only the half-travel snap shows.

**Verification**

Verified every link independently in E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs. (a) Lines 5930-5935 read exactly as quoted: cardGrow = clamp((grow * span - lead) / span, 0.0, 1.0) inside `if (stagger > 0 && grow < 1.0)`. (b) `grow` is confirmed to be the eased normalized value, not tics: line 5853 is `double grow = growFactor();` and growFactor() at 5478-5486 returns 1-(1-t)^3 with t = clamp(mOpenTics/dur, 0, 1). Defaults confirmed in CVARINFO.txt: wr_hex = false (line 1050), wr_hex_stagger = 3 (line 1056), wr_growtics = 6.0 (line 1217). hexRingOf (4212-4218) does put i=1..6 in ring 1 and i=7..18 in ring 2. (c) Not handled elsewhere: wr_hex_stagger appears at exactly one code site in the whole mod (5930); there is no clamp of lead against span and no alternate path. lineGrow() at 3560-3568 does stagger off raw mFanTics, confirming the correct idiom exists in the same file. (d) The arithmetic is genuinely broken: with grow in [0,1), (grow*span - lead)/span = grow - lead/span, which caps below 1 - lead/span, so for any ring >= 1 cardGrow can never reach 1 while the guard is active; it only reaches 1.0 when grow hits exactly 1.0 at mOpenTics == 6 and the branch stops running. Ring 2 has lead = 6 = span, so cardGrow = 0 for the entire animation. The reporter's per-tic ring-1 numbers reproduce exactly (growFactor at mOpenTics 0..6 = 0, .4213, .7037, .875, .96296, .99537, 1.0, minus 0.5). (e) Player-observable at realistic load: layout() runs every tic (called at 7398 right after ++mOpenTics at 7376) and writes positions directly via MoveBillboard/SetBillboardGroupOrigin at 5997-6014 with no smoothing, so the jump is a real one-frame teleport. Card count is realistic: mFansEnabled = countAdmissible(pmo) > cv("wr_subcards_max", 10.0) at line 3144 with default 10 (CVARINFO.txt:1429), so a vanilla 9-weapon loadout stays flat at 9 cards, putting indices 7 and 8 in hex ring 2. Two extra confirmations the reporter missed: roll = (1.0 - cardGrow) * ARRIVE_ROLL (line 5990, ARRIVE_ROLL = 26.0 at 8792) means outer cards also hold a full 26-degree tumble for the whole animation and snap level in the same frame, and the hit quads move with the cards so every outer card's selectable quad is stacked at the wrist for the duration. Could not refute on any of the five checks.

**Correction (supersedes Cause/Trigger above)**

Confirmed as reported, with two accuracy refinements. First, the outer cards are not literally motionless while stacked at the centre: openRig() calls level.AnimateBillboardGroup(mGroups[i], 0.0, 1.0, growTics) at line 966, so the engine scales each card from 0 to full size at renderer rate during those six tics. The player sees the outer cards grow to full size piled on the centre card, then teleport outward, rather than a frozen stack. Second, the severity label should be scoped: wr_hex defaults to false (CVARINFO.txt:1050), so this is broken in every case *within* the opt-in honeycomb mode (any loadout of 8+ cards, which is a normal vanilla Doom loadout), not broken in the default configuration. Everything else in the report -- the cited lines, the defaults, the ring indices, the per-tic cardGrow values, and the diagnosis that grow is an already-eased 0..1 fraction being multiplied as if it were elapsed tics -- is accurate.

---

### 17. Inspect sheet and comparison card are anchored to the hand at an offset tuned when they were a third the height

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 7180-7193 (layoutInspect) and 7105-7117 (layoutCompare)  
**Severity:** `broken-at-defaults`

**Symptom**

Rest the laser on a weapon lying on the floor for half a second and a panel taller than the player snaps up centred on the controller, filling most of the view and hiding both the pickup being inspected and the room. It is not a card held in the hand; the hand is inside it.

**Cause**

Both pass `centre = handPos(pmo, hand) + (0,0, cv("wr_rise", 2.0))`. At defaults the inspect sheet is sw 10.92 x sh 25.8 (drawn 1.2x = 30.96 tall) and the comparison card is panelWNow * CMP_W_CARDS = 17.64 x panelHNow * CMP_H_CARDS = 19.5 (drawn 23.4). With no hand tracking handPos is `eye + fwd*22 + right*(+/-11) - (0,0,8)` (7205-7209), so a 30.96-unit-tall panel sits 22 map units from the eye -- about 70 degrees of vertical arc, from ~23 degrees above eye level to ~44 degrees below. The RING's copy of the identical sheet is fine only because it hangs at mAnchor, which is wr_forward = 34 units past the hand (~56 from the eye, ~31 degrees). Both anchors date from when the panels were a third the size: SHEET_H_CARDS went 3.2 -> 3.9 -> 8.6 (comment at 8799-8818) and CMP_H_CARDS 3.0 -> 6.5 (comment at 8834-8842), and in both cases the row fractions were rescaled in proportion while the hand offset that positions the whole plate was never revisited. Secondary: layout() scales rise by wr_scale (`rise *= sc`, line 5699) but these two pass raw `cv("wr_rise", 2.0)`, so at wr_scale 2 the panel doubles and its offset does not.

**Trigger**

DEFAULTS. wr_inspect 1, wr_inspect_dwell 18 tics, laser resting on any unowned Weapon or recognised pickup stand-in. wr_inspect_delta 1 picks the comparison card when that hand holds a weapon, the data sheet when it is empty. Exact angular size depends on where real controller tracking puts handPos; the 22-unit figure is the untracked fallback the code itself synthesises.

**Verification**

Confirmed against source. All cited lines say what is claimed: 7111 `centre = handPos(pmo, mInspectHand) + (0,0,cv("wr_rise",2.0))`, 7186-7192 `wrist = handPos(...)` then `layoutSheet(wrist, ..., cv("wr_rise",2.0), 0.0, panelW, panelH, 0.0)` with lateral 0 and no forward term, and layoutSheet:2544 `centre = wrist + viewRight*lateral + (0,0,rise)` confirming the plate's CENTRE lands there. The ring's contrast is real: layout():5628 `mAnchor = handP + ahead*clearForward` with `wantForward = cv("wr_forward",34.0)` (5553), and `wrist = mAnchor` (5675), so the identical sheet hangs 34 units further out.

Defaults verified from CVARINFO.txt, not just the cv() fallbacks: wr_panel_w 4.2 (1025), wr_panel_h 3.0 (1026), wr_scale 1.0 (1170), wr_rise 2.0 (1032), wr_forward 34.0 (1196), wr_sheet_scale 1.0 (1523), wr_inspect true (1708), wr_inspect_dwell 18 (1713), wr_inspect_delta true (1721). SHEET_W_CARDS 2.6 / SHEET_H_CARDS 8.6 (8798/8818), CMP_W_CARDS 4.2 / CMP_H_CARDS 6.5 (8833/8842), CARD_STRETCH 1.2 (8720). So sheet 10.92 x 25.8 authored -> 30.96 rendered tall; compare card 17.64 x 19.5 -> 23.4 rendered. Both growth comments confirm only ROW_FRAC/PITCH were rescaled; the hand anchor is untouched.

No guard exists. buildSheet (2401) and buildCompare (6529) use plain AddBillboardPersistent with no scale group; layoutSheet (2552) and layoutCompare (7120) ResizeBillboard to the full size every tic; sheetScale() (2254) is 1.0 at defaults. Nothing clamps size against distance-to-eye. tickInspect() is called at 7321, BEFORE the `if (!mOpen) return;` at 7323, so it runs with the ring closed â€” reachable at defaults.

The one line of attack that could have refuted this: cv() uses GetFloat and wr_inspect is `user bool`, and the file's own comment at 3011-3012 asserts GetFloat on a bool returns zero (the wr_autoopen story). If true, tickInspect would endInspect() and return on every tic and this would be dead code. But buildSheet:2395 gates on the identical idiom (`cv("wr_sheet", 1.0) <= 0.0`) against `user bool wr_sheet = true` (CVARINFO 1514), and the ring's data sheet demonstrably renders in the headset. So GetFloat on a bool returns 1.0 in this engine, the 3011 comment is a misdiagnosis of something else, and inspect mode is live.

Where the reporter is wrong, and it does not change the verdict: (1) "a panel taller than the player" is false â€” 30.96 map units against a 56-unit player and a ~41-unit view height; it is about 75% of eye height, not taller than the player. (2) The angular figures are inflated. handPos is 22 fwd, 11 right, 8 down from the eye, so the horizontal distance to the panel's vertical centreline is sqrt(22^2+11^2) = 24.6, not 22. Panel centre sits at z = -6 relative to the eye, half-height 15.48, so it spans atan(9.48/24.6) = 21 deg above eye level to atan(21.48/24.6) = 41 deg below â€” about 62 deg vertical, not 70. (3) It is not "centred in the view": untracked, the panel's centre is atan(11/22) = 27 deg off to the pointing hand's side, spanning roughly 14-37 deg lateral, so in the desk fallback it sits beside the target rather than over it. With real controller tracking, where the player brings the controller into the line of sight to point, it does cover the target, and the panel gets worse rather than better â€” a controller 15-20 units from the eye puts half-height 15.48 at atan(15.48/18) = 40 deg each way, ~80 deg of vertical arc.

The core defect survives all of that: the same sheet subtends roughly 2.3x the angle in inspect mode that it does on the ring, purely because one anchor got the 34-unit standoff and the other did not, and the standoff was never revisited when SHEET_H_CARDS went 3.2 -> 3.9 -> 8.6 and CMP_H_CARDS 3.0 -> 6.5. The plate is SHEET_BG 0x0E1016 (8875), near-black and opaque, so it occludes. The hand is geometrically inside the plate: the plate's plane passes through handPos and extends 13.5 units below it and 17.5 above.

The secondary wr_scale point is real but is not a defaults issue: layout():5699 does `rise *= sc` while 7111/7192 pass raw cv("wr_rise",2.0), yet panelWNow()/panelHNow() (4748-4749) do include wr_scale â€” so at wr_scale 2 the panel doubles and its offset does not. At the default wr_scale 1.0 this is a no-op and should be reported as a separate, lower-severity inconsistency rather than as part of a broken-at-defaults finding.

**Correction (supersedes Cause/Trigger above)**

Confirmed with corrected magnitudes. At defaults the inspect data sheet is 10.92 x 25.8 authored, rendering 30.96 units tall (CARD_STRETCH 1.2), and the comparison card is 17.64 x 19.5 authored, rendering 23.4 tall. Both are centred at handPos + (0,0,2) with no forward standoff, while the ring's copy of the identical sheet hangs at mAnchor = hand + 34 units (wr_forward). Untracked (zscript.zs:7209) that puts the sheet's centreline 24.6 units from the eye and 6 units below it, so it spans ~21 deg above eye level to ~41 deg below â€” about 62 deg of vertical arc and ~23 deg wide, centred ~27 deg off to the pointing hand's side. The comparison card is ~36 deg wide by ~53 deg tall. With real controller tracking (pmo.AttackPos / OffhandPos, 15-20 units from the eye) the vertical arc grows to roughly 80 deg and the panel lands over the pickup being pointed at. The panel plane passes through the hand itself, extending ~13.5 units below and ~17.5 above it, so the hand is inside the plate rather than holding it. It is not "taller than the player" (30.96 vs a 56-unit pawn) and it is not centred in the view in the untracked fallback. Root cause as stated: SHEET_H_CARDS grew 3.2 -> 3.9 -> 8.6 (8799-8818) and CMP_H_CARDS 3.0 -> 6.5 (8834-8842) with only the row fractions rescaled; the hand anchor at 7111/7191-7192, tuned when the plates were a third the height, was never revisited. The `rise *= sc` vs raw cv("wr_rise") mismatch (5699 vs 7111/7192) is a genuine but separate inconsistency that only bites at non-default wr_scale.

---

### 18. The left/right wall clamp is inert in honeycomb mode -- the hive and its sheet render into walls

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 5645-5672 and 5789 vs 5908-5919 and 5804-5810  
**Severity:** `broken-in-edge-case`

**Symptom**

With wr_hex on, opening the wheel in a doorway, a corridor or against a corner puts the right-hand columns of the comb -- and the whole data sheet -- inside or behind the wall, where they are invisible and unpointable. The ring layout is explicitly protected from this; the hive is not.

**Cause**

The two side traces at anchor-freeze produce mMaxRingR, and the only consumer is line 5789, `if (mMaxRingR >= 0.0 && ringR > mMaxRingR) ringR = max(mMaxRingR, minR);` -- it caps `ringR` and nothing else. Hex mode never reads ringR: positions come from `hexOffset(i, cellW, cellH)` (5916) with cellW = panelW * 1.25 = 5.25, and the sheet's own offset is `sheetLateral = cellW * (outerRing + 0.5) + panelW * (SHEET_W_CARDS * sheetScale() * 0.5 + SHEET_GAP_CARDS)` (5807-5809), also independent of ringR and of mMaxRingR. At defaults with 8-19 cards outerRing is 2, so the comb reaches cellW*2 + panelW/2 = 12.6 units laterally and the sheet's far edge reaches 5.25*2.5 + 4.2*1.85 + 5.46 = 26.36 units to the player's right -- all uncapped. sideMax is 60.0, so a wall at those ranges IS found and mMaxRingR IS set correctly; the value is simply applied to a variable the hex path does not use. The forward trace (clearForward, 5597-5606) still applies, so this is precisely the lateral failure the side traces were added for and precisely the case they still miss.

**Trigger**

wr_hex 1 (not the default), wr_scale 1, wr_panel_w 4.2, 8 or more cards, ring opened with a wall within ~26 units to the player's right or ~13 units to either side.

**Verification**

Verified independently against E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs. (a) Cited lines are accurate: 5645-5672 are the two anchor-freeze side traces (sideMax 60.0 at 5646, sideMargin 6.0 at 5652, -1.0 sentinel at 5658); 5789 is `if (mMaxRingR >= 0.0 && ringR > mMaxRingR) ringR = max(mMaxRingR, minR);`. A whole-file grep for mMaxRingR yields only the decl (529), two writes (5664, 5671), one comment (5776) and that one consumer (5789), so the cap really does reach nothing but ringR. (b) Defaults confirmed in CVARINFO.txt: wr_hex=false (1050), wr_panel_w=4.2 (1025), wr_panel_h=3.0 (1026), wr_scale=1.0 (1170), wr_sheet=true (1514), wr_sheet_scale=1.0 (1523); consts SHEET_W_CARDS=2.6 (8798), SHEET_GAP_CARDS=0.55 (8819), HIT_PAD=1.12 (8653). (c) Not guarded elsewhere: cellW = panelW*1.25 (5738) is never adjusted by mMaxRingR (its only uses are 5738, 5752, 5808, 5916, 6304); layoutSheet (2521-2599) takes ringR as a parameter and never reads it, placing the plate and its hit quad at wrist + viewRight*lateral (2544, 2558-2563); mLastRingR (5793) likewise only carries ringR. In hex mode ringR survives only into layoutStars, so the wall cap effectively sizes the starfield. (d) Arithmetic verified: hexRingOf(7)=2, hexRingOf(18)=2, hexRingOf(19)=3 so outerRing=2 for 8-19 cards; sheetLateral = 5.25*2.5 + 4.2*(2.6*0.5+0.55) = 13.125+7.77 = 20.895, far edge +5.46 = 26.355. (e) Player-observable: wr_hex is exposed in MENUDEF.txt:1011, and no wheel billboard carries BBFL_NODEPTH (that flag exists and is used deliberately in wr_gunhud.zs:646-647 and 670-671), so wheel geometry is depth-tested and a wall does hide it. Two claim details fail: the symptom's "unpointable" half is wrong, because selection is entirely geometry-blind (level.AimBillboard at 7440, whose own comments at 7438-7439 and 7512-7514 state it passes through walls; TouchBillboard at 7476; stickPick at 7454) so hidden cards still hover and still commit; and the 12.6-unit comb figure needs 12+ cards on the right (the first axial x=+2 cell is index 11) and 18+ on the left, not 8 â€” at 8 cards the comb reaches only about 7.6 units right. Core mechanism stands, symptom needs correction.

**Correction (supersedes Cause/Trigger above)**

Under wr_hex 1 the anchor-freeze side traces are inert: mMaxRingR (zscript.zs:5658-5671) is consumed only at 5789 to cap ringR, and the hex path takes card positions from hexOffset(i, cellW, cellH) (5916, cellW = panelW*1.25 = 5.25) while the sheet takes sheetLateral = cellW*(outerRing+0.5) + panelW*(SHEET_W_CARDS*sheetScale()*0.5 + SHEET_GAP_CARDS) (5807-5809) â€” neither reads ringR or mMaxRingR. At defaults with 8-19 cards outerRing is 2, so the sheet centre sits 20.895 units to the player's right with its far edge at 26.355, uncapped; the comb itself reaches cellW*2 + half a card (about 12.6) only at 12+ cards on the right and 18+ on the left, roughly 7.6 at 8 cards. Opening the wheel with a wall inside that range puts the whole data sheet, and with a large weapon set the right-hand columns of the comb, behind solid geometry. The wheel's billboards carry no BBFL_NODEPTH (unlike wr_gunhud.zs:646-647), so they are occluded and invisible â€” but they are NOT unpointable: AimBillboard (7440), TouchBillboard (7476) and stickPick (7454) all ignore world geometry, so the hidden cards still hover, still light, still commit, and SetVRLaserRange (7517) still clamps the beam to a card the player cannot see. The observable failure is a truncated comb, a missing data sheet, and blind selection of cards behind the wall â€” not loss of selection.

---

## Wheel - Selection & Input

### 19. The ring auto-closes after exactly 4 seconds even while you hold the pointer steady on a card

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 8250-8252 and 8310-8317 (reset site), 7370 (decrement)  
**Severity:** `broken-at-defaults`

**Symptom**

Point the laser at a card (or at the data sheet) and hold still to read it. At ~3.3 s the whole ring visibly fades (warnFrac) and one haptic tick fires; at 4.0 s the wheel closes itself and hands the weapon back, mid-decision. Reading a DOOM Infinite / Lithium stat sheet -- which can be 28 rows -- is impossible without jiggling the pointer off the card and back on to restart the timer. Worst on a desktop/no-tracking setup, where handDir() falls back to pmo.angle/-pmo.pitch and a still mouse gives a perfectly stable hover.

**Cause**

WorldTick decrements mLockTics unconditionally every tic (`if (--mLockTics <= 0) { closeRig(); return; }`). The ONLY two writes that reset it are openRig() line 939 and updateHover() lines 8314-8315 -- and that second one lives *after* the `if (hit == mHovered) { ... return; }` early-return at 8250-8252. So mLockTics is reset on the tic the hovered id CHANGES and never again while it stays the same. Holding one card therefore gives exactly wr_locktics = 140 tics = 4.00 s from the moment you landed on it. Both the code comment ("Hovering resets it, because a hand on a card is someone who is still deciding") and CVARINFO.txt:1136-1137 ("Tics the rig stays up with nothing hovered before folding away... Hovering a card resets it") describe continuous-hover behaviour that the code does not implement. Note the hovered card is deliberately made *sticky* -- wr_pop 1.5 steps it 1.5 units toward the eye, and its hit quad subtends ~7.7 x 6.6 degrees at the ring's ~35-unit range -- so holding one card for 4 s is easy, which is what makes the bug reachable rather than masked by jitter. Paging the sheet is accidentally safe (wr_page -> rebuildPage sets mHovered = 0, which forces a change next tic); plain reading is not.

**Trigger**

DEFAULTS. wr_locktics = 140, wr_warn_tics = 25. Any steady hover of 140 tics on one card or on mSheetHit.

**Verification**

I read the actual code and could not refute any leg of this.

(a) The cited lines say what is claimed.
- `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs:7370` is `if (--mLockTics <= 0) { closeRig(); return; }`. I read the whole enclosing block (7279-7375): the decrement sits at WorldTick's top level, after only the `!mOpen` early-out (7323) and the dead/null-pawn hard-close (7326-7333). There is NO hover guard on it.
- `updateHover` starts at 8218. The `if (hit == mHovered)` branch opens at 8250, short-circuits at 8252 for `mHovered == 0`, and the branch ALWAYS returns (`return;` at 8286). The lock reset is at 8312-8317 (`mHovered = hit` at 8310, then `if (hit != 0) { mLockTics = int(cv("wr_locktics",140)); if (mLockTics<=0) mLockTics=140; mWarnedThisOpen=false; }`) â€” strictly after that return. So the reset runs only on the tic the hovered id CHANGES.

(b) Defaults are correct. CVARINFO.txt:1137 `user int wr_locktics = 140;` and :1143 `user int wr_warn_tics = 25;`. MENUDEF.txt:979 sliders wr_locktics 35..700 (no "off" value) and :980 wr_warn_tics 0..105. 140 tics / 35 = 4.00 s. Warn check (7362-7368) runs BEFORE the decrement, so it fires on the tic mLockTics is already 25, i.e. after 115 decrements = 116 tics = 3.31 s. Both numbers in the report are right.

(c) Not guarded anywhere else. `grep -n mLockTics` over zscript.zs yields exactly five sites: declaration 543, read-only warnFrac at 3863-3864 and 5894-5895, the decrement 7370, and the two writes 939-940 (openRig) and 8314-8315 (updateHover). A repo-wide grep for `mLockTics|LockTics` across every .zs outside wheel/zscript.zs returns nothing â€” no other file resets it.

(d) The arithmetic produces the broken result, and I checked the obvious masking mechanisms that could have refuted it:
- Card billboard ids are stable while open. `repaintFaces` (5052) only repaints canvases; `refreshSheet` (1086) early-returns on `mSheetValid && nowCls == mSheetShown` and otherwise only rebuilds ROWS â€” it never touches `mSheetHit` (assigned once in buildSheet at 2411, cleared at 2504). `mHovered` is written only at 913/1057 (close), 2642 (rebuildPage), 2763 (clearPanels) and 8310. None of those fire during a steady hover.
- I checked whether per-tic animation could jitter the hit id and thereby reset the timer: `breathe` (5865) is `sin(level.maptime * 1.7) * 0.35 * sc` â€” a Â±0.35 map-unit rigid translation applied identically to `origin` and every card (5868, 5919, 5942), against wr_panel_h 3.0. It cannot move the ray off a card it is centred on. `wr_pop` 1.5 (5950-5953) displaces the hovered card once along its own cardâ†’eye axis and then holds. The light's `breathe` at 8206 is radius-only.
- On a desktop/no-tracking setup `handDir` (7242-7259) and `handPos` (7195-7210) are both pure functions of pmo.angle/pmo.pitch/pmo.Pos, so with a still mouse and a standing player the AimBillboard ray and the card positions are bit-identical every tic. Hit id is provably constant, so the hover branch returns at 8286 for 140 consecutive tics and the ring closes.

(e) Player-observable, and it contradicts the shipped documentation. CVARINFO.txt:1135-1137 reads "Tics the rig stays up with nothing hovered before folding away. 35 = 1 second. / Hovering a card resets it." and the code comment at 7337-7338 says "Hovering resets it, because a hand on a card is someone who is still deciding." Neither is what the code does. The visible half is real too: warnFrac (5892-5895, and the subcard copy at 3862-3864) fades the whole ring from 1.0 to a 0.15 floor over the last 25 tics, plus one `level.VRHaptic(mPokeHand, 0.3*warnGain, 40)` at 7367 â€” so the player sees the ring fade at 3.3 s and lose the rig at 4.0 s while holding perfectly still on a card, with the gun handed back mid-decision.

The report's incidental notes also hold: rebuildPage (2630-2644) does set `mHovered = 0`, so paging is accidentally exempt; and a momentary hit==0 flicker resets the timer via the two-step (0 clears mHovered without resetting, then the card re-lands and does), which is exactly why jiggling the pointer works around it and a steady hold does not.

I found nothing that refutes the finding.

**Correction (supersedes Cause/Trigger above)**

The finding stands as written. Two minor line-reference corrections, neither affecting the substance: (1) the reset block is lines 8310-8317, not 8314-8315 alone (`mHovered = hit` at 8310, `mHoverTics = 0` at 8311, the `if (hit != 0)` lock reset at 8312-8317); (2) the `hit == mHovered` branch's return is at line 8286, not 8250-8252 â€” 8250 is the branch test and 8252 is only the `mHovered == 0` short-circuit, but the branch does unconditionally return before reaching 8312, so the conclusion is unchanged. The CVARINFO doc text the report quotes is at lines 1135-1136 with the declaration at 1137. Also worth adding: the warning haptic is only fired once per open (`mWarnedThisOpen`, 7363-7368), and because that flag is reset only where mLockTics is, a player who never changes hovered card gets exactly one fade-and-buzz and then the close, with no second chance.

---

### 20. The "reach into the ring" input is geometrically unreachable at defaults, so the +use grab never fires

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 7468-7480 (touch query), 5553-5628 (anchor placed wr_forward ahead), 807 (+use grab gate)  
**Severity:** `broken-at-defaults`

**Symptom**

The header's "TWO WAYS IN" is one way in. mTouching is never true, so: reaching a hand into a card never selects it; "TOUCH WINS OVER BEAM" never happens; and +use as the grab ("Use is the grab, for when your hand is already on the card") does nothing. On a vanilla-sized loadout (9 weapons, so mFansEnabled is false) +use inside the open wheel is completely inert -- InputProcess falls through every branch and returns false, so the key leaks out and opens the door behind you instead. wr_touch's own menu slider tunes a dead input.

**Cause**

layout() freezes the anchor at `mAnchor = handP + ahead * clearForward` with clearForward = wr_forward = 34.0 map units (~1 m). Cards then orbit that anchor at ringR, which at defaults is floored by the sheet to `panelW * (SHEET_W_CARDS*0.5 + 0.5 + SHEET_GAP_CARDS)` = 4.2 * 2.35 = 9.87, plus rise 2.0. So the nearest card sits sqrt(34^2 + 9.87^2 + 2^2) = 35.5 units from the hand position at the moment the ring opened, and even the centre sheet is 34.06 away. WorldTick then asks `level.TouchBillboard(org, touchR)` with org = the current hand position and touchR = wr_touch * wr_scale = 7.0. The hand would have to physically travel 28.5+ units (~88 cm) from where it was at open -- far past arm extension. wr_touch's CVARINFO text ("DEPTH tolerance... how far your hand may sit in front of or behind [the grid]") is left over from when the ring wrapped the hand at radius 5; wr_forward = 34 moved the ring and the 7-unit sphere was never revisited. migrateConfig() (CFG_VERSION 20) actively writes both 34.0 and 7.0 into every existing config, so no player escapes it. The one case where touch does work is a wall clamp: clearForward floors at `max(wr_forward*0.35, dist-6)` = 11.9, so opening the wheel with your hand pointed at a wall closer than ~22 units brings the nearest card to ~15.6 and puts it inside arm's reach. Reaching therefore only works pressed up against geometry.

**Trigger**

DEFAULTS. wr_forward = 34.0, wr_touch = 7.0, wr_scale = 1.0, wr_sheet on. Fails for every open in open space.

**Verification**

I could not refute it. Every link in the chain checks out, and the one thing the reporter got technically wrong (the touch test's geometry) makes the defect *worse*, not better.

(a) CITED LINES SAY WHAT IS CLAIMED.
- E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs:7428 `Vector3 org = handPos(pmo, mPokeHand);` â€” the LIVE hand position, with the surrounding comment explicitly stating the old cursor/hand gain was removed ("One to one, both position and aim... There was hand acceleration here and it is gone").
- :7467-7480 `double touchR = cv("wr_touch", 7.0) * cv("wr_scale", 1.0); mTouching = false; if (touchR > 0.0) { [touched, tuv, tdist] = level.TouchBillboard(org, touchR); mTouching = (touched != 0); ... }`. This is the ONLY assignment of `mTouching` to true in the file (greps confirm: 552 decl, 1058/2762/7469 reset to false, 7478 the only true path).
- :5628 `mAnchor = handP + ahead * clearForward;` with `handP = handPos(pmo, mRigHand)` (:5562), inside `if (!mHaveAnchor)` (:5523) so it freezes once per open. `Vector3 wrist = mAnchor;` (:5675) and cards placed at `pos = wrist + viewRight*(cos(bearing)*ringR) + (0,0,sin(bearing)*ringR + rise + breathe)` (:5941). mAnchor is world-frozen; nothing moves it while open.
- :807 `if (!fire && !(mTouching && wr_Keybind.isKeyFor(e.KeyScan, "+use"))) return false;` â€” exactly as quoted.

(b) DEFAULTS ARE CORRECT. CVARINFO.txt: wr_forward 34.0 (:1196), wr_touch 7.0 (:1109), wr_scale 1.0 (:1170), wr_panel_w 4.2 (:1025), wr_panel_h 3.0 (:1026), wr_radius 5.0 (:1031), wr_rise 2.0 (:1032), wr_sheet true (:1514), wr_sheet_scale 1.0 (:1523). Constants: SHEET_W_CARDS 2.6 (:8798), SHEET_GAP_CARDS 0.55 (:8819), HIT_PAD 1.12 (:8653), CARD_STRETCH 1.2 (:8720). sheetScale() returns 1.0 (:2254). So sheetR = 4.2*(1.3+0.5+0.55) = 9.87 â€” the reporter's number is right. migrateConfig (CFG_VERSION 20, :2951) does write `setCv("wr_touch", 7.0)` and `setCv("wr_forward", 34.0)` (:2988-2989), so archived configs get the same numbers.

(c) NOT GUARDED ANYWHERE. I checked every escape hatch:
- No second writer of mTouching; no SweepBillboard call anywhere in the mod.
- The wheel is the only source of hittable billboards near the player while open. wr_gunhud.zs's three billboards (:436, :643, :667) are all created with BBFL_NOHIT. The inspect sheet â€” the one thing layoutSheet ever places AT `handPos` (:7186) â€” is torn down unconditionally whenever the ring is open (tickInspect, :6383 `if (mOpen || cv("wr_inspect",1.0) <= 0.0) { endInspect(); return; }`). Transients (AddBillboard) carry no handle and cannot be returned by a query. So the only hittable quads in existence are the card hit quads (:5148), sub-card quads, and mSheetHit (:2411) â€” every one of them parked at the anchor.
- The recenter path (:871 `mHaveAnchor = false`) re-freezes the anchor at hand + 34 again; it does not shorten anything.
- SuppressVRInput is stick-only (vmthunks.cpp:5411 â†’ VR_SetScriptInputSuppressed; g_game.cpp:1306 gates only locomotion/snap-turn), so it does not swallow the leaked +use.

(d) THE ARITHMETIC IS BROKEN â€” and I verified the engine's actual test rather than assuming. E:\UZDXREMA\src\scripting\vmthunks.cpp:5231-5268 TouchBillboard is NOT a sphere: `double dist = fabs(normal | rel); if (dist >= bestDist) continue;` then `if (fabs(across) > halfw || fabs(down) > halfh) continue;`. So maxRange is a plane-DEPTH tolerance and the point must additionally land inside the quad â€” matching the cvar's own "DEPTH tolerance" text. Cards are BBF_FIXED with faceYaw solved toward the eye (:5975), so each card's normal points essentially back along `ahead`; the hand-to-plane depth is ~clearForward = 34.0 against a tolerance of 7.0. The hand must advance 27 map units along the aim from where it was at open. vr_vunits_per_meter defaults to 34.0 (hw_vrmodes.cpp:635), so 27 units is exactly 79 cm of forward hand travel â€” past any arm. It must ALSO simultaneously sit inside a 4.70 x 4.03 hit quad (panelW*HIT_PAD, panelH*CARD_STRETCH*HIT_PAD, :6013-6014) centred 9.87 units off-axis. The added bounds test makes this strictly harder than the sphere the reporter assumed. mTouching cannot become true at defaults in open space.

(e) PLAYER-OBSERVABLE. mFansEnabled = countAdmissible > wr_subcards_max (default 10) at :3144, so a vanilla 9-weapon loadout leaves it false. InputProcess (:761) then: the fan branch (:775) needs mFansEnabled, the sheet branch (:799) needs mHovered == mSheetHit, and :807 needs mTouching. +use on a card falls through all three and returns false â€” so the key is not consumed and reaches the playsim, activating whatever line the player is facing. A player presses Use to "grab" the card the header and the :805 comment tell them to grab, and instead opens a door. The wr_touch slider (MENUDEF.txt:1204 "Reach-in radius (0 = off)") tunes an input that is dead across its whole 0.5-20.0 range at default wr_forward.

CORROBORATING SIGNAL the reporter did not cite: `const TOUCH_RANGE = 9.0;  // fingertip radius` (:237) is declared and referenced nowhere else in the file â€” a leftover from the era when the ring wrapped the hand, which is the same "never revisited" story.

**Correction (supersedes Cause/Trigger above)**

The finding stands; three factual corrections to the write-up.

1. The metric is wrong (conclusion unchanged, and the real test is stricter). `level.TouchBillboard(org, touchR)` is not a sphere of radius 7 â€” vmthunks.cpp:5231-5268 tests `fabs(normal | (p - bpos)) < maxRange` AND `fabs(across) <= halfw && fabs(down) <= halfh`. So the governing number is not sqrt(34^2+9.87^2+2^2)=35.5; it is the 34.0-unit depth to the card plane against a 7.0 tolerance, PLUS the hand having to land inside the card's own 4.70 x 4.03 hit quad while it is there. Required forward hand travel is 27 units, and vr_vunits_per_meter defaults to 34.0 (hw_vrmodes.cpp:635), so that is exactly 79 cm â€” the "88 cm" figure is slightly overstated but the verdict is identical.

2. The wall-clamp case works for a different reason than stated. It is not that Euclidean distance falls to 15.6; it is that the depth floor becomes clearForward = max(34*0.35, dist-6) = 11.9, so the hand needs only 11.9 - 7 = 4.9 units (14 cm) of forward travel plus lateral alignment with a card. Pressed against geometry, reaching genuinely works.

3. There is a second, non-reaching way mTouching can fire that the report misses, and it is itself a wrong result: mAnchor is frozen in WORLD space, so a player who walks ~27 units forward during the 140-tic (4 s) lock window drives their hand into the card planes. Touch then fires from locomotion â€” while the ring is passing through the player's face â€” rather than from the deliberate reach the design is built around.

Also worth noting for triage, though it does not weaken the finding: MENUDEF.txt:1203 carries the author-side comment "Drop wr_forward toward 0 to bring the ring into actual arm reach." That is an invisible source comment, guards nothing, and directly contradicts zscript.zs:87-92 ("TWO WAYS IN, and they are not rivals... Reaching is switched off with wr_touch 0"), so it is evidence the mismatch was noticed and left in place, not evidence it was handled.

---

### 21. The inspect comparison card keeps comparing against a weapon you are no longer holding

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 6491-6510 (rebuild guard), 6479-6486 (mine/wantCompare recomputed every tic), 6625-6651 (fill)  
**Severity:** `broken-in-common-case`

**Symptom**

Point at a weapon on the floor while holding the pistol -- the compare card appears reading "vs PISTOL" with green/red verdicts against the pistol. Now switch your held weapon (number key, holster draw, hardpoint stow, ammo-out auto-switch) while still pointing at the same floor weapon. The card does not change: it still says "vs PISTOL", the HELD column still shows the pistol's damage/ROF/mag/ammo, and every better/worse colour is still a verdict about the pistol. The card is silently lying about the exact question it exists to answer.

**Cause**

tickInspect recomputes `mine` (line 6479-6480) and `wantCompare` (6485-6486) every tic, but the only thing that triggers a re-fill is `if (mInspectWpn != found)` at 6491 -- a change of the FLOOR weapon. fillCompare(foundW, mine) is therefore never re-run when `mine` changes under it; mCmpSub ("vs " .. mine.GetTag(), line 6626) and every mCmpB column stay strung with the old weapon. Same guard also misses a change of mInspectHand (line 6465), which switches `mine` between ReadyWeapon and OffhandWeapon with no re-fill. The same missing refresh has a second, worse failure mode: if wantCompare FLIPS while `found` is unchanged (an empty hand becomes filled, or a filled hand becomes empty), no rebuild runs, so the code calls layoutCompare() with mCmpPlate == 0 -- or layoutInspect() with mSheetPlate == 0, since the compare branch called clearSheet() -- and that layout function early-returns. The card that is actually on screen then stops being positioned at all and hangs frozen in mid-air at the last hand position until you look away.

**Trigger**

wr_inspect = true, wr_inspect_delta = true (both default), wr_inspect_dwell = 18. Any weapon change in the pointing hand while the compare card is up. The frozen-card variant additionally needs the hand to go from empty to armed or back, which in this merge means an actually-empty hand (no RS_HandFist seated).

**Verification**

I read the code directly and could not refute the core claim; it holds on every check.

(a) The cited lines say exactly what is claimed.
- `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs:6479-6480` â€” `Weapon mine = (mInspectHand == 1) ? pmo.player.OffhandWeapon : pmo.player.ReadyWeapon;` sits in the straight-line body of `tickInspect()`, past the `if (mInspectTics < want) return;` dwell gate at 6469, so it is recomputed every tic the card is up.
- `6485-6486` â€” `bool wantCompare = (foundW != null && mine != null && mine != foundW && cv("wr_inspect_delta", 1.0) > 0.0);` likewise recomputed every tic.
- `6491` â€” the rebuild block is guarded solely by `if (mInspectWpn != found)`, and `found` (6446) is the FLOOR actor only. `mine` and `wantCompare` are read inside that block (6495, 6499) but are not part of its condition.
- `6512-6513` â€” `if (wantCompare) layoutCompare(pmo); else layoutInspect(pmo);` runs on the freshly-recomputed `wantCompare`, outside the guard.
- `6626` â€” `level.SetBillboardText(mCmpSub, "vs " .. mine.GetTag());` is inside `fillCompare()`, and every `cmpStat`/`cmpRow` HELD value (6630-6651) is likewise strung from the `mine` passed in at fill time.
- `6465` â€” `mInspectHand = hand;` is assigned every tic from whichever laser hit, and is not in the guard either, so a main->off hand handoff on the same floor actor swaps which weapon `mine` resolves to with no re-fill.

(c) Not guarded anywhere else. `grep` over the whole file shows `fillCompare` has exactly ONE call site, line 6499, inside that guard. `mInspectWpn` is written in only two places: 6493 and `endInspect()` at 7172. `endInspect()` is reachable only from `tickInspect`'s own early exits (6386 ring open / `wr_inspect` off, 6393 dead or not in game, 6408 DOOM Infinite menu, 6453 grace expired) â€” none of which is a weapon change. `clearCompare()` at 2658 is inside `clearPanels()`, i.e. ring teardown, and opening the ring calls `endInspect()` first anyway. There is no weapon-change hook, no `mCmpShown` sentinel analogous to the sheet's `mSheetShown` (6505), and `tickInspect()` has a single caller at 7321 that runs unconditionally every tic. So nothing re-fills the card when the held weapon changes.

(b) Defaults are correct. `E:\mERGE\RS_VR_Unified\CVARINFO.txt:1708` `user bool wr_inspect = true;`, `:1713` `user int wr_inspect_dwell = 18;`, `:1721` `user bool wr_inspect_delta = true;` â€” matching the fallbacks at 6468 and 6486. So the compare card is the default-path card.

(d) The broken result follows. The card stays on screen (layoutCompare keeps running every tic) while its subtitle and its entire HELD column are text captured at fill time. Switch weapons in the pointing hand and the card reads "vs PISTOL" against a pistol you are no longer holding, with the green/red per-side verdicts at 6594-6601 still adjudicating the old pair. Nothing recovers it while the laser stays on the same floor actor.

(e) Player-observable, and more robustly than the reporter argued. `mInspectTics` is incremented unbounded at 6466 with no clamp, and losing the target only decrements it one per tic (6452). So after dwelling a few seconds the grace window is seconds long â€” a holster reach or hand-off that briefly breaks the trace does NOT reset anything: on reacquire, `found == mInspectCand` (6459) so tics do not reset and `mInspectWpn == found` so no re-fill. The stale card survives the interruption. A plain number-key or ammo-out auto-switch does not move the pointing hand at all and produces the stale card with zero interruption.

The frozen-card sub-variant is also structurally real: `layoutCompare` early-returns on `mCmpPlate == 0` (7107) and `layoutInspect` early-returns on `mSheetPlate == 0` (7182); the compare branch calls `clearSheet()` (6497, which zeroes mSheetPlate at 2504) and the sheet branch calls `clearCompare()` (6503, which zeroes mCmpPlate at 6575). So a `wantCompare` flip with `found` unchanged does route to a layout function whose plate is 0, leaving the other card's persistent billboards drawn but never re-positioned.

The only thing I would narrow is that sub-variant's reachability, which the reporter already flagged: `E:\mERGE\RS_VR_Unified\zscript\hands\rs_fist.zs:34` has `user bool rs_hands_fists = true;`, so at defaults a hand is normally kept armed with a seated fist and `mine != null`, keeping `wantCompare` pinned true. That makes the frozen-card mode rare-to-unreachable at stock settings. It does not touch the primary defect, which needs only a weapon change and no empty hand at all.

**Correction (supersedes Cause/Trigger above)**

The primary finding stands as written and is confirmed: tickInspect's rebuild guard at zscript.zs:6491 keys only on the floor actor, so fillCompare (sole call site, 6499) never re-runs when `mine` (6479) or `mInspectHand` (6465) changes under it, leaving the "vs <TAG>" subtitle at 6626 and the whole HELD column stale until the player points at a different floor weapon or the grace counter expires. Severity broken-in-common-case is right for this half.

One narrowing to the secondary "frozen card" failure mode: it requires `wantCompare` to flip while `found` is unchanged, which requires `mine` to become null (or non-null). rs_fist.zs:34 defaults `rs_hands_fists = true`, which seats a fist into an otherwise-empty hand, so at stock settings `mine` is rarely null and this mode is closer to edge-case than common. The mechanism is real (both layout functions early-return on a zeroed plate, and each branch zeroes the other's plate), but it should be reported as the lower-confidence half of the finding rather than as an equally-likely symptom. Note also that a hand HANDOFF (main laser drops, off-hand laser acquires the same actor) flips `mInspectHand` at 6465 with no re-fill and can flip `wantCompare` even with fists enabled, which is the most plausible route into the frozen state.

---

### 22. When the pointer is not on a card the volumetric beam stops 8 units out, a quarter of the way to a ring that is 34+ units away

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 7506-7509 (fallback), consumed at 7704-7710  
**Severity:** `broken-at-defaults`

**Symptom**

Sweep the pointer across the gap between two cards and the dusty beam collapses to a short stub floating near your hand, then snaps back out to full length the moment it lands on a card -- a 4.4x length jump on every card-to-card crossing. While it is stubbed, the engine's own thin laser (SetVRLaserRange(0) = unclamped) still runs all the way to the wall, so the two pointers visibly disagree about where you are aiming. Between cards you have no beam reaching the ring at all, which is exactly when you most need to see where the pointer is.

**Cause**

`reach` is computed as `distanceToHit(...)` when rayHit != 0 -- about 35 units at defaults -- but falls back to `cv("wr_radius", 5.0) * cv("wr_scale", 1.0) * 1.6` = 5.0 * 1.6 = 8.0 when rayHit == 0. wr_radius is the ring's ORBIT radius, not its distance from the hand; 8.0 was "just past the ring" back when the ring was centred on the wrist at radius 5 (the layout() comment describes exactly that former geometry). Once the ring moved to `handP + ahead * wr_forward` with wr_forward = 34.0, the correct miss-case length became ~34, and this expression was never updated. `reach` is passed straight to level.SetVolumetricBeam as its length (line 7707) and is the only consumer in the miss case, since SetVRLaserRange is handed 0 rather than reach when rayHit == 0.

**Trigger**

DEFAULTS. wr_vbeam = true, wr_radius = 5.0, wr_scale = 1.0, wr_forward = 34.0. Every tic the ray is not on a billboard.

**Verification**

I read zscript.zs directly and confirmed all legs of the claim.

(a) Cited lines are accurate. Lines 7499-7509: `double reach; if (rayHit != 0) { reach = distanceToHit(org, dir, rayHit); } else { reach = cv("wr_radius", 5.0) * cv("wr_scale", 1.0) * 1.6; }`. Line 7517: `level.SetVRLaserRange(rayHit != 0 ? reach : 0);`. Line 7519 `decor(pmo, org, dir, reach, hit != 0)` feeds lines 7704-7710, which pass `reach` as the 6th argument of `level.SetVolumetricBeam(org, dir, tint, inner, outer, reach, density, 2.2, dust, 0.035, 0.4)` -- between wr_vbeam_outer and wr_vbeam_density, i.e. the length slot. Grepping every occurrence of `reach` in the file shows these are its ONLY two consumers, and the laser-range one explicitly discards it when rayHit == 0. Nothing clamps or rescales it.

(b) Defaults verified in CVARINFO.txt: wr_radius = 5.0 (line 1031), wr_scale = 1.0 (1170), wr_forward = 34.0 (1196), wr_vbeam = true (1240). Fallback = 5.0 * 1.0 * 1.6 = 8.0 exactly. MENUDEF.txt 990-991 confirms wr_forward ("Ring distance ahead") and wr_radius ("Ring radius") are distinct dials, so the reporter is right that wr_radius is an orbit radius, not a distance from the hand.

(c) Not guarded. The only mitigating structure is mSheetHit (lines 2558-2562), the sheet's hit quad, sized sw = 4.2*2.6 = 10.92 by sh = 3.0*8.6 = 25.8 at defaults and centred on the ring. A ray crossing that central column does register a billboard hit and gets a correct ~34 reach. So the stub appears in the lateral gaps (|x| > 5.46 from ring centre) and anywhere off the rig -- still most of a card-to-card sweep.

(d) Arithmetic works out. Line 5628: mAnchor = handP + ahead * clearForward; line 5675: wrist = mAnchor (cards orbit it); line 7434: org = handPos(pmo, mPokeHand), with mPokeHand = mRigHand (line 900), so the beam origin is the same hand the anchor was projected from. clearForward = 34 at defaults and is floored at wantForward*0.35 = 11.9 even under wall pullback (line 5599), never below 8. ringR is floored by the sheet to 4.2*(2.6*0.5+0.5+0.55) = 9.87, so a card sits at sqrt(34^2 + 9.87^2) = 35.4. Hit ~35 vs miss 8.0 = 4.4x, as claimed.

(e) Genuinely observable. Real gaps exist between card hit quads: HIT_PAD = 1.12 (line 8653) gives a 4.70-wide quad; the chord between 8 cards at ringR 9.87 is 2*9.87*sin(22.5) = 7.55, leaving 2.85 units of daylight, about 4.8 degrees of arc seen from 34 units. Easily swept through with a wrist motion.

The reporter's causal story is also supported by the file: the comment at 7420-7433 states the ring "used to be wrapped around the hand" before it moved out in front, which is exactly the geometry under which radius*1.6 meant "just past the ring".

Only unverifiable point: the engine's SetVolumetricBeam declaration is not in this tree (the wheel is its sole caller repo-wide), so "6th param = length" rests on the parameter name `reach`, the surrounding comment reasoning about "a long beam looking like a strip light", and the fact that the same variable is used as a laser RANGE at 7517. High confidence, not proof.

**Correction (supersedes Cause/Trigger above)**

Confirmed, with two refinements. (1) The stub does not occur on every miss: mSheetHit (zscript.zs:2558-2562) is a 10.92 x 25.8 hit quad standing at the ring centre at defaults, so a ray crossing the central column registers a hit and gets the correct ~34 reach. The 8-unit stub appears in the lateral gaps between cards (about 2.85 units of daylight, ~4.8 degrees of arc, at ringR 9.87 with 8 cards) and anywhere the ray leaves the rig entirely -- still most of a card-to-card sweep, but not literally "every tic the ray is not on a billboard" in the central band. (2) It is worse than reported under stick or touch selection (lines 7454, 7468): there hit != 0 while rayHit == 0, so the beam is pinned at 8 units continuously AND gets the 1.35x onCard density boost the entire time a card is lit 35 units away -- a persistent wrong state while browsing with the stick, not just a flicker on crossings.

---

### 23. mFansEnabled is never recomputed for the inventory/model pages, so dwelling on an item card can pop a fan of weapons that cannot be picked

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 3144 (only assignment), 3074-3088 and 3101-3124 (pages that never set it), 8272-8285 (dwell consumer)  
**Severity:** `latent`

**Symptom**

On the inventory page (or ModelSwapper's model page), resting the pointer on a card for 7 tics plays the fan tick, flashes the card, and unfolds a fan of WEAPON cards out of an inventory item. Those sub-cards select nothing: pressing fire on one is swallowed by InputProcess and then dropped by commitInventory/commitModel, so the trigger is consumed and nothing at all happens.

**Cause**

mFansEnabled is written in exactly one place -- gatherWeaponCards() line 3144, `countAdmissible(pmo) > wr_subcards_max`. gatherInventory() and gatherModels() are the other two branches of gatherWeapons() and neither assigns it, so a ring opened on the weapons page with a large loadout carries mFansEnabled = true across a wr_page flip. updateHover's dwell trigger (8272-8273) is gated on mFansEnabled and not on mPage, so it fires and calls `expandSlot(pmo, cardIndexOf(hit))`. Both non-weapon gatherers push mCardSlots = 0 for every card (3083, 3117), so expandSlot resolves `slotWeapons(pmo, 0, variants)` -- slot 0's owned weapons -- and builds a real weapon fan hanging off an inventory item. HoveredClass() then answers mSubTypes[sub], but commit() routes to commitInventory/commitModel first, both of which do `cardIndexOf(mHovered)` and get -1 for a sub-card id, and return. The same path is reachable at range with +use (InputProcess 775-780 -> wr_expand), also gated on mFansEnabled and not on mPage.

**Trigger**

Needs mFansEnabled true (countAdmissible > wr_subcards_max = 10, i.e. a large-loadout mod) AND weapon slot 0 to hold at least 2 owned weapons -- expandSlot returns early on `variants.Size() < 2`. Slot 0 is empty in vanilla Doom, so this is inert there; it bites only on weapon sets that populate slot 0. DWELL_TO_EXPAND = 7 tics.

**Verification**

All five checks pass; I could not refute this.

(a) Cited lines say what is claimed.
- `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs:3144` is the ONLY assignment to mFansEnabled: `mFansEnabled = countAdmissible(pmo) > max(0, cv("wr_subcards_max", 10.0));`. A full grep for mFansEnabled returns 267 (declaration), 723, 776, 3144, 3177, 3266 (comment), 3275, 5402/5405/5408, 8265 (comment), 8273 â€” 3144 is the sole write.
- `gatherInventory` (3074-3090) and `gatherModels` (3101-3123) are the other two branches of `gatherWeapons` (3058-3062) and neither touches mFansEnabled. Both push `mCardSlots.Push(0)` â€” line 3083 and line 3116 exactly as cited.
- Dwell consumer at 8272-8273: `if (mDwellTics == DWELL_TO_EXPAND && !belongsToExpansion(hit) && mFansEnabled)` â†’ `expandSlot(pmo, cardIndexOf(hit))`. No mPage term.
- +use-at-range path at 775-780 and its server re-check at 723-724 are likewise gated on mFansEnabled/!mTouching/!belongsToExpansion and never on mPage.

(b) Defaults are correct. CVARINFO.txt:1429 `user int wr_subcards_max = 10;`. zscript.zs:8656 `const DWELL_TO_EXPAND = 7;`.

(c) Not guarded anywhere the reporter missed. I grepped every `mPage` occurrence in the file: 388 (field), 653-655 (constants), 703 (flip), 902 (open forces PAGE_WEAPONS), 3060-3061 (gather dispatch), 8046 (`spawnCardModels` only), 8491-8492 (`commit` dispatch). There is no page gate in `updateHover` (8218), in its caller at 7482, in `layout()`'s `if (i == mExpanded) layoutExpansion(...)` at 6303, or in `expandSlot` (3299). `openRig` (887-904) sets `mPage = PAGE_WEAPONS` then gathers, so mFansEnabled is always computed from the WEAPON count and then carried unchanged across `wr_page` â†’ `rebuildPage` (2630-2643), which calls `clearPanels()` + `gatherWeapons()` and nothing else. I confirmed `clearPanels` (2654-2762) does clear mTypes/mCardSlots/mCardColor/mSlotCount, so the inventory page really does have mCardSlots all-zero rather than leftovers.

(d) Arithmetic/flow produces a broken result. `expandSlot` reads `slotWeapons(pmo, mCardSlots[cardIndex], variants)` = slot 0, and `slotWeapons` (3228-3247) walks `players[consoleplayer].weapons.SlotSize(0)` with no page awareness. With â‰¥2 owned slot-0 weapons it sets mExpanded, spawns the flash billboard, and pushes real weapon classes into mSubTypes/mSubIds with flags 0 (hittable). The dead-end is confirmed: sub-card ids live in mSubIds, `cardIndexOf` (3807-3814) only scans mIds, so `commitInventory` (8448-8451) and `commitModel` (8465-8467) both get -1 and `return` â€” while `InputProcess` (806-810) already returned true, consuming the trigger. `commit` (8489-8492) dispatches to those two before ever reaching `HoveredClass()`, so the sub-card's real weapon class is never used.

(e) Player-observable, subject to the reporter's own stated scoping. With slot 0 empty the path is fully inert (verified: the `variants.Size() < 2` early return at 3313 precedes the flash at 3325, and the `mSubIds.Size() > before` check at 8279-8281 suppresses the tick), so vanilla Doom is unaffected â€” the reporter says exactly this. It bites only on a loadout with >10 admissible weapons AND â‰¥2 owned slot-0 weapons. I could not independently confirm a specific shipped mod that satisfies both, which is why this stays "latent" rather than routine; but the code deliberately treats slot 0 as populated territory (3146-3148 "Slot 0 is walked last because that is where the engine's own cycling puts it", 4541 "slot 0 and anything a mod invented"), so it is not a hypothetical the codebase itself rules out.

One thing the reporter under-stated rather than over-stated: `HoveredClass()` (588-605) checks `subIndexOf` FIRST and returns `mSubTypes[sub]` with no page consideration, and `refreshSheet` (1086-1097) feeds that straight into the data sheet. So while a phantom sub-card is hovered on the inventory page, the centre sheet also repaints to that slot-0 weapon's stat rows.

**Correction (supersedes Cause/Trigger above)**

Claim stands. Two refinements to the symptom text:

1. The tick and card flash fire ONLY when a fan actually opens. `expandSlot` returns at zscript.zs:3313 (`if (variants.Size() < 2) return;`) before the `wr_flash` billboard at 3325, and the dwell site guards feedback with `if (mSubIds.Size() > before)` at 8279. So with slot 0 empty the dwell is completely silent and invisible, not "plays the tick and flashes but nothing unfolds". The symptom only manifests in the case the TRIGGER section already scopes.

2. Add a second observable: `HoveredClass()` (zscript.zs:588-605) resolves the sub-card branch before any page check, and `refreshSheet` (1093-1094) consumes it, so hovering one of the phantom sub-cards on the inventory/model page also repaints the centre data sheet with the slot-0 weapon's stat rows â€” the sheet contradicts the page it is sitting on.

---

## Wheel - Painting & Pools

### 24. Inspect/compare card keeps comparing against a weapon you are no longer holding

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 6479-6513 (gate at 6491)  
**Severity:** `broken-in-common-case`

**Symptom**

Point the laser at a weapon on the floor with a gun in that hand. The comparison card appears ("<floor gun>" / "vs <held gun>", THIS vs HELD columns). Now change what that hand is holding -- number key, holster draw/stow, out-of-ammo auto-switch -- while still pointing. The card keeps the old weapon's name in the subtitle and the old weapon's DPS/DAMAGE/ROF/MAG/PELLETS/AMMO/TIER/HANDS in the HELD column, and keeps colouring the green/red verdict against it. Worse, if the hand becomes empty (holstering is a core mechanic of this merge), wantCompare flips false, layoutInspect() early-returns on mSheetPlate==0 (clearSheet() ran when the compare card was built at 6497), and the compare card stops tracking the hand entirely -- it freezes in mid-air at the last position it was placed and stays there until the laser leaves the pickup for wr_inspect_dwell tics. The mirror case is the same: pointing with an empty hand builds the plain sheet, then drawing a weapon flips wantCompare true, layoutCompare() early-returns on mCmpPlate==0 (7107), and the plain sheet freezes in the air instead.

**Cause**

The only rebuild gate is `if (mInspectWpn != found)` at 6491. `mine` (line 6479-6480) and `wantCompare` (6485) are recomputed every tic from the live hand, but they are only ever CONSUMED inside that gate. `found` is the floor actor and has not changed, so fillCompare(foundW, mine) is never re-run, and the built card (compare vs sheet) never switches to match the new value of wantCompare while layoutCompare/layoutInspect are selected fresh each tic at 6512-6513.

**Trigger**

Defaults. wr_inspect 1 (default), wr_inspect_delta 1 (default), wr_inspect_dwell 18. Needs only: laser resting on a floor weapon for 18 tics, then any change to that hand's weapon.

**Verification**

Verified every cited line in E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs. 6479-6480 recompute `mine` from the live hand each tic; 6485 recomputes `wantCompare`; 6491 `if (mInspectWpn != found)` is the sole rebuild gate and `fillCompare(foundW, mine)` at 6499 is inside it (whole-file grep: fillCompare has exactly one caller). 6512-6513 pick the layout from the fresh `wantCompare` outside the gate. layoutCompare early-returns on `mCmpPlate == 0` (7107) and layoutInspect on `mSheetPlate == 0` (7182); the opposite branch's clear (clearSheet 6497 / clearCompare 6503, which zero those ids at 2504 and 6575) guarantees exactly that condition after a mode flip. fillCompare (6616-6698) writes the subtitle "vs "..mine.GetTag() and every HELD-column value as one-shot billboard text, so nothing refreshes them. Defaults confirmed in CVARINFO.txt: wr_inspect=true (1708), wr_inspect_dwell=18 (1713), wr_inspect_delta=true (1721). Not guarded anywhere: mInspectWpn is written only at 6493 and 7172; endInspect fires only on ring-open, inspect-off, dead/not-in-game, DoomInfinite suppression, or target-lost grace (6386/6393/6408/6453) - no weapon-change hook; clearPanels/rebuildPage (2630, 707, 8486) are gated on mOpen and cannot run while inspect is live. Player-observable at defaults with no hand motion: press a number key while the laser rests on a floor weapon and the HELD column, the "vs <name>" subtitle, and the green/red verdict all stay pinned to the weapon you no longer hold.

**Correction (supersedes Cause/Trigger above)**

Confirmed, with two corrections to scope. (1) The freeze variants are narrower than reported: in this merge a holster stow does not empty a hand - RS_HandFist seats a fist Weapon (zscript/hands/rs_fist.zs:125 and :189 set bOffhandWeapon/SisterWeapon on the seated fist), so `mine` stays non-null, wantCompare stays true, and stowing produces the STALE card (HELD column still showing the stowed gun), not the frozen one. The freeze paths require a genuinely null hand, i.e. an off hand with no fist seated (wheel/zscript.zs:8345 sets player.OffhandWeapon = null), which the code's own comment at 6474-6478 explicitly designs for. The mirror case (empty off hand builds the plain sheet, then a draw flips wantCompare true and layoutCompare returns at 7107) does survive the hand's trip to the holster, because mInspectCand is cleared only by endInspect. (2) The freeze duration is understated: mInspectTics increments unbounded at 6466 and the target-lost path decrements one per tic at 6452, so a frozen card hangs for as many tics as were accumulated during the dwell - many seconds after a long look - not wr_inspect_dwell (18) tics.

---

### 25. Every live countdown row on the data sheet is frozen at the value it had when the selector landed

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 1086-1103 (gate at 1098); same latch for inspect mode at 6491  
**Severity:** `broken-in-common-case`

**Symptom**

Rows that are explicitly countdowns or live meters never move while you look at them: "RELOADING 3s" (Lithium auto-reload, 1157), "DESPAWN 30s" (DOOM Infinite, 1708), "ACTIVE 12s" (1758), "SPELL CD 4.2s" (Guncaster, 1576), "OVERHEATED 18s" (Combined Arms, 1823), "DODGE 1.4s" (1284), "INVULN 0.8s" (1289), "FIRING 3s" (1962), plus HEAT/MANA/OVERCHARGE/HP/ARMOR meters. In inspect mode there is no lock timer at all, so a floor weapon's DESPAWN clock -- the row whose own comment calls it "the row with a deadline on it" -- sits at whatever second it read when the dwell completed, indefinitely.

**Cause**

refreshSheet() returns at 1098 whenever `mSheetValid && nowCls == mSheetShown`, i.e. it rebuilds only when the hovered weapon's CLASS changes. The comment above it (1393-1397) justifies this with "BB_TEXT carries its string at creation and UpdateBillboard cannot change it, so a text change means destroying and recreating the row billboards" -- which is no longer true: sheetRow() (2478-2488) restrings in place with level.SetBillboardText, and buildSheetRows' own header (1338-1344) says exactly that ("RESTRUNG, NOT REBUILT ... a hover change costs two calls per row"). The stale rationale left a per-class gate in front of a per-tic-cheap rebuild. Inspect mode has the identical latch at 6491 keyed on the actor.

**Trigger**

Defaults, with any compat mod that supplies a countdown row (Lithium, DOOM Infinite, Guncaster, Combined Arms, Final Doomer). wr_locktics 140 = 4s of hover on the ring; unbounded in inspect mode.

**Verification**

Verified independently in E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs.

(a) Lines confirmed. 1086-1103 is refreshSheet(); 1098 is literally `if (mSheetValid && nowCls == mSheetShown) return;` with nowCls = shown.GetClass() (1097). 6491 is `if (mInspectWpn != found)`, the same latch keyed on the actor, wrapping the only inspect-mode call to buildSheetRows (6506).

(b) No second refresh path exists. grep shows buildSheetRows called from exactly two sites (1102, 6506). setSheetBar (2466) is called only from inside buildSheetRows/lithiumRows (1174, 1204, 1722, 1824, 1834, 1951, 2051, 2107), so the gauge freezes too. level.SetBillboardText on the row pool occurs only in sheetRow (2486) and blankRestOfSheet (2268). layoutSheet (2521) and layoutInspect (7180-7193) only compute positions -- no restring, no recolour of rows. refreshSheet itself has exactly one caller, the tick at 7384.

(c) Not guarded. mSheetValid is assigned only at 1101 (true) and 2458-2459 (false, in buildSheet at ring construction). Nothing clears it per tic. mLockTics resets only when the hovered card CHANGES (8310-8317), never on continued dwell, so a stationary hover does not re-trigger anything.

(d) Arithmetic genuinely broken. wr_compat_doominfinite.zs:440-450 DespawnOf reads the live `internalSecond` field and returns ARENA_TIMEOUT(74) - elapsed = a real per-second countdown; its Ready() gate (89-95) checks only wr_di_compat and isSetup, NOT ownership, so it fires on the ownerless floor weapon that tickInspect requires (6431-6432). That value is sampled once at build and never re-read. Same for DODGE %.1fs (1284, liDodgeN/35.0), INVULN %.1fs (1289), SPELL CD %.1fs (1576), RELOADING %ds (1157), ACTIVE %ds (1758), OVERHEATED %ds (1823, caOver/70+1), FIRING %ds (1962, fdWbTics/35+1) -- all confirmed present and all formatted from a live counter.

(e) Player-observable, and the file's own comment convicts it: 1152-1155 describes the RELOADING row as "the one row here built for a WHEEL rather than a HUD: this ticks on a gun you are NOT holding" -- and it does not tick. 1702-1704 calls DESPAWN "the row with a deadline on it".

Defaults confirmed: wr_locktics 140 (939-940, 8314-8315) = 4s at 35 tics/s; wr_inspect_dwell 18 (6468). tickInspect (6380-6514) has no lock timer of any kind, so inspect-mode staleness is bounded only by how long the laser rests on the target.

Two inaccuracies in the report, neither load-bearing: the stale-rationale comment is at 393-397, not 1393-1397 (1393-1397 is an unrelated Doomablo comment) though the quoted text is verbatim correct at 393-397; and ring-mode staleness is bounded at 4s by mLockTics rather than open-ended, with the special case that hovering the READY weapon's own card never changes nowCls (since 1093-1095 falls back to ReadyWeapon when nothing is hovered), freezing the sheet for the rig's entire lifetime.

**Correction (supersedes Cause/Trigger above)**

Confirmed, with two corrections. (1) The stale rationale comment is at zscript.zs:393-397 (on the mSheetShown field declaration), not 1393-1397; the quoted text is otherwise verbatim. (2) Ring-mode staleness is bounded at 4 seconds, not unbounded: mLockTics defaults to 140 tics (939-940) and is reset only when the hovered card CHANGES (8312-8317), so a stationary hover closes the rig after 4s. Sweeping off a card and back does force a rebuild, because HoveredClass() falls back to ReadyWeapon (1093-1095) and that is a different class -- EXCEPT when the hovered weapon IS the ready weapon, where nowCls never changes and the sheet stays frozen for the rig's whole life. Inspect mode is the genuinely unbounded case as reported: tickInspect (6380-6514) has no lock timer, and wr_CompatDoomInfinite.DespawnOf (wr_compat_doominfinite.zs:440-450) reads a live per-second field with no ownership requirement, so a floor weapon's DESPAWN row sits at its dwell-completion value indefinitely.

---

### 26. Comparison card's row pool is 26 but the plate only holds 23 -- the last three rows draw below the card in mid-air

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 8862 (CMP_ROW_POOL), 8842-8845 (constants), 7129/7141-7152 (layout)  
**Severity:** `broken-in-edge-case`

**Symptom**

On a comparison card that fills past 23 rows, rows 24, 25 and 26 are drawn as free-floating text below the bottom edge of the plate, with no background behind them, while the pool comment promises they are "silently dropped ... a card that has genuinely run out of plate".

**Cause**

At defaults panelWNow()=4.2, panelHNow()=3.0, so h = 3.0 * CMP_H_CARDS(6.5) = 19.5 and rowH = 19.5 * CMP_ROW_FRAC(0.027) = 0.5265. layoutCompare starts rows at y = h*0.5 - h*CMP_ROWS_TOP(0.26) = 4.68 for the header, then steps rowH*CMP_ROW_PITCH(1.15) = 0.605475 per row. Row i sits at 4.074525 - i*0.605475; its bottom edge is 0.263 lower. The plate bottom is -9.75. Row index 22 (the 23rd) bottoms out at -9.509, inside. Row index 23 is centred at -9.851 -- entirely below the plate -- and indices 24 and 25 at -10.457 and -11.062. So the plate holds 23 rows, not 26. The sheet's own equivalent numbers WERE kept in step when SHEET_H_CARDS grew (28 rows plus the bar land at -12.04 against a -12.9 edge, 0.86 of margin); the compare card's CMP_ROW_POOL was picked from a content estimate ("8, always present, plus up to roughly a dozen merged per-mod rows", 8856-8861) instead of from CMP_H_CARDS/CMP_ROWS_TOP/CMP_ROW_FRAC/CMP_ROW_PITCH.

**Trigger**

Needs a comparison filling 24+ rows: 8 fixed rows (DPS/DAMAGE/ROF/MAG/PELLETS/AMMO/TIER/HANDS, 6630-6651) plus 16+ merged modRowsOf rows. Reachable when the floor weapon and the held weapon come from different mods (labels do not merge, each side gets its own row with "--", 6678-6695) or with 3+ gameplay mods stacked -- e.g. a rolled DOOM Infinite weapon (QUIRKS/LOADOUT/SPREAD/AMMO COST/JAM/LOCKED/OVERCHARGE/DESPAWN/HEAT) against a held weapon from another mod, plus the owner-side rows (Doomablo LVL/INFERNO/STATS, Pandemonia GAME LVL, MetaDoom KEYS) which only the OWNED weapon can answer and so never merge.

**Verification**

I read the cited code directly rather than trusting the report.

(a) LINES CHECK OUT. zscript.zs:8862 is `const CMP_ROW_POOL = 26;`. 8842-8845 are `CMP_H_CARDS = 6.5`, `CMP_ROW_FRAC = 0.027`, `CMP_ROWS_TOP = 0.26`, `CMP_ROW_PITCH = 1.15`. 7129 is `double rowH = h * CMP_ROW_FRAC;`, 7141 is `double y = top - h * CMP_ROWS_TOP;`, 7144/7151 are the two `y -= rowH * CMP_ROW_PITCH;` steps, 7146-7152 is `for (int i = 0; i < mCmpLabel.Size(); ++i)`. The eight fixed rows are at 6630-6634 (cmpStat DPS/DAMAGE/ROF/MAG/PELLETS), 6639 (AMMO), 6646 (TIER), 6651 (HANDS); the merge loop is 6678-6695 with `else cmpRow(la[i], va[i], "--", 0);` at 6690 and the unmatched-B pass at 6692-6695.

(b) DEFAULTS CHECK OUT. E:\mERGE\RS_VR_Unified\CVARINFO.txt:1025-1026 `wr_panel_w = 4.2`, `wr_panel_h = 3.0`; :1170 `wr_scale = 1.0`; :1721 `wr_inspect_delta = true`, so the compare card is the DEFAULT path (zscript.zs:6479 `wantCompare`). zscript.zs:4748-4749 confirm panelWNow()=4.2, panelHNow()=3.0. layoutCompare does NOT apply sheetScale(), so nothing else scales it.

(d) ARITHMETIC CHECKS OUT, and is stronger than reported: the capacity is scale-INVARIANT. In fractions of h: top = 0.5h; header y = 0.5h - 0.26h = 0.24h; step = CMP_ROW_FRAC*CMP_ROW_PITCH = 0.03105h; row half-height = 0.0135h. Row i is fully on the plate while 0.24 - 0.03105*(i+1) - 0.0135 >= -0.5, i.e. 0.03105*(i+1) <= 0.7265, i.e. i <= 22.398. Exactly 23 rows (i = 0..22) fit for EVERY value of wr_panel_h and wr_scale. At defaults h = 19.5, plate bottom -9.75, step 0.605475, row 22 bottom = -9.509 (inside), row 23 centre = -9.851 with its TOP edge at -9.588, entirely below the plate; rows 24 and 25 at -10.457 and -11.062. So the pool is 26 against a 23-row plate.

(c) NOT GUARDED ANYWHERE. cmpRow (6586) caps only `if (mCmpUsed >= mCmpLabel.Size()) return;` = 26. layoutCompare's loop runs to `mCmpLabel.Size()` (26), not mCmpUsed, so any filled row past 22 is positioned unconditionally. blankRestOfCompare (6604-6612) only blanks slots ABOVE mCmpUsed. The row text billboards are independent BB_TEXT entities (mkCmpText, 6553) with no clipping to mCmpPlate. I verified the plate's `h` is a FULL height, not a half-extent: layoutCompare uses `top = h*0.5` and puts the accent bar at `top - h*0.03` with height `h*0.02`, which only reads as "bar just under the top edge" if h is the full height.

The reporter's control claim about the sheet also holds: sheet rows give 0.29 - 0.02652*i - 0.0102 >= -0.5, i.e. i <= 29.4, so 30 slots against SHEET_ROW_POOL = 28 plus two bars. The sheet WAS kept in step; the compare card's pool was not.

(e) REACHABLE, at the top end. wr_compat_doominfinite.zs:89 `Ready()` requires only `isSetup`, NOT an owner, so a DOOM Infinite weapon lying on the floor really does emit its own mod rows; and wr_compat_doomablo.zs:166/188, wr_compat_pandemonia.zs:122 and wr_compat_metadoom.zs:58 all bail on `!w.Owner`, so LVL/INFERNO/STATS/GAME LVL/KEYS can only ever come from the HELD side and never merge, which is exactly the row-doubling the reporter describes. What a player sees: up to three label/value/value triplets floating in mid-air below the bottom edge of the comparison card, with no plate behind them, instead of the "silently dropped" behaviour the pool's own comment (8856-8861) promises.

**Correction (supersedes Cause/Trigger above)**

The finding stands; two refinements. (1) The 23-row capacity is not a defaults-only figure â€” it is fixed by CMP_ROWS_TOP/CMP_ROW_FRAC/CMP_ROW_PITCH alone and does not change with wr_panel_h or wr_scale, so no user setting can make the last three pool slots land on the plate. (2) The stated trigger overstates DOOM Infinite's contribution: of its nine possible rows, JAM needs the JAMMING quirk, OVERCHARGE needs altOverchargeValue > 0, DESPAWN needs arena internalSecond > 0 and HEAT needs a live overheatCounter, none of which a weapon lying on the floor normally has, so a rolled floor DI weapon realistically yields about five (QUIRKS/LOADOUT/SPREAD/AMMO COST/LOCKED). Reaching 24 filled rows therefore needs a genuinely heavy stack â€” e.g. an eight-row Pandemonia Insurrection weapon on the floor (AUG/TAG/DURA/SUPERIOR/COMBO/AEON plus base DURA/SIDEGRADE) against a Combined Arms weapon in hand (HEAT/RESOURCE/COOLDOWN/UPGRADE/EXPIRES/HIDDEN) with Doomablo's owner-only LVL/INFERNO/STATS on top â€” which is why "broken-in-edge-case" is the right severity.

---

### 27. Fan sub-cards use their visible plate as their own hit target, so the top and bottom of every sub-card is unclickable

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 3398-3404 (sub plate created hittable), 4037-4038 (sized panelW x panelH); contrast 5148-5153 and 6012-6014  
**Severity:** `broken-at-defaults`

**Symptom**

Inside an expanded fan the laser passes through the upper and lower edges of a sub-card without selecting it -- roughly the top 8% and bottom 8% of what you can see is dead, and there is no forgiving margin at the left and right edges either. Ring cards do not behave this way. It is worst exactly where it hurts most: a fan is where several near-identical clones sit at the minimum separation `need` allows (3899-3900).

**Cause**

The main ring builds a separate invisible hit quad (spawnPanels 5148-5153, alpha 0, flags 0) and sizes it at panelW*HIT_PAD (1.12) by panelH*CARD_STRETCH(1.2)*HIT_PAD in layout() 6013-6014, precisely because -- as the comment there states -- billboards draw 1.2x taller than authored while the hit query tests the authored extents, so "a quad that is both the picture and the target is hittable across only the middle 83% of what you can see". expandSlot creates the sub-card plate with flags 0 (hittable) at 3398-3401 and layoutExpansion resizes it to plain panelW x panelH at 4038 -- it IS both the picture and the target, with neither the CARD_STRETCH correction nor HIT_PAD. At defaults panelH 3.0 authored draws as 3.6, so 0.6 of 3.6 visible height (16.7%) has no hit coverage, split top and bottom. The three-part "A SUBCARD IS A CARD" parity pass (3353-3361, 3984-3988, 8615-8619) brought over the plate, dry colour, stripe, marker, label fit, glow, shadow, gauge and fade -- but not the hit geometry.

**Trigger**

Defaults. Any expanded fan: wr_subcards_max 10 exceeded (any weapon mod with more than ten guns), then dwell DWELL_TO_EXPAND=7 tics on a multi-weapon slot.

**Verification**

I read every cited line independently and all five checks pass.

(a) CITED LINES SAY WHAT IS CLAIMED â€” all verified in E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs:
- 3398-3401, sub-card plate creation: `level.AddBillboardPersistent((0,0,0), 3.5, 2.5, 0, 0, LevelLocals.BBF_FIXED, plateKind(), plateShape(), srest, 0, 0, "")`. The render-flags argument is literally `0`. Compare the sibling calls immediately around it â€” the sub shadow (3393), accent (3416), marker (3430), icon (3454), ammo (3476), gauge (3503) and label (3515) all pass `LevelLocals.BBFL_NOHIT` in that same position. `mSubIds` is therefore the ONLY hittable billboard in the whole fan, and it is also the visible plate.
- 4037-4038: `level.MoveBillboard(mSubIds[i], pos); level.ResizeBillboard(mSubIds[i], panelW * spulse, panelH * spulse);` â€” no CARD_STRETCH, no HIT_PAD. Grep confirms 4038 is the ONLY ResizeBillboard call on mSubIds in the file.
- 5148-5153: the ring's hit quad, created `COLOR_IDLE, 0, 0, ""` then `SetBillboardAlpha(id, 0)` â€” invisible and hittable, exactly as claimed, under a comment that states the mechanism verbatim ("a quad that is both the picture and the target is hittable across only the middle 83% of what you can see").
- 6012-6014: `ResizeBillboard(mIds[i], panelW * HIT_PAD, panelH * CARD_STRETCH * HIT_PAD)`.
- 3899-3900: `double need = 2.0 * asin(clamp(cellW / (2.0 * reach), 0.0, 1.0)); double sep = max(spread, need);` â€” the minimum-separation claim is accurate.

(b) DEFAULTS CORRECT â€” HIT_PAD = 1.12 (8653), CARD_STRETCH = 1.2 (8720), DWELL_TO_EXPAND = 7 (8656), wr_panel_w 4.2 / wr_panel_h 3.0 (5111-5112 and panelWNow/panelHNow 4748-4749), wr_subcards_max default 10 (3144). layoutExpansion is called at 6303-6304 with layout()'s own panelW/panelH, so at defaults the sub plate really is authored 4.2 x 3.0.

(c) NOT GUARDED ANYWHERE. I grepped for HIT_PAD, CARD_STRETCH, SUB_HIT, mSubHit and every use of mSubIds. There is no sub-card hit quad, no compensating array, and no CARD_STRETCH term anywhere in layoutExpansion. The structural asymmetry is explicit: the main VISIBLE plate is created `rest, LevelLocals.BBFL_NOHIT` at 5198-5201 and sized `panelW * pulse, panelH * pulse` at 6144 â€” identical sizing to the sub plate â€” but main gets a second, separately-sized hit quad and the fan does not. The two partial mitigations do not cover the laser: TouchBillboard (wr_touch 7.0, line 7468-7479) is hand-proximity only, and wr_subcards_grace 6 (8237) only stops the fan collapsing when you miss, which is precisely why the symptom is "nothing happens" rather than "the fan snaps shut".

(d) ARITHMETIC HOLDS. Authored 3.0 vs drawn 3.0 * 1.2 = 3.6; 0.6 / 3.6 = 16.7% of visible height with no hit coverage, 8.3% at each edge. Main ring by contrast hit-tests at 3.0 * 1.2 * 1.12 = 4.032 authored against a 3.6 visible plate â€” a real margin. spulse is 1.0 for every unhovered card (3991-4004), so the dead band is present on exactly the cards you are trying to acquire.

(e) PLAYER-OBSERVABLE at defaults: hold more than 10 admissible weapons (countAdmissible, 3042-3053), open the wheel, dwell 7 tics on a multi-weapon slot (or hit +use while hovering, 766-769, which expands instantly), then point at the top or bottom eighth of a sub-card and it does not light or select.

One premise I want to flag honestly rather than assert: the 1.2x render-stretch-vs-authored-hit-extents behavior is an engine fact asserted by this file's comments (5138-5143, 8718-8720), not something I could verify against UZDXREMA source from here. It is corroborated inside the codebase, though â€” fitIcon at 4511 and 4516 independently divides/multiplies by CARD_STRETCH to undo the same visual stretch, and the entire HIT_PAD architecture exists only because of it. If that premise were false the main ring's hit quad would be over-sized instead of correct, which the author explicitly designed against.

Minor refinement to the report's wording, not a refutation: the trigger is more than ten admissible weapons CURRENTLY HELD (countAdmissible sums slotWeapons across slots for the live pawn), not "any weapon mod with more than ten guns" â€” a big mod early in a level may still be flat. And the fan can be opened instantly with +use while hovering, so DWELL_TO_EXPAND is not the only path in.

**Correction (supersedes Cause/Trigger above)**

The finding stands as reported. Two small precision fixes to the trigger description: (1) fans enable when the player currently HOLDS more than wr_subcards_max=10 admissible weapons (countAdmissible at 3042-3053 counts live slotWeapons for the pawn), not when the mod's total roster exceeds ten â€” so a big mod early in a level can still be flat; (2) the fan does not require the 7-tic dwell â€” InputProcess at 766-769 expands the hovered slot instantly on +use, so the defect is reachable sooner than stated. Also worth adding to the fix note: mSubIds is the only non-BBFL_NOHIT billboard in the entire fan (every other sub element at 3393/3416/3430/3454/3476/3503/3515 passes BBFL_NOHIT), so the fix is to mirror the ring exactly â€” mark the sub plate BBFL_NOHIT and add a parallel invisible mSubHits array sized panelW*HIT_PAD x panelH*CARD_STRETCH*HIT_PAD, with subIndexOf() and belongsToExpansion() taught about the new ids.

---

### 28. mFansEnabled is never recomputed for the inventory or model page, so dwelling on an item card fans out slot-0 weapons

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 3058-3063 (dispatch), 3144 (only assignment), 3302-3316 (expandSlot), 8272-8285 (dwell trigger)  
**Severity:** `broken-in-edge-case`

**Symptom**

Page across to Inventory (or Models) and rest on a card for 7 tics: a fan of WEAPON cards pops out of your medikit/model card, with the expand flash and tick sound. They are hittable, they light up on hover, and selecting one does nothing at all -- commit() routes on mPage to commitInventory/commitModel, whose cardIndexOf(mHovered) returns -1 for a sub-card id and returns silently (8450-8451, 8466-8467). The fan will not collapse while you point at it (belongsToExpansion), so the player is stuck pointing at cards that cannot be picked.

**Cause**

mFansEnabled is assigned in exactly one place, gatherWeaponCards:3144. gatherWeapons() dispatches to gatherInventory/gatherModels for the other two pages (3060-3061) and returns before ever reaching it, so the flag carries over from the weapons page. gatherInventory:3083 and gatherModels:3117 both push mCardSlots = 0, so updateHover's dwell (8272) fires expandSlot, which calls slotWeapons(pmo, mCardSlots[cardIndex]=0, variants) at 3305 and builds a fan out of slot 0 whenever that slot holds two or more owned weapons. (gatherInventory and gatherModels also never Clear() the arrays gatherWeaponCards clears at 3128-3133 -- currently masked only because rebuildPage calls clearPanels() first.)

**Trigger**

mFansEnabled true, i.e. countAdmissible > wr_subcards_max (default 10) -- any weapon mod with more than ten guns -- plus a mod that puts two or more owned weapons in slot 0. Vanilla Doom leaves slot 0 empty, so this needs a mod that populates it.

**Verification**

I could not refute this; every cited line says what the reporter claims and I found no guard anywhere on the path.

(a) Cited lines verified verbatim:
- 3058-3063 gatherWeapons(): `if (mPage == PAGE_INVENTORY) { gatherInventory(pmo); return; } if (mPage == PAGE_MODELS) { gatherModels(pmo); return; } gatherWeaponCards(pmo);` â€” the two non-weapon pages return before gatherWeaponCards.
- 3144 is the ONLY assignment to mFansEnabled. I grepped the whole file: hits at 267 (declaration), 723, 776, 3144 (assign), 3177, 3266, 3275, 5402-5408, 8265, 8273 â€” every other one is a read.
- 3083 (gatherInventory) and 3116 (gatherModels) both `mCardSlots.Push(0)`.
- 3299-3316 expandSlot(): bounds-checks cardIndex against mCardSlots.Size() only, then `slotWeapons(pmo, mCardSlots[cardIndex], variants)` at 3305, `if (variants.Size() < 2) return;` at 3314. No mPage test anywhere in the function.
- 8272-8285 dwell: `if (mDwellTics == DWELL_TO_EXPAND && !belongsToExpansion(hit) && mFansEnabled)` â†’ expandSlot(pmo, cardIndexOf(hit)). Again no mPage test. DWELL_TO_EXPAND = 7 (line 8656).
- Commit routing: commit():8489-8492 dispatches on mPage; commitInventory():8450-8451 and commitModel():8466-8467 both `int index = cardIndexOf(mHovered); if (index < 0 ...) return;` â€” and cardIndexOf (3807-3814) searches mIds only, so a sub-card id returns -1 and the press is a silent no-op. HoveredClass():592-594 resolves the sub-card first, so the sub-card really is what the player has selected.

(b) Defaults correct: wr_subcards_max default 10 at 3144; DWELL_TO_EXPAND 7; wr_flash default true (3330) so the expand flash fires; the tick sound at 8283 fires because mSubIds actually grows. pageCount() (662-667) returns 2 without ModelSwapper, so the Inventory page is always reachable at defaults.

(c) Not guarded anywhere I could find. updateHover (8218) has no page gate. The tic path (7482) calls it unconditionally. spawnPanels (5094) is page-agnostic, so inventory cards get real hittable mIds. The sub-card billboards at 3398-3401 are created with flags `0`, NOT BBFL_NOHIT, so they are genuinely hittable; tintCard's sub branch (3792-3803) lights them on hover. layoutExpansion (3831) only checks mExpanded/mSubIds, so the fan is positioned and visible on any page. NetworkProcess's page handler (705-707) calls collapseSlot() â€” that closes an existing fan on a page flip but does nothing to stop a new one being opened afterwards. The +use instant-expand path (775-776, 723-724) is gated identically (mFansEnabled only), so it is a second door to the same state.

(d) Arithmetic/trigger works out: mPage is forced to PAGE_WEAPONS in openRig (902) immediately before gatherWeapons (904), so mFansEnabled is always computed once per open from the weapon page and then carried unchanged onto the other pages. countAdmissible (3042-3053) > 10 sets it. On the inventory/model page every mCardSlots entry is 0, so expandSlot fans slot 0; it needs slotWeapons(pmo, 0, ...) (3229-3248) to return >= 2 owned, hand-admissible weapons.

(e) Player-observable, in the narrow case the reporter states. I also checked the parenthetical: clearPanels() does clear mTypes/mCardLabel/mCardSlots/mCardColor/mSlotCount/mSlotAllDry at 2752-2757, and the only two callers of gatherWeapons are openRig:904 (page forced to weapons, so gatherWeaponCards clears at 3128-3133) and rebuildPage:2630-2634 (clearPanels first) â€” so the missing Clear() in gatherInventory/gatherModels is genuinely masked today, exactly as the reporter said, and slot values on those pages really are all 0 rather than stale weapon slots.

**Correction (supersedes Cause/Trigger above)**

Confirmed as written, with three refinements to the trigger and the symptom.

1. The trigger is a three-way conjunction, not two: (i) countAdmissible > wr_subcards_max (default 10) so mFansEnabled is true; (ii) slot 0 holding two or more owned, hand-admissible weapons (slotWeapons:3244 also drops bNoHandSwitch weapons bound to the other hand, so "owned" is not quite enough); AND (iii) the non-weapon page must actually have cards to dwell on â€” for Inventory that means at least one bInvBar, Amount>0 non-weapon item (3076-3079), and vanilla Doom has none at all, so the "medikit" in the symptom is not a vanilla Doom object; for Models it means ModelSwapper loaded and StateOf(hand).count > 0 (3109-3110). A mod with more than ten guns is exactly the kind that both overflows into slot 0 and ships inventory items, so the conjunction is reachable, but it is narrower than "any mod with more than ten guns".

2. There is a second door to the same broken state, not just the dwell: the +use instant-expand gesture (InputProcess:775-776 â†’ NetworkProcess wr_expand:723-724) is gated on exactly the same mFansEnabled && !belongsToExpansion(mHovered) and likewise never checks mPage, so a player who uses that gesture pops the same slot-0 fan out of an item card with no 7-tic wait.

3. "Stuck" is bounded rather than absolute. belongsToExpansion(hit) does keep the fan open while the laser is on it, but moving onto any other card runs the collapse grace at 8235-8241 and closes it after wr_subcards_grace (default 6) tics, and paging (706) or closing collapses it immediately. The player is not trapped; they are left with a fan of weapon cards that light up on hover and swallow every selection press silently.

---

### 29. Lozenge readout is sized from the separator string it cannot draw, so magazine weapons get a badge three times too wide

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 7864-7880 (readoutAspect), 4417-4428 (ammoText), 5312-5313 and 3469-3470 (call sites)  
**Severity:** `broken-in-edge-case`

**Symptom**

With Ammo readout set to "Lozenge badge" (MENUDEF.txt:1161, OptionValue wr_Readouts value 2), a magazine weapon's badge is drawn at 0.90 of the card width -- nearly edge to edge -- with a single small digit floating in the middle of it, while a non-magazine weapon showing the same one-digit count gets a badge only 0.54 of the card wide. Two cards showing "2" are drawn at wildly different sizes.

**Cause**

readoutAspect takes `int chars = max(text.Length(), 1)` at 7866 from ammoText's full string. BB_WG13 reads its number out of `data` and never renders `text` at all -- the function's own comment at 7870-7872 says so ("it takes DIGITS -- a badge showing a separator is not a case it has, so the separator is not counted") -- but nothing in the code strips it. ammoText returns "%d|%d" for every weapon with a magazine reserve or a separate alt-fire pool (4423, 4427), so "8|112" gives chars=6 and min(0.22*1.2*(0.60+6*0.42)*2.0, 0.90) saturates at the 0.90 ceiling, against 0.264*1.02*2 = 0.539 for a genuine one-digit count. The segment path (default) is unaffected because BB_SEGMENT actually draws the whole string.

**Trigger**

wr_readout 2 (a normal menu choice, not the default 0) plus any magazine-based weapon mod (RS_Main, DOOM Infinite, Lithium, BorderDoom, Pandemonia) -- i.e. essentially every mod this wheel ships compat for.

**Verification**

I read all cited code independently and every load-bearing element checks out.

(a) Lines say what is claimed. zscript.zs:7864-7891 readoutAspect(string text) opens with `int chars = max(text.Length(), 1);` at 7866. The WG13 branch at 7868-7880 returns `min(AMMO_H_FRAC * CARD_STRETCH * (0.60 + chars * 0.42) * 2.0, 0.90)` at 7879, and its own comment at 7870-7872 states the rule "takes DIGITS -- a badge showing a separator is not a case it has, so the separator is not counted." Nothing in the function strips or replaces the separator; `chars` is the full string length. ammoText at 4417-4428 returns "%d|%d" at 4423 (magazine reserve) and at 4427 (alt-fire pool), "%d" only at 4426.

(b) Defaults/constants are correct. zscript.zs:8720 CARD_STRETCH = 1.2, 8759 AMMO_H_FRAC = 0.22, 8760 AMMO_W_FRAC = 0.52. CVARINFO.txt:1408 `user int wr_readout = 0;`. MENUDEF.txt:1161 exposes it via OptionValue wr_Readouts (1426-1431) with `2, "Lozenge badge"`. readoutKind() at 7851 reads cv("wr_readout", 0.0) and maps case 2 -> BB_WG13 at 7854.

(c) Not guarded anywhere. grep over all of zscript/ shows exactly two callers of readoutAspect (3470, 5313), both fed directly by ammoText (3469, 5312), and no other producer of the readout string. wr_gunhud.zs never uses WG13 (421-422: SEGMENT/SEGLCD only), so there is no alternate path. The min(...,0.90) is a ceiling, not a fix -- it is the thing the wrong char count saturates against. The width is used raw: level.ResizeBillboard(mAmmos[i], panelW * mAmmoW[i] * pulse, panelH * AMMO_H_FRAC * pulse) at 6284-6285, and the fan twin at 4091-4092. Height is fixed; only width varies.

(d) The arithmetic breaks. WG13 takes its number in `data`, which is `rounds` (5317, 3474) -- confirmed by the param order against the BB_TEXTURE call at 5283-5286 -- so it renders 1-2 digits while being sized from the whole string. One drawn digit should give 0.22*1.2*(0.60+1*0.42)*2.0 = 0.5386. Saturation happens at chars >= 3 (needs 0.60+0.42c >= 0.90/0.528 = 1.7045, i.e. c >= 2.63), and every separator string is at least 3 chars, so every such weapon lands on the 0.90 ceiling regardless of the actual count drawn.

(e) Player-observable. With wr_readout 2, two cards each showing the digit 8 are drawn at 0.90 vs 0.5386 of card width. The function's own comment at 7862-7863 says the ratio exists "so a three-digit count gets a wider badge than a one-digit one instead of both being stretched into the same box" -- i.e. the payload stretches its glyphs to the quad, so the magazine weapon's single digit is drawn ~1.67x horizontally distorted inside a near-card-wide plate. Confirmed, subject to the corrections below.

**Correction (supersedes Cause/Trigger above)**

Three details in the report are wrong; none of them rescue the code.

1. Magnitude is overstated. The headline says "three times too wide"; the actual ratio is 0.90 / 0.5386 = 1.67x. The SYMPTOM body's own numbers (0.90 vs 0.54) are right -- only the headline is not.

2. Char count is off by one. "8|112" is 5 characters, not 6. min(0.22*1.2*(0.60+5*0.42)*2.0, 0.90) = min(1.4256, 0.90) = 0.90; with 6 it would be min(1.647, 0.90) = 0.90. Same saturated result, so the conclusion is unaffected, but the cited expression is wrong.

3. Scope is misstated. It is not specifically "magazine weapons": ammoText's other separator branch at 4427 (hasSecondAmmo -- a distinct Ammo2 *with* an AltFire state, which hasMagazine at 4397 explicitly excludes) produces the same "%d|%d" and hits the same ceiling. The real trigger is any weapon with an Ammo2 distinct from Ammo1, magazine or alt-fire. Conversely, vanilla single-ammo weapons are affected only in the intended way: a 3-digit count such as a backpacked chaingun's 100+ also clamps to 0.90, but there the badge genuinely is showing 3 digits, so that is the ceiling doing its documented job, not the defect.

Corrected statement: readoutAspect's WG13 branch (zscript.zs:7866, 7879) sizes the lozenge from text.Length() of ammoText's full string, but BB_WG13 renders only the `data` value (`rounds`, passed at 5317 and 3474) and never the string. Any weapon with a distinct Ammo2 -- via the magazine branch at 4423 or the alt-fire branch at 4427 -- yields a string of 3+ characters, which saturates the 0.90 ceiling, so its badge is drawn 0.90 of card width while showing the 1-2 digits that warrant 0.539-0.65. With wr_readout 2 (MENUDEF.txt:1161, "Lozenge badge"), those cards' badges are ~1.67x too wide and their digits correspondingly stretched next to a vanilla weapon's badge showing the same count.

---

### 30. Every on-gun readout menu option and all twenty placement binds are inert -- wr_GunTag is not registered

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_gunhud.zs`  
**Line:** 35 (class wr_GunTag : EventHandler); registration list at MAPINFO.txt:82; menu at MENUDEF.txt:1096-1119 and 1248-1253; binds at KEYCONF:170-194  
**Severity:** `latent`

**Symptom**

Nothing in the whole file can run. Toggling "Show it" / "On the off-hand weapon too" / "LCD instead of LED" / "Which side of the gun", or moving the Glow / Fallback forward-left-up-width-height sliders, changes nothing; the Placement tool submenu, its wr_place / wr_lock / wr_measure / wr_save binds and all sixteen wr_nudge aliases produce no console output and no ghost cursor, because NetworkProcess is never reached. The whole "gun's own readout" page and the two-point calibration it documents are dead UI.

**Cause**

MAPINFO.txt:82's AddEventHandlers list registers thirteen handlers and deliberately omits wr_GunTag (MAPINFO.txt:62-68 carries the decision forward verbatim: "the readout does not work"). But KEYCONF and MENUDEF still ship the full control surface for it, so the omission is invisible to the player and reads as the options being broken rather than absent. Noted here because the review brief asked about this file's 16-segment readout and its two-point calibration: it has no player-facing behaviour at all to have defects in. (Latent, if it is ever registered: mCalClass/mCalF..mCalH are fields on a plain per-level EventHandler, so every placement stored by wr_save via calStore (225-243) is destroyed at each map change and the weapon silently reverts to the wr_gun_f/l/u/w/h fallback -- which is why savePlacement PRINTS a line to paste into builtinCalibration() rather than relying on the table.)

**Trigger**

Defaults, unconditionally -- the file is unreachable in every configuration.

**Verification**

CONFIRMED. Every leg of the claim checks out, and I tried three separate ways to refute it and failed.

(a) Cited lines say what is claimed.
- E:\mERGE\RS_VR_Unified\MAPINFO.txt:82 is a single GameInfo AddEventHandlers list containing exactly thirteen names: RS_HandsAlwaysOn, RS_HandWorldHandler, RS_GrabPolicy, RS_GrabHandler, RS_Swing, RS_Held, RS_Pull, RS_Route, RS_GrabViz, RS_HolsterManager, RS_HardPointManager, RR_Reload, wr_Rig. wr_GunTag is absent. MAPINFO.txt:61-68 carries the "the readout does not work" decision forward verbatim, as quoted.
- E:\mERGE\RS_VR_Unified\zscript\wheel\wr_gunhud.zs:35 is `class wr_GunTag : EventHandler`, and it is the ONLY class/struct/mixin in the 723-line file (grep for ^class/^struct/^mixin returns one hit). Its entire behaviour hangs off overrides that only a registered handler receives: OnRegister (684), WorldTick (689), WorldUnloaded (700), NetworkProcess (707, which is the sole dispatcher for wr_place / wr_lock / wr_measure / wr_save / wr_nudge).
- KEYCONF:170-194 is exactly the four `netevent` aliases plus four addmenukey rows plus sixteen `wr_nudge` aliases = twenty binds. MENUDEF.txt:1096 is the "The gun's own readout" section header, 1099-1118 the eight options/five sliders, 1119 the `Submenu "  Placement tool...", wr_Place`, and 1240-1263 the wr_Place page with its four Control rows. The page is reachable without a console: MENUDEF.txt:969-970 add `Submenu "RSVR HUD", wr_Options` to both OptionsMenu and OptionsMenuSimple.

(c) Not guarded or handled elsewhere. I searched the whole tree for any other registration path: no `EventHandler.Register` / `StaticEventHandler` registration call anywhere (only three OnRegister overrides, one of which is wr_gunhud's own); no reference to `wr_GunTag` outside the file except comments in MAPINFO.txt:64, zscript.zs:2-4 and wr_stattracker.zs:220; zscript.txt:108 only #includes the file so it compiles. There is no second MAPINFO/ZMAPINFO lump â€” the built RS_VR_Unified.pk3 contains exactly one MAPINFO.txt, and I extracted it: its AddEventHandlers line is byte-identical to the loose one, still without wr_GunTag.

(d)/(e) The result is player-observable, not theoretical. I grepped every .zs for `wr_gun` and there is no consumer outside wr_gunhud.zs, so all thirteen menu rows and twenty binds drive cvars nothing reads. I also checked the two "16-segment" hits in zscript.zs (4412, 5298) in case the rig drew its own on-gun readout â€” both are the wheel CARD's BB_SEGMENT ammo bezel, not a second gun readout. And CVARINFO.txt:1739 sets `user bool wr_gun = true` (with wr_gun_offhand true), so at stock defaults the menu reports the on-gun readout as ON while no readout exists on either weapon; toggling "Show it" off and on changes nothing.

Latent sub-claim also correct: `EventHandler` (not `StaticEventHandler`) is the per-map class, so mCalClass/mCalF..mCalH (73-76) are rebuilt every map; builtinCalibration() (628-630) is empty; savePlacement (600-614) calls calStore then prints a `cal(...)` line to paste, exactly as the reporter describes.

Only nits, neither affecting the finding: the menu options begin at MENUDEF.txt:1099 rather than 1096 (1096 is the gold section header), and MAPINFO's own header comment at line 5 says "15 handlers" while the list holds 13 (and names StartLoadout in the rationale at line 23, which is likewise absent) â€” that discrepancy is the file's, not the reporter's.

**Correction (supersedes Cause/Trigger above)**

Claim stands. One refinement to its own severity label: because CVARINFO.txt:1739 defaults wr_gun = true (and wr_gun_offhand = true), this is not purely latent â€” at stock defaults the menu asserts the on-gun readout is enabled while wr_gunhud.zs never runs, so the player sees no readout on either weapon and every one of the thirteen menu rows and twenty binds is silently inert. Precise menu span is MENUDEF.txt:1099-1119 (1096 is the section header).

---

## Wheel - Stat Resolver & Tracker

### 31. Observed PELLETS can never report â€” pelletRun is hard-capped at 1, so the row never draws and observed DPS is ~7x low for shotguns

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_stattracker.zs`  
**Line:** 426-433 (increment + consume), 326-327 (roll-up), 553-560 (reader)  
**Severity:** `broken-at-defaults`

**Symptom**

The PELLETS field never appears on the data sheet or in the side-by-side compare view for any weapon that is not an RS Weapon roll or a DOOM Infinite gun â€” every shotgun from BorderDoom, Lithium, Combined Arms, Pandemonia, DRLA, Guncaster, vanilla Doom, and every mod that did not exist when this was written. As a knock-on, the DPS row for those same shotguns is computed with 1 pellet: a vanilla-style 7-pellet shotgun prints roughly one seventh of its real DPS, an SSG one twentieth, and the DAMAGE row shows a single pellet's roll (5-15 for a vanilla shotgun) as if it were the shot's damage.

**Cause**

pelletRun is incremented at exactly one place, line 427, under the guard `if (s.pendingHitUntilTic > 0 && level.maptime <= s.pendingHitUntilTic)`. Four lines later, line 430 tests the SAME guard and line 433 sets `s.pendingHitUntilTic = 0`. So the first damage event of a shot raises pelletRun 0->1 and then closes the window; the second, third and eighth pellet of the same blast all see pendingHitUntilTic == 0 and fail the line-426 guard. pelletRun therefore only ever holds 0 or 1, line 326 rolls at most 1 into pelletMax, and PelletsOf's `if (best < 2) return false, 0;` (line 558) is unconditionally true. The window the pellet counter needs is the shot's own 12-tic span; the flag it actually reads is the hit-credit token, which is deliberately single-use ('Consumed by the first damage event that lands inside it', line 107-109). The pellet loop needed its own `level.maptime <= s.lastFireTic + HIT_WINDOW` test rather than sharing the consumable one. Downstream: wr_stats.zs:206-208 gets false, Pellets() returns SRC_UNKNOWN, zscript.zs:2155 (`pSrc != SRC_UNKNOWN && pel > 1`) never fires, and wr_stats.zs:328 `if (pel < 1) pel = 1;` silently makes Dps multiply by 1.

**Trigger**

DEFAULTS, no unusual settings. Any multi-pellet weapon from any mod other than RS Weapon or DOOM Infinite, fired any number of times, at any range, with wr_stats_track = true (default) and wr_sheet_stats = true (default).

**Verification**

CONFIRMED. I read E:\mERGE\RS_VR_Unified\zscript\wheel\wr_stattracker.zs, wr_stats.zs and the relevant zscript.zs regions independently.

(a) Lines are as cited. wr_stattracker.zs:426-427 increments s.pelletRun under `if (s.pendingHitUntilTic > 0 && level.maptime <= s.pendingHitUntilTic)`. Lines 430-433 test the identical guard and then execute `s.hits++; s.pendingHitUntilTic = 0;`. The increment textually and temporally precedes the consume inside the same WorldThingDamaged invocation. Line 326-327 is `if (s.pelletRun > s.pelletMax) s.pelletMax = s.pelletRun; s.pelletRun = 0;`. Lines 557-558 are `int best = s.pelletMax > s.pelletRun ? s.pelletMax : s.pelletRun;` / `if (best < 2) return false, 0;`.

(b) Defaults correct: CVARINFO.txt:1729 `user bool wr_stats_track = true;`, CVARINFO.txt:1533 `user bool wr_sheet_stats = true;`.

(c) Not handled anywhere else. Repo-wide grep for pellet shows s.pelletRun written in exactly two places (427 increment, 327 reset); no second writer, no duplicate copy of the file. wr_stats.zs:189-211 Pellets() has only three sources: RS PelletCount field, wr_CompatDoomInfinite.PelletsOf, then wr_StatTracker.PelletsOf. No other compat file exposes a pellet count â€” Lithium's ShrapnelOf is a separate dedicated row (zscript.zs:1246-1248) for one weapon's charge level, not a Pellets() source. So BorderDoom, Combined Arms, Pandemonia, DRLA, Guncaster, FinalDoomer, MetaDoom and vanilla all fall through to the broken observed path.

(d) Arithmetic breaks as claimed. First damage event of a blast: 426 passes -> pelletRun 0->1; 430 passes -> hits++, pendingHitUntilTic=0. Pellets 2..N of the same blast are in the same tic and see pendingHitUntilTic==0, failing both guards. pelletRun is therefore always 0 or 1, pelletMax always 0 or 1, best<2 always true, PelletsOf always returns false. I also checked the alternate tick ordering (pellets landing before WorldTick arms the window): pelletRun is still 0 or 1. There is no path to 2. Downstream: zscript.zs:2155 `pSrc != SRC_UNKNOWN && pel > 1` never fires so the PELLETS half of the ROF row never draws; wr_stats.zs:328 `if (pel < 1) pel = 1;` then makes Dps (line 339) return dlo*1*rps / dhi*1*rps. Damage for these weapons also comes from the tracker (wr_stats.zs:113-115), and the tracker samples e.Damage per damage EVENT i.e. per pellet (wr_stattracker.zs:398-407, deliberately outside the hit-window guard), so DAMAGE is a per-pellet 5-15 and DPS is ~1/7 of a 7-pellet shotgun's real DPS, ~1/20 for an SSG.

(e) Player-observable. zscript.zs:2113-2117 draws the DPS row whenever dpsSrc != SRC_UNKNOWN, which it is (SRC_OBSERVED) after a handful of shots with default cvars. The compare view calls the same functions (zscript.zs:7023 for Dps, 7053-7057 for Pellets via cmpStat at 6634), so the PELLETS compare row shows 0/-- for both weapons and the DPS comparison is wrong by the pellet factor on both sides.

Unverified aside (reasoning, not tested): the suggested fix of giving the pellet loop its own `level.maptime <= s.lastFireTic + HIT_WINDOW` test may still under-count if GZDoom runs EventHandler.WorldTick after thinkers, since lastFireTic would be stamped the tic after the pellets landed. I did not confirm engine tick ordering. This does not affect the finding â€” pelletRun is capped at 1 under every ordering.

---

### 32. Two weapons sharing an ammo pool make every trigger pull stamp both hands with the same lastFireTic, so attribution returns null forever â€” kills, hits and headshots stay at zero while SHOTS double-counts

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_stattracker.zs`  
**Line:** 268-269 (both hands each tic), 289 + 306-314 (shared-pool drain seen by both), 337 (same stamp), 358 (tA == tB bails)  
**Severity:** `broken-in-common-case`

**Symptom**

Hold two weapons that draw from the same ammo pool â€” vanilla Doom pistol + chaingun (both Clip), shotgun + SSG (both Shell), plasma rifle + BFG (both Cell), or any pair of identical guns, which is the flagship use of this dual-wield rig â€” and the sheet reads "KILLS 0  SHOTS <2N>  ACC 0%" permanently for both. The DAMAGE and DPS rows never appear at all, HEADSHOTS stays 0 with the mod loaded, and SHOTS counts double: one trigger pull adds a shot to BOTH guns.

**Cause**

WorldTick (268-269) calls trackFire for ReadyWeapon and then OffhandWeapon in the same tic. Weapon.Ammo1 is a pointer to the player's single Inventory item of that ammo class, so two same-ammo weapons read the identical `a1` at line 289 and compute the identical `down1` at line 306. The band test at line 314, `(down1 > 0 && down1 <= use1 * 2)`, passes for both: firing the 1-shell shotgun gives down1 = 1, inside the shotgun's band 1..2 and inside the SSG's band 1..4 (use1 = w.default.AmmoUse1, 1 and 2 respectively); firing the SSG gives down1 = 2, still inside both. So both records take `s.shotsFired++` (321) and both take `s.lastFireTic = level.maptime` (337) with the SAME value. attributedWeapon then hits line 358 `if (tA == tB) return null;` on every subsequent damage/death/marker event, and WorldThingDamaged (370), WorldThingDied (447) and WorldThingSpawned (464) all return early. Because damageSamples is never incremented, wr_stats.zs:114 gets false from DamageOf, Damage() returns SRC_UNKNOWN, and Dps() bails at wr_stats.zs:324 â€” so those two rows vanish entirely. The same-tic rule was written for the rare case of both triggers pulled simultaneously (file header, lines 22-31); the shared ammo pool makes it fire on every shot from either hand.

**Trigger**

DEFAULTS. Any two simultaneously-held weapons whose Weapon.Ammo1 resolves to the same Inventory item. In vanilla Doom alone that is pistol+chaingun, shotgun+SSG, and plasma+BFG; in practice also any two copies of the same gun.

**Verification**

I read E:\mERGE\RS_VR_Unified\zscript\wheel\wr_stattracker.zs in full, plus wr_stats.zs, zscript.zs:1985-2190, CVARINFO.txt, and RS_Holsters.zs:2065-2105, and grepped the whole tree for other writers/readers of lastFireTic.

(a) LINES ARE VERBATIM AS CLAIMED. 268-269 are `trackFire(pawn, pawn.player.ReadyWeapon);` / `trackFire(pawn, pawn.player.OffhandWeapon);` in the same WorldTick. 289 is `int a1 = w.Ammo1 ? w.Ammo1.Amount : 0;`. 306 is `int down1 = s.lastAmmo1 - a1;`. 314 is `bool fired = (down1 > 0 && down1 <= use1 * 2) || (down2 > 0 && down2 <= use1 * 2);`. 337 is `s.lastFireTic = level.maptime;`. 358 is `if (tA == tB) return null;`. 321 is `s.shotsFired++;`. attributedWeapon is called at 370/447/464 with an unconditional `if (!w) return;` at 371/448/465. wr_stats.zs:114 is the `DamageOf` fallback and wr_stats.zs:324 is `if (dsrc == SRC_UNKNOWN) return SRC_UNKNOWN, 0, 0;` inside Dps. All exact.

(b) DEFAULTS CHECK OUT. CVARINFO.txt:1729 `user bool wr_stats_track = true;` â€” tracking is on by default, so active() is true. Vanilla AmmoUse1: Pistol 1, Chaingun 1, Shotgun 1, SSG 2, PlasmaRifle 1, BFG9000 40. Weapon.Ammo1 is the pointer to the owner's single Ammo inventory item, so two weapons with the same AmmoType1 read the identical `a1`.

(c) NOT GUARDED ANYWHERE. `lastFireTic`, `attributedWeapon`, `wr_StatLedger` and `wr_WeaponStats` appear nowhere else in the repo except two comment lines in MAPINFO.txt/zscript.txt. There is no second attribution path, no per-hand disambiguation, no reset. The per-weapon `lastAmmo1` baselines cannot diverge: both are rewritten to the same shared `a1` at line 316 every tic both weapons are held, so `down1` is bit-identical for both records.

(d) THE ARITHMETIC BREAKS. Shotgun+SSG on one Shell pool: fire the shotgun, down1 = 1, which passes the shotgun's band (1..2) and the SSG's band (1..4); fire the SSG, down1 = 2, which still passes both (2 <= 1*2). Both records take shotsFired++ and both stamp lastFireTic = level.maptime with the same value, so tA == tB on every subsequent damage/death/HS_Marker event and all three handlers return at 371/448/465. damageSamples stays 0, so DamageOf returns false, Damage() returns SRC_UNKNOWN, and zscript.zs:2119-2126 omits the DAMAGE row; Dps bails at wr_stats.zs:324 and 2115-2116 omits the DPS row. Same for pistol+chaingun on Clip (both use1 = 1).

(e) PLAYER-OBSERVABLE AND COMMON. zscript.zs:2005 draws `KILLS %d  SHOTS %d  ACC %d%%` literally, and statRows draws a second `HIT RATE 0%` row from the SRC_OBSERVED accuracy path. The mod's own RS_Holsters.zs:2075-2090 states outright that "a gun in EVERY hand is the baseline" and "In the ordinary case the two hands share an ammo pool anyway (two pistols, one Clip)" â€” the reporter's trigger case is the configuration the codebase itself calls ordinary. I could find no reason this is theoretical.

**Correction (supersedes Cause/Trigger above)**

The finding stands; three details need tightening.

1. PLASMA+BFG IS ONLY HALF-BROKEN, not fully. BFG9000's AmmoUse1 is 40, so a BFG shot gives down1 = 40, which fails the plasma rifle's band (1..2) â€” only the BFG stamps, tA != tB, and BFG kills/hits/damage ARE attributed correctly. Plasma shots (down1 = 1) fall inside the BFG's band (1..80) and stamp both. So that pair loses all plasma attribution and intermittently recovers BFG attribution. Pistol+Chaingun (both use1 = 1) and Shotgun+SSG (1 and 2, and 1 <= 2 either way) are the fully-dead pairs.

2. "ANY PAIR OF IDENTICAL GUNS" NEEDS A CAVEAT. GZDoom weapons are MaxAmount 1 and GiveInventory on an already-owned class returns the existing instance, so a plain pickup cannot produce two instances of one class. This rig does create duplicates deliberately (rs_fist.zs spawns a second fist via Actor.Spawn + AttachToOwner, and its comment notes the mod's own starting loadout "spawns one instance PER HAND"), so identical-gun pairs are reachable here â€” but through this mod's machinery, not through vanilla pickup.

3. "SHOTS <2N>" IS THE EVEN-USE CASE. Each weapon's shotsFired becomes the SUM of both hands' trigger pulls, so it reads 2N only when both hands fire equally; fire the chaingun 100 times and the pistol twice and both guns read 102.

Two consequences worth adding: the sheet also prints a second permanently-zero row, `HIT RATE 0%` (wr_stats.zs:179 Accuracy resolving to SRC_OBSERVED with hits = 0), and the PELLETS half of the ROF row disappears too, because pelletRun is only incremented at line 427 inside the same handler that returns early. The ROF row still works, since rofEma is computed in trackFire and never touches attribution.

---

### 33. MAG row prints two different ammo pools as numerator and denominator â€” the tracker's magazine test is the third copy of hasMagazine and is missing the alt-fire exclusion the other two got

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_stattracker.zs`  
**Line:** 296  
**Severity:** `broken-in-common-case`

**Symptom**

For any weapon with an AltFire state and a distinct Ammo2, the sheet's MAG row (zscript.zs:2170) reads a nonsense pair like "MAG 187 / 12" â€” 187 primary rounds over a capacity of 12 grenades â€” with the numerator routinely larger than the denominator. On a real magazine weapon that also has an alt fire it reads the backpack reserve over the magazine size, e.g. "MAG 187 / 30".

**Cause**

Line 296 is `if (w.Ammo2 != null && w.Ammo1 != w.Ammo2 && a2 > s.magHigh) s.magHigh = a2;` â€” a two-part test. The authoritative version, wr_Rig.hasMagazine at zscript.zs:4394-4399, is a three-part test that adds `if (hasAltFire(w)) return false;`, because Ammo2 is overloaded (a magazine on one weapon, a separate alt-fire pool on another). That fix was propagated to the second copy, wr_gunhud.zs:291-296, whose own comment at lines 280-285 says outright "This copy never got the alt-fire exclusion that one did, so a Rockets/Grenades-style weapon ... read its alt-fire reserve as the gun's own magazine here". wr_stattracker.zs:296 is a third copy still in the pre-fix form. The two halves of the printed row are then computed by the two different tests: zscript.zs:2170 formats `ammoLoaded(w)` over `cap`, where ammoLoaded (4459-4463) uses the three-part hasMagazine and so returns w.Ammo1.Amount for an alt-fire weapon, while cap comes from wr_Stats.Magazine -> wr_StatTracker.MagazineOf -> magHigh, the high-water of w.Ammo2.Amount. Numerator from Ammo1, denominator from Ammo2.

**Trigger**

DEFAULTS. Any weapon with an AltFire state and an AmmoType2 different from AmmoType1, once carried long enough for one WorldTick to record the high-water (immediately). Reached whenever the weapon is not answered earlier by wr_Stats.Magazine's declared sources (RS Weapon, BorderDoom, Pandemonia) â€” i.e. DRLA, Combined Arms, Guncaster, Lithium, MetaDoom, LegenDoom and plain unmodded weapons.

**Verification**

I read every cited line myself and the chain holds end to end.

VERBATIM CHECK. wr_stattracker.zs:296 is exactly `if (w.Ammo2 != null && w.Ammo1 != w.Ammo2 && a2 > s.magHigh) s.magHigh = a2;` â€” a two-part test inside trackFire(), with a2 = w.Ammo2.Amount (line 290). wr_Rig.hasMagazine at zscript.zs:4394-4399 is the three-part test with `if (hasAltFire(w)) return false;` (hasAltFire at 4387-4390 = `w.FindState('AltFire') != null`). wr_gunhud.zs:291-296 is the second copy, fixed by taking `hasAlt` as a parameter; its comment at 280-285 says verbatim that it "never got the alt-fire exclusion that one did, so a Rockets/Grenades-style weapon ... read its alt-fire reserve as the gun's own magazine here" â€” the author's own record that this weapon class exists and produced a visible defect. zscript.zs:296 in wr_stattracker is therefore the third, still-unfixed copy. Grep confirms exactly one wr_Rig.hasMagazine and one ammoLoaded; no shadowing.

CHAIN. zscript.zs:2165-2170: `[mSrc, cap] = wr_Stats.Magazine(w);` then `sheetRow(String.Format("MAG %d / %d", ammoLoaded(w), cap), SHEET_TEXT)`. ammoLoaded (4459-4463) calls the THREE-part hasMagazine, so for an alt-fire weapon it returns ammoLeftRaw(w) = w.Ammo1.Amount (4485-4489). cap comes from wr_Stats.Magazine (wr_stats.zs:222-248), which consults only isRS Capacity, BorderDoom bdClip, and Pandemonia magMax before falling to wr_StatTracker.MagazineOf (wr_stattracker.zs:542-547), which returns magHigh unless it is <= 0. magHigh is set by the TWO-part test. Numerator from Ammo1, denominator from Ammo2. Confirmed.

NO GUARD. Nothing clamps or cross-checks. wr_CompatLithium.MagazineOf exists (wr_compat_lithium.zs:310) but is NOT wired into wr_Stats.Magazine â€” only into zscript.zs:1137 â€” so Lithium falls through to the tracker as well, which if anything widens the reach. Both lines 2050 and the tracker's active() gate read cvars that CVARINFO.txt:1533 and :1729 declare `= true`. The comment at zscript.zs:2038-2042 states outright that the stat rows now run for every weapon, not only RS Weapon's.

BOTH classes of misread are real. (1) Alt-fire weapon with a genuinely separate Ammo2 pool: numerator = primary reserve, denominator = high-water of the alt pool, an unrelated pair. (2) Magazine weapon that also has an alt fire: hasMagazine returns false on it, so the numerator becomes the backpack reserve while the denominator is the true magazine size â€” the exact "MAG 187 / 30" shape described.

ONE THING THE REPORT UNDERSTATES, which I verified independently: because the tracker's two-part test admits any weapon with a distinct non-null Ammo2, magHigh becomes non-zero for weapons that HAVE NO MAGAZINE AT ALL. wr_Stats.Magazine then returns SRC_OBSERVED, so the MAG row is printed where it should not exist at all â€” not merely printed with a wrong denominator.

I could not refute this on any of (a) through (e).

**Correction (supersedes Cause/Trigger above)**

The defect is confirmed as stated; two reachability details in the report are wrong and should be tightened.

1. "plain unmodded weapons" is wrong. No vanilla Doom weapon has an AltFire state, and none has a distinct AmmoType2, so on unmodded Doom w.Ammo2 is null, magHigh stays 0, MagazineOf returns false, and no MAG row is printed at all. Vanilla weapons are unaffected. The trigger requires a mod-defined weapon with both an AltFire state and an AmmoType2 different from AmmoType1.

2. "immediately" overstates the trigger slightly. magHigh only becomes non-zero once the weapon is in a hand (trackFire runs only for ReadyWeapon and OffhandWeapon, wr_stattracker.zs:268-269) during a tic where Ammo2.Amount > 0. A player who has never picked up any alt-fire ammo for that gun sees no MAG row. In practice this is the first tic after acquiring one round of alt ammo.

3. Add to the symptom: the row's mere PRESENCE is also wrong, not only its numbers. On an alt-fire weapon with no magazine whatsoever, the two-part test at wr_stattracker.zs:296 manufactures an observed "capacity" out of the alt-fire pool, so wr_Stats.Magazine reports SRC_OBSERVED and the sheet prints a MAG row for a gun that has no magazine to report.

4. Reachability list correction: Lithium reaches this not merely by omission but despite having a working wr_CompatLithium.MagazineOf at wr_compat_lithium.zs:310 â€” that function is consumed at zscript.zs:1137 but is absent from wr_Stats.Magazine's source chain (wr_stats.zs:222-248), so the sheet's MAG row ignores it and falls to the tracker.

The one-line fix is to make wr_stattracker.zs:296 call the authoritative test rather than re-inline a stale copy: `if (w.Ammo2 != null && w.Ammo1 != w.Ammo2 && !wr_Rig.hasAltFire(w) && a2 > s.magHigh) s.magHigh = a2;` â€” wr_Rig.hasAltFire is already non-private for exactly this reason (see its note at zscript.zs:4381-4386).

---

### 34. HEADSHOTS percentage can exceed 100% â€” hits are hard-capped at one per detected shot while headshots are uncapped and use a 3x wider window

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_stattracker.zs`  
**Line:** 430-437 and 457-472 (tracker); consumed at zscript.zs:2022-2026  
**Severity:** `broken-in-edge-case`

**Symptom**

With RS_Headshots loaded, the sheet prints e.g. "HEADSHOTS 5  (500%)" â€” a share-of-hits figure above 100%, on a row that is coloured SHEET_HOT and reads as a headline stat.

**Cause**

zscript.zs:2022 computes `int hsPct = trHits > 0 ? (trHs * 100 / trHits) : 0;` and nothing clamps it. The two counters are bounded differently. hits (line 432) requires pendingHitUntilTic to be open â€” HIT_WINDOW = 12 tics â€” and line 433 zeroes it immediately, so hits can never exceed one per ammo-drain-detected shot. headshots (line 468) has no hit-window test at all; it is gated only by attributedWeapon's ATTRIB_WINDOW = 35 tics, and increments once per HS_Marker spawn with no per-shot cap. So one shotgun blast that lands several head pellets produces one hit and several markers, and any headshot landing 13-35 tics after the shot (a rocket or a slow bolt in flight) produces a headshot with no hit at all. Note this depends on RS_Headshots spawning one HS_Marker per headshot damage event, which is what this file's own header describes (lines 33-40, HS_Handler.WorldThingDamaged -> HS_Marker.Confirm()) but which I could not verify â€” that mod's source is not in this tree.

**Trigger**

RS_Headshots loaded, wr_stats_track = true (default). Multi-pellet weapon landing more than one head pellet in a single blast, or a projectile headshot arriving more than 12 tics after the shot. Needs trHits > 0, so the weapon must have landed at least one in-window hit first.

**Verification**

Read wr_stattracker.zs in full, zscript.zs:2000-2036, CVARINFO.txt, the extracted RS_Headshots pk3 (hs_detect.zs, hs_feedback.zs, its CVARINFO), and UZDXREMA engine source (p_tick.cpp, p_mobj.cpp, weaponrlaunch.zs, weaponshotgun.zs).

(a) Cited lines are accurate. wr_stattracker.zs:430-437 does `s.hits++; s.pendingHitUntilTic = 0;` inside the window test, so hits is hard-capped at one per opened window. wr_stattracker.zs:457-472 (WorldThingSpawned) does `s.headshots++` on every HS_Marker with no window test, gated only by attributedWeapon. zscript.zs:2022 is verbatim `int hsPct = trHits > 0 ? (trHs * 100 / trHits) : 0;`.

(b) Defaults correct. HIT_WINDOW = 12 (line 229), ATTRIB_WINDOW = 35 (line 240), CVARINFO.txt:1729 `user bool wr_stats_track = true;`. Rocket Speed 20 (weaponrlaunch.zs:72).

(c) No clamp anywhere: grep for hsPct in zscript.zs returns only 2022 and 2024; nothing bounds trHs against trHits. p_mobj.cpp:5849 confirms Actor.Spawn -> CallPostBeginPlay -> WorldThingSpawned, so every marker genuinely reaches the counter.

(d) THE STATED PRIMARY MECHANISM IS WRONG. hs_detect.zs:275 wraps the spawn in `if (!AlreadyConfirmed(victim))`. AlreadyConfirmed (lines 216-234) keeps hs_ConfirmedThisTic/hs_ConfirmTic and dedupes per victim per tic, with an explicit comment at lines 50-58: "One SSG blast is up to twenty pellets ... without this a single trigger pull fires twenty markers". So one blast into one head = exactly ONE marker, not several. The reporter guessed wrong on the exact guard they flagged as unverified. That example is refuted a second time by tick ordering: p_tick.cpp:501-506 runs P_PlayerThink -> WorldTick -> RunThinkers, so hitscan damage is raised BEFORE trackFire detects that shot's ammo drain; the vanilla Shotgun's A_FireShotgun-to-A_FireShotgun gap is 44 tics (weaponshotgun.zs:49-57), far past HIT_WINDOW=12, so its window is always expired at damage time, trHits stays 0, and the percentage clause (`hasBasics && trHits > 0`, zscript.zs:2023) never even prints for it.

BUT the reporter's secondary path is correct and is in fact the dominant one, for a reason they did not identify. Because pendingHitUntilTic is only set during WorldTick of the firing tic, its 12 tics cover projectile travel alone: 12 tics x Speed 20 = 240 map units for a rocket. Any rocket flying farther than ~240 units credits ZERO hits (line 430's `level.maptime <= s.pendingHitUntilTic` fails), while a head-region direct impact still increments headshots unconditionally out to the 35-tic attribution window (~700 units). hs_detect.zs:251 skips DMG_EXPLOSION, so only the direct impact can be a headshot, and hs_detect.zs:265 tests inflictor.pos against the top 20% of victim height (HEAD_FRAC = 0.2) â€” reachable in VR because the rig aims manually rather than by autoaim.

(e) Player-observable. Rocket launcher, head-aimed: 2 rockets land inside 240 units (trHits = 2), 8 land at 300-700 units (headshots only). trHs = 10, trHits = 2, and the sheet prints "HEADSHOTS 10  (500%)" in SHEET_HOT â€” the reporter's own example figure, arrived at by a different route. hits on that weapon is systematically suppressed while headshots is not, so once any single close hit exists the ratio runs away.

The multi-victim variant also survives weakly (AlreadyConfirmed dedupes per victim, not per shot, so one blast head-hitting two separate monsters in one tic = 2 markers, 1 hit), but that alone would need most landing shots to head-hit 2+ distinct monsters, so it is not a realistic route on its own.

Net: the headline conclusion (unclamped hsPct can exceed 100%, player-visible on a SHEET_HOT headline row) is real and confirmed; the stated cause and trigger are half wrong and need replacing.

**Correction (supersedes Cause/Trigger above)**

HEADSHOTS percentage can exceed 100% â€” but not via multi-pellet blasts, which RS_Headshots already dedupes. The real cause is that hits requires an in-flight arrival within 12 tics while headshots does not.

zscript.zs:2022 computes `int hsPct = trHits > 0 ? (trHs * 100 / trHits) : 0;` with no clamp. The two counters are bounded differently, but not for the reason first reported:

- wr_stattracker.zs:430-437 credits a hit only while `level.maptime <= s.pendingHitUntilTic`, and zeroes the window on the first credit. HIT_WINDOW = 12 (line 229).
- pendingHitUntilTic is set in trackFire (line 329), which runs from WorldTick. The engine's tick order is P_PlayerThink -> WorldTick -> RunThinkers (E:\UZDXREMA\src\p_tick.cpp:501-506), so a shot's window opens only AFTER that tic's hitscan damage has already been raised. Those 12 tics therefore cover projectile travel and nothing else.
- wr_stattracker.zs:457-472 increments headshots on every HS_Marker spawn with no window test at all, gated only by ATTRIB_WINDOW = 35 (line 240).

TRIGGER (corrected): a slow projectile whose flight exceeds 12 tics. Doom's Rocket is Speed 20 (E:\UZDXREMA\wadsrc\static\zscript\actors\doom\weaponrlaunch.zs:72), so past ~240 map units the direct impact credits zero hits, while HS_Handler still confirms the headshot out to ~700 units. In VR the player aims manually, so putting a rocket in the top 20% of a monster's height (HEAD_FRAC = 0.2, hs_detect.zs:24, 196-199) is a deliberate act; direct impacts are not DMG_EXPLOSION so they are not filtered by hs_detect.zs:251. Fire ten head-aimed rockets with two landing inside 240 units and eight beyond it: trHits = 2, trHs = 10, and the sheet prints "HEADSHOTS 10  (500%)" in SHEET_HOT.

NOT A TRIGGER: multi-pellet weapons landing several head pellets in one blast. E:\RS_Headshots\Headshots.pk3, zscript/hs_detect.zs:275 wraps the spawn in `if (!AlreadyConfirmed(victim))`, and AlreadyConfirmed (lines 216-234) dedupes per victim per tic specifically to stop that â€” see its comment at lines 50-58. One blast into one monster spawns exactly one marker. Additionally, a hitscan weapon with a refire gap over 12 tics (vanilla Shotgun: 44 tics) never credits a hit at all, so trHits stays 0 and zscript.zs:2023's `hasBasics && trHits > 0` suppresses the percentage entirely for it.

Residual weak path: AlreadyConfirmed is per-victim, not per-shot, so one blast head-hitting two DIFFERENT monsters in the same tic yields 2 headshots against 1 hit. Real, but it would need most landing shots to head-hit 2+ separate monsters to push the total over 100%, so it is not on its own a realistic trigger.

---

## Wheel - Compatibility Shims

### 35. Final Doomer's DOOM II set is never identified â€” prefix compare uses length 8 against a 7-character string

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_compat_finaldoomer.zs`  
**Line:** 92 (helper at 100-103; consumer zscript.zs:1867-1868)  
**Severity:** `broken-in-common-case`

**Symptom**

Playing Final Doomer as the DOOM II class, no weapon ever gets its Final Doomer name row. Every other set shows e.g. "Quantum Accelerator -- PLUTONIA"; the Doom II set shows nothing, leaving only the generic "SLOT N" title the shim's own comment (line 108-109) says the row exists to replace. Since the file header states Doom2 is one of the two sets that get "identification only", this is the entire feature for that class, silently dead.

**Cause**

`if (Left(wc, 8) == "FDDoom2")`. "FDDoom2" is 7 characters (F-D-D-o-o-m-2), not 8. `Left(s,n)` returns `s.Mid(0,n)` whenever `s.Length() > n`, so for a real class like "FDDoom2Shotgun" it returns the 8-char "FDDoom2S", which can never equal the 7-char literal. The only class name that would match is one that is literally "FDDoom2" and nothing more. Every other prefix in the same block is counted correctly: FDAlienVendetta=15 âœ“, FDAliens=8 âœ“, FDPlut=6 âœ“, FDTNT=5 âœ“, FDJPCP=6 âœ“, FDBTSX=6 âœ“, FDHellbound=11 âœ“, FDWhitemare=11 âœ“. Exactly one is off by one.

**Trigger**

DEFAULTS (wr_fd_compat = true, CVARINFO.txt:1636). Final Doomer loaded, DOOM II player class selected at game start, any weapon on the wheel or inspect card.

**Verification**

I could not refute this; every check confirms it.

(a) Cited lines say exactly what is claimed. E:\mERGE\RS_VR_Unified\zscript\wheel\wr_compat_finaldoomer.zs:92 reads `if (Left(wc, 8)  == "FDDoom2")         return true, "DOOM II";`. The helper at lines 100-103 reads `return (int(s.Length()) <= n) ? s : s.Mid(0, n);`. `Left` is a private static of this same class (there is no other `Left` in scope; the call site is unqualified inside `wr_CompatFinalDoomer`, so it resolves to the file's own helper, not GZDoom's `String.Left` method form).

(b) Lengths verified mechanically, not by eye. "FDDoom2" = 7 bytes; the arg is 8. Every other literal's length matches its n exactly: FDAlienVendetta 15/15, FDAliens 8/8, FDPlut 6/6, FDTNT 5/5, FDJPCP 6/6, FDBTSX 6/6, FDHellbound 11/11, FDWhitemare 11/11. Exactly one is off by one, as claimed. Default confirmed at E:\mERGE\RS_VR_Unified\CVARINFO.txt:1636 â€” `user bool  wr_fd_compat = true;` â€” and `active()`/`SetOf()` gate on `cv("wr_fd_compat", 1.0) > 0.0` (lines 41, 81), so the code path is live at defaults.

(c) Not guarded or handled elsewhere. I grepped the whole repo: `FDDoom2` appears at exactly one site (line 92). `SetOf` has no consumers outside this file â€” only `NameOf` (line 114) and `NanoCoreOf` (line 313, which additionally requires set == "BTSX"). There is no second Final Doomer set-identification path anywhere in zscript/, so nothing else recovers the DOOM II label.

(d) Arithmetic is genuinely broken. For any class name longer than 8 chars (`FDDoom2Shotgun` etc.), `Left` takes the `Mid(0,8)` branch and returns an 8-char string, which can never equal a 7-char literal. For names of length <= 8 it returns the whole string, so the only value that matches is a class named literally "FDDoom2" â€” impossible for a set of nine distinct weapons. The branch is therefore dead in both branches of the helper's ternary. `NameOf` (line 111-119) returns `false, ""` on `!got`.

(e) Player-observable at both consumer sites, which I read. zscript.zs:1866-1868 (`buildSheetRows`, a live method â€” `private void buildSheetRows(Weapon w)` at line 1336) pushes the row via `sheetRow(fdNameRow, SHEET_TEXT)` only `if (fdName)`; zscript.zs:6924-6925 pushes `labels.Push("SET")` only `if (fdNHas)`. I also confirmed the fallback the shim's comment (lines 105-109) describes: zscript.zs:1430-1432 prints `String.Format("SLOT %d", slotOf(w))` when no rarity/flavor shim claims the title row, and Final Doomer claims none (no tier ladder, per the file header and CVARINFO.txt:1629-1635). So on the DOOM II class the sheet shows a bare "SLOT N" and the inspect card has no SET row, where all eight other sets show e.g. "Quantum Accelerator -- PLUTONIA". Since the file header (lines 22-25) states Doom2 gets "identification only", this is that class's entire Final Doomer feature, silently dead.

The one premise I cannot check from this repo is that Final Doomer's DOOM II weapons actually use the `FDDoom2` prefix (the mod's DECORATE is not present here). That does not rescue the code either way: if the prefix is right, the length is wrong and the branch is dead; if the prefix is wrong, the branch is dead for a different reason. The observable outcome â€” DOOM II is never identified â€” holds in both cases. Fix is `Left(wc, 7)`.

---

### 36. The DURA row is printed twice â€” the two Pandemonia durability readers are byte-identical name-based reads

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_compat_pandemonia.zs`  
**Line:** 50-60 (twin at wr_compat_pandemonia_insurrection.zs:106-128; consumers zscript.zs:1507-1511 and 1537-1541, plus 6756-6762 and 6782-6788)  
**Severity:** `broken-at-defaults`

**Symptom**

Any Pandemonia-family weapon that opts into durability shows two identical adjacent rows on the data sheet: "DURA 40/60" / "DURA 40/60". On the comparison card the same weapon pushes the label "DURA" twice, so the merge loop at zscript.zs:6678-6695 emits two identical comparison rows as well. Both consume slots from the fixed pools (SHEET_ROW_POOL 28, CMP_ROW_POOL 26), where overflow rows are silently dropped.

**Cause**

`wr_CompatPandemonia.DurabilityOf` and `wr_CompatPandemoniaInsurrection.DurabilityOf` are the same function character-for-character: same cvar gate (`wr_pand_compat`), same four reflected field names ("dwep", "durability", "dmax", "dbroken"), same returns. A grep of every reflected field name across the eleven shims shows those four strings appearing exactly twice each, once per file. Reflection is by NAME and neither function performs any class check, so the class-hierarchy argument both files rely on never reaches the code â€” the comments at wr_compat_pandemonia.zs:46-49 ("only one can ever return found=true for a given weapon") and zscript.zs:1532-1535 ("at most one of the two DURA rows can ever fire") are false by construction. Whichever weapon satisfies one satisfies the other. (The only alternative reading is worse in a different way: if PandWeapon and PandInsWeapon really do use different field names, then one of the two files is reading names that do not exist and that mod's durability never appears at all.)

**Trigger**

DEFAULTS (wr_pand_compat = true, CVARINFO.txt:1593). Any Pandemonia / Anarchy / Insurrection weapon with dwep true, on both the wheel sheet and the inspect comparison card.

**Verification**

CONFIRMED on every check.

(a) Cited lines verified verbatim. wr_compat_pandemonia.zs:50-60 and wr_compat_pandemonia_insurrection.zs:106-128 have identical bodies once comments are stripped: same `active(w)` gate (both helpers also identical, cvar "wr_pand_compat" with fallback 1.0), same GetFieldBool(w,"dwep") opt-in gate, same three checked reads of "durability"/"dmax"/"dbroken", same `return true, cur, max, brokenI != 0`. Neither performs any class check, GetClassName compare, or ancestry walk. A grep of "dwep"/"dmax"/"dbroken" across E:\mERGE\RS_VR_Unified\zscript\ returns exactly two hits each, one per file. Because both are pure static functions of `w` and are textually identical, they return the same tuple for every possible input â€” the class-hierarchy separation the two header comments rely on (wr_compat_pandemonia.zs:45-49 "only one can ever return found=true"; zscript.zs:1532-1535 "at most one of the two DURA rows can ever fire") is unreachable by the code, exactly as reported.

(b) Defaults correct. CVARINFO.txt:1593 `user bool wr_pand_compat = true;`. Both cv() fallbacks are 1.0, so the readers are active even with the cvar absent.

(c) No guard, clamp, or dedup exists anywhere the reporter did not look. Both call-site pairs are unconditional with no intervening `if`: zscript.zs:1507 (Insurrection) and 1537 (base) inside buildSheetRows; 6757 and 6783 inside modRowsOf. sheetRow() at zscript.zs:2478-2488 is a blind appender whose only early return is `mSheetUsed >= mSheetRows.Size()`; cmpRow() at 6584-6602 likewise on mCmpUsed. Neither dedups on text or label. Both files are compiled in (zscript.txt:112 and 114).

(d) Arithmetic/logic works out to the broken result. Sheet: two adjacent rows with identical text and identical color logic. Comparison card: the merge loop at 6678-6695 uses `usedB[match] = true`, so la's first "DURA" pairs with lb's first "DURA" and la's second with lb's second â€” both emit a cmpRow, giving two identical comparison rows. If only one of the two weapons has durability, the duplicate still emits twice with "--" in the other column. Pool constants confirmed at zscript.zs:8862 (CMP_ROW_POOL = 26) and 8873 (SHEET_ROW_POOL = 28), with silent drop on overflow in both appenders.

(e) Player-observable for any Pandemonia-family weapon with dwep set. The only scenario in which it is not observable is one where no weapon in the family carries the field at all, which would make wr_compat_pandemonia.zs's durability reader entirely dead code â€” a defect, not an exoneration. The Pandemonia mod source is not present on this machine (searched E:\ root; only RS_* / engine trees exist), so I could not confirm the field names against the mod itself, but that is irrelevant to the finding: two textually identical functions agree on every input regardless of what the real field names turn out to be.

**Correction (supersedes Cause/Trigger above)**

The claim is correct as written; two details refine it in the direction of being slightly worse, not better. (1) The effective sheet budget is not SHEET_ROW_POOL = 28 but the visible plate capacity documented at zscript.zs:8864-8873 â€” twelve rows plus one bar, past which an element "would silently draw into the room," off the bottom edge of the plate. The duplicate DURA row therefore consumes one of roughly twelve visible slots, not one of 28. (2) On the comparison card the value string is "BROKEN" rather than "%d/%d" when the weapon is broken (zscript.zs:6761, 6787), so the duplicated pair there reads "DURA BROKEN" / "DURA BROKEN"; the reporter's "DURA 40/60" twice is accurate for the wheel sheet (zscript.zs:1509, 1539), which always formats cur/max and signals broken through color instead.

---

### 37. Combined Arms Striker lockout reads ~6 seconds for a lockout the file itself documents as fifty seconds (9x too small)

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_compat_combinedarms.zs`  
**Line:** 202 and 205 (unit comment 198-200; the real figure is in the file header at line 24-25)  
**Severity:** `broken-in-common-case`

**Symptom**

A Tech Monk who has just used the Striker opens the wheel and reads "STRIKER LOCKED 6s". The lockout actually lasts about fifty seconds. The number then crawls â€” each displayed second takes nine real seconds â€” and the row is still claiming a couple of seconds left long after six have gone by. "STRIKER ACTIVE %ds" is wrong by the same factor.

**Cause**

`String.Format("STRIKER LOCKED %ds", reset / 105 + 1)`. The comment above it states the mechanism correctly â€” "StrikerTimer and StrikerReset both drain 1 per 3 tics" â€” and then writes the formula for the opposite mechanism: dividing by 105 is `counter/(3*35)`, which is only right if the counter were measured in tics and drained 3 per tic. Draining 1 per 3 tics means remaining tics = counter*3, so seconds = counter*3/35. The file's own header supplies the check value: "StrikerMeter grants StrikerReset 600, a fifty-second lockout". 600*3/35 = 51.4s (matches the header); 600/105+1 = 6s (what the code prints). The correct expression is `reset * 3 / 35 + 1`.

**Trigger**

DEFAULTS (wr_ca_compat = true, CVARINFO.txt:1627). Combined Arms loaded, Tech Monk class, immediately after any Striker use; same for StrikerTimer while the Striker is active.

**Verification**

CONFIRMED â€” I could not refute it. Checked all five points.

(a) Lines say what is claimed. E:\mERGE\RS_VR_Unified\zscript\wheel\wr_compat_combinedarms.zs, read in full:
- 198-200 comment: "StrikerTimer and StrikerReset both drain 1 per 3 tics, so seconds are tics/3/35 -- written as /105 rather than /35 the way the 1-per-tic counters below are."
- 202: `if (reset > 0) return true, String.Format("STRIKER LOCKED %ds", reset / 105 + 1);`
- 205: `if (timer > 0) return true, String.Format("STRIKER ACTIVE %ds", timer / 105 + 1);`
- 24-25 header: "StrikerMeter grants StrikerReset 600, a fifty-second lockout."
All four quotes are verbatim. Line numbers as reported.

(b) Defaults correct. CVARINFO.txt:1627 is exactly `user bool  wr_ca_compat = true;`, and `active()` (line 59) reads `cv("wr_ca_compat", 1.0) > 0.0` with fallback 1.0, so the path is on both by cvar and by fallback. MENUDEF.txt:1323 exposes it as an OnOff toggle. Reached only for CA_MONK (IAmTechMonk, granted as a startitem per the line 100-104 comment).

(c) Nothing clamps or reformats it downstream. `amountOf` (86-91) returns raw `it.Amount`, no cap. Both consumers print the string verbatim: zscript.zs:1839-1840 `sheetRow(caResRow, SHEET_TEXT)` on the data sheet, and zscript.zs:6902-6904 `labels.Push("RESOURCE"); values.Push(caRRow)`. No second formatter, no clamp, no override anywhere.

(d) The arithmetic is broken, and the direction error is provable without needing the mod. The same file states the correct rule for the 1-per-tic case at line 262: "SecondWindHeat and BootTimer both drain 1 per tic, so both are plain tics and divide by the tic rate for seconds" -> `/35 + 1` (265, 270). A counter that drains SLOWER than 1/tic must therefore yield a LONGER time than /35, i.e. `amount * 3 / 35`. Line 202 instead divides by MORE (105), producing a value 3x shorter than even the plain-tics reading and 9x shorter than the truth. The header supplies the check value and confirms the magnitude: 600*3/35 = 51.4s, which is the header's "fifty-second lockout"; the shipped `600/105 + 1` = 6. Ratio 105 / (35/3) = 9 exactly, so each displayed second lasts 9 real seconds â€” the claim's "crawls" description is arithmetically right. The reporter's fix `reset * 3 / 35 + 1` yields 52 for 600, matching the header.

The only escape hatch would be that the counter is really in tics draining 3-per-tic (the mechanism the shorthand "tics/3/35" actually describes), which would make /105 correct. That requires BOTH the prose at 198 ("drain 1 per 3 tics") AND the header at 24-25 ("600, a fifty-second lockout") to be wrong, and wrong in mutually consistent ways 175 lines apart, while the code alone is right. Under that reading the lockout would be 5.7s, contradicting the header outright. A `delay(3)`-loop TakeInventory (1 per 3 tics) is also the idiomatic ACS pattern; decrementing 3 per tic is not.

(e) Player-observable. A Tech Monk opening the wheel right after a Striker use reads "STRIKER LOCKED 6s" on a row that stays visible for ~51 real seconds, still reading 1-2s after 40+ seconds have passed. Same 9x factor on "STRIKER ACTIVE %ds" (line 205).

Caveat the parent should carry: Combined Arms itself is not on this disk (searched E:\mERGE and E:\RS_WeaponWheel; the only occurrences of StrikerReset/StrikerTimer/StrikerMeter anywhere are inside this one compat file, and the copy at E:\RS_WeaponWheel\RS_WeaponWheel\wr_compat_combinedarms.zs is byte-identical). So the drain rate and the 600 grant rest on the file's own two independent comments rather than on CBarms.acs read directly. That does not rescue the code: at minimum the file is self-contradictory, and under the reading its own two comments agree on, the display is 9x too small.

Adjacent, NOT confirmed, flagging only: zscript.zs:1823 `String.Format("OVERHEATED  %ds", caOver / 70 + 1)` uses the same /70 = 2*35 shape against a comment (wr_compat_combinedarms.zs:122-126) documenting "twenty seconds". If BMoverheat likewise drains 1 per 2 tics it is the same error (would print 6s for 20s), but no grant amount is stated anywhere so I could not verify it either way.

---

### 38. The ModelSwapper page is offered or withheld based on the MAIN hand only, on a per-hand wheel

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 662-667 (pageCount), used at 702-703; contrast gatherModels at 3106-3110 and commitModel at 8469-8473  
**Severity:** `broken-in-common-case`

**Symptom**

Two wrong outcomes depending on which way the hands differ. (A) Off hand holds a gun with a model shelf but the main hand does not: pageCount() returns 2, so paging on the off-hand wheel cycles Weapons -> Inventory -> Weapons and the Models page for the gun actually in that hand is unreachable. (B) Main hand has a shelf but the off hand does not: pageCount() returns 3, the player pages to Models on the off-hand wheel, gatherModels calls StateOf(1), gets ok=false and returns having pushed zero cards â€” the ring comes up completely empty with no explanation and no fallback (rebuildPage at 2630-2644 does nothing about an empty gather).

**Cause**

`pageCount()` calls `wr_CompatModelSwapper.StateOf(0)` with a hardcoded hand 0. Every other consumer of the same shim resolves the hand from the rig: gatherModels and commitModel both use `int hand = (mRigHand == 1) ? 1 : 0`, and the sheet's MODEL row at 1981-1988 resolves msHand from which hand actually holds the weapon. Verified against the real bridge in E:\ModelSwapper\zscript\RS_ForeignModels.zs:2398-2432: mBridgeHasMain and mBridgeHasOff are set independently from mi/oi, and mBridgeCountMain/Off come from separate `mShelf.Count(archetype)` calls, so the two hands genuinely disagree whenever they hold weapons with different archetypes or when one hand's weapon has no shelf entry.

**Trigger**

DEFAULTS (wr_ms_compat = true, CVARINFO.txt:1668) with ModelSwapper loaded. Any moment the two hands' bridge state differs â€” e.g. off hand holding a pistol with five models while the main hand holds a weapon ModelSwapper has no entry for.

**Verification**

Confirmed on all five checks by reading the files directly.

(a) Lines say what is claimed. zscript.zs:662-667 is exactly `private int pageCount() { ... [ms, arche, pick, cnt, donor] = wr_CompatModelSwapper.StateOf(0); return ms ? 3 : 2; }` â€” hand hardcoded to 0. Consumed at 702-703: `int n = pageCount(); mPage = (mPage + e.Args[0] + n) % n;`. gatherModels at 3106/3109 and commitModel at 8469/8472 both use `int hand = (mRigHand == 1) ? 1 : 0;`, and the sheet MODEL row at 1981-1988 resolves msHand from `sheetPi.ReadyWeapon == w` / `sheetPi.OffhandWeapon == w`. The inconsistency is real and the cited line numbers are accurate.

(b) The shim is genuinely per-hand, not a mod-presence probe. wr_compat_modelswapper.zs:65-86 picks mBridgeHasOff/ArcheOff/PickOff/CountOff/DonorOff vs the Main set purely from the `hand` argument, and returns false when `hasI == 0` OR `cnt <= 0`. pageCount's own comment ("Two pages, or three when ModelSwapper is loaded ... the compat switch behind it can be turned off from the menu") shows the intent was a mod/switch-presence test, which is precisely why passing a hand-specific query with a hardcoded hand is the defect.

(c) The two hands genuinely disagree. E:\ModelSwapper\zscript\RS_ForeignModels.zs:1843-1844 computes `int mi = pi.ReadyWeapon ? FindEntry(...) : -1;` and `int oi = pi.OffhandWeapon ? FindEntry(...) : -1;` independently, then RefreshBridge (2398-2432) sets mBridgeHasMain = (mi >= 0) and mBridgeHasOff = (oi >= 0) in separate blocks, with separate mShelf.Count(archetype) calls for mBridgeCountMain/Off.

(d) Not guarded anywhere the reporter did not look. Every mPage occurrence in the file is 388 (decl), 703 (page step), 902 (reset to PAGE_WEAPONS on open), 3060-3061 (gather dispatch), 8046, 8491-8492 (commit dispatch) â€” there is no re-validation of mPage against pageCount and no empty-page fallback. The only empty-ring guard in the whole file is `if (mTypes.Size() == 0) return;` at line 905, inside openRig, which covers opening but not a page flip. rebuildPage (2629-2643) runs clearPanels/gatherWeapons/spawnPanels/buildSheet/buildStars unconditionally, and spawnPanels' card loop `for (i = 0; i < mTypes.Size(); ++i)` (5131) simply runs zero times, leaving the rig open with no cards at all.

(e) Defaults correct and player-observable. CVARINFO.txt:1668 `user bool wr_ms_compat = true;` and CVARINFO.txt:1150 `user int wr_toggle_prefer_hand = -1;`, so preferredToggleHand(1) returns 1 unchanged and wr_toggle_off really does open the rig on hand 1 at defaults. Both outcomes are things the player sees directly: a Models page that will not appear for the gun in the off hand, or a completely empty ring after two page presses.

I could not refute any leg. The only thing I would change is the trigger description (see correction) â€” the reporter picked a rarer instance of a more common failure.

**Correction (supersedes Cause/Trigger above)**

The finding stands; only the trigger for outcome (B) should be broadened, because the reporter picked a rarer case than the one that actually fires most often.

gatherModels bails one line EARLIER than the reporter cites â€” at zscript.zs:3103-3104, `let held = (mRigHand == 1) ? pmo.player.OffhandWeapon : pmo.player.ReadyWeapon; if (held == null) return;` â€” before StateOf(hand) is ever called. So outcome (B) does not require the off hand to hold a weapon ModelSwapper has no entry for; an EMPTY off hand is sufficient, and that is the everyday reason to summon the off-hand wheel at all. Concrete default-settings repro: main hand holds any weapon on a ModelSwapper shelf, off hand empty, press wr_toggle_off, press wr_page twice â€” pageCount() asks StateOf(0), sees the MAIN hand's live bridge state, returns 3, the wheel pages to PAGE_MODELS, gatherModels returns at 3104 on held == null, and rebuildPage spawns zero cards into a still-open rig. The player gets a ring with nothing in it and no way to tell why, until they page again.

Outcome (A) is likewise slightly broader than stated: because mBridgeHasMain is false whenever ReadyWeapon is null (RS_ForeignModels.zs:1843), an empty MAIN hand also collapses pageCount() to 2 on the off-hand wheel, hiding the Models page for a shelved weapon the off hand is actually holding.

---

### 39. Lithium's SMG heat row has no weapon-class gate, so it appears on every Lithium weapon's card

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\wr_compat_lithium.zs`  
**Line:** 724-732 (consumer zscript.zs:1196-1205)  
**Severity:** `broken-in-common-case`

**Symptom**

A CyberMage who has been firing the SMG then browses the ring: every other Lithium weapon card â€” Mateba, Shock Rifle, Ion Rifle, Star Destroyer, Plasma Rifle, every spell â€” shows "HEAT 300/500", and once heat reaches 450 it shows "HEAT 460/500  LOCKED" in the dry-ammo red on weapons that are not locked out at all. It also claims the sheet's single gauge (line 1204) on those cards whenever mana has not already taken it, so the bar shows another gun's heat.

**Cause**

`SmgHeatOf` gates only on `ready(w)` = active(w) && IsLithium(w), then reads the player-owned pool `Lith_SMGHeat` off w.Owner and returns found=true for any Lithium weapon that reaches it. Every other weapon-specific reader in the same file carries its own class gate â€” SmgSpreadOf checks `clsOf(w) != "Lith_SMG"` (741), IonChargeOf checks Lith_IonRifle (757), WindUpOf Lith_Minigun (774), RemsOf Lith_Rems (822), ShrapnelOf Lith_ShrapnelGun (836), ComboOf Lith_Kampilan (807) â€” and this one, which returns the SMG's own fire-abort flag as its fourth value (`n >= SMG_HEAT_HOT`, 450 of 500), does not. ChargeFistOf (591-597) has the same shape, printing the Marine's "CHARGE %d" on every Lithium weapon card.

**Trigger**

DEFAULTS (wr_lith_compat = true, CVARINFO.txt:1670). Lithium loaded, CyberMage character, any time SMG heat is above 0 â€” i.e. from the first SMG shot until it fully cools.

**Verification**

Verified every cited line directly. (a) wr_compat_lithium.zs:724-732 SmgHeatOf gates only on `ready(w)` then reads the owner pool `Lith_SMGHeat` via itemOf(w.Owner, ...) â€” no `clsOf(w) != "Lith_SMG"` test. Every sibling reader in the same file does carry one: 741 SmgSpreadOf (Lith_SMG), 757 IonChargeOf, 774 WindUpOf, 807 ComboOf, 822 RemsOf, 836 ShrapnelOf. ChargeFistOf (591-597) is likewise ungated, reading Lith_FistCharge off the owner. The asymmetry is exactly as reported.

The decisive check was whether `ready()` silently restricts to the equipped weapon, which would have refuted the whole thing. It does not: line 56-59 `active(w)` is only `w && w.Owner && cv("wr_lith_compat",1.0) > 0.0`, and line 143-146 `ready(w) = active(w) && IsLithium(w)`. Any carried Lithium weapon passes.

(c) No guard downstream either. zscript.zs:1093-1102 builds the sheet for `shown = pmo.FindInventory(HoveredClass())` â€” the hovered weapon's own instance â€” and 1972 calls `lithiumRows(w)` unconditionally; 1196-1205 applies no class test. Row-drop is not a rescue: SHEET_ROW_POOL = 28 (zscript.zs:8873), far above the ~8 rows a Lithium card emits, so the row is really drawn.

(b) Defaults correct: CVARINFO.txt:1670 `user bool wr_lith_compat = true`; SMG_HEAT_MAX 500 (line 43), SMG_HEAT_HOT 450 (line 44). The consumer gate at 1198 is `liHeatN > 0 || liHeatLock`, so the row is absent at heat 0 and present from the first SMG shot until cool â€” matching the stated trigger.

(d) Arithmetic holds: `liHeatLock = n >= 450` drives COLOR_AMMO_DRY plus the "  LOCKED" suffix at 1200-1203, so a Mateba with the SMG at 460 heat prints "HEAT 460/500  LOCKED" in dry-ammo red on a weapon with no lockout. The gauge claim at 1204 is correctly qualified by the reporter â€” `liTookBar` is set by the mana row at 1174 when liManaN > 0, so heat only takes the bar when mana is at zero.

(e) Player-observable: the mod's own name table (246-282) confirms pc==1 (CyberMage) carries CHARGE FIST, MATEBA, SHOCK RIFLE, SPAS, SMG, ION RIFLE, PLASMA RIFLE, STAR DESTROYER plus the spells, so there are eight-plus other weapons that will show the SMG's heat.

Only inaccuracy is the UI wording â€” see correction. It does not affect the defect.

**Correction (supersedes Cause/Trigger above)**

The defect is confirmed; only the description of where it appears needs correcting. These rows are not drawn on each weapon card. zscript.zs:1093-1102 rebuilds the single centre data sheet for whichever weapon is hovered (`shown = pmo.FindInventory(HoveredClass())`, falling back to ReadyWeapon), so the player sees the bogus "HEAT n/500" row on one weapon at a time as the selector passes over each non-SMG CyberMage weapon â€” not simultaneously on twenty cards. Same for ChargeFistOf's "CHARGE %d" row (zscript.zs:1258). Also note ChargeFistOf sits under the file's "MARINE" header but the Charge Fist is granted to both pc==0 and pc==1 (lines 247, 251), so its ungated row leaks onto CyberMage weapons too, not just Marine ones. The fix is a one-line class gate in each reader, matching the pattern already used at lines 741, 757, 774, 807, 822 and 836.

---

### 40. Every per-second countdown the shims produce is frozen â€” the sheet rebuilds only when the hovered weapon's CLASS changes

**File:** `E:\mERGE\RS_VR_Unified\zscript\wheel\zscript.zs`  
**Line:** 1097-1102 (refreshSheet), 6491-6510 (inspect card); rows affected e.g. wr_compat_lithium.zs:367-381, wr_compat_guncaster.zs:38-44, wr_compat_doominfinite.zs:440-450  
**Severity:** `broken-at-defaults`

**Symptom**

Hover a stowed Lithium weapon mid-auto-reload and the card reads "RELOADING 4s" and stays at 4s indefinitely â€” it never counts down and never clears when the reload finishes. Same for "SPELL CD 2.3s" (Guncaster), "STRIKER LOCKED"/"OVERHEATED %ds" (Combined Arms), "ACTIVE %ds" and "DESPAWN %ds" (DOOM Infinite, where the whole point is a live deadline on a gun that is about to vanish), the Lithium status-effect seconds, and every heat/mana/charge gauge. Values only ever update if the player moves the selector to a weapon of a different class and back.

**Cause**

`refreshSheet` early-returns on `if (mSheetValid && nowCls == mSheetShown) return;` where nowCls is the hovered weapon's CLASS, so buildSheetRows runs exactly once per distinct hovered class per ring session; setSheetBar is only ever called from inside buildSheetRows, so the gauge is snapshotted too. The inspect path is the same shape, rebuilding only when `mInspectWpn != found`. wr_compat_lithium.zs:359-364 justifies AutoReloadOf specifically as "the one row here built specifically for a WHEEL rather than for a HUD... browsing the ring is exactly when you would want to know a gun is nearly ready again" â€” resting the selector on that card is precisely the case the caching policy freezes. AUTORELOAD_TICS is 175 (5 seconds), so the row is stale within a second of appearing.

**Trigger**

DEFAULTS, no unusual settings. Any wheel or inspect session where the player rests the selector on one weapon for more than a second â€” the normal way the sheet is read in a headset.

**Verification**

Verified independently against the source. (a) zscript.zs:1098 is exactly `if (mSheetValid && nowCls == mSheetShown) return;` with nowCls = shown.GetClass(), and the header comment at 1084 states the policy outright ("Rebuild the rows when, and only when, the selector lands on a different weapon"). zscript.zs:6491 is `if (mInspectWpn != found)` gating buildSheetRows at 6506. (b) Exhaustive grep confirms no second refresh path: buildSheetRows is called ONLY at 1102 and 6506; setSheetBar is called only from inside those build paths; SetBillboardText on sheet rows occurs only in sheetRow() (2486), blankRestOfSheet (2268) and the title (1352/6356); mSheetValid=false appears only at 2459 inside buildSheet() (called at open 909, page flip 2638, inspect 6504); mSheetShown=null only at 2458/6505. layoutSheet (2521) only positions, never restrings. So nothing re-runs the row fill while the selector rests. (c) Defaults check out: AUTORELOAD_TICS=175 (wr_compat_lithium.zs:46), AutoReloadOf returns (175-t)/35+1 with t counting up each tic on a stowed gun (367-381); guncaster SpellCooldownOf returns delay/35.0 rendered as "SPELL CD %.1fs" (zscript.zs:1576) â€” a tenth-of-a-second field that should change roughly every 3.5 tics; DespawnOf (doominfinite 440-450) returns ARENA_TIMEOUT - internalSecond and inspect targets are unowned world actors by construction (6427-6446), so this is a live floor-weapon deadline. "OVERHEATED %ds" (1823), "STRIKER LOCKED %ds" (combinedarms:202) and "ACTIVE %ds" (1758) also confirmed present. (d) Arithmetic produces a genuinely wrong display: over the life of one hover the underlying values change several times and the drawn text never does. (e) Player-observable, and the code contradicts itself about it in two places: zscript.zs:2449-2450 claims the gauge is "unconditionally safe to update in place every tic" when setSheetBar is never called per tic, and wr_compat_lithium.zs:357-361 justifies the AutoReload row specifically as a live wheel-only ticker for a stowed gun â€” the exact case the cache freezes. The only inaccuracy is scope, corrected below.

**Correction (supersedes Cause/Trigger above)**

The mechanism and all cited lines/values are correct; only the word "indefinitely" needs splitting by mode. In the RING, wr_locktics defaults to 140 tics = 4 seconds (CVARINFO.txt:1137) and mLockTics is reset only on a hover change (zscript.zs:8312-8317, the sole reset besides open at 939), so a selector resting on one card freezes the row for up to 4 seconds and then the ring folds â€” the counter never advances once while it is readable, but it is not unbounded. In INSPECT mode there is no timeout at all (the tick at 6386-6514 only decays mInspectTics when the laser leaves the target), so the freeze there IS indefinite â€” which makes DOOM Infinite's "DESPAWN %ds" on an unowned Infinite Arena floor weapon the worst instance: the card holds its original figure while the sprite fades out and the gun vanishes. Also worth noting alongside the reported rows: setSheetBar being reachable only from inside buildSheetRows means every gauge (Lithium mana/heat, DI heat, Combined Arms heat, RS condition) is snapshotted by the same cache, directly contradicting zscript.zs:2449-2450's claim that the bar is updated in place every tic.

---

## Refuted findings

The following 20 candidates did NOT survive verification and are recorded
only so they are not re-raised as new discoveries later:

- Data-sheet title is drawn ~3.3x oversized and runs off both edges of the plate
- A wrapped two-line weapon name is drawn straight across the ammo bar under it
- Fan sub-cards are hit-tested at their authored size, so the top and bottom of every visible fan card is dead to the laser
- When the 28-row sheet pool overflows, the rows dropped are DAMAGE / ACCURACY / ROF / MAG / VELOCITY / CRIT
- After every level change, kills and hits are credited to the wrong hand's weapon â€” the "fails closed" attribution guard goes negative because level.maptime restarts while lastFireTic does not
- The drawn reach oval is ~33x bigger than the volume that actually grabs
- rs_hands clears NoDraw on the weapon psprite every tic, un-hiding hardpoint gesture-fire weapons
- rs_hands' fist stand-in misses Brutal Doom's melee weapon -- the check rs_fist.zs was fixed for was never copied here
- rs_grab_corpses ships true while the code and its own design note say it must default false
- The fist fallback relabels the OTHER hand's live weapon via SisterWeapon
- Every measured weapon is drawn 45% larger than the marker ring it is supposed to sit in (95% during the settle pop)
- Turning both display switches off silently disables the holster-desync repair, permanently bricking a drifted weapon
- The pouch marker never actually goes invisible when stocked -- proximity lights it from 14 units away
- The ammo pouch's catch volume is 0.5 units wider than the ring drawn for it
- A holster's pitch can never tilt its marker -- edit mode captures a pitch the reticle ignores
- Every mount's reticle is drawn 52% larger than the volume that actually catches your hand
- The palm-out arming gesture is inverted: rs_hardpoint_gesture_roll_target defaults to 0.0, so a normal grip ARMS and rolling palm-out DISARMS
- gesturePreviousOff/Main use null as both the value and the "not captured yet" flag, so a second fire from an empty hand seats a hardpoint weapon as the player's real weapon
- The magazine system is implemented but its menu row and cvar comment tell the player it does nothing, and it defaults off -- so at defaults a completed reload moves zero ammunition
- rr_mag_scale does not exist -- magazine capacity is untunable and CapOf's scaling/floor arithmetic is dead code


---

## Caveats on the counts

**Some findings are duplicates across slices.** The wheel was analysed in five
overlapping slices, and several defects were independently found by more than one.
The 40 figure counts reports, not distinct defects; the real number of distinct
defects is nearer 35. Known duplicate pairs:

- "Inspect/compare card keeps comparing against a weapon you are no longer holding"
  -- reported by both `wheel-interaction` and `wheel-render`.
- "mFansEnabled is never recomputed for the inventory/model pages" -- reported by
  both `wheel-interaction` and `wheel-render`.
- "Fan sub-cards use their visible plate as their own hit target" -- reported by both
  `wheel-layout` and `wheel-render`.
- "Every live countdown row is frozen" (`wheel-render`) and "Every per-second countdown
  the shims produce is frozen" (`wheel-compat`) are the same root cause: the sheet
  rebuilds only on a hovered-CLASS change.

Duplicates were kept rather than merged because each report cites different lines and
reasons from a different angle, and the overlap is itself evidence -- a defect found
independently from two directions is better attested than one found once.

**One defect has CONFLICTING verdicts and is listed on both sides.** The psprite
`NoDraw` collision between `rs_hands` and hardpoint gesture-fire was CONFIRMED when
reported from the `hardpoints` slice and REFUTED when reported from the `hands` slice.
The confirmed version is the better-evidenced one -- it cites both sides of the
collision (`RS_HardPoints.zs:2821-2823, 2936-2938` setting `psp.NoDraw = true`, and
`rs_hands.zs:281-283` overwriting it every tic) -- but the disagreement is recorded
rather than silently resolved. Treat it as needing one in-headset check, not as settled.

This is exactly the failure mode [calibrating diagnostic claims] exists to catch: a
verification pass is a filter, not an oracle. Everything here is code analysis. Only
one finding in this document -- the wheel data sheet swallowing its own cards -- was
independently observed in a headset by the owner before being root-caused.