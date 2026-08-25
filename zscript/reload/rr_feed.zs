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

// Beat completion modes.
//
// THERE IS NO TRIP TO A POUCH. An earlier cut sent the off hand to a chest
// pouch mid-reload and that is gone for two reasons: no pouch actually exists
// (RS_Holsters has none -- only the engine enum does), and a reload that makes
// you reach across your body mid-fight is a reload you stop using.
//
// Everything happens at ONE PLACE ON THE GUN. Touch it, pull away, touch it
// again. That is a real reload motion and it needs no second location, no body
// volume and no mod to be loaded alongside.
enum RR_BeatMode
{
	RR_M_TOUCH = 0,  // off hand entered the point's ellipsoid
	RR_M_LEAVE,      // off hand left it again -- the mag coming clear
	RR_M_TRAVEL,     // off hand moved far enough along a weapon axis
	RR_M_HOLD        // dwell, in tics
}

// One step of a reload. Built on demand rather than held in a table, because
// ZScript has no array-of-struct literal and the runner only ever needs the
// beat it is currently on -- which it caches when it advances, so this is
// allocated a handful of times per reload and never per tic.
class RR_BeatDef
{
	int     subject;   // GRIPSUBJ_* claimed while this beat is live
	int     mode;
	Vector3 pt;        // normalised point on the weapon, gun-lengths
	Vector3 radii;     // ellipsoid semi-axes, map units (TOUCH)
	int     axis;      // 0 fwd 1 side 2 up (TRAVEL)
	double  param;     // travel distance in map units, or dwell in tics
	String  snd;
	String  label;     // dev trace only

	static RR_BeatDef Make(int subject, int mode, Vector3 pt, Vector3 radii,
		int axis, double param, String snd, String label)
	{
		let b = new("RR_BeatDef");
		b.subject = subject; b.mode = mode;
		b.pt = pt; b.radii = radii;
		b.axis = axis; b.param = param;
		b.snd = snd; b.label = label;
		return b;
	}
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

	static const double ARCH_LEN[] =
	{
		 8,   // pistol
		 9,   // revolver
		14,   // smg
		24,   // rifle
		30,   // sniper
		26,   // shotgun
		18,   // ssg
		26,   // chaingun
		30,   // railgun
		26,   // rocket
		18,   // grenade launcher
		24,   // plasma
		30,   // bfg
		18,   // unmaker
		 0    // melee
	};

	// How far FORWARD of AttackPos the firing grip sits. The controller origin
	// is at the wrist and the gun is held in the palm, so this absorbs that gap
	// as well as the model's own forward bias -- one number instead of a palm
	// bone lookup, which is the thing fifteen attempts died on.
	static const double ARCH_GRIP[] =
	{
		2, 2, 3, 4, 4, 4, 3, 4, 4, 5, 4, 4, 6, 4, 0
	};

	// ---- archetype -> default feed ----------------------------------------
	static const int ARCH_FEED[] =
	{
		RR_F_BOX,    // pistol
		RR_F_BREAK,  // revolver -- swing the cylinder out, speedloader in
		RR_F_BOX,    // smg
		RR_F_BOX,    // rifle
		RR_F_BOLT,   // sniper
		RR_F_PUMP,   // shotgun
		RR_F_BREAK,  // ssg
		RR_F_BELT,   // chaingun
		RR_F_BOLT,   // railgun
		RR_F_POD,    // rocket
		RR_F_POD,    // grenade launcher
		RR_F_CELL,   // plasma
		RR_F_CELL,   // bfg
		RR_F_CELL,   // unmaker
		RR_F_NONE    // melee
	};

	// Cvar suffixes, so a MENUDEF row reads "rr_len_pistol" and not "rr_len_0".
	// A slider you cannot identify is a slider nobody tunes.
	static const string ARCH_NAME[] =
	{
		"pistol", "revolver", "smg", "rifle", "sniper", "shotgun", "ssg",
		"chaingun", "railgun", "rocket", "grenade", "plasma", "bfg",
		"unmaker", "melee"
	};

	// The cvar is the source of truth; the const arrays above are the fallback
	// for a load where CVARINFO is absent or a name got renamed. A missing cvar
	// otherwise reads as a zero-length gun -- every point collapsing onto the
	// grip -- and an absent cvar looks exactly like a zeroed one, with nothing
	// in the log either way.
	static double LenOf(int arch, PlayerInfo p)
	{
		if (arch < 0 || arch >= RR_A_MAX) return 0;
		let c = CVar.GetCVar("rr_len_" .. ARCH_NAME[arch], p);
		if (!c) return ARCH_LEN[arch];
		double v = c.GetFloat();
		return (v > 0) ? v : ARCH_LEN[arch];
	}

	static double GripOf(int arch, PlayerInfo p)
	{
		if (arch < 0 || arch >= RR_A_MAX) return 0;
		let c = CVar.GetCVar("rr_grip_" .. ARCH_NAME[arch], p);
		if (!c) return ARCH_GRIP[arch];
		return c.GetFloat();
	}

	// ---- feed -> where the ammunition goes in ------------------------------
	//
	// ONE POINT PER FAMILY, not a sequence of them. The first cut of this file
	// held a beat table -- touch here, pull away, touch again -- which modelled
	// a reload as a series of places to tap. It is not: it is one thing carried
	// to one place. The rest is grip.
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
			int f2 = (ff >= 0) ? ff : ARCH_FEED[a2];
			return f2, a2;
		}

		// 1. Tagged -- our own table, one rr_compat_<mod>.zs per mod.
		int tf, ta;
		[tf, ta] = RR_Tags.Lookup(cn);
		if (ta >= 0) return (tf >= 0) ? tf : ARCH_FEED[ta], ta;

		// 2. Inferred.
		int arch = InferArch(w);
		return ARCH_FEED[arch], arch;
	}

	// Everything here is readable on ANY Weapon from ANY mod, which is the point.
	// Nothing below names a class from another package.
	static int InferArch(Weapon w)
	{
		if (!w || w.bMeleeWeapon) return RR_A_MELEE;

		string ammo = "";
		if (w.AmmoType1) ammo = ("" .. w.AmmoType1.GetClassName());
		ammo = ammo.MakeLower();

		bool twoHand = w.bTwoHanded;
		int  give    = w.default.AmmoGive1;

		// Ammo class name is the strongest generic signal there is: almost every
		// mod either uses Doom's four or names its own after what it is.
		if (ammo.IndexOf("shell") >= 0)
			return twoHand ? RR_A_SHOTGUN : RR_A_SSG;

		if (ammo.IndexOf("rocket") >= 0 || ammo.IndexOf("grenade") >= 0)
			return twoHand ? RR_A_ROCKET : RR_A_GRENADE;

		if (ammo.IndexOf("cell") >= 0 || ammo.IndexOf("plasma") >= 0
			|| ammo.IndexOf("energy") >= 0 || ammo.IndexOf("fuel") >= 0)
		{
			// A big cell pool is a BFG, a small one is a rifle. Crude, and the
			// only cost of getting it wrong is the point spacing being sized for
			// the wrong gun -- which one menu row fixes.
			if (give >= 40) return RR_A_BFG;
			return RR_A_PLASMA;
		}

		if (ammo.IndexOf("clip") >= 0 || ammo.IndexOf("bullet") >= 0
			|| ammo.IndexOf("ammo") >= 0)
		{
			if (!twoHand) return RR_A_PISTOL;
			if (give >= 50) return RR_A_CHAINGUN;
			return RR_A_RIFLE;
		}

		return twoHand ? RR_A_RIFLE : RR_A_PISTOL;
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
