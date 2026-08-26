// A hardpoint-testable flashlight -- an ordinary Weapon, so it drops
// straight into RS_HardPoints' existing store/draw pipeline with ZERO
// changes to that system. Built to answer "what does a utility item need
// to fit a hardpoint": the answer is just "be a real Weapon with a Ready
// state," same as every other holsterable item already is.
//
// Model, skin, sprite and click sounds are copied (not referenced) from
// GlowInTheDark's GITD_Flashlight (E:\GlowInTheDark\zscript\Flashlight.zs)
// -- sounds credited there to mshahen, CC BY 3.0. Copied rather than loaded
// alongside on purpose: this class does not reference GITD_* anything, so
// it works with or without GlowInTheDark loaded, the same "any weapon pack,
// no specific dependency" independence as the rest of this mod.
//
// Unlike GITD_Flashlight (an always-on Thinker singleton with its own
// fl_mount cvar picking one of 4 fixed mounts), this is an ordinary
// inventory item with no separate mount system at all: the beam runs
// whenever THIS instance is actually being held in either hand, and stops
// the instant it is not -- holstered, dropped, or never picked up.
// DoEffect() runs every tic for any inventory item regardless of held
// state, so it is the one hook that can tell "holstered" from "held"
// without a Thinker of its own.
//
// The hand-pose read is GITD_Flashlight's ResolveMount, ported as-is, NOT
// re-derived: AttackAngle/OffhandAngle are stored as world yaw MINUS 90,
// and AttackPitch/OffhandPitch are stored NEGATED -- documented in
// Flashlight.zs against actual engine source (g_game.cpp:1237,
// hw_vrmodes.cpp:1170/1192). Getting this wrong is the exact bug
// Flashlight.zs's own header spends a page describing; this applies the
// same correction on the way in rather than repeating that debugging
// session blind. Also relevant to RS_Holsters.zs's own wrist hardpoints,
// which read OffhandPitch WITHOUT this correction -- see handBasisPose
// there and CLAUDE.md's note on it. Not touched here; that is a position-
// anchor question, this is a beam-aim one, and they should be tested and
// fixed independently.
class RS_HolsterFlashlight : Weapon
{
	Default
	{
		Weapon.SlotNumber 7;
		Weapon.SelectionOrder 4000;
		Weapon.AmmoUse 0;
		Weapon.AmmoGive 0;
		Weapon.Kickback 0;
		+WEAPON.NOALERT
		+WEAPON.AMMO_OPTIONAL
		+WEAPON.NOAUTOSWITCHTO
		Tag "Hardpoint Flashlight";
		Inventory.PickupMessage "You found a hardpoint flashlight.";
		+NOGRAVITY
		+FLOATBOB
	}

	// The surface lighting and its dim fill light. Spawned/destroyed as this
	// instance moves in and out of a hand, not parked for the item's whole
	// lifetime -- a holstered copy has no business lighting anything.
	Actor beamLight;
	Actor bounceLight;

	// Settle()'s smoothed state -- see GITD_Flashlight's own comment on why
	// this exists at all: a snapped beam reads as glued to the camera
	// rather than carried in a hand, and it is worse in VR specifically,
	// where head and hand move independently.
	private Vector3 smPos, smDir;
	private bool smPrimed;

	// Throttle for the debug print in DoEffect() below -- every tic would
	// be unreadable console spam.
	private int debugTic;

	States
	{
	Spawn:
		FLSH A -1;
		Stop;
	Ready:
		FLSH A 1 A_WeaponReady;
		Loop;
	Select:
		FLSH A 0 A_StartSound("rs_holster_flashlight_on", CHAN_WEAPON);
		FLSH A 1 A_Raise;
		Loop;
	Deselect:
		FLSH A 0 A_StartSound("rs_holster_flashlight_off", CHAN_WEAPON);
		FLSH A 1 A_Lower;
		Loop;
	Fire:
		FLSH A 1;
		Goto Ready;
	}

	override void DoEffect()
	{
		Super.DoEffect();

		let pmo = PlayerPawn(Owner);
		bool held = pmo && pmo.player
			&& (pmo.player.ReadyWeapon == self || pmo.player.OffhandWeapon == self);

		if (!held)
		{
			level.ClearVolumetricBeam();
			if (beamLight)   { beamLight.Destroy();   beamLight = null; }
			if (bounceLight) { bounceLight.Destroy(); bounceLight = null; }
			smPrimed = false;
			return;
		}

		bool offhand = (pmo.player.OffhandWeapon == self);
		Vector3 pos, dir;
		[pos, dir] = ResolveMount(pmo, offhand);

		// Raw input plus the corrected/resolved direction, throttled to
		// ~3.5/sec -- read against an actual physical tilt, same reasoning
		// as the wrist-pitch dump in RS_Holsters.zs.
		//
		// GATED BEHIND rs_holster_verbose AS OF 2026-08-26. This ran in the
		// default build with no switch at all: hold the flashlight and it
		// printed roughly three and a half lines a second into the player's
		// console, forever. GATED, NOT DELETED -- the question it answers is
		// still open (see this file's own header on OffhandPitch being stored
		// negated, and whether RS_Holsters' hand-anchored basis has the same
		// bug), and re-deriving that from scratch later would cost far more
		// than a cvar read costs now.
		//
		// debugTic still advances on the OUTSIDE of the gate on purpose, so
		// switching the cvar on mid-session lands on the same 10-tic cadence
		// it always had rather than restarting the counter and printing
		// immediately.
		int tick = debugTic++;
		let dbgCv = CVar.GetCVar("rs_holster_verbose", pmo.player);
		bool wantDbg = (dbgCv != null) && dbgCv.GetBool();
		if (wantDbg && (tick % 10) == 0)
		{
			double rawPit = offhand ? pmo.OffhandPitch : pmo.AttackPitch;
			double rawAng = offhand ? pmo.OffhandAngle : pmo.AttackAngle;
			double rawRol = offhand ? pmo.OffhandRoll : pmo.AttackRoll;
			Console.Printf("RS_HP_FLASHLIGHT %s hand: raw pitch=%.1f angle=%.1f roll=%.1f -> dir %.2f,%.2f,%.2f",
				offhand ? "OFF" : "MAIN", rawPit, rawAng, rawRol, dir.X, dir.Y, dir.Z);
		}

		[pos, dir] = Settle(pos, dir);

		// Fixed warm white -- GITD_Flashlight's colour-cycling palette
		// (fl_slots/fl_pattern/fl_random) is that mod's own configuration
		// layer and is not ported here; this is a hardpoint test fixture,
		// not a reimplementation of GlowInTheDark.
		Color col = Color(255, 255, 244, 214);
		double range = 512.0;
		double inner = 6.0;
		double outer = 22.0;

		level.SetVolumetricBeam(pos, dir, col, inner, outer, range, 0.6, 1.0, 0.35, 0.04, 0.0);

		if (!beamLight)
			beamLight = Actor.Spawn("RS_HolsterFlashlightSpot", pos);
		if (beamLight)
		{
			beamLight.SetOrigin(pos, true);
			beamLight.angle = atan2(dir.y, dir.x);
			beamLight.pitch = -asin(clamp(dir.z, -1.0, 1.0));
			beamLight.args[0] = col.r;
			beamLight.args[1] = col.g;
			beamLight.args[2] = col.b;
			beamLight.args[3] = int(range);
			let sl = SpotLight(beamLight);
			if (sl)
			{
				sl.SpotInnerAngle = inner;
				sl.SpotOuterAngle = outer;
			}
		}

		// Bounce: a wide, dim, short-range fill at the lens, same reasoning
		// as GITD_Flashlight's own -- a bare cone in a black room reads as
		// harsh and floating without a little light going back into the
		// space around it.
		if (!bounceLight)
			bounceLight = Actor.Spawn("RS_HolsterFlashlightBounce", pos);
		if (bounceLight)
		{
			bounceLight.SetOrigin(pos, true);
			bounceLight.args[0] = int(col.r * 0.35);
			bounceLight.args[1] = int(col.g * 0.35);
			bounceLight.args[2] = int(col.b * 0.35);
			bounceLight.args[3] = int(range * 0.18);
		}
	}

	// Where the light sits and which way it faces, for whichever hand is
	// actually holding this instance. Direct port of GITD_Flashlight's
	// ResolveMount (mainhand/offhand branches only -- the head/chest mounts
	// do not apply to a weapon that is, by definition, in a hand).
	private Vector3, Vector3 ResolveMount(PlayerPawn pmo, bool offhand)
	{
		double ang, pit, rol;
		Vector3 pos;

		if (offhand)
		{
			pos = pmo.OffhandPos;
			ang = pmo.OffhandAngle + 90;
			pit = -pmo.OffhandPitch;
			rol = pmo.OffhandRoll;
		}
		else
		{
			pos = pmo.AttackPos;
			ang = pmo.AttackAngle + 90;
			pit = -pmo.AttackPitch;
			rol = pmo.AttackRoll;
		}

		// Rolled past upside-down: follow the intent (pointed back over the
		// shoulder) rather than the raw geometry. Same flip GITD_Flashlight
		// applies under fl_allowflip, fixed on here since there is no cvar
		// layer ported for this test fixture.
		if (abs(rol) > 120)
		{
			ang -= 180;
			pit *= -1;
		}

		double cp = cos(pit);
		Vector3 dir = (cos(ang) * cp, sin(ang) * cp, -sin(pit));
		return pos, dir;
	}

	// Direct port of GITD_Flashlight.Settle, fixed lag (0.55, GITD's own
	// default) rather than a cvar. The origin (your hand) barely moves
	// relative to you; the far end sweeps metres for the same wrist turn,
	// which is where the sense of weight actually lives -- see
	// GITD_Flashlight's own comment for the full reasoning.
	private Vector3, Vector3 Settle(Vector3 pos, Vector3 dir)
	{
		double lag = 0.55;

		if (!smPrimed || (pos - smPos).Length() > 192.0)
		{
			smPos = pos; smDir = dir; smPrimed = true;
			return pos, dir;
		}

		double aPos = 1.0 - (lag * 0.35);
		double aDir = 1.0 - lag;

		smPos += (pos - smPos) * aPos;
		smDir += (dir - smDir) * aDir;

		double len = smDir.Length();
		if (len < 0.0001) { smDir = dir; }
		else smDir /= len;

		return smPos, smDir;
	}
}

// The surface light. DYNAMICLIGHT.ATTENUATE is not optional -- without it
// the shader skips the N.L term and every surface in the cone comes back
// the same brightness regardless of facing, which is the flat sourceless
// look of an ambient fill rather than a beam. GITD_FlashlightSpot's own
// comment documents this costing real debugging time; carried forward
// rather than risking the same miss twice.
class RS_HolsterFlashlightSpot : SpotLight
{
	Default
	{
		//$Title RS Hardpoint Flashlight beam light
		Args 255, 255, 244, 512;
		+DYNAMICLIGHT.ATTENUATE
	}
}

class RS_HolsterFlashlightBounce : PointLight
{
	Default
	{
		//$Title RS Hardpoint Flashlight bounce light
		Args 255, 255, 244, 96;
	}
}
