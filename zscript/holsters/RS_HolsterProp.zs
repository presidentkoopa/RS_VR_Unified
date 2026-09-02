// The visible half of a holster: a prop actor parked at each anchor, showing
// the weapon stored there.
//
// HOW THE MODEL GETS THERE. MODELDEF binds a model to a (class, sprite, frame)
// triple, and FindModelFrameRaw matches the class by EXACT pointer -- so a
// subclass does not inherit its parent's model, and no generic prop class can
// ever have a weapon's model bound to it directly.
//
// A_ChangeModel is the way through. It creates per-instance model data and
// sets modelDef on it, and FindModelFrame prefers modelData->modelDef over the
// actor's real class. So this prop borrows the weapon's model definition at
// runtime, then wears the weapon's own Ready-state sprite and frame so the
// (class, sprite, frame) lookup resolves. No new art, no generated MODELDEF
// entries, no spawning real Weapon actors just to look at them.
//
// Why not spawn the actual weapon as a prop: a Weapon in the world runs its
// own BeginPlay and lands in this mod's condition/rarity/GunBonsai paths. A
// display object must not be able to roll a rarity.
//
// Why the Ready state rather than Spawn: Spawn is the PICKUP sprite (RIFK),
// which has no model bound. The held frames (RIFL) are the ones MODELDEF
// actually covers.
// A visible ring at every holster anchor, whether or not anything is stored
// there. Without this an empty holster is invisible and the player has nothing
// to aim a hand at -- and no way to tell a mispositioned anchor from a dead
// one. Frame A is idle, frame B lights up while a hand is inside the radius,
// which doubles as live confirmation that the claim is firing.
class RS_HolsterMarker : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		+BRIGHT
		+FORCEXYBILLBOARD
		RenderStyle "Add";
		Alpha 0.85;
		Radius 1;
		Height 1;
	}

	States
	{
	Idle:
		RSHM A -1;
		Stop;
	Hot:
		RSHM B -1;
		Stop;
	Spawn:
		RSHM A -1;
		Stop;
	}

	// Tracks the current look so the state is only re-entered on a change.
	// SetStateLabel restarts the state, so calling it every tic would keep
	// resetting the sprite forever. lastShape rides along in the SAME guard
	// -- without it, changing the shape cvar mid-session would sit inert
	// until this holster's hot/idle state happened to toggle on its own
	// (the next time a hand entered or left it), which reads as "the menu
	// setting did nothing" rather than "not yet, still waiting."
	private bool isHot;
	private bool everSet;
	// No sentinel needed: everSet already gates "first call ever" on its own
	// (no field initializer here -- there is no precedent anywhere in this
	// codebase for one, and no way to confirm ZScript even allows it without
	// a test-compile this session cannot do). The default 0 is never
	// mistaken for "already matches", because everSet being false forces the
	// guard below to proceed regardless of what lastShape happens to hold.
	private int lastShape;

	// 0 = bracket reticle (the default), 1 = the original wireframe sphere.
	// Both files stay on disk permanently now -- this is a choice, not a
	// replacement.
	static int holsterMarkerShape()
	{
		let cv = CVar.GetCVar("rs_holster_marker_shape", players[consoleplayer]);
		return (cv != null) ? cv.GetInt() : 0;
	}

	// Live-tunable overall marker size, independent of the proximity-tighten
	// multiplier Tick() already applies -- that one is a fixed, momentary
	// squeeze as a hand approaches; this is a flat user preference, so it
	// composes with the tighten rather than replacing it. 1.0 leaves the
	// mesh at its authored unit-radius/Scale-3 size, same as before this
	// cvar existed.
	static double markerScale()
	{
		let cv = CVar.GetCVar("rs_holster_marker_scale", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 1.0;
	}

	// A fixed small palette, not an arbitrary color picker. GZDoom's
	// Translation is a per-CLASS Default property (Actor.Translation is
	// writable, but there is no runtime API in this fork for building an
	// arbitrary RGB translation from a plain int/color at a holster's own
	// spawn time without risking an unverified cast this session has no way
	// to test-compile) -- so each choice is its own subclass carrying one
	// hardcoded Translation string, in the same "%[desat]:[tint]" syntax
	// RS_Main already uses on monster skins (RS_Archvile.zs). SetHot() is
	// inherited unchanged by every one of them, and A_ChangeModel's modeldef
	// argument there is the LITERAL name 'RS_HolsterMarker', not
	// self.GetClassName() -- so every subclass still redirects model lookup
	// to the one MODELDEF block that actually exists, regardless of which of
	// these actually gets spawned. Translation is the only thing that
	// differs; model binding does not care which of these it is.
	//
	// Cold (idle) and hot (hand-in-range) are two INDEPENDENT choices, each
	// its own cvar -- picking the same color for both used to be the only
	// option there was, and a marker that looks identical whether or not a
	// hand is actually in range defeats the one thing the color is for.
	// hot selects which cvar gets read; the class list itself is shared.
	static class<Actor> holsterMarkerColorClass(bool hot)
	{
		string cvarName = hot ? "rs_holster_marker_color_hot" : "rs_holster_marker_color";
		let cv = CVar.GetCVar(cvarName, players[consoleplayer]);
		int c = (cv != null) ? cv.GetInt() : 0;
		switch (c)
		{
			case 1: return "RS_HolsterMarker_Blue";
			case 2: return "RS_HolsterMarker_Red";
			case 3: return "RS_HolsterMarker_Gold";
			case 4: return "RS_HolsterMarker_Purple";
			case 5: return "RS_HolsterMarker_Orange";
			case 6: return "RS_HolsterMarker_Green";
			case 7: return "RS_HolsterMarker_Cyan";
			case 8: return "RS_HolsterMarker_Pink";
			default: return "RS_HolsterMarker";
		}
	}

	void SetHot(bool hot)
	{
		int wantShape = holsterMarkerShape();
		if (everSet && hot == isHot && wantShape == lastShape)
			return;
		isHot = hot;
		everSet = true;
		lastShape = wantShape;

		// Literal labels only -- a StateLabel cannot be produced by a ternary
		// or built from a string at runtime.
		if (hot) { SetStateLabel("Hot"); }
		else     { SetStateLabel("Idle"); }

		// Swap the SKIN directly rather than trusting the frame to select a
		// different MODELDEF model slot. Two Model entries pointing at the
		// same .obj is exactly the case where slot selection is least certain,
		// and A_ChangeModel is the mechanism already proven to work on the
		// weapon props -- so use the one that is known good.
		name skinWanted = hot ? 'rs_wire_hot.png' : 'rs_wire_idle.png';
		name modelWanted = (wantShape == 1) ? 'rs_wiresphere.obj' : 'rs_holster_bracket.obj';
		A_ChangeModel('RS_HolsterMarker', 0, "models", modelWanted, 0, "models", skinWanted);
	}

	// 0 = no hand within sense range, 1 = hand exactly at the anchor. Fed by
	// the manager every tic (RS_Holsters.zs updateProps) from the same
	// hand-to-anchor distance updateClaims already computes for the claim
	// radius -- this marker has no way to know a hand position on its own.
	private double proximity01;

	void SetProximity(double t)
	{
		proximity01 = (t < 0.0) ? 0.0 : (t > 1.0) ? 1.0 : t;
	}

	// AMMO-DRIVEN GLOW. 0 = this marker wants to be invisible, 1 = it wants
	// its full authored alpha. Added 2026-08-26 for the chest ammo pouch
	// (AMMO_POUCH_IDX) and fed ONLY for that index -- see
	// RS_Holsters.zs pouchGlow()/pouchAmmoCurve().
	//
	// ammoDriven is the opt-in, and it is what keeps the other eight
	// holsters byte-for-byte unchanged. A marker that is never fed leaves it
	// false and Tick() below never touches its alpha at all; a zero-default
	// glow with no flag would instead read as "wants to be invisible" and
	// silently blank every torso holster on the first tic. No field
	// initializer to say otherwise -- there is no precedent for one anywhere
	// in this codebase (same reasoning as lastShape above), so the flag is
	// how the "not fed yet" state gets told apart from a real 0.0.
	//
	// NOT carried across the color-class respawn the way fadeAlpha is, and
	// that is a judgement, not an oversight: the fade carry exists because a
	// fresh marker would spend EIGHT tics fading back in, which is visible.
	// This one costs at most a single tic at the old brightness before the
	// manager feeds it again on the very next pass -- and the respawn only
	// happens on a hot/cold transition, i.e. with a hand already at the
	// pouch, which is the one moment the marker is meant to be lit anyway.
	// Not worth another pair of carry fields on every marker in the rig.
	private double ammoGlow01;
	private bool   ammoDriven;

	void SetAmmoGlow(double g)
	{
		ammoDriven = true;
		// Same nested-ternary clamp SetProximity uses. No bare clamp() here
		// for the same reason the manager's proximity feed gives for min():
		// the two files agree on plain comparisons and there is no
		// test-compile to settle it otherwise.
		ammoGlow01 = (g < 0.0) ? 0.0 : (g > 1.0) ? 1.0 : g;
	}

	// Read/write the fade state directly, for RS_HolsterManager to carry
	// across a color-class respawn (updateProps) when hot/cold toggles pick
	// different subclasses. Without this, every hand-enter/leave would
	// destroy and respawn the marker, and a fresh instance always starts at
	// fadeAlpha 0 -- the transition meant to read as instant (SetHot's skin
	// swap, the entry haptic) would fade in from invisible instead, every
	// single time.
	double GetFadeAlpha() const { return fadeAlpha; }
	bool GetFadeVisible() const { return fadeVisible; }

	void SetFadeState(double alpha, bool visible)
	{
		fadeAlpha = alpha;
		fadeVisible = visible;
		bINVISIBLE = (alpha <= 0.0);
	}

	// Fade instead of a hard bINVISIBLE cut. FADE_STEP is a CLASS-level
	// const, not a local one -- a const declared inside a method body has no
	// precedent anywhere in this codebase and no way to confirm ZScript even
	// allows it without a test-compile this session cannot do (caught making
	// exactly that mistake once already tonight, in RS_Holsters.zs).
	const FADE_STEP = 0.125;   // ~8 tics for a full fade, either direction

	private double fadeAlpha;
	private bool   fadeVisible;

	void SetVisible(bool show)
	{
		fadeVisible = show;
		if (show)
			bINVISIBLE = false;   // visible-but-transparent during fade-in, not hidden
	}

	override void Tick()
	{
		Super.Tick();

		if (fadeVisible)
		{
			fadeAlpha += FADE_STEP;
			if (fadeAlpha > 1.0) fadeAlpha = 1.0;
		}
		else
		{
			fadeAlpha -= FADE_STEP;
			if (fadeAlpha < 0.0) fadeAlpha = 0.0;
			if (fadeAlpha <= 0.0)
				bINVISIBLE = true;   // only actually hide once fully faded out
		}

		// Tighten: brackets draw inward as a hand approaches. Actor Scale is
		// a straight multiplier on top of MODELDEF's own Scale (RenderModel:
		// scaleFactorX = actor->Scale.X * smf->xscale) -- the same mechanism
		// RS_HolsterProp already uses to size the stored weapon, just driven
		// by proximity here instead of a fixed cvar. markerScale() composes on
		// top as a flat user preference, not a replacement for the tighten.
		double s = (1.0 - (0.28 * proximity01)) * markerScale();
		Scale = (s, s);

		// Pulse, hot state only -- a marker breathing at every holster all
		// the time is noise the player has to learn to filter out, which
		// defeats the point of a state cue. Idle stays flat at the base
		// alpha; only the one you could actually reach right now moves.
		// Multiplied by fadeAlpha, not replaced by it, so the pulse and the
		// fade compose instead of one clobbering the other mid-transition.
		// SOLID WHEN IDLE, 2026-08-29. This was 0.85, which read in the headset
		// as the stored weapon being see-through and got reported as a
		// ModelSwapper texture fault -- a translucent model shows its own back
		// faces, so a deliberate 15% became indistinguishable from a broken
		// mesh. A cue that gets mistaken for a defect is not doing its job.
		//
		// The HOT pulse keeps its translucency: that one is motion as well as
		// alpha, so it reads as a highlight rather than as a hole in the model,
		// and it only ever applies to the single holster you could reach.
		double baseAlpha = isHot ? (0.70 + 0.25 * sin(360.0 * ((level.time % 70) / 70.0))) : 1.0;

		// The ammo glow COMBINES with proximity rather than replacing it,
		// and the combination is a MAX, not a product. A product would mean
		// a full pouch stays invisible even with a hand inside it -- you
		// could not find the thing, aim at it, or confirm it was reacting,
		// which is exactly the "empty holster is invisible and the player
		// has nothing to aim a hand at" complaint the marker system exists
		// to answer in the first place (see this class's header comment).
		//
		// Reading it as "whichever reason to be visible is stronger right
		// now wins": low ammo lights it from across the room, a hand
		// reaching for it lights it regardless of how much ammo you have.
		// proximity01 is already 1.0 at the anchor and 0 at the edge of the
		// sense range, so a hand at the pouch always restores full alpha.
		//
		// This is also why the pulse is left alone: the hot pulse only ever
		// runs when a hand IS in range, which is precisely when proximity01
		// is near 1 and this multiplier is near 1 too.
		if (ammoDriven)
		{
			double lit = (ammoGlow01 > proximity01) ? ammoGlow01 : proximity01;
			baseAlpha *= lit;
		}

		Alpha = fadeAlpha * baseAlpha;
	}
}

// The color palette for RS_HolsterMarker.holsterMarkerColorClass(). Each one
// adds ONLY a Translation -- everything else (states, Tick, SetHot, the
// shape choice) is inherited unchanged, and SetHot's A_ChangeModel already
// redirects model lookup to the parent class's literal name regardless of
// which of these is actually spawned, so subclassing here cannot break model
// binding. Desaturation weights are the standard NTSC luma split
// (0.30/0.59/0.11) for all four -- only the tint range after that differs.
// Same "%[desat]:[tint]" syntax RS_Main already uses on monster skins
// (RS_Archvile.zs), not a new mechanism.
class RS_HolsterMarker_Blue : RS_HolsterMarker
{
	Default { Translation "0:255=%[0.30,0.59,0.11]:[0.35,0.65,2.00]"; }
}
class RS_HolsterMarker_Red : RS_HolsterMarker
{
	Default { Translation "0:255=%[0.30,0.59,0.11]:[2.00,0.35,0.35]"; }
}
class RS_HolsterMarker_Gold : RS_HolsterMarker
{
	Default { Translation "0:255=%[0.30,0.59,0.11]:[2.00,1.55,0.30]"; }
}
class RS_HolsterMarker_Purple : RS_HolsterMarker
{
	Default { Translation "0:255=%[0.30,0.59,0.11]:[1.40,0.35,1.85]"; }
}
class RS_HolsterMarker_Orange : RS_HolsterMarker
{
	Default { Translation "0:255=%[0.30,0.59,0.11]:[2.00,0.85,0.15]"; }
}
class RS_HolsterMarker_Green : RS_HolsterMarker
{
	Default { Translation "0:255=%[0.30,0.59,0.11]:[0.30,2.00,0.35]"; }
}
class RS_HolsterMarker_Cyan : RS_HolsterMarker
{
	Default { Translation "0:255=%[0.30,0.59,0.11]:[0.25,1.75,2.00]"; }
}
class RS_HolsterMarker_Pink : RS_HolsterMarker
{
	Default { Translation "0:255=%[0.30,0.59,0.11]:[2.00,0.30,1.10]"; }
}

class RS_HolsterProp : Actor
{
	Default
	{
		// RENDERSTYLE IS LOAD-BEARING, 2026-08-28. Without it this class
		// inherits Actor's own default of "Normal" (actor.zs:656), and
		// STYLE_Normal carries STYLEF_Alpha1 (renderstyle.cpp:38) -- which
		// makes the renderer THROW THE ACTOR'S ALPHA AWAY before drawing
		// (hw_sprites.cpp:1639, `else if (RenderStyle.Flags & STYLEF_Alpha1)
		// trans = 1.f;`). FRenderStyle::IsVisible forces alpha to 1 as well,
		// so a faded prop could not even be culled.
		//
		// The effect was that Tick()'s whole fade ramp rendered NOTHING: the
		// prop sat at full opacity for the 8 tics the ramp takes (1.0 /
		// FADE_STEP) and then popped out in one frame -- strictly WORSE than
		// the hard cut the ramp replaced, since it added the delay and
		// delivered none of the fade it was traded for. Fade-in was equally
		// inert.
		//
		// This went unnoticed for so long because the sibling class in this
		// same file, RS_HolsterMarker, declares RenderStyle "Add" -- and
		// STYLE_Add's flags are 0, no STYLEF_Alpha1 -- so the IDENTICAL fade
		// code visibly worked there the whole time.
		//
		// The engine's own fade helpers (A_FadeIn/A_FadeOut/A_FadeTo,
		// p_actionfunctions.cpp:1489/1523/1554) all clear STYLEF_Alpha1
		// before touching Alpha. This class writes Alpha directly, so it has
		// to declare a style that never sets the flag in the first place.
		//
		// RS_HardPointProp has the identical defect and needs the identical
		// line -- see the note in the audit doc.
		RenderStyle "Translucent";

		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		Radius 1;
		Height 1;
	}

	// A HOLSTERED WEAPON IS WEARING SOMEONE ELSE'S MODEL.
	//
	// A_ChangeModel binds the real weapon's MODELDEF to this prop, and that
	// definition opts into actor YAW only -- MDL_USEACTORPITCH and
	// MDL_USEACTORROLL are per-definition opt-ins, and no weapon declares them,
	// because a weapon in your hand is posed by the psprite path instead.
	//
	// So the pitch and roll this subsystem carefully computes and writes every
	// tic (RS_Holsters.zs:1715) were discarded by the renderer before anything
	// could be drawn. That is the whole of "only the yaw slider does anything":
	// the other two were moving numbers nothing ever read.
	//
	// Setting the flags on the borrowed definition is not available -- it is
	// shared with the weapon itself, so trimming how a pistol SITS IN A HOLSTER
	// would change how that pistol is drawn in your hand. ForceModelAngles is
	// the per-actor opt-in added for this, 2026-08-28.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		ForceModelAngles = true;
	}

	// The class currently displayed, so a re-show with the same weapon does
	// not rebind the model every tic. Actor, not Weapon: this is now the
	// RESOLVED model class from level.GetActorModelClass(w), which can be a
	// donor class belonging to a completely different mod (ModelSwapper)
	// rather than the weapon's own class.
	class<Actor> shownClass;
	// The class the model was ACTUALLY bound from. shownClass is the
	// change-detection key (the GetActorModelClass donor) and stays that
	// even when the ModelSwapper retry rebinds to the MS_PU_ pickup class
	// with sprite/frame pinned -- so anything that asks the engine about
	// this prop's model has to name THIS class, or it asks about a
	// (class, sprite, frame) triple that has no model and gets "not found".
	class<Actor> boundClass;

	// Measured, not guessed. Whether THIS specific weapon's MODELDEF mirrors
	// it (negative X Scale) plus its own baked AngleOffset/PitchOffset/
	// RollOffset, read via level.GetModelOrientationHint -- the native that
	// exposes exactly what FindModelFrameRaw already knows internally.
	//
	// The thing this replaced: "needsFlip = !offhand" assumed mirroring
	// correlates with which hand a weapon is normally held in. It does not.
	// Scale sign is a per-model AUTHORING choice -- chainsaw is -1.5 X, SMG is
	// -1.0 X, rifle/pistol/revolver are positive and unmirrored -- with zero
	// relationship to hand assignment. That mismatch is why some stored
	// weapons pointed forward, some backward, some sideways: one global
	// guess cannot be right for a mixed-convention arsenal.
	bool   mirrored;
	double bakedAngleOffset;
	double bakedPitchOffset;
	double bakedRollOffset;

	// The model's baked POSITION offset (MODELDEF Offset/ZOffset), from
	// level.GetModelOffsetHint. Different bug from the rotation ones above:
	// this is why a stored weapon did not sit at the actor's own origin, not
	// why it pointed the wrong way. Expressed in the model's own LOCAL axes
	// (pre-rotation) -- the manager rotates it by the same angle/pitch it
	// assigns the actor before applying it, since that offset gets carried
	// along by the actor's rotation in the renderer (r_data/models.cpp: the
	// offset translate is composed INSIDE the actor rotation, not after it).
	double bakedOffX;
	double bakedOffY;
	double bakedOffZ;

	// The model's measured bounding radius (level.GetModelBoundsHint),
	// cached from the last class-change so ShowWeapon can recompute
	// baseScale from it EVERY call, not just when the weapon class
	// changes -- rs_holster_prop_fill/_scale/_scale_arm need to apply
	// live to an already-holstered weapon, not just to the next weapon
	// that gets stored. Re-measuring the model itself every tic would be
	// the expensive part (native call + FindModelFrame lookup); this way
	// only the measurement is class-change-gated, and the cheap arithmetic
	// that turns it into a scale runs unconditionally.
	bool   boundsFound;
	double measuredRadius;

	// Live-tunable rather than baked, for the same reason the anchors are:
	// the right number is found by looking at it in the headset, not by
	// reasoning about model units.
	static double holsterPropScale()
	{
		let cv = CVar.GetCVar("rs_holster_prop_scale", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.18;
	}

	// Separate, smaller default for the forearm/wrist hardpoints -- a
	// utility item riding a wrist mount should read as compact gear, not a
	// full holstered sidearm. Its OWN cvar rather than reusing
	// rs_holster_prop_scale means tuning one range never shrinks the other.
	static double holsterPropScaleArm()
	{
		let cv = CVar.GetCVar("rs_holster_prop_scale_arm", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.08;
	}

	// Fraction of the holster's own radius a measured model gets scaled to
	// fill. See CVARINFO.txt for why this is a separate dial from the flat
	// scale/scale_arm fallbacks rather than replacing them.
	static double holsterPropFill()
	{
		let cv = CVar.GetCVar("rs_holster_prop_fill", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.55;
	}

	// The display-size target holsterPropFill() scales a measured model
	// toward, in map units. Deliberately NOT a holster's own hsRadius
	// (RS_Holsters.GetHolster) -- see ShowWeapon's doc comment for why.
	static double holsterPropVisualRadius()
	{
		let cv = CVar.GetCVar("rs_holster_prop_visual_radius", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 8.0;
	}

	// The flat size a model gets when the engine cannot measure it -- no bounds
	// survive in memory for some formats, so there is nothing to fit against
	// and a constant is the only honest answer. Was the default of
	// rs_holster_prop_scale back when that cvar WAS this number; it is a
	// constant now because that cvar became a multiplier over both solves,
	// which is what made the size slider work on measured weapons at all.
	const UNMEASURED_SCALE = 0.18;

	// The same one diagnostic gate the rest of this repo uses. RS_Holsters has
	// its own copy (verboseDiag) because it is a different class and ZScript
	// has no shared free functions -- same cvar, same meaning, read the same
	// way, so the two stay in step by reading one name rather than by anyone
	// remembering to update both.
	static bool holsterVerbose()
	{
		let cv = CVar.GetCVar("rs_holster_verbose", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : false;
	}

	// Yaw offset applied to every stored weapon, and a separate 180 for
	// main-hand weapons whose models are mirrored.
	//
	// This comment used to claim pitch and roll DO NOTHING and that yaw was the
	// only axis the renderer honoured. That was never a property of the engine
	// -- it was two stacked content bugs being mistaken for one. RenderModel
	// applies yaw unconditionally but gates pitch on MDL_USEACTORPITCH and roll
	// on MDL_USEACTORROLL, and neither flag was reaching the render table:
	// first because the MODELDEF tokens sat AFTER their FrameIndex lines (each
	// FrameIndex snapshots the flags set so far), and then, after that was
	// fixed, because a backup file named MODELDEF.bak2 in the mod root
	// registered under the same 8-character lump name "MODELDEF", parsed
	// second, and won the frame lookup with its stale flagless entries.
	// All three axes work. Keep this a slider anyway -- the right number is
	// found by looking at it in the headset, not by reasoning about it.
	static double holsterPropYaw()
	{
		let cv = CVar.GetCVar("rs_holster_prop_yaw", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.0;
	}

	// Fallback was 90.0 here while CVARINFO.txt declared the cvar's real
	// default as 0.0 -- two places stating the same default, silently
	// disagreeing. That mattered: GetHolster's own table already defaults
	// EVERY torso holster's hsPitch to 90.0 (barrel down), and edPitch[h]
	// (below, via updateProps/dumpOneHolsterProp) is a straight copy of it
	// -- this cvar is documented as a TRIM on top of that per-holster
	// value, not a second full contribution. At the old 90.0 fallback,
	// clean defaults summed to 180 degrees (90 from the table, 90 again
	// here), not 90 -- nowhere near "points at the floor", and close
	// enough to the flip-over point that per-weapon pitch differences
	// pushed some guns visibly up and others down. 0.0 matches CVARINFO.txt
	// and actually behaves like a trim: does nothing until you move it.
	static double holsterPropPitch()
	{
		let cv = CVar.GetCVar("rs_holster_prop_pitch", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.0;
	}

	static double holsterPropRoll()
	{
		let cv = CVar.GetCVar("rs_holster_prop_roll", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.0;
	}

	// Centring nudge, in the body's own frame. A weapon's MODELDEF carries an
	// Offset tuned for the HUD (the chainsaw's is "Offset 0.0 14.0 0.0"), which
	// puts the mesh well away from the actor origin. Scaling then shrinks the
	// model toward that origin rather than toward anything you can see, so it
	// drifts out of the sphere. There is no way to read a MODELDEF Offset from
	// script, so this is a manual correction -- and a slider, because the right
	// value is whatever makes it sit in the ring.
	static double holsterPropUp()
	{
		let cv = CVar.GetCVar("rs_holster_prop_up", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.0;
	}

	static double holsterPropFwd()
	{
		let cv = CVar.GetCVar("rs_holster_prop_fwd", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.0;
	}

	static double holsterPropSide()
	{
		let cv = CVar.GetCVar("rs_holster_prop_side", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.0;
	}

	// Fade instead of a hard bINVISIBLE cut, same mechanism as
	// RS_HolsterMarker (own copy, not shared -- these two classes have no
	// common base below Actor to hang a shared const/method off of).
	const FADE_STEP = 0.125;

	// The store/draw settle pop: a fresh weapon starts slightly OVERSIZED and
	// eases down to its real scale over POP_TICS, instead of just appearing
	// at final size. Pure polish -- POP_OVERSHOOT of 1.0 would make this a
	// no-op, so nothing breaks if these ever need retuning.
	const POP_TICS = 6;
	const POP_OVERSHOOT = 1.35;

	private double fadeAlpha;
	private bool   fadeVisible;
	private double baseScale;
	private int    popTicsRemaining;

	// Set true only by the w==null branch of ShowWeapon, and consumed here
	// once the fade-out actually finishes. The model/sprite reset used to
	// happen IMMEDIATELY on that transition -- but that is exactly what a
	// fade-out needs to still be showing while it plays. Clear on the spot
	// and there is nothing left to fade; defer it and the old weapon fades
	// out looking like itself, then vanishes for real only once Alpha has
	// actually reached 0.
	private bool pendingClear;

	void SetVisible(bool show)
	{
		fadeVisible = show;
		if (show)
			bINVISIBLE = false;
	}

	override void Tick()
	{
		Super.Tick();

		if (fadeVisible)
		{
			fadeAlpha += FADE_STEP;
			if (fadeAlpha > 1.0) fadeAlpha = 1.0;
		}
		else
		{
			fadeAlpha -= FADE_STEP;
			if (fadeAlpha < 0.0) fadeAlpha = 0.0;
			if (fadeAlpha <= 0.0)
			{
				bINVISIBLE = true;
				if (pendingClear)
				{
					ClearModelStateFrames();
					sprite = GetSpriteIndex("TNT1");
					frame = 0;
					pendingClear = false;
				}
			}
		}
		Alpha = fadeAlpha;

		double popMult = 1.0;
		if (popTicsRemaining > 0)
		{
			// (popTicsRemaining * 1.0) rather than a double(...) cast -- no
			// precedent anywhere in this codebase for that cast syntax in
			// ZScript specifically, and no way to test-compile to find out.
			// Multiplying by a double literal forces float promotion using
			// only ordinary arithmetic operator rules, which every C-family
			// language shares regardless of its exact cast syntax.
			double t = 1.0 - ((popTicsRemaining * 1.0) / POP_TICS);
			popMult = POP_OVERSHOOT - ((POP_OVERSHOOT - 1.0) * t);
			popTicsRemaining--;
		}
		Scale = (baseScale * popMult, baseScale * popMult);
	}

	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	}

	// Show a weapon, or pass null to go empty/invisible. fallbackScale is
	// always passed in explicitly by the caller (holsterPropScale() or
	// holsterPropScaleArm(), picked per-holster in updateProps) rather than
	// read here via a default parameter value -- no confirmed precedent for
	// user-method default args anywhere in this codebase, and no way to
	// test-compile to find out, so the one call site just always supplies it.
	// visualRadius is the display-size target a measured model gets scaled to
	// fill (RS_HolsterProp.holsterPropVisualRadius(), a cvar) -- NOT a
	// holster's own hsRadius (grab/claim detection, RS_Holsters.GetHolster).
	// Those two used to be the same number; decoupled because a claim sphere
	// sized for reach detection has no reason to also be the visual size
	// budget every stored weapon gets capped at.
	void ShowWeapon(Weapon w, double fallbackScale, double visualRadius)
	{
		// GetActorModelClass, not w.GetClass() -- reads what THIS INSTANCE
		// actually resolves against right now, which is a donor class
		// rather than w's own class whenever something else (ModelSwapper,
		// or anything working the same way) has model-swapped w
		// per-instance. w's own class remains the answer for everything
		// that was never touched that way -- this is a strict superset of
		// the old behavior, not a different one for the common case.
		let wantClass = (w != null) ? level.GetActorModelClass(w) : null;
		if (wantClass != shownClass)
		{
			shownClass = wantClass;

			if (w == null)
			{
				pendingClear = true;   // Tick() clears the model once faded out
				SetVisible(false);
				mirrored = false;
				bakedAngleOffset = 0.0;
				bakedPitchOffset = 0.0;
				bakedRollOffset = 0.0;
				bakedOffX = 0.0; bakedOffY = 0.0; bakedOffZ = 0.0;
				boundsFound = false;
				measuredRadius = 0.0;
				return;
			}

			// The held-weapon frame is the one MODELDEF covers. Ready is where
			// a weapon idles, so it is the pose a holstered gun should sit in.
			State rs = w.FindState("Ready");
			if (rs == null)
			{
				SetVisible(false);
				return;
			}

			pendingClear = false;   // showing something new; any stale deferred clear is moot
			SetVisible(true);
			sprite = rs.sprite;
			frame  = rs.Frame;

			bool found;
			[found, mirrored, bakedAngleOffset, bakedPitchOffset, bakedRollOffset]
				= level.GetModelOrientationHint(wantClass, sprite, frame);

			double stretch = (level.info != null) ? level.info.pixelstretch : 1.0;
			bool foundOff;
			[foundOff, bakedOffX, bakedOffY, bakedOffZ]
				= level.GetModelOffsetHint(wantClass, sprite, frame, stretch);

			// Measured once per class-change, same as the orientation/offset
			// hints above -- the native call and FindModelFrame lookup are
			// the expensive part. What that measurement is USED for (below)
			// is not gated the same way.
			[boundsFound, measuredRadius] = level.GetModelBoundsHint(wantClass, sprite, frame);

			// A foreign model-swap (ModelSwapper, or anything working the
			// same way) resolves wantClass to a donor class -- but the
			// donor's MODELDEF is keyed against ITS OWN anchor sprite/frame,
			// not w's real compiled Ready sprite/frame. ModelSwapper keeps
			// its HUD-hand and world/pickup anchors deliberately disjoint
			// from the foreign weapon's own sprites (its own docs call this
			// "the disjoint-anchor invariant"), so w's real sprite letter
			// never appears in the donor's FrameIndex table and every hint
			// above comes back not-found -- nothing renders, even though
			// wantClass itself resolved correctly. ModelSwapper's own
			// world/pickup binder (RS_ForeignPickups.zs) anchors every donor
			// on sprite "SHOT" frame 0 for exactly this "not currently in a
			// HUD hand" case -- a holstered prop is that, not a HUD-held
			// weapon, so retry against the same anchor before giving up.
			// Gated on the real sprite having already failed, so an ordinary
			// (non-swapped) weapon whose OWN bounds genuinely cannot be
			// measured still falls back to fallbackScale below as before,
			// rather than being pointed at an unrelated generic sprite.
			if (!boundsFound && wantClass != w.GetClass())
			{
				int foreignSpr = Actor.GetSpriteIndex("SHOT");
				if (foreignSpr >= 0)
				{
					SpriteID realSprite = sprite;
					int realFrame = frame;
					sprite = foreignSpr;
					frame  = 0;

					[found, mirrored, bakedAngleOffset, bakedPitchOffset, bakedRollOffset]
						= level.GetModelOrientationHint(wantClass, sprite, frame);
					[foundOff, bakedOffX, bakedOffY, bakedOffZ]
						= level.GetModelOffsetHint(wantClass, sprite, frame, stretch);
					[boundsFound, measuredRadius] = level.GetModelBoundsHint(wantClass, sprite, frame);

					// CONFIRMED WRONG IN HEADSET, 2026-08-28: the donor class
					// itself is never the one anchored on SHOT/A. ModelSwapper
					// generates a SEPARATE display class per donor for exactly
					// that anchor (RS_ForeignPickups.zs, MS_PickupModel and its
					// ~35 generated subclasses -- "MS_BD_Rifle|MS_PU_BD_Rifle",
					// "MS_Pistol|MS_PU_Pistol", etc.), always named by stripping
					// the "MS_" prefix and adding "MS_PU_" back -- checked
					// against the full list in this install, zero exceptions.
					// Querying the donor class directly for SHOT/A, as this
					// retry used to, always fails: bounds=0 found=0 offFound=0
					// every single time, confirmed against real PB_DMR/MS_BD_
					// Rifle and PB_Pistol/MS_Pistol logs.
					string donorName = wantClass.GetClassName();
					if (donorName.Left(3) == "MS_")
					{
						class<Actor> pickupClass = (class<Actor>)("MS_PU_" .. donorName.Mid(3));
						if (pickupClass != null)
						{
							[found, mirrored, bakedAngleOffset, bakedPitchOffset, bakedRollOffset]
								= level.GetModelOrientationHint(pickupClass, sprite, frame);
							[foundOff, bakedOffX, bakedOffY, bakedOffZ]
								= level.GetModelOffsetHint(pickupClass, sprite, frame, stretch);
							[boundsFound, measuredRadius] = level.GetModelBoundsHint(pickupClass, sprite, frame);

							// Found it under the PICKUP class -- that is what
							// actually has to be bound via A_ChangeModel below,
							// not the donor wantClass started as.
							if (boundsFound)
								wantClass = pickupClass;
						}
					}

					// Neither the donor nor its pickup class (or this install
					// has no "MS_" donor at all -- some OTHER foreign-model
					// system, not ModelSwapper) resolved anything. sprite/frame
					// are this actor's own native rendering fields, not just a
					// model-lookup key, so leaving them pinned to SHOT/0 would
					// show a generic shotgun-pickup icon instead of the real
					// weapon's own. Put the real values back; no model
					// resolved either way, so fallbackScale below applies same
					// as any other unmeasurable weapon.
					if (!boundsFound)
					{
						sprite = realSprite;
						frame  = realFrame;
					}

					// GATED, 2026-08-28. This was the live probe for "ModelSwapper
					// weapons show no model in holsters," and it did its job: it
					// proved the donor class itself never resolves on SHOT/A and
					// the MS_PU_ pickup class does. CONFIRMED WORKING IN HEADSET
					// against both Brutal Doom and Project Brutality that same
					// day. Kept rather than deleted, behind the same one gate the
					// rest of this repo uses, because the MS_PU_ prefix is a
					// convention read off ModelSwapper's own generated class
					// list -- if that mod ever renames them, this line is what
					// says so immediately instead of another blind chase.
					if (holsterVerbose())
						Console.Printf("\cy RS_HOLSTERPROP: ModelSwapper retry for %s -- resolved class %s -- bounds=%d",
							w.GetClassName(), wantClass.GetClassName(), boundsFound);
				}
			}

			if (!found)
			{
				mirrored = false;
				bakedAngleOffset = 0.0;
				bakedPitchOffset = 0.0;
				bakedRollOffset = 0.0;
			}
			if (!foundOff)
			{
				bakedOffX = 0.0; bakedOffY = 0.0; bakedOffZ = 0.0;
			}

			popTicsRemaining = POP_TICS;   // settle-pop on every fresh show

			// GATED, 2026-08-28, same as the retry print above. Covers the
			// case that print never fires at all, which is itself
			// diagnostic: wantClass == w.GetClass() here means
			// GetActorModelClass never saw a donor swap for this weapon in
			// the first place, so ModelSwapper compatibility never had a
			// chance to matter -- a completely different problem than the
			// SHOT/0 anchor failing.
			if (holsterVerbose())
				Console.Printf("\cy RS_HOLSTERPROP: A_ChangeModel(%s) for %s -- boundsFound=%d sprite=%d frame=%d",
					wantClass.GetClassName(), w.GetClassName(), boundsFound, sprite, frame);

			// Borrow the RESOLVED model definition onto this instance --
			// wantClass, not w.GetClassName(). After this, FindModelFrame
			// resolves against that class rather than RS_HolsterProp, and
			// the (sprite, frame) set above completes the key.
			boundClass = wantClass;
			A_ChangeModel(wantClass.GetClassName());
		}

		if (w == null)
			return;   // still nothing to show; nothing below has anything to recompute

		// A weapon's MODELDEF Scale is tuned for the HUD/psprite path, where
		// the model sits inches from the camera under its own projection. Reuse
		// that scale on a world actor and you get a rifle the size of a car --
		// which is exactly what happened. Shrink it back to something that
		// reads as the same object you were just holding. fallbackScale is
		// that flat shrink, used as-is when there is no real geometry to
		// measure.
		//
		// When there IS real geometry, solve for the scale that makes this
		// SPECIFIC model's measured bounding radius fill a fraction of THIS
		// holster's own radius, instead of applying fallbackScale (a flat
		// number identical for every weapon) regardless of how physically
		// big the model actually is -- a BFG and a pistol stop reading as
		// the same size for no reason other than sharing one constant.
		//
		// Recomputed EVERY call (every tic), not just on a class-change --
		// otherwise rs_holster_prop_fill/_scale/_scale_arm read as dead
		// cvars on any weapon that is already sitting in a holster, since
		// nothing else ever re-solves baseScale for it. Cheap: this is just
		// arithmetic over the cached measurement above, no native call.
		// THE SIZE SLIDER NOW APPLIES TO EVERY WEAPON, 2026-08-28.
		//
		// It used to live in the `else` alone, which made it dead for any
		// weapon the engine could actually measure -- and that is most of them.
		// The menu row said "Stored weapon size", the player dragged it, and
		// nothing moved, because a measured model's size came entirely from
		// visualRadius * fill / measuredRadius and never consulted it at all.
		// The only weapons it ever moved were the ones whose bounds could not
		// be read, which is exactly the set a player never knowingly picks.
		//
		// So the two solves now decide a BASE size and the slider is a
		// multiplier over both. Measured models still auto-fit to the holster
		// -- a BFG and a pistol still arrive proportionate, which is the whole
		// point of measuring -- and the slider scales that result up or down as
		// a matter of taste. Unmeasurable models keep the flat fallback they
		// always had, now also multiplied, so one control means one thing
		// everywhere.
		if (boundsFound && measuredRadius > 0.0)
			baseScale = (visualRadius * holsterPropFill()) / measuredRadius;
		else
			baseScale = UNMEASURED_SCALE;

		baseScale *= fallbackScale;

		// Also write the real Scale here, not just baseScale -- Tick() is
		// the only other writer, and the engine runs WorldTick (this call's
		// caller, updateProps) BEFORE Thinkers.RunThinkers (what actually
		// calls Tick()) every tic, confirmed in p_tick.cpp. updateProps
		// calls GetModelWorldOffset for centering using p.scale.X/Y right
		// after this returns, in the SAME WorldTick pass -- without this
		// line that call would read whatever Scale was left over from
		// LAST tic (a different weapon's size, on a fresh store) instead
		// of the value just solved above. Tick()'s pop-overshoot ramp
		// still overwrites this a moment later; this just makes sure
		// nothing reads a stale, wrong-weapon Scale in the meantime.
		Scale = (baseScale, baseScale);
	}
}
