// THROWING, AND THE DIFFERENCE BETWEEN A THROW AND A DROP.
//
// This is small because the hard part was built first. RS_Swing already keeps
// the peak of the last ~180ms of hand movement, already measures it relative to
// the player so walking is not a throw, and already discards a snap turn. All
// that is left is: read it at the moment of release, scale it, and write it to
// the actor's Vel.
//
// AND THEN DOOM DOES EVERYTHING ELSE. P_XYMovement and P_ZMovement give gravity,
// floors, ceilings, stairs, wall sliding, bouncing and impact -- for a thrown
// object those are not features to implement, they are what an actor with a
// velocity already does. That is the entire argument for 35Hz on the playsim in
// one sentence, and it is why the physics module was not worth its cost.
//
// THE PEAK, NOT THE LAST SAMPLE. By the time your fingers open, your arm is
// already slowing down. A throw built on the instantaneous speed at release
// comes out limp no matter how hard it felt, and no amount of scaling fixes it
// because the number being scaled is the deceleration.

// PLAY SCOPE, DECLARED -- the same trap RS_Reach fell into. A plain class's
// statics default to data, and data cannot call a play function, which is what
// RS_Swing.Get and RS_Reach.Flag both are.
class RS_Throw play
{
	// Below this it is a DROP, and that distinction matters more than the
	// number. A release at rest that inherits a peak from a fifth of a second
	// ago is an object leaping out of your hand for no reason -- most obviously
	// when you let go of something right after catching it, where the catch's
	// own motion is still sitting in the window.
	//
	// Under the threshold the object leaves at the hand's CURRENT speed rather
	// than at zero: setting it down while walking should not make it hang in the
	// air behind you.
	static Vector3 VelocityFor(int hand, PlayerPawn pmo, PlayerInfo p)
	{
		let sw = RS_Swing.Get();
		if (!sw || !RS_Reach.Flag("rs_throw", p, true)) return (0, 0, 0);

		Vector3 peak = sw.PeakVelocity(hand);
		double need = RS_Swing.MetresPerSecToUnitsPerTic(
			RS_Reach.Num("rs_throw_min", p, 1.2));

		Vector3 v = (peak.Length() >= need) ? peak : sw.LastVelocity(hand);

		// The hand's motion is measured relative to the player, so a thrown
		// object would be launched relative to the player too -- throw a barrel
		// while sprinting forward and it would fall short by exactly your own
		// speed. The pawn's velocity goes back in here, once, at the only place
		// it is wanted.
		return v * RS_Reach.Num("rs_throw_scale", p, 1.0) + pmo.Vel;
	}

	// NO TUMBLE, and that is deliberate rather than forgotten.
	//
	// A Doom actor does not roll on its own -- nothing advances its angle unless
	// something writes one every tic. A single angle change at the moment of
	// release is not a tumble, it is the object facing a different way for the
	// whole flight, which looks worse than not trying. Real tumbling means
	// tracking every thrown object for as long as it is in the air, which is a
	// system, not a line, and it belongs with whatever eventually wants
	// orientation on held objects too.
}
