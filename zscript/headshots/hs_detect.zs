// ---------------------------------------------------------------------------
// Headshot detection — interim.
//
// This is the cheap version, and it is deliberately temporary. It hangs off
// WorldThingDamaged and asks one question: was the thing that hit you inside
// the top slice of your own height? Good enough to make the marker fire today,
// wrong in all the ways a height band is wrong -- it has no idea which way the
// victim is facing, no idea where on the head it landed, and it treats a
// Mancubus and a Zombieman as the same shape.
//
// The real one resolves a segment (AActor::Prev -> Pos, the bullet's actual
// travel that tic) against per-class capsules, and it replaces this file
// wholesale. Confirm() is already the shape that wants, so nothing downstream
// changes when it lands.
//
// One bug from mk-crits is fixed here on the way past: the band is measured
// from the victim's own pos.z, not from floorz. Measuring from the floor puts
// a Cacodemon's "head" somewhere around its feet the moment it gains altitude.
// ---------------------------------------------------------------------------

class HS_Handler : EventHandler
{
	// Fraction of the victim's height counted as head, measured down from the top.
	const HEAD_FRAC = 0.2;

	// Things with no head, no neck, or a hitbox that makes the question
	// meaningless. A Cacodemon is entirely head; a Lost Soul is a flying skull.
	static const class<Actor> HS_NoHead[] =
	{
		"Demon",
		"Spectre",
		"LostSoul",
		"Cacodemon",
		"PainElemental",
		"Arachnotron",
		"SpiderMastermind"
	};

	// Weapons that make landing many headshots a matter of spray volume
	// rather than aim get the lower of the two damage multipliers
	// (hs_headshot_damage_mult_highrof) instead of the full one -- see the
	// damage bonus block in WorldThingDamaged, below. Hand-curated same as
	// HS_NoHead above: add a class name here for any other high-ROF weapon
	// this loads alongside.
	static const class<Weapon> HS_HighROF[] =
	{
		"Chaingun"
	};

	// Not static: a static const array declared in a class is not in scope from a
	// static function of that class, only from an instance method. The handler is
	// an object, so an instance method costs nothing here.
	bool HasHead(class<Actor> check)
	{
		for (uint i = 0; i < HS_NoHead.Size(); i++)
		{
			if (check is HS_NoHead[i])
				return false;
		}
		return true;
	}

	bool IsHighROF(class<Weapon> check)
	{
		if (!check)
			return false;

		for (uint i = 0; i < HS_HighROF.Size(); i++)
		{
			if (check is HS_HighROF[i])
				return true;
		}
		return false;
	}

	// Shared by the confirmed-hit path (WorldThingDamaged, below) and the
	// lined-up-before-firing path (WorldTick, below) -- one definition of
	// "that point is a head" for both, so the laser sight's live reaction
	// can never disagree with what actually confirms a moment later.
	bool IsHeadHit(Actor victim, Vector3 hitPos)
	{
		if (!victim || !victim.bISMONSTER || victim.health <= 0 || victim.player)
			return false;

		if (!HasHead(victim.GetClass()))
			return false;

		// Measured from the victim's own pos.z, not floorz -- see the file
		// header on why that matters the moment a Cacodemon gains altitude.
		double headBase = victim.pos.z + victim.height * (1.0 - HEAD_FRAC);
		double headTop  = victim.pos.z + victim.height;

		return hitPos.z >= headBase && hitPos.z <= headTop;
	}

	override void WorldThingDamaged(WorldEvent e)
	{
		// e.DamageType is Name-typed, and 'HS_HeadshotBonus' is what the bonus
		// hit below is tagged with -- this recognizes and skips the
		// WorldThingDamaged that OUR OWN follow-up damage call triggers,
		// instead of re-detecting a headshot on it.
		if (e.DamageType == 'HS_HeadshotBonus')
			return;

		let victim = e.Thing;
		let inflictor = e.Inflictor;
		let source = e.DamageSource;

		if (!victim || !inflictor || !source)
			return;

		if (!source.player)
			return;

		// The inflictor is the bullet (or puff) sitting at the impact point.
		if (!IsHeadHit(victim, inflictor.pos))
			return;

		HS_Marker.Confirm(victim, inflictor.pos, source);

		// ---- Damage bonus -----------------------------------------------
		// e.Damage is the damage that was ALREADY applied (WorldThingDamaged
		// fires after DamageMobj runs -- see p_interaction.cpp -- so the
		// original hit's number cannot be changed in place). Instead this
		// deals a SECOND, immediate hit for the difference between the
		// multiplier and 1.0, so total damage taken still ends up at
		// mult * original.
		//
		// DMG_THRUSTLESS: no extra knockback on top of the original hit's.
		// DMG_NO_PAIN: no second pain-state trigger -- the flinch already
		// happened on the original hit; a second one a tic later would
		// read as a stutter, not as "one bigger hit."
		if (victim.health <= 0)
			return; // already dead from the original hit; nothing to add

		bool highROF = IsHighROF(source.player.ReadyWeapon ? source.player.ReadyWeapon.GetClass() : null);
		let cv = CVar.GetCVar(highROF ? "hs_headshot_damage_mult_highrof" : "hs_headshot_damage_mult", null);
		double mult = cv ? cv.GetFloat() : 1.0;
		int bonus = int(round(e.Damage * (mult - 1.0)));

		if (bonus > 0)
		{
			victim.DamageMobj(inflictor, source, bonus, 'HS_HeadshotBonus', DMG_THRUSTLESS | DMG_NO_PAIN | DMG_PLAYERATTACK);
		}
	}

	// ---------------------------------------------------------------------
	// Live "you are about to land a headshot" reaction on the laser sight
	// itself, ahead of any actual shot. The engine's laser trace already
	// finds what the sight is resting on and where -- AActor.LaserTraceTarget*
	// and LaserTraceHitPos*, per hand, refreshed every render frame -- so this
	// reads THAT rather than casting a second ray, and it is the same reason
	// the confirmed-hit path above and this one share IsHeadHit(): the sight's
	// reaction and the eventual confirm must never disagree about what counts.
	//
	// Sets AActor.LaserHeadshotLinedUpMain/Off; the engine reads those back to
	// decide whether to tint the beam (vr_laser_headshot_react and friends).
	// This is a tic behind the render-frame trace, which is fine -- it is a
	// cosmetic reaction, not a hit determination.
	override void WorldTick()
	{
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			if (!playeringame[i] || players[i].mo == null)
				continue;

			let pawn = players[i].mo;
			pawn.LaserHeadshotLinedUpMain = IsHeadHit(pawn.LaserTraceTargetMain, pawn.LaserTraceHitPosMain);
			pawn.LaserHeadshotLinedUpOff  = IsHeadHit(pawn.LaserTraceTargetOff,  pawn.LaserTraceHitPosOff);
		}
	}
}
