// ---------------------------------------------------------------------------
// Headshot feedback — the marker and the confirm.
//
// This is the presentation half only. Nothing in here decides what a headshot
// *is*; it is handed a victim and a world-space impact point and it sells the
// hit. Detection lands later, against real anatomy volumes, and calls
// HS_Marker.Confirm() when it resolves a head.
//
// The marker sprite (HSHT, 19 frames) and the mini-crit samples are lifted from
// mk-crits. Two things changed on the way over:
//
//   1. The sound plays off the marker at the impact point, not off the player.
//      In VR a confirm that fires inside your own skull tells you nothing about
//      where the shot went; one that arrives from the thing you shot does.
//   2. Roll and flip are randomised per spawn as before, but the marker is
//      spawned at the true impact point rather than at a puff's position.
// ---------------------------------------------------------------------------

class HS_Marker : Actor
{
	// The engine resolves handedness itself (vr_control_scheme), so this is the
	// weapon hand whichever way round the player is holding things.
	const HS_HAND_MAIN = 0;
	const HS_HAND_OFF  = 1;

	// Entry point for the detection layer. `hitPos` is world space and should be
	// the point on the head that was actually struck, not the victim's origin —
	// the marker is the only readout of *where* you hit, so putting it at the
	// actor centre throws away the information it exists to show.
	static void Confirm(Actor victim, Vector3 hitPos, Actor shooter)
	{
		if (!victim)
			return;

		let mark = Actor.Spawn("HS_Marker", hitPos, ALLOW_REPLACE);
		if (!mark)
			return;

		// Off the marker, so it is positional. $limit in SNDINFO stops a spread
		// weapon from stacking five copies of the same confirm.
		mark.A_StartSound("headshot/mini", CHAN_AUTO, CHANF_DEFAULT, 1.0, ATTN_NORM);

		// Only the local player gets buzzed, and only for their own shots.
		if (shooter && shooter.player && shooter.player == players[consoleplayer])
			victim.Level.VRHaptic(HS_HAND_MAIN, 0.55, 45);
	}

	default
	{
		RenderStyle "Add";
		+NOGRAVITY
		+NOBLOCKMAP
		+NOINTERACTION
		+ROLLSPRITE
		+ROLLCENTER
	}

	override void PostBeginPlay()
	{
		super.PostBeginPlay();

		bSPRITEFLIP = random(0, 1);
		roll = frandom(-45.0, 45.0);
		scale.x = scale.y = frandom(0.30, 0.40);
	}

	states
	{
	Spawn:
		HSHT ABCDEFGHIJKLM 1 Bright;
		HSHT NOPQRS 1 Bright A_FadeOut();
		stop;
	}
}
