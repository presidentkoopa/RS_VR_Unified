// WHERE A PART OF THE WEAPON IS, IN THE ROOM.
//
// This is the entire reason RS_Reload exists as a separate thing from the six
// abandoned attempts before it, so it is worth being blunt about what it
// replaces.
//
// Rusted Legacy asked the same question -- "is the off hand on the magwell" --
// and answered it with LineAttack: fire a trace from the PLAYER'S EYE along
// head yaw/pitch, some hand-tuned distance, harvest the puff's position, call
// that the magwell. Seventy of those, three magic numbers each. It fails three
// ways at once and all three are unfixable inside the technique:
//
//   * the trace starts at your FACE, so the "gun" it describes only coincides
//     with the drawn gun when your hand happens to be in the canonical pose;
//   * the pitch is `AimTarget() ? BulletSlope() : pitch`, so AUTOAIM moves it --
//     the magwell physically jumps when a monster walks under your crosshair;
//   * a trace STOPS AT GEOMETRY, so reloading with your back to a wall collapses
//     a 16-unit anchor to 2 and every distance check goes wrong together.
//
// The weapon is held in your HAND. Its position and orientation are published
// every tic as AttackPos + AttackAngle/AttackPitch/MainHandRoll. A point on the
// gun is that, plus a constant offset, rotated. That is all it ever was:
//
//     world = AttackPos + Fwd*(grip + x*len) + Side*(y*len) + Up*(z*len)
//
// No trace, no autoaim, no wall, no world actor, no bone. The offsets are
// authored per FEED FAMILY in normalised gun-lengths, and scaled by ARCHETYPE,
// so one number pair sizes every pistol in every mod at once.
//
// MainHandRoll and not AttackRoll: AttackRoll is zeroed by the playsim every tic
// because the usercmd has no weaponroll to rebuild it from, which left script
// believing the wrist was level while the model rolled with it. actor.zs says
// outright that MainHandRoll is the one for anything welded to the weapon.

class RR_Point play
{
	// The hand yaw convention is RS_Hands' -- AttackAngle + 90 -- and it has to
	// be, or this basis sits ninety degrees off the one rs_grab.zs draws and
	// tests with. Two packages disagreeing about which way is forward is exactly
	// the class of bug where everything reads correct at rest and goes wrong the
	// moment you turn.
	static double Yaw(PlayerPawn pmo, int hand)
	{
		return ((hand == 0) ? pmo.AttackAngle : pmo.OffhandAngle) + 90;
	}
	// NEGATED, fixed 2026-08-26. This returned AttackPitch/OffhandPitch RAW
	// while RS_Reach.HandPitch (RS_Hands, rs_grab.zs:73-76) negates -- and both
	// feed the SAME RS_Basis. The engine stores these pitches negated; stock
	// ZScript negates on read too (weaponmace.zs, `directionPitch =
	// -player.mo.AttackPitch`), which is the precedent RS_Hands cites.
	//
	// Yaw() directly above already documents that it matches RS_Hands' +90
	// convention deliberately, and why: "two packages disagreeing about which
	// way is forward is exactly the class of bug where everything reads correct
	// at rest and goes wrong the moment you turn." The same argument applies
	// here and this function was simply missed.
	//
	// EFFECT: the magwell point was mirrored vertically whenever the gun was
	// pitched -- level shots looked right, which is why it survived. Expect the
	// reload target point to MOVE for any non-level gun; that movement is the
	// fix, not a regression. Verify in headset with the gun pitched steeply up
	// and down before trusting the tuned per-archetype numbers.
	static double Pit(PlayerPawn pmo, int hand)
	{
		return -((hand == 0) ? pmo.AttackPitch : pmo.OffhandPitch);
	}
	static double Rol(PlayerPawn pmo, int hand)
	{
		return (hand == 0) ? pmo.MainHandRoll : pmo.OffhandRoll;
	}
	static Vector3 HandPos(PlayerPawn pmo, int hand)
	{
		return (hand == 0) ? pmo.AttackPos : pmo.OffhandPos;
	}

	// A point on the weapon, in world space.
	//
	// `local` is normalised: 1.0 on any axis is one GUN LENGTH from the firing
	// grip. That is what lets the same magwell offset serve a pistol and a rifle
	// -- the shape of a gun does not change with its size, only the scale does.
	//
	// `len` and `grip` come from the archetype (rr_feed.zs), never from the
	// weapon. Thirteen pairs cover every gun that will ever load; two sliders per
	// weapon covers the twelve you measured and nothing else.
	// gunHand: 0 main, 1 off. NOT ASSUMED.
	//
	// This used to hardcode the main hand as the one holding the weapon and the
	// off hand as the one reaching. That is wrong half the time here: a gun in
	// EVERY hand is the baseline, so reloading the off-hand weapon means the
	// MAIN hand does the reaching and every axis flips. RS_Holsters' pouch
	// reached the same conclusion independently and claims for both hands.
	static Vector3 World(PlayerPawn pmo, Vector3 local, double len, double grip, int gunHand)
	{
		double y = Yaw(pmo, gunHand), p = Pit(pmo, gunHand), r = Rol(pmo, gunHand);
		return HandPos(pmo, gunHand)
			+ RS_Basis.Fwd (y, p, r) * (grip + local.x * len)
			+ RS_Basis.Side(y, p, r) * (local.y * len)
			+ RS_Basis.Up  (y, p, r) * (local.z * len);
	}

	// IS THE OFF HAND ON IT. <= 1 is inside, smaller is more central.
	//
	// An ellipsoid, and measured in the WEAPON'S axes rather than the hand's.
	// rs_grab.zs already has an ellipsoid test and this deliberately does not
	// call it: that one is sized and oriented for grabbing world objects out of
	// your palm, and reusing it would weld reload tolerance to grab tolerance.
	// They are different gestures with different failure complaints, and the
	// first time you widened one to fix the other you would break both.
	//
	// Weapon axes matter: a magwell is a tall thin target along the magazine's
	// travel and a wide one across it. A sphere generous enough to catch the
	// former also catches your own trigger hand.
	// reachHand is the hand that is NOT holding this weapon.
	static double Score(PlayerPawn pmo, Vector3 world, Vector3 radii, int gunHand, int reachHand)
	{
		double rx = radii.x, ry = radii.y, rz = radii.z;
		if (rx < 0.05) rx = 0.05;
		if (ry < 0.05) ry = 0.05;
		if (rz < 0.05) rz = 0.05;

		double y = Yaw(pmo, gunHand), p = Pit(pmo, gunHand), r = Rol(pmo, gunHand);
		Vector3 d = HandPos(pmo, reachHand) - world;

		double fx = (d dot RS_Basis.Fwd (y, p, r)) / rx;
		double fy = (d dot RS_Basis.Side(y, p, r)) / ry;
		double fz = (d dot RS_Basis.Up  (y, p, r)) / rz;
		return fx*fx + fy*fy + fz*fz;
	}

	// TRAVEL WAS HERE AND IS GONE (2026-08-26). It measured how far the reaching
	// hand had moved along a weapon axis, signed, in map units -- the whole of
	// the travel-driven beat, for a beat runner that no longer exists. What got
	// built instead is one carry to one point (rr_sequence.zs), so it had zero
	// call sites and it went with RR_BeatDef and RR_BeatMode.
	//
	// KEEP THE LESSON IT WAS BUILT FOR, because it outlives the function.
	// Rusted Legacy completed a step the instant a distance check passed, which
	// is why a hand resting on the boundary retriggered it over and over. A rack
	// is not a place you touch, it is a distance you PULL, and the difference is
	// the difference between the gesture reading as performed and as tripped. If
	// a racking beat ever comes back it wants a travel measure and not a
	// proximity test; the `guard` debounce in rr_sequence.zs is the same worry
	// in the shape the current design needed.

	// The dev marker.
	//
	// A PARTICLE and not an actor on purpose. rs_grabviz's gauges are actors that
	// have to be parked on the player's own position every tic or the engine
	// culls them on a location they are not being drawn at -- correct for a gauge
	// that rides a controller through a MODELDEF Follow flag, and pure overhead
	// for a point that is somewhere else entirely. A particle needs no lifecycle,
	// no culling exemption and no art.
	//
	// Offsets are NOT flagged SPF_RELATIVE, so they are world-axis deltas rather
	// than being rotated by the player's facing -- which is what we want, having
	// already done the rotation ourselves.
	static void Mark(PlayerPawn pmo, Vector3 world, color c, double size = 4.0)
	{
		Vector3 d = level.Vec3Diff(pmo.Pos, world);
		pmo.A_SpawnParticle(c, 0, 2, size, 0, d.x, d.y, d.z);
	}
}
