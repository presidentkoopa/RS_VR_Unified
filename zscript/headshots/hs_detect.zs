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

	// Victims that have already had their confirm this tic, and the tic that
	// list belongs to. One SSG blast is up to twenty pellets and every pellet
	// arrives as its own WorldThingDamaged, so without this a single trigger
	// pull fires twenty markers, twenty sounds and twenty haptic pulses into
	// the same skull.
	//
	// The DAMAGE bonus deliberately does not go through this. Each pellet that
	// lands on a head has earned its own bonus; it is only the presentation
	// that wants collapsing down to one event.
	private Array<Actor> hs_ConfirmedThisTic;
	private int hs_ConfirmTic;

	// Set for the duration of our own follow-up DamageMobj call, so the
	// WorldThingDamaged it re-enters with is recognised as ours.
	private bool hs_InBonus;

	override void OnRegister()
	{
		super.OnRegister();

		// -1, not the zero default: maptime 0 is a real tic, and a zero here
		// would silently swallow a confirm that landed on it.
		hs_ConfirmTic = -1;
		hs_InBonus = false;
	}

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

	// Which weapon actually fired the shot behind this hit?
	//
	// The engine knows at attack time -- P_LineAttack takes LAF_ISOFFHAND and
	// picks OffhandWeapon or ReadyWeapon from it (p_map.cpp:4872) -- but it
	// never stamps that hand onto the puff or the missile, so nothing survives
	// the trip to WorldThingDamaged. This is a dual-wield engine, and the old
	// fixed read of ReadyWeapon was wrong for both things that hang off the
	// answer: which multiplier a shot earns, and which controller buzzes.
	//
	// Recovered in three steps, best evidence first:
	//
	//   1. Hitscan damage runs synchronously inside the weapon's own fire
	//      action, so at this exact moment the firing weapon's psprite is still
	//      sitting in its Fire sequence and the idle hand's is not. That is
	//      exact, and hitscan is every weapon HS_HighROF cares about.
	//   2. A projectile resolves its damage tics after the shot, with both
	//      psprites long back to idle. The laser trace is the next best
	//      witness: whichever hand is resting on this victim is the hand that
	//      put the shot there.
	//   3. Failing both, the main hand -- which is what this used to assume
	//      unconditionally.
	Weapon FiringWeapon(PlayerInfo p, Actor victim)
	{
		if (!p)
			return null;

		bool mainFiring = IsHandFiring(p, PSP_WEAPON, p.ReadyWeapon);
		bool offFiring  = IsHandFiring(p, PSP_OFFHANDWEAPON, p.OffhandWeapon);

		if (offFiring && !mainFiring)
			return p.OffhandWeapon;
		if (mainFiring && !offFiring)
			return p.ReadyWeapon;

		let pawn = p.mo;
		if (pawn && victim)
		{
			bool onMain = (pawn.LaserTraceTargetMain == victim);
			bool onOff  = (pawn.LaserTraceTargetOff  == victim);

			if (onOff && !onMain)
				return p.OffhandWeapon;
		}

		return p.ReadyWeapon;
	}

	// Is this hand's weapon mid-shot right now? See FiringWeapon above for why
	// that question answers "which hand fired" for hitscan.
	bool IsHandFiring(PlayerInfo p, int pspId, Weapon weap)
	{
		if (!p || !weap)
			return false;

		let psp = p.GetPSprite(pspId);
		if (!psp || !psp.CurState)
			return false;

		State fire = weap.FindState('Fire');
		if (fire && Actor.InStateSequence(psp.CurState, fire))
			return true;

		State altFire = weap.FindState('AltFire');
		if (altFire && Actor.InStateSequence(psp.CurState, altFire))
			return true;

		return false;
	}

	// Shared by the confirmed-hit path (WorldThingDamaged, below) and the
	// lined-up-before-firing path (WorldTick, below) -- one definition of
	// "that point is a head" for both, so the laser sight's live reaction
	// can never disagree with what actually confirms a moment later.
	//
	// Geometry only. It deliberately does NOT ask whether the victim is still
	// alive. On a killing hit the engine raises WorldThingDamaged BEFORE it
	// calls Die() (p_interaction.cpp:1624 vs :1627), so health is already at or
	// below zero while the victim is still standing at its full living height
	// -- and a killing headshot is the single shot that most deserves a
	// confirm. An aliveness test in here made it the one shot that got none.
	//
	// Aliveness is asked in the two places it actually means something: the
	// damage bonus checks it (a corpse should not take bonus damage) and the
	// sight path checks it (the beam should not tint on a corpse).
	bool IsHeadHit(Actor victim, Vector3 hitPos)
	{
		if (!victim || !victim.bISMONSTER || victim.player)
			return false;

		if (!HasHead(victim.GetClass()))
			return false;

		// Measured from the victim's own pos.z, not floorz -- see the file
		// header on why that matters the moment a Cacodemon gains altitude.
		double headBase = victim.pos.z + victim.height * (1.0 - HEAD_FRAC);
		double headTop  = victim.pos.z + victim.height;

		return hitPos.z >= headBase && hitPos.z <= headTop;
	}

	// The sight reaction, unlike the confirm, does care whether the thing is
	// still alive: tinting the beam on a corpse promises a headshot that is not
	// there to take. IsHeadHit answers geometry alone, so that test lives here.
	bool IsLinedUpOnHead(Actor target, Vector3 hitPos)
	{
		if (!target || target.health <= 0)
			return false;

		return IsHeadHit(target, hitPos);
	}

	// True if this victim already had its confirm this tic. Marks it on the way
	// past, so the first pellet of a blast gets the confirm and its nineteen
	// siblings do not. See hs_ConfirmedThisTic.
	bool AlreadyConfirmed(Actor victim)
	{
		int now = victim.Level.maptime;

		if (now != hs_ConfirmTic)
		{
			hs_ConfirmTic = now;
			hs_ConfirmedThisTic.Clear();
		}

		for (uint i = 0; i < hs_ConfirmedThisTic.Size(); i++)
		{
			if (hs_ConfirmedThisTic[i] == victim)
				return true;
		}

		hs_ConfirmedThisTic.Push(victim);
		return false;
	}

	override void WorldThingDamaged(WorldEvent e)
	{
		// Our own follow-up damage call below re-enters here. hs_InBonus is the
		// authoritative test -- handler state, set across exactly that call and
		// nothing else. The damage-type name compare is kept as a second line
		// of defence but is no longer load-bearing: a bare Name compare is the
		// kind of thing that quietly stops matching.
		if (hs_InBonus || e.DamageType == 'HS_HeadshotBonus')
			return;

		// Splash shares one inflictor position across every actor caught in the
		// blast, so without this a single rocket registers a headshot on the
		// whole room. Only P_RadiusAttack raises DMG_EXPLOSION
		// (p_map.cpp:6695-6776) -- a direct rocket impact does not carry it and
		// still counts as the headshot it is.
		if (e.DamageFlags & DMG_EXPLOSION)
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

		// The hand that fired decides both which multiplier this shot earns and
		// which controller buzzes for the confirm.
		let weap = FiringWeapon(source.player, victim);
		int hand = (weap && weap.bOffhandWeapon) ? HS_Marker.HS_HAND_OFF : HS_Marker.HS_HAND_MAIN;

		// Marker, sound and haptic: once per victim per tic. The bonus below is
		// per pellet, deliberately -- see hs_ConfirmedThisTic.
		if (!AlreadyConfirmed(victim))
			HS_Marker.Confirm(victim, inflictor.pos, source, hand);

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
		// DMG_NO_FACTOR: e.Damage has ALREADY been through the victim's damage
		// factor. Without this the bonus is factored a second time and a
		// resistant monster quietly takes less than the mult * original that
		// CVARINFO and the menu slider both promise.
		if (victim.health <= 0)
			return; // already dead from the original hit; nothing to add

		bool highROF = IsHighROF(weap ? weap.GetClass() : null);
		let cv = CVar.GetCVar(highROF ? "hs_headshot_damage_mult_highrof" : "hs_headshot_damage_mult", null);
		double mult = cv ? cv.GetFloat() : 1.0;
		int bonus = int(round(e.Damage * (mult - 1.0)));

		// A multiplier above 1.0 that rounds away to nothing leaves a small hit
		// -- one shotgun pellet, one chaingun tick into armour -- landing for
		// exactly the same damage as a body shot. One point is the least that
		// still reads as "the head hurt more."
		if (bonus <= 0 && mult > 1.0 && e.Damage > 0)
			bonus = 1;

		if (bonus > 0)
		{
			hs_InBonus = true;
			victim.DamageMobj(inflictor, source, bonus, 'HS_HeadshotBonus',
				DMG_THRUSTLESS | DMG_NO_PAIN | DMG_NO_FACTOR | DMG_PLAYERATTACK);
			hs_InBonus = false;
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
			pawn.LaserHeadshotLinedUpMain = IsLinedUpOnHead(pawn.LaserTraceTargetMain, pawn.LaserTraceHitPosMain);
			pawn.LaserHeadshotLinedUpOff  = IsLinedUpOnHead(pawn.LaserTraceTargetOff,  pawn.LaserTraceHitPosOff);
		}
	}
}
