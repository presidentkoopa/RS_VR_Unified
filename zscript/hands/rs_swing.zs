// HOW FAST YOUR HANDS ARE MOVING, and how fast they were moving a moment ago.
//
// One foundation, four features. A flick that pulls something to you, a throw, a
// grenade and a melee swing are all the same measurement read at different
// moments -- so this measures, and says nothing about what any of it means.
//
// THE PEAK, NOT THE LAST SAMPLE. This is the whole reason the class exists
// rather than two lines wherever a speed is wanted. By the time you open your
// fingers to release something, your arm is already slowing down: the last
// sample is deceleration, and a throw built on it comes out limp no matter how
// hard you actually threw. The peak over the last fifth of a second is what your
// arm did, and it is what a thrown object should inherit.
//
// A ring buffer of PER-TIC DELTAS rather than of positions. Deltas are what
// every consumer wants, they are what "peak" is taken over, and keeping
// positions would mean every reader re-deriving the same subtraction and being
// free to get the window wrong in its own way.

class RS_Swing : EventHandler
{
	// ~180ms. The playsim runs at 35Hz, so a tic is 28.6ms and seven of them is
	// 200ms -- close enough, and an odd count means the window has a middle.
	const WINDOW = 7;

	// Flat and indexed hand*WINDOW + slot. ZScript has no two-dimensional fixed
	// array, and faking one with an array of objects would put an allocation in
	// front of a number that is read every tic.
	private Vector3 delta[14];
	private int  head[2];
	private int  filled[2];
	private Vector3 lastPalm[2];
	private bool primed[2];
	// Last tic's TOTAL accumulated turn, so the per-tic delta can be derived.
	private double lastTurn;
	private bool  turnPrimed;

	// HOW FAST THE WRIST IS TIPPING UP, same window and same shape as the
	// translation samples beside it.
	//
	// Added 2026-08-28 for a seated-comfort reason rather than a technical one.
	// The pull gesture was a TRANSLATION -- drag your whole hand back toward
	// your body -- which is a shoulder movement, and a shoulder movement is
	// exactly what someone in a chair with armrests cannot do repeatedly. A
	// wrist tip is the same intent expressed by the one joint that is still
	// free when your elbow is resting on something.
	//
	// SIGN: stored so POSITIVE MEANS TIPPING UP, which is the opposite of the
	// raw field. RS_Reach.HandPitch returns true-signed pitch, and RS_Basis.Fwd
	// builds its Z as -sin(pitch), so pointing up is pitch going NEGATIVE. The
	// per-tic sample is therefore (previous - current), and every consumer gets
	// to read "up is a bigger positive number" instead of re-deriving that.
	private double dPitchUp[14];
	private double lastPitch[2];
	private bool   pitchPrimed[2];

	static RS_Swing Get()
	{
		return RS_Swing(EventHandler.Find("RS_Swing"));
	}

	// MAP UNITS PER TIC is the unit everything here is in, because that is what
	// the samples natively are and converting on the way in would round twice.
	// 34 units is a metre and there are 35 tics in a second, so one unit per tic
	// is very nearly exactly one metre per second -- which makes the numbers
	// readable without a conversion in the middle of the measurement.
	static double UnitsPerTicToMetresPerSec(double u)
	{
		return u * 35.0 / 34.0;
	}
	static double MetresPerSecToUnitsPerTic(double m)
	{
		return m * 34.0 / 35.0;
	}

	// The fastest single tic in the window, as a VECTOR -- direction included,
	// because a throw needs to know which way and a flick needs to know whether
	// it came toward you. Zero length when there is nothing recorded yet.
	Vector3 PeakVelocity(int hand) const
	{
		if (hand != 0 && hand != 1) return (0, 0, 0);
		Vector3 best = (0, 0, 0);
		double bestLen = -1.0;
		int n = filled[hand];
		for (int i = 0; i < n; i++)
		{
			Vector3 d = delta[hand * WINDOW + i];
			double len = d.Length();
			if (len > bestLen) { bestLen = len; best = d; }
		}
		return best;
	}

	// Magnitude of the above, map units per tic.
	double PeakSpeed(int hand) const
	{
		return PeakVelocity(hand).Length();
	}

	// The fastest UPWARD wrist tip in the window, DEGREES PER TIC, positive.
	// Zero or negative means the wrist was level or tipping down across the
	// whole window -- callers test against a positive threshold, so a downward
	// flick can never satisfy an upward gesture by magnitude alone.
	//
	// The peak and not the last sample, for the identical reason PeakVelocity
	// exists: by the time the fingers open the wrist is already settling, so
	// the final sample is the recovery rather than the flick.
	double PeakPitchUp(int hand) const
	{
		if (hand != 0 && hand != 1) return 0.0;
		double best = 0.0;
		int n = filled[hand];
		for (int i = 0; i < n; i++)
		{
			double d = dPitchUp[hand * WINDOW + i];
			if (d > best) best = d;
		}
		return best;
	}

	// The most recent tic only. Deliberately available and deliberately NOT what
	// a release should use -- see the note at the top. It is here for things
	// that genuinely want "right now", like deciding whether a hand is currently
	// still.
	Vector3 LastVelocity(int hand) const
	{
		if (hand != 0 && hand != 1) return (0, 0, 0);
		if (filled[hand] <= 0) return (0, 0, 0);
		int last = head[hand] - 1;
		if (last < 0) last = WINDOW - 1;
		return delta[hand * WINDOW + last];
	}

	// Throw the history away. Called when the hand teleports rather than moves
	// -- a level change, a respawn -- because the delta across a teleport is an
	// enormous fictional velocity that would read as the throw of a lifetime.
	void Forget(int hand)
	{
		if (hand != 0 && hand != 1) return;

		// THE TURN BASELINE IS SHARED AND IS NO LONGER CLEARED HERE.
		//
		// It used to be, for a real reason: keeping a stale lastTurn across a
		// teleport means the next tic differences against a number from before
		// the reset, and across a savegame that is a whole session's turn in
		// one tic -- which rotates the previous palm sample into nonsense and
		// manufactures the fastest throw of your life.
		//
		// But lastTurn/turnPrimed are ONE pair shared by BOTH hands, while this
		// function is per-hand, so clearing them here punished the hand that was
		// not being forgotten. A successful flick calls Forget(hand) on itself
		// (rs_grab.zs), and that de-primed turn compensation globally: on the
		// very next tic the OTHER hand differenced an uncompensated sample and
		// read a phantom ~24 m/s. Since PeakVelocity holds the maximum for the
		// whole window, that fiction then survived a fifth of a second -- long
		// enough for that hand to hurl whatever it held across the map, or fire
		// a pull nobody asked for.
		//
		// The teleport case that wanted the clear is handled where it actually
		// belongs: ForgetAll, which is what WorldLoaded/WorldUnloaded call.
		head[hand] = 0;
		filled[hand] = 0;
		primed[hand] = false;
		pitchPrimed[hand] = false;
		for (int i = 0; i < WINDOW; i++)
		{
			delta[hand * WINDOW + i] = (0, 0, 0);
			dPitchUp[hand * WINDOW + i] = 0.0;
		}
	}

	void ForgetAll()
	{
		Forget(0);
		Forget(1);

		// HERE, not in Forget. This is the teleport path -- level change,
		// respawn, savegame -- and it is the only one where the shared turn
		// baseline is genuinely stale. Clearing it per-hand instead was what
		// let one hand's flick corrupt the other hand's velocity; see Forget.
		turnPrimed = false;
	}

	override void WorldTick()
	{
		let p = players[consoleplayer];
		if (!p || !p.mo) return;
		let pmo = p.mo;

		// TURNING IS NOT AN ARM MOVEMENT, AND VRTurnYaw IS NOT A DELTA.
		//
		// The samples below are player-RELATIVE, which removes walking but not
		// turning: rotate the player and both hands swing bodily around them
		// without a muscle moving.
		//
		// This used to read `if (VRTurnYaw != 0) ForgetAll()`, on the assumption
		// that the field carried this frame's turn. It does not. VRTurnYaw is
		// the engine's `snapTurn`, which ACCUMULATES -- `snapTurn += ...` for
		// analog turning and `snapTurn -= vr_snapTurn` for snap. It is your
		// total turn since the level began, so it is non-zero from the first
		// time you ever turn and never returns to zero.
		//
		// Which meant the buffer was wiped every single tic for the rest of the
		// session. PeakVelocity was permanently zero, and the flick and the
		// throw both silently stopped working with nothing to say why.
		//
		// So take the DELTA and compensate rather than discard. Rotating the
		// previous sample by how far the player turned puts it where it would
		// have been had they not, and the subtraction that follows measures pure
		// arm motion. Smooth turning is handled properly instead of throwing
		// away every frame it touches.
		double turn = pmo.VRTurnYaw;
		double dTurn = 0;
		if (turnPrimed) dTurn = turn - lastTurn;
		lastTurn = turn;
		turnPrimed = true;

		for (int h = 0; h < 2; h++)
		{
			Vector3 palm = RS_Reach.Centre(pmo, p, h);

			// MEASURED RELATIVE TO THE PLAYER, not in world space.
			//
			// Walking forward moves your hands forward at walking speed without
			// you having swung anything. In world space that reads as a constant
			// throw, and it would make every object you let go of while moving
			// fly off at running pace. Subtracting the pawn leaves what your ARM
			// did, which is the thing being asked about.
			palm -= pmo.Pos;

			if (!primed[h])
			{
				lastPalm[h] = palm;
				primed[h] = true;
				continue;
			}

			// Spin the previous sample forward by this tic's turn before
			// comparing, so what is left is what the arm did. Yaw only: turning
			// is about the vertical axis and nothing here rotates in Z.
			if (dTurn != 0)
			{
				double cs = cos(dTurn), sn = sin(dTurn);
				lastPalm[h] = (lastPalm[h].x * cs - lastPalm[h].y * sn,
				               lastPalm[h].x * sn + lastPalm[h].y * cs,
				               lastPalm[h].z);
				// The deltas already in the window were sampled in the old
				// orientation, and PeakVelocity hands the largest of them to
				// the throw -- a snap turn mid wind-up used to launch the
				// object off by the snap angle. Seven 2D rotations, turn tics
				// only.
				for (int i = 0; i < filled[h]; i++)
				{
					Vector3 dd = delta[h * WINDOW + i];
					delta[h * WINDOW + i] = (dd.x * cs - dd.y * sn,
					                         dd.x * sn + dd.y * cs,
					                         dd.z);
				}
			}

			Vector3 d = palm - lastPalm[h];
			lastPalm[h] = palm;

			// THE WRIST SAMPLE. Needs no turn compensation, unlike the
			// translation above: turning the player rotates both hands about the
			// VERTICAL axis, which changes their yaw and their position but
			// leaves pitch untouched. So this is already pure wrist motion.
			//
			// Negated on the way in so positive reads as tipping UP -- see the
			// note on dPitchUp for why the raw field runs the other way.
			double pit = RS_Reach.HandPitch(pmo, h);
			double up  = 0.0;
			if (pitchPrimed[h]) up = lastPitch[h] - pit;
			lastPitch[h]   = pit;
			pitchPrimed[h] = true;

			// Written at the SAME head index as the translation delta, and
			// before head advances, so sample i of one buffer is always the same
			// tic as sample i of the other. Two counters could drift apart; one
			// cannot.
			delta[h * WINDOW + head[h]] = d;
			dPitchUp[h * WINDOW + head[h]] = up;
			head[h] = (head[h] + 1) % WINDOW;
			if (filled[h] < WINDOW) filled[h]++;
		}
	}

	override void WorldLoaded(WorldEvent e) { ForgetAll(); }
	override void WorldUnloaded(WorldEvent e) { ForgetAll(); }
}
