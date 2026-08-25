// THE HAND IS A SLOT. Part A of the Reload Rig Contract, implemented.
//
// A hand holds exactly one thing. The chest pouch swaps what that is.
// GRIP IS THE VERB.
//
//   weapon    default -- the hand holds whatever it was holding
//   -> hands  hand enters the pouch; its weapon SWAPS OUT for open hands.
//             It is not stored there. The pouch holds ammunition only.
//   -> ammo   grip pressed inside the pouch spawns ammunition for the weapon
//             in the OPPOSITE hand
//   -> weapon ammo leaves; the weapon swaps back in
//
// Ammunition stays in the feeder hand until exactly one of four things happens,
// and all four end the same way -- the hand gets its weapon back:
//
//   SEATED    released inside the target weapon's magwell
//   RETURNED  released inside the pouch
//   DROPPED   released anywhere else
//   THROWN    released with speed. Not built; falls through to DROPPED.
//
// The first three are the contract's; DROPPED is the owner's addition and is
// just what release-anywhere means once grip is the verb.
//
// WHAT THIS REPLACES. The first cut of this file was a proximity beat runner:
// touch the magwell, pull away, touch it again, no grip, no pouch, no carry,
// no weapon swap. It was invented rather than read, and it modelled a game
// where one hand is empty. This one is a gun in EVERY hand -- which is why the
// feeder hand has to give its own weapon up to carry a magazine at all, and why
// reloading costs you your other gun for the duration. That cost is the point.
//
// THE WEAPON SWAP IS NOT DONE HERE. RS_Holsters' pouch already stores each
// hand's real weapon on pouch entry (pouchPreviousMain/Off) and restores it when
// the hand's GripClaim goes back to None -- watching the claim BROADLY, not just
// its own, precisely so this mod can take the claim over mid-carry and the
// weapon stays away until the ammunition is gone. So the entire swap contract
// here is: hold a claim while carrying, drop it when the ammo leaves.

class RR_Reload : EventHandler
{
	// Single player. usercmd_t carries weaponpitch/weaponyaw only -- main hand,
	// direction, no position and no off hand at all -- and every measurement
	// here reads a hand POSITION. This goes multiplayer when the protocol
	// grows, not before.

	enum RR_State
	{
		RR_IDLE = 0,
		RR_CARRY        // ammunition in the feeder hand, grip held
	}

	private int  state;
	private int  feeder;      // 0 main, 1 off -- the hand that went to the pouch
	private int  gunHand;     // the opposite hand: whose weapon is being fed
	private int  feed;
	private int  arch;
	private int  claimed;     // what we last wrote to this hand's GripClaim
	private Name target;      // class of the weapon being fed
	private int  guard;       // debounce, tics

	static RR_Reload Get() { return RR_Reload(EventHandler.Find("RR_Reload")); }

	override void WorldTick()
	{
		let p = players[consoleplayer];
		if (!p) return;
		let pmo = p.mo;
		if (!pmo || pmo.health < 1) { Abort(pmo); return; }

		if (guard > 0) guard--;

		if (state == RR_CARRY) { Carry(p, pmo); return; }
		Watch(p, pmo);
	}

	// ---- idle: watch both hands for a grip inside the pouch -----------------

	private void Watch(PlayerInfo p, PlayerPawn pmo)
	{
		if (guard > 0) return;

		// BOTH HANDS, and that is the whole reason this is not hardcoded to the
		// off hand: with a gun in each hand there is no hand that starts free,
		// so either one may be the feeder and the other is then the gun hand.
		for (int h = 0; h < 2; h++)
		{
			if (!InPouch(pmo, h)) continue;
			if (!GripHeld(pmo, h)) continue;

			int g = 1 - h;
			let w = WeaponIn(p, g);
			if (!w) continue;                      // nothing to feed

			int f, a;
			[f, a] = RR_Feed.Resolve(w, p);
			if (f == RR_F_NONE) continue;

			Begin(p, pmo, h, g, f, a, w);
			return;
		}
	}

	private void Begin(PlayerInfo p, PlayerPawn pmo, int h, int g, int f, int a, Weapon w)
	{
		state  = RR_CARRY;
		feeder = h;
		gunHand = g;
		feed   = f;
		arch   = a;
		target = w.GetClassName();

		// Where the pouch WAS, captured at the moment the hand was in it and
		// the arbiter still said so. RS_Holsters owns the anchor and does not
		// export its position, and once we claim Magazine over it the subject
		// stops answering -- so the only chance to learn the location is now.
		pouchAt = RR_Point.HandPos(pmo, h);

		// The contract's claim table: the pouch sets GRIPSUBJ_Pouch on entry,
		// and THE RELOAD MOD sets GRIPSUBJ_Magazine when ammunition is handed
		// over. The pouch then sees a claim that is not its own and neither
		// overwrites nor clears it -- which is what keeps the feeder hand's
		// weapon swapped out for the whole carry rather than only while the
		// hand is physically inside the volume.
		Claim(pmo, SubjectFor(feed));
		RR_Ammo.Show(p, feed, feeder);

		level.VRHaptic(feeder, 0.5, 45);
		Sound(pmo, SndDraw(feed));
		if (Debug(p)) Console.Printf("[RR] draw: feeder=%d gun=%d feed=%d arch=%d (%s)",
			feeder, gunHand, feed, arch, target);
	}

	// ---- carrying -----------------------------------------------------------

	private void Carry(PlayerInfo p, PlayerPawn pmo)
	{
		// The gun hand's weapon going away mid-carry ends it. The magwell was
		// sized for that gun and there is nothing left to feed.
		let w = WeaponIn(p, gunHand);
		if (!w || w.GetClassName() != target) { Release(p, pmo, false, false); return; }

		Claim(pmo, SubjectFor(feed));
		RR_Ammo.Show(p, feed, feeder);

		double len  = RR_Feed.LenOf(arch, p);
		double grip = RR_Feed.GripOf(arch, p);
		Vector3 pt  = RR_Point.World(pmo, RR_Feed.Magwell(feed), len, grip, gunHand);
		bool onWell = RR_Point.Score(pmo, pt, RR_Feed.Radii(feed), gunHand, feeder) <= 1.0;

		if (ShowMarks(p)) RR_Point.Mark(pmo, pt, onWell ? 0x30FF60 : 0xFFA030);

		// As the ammunition closes on the insertion point the hand changes shape
		// for the insert -- GRIPSUBJ_Inserting is POSE_INSERT, thumb driving it
		// home. The contract calls for the pose to lead the seat, not follow it.
		if (onWell) Claim(pmo, GRIPSUBJ_Inserting);

		// RELEASE IS WHAT ENDS IT. Grip held = still carrying.
		if (GripHeld(pmo, feeder)) return;

		Release(p, pmo, onWell, InPouchGeom(pmo, feeder));
	}

	// ---- the four exits -----------------------------------------------------

	private void Release(PlayerInfo p, PlayerPawn pmo, bool onWell, bool inPouch)
	{
		if (onWell)
		{
			Seat(p, pmo);
		}
		else if (inPouch)
		{
			// RETURNED. Note this is a GEOMETRIC test and not IsHandInPouch's
			// question: the arbitrated subject reads as Magazine, not Pouch,
			// for a hand that is carrying -- correct for "is this hand still
			// just reaching", useless for "has the ammunition been put back".
			// Conflating the two makes this exit undetectable.
			Sound(pmo, "rr/stow");
			level.VRHaptic(feeder, 0.4, 40);
			if (Debug(p)) Console.Printf("[RR] returned to pouch");
		}
		else
		{
			// DROPPED. Thrown is the same exit with speed on it and is not
			// built -- the contract lists it as unbuilt too.
			Sound(pmo, "rr/drop");
			level.VRHaptic(feeder, 0.3, 30);
			if (Debug(p)) Console.Printf("[RR] dropped");
		}

		// All four exits end identically: the claim goes, and RS_Holsters gives
		// the feeder hand its weapon back because it watches for exactly that.
		Abort(pmo);
		guard = 10;
	}

	private void Seat(PlayerInfo p, PlayerPawn pmo)
	{
		Sound(pmo, SndSeat(feed));
		level.VRHaptic(feeder, 0.75, 90);
		level.VRHaptic(gunHand, 0.55, 70);
		Refill(p, WeaponIn(p, gunHand));
		if (Debug(p)) Console.Printf("[RR] seated in %s", target);
	}

	// MAGAZINES OFF BY DEFAULT while the gesture is being tuned. When it goes
	// on the mechanism is a reserve swap -- the real Ammo item holds only the
	// current magazine and a shadow item holds the pool, so GZDoom's own
	// CheckAmmo does the gating and no per-weapon hook is needed anywhere.
	private void Refill(PlayerInfo p, Weapon w)
	{
		if (!w) return;
		let c = CVar.GetCVar("rr_magazines", p);
		if (!c || !c.GetBool()) return;
		// slice 5.
	}

	// ---- plumbing -----------------------------------------------------------

	private static Weapon WeaponIn(PlayerInfo p, int hand)
	{
		return (hand == 0) ? p.ReadyWeapon : p.OffhandWeapon;
	}

	private static bool GripHeld(PlayerPawn pmo, int hand)
	{
		return (hand == 0) ? pmo.GripHeldMain : pmo.GripHeldOff;
	}

	// The ARBITRATED answer: true only while the hand is empty-reaching. Goes
	// false the moment we claim Magazine over it, which is what we want for
	// starting a carry and wrong for ending one -- see InPouchGeom.
	private static bool InPouch(PlayerPawn pmo, int hand)
	{
		int s = (hand == 0) ? pmo.GripSubjectMain : pmo.GripSubjectOff;
		return s == GRIPSUBJ_Pouch;
	}

	// GEOMETRY, true regardless of what the hand holds.
	//
	// RS_Holsters owns the pouch anchor and does not export its position, so
	// this asks the only question that survives without it: is the feeder hand
	// back where it started. The start position is captured on Begin.
	private bool InPouchGeom(PlayerPawn pmo, int hand)
	{
		return (RR_Point.HandPos(pmo, hand) - pouchAt).Length() <= POUCH_R;
	}

	private Vector3 pouchAt;
	const POUCH_R = 3.5;   // matches RS_Holsters' AmmoPouch hsRadius

	private static int SubjectFor(int feed)
	{
		switch (feed)
		{
		case RR_F_PUMP:
		case RR_F_BREAK: return GRIPSUBJ_Shell;
		case RR_F_POD:   return GRIPSUBJ_Round;
		}
		return GRIPSUBJ_Magazine;
	}

	private static String SndDraw(int feed)
	{
		if (feed == RR_F_PUMP || feed == RR_F_BREAK) return "rr/shelldraw";
		if (feed == RR_F_CELL) return "rr/celldraw";
		return "rr/magdraw";
	}

	private static String SndSeat(int feed)
	{
		if (feed == RR_F_PUMP || feed == RR_F_BREAK) return "rr/shellin";
		if (feed == RR_F_CELL) return "rr/cellin";
		if (feed == RR_F_POD)  return "rr/podin";
		return "rr/magin";
	}

	private static void Sound(PlayerPawn pmo, String s)
	{
		if (s.Length()) pmo.A_StartSound(s, CHAN_WEAPON, CHANF_OVERLAP);
	}

	// SET while carrying, and clear ONLY a value that is ours. More than one mod
	// writes GripClaim* -- the pouch, rs_hands' grab family, this -- and clearing
	// another package's claim leaves a hand posed for something it is not
	// holding, with nothing in the log.
	private void Claim(PlayerPawn pmo, int subj)
	{
		if (feeder == 0) pmo.GripClaimMain = subj;
		else             pmo.GripClaimOff  = subj;
		claimed = subj;
	}

	private void Abort(Actor a)
	{
		let pmo = PlayerPawn(a);
		if (pmo && claimed != GRIPSUBJ_None)
		{
			int cur = (feeder == 0) ? pmo.GripClaimMain : pmo.GripClaimOff;
			if (cur == claimed)
			{
				if (feeder == 0) pmo.GripClaimMain = GRIPSUBJ_None;
				else             pmo.GripClaimOff  = GRIPSUBJ_None;
			}
		}
		if (pmo && pmo.player) RR_Ammo.Hide(pmo.player, feeder);

		claimed = GRIPSUBJ_None;
		state   = RR_IDLE;
		target  = 'None';
	}

	private static bool Debug(PlayerInfo p)
	{
		let c = CVar.GetCVar("rr_debug", p);
		return c && c.GetBool();
	}

	private static bool ShowMarks(PlayerInfo p)
	{
		let c = CVar.GetCVar("rr_marks", p);
		return c && c.GetBool();
	}
}
