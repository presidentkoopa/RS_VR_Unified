// THE THING IN YOUR HAND.
//
// RS_Hands poses the fingers into a magazine grip and there is nothing between
// them until this exists. The pose is only half the picture; a hand closed on
// air reads as a bug, not as a reload.
//
// HOW IT IS DRAWN, AND WHY THIS WAY.
//
// Three ways were on the table and only one of them is the pattern this stack
// has already proven:
//
//   * a world actor following the hand -- MDL_FOLLOWOFFHAND. Off the table.
//     A followed model is culled on its real world position while being drawn at
//     your hand, and world-actor placement is the thing fifteen attempts died
//     on. Not revisiting it for a magazine.
//   * a second mesh slot on RS_Hands' own hand model. Puts the mag literally in
//     the fingers, which is the nicest answer, and requires editing another
//     package plus hanging an untested `Model 1` off a BaseFrame IQM. Two
//     unknowns to save one file.
//   * ITS OWN PSPRITE LAYER. Which is exactly what RS_Hands does for the HANDS
//     THEMSELVES -- MODELDEF.txt says so outright: a weapon owns the controller's
//     hand slot, so the hands "ride their own psprite layers instead, so they are
//     visible no matter what is held". A magazine has the same problem and takes
//     the same answer.
//
// So: one more layer on the off hand, drawn by the same SetPsprite call, with
// the same UseHandOffsets / NOAUTOREVERSE / PitchOffset 90 / BaseFrame block the
// hands use. Nothing is added to RS_Hands and no new engine behaviour is asked
// for.
//
// ONE CLASS PER FEED FAMILY, not one class with A_ChangeModel swapping its mesh.
// Runtime model swapping against a BaseFrame + DECOUPLEDANIMATIONS actor is
// uncharted here, and MODELDEF's own rule is that BaseFrame is the only thing
// that registers hasmodel. Five tiny classes with five static MODELDEF blocks
// ask nothing of the engine that the hands do not already ask.
//
// FIVE MESHES FOR EVERY GUN THAT WILL EVER LOAD. Authoring a magazine per weapon
// does not scale to "any mod with 3D models" -- nobody is modelling 400
// magazines. A generic mag IS the correct answer for a universal system, not a
// compromise in place of one.

class RR_AmmoInHand : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		Inventory.InterHubAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.QUIET
		// Model lookup goes through BaseSpriteModelFrames rather than the
		// state's sprite and frame, which is what lets the placeholder below
		// be TNT1.
		+DECOUPLEDANIMATIONS
	}

	States
	{
	Spawn:
		// TNT1 IS CORRECT HERE, despite being an instruction to skip the actor
		// on the ordinary path. A DECOUPLEDANIMATIONS actor resolves its model
		// through BaseSpriteModelFrames and never consults the state's sprite,
		// so there is nothing to skip. RS_Hands' own hand actors do exactly
		// this -- copying the proven pattern rather than inventing a
		// placeholder sprite that would need a TEXTURES entry to bind to.
		TNT1 A -1;
		Stop;
	}
}

// One per feed family. The MODELDEF block for each names its own mesh, so
// nothing has to be swapped at runtime.
class RR_AmmoMag   : RR_AmmoInHand {}   // box, bolt -- a detachable magazine
class RR_AmmoShell : RR_AmmoInHand {}   // pump, break -- a single shell
class RR_AmmoCell  : RR_AmmoInHand {}   // cell -- an energy pack
class RR_AmmoPod   : RR_AmmoInHand {}   // pod -- a rocket or grenade
class RR_AmmoBelt  : RR_AmmoInHand {}   // belt -- a linked belt

// PLAY SCOPE, DECLARED -- and it belongs on the CLASS, not on the methods.
//
// This class went in with no scope keyword and no parent. A ZScript class that
// names neither is plain data (zcc_compile.cpp:1006-1020), and every function in
// it inherits that (zcc_compile.cpp:2551-2552 sets VARF_Play from the class's own
// ScopeFlags; `static` at :2585 only clears VARF_Method, so static methods take
// the class scope too). Meanwhile the body of Show() is a near-verbatim copy of
// RS_Hands' hand-layer routine (rs_hands.zs:320-349) -- FindInventory,
// GiveInventory, FindPSprite, FindState, SetPsprite, scale. That copy compiles
// over there only because its container is `class RS_HandsAlwaysOn : EventHandler`
// and EventHandler descends from `StaticEventHandler : Object native play`. The
// code was lifted; the scope it depended on was not.
//
// ON THE CLASS and not on each method, for three reasons:
//   * it is what the borrowed-from code actually has -- one container, play, and
//     everything inside it inherits;
//   * every function here is play or wants to be, so five `play` qualifiers would
//     say the same thing five times and leave the sixth to be forgotten;
//   * the precedent that actually PROVES the construct is stock, not local:
//     `class ScriptUtil play` (E:\UZDXREMA\wadsrc\static\zscript\scriptutil\
//     scriptutil.zs:20) is parentless, play-qualified, and its STATIC
//     GiveInventory calls the play method activator.GiveInventory -- exactly
//     this shape, shipping in the engine's own stdlib.
//
//     rr_point.zs:35 and rr_feed.zs:55 carry the same marker, but they are a
//     HOUSE-STYLE note and not evidence: they live in a pk3 that had never
//     compiled, so citing them to prove what the parser accepts is circular.
//     That distinction is worth keeping -- this package has already been bitten
//     by confident comments describing behaviour nobody had verified.
//
// SAFE FOR THE CALLERS. All three call sites -- rr_sequence.zs:164, :182, :501 --
// are methods of `class RR_Reload : EventHandler`, which is play. Narrowing to
// play cannot bar them. Nothing ui-side touches this class.
class RR_Ammo play
{
	// ABOVE RS_Hands' OFF-HAND LAYER. 1900000 is what puts a layer on the other
	// controller (it is >= PSprite.OFFHANDWEAPON); RS_Hands parks its off hand
	// exactly there, so this sits just above it and draws over the fingers
	// rather than under them.
	// ONE LAYER PER HAND, because either hand can be the feeder. 1900000 is what
	// puts a layer on the OFF controller (>= PSprite.OFFHANDWEAPON); below that
	// is the main. RS_Hands parks its hands at 900000 / 1900000, so these sit
	// just above each and draw over the fingers rather than under them.
	const LAYER_MAIN = 900010;
	const LAYER_OFF  = 1900010;

	static int LayerFor(int hand) { return (hand == 0) ? LAYER_MAIN : LAYER_OFF; }

	// Which mesh a family carries. The whole per-weapon-asset problem collapses
	// to this one function.
	static Name ClassFor(int feed)
	{
		switch (feed)
		{
		case RR_F_BOX:
		case RR_F_BOLT:  return 'RR_AmmoMag';
		case RR_F_PUMP:
		case RR_F_BREAK: return 'RR_AmmoShell';
		case RR_F_CELL:  return 'RR_AmmoCell';
		case RR_F_POD:   return 'RR_AmmoPod';
		case RR_F_BELT:  return 'RR_AmmoBelt';
		}
		return 'None';
	}

	// AMMO IS IN THE HAND ONLY BETWEEN PULLING THE OLD ONE AND SEATING THE NEW.
	//
	// Which is the LEAVE beat and nothing else. Showing it on the opening TOUCH
	// would put a fresh magazine in your hand before you had removed the old
	// one, and leaving it up through the closing TOUCH would leave one there
	// after it went into the gun -- both of which read as the mesh being stuck.
	static void Show(PlayerInfo p, int feed, int hand)
	{
		Name cls = ClassFor(feed);
		// GUARD p ITSELF, not just p.mo. Hide() has done this since it was
		// written (`if (!p) return;`, below) and Show() never did -- so the same
		// null PlayerInfo was a clean return through one door and a VM abort
		// through the other. rr_sequence.zs:501 checks pmo.player before
		// calling Hide, but the two Show call sites (:164, :182) pass p through
		// unchecked, so the asymmetry was reachable rather than theoretical.
		if (!p) return;
		if (cls == 'None') { Hide(p, hand); return; }

		let pmo = p.mo;
		if (!pmo) return;

		let it = pmo.FindInventory(cls);
		if (!it)
		{
			pmo.GiveInventory(cls, 1);
			it = pmo.FindInventory(cls);
			if (!it) return;
		}

		int layer = LayerFor(hand);
		let psp = p.FindPSprite(layer);
		if (!psp || psp.Caller != it)
		{
			// FindState and not ResolveState: ResolveState is an action function
			// and aborts when called with no state context. RS_Hands hit this
			// first and left the note.
			State st = it.FindState("Spawn");
			if (!st) return;
			p.SetPsprite(layer, st, false, it);
			psp = p.FindPSprite(layer);
			if (!psp) return;
		}

		// "EXPRESSION MUST BE A MODIFIABLE VALUE" WAS THIS SAME SCOPE FAULT WEARING
		// A DIFFERENT ERROR MESSAGE, and it is worth writing down because the
		// message actively misleads.
		//
		// PSprite.scale is `native Vector2 scale` -- not readonly, and stock
		// ZScript writes it (wadsrc weapons.zs:326-327). What blocked it was the
		// WRITE BARRIER: PSprite is `Object native play` (player.zs:3075), so the
		// field is play, and a play field is READABLE from data scope but not
		// WRITABLE. The compiler does not say so, because
		// FxStructMember::RequestAddress (codegen.cpp:7647-7666) reports a barred
		// write by returning true with *writable = false, and FxAssign::Resolve
		// (codegen.cpp:2845) prints its own generic message for that instead of
		// the scopeBarrier.writeerror it just computed. So the same missing `play`
		// on the class produced three "can't call play function" and one
		// "modifiable value" -- one cause, two vocabularies.
		//
		// With the class play-scoped this is legal, and RS_Hands proves it: the
		// identical line, on the identical field, from an EventHandler method --
		// rs_hands.zs:349, `psp.scale = (s, s);`.
		double s = Scale(p);
		psp.scale = (s, s);
	}

	static void Hide(PlayerInfo p, int hand)
	{
		if (!p) return;
		let psp = p.FindPSprite(LayerFor(hand));
		if (psp) psp.SetState(null);
	}

	// RUSTED LEGACY'S MESHES WERE BAKED FOR RUSTED LEGACY'S SCALE. Its MODELDEF
	// drew them at Scale -1/1/1 with Offset 0 -24 -10; RS_Hands' psprite path
	// works out to 173.44 units per metre and its hand mesh is baked 1875x
	// oversized to suit. Those two do not agree, and a model scaled for one path
	// is wildly wrong on the other -- this is the entire "100x" class of bug.
	//
	// So the size is a slider rather than a guess. One number for all five,
	// because they came out of the same file at the same scale.
	// LIVE. rr_ammo_scale is a user cvar with a MENUDEF slider (CVARINFO.txt:38,
	// MENUDEF.txt:68), and Show() reads it every call. It multiplies the measured
	// per-mesh MODELDEF scale rather than replacing it -- the measurement is the
	// baseline, this is the nudge on top.
	static double Scale(PlayerInfo p)
	{
		let c = CVar.GetCVar("rr_ammo_scale", p);
		double v = c ? c.GetFloat() : 1.0;
		return (v > 0) ? v : 1.0;
	}
}
