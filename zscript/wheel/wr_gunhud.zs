// A READOUT WELDED TO THE GUN.
//
// The count, drawn as a 16-segment display sitting on the weapon in your hand
// rather than in a corner of a screen you do not have. Dead Space's on-gun
// counter by way of the Aliens pulse rifle: dark bed, glowing segments, close
// enough to read without aiming your head at it.
//
// WHY THIS IS NOT ATTACHED TO ANYTHING.
//
// The obvious implementation -- attach a billboard to the weapon model -- is
// not available and never will be without engine work. The held model's world
// matrix is built inside RenderHUDModel and thrown away at the draw call; no
// native exposes it. AttachBillboard tracks an ACTOR's Pos(), and a held
// weapon is an inventory item whose position is the player's feet, so
// attaching to the weapon would put the counter at your ankles.
//
// What rescues it: in VR, weapon bob is hard-zeroed for the local player
// (p_pspr.cpp), so every step from the controller pose to the mesh is a
// CONSTANT per weapon. A fixed offset in the hand's own frame therefore lands
// on the same spot of the model every frame -- it is not an approximation of
// where the gun is, it is exactly where the gun is. That is the whole trick,
// and it is why this file is arithmetic rather than a plea for new natives.
//
// WHICH ALSO ANSWERS "HOW BIG IS THE BFG".
//
// It does not need to know. Model bounds do not exist in the engine for any
// format but IQM -- MD3 reads the bounding box out of its own file header and
// throws it away -- and adding them would answer the wrong question anyway. A
// box says the BFG is ninety units long; it does not say the flat plate on the
// receiver is six units left and three up from the grip. The placement mode
// below produces that number directly, in about twenty seconds a gun, and
// measures the drawn model as a side effect -- after every scale in the chain,
// for every format, including the ones with no bounds in memory at all.

class wr_GunTag : EventHandler
{
	// One readout per hand. Index 0 is the main hand, 1 the off hand, matching
	// every other hand index in this mod.
	private int    mTagId[2];
	private string mTagText[2];
	private Class<Weapon> mTagFor[2];
	private bool   mTagDry[2];
	// Caches hasAltFire()'s result per hand, keyed by weapon class --
	// countFor() runs every tic (the readout NUMBERS have to stay live),
	// but whether a weapon has an alt fire at all is a fact about its
	// CLASS, not something that changes tic to tic. Without this,
	// FindState('AltFire') ran on a genuine per-tic hot path (both
	// hands, every tic) for a result that only ever changes on a weapon
	// swap.
	private Class<Weapon> mMagCheckedFor[2];
	private bool   mMagCache[2];
	// wr_gun_color/wr_gun_dry (hue) and wr_gun_lcd (payload shape) go into
	// AddBillboardPersistent at creation and never get revisited, same as
	// mTagFor/mTagDry -- but neither WAS in the rebuild gate, so toggling
	// either at the console did nothing until the next weapon swap or dry
	// flip happened to also rebuild the billboard. Tracked here so the
	// gate below can actually see a live change.
	private color  mTagHue[2];
	private int    mTagPayload[2];
	private int    mDebugTics[2];   // wr_debug heartbeat, one per hand

	// Placement mode.
	private bool    mPlacing;
	private int     mGhostId;         // where the free hand is, while placing
	private int     mReadoutId;       // the numbers, floating by the free hand
	private bool    mHaveA;           // first point of a two-point measure
	private Vector3 mPointA;
	private string  mMeasured;

	// Per-weapon calibration, parallel arrays keyed by class name. Small and
	// linear on purpose: this holds the handful of guns somebody actually
	// bothered to place, not every weapon in the game.
	private Array<string> mCalClass;
	private Array<double> mCalF, mCalL, mCalU;
	private Array<double> mCalYaw, mCalTilt, mCalRoll;
	private Array<double> mCalW, mCalH;

	// The offsets being edited right now, in the placed weapon's frame.
	private double mEdF, mEdL, mEdU, mEdYaw, mEdTilt, mEdRoll, mEdW, mEdH;

	const AXIS_F = 0;
	const AXIS_L = 1;
	const AXIS_U = 2;
	const AXIS_YAW = 3;
	const AXIS_TILT = 4;
	const AXIS_ROLL = 5;
	const AXIS_W = 6;
	const AXIS_H = 7;

	private static double cv(string name, double fallback)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : fallback;
	}

	//==========================================================================
	// The hand's own frame
	//==========================================================================

	// Forward, left and up for a hand, as an orthonormal basis in world space.
	//
	// The yaw convention is the engine's and it is not the actor's: a hand's
	// facing is its stored angle PLUS NINETY. Pitch is up-positive, which is
	// the opposite of pmo.pitch and is the trap the engine's own weapon wheel
	// falls into -- it feeds raw pitch to an AngleToVector whose Z is -sin.
	//
	// Roll comes from MainHandRoll for the main hand, NOT AttackRoll. The
	// playsim zeroes AttackRoll every tic because the usercmd has no weaponroll
	// to rebuild it from on a peer, so it reads 0 forever while the model
	// visibly rolls with your wrist. See the fork's FORK_CHANGES.md section 31.
	//
	// Returns fwd and left only, as six doubles rather than out Vector3
	// params -- NOT a style choice. out Vector3 compiles and runs, but the
	// JIT backend cannot generate a call to it (EmitPARAM has no case for a
	// struct passed by reference) and silently falls back to the bytecode
	// interpreter for every caller, three tic-rate functions among them.
	// Every other multi-value return in this file is bare doubles for the
	// same reason: proven to JIT clean, because it already does everywhere
	// else. Callers rebuild the two Vector3s locally.
	static double, double, double, double, double, double
		handFrame(PlayerPawn pmo, int hand)
	{
		double y, p, r;

		if (pmo.OverrideAttackPosDir)
		{
			y = ((hand == 1) ? pmo.OffhandAngle : pmo.AttackAngle) + 90;
			p = (hand == 1) ? pmo.OffhandPitch  : pmo.AttackPitch;
			r = (hand == 1) ? pmo.OffhandRoll   : pmo.MainHandRoll;
		}
		else
		{
			// No tracking: point where the player looks, so this is testable
			// at a desk instead of only in a headset.
			y = pmo.angle;
			p = -pmo.pitch;
			r = 0;
		}

		r *= cv("wr_gun_rollsign", 1.0);

		double cp = cos(p), sp = sin(p);
		double cyw = cos(y), syw = sin(y);

		Vector3 fwd = (cp * cyw, cp * syw, sp);
		Vector3 l0  = (-syw, cyw, 0);
		Vector3 left;

		if (r != 0)
		{
			// up = fwd cross left holds for ANY roll: rotating left and up
			// together about the fwd axis is exactly what a cross product
			// commutes with, so deriving u0 once and rotating within the
			// l0/u0 plane is exact, not an approximation.
			Vector3 u0 = fwd cross l0;   // (0,0,1) at pitch 0, as it should be
			double cr = cos(r), sr = sin(r);
			left = l0 * cr + u0 * sr;
		}
		else
		{
			left = l0;
		}

		return fwd.X, fwd.Y, fwd.Z, left.X, left.Y, left.Z;
	}

	static Vector3 handPos(PlayerPawn pmo, int hand)
	{
		if (pmo.OverrideAttackPosDir)
			return (hand == 1) ? pmo.OffhandPos : pmo.AttackPos;

		double yaw = pmo.angle;
		double side = (hand == 1) ? -1.0 : 1.0;
		Vector3 head = pmo.Pos + (0, 0, pmo.player.viewheight);
		Vector3 f = (cos(yaw), sin(yaw), 0);
		Vector3 rt = (cos(yaw - 90), sin(yaw - 90), 0);
		return head + f * 22.0 + rt * (side * 11.0) - (0, 0, 8.0);
	}

	// Yaw and tilt that make a billboard's FACE point along `n`.
	//
	// Straight out of the engine's own BillboardBasis: normal works out to
	// (cosYaw cosTilt, sinYaw cosTilt, sinTilt), so this is that read
	// backwards. Guessing it would have been a coin flip between "flat on the
	// gun" and "edge-on and invisible".
	static double, double aimPanel(Vector3 n)
	{
		double len = n.Length();
		if (len < 0.0001) return 0, 0;
		n /= len;
		return atan2(n.Y, n.X), asin(clamp(n.Z, -1.0, 1.0));
	}

	// The roll that turns a panel's own right axis onto `want`.
	//
	// A panel aimed by yaw/tilt alone is always level with the world, so on a
	// gun held sideways the numbers stay upright while the gun does not. Roll
	// is the only axis that can fix that, and BillboardBasis defines it as
	// right = r0*cos + u0*sin -- so the angle wanted is just `want` resolved
	// onto that pair.
	static double rollToAlign(double yaw, double tilt, Vector3 want)
	{
		double sy = sin(yaw), cyw = cos(yaw);
		double st = sin(tilt), ct = cos(tilt);

		Vector3 r0 = (-sy, cyw, 0);
		Vector3 u0 = (-cyw * st, -sy * st, ct);

		return atan2(want dot u0, want dot r0);
	}

	//==========================================================================
	// Calibration table
	//==========================================================================

	private int calIndex(Class<Weapon> cls) const
	{
		if (cls == null) return -1;
		string want = cls.GetClassName();
		for (int i = 0; i < mCalClass.Size(); ++i)
			if (mCalClass[i] == want) return i;
		return -1;
	}

	private void calStore(Class<Weapon> cls, double f, double l, double u,
	                      double yw, double tl, double rl, double w, double h)
	{
		if (cls == null) return;

		int i = calIndex(cls);
		if (i < 0)
		{
			mCalClass.Push(cls.GetClassName());
			mCalF.Push(0); mCalL.Push(0); mCalU.Push(0);
			mCalYaw.Push(0); mCalTilt.Push(0); mCalRoll.Push(0);
			mCalW.Push(0); mCalH.Push(0);
			i = mCalClass.Size() - 1;
		}

		mCalF[i] = f;    mCalL[i] = l;    mCalU[i] = u;
		mCalYaw[i] = yw; mCalTilt[i] = tl; mCalRoll[i] = rl;
		mCalW[i] = w;    mCalH[i] = h;
	}

	// The placement for a weapon: its own if it has been measured, otherwise
	// the global fallback from the cvars.
	//
	// ONE fallback, not a table of guesses by archetype. An archetype table
	// sounds better and is worse -- it would be right for the weapon set it was
	// measured against and quietly wrong for every other, while looking
	// deliberate. One obvious default that is visibly approximate for
	// everything is honest, and the placement mode fixes the six guns anyone
	// actually cares about.
	private bool, double, double, double, double, double, double, double, double
		placementFor(Class<Weapon> cls) const
	{
		int i = calIndex(cls);
		if (i >= 0)
			return true, mCalF[i], mCalL[i], mCalU[i],
			             mCalYaw[i], mCalTilt[i], mCalRoll[i], mCalW[i], mCalH[i];

		return false,
		       cv("wr_gun_f",  6.0), cv("wr_gun_l", 2.5), cv("wr_gun_u", 1.5),
		       0, 0, 0,
		       cv("wr_gun_w",  7.0), cv("wr_gun_h", 3.0);
	}

	//==========================================================================
	// The readout itself
	//==========================================================================

	private static Weapon heldBy(int hand)
	{
		let p = players[consoleplayer];
		return (hand == 1) ? p.OffhandWeapon : p.ReadyWeapon;
	}

	// Ammo2 is overloaded -- a magazine's loaded rounds on one weapon, a
	// genuinely separate alt-fire pool on another (zscript.zs's own
	// hasMagazine, ~line 2415, has the full note). This copy never got
	// the alt-fire exclusion that one did, so a Rockets/Grenades-style
	// weapon (Ammo1 for the primary, a distinct Ammo2 for the alt) read
	// its alt-fire reserve as the gun's own magazine here -- showing the
	// grenade count as the headline number and flagging the weapon dry
	// at 0 grenades while it was still fully loaded.
	//
	// hasMag is passed in, not recomputed here -- see mMagCache in
	// updateTag(). Whether a weapon has an alt fire doesn't change while
	// you're holding it, so the caller checks it once per weapon swap,
	// not once per tic.
	private static bool hasMagazine(Weapon w, bool hasAlt)
	{
		if (w == null || w.Ammo2 == null || w.Ammo2 == w.Ammo1) return false;
		if (hasAlt) return false;
		return true;
	}

	// What the counter says.
	//
	// A magazine gun shows rounds and reserve, because both change and both
	// matter. Everything else shows the one number it has. A weapon with no
	// ammo at all -- a fist, a chainsaw -- gets no readout rather than a zero,
	// which would read as empty rather than as not applicable.
	private static string, bool countFor(Weapon w, bool hasAlt)
	{
		if (w == null) return "", false;

		if (hasMagazine(w, hasAlt))
		{
			int mag = w.Ammo2.Amount;
			int res = (w.Ammo1 != null) ? w.Ammo1.Amount : -1;
			if (res >= 0) return String.Format("%d/%d", mag, res), (mag == 0);
			return String.Format("%d", mag), (mag == 0);
		}

		if (w.Ammo1 == null) return "", false;
		return String.Format("%d", w.Ammo1.Amount), (w.Ammo1.Amount == 0);
	}

	private void dropTag(int hand)
	{
		if (mTagId[hand] != 0) { level.RemoveBillboard(mTagId[hand]); mTagId[hand] = 0; }
		mTagText[hand] = "";
		mTagFor[hand]  = null;
		mTagDry[hand]  = false;
		mTagHue[hand]     = 0;
		mTagPayload[hand] = 0;
	}

	private void updateTag(PlayerPawn pmo, int hand)
	{
		bool want = cv("wr_gun", 1.0) > 0.0;
		if (hand == 1 && cv("wr_gun_offhand", 1.0) <= 0.0) want = false;

		Weapon w = heldBy(hand);

		// Recomputed only on a weapon-class change, not every tic -- see
		// mMagCache's own field comment.
		if (w == null)
		{
			mMagCheckedFor[hand] = null;
			mMagCache[hand] = false;
		}
		else if (mMagCheckedFor[hand] != w.GetClass())
		{
			mMagCheckedFor[hand] = w.GetClass();
			mMagCache[hand] = wr_Rig.hasAltFire(w);
		}

		string txt; bool dry;
		[txt, dry] = countFor(w, mMagCache[hand]);

		bool dbg = cv("wr_debug", 0.0) > 0.0 && mDebugTics[hand]-- <= 0;
		if (dbg)
		{
			mDebugTics[hand] = 35;
			// A ternary needs both branches to already be the same type, and
			// GetClassName() returns Name where the other branch is a String
			// literal -- ".. ''" is the ZScript idiom that forces the coercion
			// (Console.Printf's %s takes a Name directly with no fuss, this is
			// purely the ternary's own type unification being stricter).
			Console.Printf("\c[Cyan]RSVR HUD gun[%d]:\c- want=%d weapon=%s txt='%s' override=%d",
				hand, int(want), (w == null) ? "null" : (w.GetClassName() .. ""), txt,
				int(pmo.OverrideAttackPosDir));
		}

		if (!want || w == null || txt == "") { dropTag(hand); return; }

		bool has; double oF, oL, oU, oYaw, oTilt, oRoll, pw, ph;
		[has, oF, oL, oU, oYaw, oTilt, oRoll, pw, ph] = placementFor(w.GetClass());

		// While placing, the weapon being placed follows the live edit values
		// instead of the stored ones -- that is what makes a nudge visible.
		if (mPlacing && hand == placeHand())
		{
			oF = mEdF; oL = mEdL; oU = mEdU;
			oYaw = mEdYaw; oTilt = mEdTilt; oRoll = mEdRoll;
			pw = mEdW; ph = mEdH;
		}

		double fx, fy, fz, lx, ly, lz;
		[fx, fy, fz, lx, ly, lz] = handFrame(pmo, hand);
		Vector3 fwd = (fx, fy, fz), left = (lx, ly, lz), up = fwd cross left;

		Vector3 pos = handPos(pmo, hand) + fwd * oF + left * oL + up * oU;

		// WHICH WAY THE FACE POINTS -- the one real choice in here.
		//
		// 0 lies it on the gun: the panel's normal is the hand's left axis, so
		// it sits on the weapon's flank and you turn the gun to read it. That
		// is the Dead Space reading and it only works because depth testing is
		// on by default and the VR weapon writes depth before the translucent
		// pass, so the gun genuinely occludes a panel buried in it.
		//
		// 1 turns it to you wherever the gun is pointing. Always readable,
		// never part of the weapon. Both ship; neither is correct.
		int mode = int(cv("wr_gun_face", 0.0));
		double side = (cv("wr_gun_side", 0.0) > 0.0) ? -1.0 : 1.0;

		double yaw, tilt, roll;
		int facing;

		if (mode == 1)
		{
			facing = LevelLocals.BBF_CAMERAYAW;
			yaw = 0; tilt = 0; roll = 0;
		}
		else
		{
			facing = LevelLocals.BBF_FIXED;
			Vector3 n = left * side;
			[yaw, tilt] = aimPanel(n);
			// Text runs along the barrel, not along the horizon.
			roll = rollToAlign(yaw, tilt, fwd);
			yaw += oYaw; tilt += oTilt; roll += oRoll;
		}

		color hue = dry ? color(int(cv("wr_gun_dry", 0xD8402E)))
		                : color(int(cv("wr_gun_color", 0x35E0A0)));

		int payload = (cv("wr_gun_lcd", 0.0) > 0.0) ? LevelLocals.BB_SEGLCD
		                                            : LevelLocals.BB_SEGMENT;

		// Rebuilt when the WEAPON changes, when dry-vs-loaded flips, or when
		// the hue or the payload shape (wr_gun_color/wr_gun_dry/wr_gun_lcd)
		// no longer match what this billboard was actually built with --
		// colour has no setter, so a colour change needs a new billboard,
		// and BB_SEGMENT/BB_SEGLCD are two different payloads, not a flag
		// on one. NOT rebuilt when only the number changes, or a counter
		// that destroyed and respawned itself every shot would restart its
		// own reveal animation on every trigger pull.
		if (mTagId[hand] == 0 || mTagFor[hand] != w.GetClass() || mTagDry[hand] != dry
			|| mTagHue[hand] != hue || mTagPayload[hand] != payload)
		{
			dropTag(hand);
			mTagId[hand] = level.AddBillboardPersistent(
				pos, pw, ph, yaw, tilt, facing, payload, 0, hue,
				LevelLocals.BBFL_PERSISTENT | LevelLocals.BBFL_NOHIT, 0, txt);

			// Unconditional, not gated on the heartbeat -- this only fires on a
			// weapon swap or a dry flip, so it is rare enough to print always,
			// and is the one line that actually says whether the native call
			// itself succeeded.
			if (cv("wr_debug", 0.0) > 0.0) Console.Printf(
				"\c[Cyan]RSVR HUD gun[%d]:\c- created id=%d pos=(%.1f,%.1f,%.1f) yaw=%.1f tilt=%.1f facing=%d size=%.1fx%.1f",
				hand, mTagId[hand], pos.X, pos.Y, pos.Z, yaw, tilt, facing, pw, ph);

			if (mTagId[hand] == 0) return;

			mTagFor[hand]  = w.GetClass();
			mTagText[hand] = txt;
			mTagDry[hand]  = dry;
			mTagHue[hand]     = hue;
			mTagPayload[hand] = payload;
			level.SetBillboardProgress(mTagId[hand], 1.0);
		}
		else if (mTagText[hand] != txt)
		{
			level.SetBillboardText(mTagId[hand], txt);
			mTagText[hand] = txt;
		}

		level.MoveBillboard(mTagId[hand], pos);
		level.ResizeBillboard(mTagId[hand], pw, ph);
		level.OrientBillboard(mTagId[hand], yaw, tilt, facing);
		level.RollBillboard(mTagId[hand], roll);
		level.SetBillboardGlow(mTagId[hand],
			clamp(cv("wr_gun_glow", 0.7), 0.0, 1.0), cv("wr_gun_glow", 0.7));
	}

	//==========================================================================
	// Placement mode
	//==========================================================================

	// The hand being placed ONTO is the one holding a gun worth placing; the
	// other is the cursor. Main hand by default, and swappable, because a
	// left-handed player placing an offhand weapon needs it the other way.
	private int placeHand() const { return (cv("wr_gun_placehand", 0.0) > 0.0) ? 1 : 0; }
	private int freeHand()  const { return placeHand() == 1 ? 0 : 1; }

	private void beginPlace()
	{
		let pmo = players[consoleplayer].mo;
		if (pmo == null) return;

		Weapon w = heldBy(placeHand());
		if (w == null)
		{
			Console.Printf("\c[Brick]RSVR HUD:\c- nothing in that hand to place on.");
			return;
		}

		bool has;
		[has, mEdF, mEdL, mEdU, mEdYaw, mEdTilt, mEdRoll, mEdW, mEdH]
			= placementFor(w.GetClass());

		mPlacing  = true;
		mHaveA    = false;
		mMeasured = "";

		Console.Printf("\c[Gold]RSVR HUD placement\c- -- %s%s",
			w.GetClassName(), has ? " (already measured)" : " (using defaults)");
		Console.Printf("  put your free hand where you want it and \c[Gold]wr_lock\c-");
		Console.Printf("  \c[Gold]wr_nudge\c- to fine tune, \c[Gold]wr_measure\c- for a two-point size, \c[Gold]wr_save\c- to print");
	}

	private void endPlace()
	{
		mPlacing = false;
		if (mGhostId   != 0) { level.RemoveBillboard(mGhostId);   mGhostId = 0; }
		if (mReadoutId != 0) { level.RemoveBillboard(mReadoutId); mReadoutId = 0; }
	}

	// The free hand's position expressed in the placed hand's frame. THIS IS
	// THE CALIBRATION -- you physically touch the spot on the gun and the three
	// numbers fall out of a dot product. No bounds, no guessing, no table.
	private bool, double, double, double cursorTriple(PlayerPawn pmo) const
	{
		if (!pmo.OverrideAttackPosDir) return false, 0, 0, 0;

		double fx, fy, fz, lx, ly, lz;
		[fx, fy, fz, lx, ly, lz] = handFrame(pmo, placeHand());
		Vector3 fwd = (fx, fy, fz), left = (lx, ly, lz), up = fwd cross left;

		Vector3 d = handPos(pmo, freeHand()) - handPos(pmo, placeHand());
		return true, d dot fwd, d dot left, d dot up;
	}

	private void lockHere()
	{
		let pmo = players[consoleplayer].mo;
		if (pmo == null || !mPlacing) return;

		bool ok; double f, l, u;
		[ok, f, l, u] = cursorTriple(pmo);
		if (!ok)
		{
			Console.Printf("\c[Brick]RSVR HUD:\c- no tracked hands -- nudge instead.");
			return;
		}

		mEdF = f; mEdL = l; mEdU = u;
		Console.Printf("\c[Gold]locked\c- F %.2f  L %.2f  U %.2f", f, l, u);
	}

	// Two points, and the distance between them. This is the "how big is the
	// BFG" answer, and it beats a bounds native outright: it measures the model
	// as DRAWN -- after MODELDEF scale, after vr_weaponScale, after every term
	// in the transform chain -- for every model format, including the ones that
	// keep no bounds in memory at all.
	private void measureStep()
	{
		let pmo = players[consoleplayer].mo;
		if (pmo == null || !mPlacing || !pmo.OverrideAttackPosDir) return;

		Vector3 here = handPos(pmo, freeHand());

		if (!mHaveA)
		{
			mPointA = here;
			mHaveA  = true;
			Console.Printf("\c[Gold]point A\c- set -- move to the other end and \c[Gold]wr_measure\c- again");
			return;
		}

		double d = (here - mPointA).Length();
		mHaveA = false;
		mMeasured = String.Format("%.1f units", d);

		Console.Printf("\c[Gold]measured\c- %.2f map units (%.1f panel widths at %.1f wide)",
			d, mEdW > 0.01 ? d / mEdW : 0.0, mEdW);
	}

	private void nudge(int axis, int dir)
	{
		if (!mPlacing) return;

		double step = cv("wr_gun_step", 0.25) * (dir < 0 ? -1.0 : 1.0);
		double astep = cv("wr_gun_astep", 5.0) * (dir < 0 ? -1.0 : 1.0);

		switch (axis)
		{
			case AXIS_F:    mEdF += step; break;
			case AXIS_L:    mEdL += step; break;
			case AXIS_U:    mEdU += step; break;
			case AXIS_YAW:  mEdYaw += astep; break;
			case AXIS_TILT: mEdTilt += astep; break;
			case AXIS_ROLL: mEdRoll += astep; break;
			case AXIS_W:    mEdW = max(0.5, mEdW + step); break;
			case AXIS_H:    mEdH = max(0.25, mEdH + step); break;
		}
	}

	// Printed, not written to a file.
	//
	// The engine has JSON profile natives that would persist this properly, but
	// they are uncommitted work sitting in a shared tree -- depending on them
	// would couple this mod to another branch's in-progress state. A printed
	// block costs one paste and works on every build.
	private void savePlacement()
	{
		let pmo = players[consoleplayer].mo;
		if (pmo == null || !mPlacing) return;

		Weapon w = heldBy(placeHand());
		if (w == null) return;

		calStore(w.GetClass(), mEdF, mEdL, mEdU, mEdYaw, mEdTilt, mEdRoll, mEdW, mEdH);

		Console.Printf("\c[Gold]-- paste into wr_GunTag.builtinCalibration --\c-");
		Console.Printf("\t\tcal(\"%s\", %.2f, %.2f, %.2f, %.1f, %.1f, %.1f, %.2f, %.2f);",
			w.GetClassName(), mEdF, mEdL, mEdU, mEdYaw, mEdTilt, mEdRoll, mEdW, mEdH);
		if (mMeasured != "") Console.Printf("\t\t// measured %s", mMeasured);
	}

	private void cal(string cls, double f, double l, double u,
	                 double yw, double tl, double rl, double w, double h)
	{
		mCalClass.Push(cls);
		mCalF.Push(f); mCalL.Push(l); mCalU.Push(u);
		mCalYaw.Push(yw); mCalTilt.Push(tl); mCalRoll.Push(rl);
		mCalW.Push(w); mCalH.Push(h);
	}

	// Measured placements go here. Empty until somebody has actually stood in a
	// headset and put one somewhere -- a table of plausible-looking numbers
	// nobody verified is worse than no table, because it looks measured.
	private void builtinCalibration()
	{
	}

	// The cursor and the numbers, both parked at the free hand so you never
	// have to take the headset off to read what you are doing.
	private void updatePlaceUI(PlayerPawn pmo)
	{
		if (!mPlacing) { endPlace(); return; }
		if (!pmo.OverrideAttackPosDir) return;

		Vector3 at = handPos(pmo, freeHand());

		if (mGhostId == 0)
		{
			mGhostId = level.AddBillboardPersistent(
				at, 0.8, 0.8, 0, 0, LevelLocals.BBF_CAMERAYAW,
				LevelLocals.BB_RING, 0, 0xFFC24A,
				LevelLocals.BBFL_PERSISTENT | LevelLocals.BBFL_NOHIT
				| LevelLocals.BBFL_NODEPTH);
		}
		if (mGhostId != 0) level.MoveBillboard(mGhostId, at);

		bool ok; double f, l, u;
		[ok, f, l, u] = cursorTriple(pmo);

		string sheet = String.Format(
			"CURSOR  F %.2f  L %.2f  U %.2f\nPLACED  F %.2f  L %.2f  U %.2f\nANG  %.0f / %.0f / %.0f    SIZE  %.2f x %.2f%s",
			f, l, u, mEdF, mEdL, mEdU,
			mEdYaw, mEdTilt, mEdRoll, mEdW, mEdH,
			mMeasured == "" ? "" : ("\nMEASURED  " .. mMeasured));

		double fx, fy, fz, lx, ly, lz;
		[fx, fy, fz, lx, ly, lz] = handFrame(pmo, freeHand());
		Vector3 fwd = (fx, fy, fz), left = (lx, ly, lz), up = fwd cross left;
		Vector3 sheetAt = at + fwd * 8.0 + up * 4.0;

		if (mReadoutId == 0)
		{
			mReadoutId = level.AddBillboardPersistent(
				sheetAt, 26, 9, 0, 0, LevelLocals.BBF_CAMERAYAW,
				LevelLocals.BB_TEXT, 0, 0xFFE9B0,
				LevelLocals.BBFL_PERSISTENT | LevelLocals.BBFL_NOHIT
				| LevelLocals.BBFL_NODEPTH, 0, sheet);
		}
		else
		{
			level.SetBillboardText(mReadoutId, sheet);
			level.MoveBillboard(mReadoutId, sheetAt);
		}
	}

	//==========================================================================
	// Plumbing
	//==========================================================================

	override void OnRegister()
	{
		builtinCalibration();
	}

	override void WorldTick()
	{
		let pmo = players[consoleplayer].mo;
		if (pmo == null) return;

		updateTag(pmo, 0);
		updateTag(pmo, 1);

		if (mPlacing) updatePlaceUI(pmo);
	}

	override void WorldUnloaded(WorldEvent e)
	{
		dropTag(0);
		dropTag(1);
		endPlace();
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Player != consoleplayer) return;

		if (e.Name ~== "wr_place")
		{
			if (mPlacing) { endPlace(); Console.Printf("\c[Gold]RSVR HUD:\c- placement off."); }
			else beginPlace();
			return;
		}

		if (e.Name ~== "wr_lock")    { lockHere();      return; }
		if (e.Name ~== "wr_measure") { measureStep();   return; }
		if (e.Name ~== "wr_save")    { savePlacement(); return; }
		if (e.Name ~== "wr_nudge")   { nudge(e.Args[0], e.Args[1]); return; }
	}
}
