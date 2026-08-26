// DISTANCE GRABBING -- point at a thing across the room and it comes to you.
//
// Three parts, kept apart because they fail differently:
//
//   RS_Cone   the question "what am I pointing at". Pure geometry, no state.
//   RS_Pull   the flight. The only part that owns state, and it owns it per
//             hand for exactly as long as an object is in the air.
//   the hook  in RS_GrabHandler: a squeeze with nothing in your palm asks the
//             cone instead of giving up.
//
// REACH AND SPREAD ARE SEPARATE NUMBERS. How FAR you can pull from and how
// PRECISELY you have to point are different complaints with different fixes, and
// a single "cone size" slider forces one to be wrong to make the other right.

class RS_Cone play
{
	// The hand's forward axis. Same basis, same +90 on yaw, same order as
	// RS_Reach -- because a cone that tests one convention while the reach
	// volume tests another is two systems that disagree about where your hand
	// points, and that reads in the headset as the aim being randomly off.
	static Vector3 Dir(PlayerPawn pmo, int hand)
	{
		double yaw = ((hand == 0) ? pmo.AttackAngle : pmo.OffhandAngle) + 90;
		double pit = RS_Reach.HandPitch(pmo, hand);
		double rol = ((hand == 0) ? pmo.MainHandRoll : pmo.OffhandRoll);
		return RS_Basis.Fwd(yaw, pit, rol);
	}

	// The best thing in this hand's cone, or null.
	//
	// Scored on ANGLE FIRST and distance second, because pointing is what you
	// are actually doing. A nearer object well off your axis is not what you
	// meant; the thing you are pointing straight at is, even if something else
	// is closer to your hand.
	static Actor Best(PlayerPawn pmo, PlayerInfo p, int hand)
	{
		let pol = RS_GrabPolicy.Get();
		if (!pol) return null;

		double reach  = RS_Reach.Num("rs_dgrab_reach",  p, 512.0);
		double spread = RS_Reach.Num("rs_dgrab_spread", p, 12.0);
		if (reach <= 0 || spread <= 0) return null;

		Vector3 origin = RS_Reach.Centre(pmo, p, hand);
		Vector3 dir    = Dir(pmo, hand);

		// Compared as a COSINE, so the test is one dot product and no inverse
		// trig runs per candidate. cos is monotonically decreasing over 0..180,
		// so "within the spread" is "dot product at least this big".
		double cosLimit = cos(spread);

		Actor best = null;
		double bestScore = -2.0;

		// WHAT IS ALREADY IN A HAND IS NOT IN THE CONE, and the near path has had
		// this guard from the start (RS_Reach.Best). Without it the cone will
		// happily pick the object in your OTHER fist -- it is a legal grab
		// candidate, it is within reach, and it is usually the thing you are
		// looking straight at -- and then a flick tears it out of that hand and
		// throws it across the room at this one. There is no gesture for "yank it
		// out of my own grip", so there is nothing this could have meant.
		//
		// Broader than the near guard on purpose. The near path deliberately
		// keeps the other hand's object as a target, because closing on it there
		// means a second hand joining or a hand-to-hand pass, and RS_Held.Take
		// handles both. Nothing on the flight path does: RS_Pull.Start would
		// simply take it.
		let held = RS_Held.Get();

		BlockThingsIterator it =
			BlockThingsIterator.CreateFromPos(origin.x, origin.y, origin.z, reach, reach, false);
		while (it.Next())
		{
			Actor a = it.thing;
			if (!a || a == pmo) continue;
			if (held && held.IsHeld(a)) continue;
			if (!pol.Decide(a, pmo, p)) continue;

			// The MIDDLE of the thing, not its origin. A Doom actor's origin is
			// the floor of its volume, so aiming at a barrel by eye and testing
			// against its feet means pointing at the floor in front of it.
			Vector3 mid = (a.Pos.x, a.Pos.y, a.Pos.z + a.Height * 0.5);
			Vector3 d = mid - origin;
			double dist = d.Length();
			if (dist > reach || dist < 0.01) continue;

			double c = (d / dist) dot dir;
			if (c < cosLimit) continue;

			// Through walls is not pointing at it. Checked last, because it is
			// the only expensive test here and by this point at most a handful
			// of candidates have survived the cheap ones.
			if (RS_Reach.Flag("rs_dgrab_sight", p, true) && !pmo.CheckSight(a))
				continue;

			// Angle dominates; distance only separates two things you are
			// pointing at equally well.
			double score = c - (dist / reach) * 0.25;
			if (score > bestScore) { bestScore = score; best = a; }
		}
		return best;
	}
}

// THE FLIGHT.
//
// Owns an object for the fraction of a second between the squeeze and the catch,
// and owns nothing else. On arrival it hands over to RS_Held and forgets.
class RS_Pull : EventHandler
{
	private Actor   flyActor[2];
	private int     flyTic[2];
	private int     flyTotal[2];
	private Vector3 flyStart[2];
	// The LAUNCH distance, kept for the whole flight. Arc height is a fraction
	// of it, and re-measuring each tic would shrink the arc as the object closed
	// on you -- flattening the parabola into a straight line exactly as it
	// arrived, which is the one moment you are looking at it.
	private double  flyDist[2];

	// THE OBJECT'S OWN FLAGS, SAVED HERE AND HANDED OVER INTACT.
	//
	// Flight has to switch gravity off and pickup-on-touch off, exactly as
	// holding does. If it did that and then called RS_Held.Take, Take would save
	// the flags it found -- which are the ones flight just changed -- and record
	// "this object was always weightless and never touchable" as its original
	// state. Releasing it later would leave it floating and unpickable forever.
	//
	// So the true values are captured before flight touches anything, and put
	// back one line before the handover, so the state Take saves is the truth.
	private bool flySavedSpecial[2];
	private bool flySavedNoGrav[2];
	// THE THIRD ONE, and the barrel is why -- see the note in Start.
	private bool flySavedThruActors[2];

	// THE LOCK -- grabbed, and still across the room.
	//
	// This is the state the system was missing, and its absence is why a squeeze
	// used to launch things instantly. There are THREE acts, not two:
	//
	//   point   the cone considers it            neutral <-> orange
	//   GRIP    you take hold of it at range     orange  <-> green
	//   flick   you pull it to you               the flash stops
	//
	// The grip does not move anything. It says "that one", and it keeps saying
	// it until you flick, let go, or lose it. Collapsing the grip and the flick
	// into one act removes the only moment where you can change your mind.
	private Actor lockActor[2];

	static RS_Pull Get()
	{
		return RS_Pull(EventHandler.Find("RS_Pull"));
	}

	bool Flying(int hand) const
	{
		return (hand == 0 || hand == 1) && flyActor[hand] != null;
	}

	Actor Locked(int hand) const
	{
		if (hand != 0 && hand != 1) return null;
		return lockActor[hand];
	}

	// Take hold of it where it stands. Nothing moves.
	bool Lock(int hand, Actor a, PlayerPawn pmo, PlayerInfo p)
	{
		if (hand != 0 && hand != 1 || !a) return false;
		if (flyActor[hand]) return false;
		let held = RS_Held.Get();
		if (held && held.HandIsFull(hand)) return false;
		// Not something a hand already has hold of -- see the note in
		// RS_Cone.Best. Refused here as well as filtered there because the cone
		// is not the only thing that can name a target, and this is the door the
		// object actually leaves through.
		if (held && held.IsHeld(a)) return false;
		lockActor[hand] = a;
		if (RS_Reach.Flag("rs_hold_debug", p, true))
			Console.Printf("[RSPULL] hand %d LOCKED %s -- flick to pull it", hand, a.GetClassName());
		return true;
	}

	void Unlock(int hand)
	{
		if (hand != 0 && hand != 1) return;
		lockActor[hand] = null;
	}

	// A lock is not forever. It survives you looking away -- you already decided
	// -- but not the object dying, not your hand filling up, and not the thing
	// leaving the range you could have pulled it from anyway.
	private void ValidateLock(int hand, PlayerPawn pmo, PlayerInfo p)
	{
		Actor a = lockActor[hand];
		if (!a) return;
		let held = RS_Held.Get();
		if (held && held.HandIsFull(hand)) { Unlock(hand); return; }
		double reach = RS_Reach.Num("rs_dgrab_reach", p, 512.0);
		Vector3 mid = (a.Pos.x, a.Pos.y, a.Pos.z + a.Height * 0.5);
		if ((mid - RS_Reach.Centre(pmo, p, hand)).Length() > reach * 1.25)
		{
			if (RS_Reach.Flag("rs_hold_debug", p, true))
				Console.Printf("[RSPULL] hand %d lost its lock on %s -- out of range",
					hand, a.GetClassName());
			Unlock(hand);
		}
	}

	Actor FlyingActor(int hand) const
	{
		if (hand != 0 && hand != 1) return null;
		return flyActor[hand];
	}

	// Begin a pull. Returns false if it could not start, so the caller can say
	// so rather than silently doing nothing.
	bool Start(int hand, Actor a, PlayerPawn pmo, PlayerInfo p)
	{
		if (hand != 0 && hand != 1) return false;
		if (!a || flyActor[hand]) return false;

		let held = RS_Held.Get();
		if (!held || held.HandIsFull(hand)) return false;
		// Nor out of the other hand. Same reason as Lock: this is the call that
		// would actually launch it.
		if (held.IsHeld(a)) return false;

		// FLIGHT TIME COMES FROM THE DISTANCE, so near and far pulls travel at
		// the same SPEED. A fixed tic count meant a thing across the room moved
		// three times faster than one at your feet -- the far pull a blur, the
		// near one a drift, and both driven by the same slider.
		Vector3 mid0 = (a.Pos.x, a.Pos.y, a.Pos.z + a.Height * 0.5);
		double dist = (mid0 - RS_Reach.Centre(pmo, p, hand)).Length();
		double upt  = RS_Swing.MetresPerSecToUnitsPerTic(
			RS_Reach.Num("rs_dgrab_speed", p, 15.0));
		if (upt < 0.1) upt = 0.1;
		double lo = RS_Reach.Num("rs_dgrab_time_min", p, 6.0);
		double hi = RS_Reach.Num("rs_dgrab_time_max", p, 70.0);
		if (lo < 1) lo = 1;
		if (hi < lo) hi = lo;
		double tics = clamp(dist / upt, lo, hi);

		lockActor[hand] = null;
		flyActor[hand] = a;
		flyTic[hand]   = 0;
		flyTotal[hand] = int(tics);
		flyStart[hand] = mid0;
		flyDist[hand]  = dist;

		flySavedSpecial[hand]    = a.bSPECIAL;
		flySavedNoGrav[hand]     = a.bNOGRAVITY;
		flySavedThruActors[hand] = a.bTHRUACTORS;

		// SPECIAL IS LEFT ALONE, and that is the whole design in one line.
		//
		// Holding an object clears it, because an item inside your own collision
		// cylinder would be collected every tic. Flight is the opposite case: an
		// object crossing the room at you SHOULD resolve if it reaches you.
		// Missing a catch is not a dropped ball -- it is the medikit hitting you
		// and healing you, the ammo box hitting you and giving you ammo, the
		// barrel hitting you and hurting. There is no outcome where you flicked
		// something and nothing happened.
		//
		// NOGRAVITY still goes on: the arc is authored, and gravity fighting it
		// mid-flight would drag every pull into the floor.
		a.bNOGRAVITY = true;

		// AND THRUACTORS, FOR THE LAST FEW TICS OF THE ARC.
		//
		// The flight is driven with TryMove (see the note there), and the arc
		// homes to your PALM -- so every pull ends with the object crossing
		// inside your own collision cylinder. A +SOLID thing, a barrel above all,
		// is refused that move by PIT_CheckThing, and the blocked branch below
		// reads a refusal as "it hit geometry" and aborts the pull. The barrel
		// therefore dropped out of the air roughly an arm's length short, every
		// single time, and the catch window never opened at all.
		//
		// The same flag and the same reasoning as RS_Held.SaveFlags, which is the
		// point: an object handed from flight to a hand must not change what it
		// is on the way. Cleared again one line before the handover in Catch, so
		// what RS_Held records as the object's true state is the object's true
		// state, and put back by Abort and Impact on every path that does not end
		// in a hand.
		a.bTHRUACTORS = true;
		a.Vel = (0, 0, 0);
		return true;
	}

	// TAKE IT OUT OF THE AIR.
	//
	// Hands the object over to the held-state machine mid-flight and stops
	// driving it. Returns false when it could not be taken, so the caller can
	// leave the object flying rather than dropping it on a refusal.
	//
	// The real flags go back BEFORE the handover, every time -- RS_Held.Take
	// saves what it finds, and what it would find otherwise is the state flight
	// imposed. An object released later would be weightless forever.
	bool Catch(int hand, PlayerPawn pmo, PlayerInfo p)
	{
		if (hand != 0 && hand != 1) return false;
		Actor a = flyActor[hand];
		if (!a) return false;

		let held = RS_Held.Get();
		let pol  = RS_GrabPolicy.Get();
		let rule = pol ? pol.Decide(a, pmo, p) : null;
		if (!held || !rule) return false;

		a.bSPECIAL    = flySavedSpecial[hand];
		a.bNOGRAVITY  = flySavedNoGrav[hand];
		a.bTHRUACTORS = flySavedThruActors[hand];

		// Consumed on the way in -- a weapon that equipped, or a third copy that
		// became ammo. There is nothing left to hold.
		if (pol.OnTake(hand, a, rule, pmo, p))
		{
			flyActor[hand] = null;
			return true;
		}

		int res = held.Take(hand, a, rule.subject, rule.pose, rule.twohand, p);
		if (res == RS_Held.TAKE_REFUSED)
		{
			// Put flight's own flags back and keep flying. A refused catch must
			// not leave the object half-owned by nobody -- and that includes
			// THRUACTORS, or the rest of the arc runs into you and aborts.
			a.bNOGRAVITY  = true;
			a.bTHRUACTORS = true;
			return false;
		}

		flyActor[hand] = null;
		if (RS_Reach.Flag("rs_hold_debug", p, true))
			Console.Printf("[RSPULL] hand %d CAUGHT %s (%s)", hand, a.GetClassName(), rule.why);
		return true;
	}

	// Which flying object, if any, is inside this hand's reach volume right now.
	// This is what makes catching a matter of TIMING rather than a button that
	// always works: the object homes to your palm, so it is only catchable once
	// it has nearly got there.
	Actor CatchableBy(int hand, PlayerPawn pmo, PlayerInfo p)
	{
		if (hand != 0 && hand != 1) return null;
		Actor a = flyActor[hand];
		if (!a) return null;
		// ScoreAt with the centre we already have. Score would derive it a second
		// time, and deriving it walks the thinker list for the hand actor -- twice
		// per hand per tic for one number that cannot have changed in between.
		Vector3 c = RS_Reach.Centre(pmo, p, hand);
		return (RS_Reach.ScoreAt(pmo, p, hand, RS_Reach.ClosestOn(a, c), c) <= 1.0) ? a : null;
	}

	// Put the object back the way it was found and forget it. Not a drop and not
	// a catch -- this is the path for a pull that cannot finish.
	private void Abort(int hand)
	{
		Actor a = flyActor[hand];
		if (a)
		{
			a.bSPECIAL    = flySavedSpecial[hand];
			a.bNOGRAVITY  = flySavedNoGrav[hand];
			a.bTHRUACTORS = flySavedThruActors[hand];
			a.Vel = (0, 0, 0);
		}
		flyActor[hand] = null;
	}

	void AbortAll()
	{
		Abort(0);
		Abort(1);
		Unlock(0);
		Unlock(1);
	}

	override void WorldTick()
	{
		let p = players[consoleplayer];
		if (!p || !p.mo) return;
		let pmo = p.mo;

		if (pmo.Health <= 0 || !RS_Reach.Flag("rs_dgrab", p, true))
		{
			AbortAll();
			Unlock(0); Unlock(1);
			return;
		}

		ValidateLock(0, pmo, p);
		ValidateLock(1, pmo, p);

		let held = RS_Held.Get();

		for (int h = 0; h < 2; h++)
		{
			Actor a = flyActor[h];
			// An actor pointer nulls itself when the actor dies, so a target
			// crushed or consumed mid-flight clears its own slot. The saved
			// flags do not, and a stale pair of those is what the NEXT pull
			// would hand to RS_Held.
			if (!a) { if (flyTic[h] != 0) { flyTic[h] = 0; } continue; }

			flyTic[h]++;
			double t = double(flyTic[h]) / double(flyTotal[h]);
			if (t > 1.0) t = 1.0;

			// LINEAR, because a thrown object has constant horizontal speed.
			//
			// This was a cubic ease-out and it was wrong twice over. A parabola
			// does not decelerate horizontally -- only gravity acts on it, and
			// gravity is vertical. And the numbers were brutal: over a 12-tic
			// flight from 512 units it covered 23% of the distance in the FIRST
			// TIC, which is 121 m/s.
			//
			// Worse, it destroyed the arc. The lift peaked at t=0.5, by which
			// point the ease-out had already carried the object 88% of the way
			// there -- so the whole hump happened inside the last 13% of the
			// distance. It was not an arc, it was a straight line with a hook on
			// the end.
			// ACCELERATES. Starts slow, picks up speed -- the thing is being
			// PULLED, and a pull that begins at full speed reads as a teleport
			// with a delay rather than as something taking hold of an object.
			//
			// t^2 by default. The old curve was the exact opposite -- a cubic
			// ease-OUT, fastest at the instant of launch, which is where the
			// 121 m/s first tic came from.
			double acc = RS_Reach.Num("rs_dgrab_accel", p, 1.6);
			if (acc < 0.25) acc = 0.25;
			double e = t ** acc;

			// HOMES TO WHERE YOUR HAND IS NOW, re-read every tic, not to where
			// it was when you squeezed. Over a third of a second your hand has
			// moved, and an object flying to a stale point arrives beside it.
			Vector3 palm = RS_Reach.Centre(pmo, p, h);

			Vector3 pos = flyStart[h] + (palm - flyStart[h]) * e;

			// The lift, applied on top of the straight line. Zero at both ends
			// and highest in the middle -- sin over 0..180 does that with no
			// special-casing at either end. It is what makes the object come UP
			// to you over the floor between rather than dragging through it.
			// THE PARABOLA. 4h*t*(1-t) is the canonical one: zero at both ends,
			// peak of exactly h at the midpoint, quadratic in between -- the
			// shape gravity actually makes. sin(180t) was a sine hump: close
			// enough to look right written down, not the same curve.
			//
			// Height is a FRACTION OF THE LAUNCH DISTANCE, so the arc keeps its
			// shape at every range rather than a long pull reading flat and a
			// short one reading as a lob. That is what makes near and far feel
			// like the same gesture.
			// KEYED ON e, NOT t, and that is the difference between an arc and a
			// swoop. e is how far along the PATH it is; t is how far through the
			// clock. Key the height on time while the travel accelerates and the
			// peak lands a quarter of the way along in space -- the object
			// leaps up beside itself and then falls the whole way to you.
			//
			// On e, the shape in SPACE is a clean symmetric parabola whatever
			// the speed curve is doing, and the acceleration is free to be
			// whatever feels right without bending the arc out of shape.
			double arcH = flyDist[h] * RS_Reach.Num("rs_dgrab_arc", p, 0.15);
			pos.z += 4.0 * arcH * e * (1.0 - e);

			// TRYMOVE, NOT SETORIGIN. The object is a real thing crossing the
			// room: it clips doorframes, and it can reach your body. SetOrigin
			// is a write, not a move -- it tests nothing, so the old flight
			// passed through walls and through you, and arrival was
			// unconditional. Nothing could ever be missed.
			//
			// Z first, then XY, for the same reason CarryOne does it: TryMove
			// tests at the actor's CURRENT height.
			a.SetZ(pos.z - a.Height * 0.5);
			bool moved = a.TryMove((pos.x, pos.y), 1);
			a.Vel = (0, 0, 0);

			// BLOCKED. It hit geometry on the way over, so it stops there and
			// falls. That is a miss, and a miss is what makes catching mean
			// anything.
			if (!moved)
			{
				if (RS_Reach.Flag("rs_hold_debug", p, true))
					Console.Printf("[RSPULL] hand %d lost %s -- blocked in flight",
						h, a.GetClassName());
				Abort(h);
				continue;
			}

			if (t < 1.0) continue;

			// THE ARC RAN OUT AND YOU DID NOT CLOSE YOUR HAND. It hits you.
			//
			// This used to test the object against your BODY every tic and
			// resolve there -- which could not work, and made catching
			// impossible rather than merely hard. Your radius plus a medikit's
			// is 36 map units, over a metre, and the object is flying to your
			// PALM, which is always well inside that. The impact fired before
			// the thing ever reached your hand: the catch window closed before
			// it opened.
			//
			// It resolves at the END of the arc instead, which is also the only
			// place it means anything -- the whole point is that missing the
			// catch is not a dropped ball, it is the medikit healing you, the
			// ammo box arming you, the barrel hurting.
			//
			// Explicit, not left to Doom's touch check: an item moving into a
			// STATIONARY player never fires P_TouchSpecialThing, because that
			// runs when the PLAYER moves into a special and not the reverse. A
			// perfect pull at someone standing still would pass through them
			// and wait forever.
			Impact(a, pmo, p, h);
		}
	}

	// IT HIT YOU. Resolve it as whatever it is.
	private void Impact(Actor a, PlayerPawn pmo, PlayerInfo p, int h)
	{
		flyActor[h] = null;
		a.bSPECIAL    = flySavedSpecial[h];
		a.bNOGRAVITY  = flySavedNoGrav[h];
		// Put back BEFORE the resolve below. Impact is where a missed pull
		// becomes a pickup or a hit, and both of those are ordinary Doom
		// interactions that have to happen to an ordinary Doom actor.
		a.bTHRUACTORS = flySavedThruActors[h];
		a.Vel = (0, 0, 0);

		bool dbg = RS_Reach.Flag("rs_hold_debug", p, true);

		// A pickup resolves as a pickup -- the ordinary Doom path, so a medikit
		// heals exactly as much as walking over it would and a mod's custom
		// pickup behaviour runs untouched.
		let inv = Inventory(a);
		if (inv && !inv.Owner)
		{
			bool took = inv.CallTryPickup(pmo);
			if (dbg) Console.Printf("[RSPULL] %s hit you -- %s",
				a.GetClassName(), took ? "picked up" : "refused");
			return;
		}

		// Anything else is a lump of matter arriving at speed. Damage rather
		// than an explosion: a barrel that detonates on contact makes every
		// missed pull a near-death, and you can still shoot one out of the air
		// if that is what you wanted.
		int dmg = int(RS_Reach.Num("rs_dgrab_impact", p, 5.0));
		if (dmg > 0)
			pmo.DamageMobj(a, null, dmg, 'Crush', DMG_THRUSTLESS);
		if (dbg) Console.Printf("[RSPULL] %s hit you -- %d damage", a.GetClassName(), dmg);
	}

	override void WorldLoaded(WorldEvent e) { AbortAll(); }
	override void WorldUnloaded(WorldEvent e) { AbortAll(); }
}
