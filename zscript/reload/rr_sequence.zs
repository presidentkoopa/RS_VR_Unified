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

	// RENAMED FROM `state` ON 2026-08-26, AND THIS PACKAGE HAD NEVER COMPILED
	// UNTIL IT WAS.
	//
	// `state` is a TYPE in ZScript. At the start of a statement the parser sees
	// it and expects a declaration -- `state foo;` -- so `state = RR_CARRY;`
	// fails with "Unexpected '=' Expecting identifier". The declaration itself
	// parses, and so does `if (state == RR_CARRY)`, because that is expression
	// position where no declaration is possible. Only assignment at statement
	// start breaks, which is why this survived every read-through: four of the
	// five uses look fine and are.
	//
	// The same trap took out this file's `Sound()` helper, now PlaySnd() --
	// `sound` is also a type, so `Sound(pmo, ...)` at statement start reads as
	// `Sound <identifier>` and fails identically.
	//
	// Six errors, one file, from the very first commit. RS_Reload was written
	// in a single sitting and never loaded, so nothing ever told anyone. Worth
	// remembering the next time a package "just needs a quick test in headset":
	// it took from 2026-08-25 to 2026-08-26 for the engine to say so.
	private int  phase;
	private int  feeder;      // 0 main, 1 off -- the hand that went to the pouch
	private int  gunHand;     // the opposite hand: whose weapon is being fed
	private int  feed;
	private int  arch;
	private int  claimed;     // what we last wrote to this hand's GripClaim
	private Name target;      // class of the weapon being fed
	private int  guard;       // debounce, tics

	// NO Get() ACCESSOR, DELIBERATELY. One was here --
	// `RR_Reload(EventHandler.Find("RR_Reload"))` -- with zero call sites, and
	// it went on 2026-08-26 for a second reason beyond being dead.
	//
	// EventHandler.Find(literal) is a COMPILE-TIME link and not a lookup. A
	// missing class there does not return null, it fails to compile -- and a
	// ZScript error is fatal AND GLOBAL: thingdef.cpp:420-424 calls I_Error and
	// then refuses to compile every pk3 LATER IN THE LOAD ORDER as well, so one
	// unused convenience function is enough to stop the game starting. Nothing
	// outside this file needs a handle on the runner. If something ever does,
	// reach it with ServiceIterator.Find(String), which fails soft.
	//
	// MAPINFO.txt registers this handler through AddEventHandlers, which is what
	// makes it tick; that is the only wiring it has ever needed.

	override void WorldTick()
	{
		let p = players[consoleplayer];
		if (!p) return;

		// FIRST, and above the dead-player early-out on purpose: the probe
		// touches no pawn and nothing about the reload sequence, so there is no
		// reason for it to stop running when the player dies -- and a handshake
		// that only ever runs while alive is a handshake that is harder to
		// watch. See the grip arbiter section further down.
		ArbiterProbe(p);

		let pmo = p.mo;
		if (!pmo || pmo.health < 1) { Abort(pmo); return; }

		if (guard > 0) guard--;

		// ABOVE THE CARRY/WATCH BRANCH, because both of those return. Magazine
		// upkeep is not part of the gesture -- it has to run while the player is
		// walking around firing, which is most of the time and none of it is
		// spent in a carry. It is also what performs the one-time conversion of
		// an existing flat ammo pool the first tic rr_magazines is switched on,
		// so it cannot wait for a reload that the player cannot yet perform.
		Magazines(p, pmo);

		if (phase == RR_CARRY) { Carry(p, pmo); return; }
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
		phase  = RR_CARRY;
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
		PlaySnd(pmo, SndDraw(feed));
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
			PlaySnd(pmo, "rr/stow");
			level.VRHaptic(feeder, 0.4, 40);
			if (Debug(p)) Console.Printf("[RR] returned to pouch");
		}
		else
		{
			// DROPPED. Thrown is the same exit with speed on it and is not
			// built -- the contract lists it as unbuilt too.
			PlaySnd(pmo, "rr/drop");
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
		PlaySnd(pmo, SndSeat(feed));
		level.VRHaptic(feeder, 0.75, 90);
		level.VRHaptic(gunHand, 0.55, 70);
		Refill(p, pmo, WeaponIn(p, gunHand));
		if (Debug(p)) Console.Printf("[RR] seated in %s", target);
	}

	// MAGAZINES OFF BY DEFAULT while the gesture is being tuned. The mechanism
	// is a reserve swap -- the real Ammo item holds only the current magazine
	// and a shadow item holds the pool, so GZDoom's own CheckAmmo does the
	// gating and no per-weapon hook is needed anywhere. rr_magazine.zs holds all
	// of it; this function is only the moment it happens.
	//
	// WAS `// slice 5.` AND NOTHING ELSE UNTIL 2026-08-26, which made the whole
	// package a gesture demo: the pouch, the carry and all four exits worked and
	// no ammunition ever moved.
	//
	// THE DEBIT IS HERE, AT THE SEAT, AND NOWHERE EARLIER. Not when the magazine
	// was drawn out of the pouch, not while it is being carried. That is what
	// makes the DROPPED exit cost the trip and nothing else, and it is the only
	// reason README's "reloads can be missed but nothing is ever lost" is a true
	// statement about the code rather than about the intention.
	//
	// WITH rr_magazines OFF THIS STILL RETURNS IMMEDIATELY, and that is correct
	// rather than unfinished. Vanilla has one flat pool and there is nothing to
	// transfer; the reload is a gesture over an unchanged pool.
	private void Refill(PlayerInfo p, PlayerPawn pmo, Weapon w)
	{
		if (!w || !pmo) return;
		let c = CVar.GetCVar("rr_magazines", p);
		if (!c || !c.GetBool()) return;

		int cap = RR_Feed.CapOf(arch, w, p);
		int per = RR_Feed.SeatOf(arch, w);
		int got = RR_Mag.Insert(pmo, w, cap, per);

		if (!Debug(p)) return;

		// Reported even when nothing moved, because "nothing moved" is the
		// answer with the most ways to be wrong -- magazine already full,
		// reserve empty, no ammo item, an archetype with no capacity -- and a
		// silent no-op looks identical to the feature not being wired up at all,
		// which is the exact confusion this file just spent a slice in.
		let am = RR_Mag.AmmoOf(pmo, w);
		if (!am) { Console.Printf("[RR] refill: %s has no ammo item", target); return; }
		Console.Printf("[RR] refill: +%d -- magazine %d/%d, reserve %d",
			got, am.Amount, cap, RR_Mag.Pool(pmo, am));
	}

	// ---- magazine upkeep, every tic -----------------------------------------
	//
	// TWO JOBS AND THEY ARE BOTH HOUSEKEEPING: hold each held weapon's ammo item
	// at or below its magazine size, spilling the rest into the reserve, and
	// keep an empty-but-reloadable gun in the hand that is holding it.
	//
	// RESOLVED FRESH EVERY TIC RATHER THAN CACHED. RR_Feed.Resolve does string
	// work on two class names and reads two cvars; a cache would be two more
	// handler fields that go stale the moment somebody moves rr_force_arch,
	// which is the tuning knob most likely to be moved while watching this. Two
	// short IndexOf chains a tic is not what will make this mod slow.
	private void Magazines(PlayerInfo p, PlayerPawn pmo)
	{
		let w0 = p.ReadyWeapon;
		let w1 = p.OffhandWeapon;

		let c = CVar.GetCVar("rr_magazines", p);
		if (!c || !c.GetBool())
		{
			// OFF MUST MEAN EXACTLY VANILLA, including for a player who had it
			// on five minutes ago. If no reserve was ever created this costs one
			// FindInventory that returns null and nothing else happens -- which
			// is the whole of the off path in a game that never used the
			// feature, and it is why the flag restores below sit INSIDE this
			// branch rather than running unconditionally.
			//
			// If one does exist the pool is handed straight back to the real
			// ammo items, so toggling off returns the ammunition instead of
			// stranding most of it in an item nothing reads any more.
			let r = RR_Mag.Bag(pmo, false);
			if (!r) return;

			r.Dump();
			RR_Mag.RestoreKeep(w0);
			RR_Mag.RestoreKeep(w1);
			return;
		}

		let a0 = RR_Mag.AmmoOf(pmo, w0);
		let a1 = RR_Mag.AmmoOf(pmo, w1);

		int cap0 = a0 ? RR_Feed.CapOf(ArchOf(p, w0), w0, p) : 0;
		int cap1 = a1 ? RR_Feed.CapOf(ArchOf(p, w1), w1, p) : 0;

		// ONE POOL, ONE MAGAZINE, AND THE BIGGER GUN WINS.
		//
		// GZDoom ammo is shared by ammo CLASS, not by weapon: Doom's pistol and
		// chaingun both draw Clip out of the same item, and this is a dual-wield
		// engine so both can be in your hands at once. There is exactly one
		// Amount to cap and two answers for what to cap it at, and taking the
		// smaller one would drain the chaingun's magazine into the reserve every
		// tic the pistol was in the other hand -- a gun quietly emptying itself
		// because of what the OTHER hand is holding. Taking the larger costs
		// nothing: the pistol simply has more in front of it than a pistol
		// normally would, out of a pool it was always sharing anyway.
		//
		// Nothing is lost or duplicated either way. Amount + reserve is what is
		// conserved, and every path in rr_magazine.zs moves between the two.
		if (a0 && a0 == a1)
		{
			int shared = max(cap0, cap1);
			cap0 = shared;
			cap1 = shared;
		}

		if (a0) RR_Mag.Trim(pmo, a0, cap0);
		if (a1 && a1 != a0) RR_Mag.Trim(pmo, a1, cap1);

		RR_Mag.KeepEmpty(pmo, w0);
		RR_Mag.KeepEmpty(pmo, w1);
	}

	// Archetype only. Resolve returns the feed as well and the caller above has
	// no use for it -- the feed picks the sequence and the mesh, and capacity is
	// a property of the gun.
	private static int ArchOf(PlayerInfo p, Weapon w)
	{
		if (!w) return RR_A_MELEE;
		int f, a;
		[f, a] = RR_Feed.Resolve(w, p);
		return a;
	}

	// ---- the grip arbiter handshake -----------------------------------------
	//
	// THIS CHANGES NOTHING, AND THAT IS THE ENTIRE POINT.
	//
	// RS_GripArbiter is a sixth, OPTIONAL pk3. Its v1 answers a handshake and
	// nothing else -- it writes no field, reads no player and registers no
	// handler. This is its FIRST consumer and it is deliberately just as inert:
	// it finds the arbiter, confirms the answer is really the arbiter's, prints
	// one line behind rr_debug, and leaves Claim(), Abort() and every single
	// GripClaim write byte-for-byte as they were. Real arbitration is a later
	// step and is not worth building on top of a lookup nobody has ever watched
	// run once.
	//
	// Three things get proved here, none of which anyone has yet observed --
	// which matters more than usual because there is no test-compile anywhere
	// in this project and a ZScript error is fatal AND GLOBAL:
	//   1. the lookup returns cleanly with the arbiter pk3 ABSENT,
	//   2. a Service resolves and answers from inside play-scope WorldTick,
	//   3. a consumer compiles against it -- and this package declares version
	//      "5.0.0" while RS_Holsters, RS_HardPoints and Headshots declare 4.14
	//      and are converted after it, so nothing below may be 5.0-only.
	//
	// ServiceIterator.Find(String), NEVER Service.Find and NEVER
	// EventHandler.Find. Both of those take a CLASS and resolve it at COMPILE
	// time, so a missing optional pk3 is not a null return -- it is I_Error,
	// fatal and global, refusing to compile every pk3 later in the load order
	// (thingdef.cpp:420-424). That is the same trap the tombstone above
	// WorldTick was left to guard, and this is the first code in the package to
	// actually need the soft path it points at: ServiceIterator's Find takes a
	// plain String and its Next() just returns null (engine/service.zs:154-176).
	// Shipped precedent for the whole shape is RS_WeaponWheel zscript.zs:4439,
	// which finds RS_TierColorService from inside an EventHandler exactly this
	// way and degrades to "no colour" when RS_Main is not loaded.
	//
	// AND THE HIT IS VERIFIED RATHER THAN TRUSTED, because ServiceIterator
	// matching is a case-insensitive SUBSTRING test and not equality
	// (service.zs:167-176) -- any service whose class name merely CONTAINS
	// "RS_GripArbiterService" comes back too. So the iterator is walked instead
	// of sampled once, and a candidate only becomes the handle after it answers
	// "grip.hello" with the protocol number. Service's own base GetInt returns
	// 0 for anything a subclass did not override (service.zs:47-50), so an
	// impostor fails that test without having to know it is being tested.
	//
	// THE TEST IS EXACT EQUALITY, not "greater than zero", deliberately. It
	// buys identity and protocol agreement in one question: a future arbiter
	// that bumps the number reads as ABSENT to this consumer rather than as a
	// stranger it half-understands. For a consumer that changes no behaviour
	// that is the safe direction, and it is the direction the arbiter's own
	// header asks for -- fall back rather than believe a number you did not
	// expect.
	//
	// ALL SIX ARGUMENTS ARE SPELLED OUT on every call. The defaults live on the
	// base declaration and would be filled in anyway, but this parameter list
	// is the entire ABI between two packages that never name each other, and
	// writing it out is what turns a future signature drift into a compile
	// error here instead of a silently mis-bound call.

	// THE HANDLE IS CACHED AND RE-RESOLVED, never held forever. It reads back
	// null in three different situations and only one of them means "absent":
	//   * the arbiter pk3 genuinely is not loaded,
	//   * this handler was rebuilt for a new map -- MAPINFO's AddEventHandlers
	//     registers it per level, so it is a fresh object every time,
	//   * a savegame was loaded. InitServices flags every Service instance
	//     OF_Transient (vmnatives.cpp:62-75), so it is never serialised and
	//     this pointer comes back null with the arbiter sitting right there.
	//     The handler's OWN fields do survive that -- the local event handler
	//     chain is archived at p_saveg.cpp:1112 -- which is exactly why
	//     arbLogged stays true across a load and the line is not printed twice.
	private Service arbiter;

	// 0 never asked, 1 answered, 2 asked and absent. Tri-state and not a bool
	// beside the pointer, because "null handle" cannot tell "not yet" from
	// "not there", and the log line has to say which.
	private int  arbSeen;
	private int  arbProto;      // what it reported for "grip.version"
	private int  arbWait;       // tics left before the next lookup attempt
	private bool arbLogged;     // the one debug line has been printed

	// THE RETRY IS A COUNTDOWN AND NOT A DEADLINE, and the difference is not
	// cosmetic. ServiceIterator.Find news up a fresh iterator on every call
	// (service.zs:156), so a game running without the arbiter would otherwise
	// allocate one every tic forever to learn the same nothing. The obvious
	// form -- remember `gametic + N` and compare -- is wrong here: gametic
	// restarts at zero in a new process, so a deadline saved late in one
	// session is either already behind or unreachably ahead in the next one. A
	// countdown carries no absolute time inside it and cannot go stale.
	const RR_ARB_RETRY = 350;   // ~10s at 35Hz. Nothing depends on the value.

	// The protocol this consumer speaks. Matches RS_GripArbiterService's own
	// PROTOCOL; both move together or the handshake is meant to fail.
	const RR_ARB_PROTO = 1;

	private void ArbiterProbe(PlayerInfo p)
	{
		if (!arbiter)
		{
			if (arbWait > 0) arbWait--;
			else
			{
				Service found = null;
				int proto = 0;

				// Declared shape copied from the nearest working precedent for
				// an iterator walk in this stack -- RS_Hands handworld.zs:209
				// and rs_grabpolicy.zs:267, both `Iter it = Iter.Create(...);`
				// then a typed pointer assigned in the while condition. The
				// only difference is that Next() here already returns a Service
				// and needs no cast.
				ServiceIterator it = ServiceIterator.Find("RS_GripArbiterService");
				Service s;
				while (s = it.Next())
				{
					// IDENTITY, not presence. A substring hit is not proof.
					if (s.GetInt("grip.hello", "", 0, 0, null, 'None') != RR_ARB_PROTO)
						continue;

					found = s;

					// Asked separately even though v1 answers both requests
					// with the same number by construction. "grip.hello" is a
					// yes/no about identity; "grip.version" is the one that is
					// contracted to keep meaning a version when the vocabulary
					// grows. Reading the logged number off the wrong one would
					// make that divergence invisible.
					proto = s.GetInt("grip.version", "", 0, 0, null, 'None');
					break;
				}

				arbiter  = found;
				arbProto = found ? proto : 0;
				arbSeen  = found ? 1 : 2;

				// ONLY A FAILURE ARMS THE THROTTLE. A success leaves the
				// counter at zero on purpose, so the re-resolve after a
				// savegame load lands on the very next tic instead of up to ten
				// seconds later. Repeating is only expected of the miss.
				if (!found) arbWait = RR_ARB_RETRY;
			}
		}

		// ONE LINE, ONCE, AND IT IS THE WHOLE DELIVERABLE OF THIS CONVERSION.
		//
		// Gated on Debug rather than printed at the moment of resolution, so
		// that turning rr_debug on after the fact still produces it -- the
		// found handle stops the block above from running again, and if the
		// print lived up there the evidence would be unrecoverable for anyone
		// who had the cvar off at map start.
		if (arbLogged || arbSeen == 0 || !Debug(p)) return;
		arbLogged = true;

		if (arbSeen == 1)
			Console.Printf("[RR] arbiter: FOUND, protocol %d -- handshake ok, reload behaviour unchanged", arbProto);
		else
			Console.Printf("[RR] arbiter: absent -- lookup returned cleanly, reload behaviour unchanged");
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

	private static void PlaySnd(PlayerPawn pmo, String s)
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
		phase   = RR_IDLE;
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
