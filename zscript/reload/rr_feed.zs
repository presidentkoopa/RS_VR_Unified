// WHAT KIND OF GUN, AND HOW IT LOADS. Data. No behaviour lives here.
//
// TWO AXES, AND KEEPING THEM APART IS THE WHOLE DESIGN.
//
//   archetype -- what the gun IS.  Sets its SIZE.      14 of them.
//   feed      -- how it RELOADS.   Sets its SEQUENCE.   7 of them.
//
// They are separate because they collapse at different rates. A revolver and a
// break-action shotgun are nothing alike as guns and load identically; a pistol
// and a sniper rifle load identically and are nothing alike as guns. Fourteen
// archetypes fold into seven sequences, and that fold is what makes this
// universal instead of a table of every weapon anyone ever shipped.
//
// Authoring a magazine mesh or a reload sequence PER WEAPON does not scale to
// "any mod with 3D weapon models", which is the actual goal. Per FAMILY does,
// and it is the same seven either way.

enum RR_FeedKind
{
	RR_F_NONE = 0,   // no manual reload -- melee, or fall through to vanilla
	RR_F_BOX,        // detachable box magazine
	RR_F_BOLT,       // box magazine plus a cycle after
	RR_F_PUMP,       // shells into a port, then racked
	RR_F_BREAK,      // hinge open, load, close
	RR_F_BELT,       // cover up, belt in, cover down
	RR_F_POD,        // a single large round into a tube
	RR_F_CELL,       // energy pack swap
	RR_F_MAX
}

enum RR_ArchKind
{
	RR_A_PISTOL = 0,
	RR_A_REVOLVER,
	RR_A_SMG,
	RR_A_RIFLE,
	RR_A_SNIPER,
	RR_A_SHOTGUN,
	RR_A_SSG,
	RR_A_CHAINGUN,
	RR_A_RAILGUN,
	RR_A_ROCKET,
	RR_A_GRENADE,
	RR_A_PLASMA,
	RR_A_BFG,
	RR_A_UNMAKER,
	RR_A_MELEE,
	RR_A_MAX
}

// PLAY SCOPE, DECLARED. InferArch reads AmmoType1, bMeleeWeapon and the
// defaults off a live Weapon, and reading a play object's fields from data
// scope does not compile -- the error lands on the `let` line rather than the
// read, which makes it read as an unknown identifier instead of a scope fault.
class RR_Feed play
{
	// ---- archetype -> size ------------------------------------------------
	//
	// Map units. A Doom player is 56 tall, so a pistol at 8 and a BFG at 30 is
	// about right to start. These are the ONLY per-gun numbers in the system and
	// there are fourteen pairs of them, not two per weapon -- tuning `pistol`
	// fixes every pistol in every mod that will ever load.
	//
	// The menu writes overrides into rr_len_* / rr_grip_* (see MENUDEF).


	// How far FORWARD of AttackPos the firing grip sits. The controller origin
	// is at the wrist and the gun is held in the palm, so this absorbs that gap
	// as well as the model's own forward bias -- one number instead of a palm
	// bone lookup, which is the thing fifteen attempts died on.

	// ---- archetype -> default feed ----------------------------------------

	// Cvar suffixes, so a MENUDEF row reads "rr_len_pistol" and not "rr_len_0".
	// A slider you cannot identify is a slider nobody tunes.

	// The cvar is the source of truth; the const arrays above are the fallback
	// for a load where CVARINFO is absent or a name got renamed. A missing cvar
	// otherwise reads as a zero-length gun -- every point collapsing onto the
	// grip -- and an absent cvar looks exactly like a zeroed one, with nothing
	// in the log either way.

	// SWITCHES, NOT `static const` ARRAYS -- and this is not a style choice.
	//
	// THE ARRAYS WERE FINE. THE READERS WERE `static`, AND THAT IS THE WHOLE
	// FAULT. A `static const T NAME[] = {...}` at CLASS scope parses and
	// compiles: CompileArrays turns it into a VARF_Static|VARF_ReadOnly PField
	// in the class symbol table (zcc_compile.cpp:1288-1347). Reading it back is
	// what fails. FxIdentifier::Resolve finds that PField in the owning class
	// and can only reach a field through the `SelfClass != nullptr` branch
	// (codegen.cpp:6744) -- which a static function skips by design, since a
	// static function has no self: zcc_compile.cpp:2585 strips VARF_Method from
	// every `static`, and symbols.cpp:95 nulls SelfClass whenever VARF_Method is
	// absent. The name then falls through to globals, to cvars, and out the
	// bottom as "Unknown identifier" (codegen.cpp:6850). Every accessor in this
	// class is static, so all four tables were invisible to every one of them.
	//
	// This is why wadsrc puts all 32 of its static const arrays INSIDE a
	// function body and not one at class scope (actor.zs:1397,
	// statusbar.zs:848). A function-local one resolves through the
	// EFX_StaticArray path at codegen.cpp:6659, where self never enters into it.
	// Either shape works -- in-function arrays, or these accessors. What does
	// not work is a class-scope table read by a static method.
	//
	// AND THE CASCADE IS WHY THIS READ AS TWELVE FAULTS INSTEAD OF FOUR. A
	// failed initializer does not leave a mistyped local, it leaves NO local:
	// `let c` and the explicitly-typed `double v` and `int f2` all came back
	// "Unknown identifier" on their own lines. RS_Hands' rs_grab.zs:53 documents
	// the same shape. Read the FIRST name on the list; the rest is noise.
	//
	// RS_Holsters reached the switch from the other direction -- its holster
	// table is an indexed accessor "because ZScript dynamic arrays only accept
	// integral and object types" (RS_Holsters.zs:18-21), and GetHolster
	// (RS_Holsters.zs:111) is a static method switching over a constant index,
	// string cases and all, exactly like these. A switch over a compile-time
	// constant costs nothing and allocates nothing.
	//
	// One behaviour change and it is in the safe direction: ARCH_FEED[a2] was
	// indexed by the unclamped `rr_force_arch` cvar, so typing a number above 14
	// into the console was an out-of-bounds VM abort. ArchFeed returns RR_F_BOX.

	// Map units. A Doom player is 56 tall. These are the ONLY per-gun numbers in
	// the system and there are fourteen of them, not two per weapon -- tuning
	// `pistol` sizes every pistol in every mod that will ever load.
	static double ArchLen(int a)
	{
		switch (a)
		{
		case RR_A_PISTOL:   return  8;
		case RR_A_REVOLVER: return  9;
		case RR_A_SMG:      return 14;
		case RR_A_RIFLE:    return 24;
		case RR_A_SNIPER:   return 30;
		case RR_A_SHOTGUN:  return 26;
		case RR_A_SSG:      return 18;
		case RR_A_CHAINGUN: return 26;
		case RR_A_RAILGUN:  return 30;
		case RR_A_ROCKET:   return 26;
		case RR_A_GRENADE:  return 18;
		case RR_A_PLASMA:   return 24;
		case RR_A_BFG:      return 30;
		case RR_A_UNMAKER:  return 18;
		}
		return 0;
	}

	// How far FORWARD of the hand the firing grip sits. Absorbs the wrist-to-palm
	// gap as well as the model's own forward bias.
	static double ArchGrip(int a)
	{
		switch (a)
		{
		case RR_A_PISTOL: case RR_A_REVOLVER: return 2;
		case RR_A_SMG:    case RR_A_SSG:      return 3;
		case RR_A_ROCKET:                     return 5;
		case RR_A_BFG:                        return 6;
		case RR_A_MELEE:                      return 0;
		}
		return 4;
	}

	static int ArchFeed(int a)
	{
		switch (a)
		{
		case RR_A_REVOLVER: case RR_A_SSG:      return RR_F_BREAK;
		case RR_A_SNIPER:   case RR_A_RAILGUN:  return RR_F_BOLT;
		case RR_A_SHOTGUN:                      return RR_F_PUMP;
		case RR_A_CHAINGUN:                     return RR_F_BELT;
		case RR_A_ROCKET:   case RR_A_GRENADE:  return RR_F_POD;
		case RR_A_PLASMA:   case RR_A_BFG: case RR_A_UNMAKER: return RR_F_CELL;
		case RR_A_MELEE:                        return RR_F_NONE;
		}
		return RR_F_BOX;
	}

	// Cvar suffix, so a MENUDEF row reads "rr_len_pistol" and not "rr_len_0".
	// A slider you cannot identify is a slider nobody tunes.
	static string ArchName(int a)
	{
		switch (a)
		{
		case RR_A_PISTOL:   return "pistol";
		case RR_A_REVOLVER: return "revolver";
		case RR_A_SMG:      return "smg";
		case RR_A_RIFLE:    return "rifle";
		case RR_A_SNIPER:   return "sniper";
		case RR_A_SHOTGUN:  return "shotgun";
		case RR_A_SSG:      return "ssg";
		case RR_A_CHAINGUN: return "chaingun";
		case RR_A_RAILGUN:  return "railgun";
		case RR_A_ROCKET:   return "rocket";
		case RR_A_GRENADE:  return "grenade";
		case RR_A_PLASMA:   return "plasma";
		case RR_A_BFG:      return "bfg";
		case RR_A_UNMAKER:  return "unmaker";
		}
		return "melee";
	}

	static double LenOf(int arch, PlayerInfo p)
	{
		if (arch < 0 || arch >= RR_A_MAX) return 0;
		let c = CVar.GetCVar("rr_len_" .. ArchName(arch), p);
		if (!c) return ArchLen(arch);
		double v = c.GetFloat();
		return (v > 0) ? v : ArchLen(arch);
	}

	static double GripOf(int arch, PlayerInfo p)
	{
		if (arch < 0 || arch >= RR_A_MAX) return 0;
		let c = CVar.GetCVar("rr_grip_" .. ArchName(arch), p);
		if (!c) return ArchGrip(arch);
		return c.GetFloat();
	}

	// ---- archetype -> magazine capacity ------------------------------------
	//
	// COUNTED IN SHOTS, NOT IN ROUNDS, and that one decision does most of the
	// work. Rounds are shots * AmmoUse1, read off the DEFAULT for the same
	// reason every other read in this file is (the engine rewrites a live
	// weapon's AmmoUse1 for multi-attack weapons, weapons.zs:92). What falls out
	// of it for free:
	//
	//   * A DOUBLE BARREL HOLDS TWO SHELLS. One shot, two shells a shot
	//     (weaponssg.zs:31), so 1 * 2 = 2 and nobody had to write "2" anywhere.
	//   * A BFG MAGAZINE IS ONE SHOT. Forty cells a shot (weaponbfg.zs:32), so
	//     1 * 40 = 40 -- while a plasma rifle on the same ammo class gets 40 * 1
	//     = 40 cells and forty shots out of it. Same number of cells, completely
	//     different guns, no special case.
	//   * NO WEAPON CAN EVER BE BUILT DEAD. A capacity counted in rounds can
	//     land below AmmoUse1 -- a BFG with a twelve-round magazine can never
	//     fire, ever, and would read as the mod having broken the gun. Counted
	//     in shots the capacity is a multiple of the cost by construction, and
	//     the floor of one shot below is what holds that even at the lowest
	//     rr_mag_scale.
	//
	// AmmoGive1 is NOT read here, and it is the obvious thing to reach for. It
	// is a POOL-size signal, not a magazine one -- see the cell branch of
	// InferArch for what trusting it cost last time: Doom's plasma rifle and BFG
	// both give 40 and the plasma rifle came out a BFG.
	static int ArchShots(int a)
	{
		switch (a)
		{
		case RR_A_PISTOL:   return  12;
		case RR_A_REVOLVER: return   6;
		case RR_A_SMG:      return  30;
		case RR_A_RIFLE:    return  30;
		case RR_A_SNIPER:   return   5;
		case RR_A_SHOTGUN:  return   8;   // a tube, filled one shell at a time
		case RR_A_SSG:      return   1;   // one shot, both barrels
		case RR_A_CHAINGUN: return 100;
		case RR_A_RAILGUN:  return   5;
		case RR_A_ROCKET:   return   1;
		case RR_A_GRENADE:  return   6;
		case RR_A_PLASMA:   return  40;
		case RR_A_BFG:      return   1;
		case RR_A_UNMAKER:  return  40;
		}
		return 0;   // melee, and anything unknown -- no magazine, nothing to fill
	}

	// HOW MUCH ONE SEATING PUTS IN, in shots. 0 means "fill it", which is what a
	// magazine, a cell pack and a speedloader all are: one trip, one insertion,
	// gun full.
	//
	// SHOTGUNS ARE THE EXCEPTION AND THE REASON THIS FUNCTION EXISTS. A shell
	// goes into the port one at a time and each one is COMMITTED THE MOMENT IT
	// IS SEATED, so eight shells is eight trips to the pouch and stopping after
	// three leaves you with three and a partial tube. Interrupted is not wasted,
	// only incomplete.
	//
	// SSG is here at 1 SHOT rather than "2", which for a double barrel is both
	// shells at once because its shot costs two. Writing 2 would have been the
	// same number for Doom's SSG and wrong for any break-action a mod ships that
	// spends a different amount.
	//
	// A REVOLVER IS NOT ON THIS LIST although it feeds RR_F_BREAK alongside the
	// SSG. Feed sets the sequence; this is about the gun, and a revolver is
	// reloaded with a speedloader in one motion. That split is the whole reason
	// archetype and feed are separate axes.
	static int ArchSeat(int a)
	{
		switch (a)
		{
		case RR_A_SHOTGUN: return 1;
		case RR_A_SSG:     return 1;
		}
		return 0;
	}

	// Rounds, not shots -- the two callers both want rounds and neither should
	// have to remember to multiply.
	//
	// ONE GLOBAL SLIDER AND NOT FOURTEEN, unlike len/grip above, and that is a
	// deliberate difference rather than an oversight. Length and grip are
	// MEASUREMENTS of somebody's model and have to be tuned per family or they
	// are wrong per family. Magazine size is a BALANCE number where the whole
	// table moves together -- "reloading too often" is one complaint about all
	// fourteen. Fourteen more cvars, fourteen more CVARINFO lines and fourteen
	// more menu rows is a lot of surface to add on a change nobody has been able
	// to compile yet, and per-archetype rows can be split out later without
	// moving anything already written here.
	static int CapOf(int arch, Weapon w, PlayerInfo p)
	{
		if (!w) return 0;
		if (arch < 0 || arch >= RR_A_MAX) return 0;

		int shots = ArchShots(arch);
		if (shots <= 0) return 0;

		let c = CVar.GetCVar("rr_mag_scale", p);
		double s = c ? c.GetFloat() : 1.0;
		if (s <= 0) s = 1.0;

		int n = int(double(shots) * s);
		if (n < 1) n = 1;          // never scale a gun down to no magazine at all

		return n * ShotCost(w);
	}

	static int SeatOf(int arch, Weapon w)
	{
		if (!w) return 0;
		if (arch < 0 || arch >= RR_A_MAX) return 0;

		int n = ArchSeat(arch);
		if (n <= 0) return 0;      // 0 stays 0 -- one seating fills the magazine
		return n * ShotCost(w);
	}

	// What one shot costs, floored at one. A weapon with AmmoUse1 0 fires for
	// free and would otherwise turn every capacity above into zero.
	static int ShotCost(Weapon w)
	{
		if (!w) return 1;
		int use = w.default.AmmoUse1;
		return (use > 0) ? use : 1;
	}

	// ---- feed -> where the ammunition goes in ------------------------------
	//
	// ONE POINT PER FAMILY, not a sequence of them. The first cut of this file
	// held a beat table -- touch here, pull away, touch again -- which modelled
	// a reload as a series of places to tap. It is not: it is one thing carried
	// to one place. The rest is grip.
	//
	// The RR_BeatDef class and the RR_BeatMode enum were the last residue of
	// that first cut and were deleted on 2026-08-26 with zero call sites. Their
	// header carried a paragraph asserting that no trip to a pouch existed and
	// that everything happened at one place on the gun -- true of the beat
	// runner, and flatly contradicted by the mod that got built instead, which
	// starts every reload at the chest pouch (rr_sequence.zs). Leaving a
	// confident wrong statement in the file was worse than losing it.
	//
	// Normalised, in gun-lengths from the firing grip.
	// x forward, y sideways, z up -- the MODEL convention, not Doom's.
	static Vector3 Magwell(int feed)
	{
		switch (feed)
		{
		// Under the grip. A box magazine goes up into the well.
		case RR_F_BOX:
		case RR_F_BOLT:  return ( 0.00, 0, -0.35);
		// Forward of the grip and low -- the loading port on a tube gun.
		case RR_F_PUMP:  return ( 0.10, 0, -0.10);
		// The open breech, just ahead of the grip and high.
		case RR_F_BREAK: return ( 0.15, 0,  0.05);
		// The feed tray, on top.
		case RR_F_BELT:  return ( 0.10, 0,  0.15);
		// Down the tube, well forward.
		case RR_F_POD:   return ( 0.30, 0,  0.00);
		// The cell slot, under and slightly back.
		case RR_F_CELL:  return (-0.05, 0, -0.30);
		}
		return (0, 0, -0.35);
	}

	// Ellipsoid semi-axes in MAP UNITS and deliberately not normalised: how
	// precisely you have to hit a thing is a property of your hand, which does
	// not get bigger when the gun does.
	//
	// Wider than the first cut's. Seating is the end of a carry you are already
	// committed to -- the contract says the lock commits and there is no abort
	// path -- so a near miss should seat, not drop a magazine on the floor.
	static Vector3 Radii(int feed)
	{
		switch (feed)
		{
		case RR_F_PUMP:
		case RR_F_BREAK: return (3.5, 4.5, 3.5);
		case RR_F_POD:   return (5.0, 5.0, 5.0);
		}
		return (4.0, 5.0, 4.0);
	}

	// ---- resolution -------------------------------------------------------
	//
	// Returns feed, archetype. Three tiers, and the middle one carries the whole
	// universality claim because it is where almost every weapon lands: nobody
	// is going to tag Guncaster's arsenal, or DRLA's, or a wad from 2004.
	//
	// ON THE MISSING 3D-MODEL GATE. A sprite weapon has no geometry for a hand
	// to reach parts of, and running this on one would be Rusted Legacy's mistake
	// in new clothes. But ZScript cannot ask whether an actor has a MODELDEF
	// entry -- there is no such query, only A_ChangeModel to SET one -- so the
	// check does not exist and pretending otherwise would be worse than saying
	// so. The escape hatch is the per-weapon menu override, which includes
	// "none": one row, and the weapon falls through to vanilla Reload.
	static int, int Resolve(Weapon w, PlayerInfo p)
	{
		if (!w) return RR_F_NONE, RR_A_MELEE;

		string cn = "" .. w.GetClassName();

		// 3. Forced, for tuning. Global rather than per weapon on purpose: a
		//    PER-WEAPON override needs a cvar per weapon class, and CVARINFO
		//    cannot enumerate classes that do not exist until a mod is loaded.
		//    Doing it properly means a ZScript OptionMenuItem building rows for
		//    the arsenal you are actually carrying and persisting them itself,
		//    which is its own slice. Until then this forces every weapon, which
		//    is what tuning a family wants anyway.
		let fv = CVar.GetCVar("rr_force_feed", p);
		let av = CVar.GetCVar("rr_force_arch", p);
		int ff = fv ? fv.GetInt() : -1;
		int fa = av ? av.GetInt() : -1;
		if (ff >= 0 || fa >= 0)
		{
			int a2 = (fa >= 0) ? fa : InferArch(w);
			int f2 = (ff >= 0) ? ff : ArchFeed(a2);
			return f2, a2;
		}

		// 1. Tagged -- our own table, one rr_compat_<mod>.zs per mod.
		int tf, ta;
		[tf, ta] = RR_Tags.Lookup(cn);
		if (ta >= 0) return (tf >= 0) ? tf : ArchFeed(ta), ta;

		// 2. Inferred.
		int arch = InferArch(w);
		return ArchFeed(arch), arch;
	}

	// SHOTGUN OR DOUBLE BARREL, and AmmoUse1 answers it without asking anyone to
	// tag anything: a double barrel spends two shells a shot because it fires
	// two, and that has been true of every one ever shipped. Doom's own pair
	// differ by exactly this and by nothing else -- Shotgun is AmmoUse 1 /
	// AmmoGive 8 (weaponshotgun.zs:31-32), SuperShotgun AmmoUse 2 / AmmoGive 8
	// (weaponssg.zs:31-32).
	//
	// The name is the second opinion rather than the first because "super" and
	// "double" are naming conventions and AmmoUse is arithmetic.
	static int ShellArch(string cn, int use)
	{
		if (use >= 2) return RR_A_SSG;
		if (cn.IndexOf("super") >= 0 || cn.IndexOf("double") >= 0
			|| cn.IndexOf("sawn") >= 0 || cn.IndexOf("sawed") >= 0)
			return RR_A_SSG;
		return RR_A_SHOTGUN;
	}

	// Everything here is readable on ANY Weapon from ANY mod, which is the point.
	// Nothing below names a class from another package.
	//
	// bTwoHanded WAS THE PRIMARY SPLIT AND THAT WAS THE BUG (fixed 2026-08-26).
	// It is a flagdef this fork added -- weapons.zs:163, WeaponFlags bit 22 --
	// and nothing in the stock game sets it, let alone a foreign mod. So every
	// weapon this package was built for read as one-handed and all four tests
	// hanging off the flag resolved to their wrong side together: a plain pump
	// shotgun came out RR_A_SSG on RR_F_BREAK, and every bullet weapon in
	// existence came out a pistol. That is the core premise of the mod failing
	// on precisely the weapons it exists for.
	//
	// The flag survives below in ONE place and as a one-way statement: TRUE
	// still means two-handed, FALSE now means "nobody said". Those are not the
	// same claim and reading them as the same is what broke this.
	//
	// THE SIGNALS THAT DO SURVIVE THE TRIP TO A FOREIGN MOD:
	//
	//   ammo class name -- almost every mod either uses Doom's four or names its
	//                      own after what it is. It picks the FAMILY, which is
	//                      the expensive thing to get wrong: family sets the
	//                      feed and feed sets the whole sequence.
	//   AmmoUse1        -- what one shot costs. Arithmetic rather than
	//                      convention, and it is the only thing that separates
	//                      the two pairs nothing else can. Read off the DEFAULT
	//                      for the same reason AmmoGive1 was: the engine
	//                      rewrites a live weapon's AmmoUse1 for multi-attack
	//                      weapons (weapons.zs:92).
	//   class name      -- mods name guns after what they are far more reliably
	//                      than they set any flag. It picks the archetype WITHIN
	//                      a family, and is the whole answer when the ammo class
	//                      is one this has never seen. Same trick and the same
	//                      deliberate narrowness as RS_Hands' IsFist
	//                      (rs_hands.zs:208-216): a false positive hides a real
	//                      gun, so only match words that announce themselves.
	//
	// AmmoGive1 is no longer read at all. See the cell branch for why -- it does
	// not separate the one case it was being used for.
	static int InferArch(Weapon w)
	{
		if (!w || w.bMeleeWeapon) return RR_A_MELEE;

		string cn = "" .. w.GetClassName();
		cn = cn.MakeLower();

		// NAMED MELEE, BEFORE THE AMMO FAMILIES AND NOT AFTER. A chainsaw that
		// burns a "Fuel" ammo type would otherwise land in the energy family
		// below and be handed a cell to seat. Stock does set the flag above
		// (Chainsaw and Fist both carry +WEAPON.MELEEWEAPON), which is exactly
		// the reason not to trust it -- the mods that do not are the ones this
		// has to survive.
		if (cn.IndexOf("chainsaw") >= 0 || cn.IndexOf("fist") >= 0
			|| cn.IndexOf("punch") >= 0 || cn.IndexOf("melee") >= 0)
			return RR_A_MELEE;

		// NO AMMUNITION MEANS NOTHING TO FEED, whatever else is true. Such a
		// weapon used to fall out of the bottom of this function as a RIFLE and
		// be offered a magazine. RR_A_MELEE is the archetype whose feed is
		// RR_F_NONE, which is the "leave it to the weapon's own Reload" answer.
		if (!w.AmmoType1) return RR_A_MELEE;

		string ammo = "" .. w.AmmoType1.GetClassName();
		ammo = ammo.MakeLower();

		int use = w.default.AmmoUse1;

		// ---- family, from the ammunition --------------------------------------

		if (ammo.IndexOf("shell") >= 0) return ShellArch(cn, use);

		if (ammo.IndexOf("rocket") >= 0 || ammo.IndexOf("grenade") >= 0)
		{
			// Both put one large round down a tube and both feed RR_F_POD, so
			// only the size is at stake and the launcher's own name settles it.
			if (cn.IndexOf("grenade") >= 0 || ammo.IndexOf("grenade") >= 0)
				return RR_A_GRENADE;
			return RR_A_ROCKET;
		}

		if (ammo.IndexOf("cell") >= 0 || ammo.IndexOf("plasma") >= 0
			|| ammo.IndexOf("energy") >= 0 || ammo.IndexOf("fuel") >= 0)
		{
			if (cn.IndexOf("bfg") >= 0)     return RR_A_BFG;
			if (cn.IndexOf("unmaker") >= 0) return RR_A_UNMAKER;
			if (cn.IndexOf("rail") >= 0)    return RR_A_RAILGUN;

			// COST PER SHOT, NOT POOL SIZE. This test read `give >= 40`, and
			// Doom's plasma rifle and BFG BOTH give 40 (weaponplasma.zs:32,
			// weaponbfg.zs:33) -- so the plasma rifle came out a BFG on the
			// stock game, sized 30 units long on a 6-unit grip. What actually
			// separates them is what a shot costs: 1 against 40
			// (weaponplasma.zs:31, weaponbfg.zs:32). Anything spending ten cells
			// to fire once is a BFG-class weapon whoever built it.
			if (use >= 10) return RR_A_BFG;
			return RR_A_PLASMA;
		}

		// ---- family, from the weapon's own name --------------------------------
		//
		// Reached when the ammo class is one this has never seen, which is the
		// ordinary case in a total conversion. Ordered so the longer word wins
		// where two overlap: "sniperrifle" must not read as a rifle, and a
		// "plasmarifle" that arrived here on some exotic ammo type must not
		// either.

		if (cn.IndexOf("bfg") >= 0)     return RR_A_BFG;
		if (cn.IndexOf("unmaker") >= 0) return RR_A_UNMAKER;
		if (cn.IndexOf("rail") >= 0)    return RR_A_RAILGUN;
		if (cn.IndexOf("sniper") >= 0)  return RR_A_SNIPER;

		if (cn.IndexOf("chaingun") >= 0 || cn.IndexOf("minigun") >= 0
			|| cn.IndexOf("gatling") >= 0)
			return RR_A_CHAINGUN;

		if (cn.IndexOf("revolver") >= 0 || cn.IndexOf("magnum") >= 0)
			return RR_A_REVOLVER;

		if (cn.IndexOf("shotgun") >= 0 || cn.IndexOf("shotty") >= 0)
			return ShellArch(cn, use);

		if (cn.IndexOf("grenade") >= 0) return RR_A_GRENADE;

		if (cn.IndexOf("rocket") >= 0 || cn.IndexOf("missile") >= 0
			|| cn.IndexOf("launcher") >= 0)
			return RR_A_ROCKET;

		if (cn.IndexOf("plasma") >= 0 || cn.IndexOf("laser") >= 0)
			return RR_A_PLASMA;

		if (cn.IndexOf("smg") >= 0 || cn.IndexOf("submachine") >= 0
			|| cn.IndexOf("uzi") >= 0)
			return RR_A_SMG;

		if (cn.IndexOf("pistol") >= 0 || cn.IndexOf("handgun") >= 0)
			return RR_A_PISTOL;

		if (cn.IndexOf("rifle") >= 0 || cn.IndexOf("carbine") >= 0)
			return RR_A_RIFLE;

		// ---- nothing announced itself ------------------------------------------
		//
		// Doom's own pistol and chaingun are the honest limit of all this: same
		// ammo class, same AmmoUse, same AmmoGive -- weaponpistol.zs:31-33 and
		// weaponchaingun.zs:31-33 are the identical three lines. Nothing but the
		// name tells them apart, so a weapon that reaches here has genuinely not
		// said what it is and a guess is all that is left.
		//
		// THE ONLY SURVIVING bTwoHanded READ, and it is one-way. Set, it is a
		// real statement that this is a long gun. Unset, it says nothing, so the
		// answer is a middle-sized gun rather than either extreme. Pistol, SMG
		// and rifle all feed RR_F_BOX, so this choice moves the magwell and
		// changes nothing else -- and the SMG's 14 units sits between a pistol's
		// 8 and a rifle's 24. Guessing the middle is wrong by six; guessing an
		// end, which is what this used to do to every foreign weapon, is wrong
		// by sixteen. One menu row fixes either.
		if (w.bTwoHanded) return RR_A_RIFLE;
		return RR_A_SMG;
	}
}

// PER-MOD TAGS. One file per mod, appended to this table -- never folded into
// zscript.txt, so a mod's tags can be deleted in one piece.
//
// Empty by default. Inference covers the general case; this is for the weapons
// inference gets wrong in a way worth fixing permanently rather than per player.
class RR_Tags
{
	// Returns feed, archetype. -1 archetype means "not tagged".
	static int, int Lookup(string cn)
	{
		return -1, -1;
	}
}
