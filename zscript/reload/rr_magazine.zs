// THE MAGAZINE AND THE RESERVE. Where the ammunition actually moves.
//
// ONE SENTENCE OF MECHANISM: the real Ammo item holds only the CURRENT
// MAGAZINE, and a shadow item on the player holds the RESERVE POOL.
//
// THAT ORDER IS THE WHOLE TRICK AND IT IS NOT ARBITRARY. GZDoom's own
// Weapon.CheckAmmo reads Ammo1.Amount and refuses to fire below AmmoUse1
// (weapons.zs:1113-1147), so capping THAT number IS the gate. There is no
// per-weapon hook to install, no Reload state to override, no class to replace
// and nothing to tag -- which is exactly why this works on weapons this mod has
// never seen, in mods that were written before it existed. Put the pool in the
// real item and the magazine in the shadow one, the obvious way round, and you
// would have to gate firing yourself on every weapon in every mod that will
// ever load. That is the version that does not scale.
//
// EVERYTHING HERE IS BEHIND rr_magazines, WHICH DEFAULTS FALSE. With the cvar
// off nothing in this file runs except one FindInventory that returns null, and
// the reload stays what it is today: a gesture over one flat ammo pool. That is
// correct rather than a bug -- vanilla GZDoom has one pool and there is nothing
// to transfer.
//
// WHAT IS DELIBERATELY NOT HERE:
//   * the dropped-magazine world object and its pickup lockout. Designed, and
//     behind its own second toggle (see CLAUDE.md). Nothing in this file spawns
//     anything.
//   * slide-lock-back on empty. It needs a per-weapon empty state that most
//     foreign weapons do not have, so it would look broken on the majority of
//     the arsenal this exists for.
//   * anything touching Claim()/Abort() or a GripClaim write. The grip arbiter
//     owns those.

// THE SHADOW ITEM.
//
// AN Inventory ON THE PLAYER, AND NOT A HANDLER FIELD, FOR ONE REASON: it has
// to survive a save/load. The local event handler chain IS archived
// (p_saveg.cpp:1112) so a handler field would in fact survive that -- but
// MAPINFO's AddEventHandlers rebuilds RR_Reload per level, so a handler field
// does NOT survive a map change, and a reserve pool that empties itself every
// time you take an exit is worse than no reserve pool at all. Inventory travels
// with the player. A DObject's script fields are serialised by
// PClass::WriteAllFields (dobjtype.cpp:136) with no opt-in needed, dynamic
// arrays included (PDynArray::WriteValue, types.cpp:2277).
class RR_Reserve : Inventory
{
	// PARALLEL ARRAYS, INDEXED TOGETHER. ZScript dynamic arrays take integral
	// and object types only -- Array<SomeStruct> does not compile, which
	// RS_Holsters.zs:18-21 found the hard way and worked around the same way.
	//
	// INSTANCE POINTERS AND NOT CLASS NAMES, which is the other half of that
	// same lesson (RS_Holsters.zs:228-237, the "can't holster it again" bug).
	// Two reasons here: the player has exactly one Ammo item per ammo class so
	// the pointer is a stronger key than the name, and GZDoom nulls an
	// Actor-typed field automatically when the actor it points to is destroyed
	// -- so "that ammo type is gone" is just kinds[i] reading null, with no
	// FindInventory needed to notice and no stale row to trip over.
	//
	// NO SCRIPT PRECEDENT IN THIS TREE FOR A DYNAMIC ARRAY AS A FIELD OF AN
	// ACTOR SUBCLASS, and the house rule is that no precedent usually means it
	// does not work -- so this one is cited from the engine instead, all four
	// stages, because it is the least-proven construct in the magazine work and
	// the next person to read this deserves better than "it seemed fine":
	//   * CONSTRUCTED PER INSTANCE. PClass::CreateNew memcpys the class
	//     Defaults and then calls InitializeSpecials (dobjtype.cpp:454-470), and
	//     PDynArray::InitializeValue (types.cpp:2190) hands the new instance its
	//     own heap block rather than the defaults' pointer. Without that step
	//     every RR_Reserve would share one array, which is the failure this
	//     paragraph exists to say is not happening.
	//   * TRACED BY THE GC. DObject::Mark walks ArrayPointers (dobject.cpp:373-381).
	//   * NULLED ON DESTROY. PointerSubstitution does the same walk
	//     (dobject.cpp:533-546), which is what makes the null-row handling below
	//     correct rather than a dangling read.
	//   * SERIALISED. Script fields go through PClass::WriteAllFields
	//     (dobjtype.cpp:136) and PDynArray::WriteValue (types.cpp:2277).
	// The five RS packages only ever put dynamic arrays on EventHandlers
	// (RS_Holsters.zs:210, rs_grabpolicy.zs:85) because none of them has yet
	// needed one that outlives a map.
	Array<Ammo> kinds;
	Array<int>  pool;

	Default
	{
		Inventory.MaxAmount 1;
		Inventory.InterHubAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.QUIET
	}

	States
	{
	Spawn:
		// TNT1 for the same reason RR_AmmoInHand uses it (rr_ammo.zs:66): there
		// is nothing to draw. This one is never on a psprite layer at all -- it
		// is pure bookkeeping that happens to live in the inventory chain
		// because that is the container the engine already saves for us.
		TNT1 A -1;
		Stop;
	}

	// -1 when this ammo type has no row yet. Linear, over a table whose length
	// is the number of ammo classes the player has ever spilled -- four, in
	// stock Doom. A map or a hash here would cost more to maintain than the
	// scan costs to run.
	int RowOf(Ammo am)
	{
		if (!am) return -1;
		for (int i = 0; i < kinds.Size(); i++)
		{
			if (kinds[i] == am) return i;
		}
		return -1;
	}

	int Get(Ammo am)
	{
		int i = RowOf(am);
		return (i < 0) ? 0 : pool[i];
	}

	void Set(Ammo am, int v)
	{
		if (!am) return;
		if (v < 0) v = 0;

		int i = RowOf(am);
		if (i >= 0) { pool[i] = v; return; }

		// A zero for a type with no row is already true. Recording it would
		// grow the table to say nothing.
		if (v == 0) return;

		// REUSE A DEAD ROW BEFORE PUSHING A NEW ONE. A row whose kinds[] entry
		// has gone null is an ammo type the engine destroyed under us
		// (ClearInventory, a morph, a hub strip); its count is unreachable and
		// the slot is free. Reusing it is also why nothing in this file ever
		// calls Array.Delete -- no index shifts, so no other row can be moved
		// out from under a caller mid-loop.
		for (int k = 0; k < kinds.Size(); k++)
		{
			if (!kinds[k]) { kinds[k] = am; pool[k] = v; return; }
		}

		kinds.Push(am);
		pool.Push(v);
	}

	// GIVE IT ALL BACK. Called every tic that rr_magazines is OFF and a reserve
	// exists, which is how turning the cvar off mid-game returns the player to
	// exactly vanilla rather than stranding most of their ammunition in an item
	// nothing reads any more.
	//
	// Idempotent on purpose: after the first pass every count is zero and the
	// loop does nothing but walk a four-entry array. It is cheaper than
	// remembering whether the dump has already happened, and remembering would
	// need a flag that has to survive the same save/load this class exists for.
	void Dump()
	{
		for (int i = 0; i < kinds.Size(); i++)
		{
			let am = kinds[i];
			int n = pool[i];
			pool[i] = 0;
			if (!am || n <= 0) continue;

			am.Amount += n;
			if (am.MaxAmount > 0 && am.Amount > am.MaxAmount) am.Amount = am.MaxAmount;
		}
	}
}

// PLAY SCOPE, DECLARED ON THE CLASS -- same marker and the same reason as
// RR_Ammo (rr_ammo.zs:112). A parentless class with no scope keyword is plain
// data (zcc_compile.cpp:1006-1020) and every function in it inherits that,
// static ones included, so calling a play method like Actor.FindInventory from
// here would fail. The stock precedent that proves the construct is
// `class ScriptUtil play` (wadsrc scriptutil.zs:20), parentless, play-qualified,
// with static methods that call play methods on an Actor.
class RR_Mag play
{
	// The shadow item, created on demand. `create` is false everywhere the
	// answer "there isn't one" is a valid answer, so a game that never turns
	// rr_magazines on never gets the item at all.
	static RR_Reserve Bag(PlayerPawn pmo, bool create)
	{
		if (!pmo) return null;

		let r = RR_Reserve(pmo.FindInventory('RR_Reserve'));
		if (r || !create) return r;

		// Name into class<Inventory>, as rr_ammo.zs:168 and rs_hands.zs:324
		// both do. GiveInventory is Actor's (inventory_util.zs:81).
		pmo.GiveInventory('RR_Reserve', 1);
		return RR_Reserve(pmo.FindInventory('RR_Reserve'));
	}

	// THE LIVE Ammo ITEM A WEAPON DRAWS FROM, or null -- and null is an ordinary
	// answer, not an error. A chainsaw or a fist has no AmmoType1 at all; a
	// weapon whose ammo the player has never picked up has the type but no item.
	//
	// Weapon.Ammo1 is cached at pickup (weapons.zs:843) and is the fast path,
	// but it can be stale if something destroyed and re-gave the ammo item
	// underneath it, so the lookup by class is the fallback. Stock does exactly
	// that lookup at weapons.zs:887, which is also the precedent for handing a
	// class<Ammo> to FindInventory's class<Inventory> parameter.
	static Ammo AmmoOf(Actor owner, Weapon w)
	{
		if (!w || !w.AmmoType1) return null;
		if (w.Ammo1) return w.Ammo1;
		if (!owner) return null;
		return Ammo(owner.FindInventory(w.AmmoType1));
	}

	static int Pool(PlayerPawn pmo, Ammo am)
	{
		let r = Bag(pmo, false);
		return r ? r.Get(am) : 0;
	}

	// A MAGAZINE CANNOT BE BIGGER THAN THE POOL IT IS DRAWN FROM. MaxAmount is
	// live -- Backpack raises it on the item itself -- so this is read every
	// time rather than cached. A cap above MaxAmount would make the reserve
	// mathematically unreachable: the magazine would swallow everything the
	// player is allowed to carry and there would never be anything to reload
	// from.
	static int Fit(Ammo am, int cap)
	{
		if (!am || cap < 0) return 0;
		if (am.MaxAmount > 0 && cap > am.MaxAmount) return am.MaxAmount;
		return cap;
	}

	// FOLD EVERYTHING ABOVE THE MAGAZINE INTO THE RESERVE. Run every tic, for
	// each ammo type a held weapon feeds from.
	//
	// THIS IS ALSO THE MIGRATION. Turn rr_magazines on mid-game with 200 clips
	// in one flat pool and the first pass of this leaves a full magazine and
	// 188 in reserve, with no separate "convert my ammo" step to write, to run
	// at the right moment, or to get wrong on a savegame that never saw it.
	//
	// IT ONLY EVER SPILLS DOWN. `mag` is min(what is there, capacity) and never
	// the other way about -- if this were allowed to raise the magazine from the
	// reserve it would silently reload the gun every tic and there would be no
	// feature at all. Filling upward happens in exactly one place, Seat, which
	// only the completed gesture calls.
	//
	// THE ONE PLACE THIS DIFFERS FROM VANILLA'S AMMO CEILING, stated plainly
	// because it is a real difference: because Amount is held at or below the
	// magazine size, it is almost always well under MaxAmount, so the engine's
	// pickup test (`Amount < MaxAmount`, weapons.zs:894) accepts ammunition the
	// player is not entitled to. The total is therefore clipped to MaxAmount
	// here and the surplus is discarded -- the same amount of ammunition
	// vanilla would have refused, so the ceiling is preserved exactly; the only
	// visible difference is that the pickup disappears instead of staying on the
	// floor. Fixing THAT properly means an Ammo.HandlePickup override, which
	// means replacing every ammo class in every mod, which is the universality
	// this whole design exists to avoid.
	//
	// AND THE CLIP LANDS ON THE RESERVE SIDE OF THE LEDGER, NEVER ON THE
	// MAGAZINE. `mag` below is min(what is in the item, capacity) and is worked
	// out from the UNCLIPPED amount, so the ceiling can only ever eat into what
	// was about to be spilled. Losing the rounds in the gun in your hand because
	// you walked over a clip would be indefensible.
	static void Trim(PlayerPawn pmo, Ammo am, int cap)
	{
		if (!pmo || !am) return;

		cap = Fit(am, cap);
		if (cap <= 0) return;

		int res = Pool(pmo, am);

		// Nothing above the magazine and nothing below it: the common case, and
		// it costs one FindInventory.
		if (am.Amount <= cap && res == 0) return;

		int total = am.Amount + res;
		if (am.MaxAmount > 0 && total > am.MaxAmount) total = am.MaxAmount;

		int mag = min(am.Amount, cap);
		if (mag > total) mag = total;

		int keep = total - mag;
		if (keep < 0) keep = 0;

		if (mag == am.Amount && keep == res) return;   // already settled

		// THE BAG IS MADE BEFORE THE MAGAZINE IS EMPTIED, not after. The other
		// order loses rounds outright on the one tic where GiveInventory fails:
		// Amount would already have been written down with nowhere for the
		// spill to have gone.
		let r = Bag(pmo, keep > 0);
		if (keep > 0 && !r) return;

		am.Amount = mag;
		if (r) r.Set(am, keep);
	}

	// THE SEATED RELOAD. Reserve into magazine, and the ONLY function here that
	// fills upward. Returns how many rounds moved, for the debug line.
	//
	// NOT CALLED Seat, although that is what the sequence calls the beat that
	// calls it: RR_Reload.Seat is already a different function one file over --
	// the sound, the haptics and this. Two Seats reachable from the same method
	// body is the kind of ambiguity this package has already paid for once.
	//
	// `per` is how many rounds one seating inserts, 0 meaning "as many as fit".
	// That is what makes a shotgun a shotgun: one shell per trip to the pouch,
	// COMMITTED THE MOMENT IT IS SEATED. Stop after three and you have three and
	// you fire with a partial tube. An interrupted shotgun reload is never
	// wasted, only incomplete -- which is only true because the debit happens
	// here, at the seat, and not when the shell was drawn. Dropping what you are
	// carrying costs the trip and nothing else, exactly as README promises.
	static int Insert(PlayerPawn pmo, Weapon w, int cap, int per)
	{
		let am = AmmoOf(pmo, w);
		if (!am) return 0;

		cap = Fit(am, cap);
		if (cap <= 0) return 0;

		// No bag means no reserve, which means nothing to move. Not an error --
		// it is what a player who has never spilled a round looks like.
		let r = Bag(pmo, false);
		if (!r) return 0;

		int res = r.Get(am);
		if (res <= 0) return 0;

		int need = cap - am.Amount;
		if (need <= 0) return 0;

		int take = (per > 0) ? min(per, need) : need;
		take = min(take, res);
		if (take <= 0) return 0;

		am.Amount += take;
		r.Set(am, res - take);
		return take;
	}

	// KEEP AN EMPTY GUN IN THE HAND THAT IS HOLDING IT.
	//
	// Without this the feature cannot work at all. Weapon.CheckAmmo calls
	// PickNewWeapon the moment Amount drops below AmmoUse1 (weapons.zs:1147-1151)
	// -- so running the magazine dry would swap the gun out of your hand before
	// you could reload it, which is precisely the failure this fork added
	// Weapon.bKeepWhenEmpty to prevent. Read its comment at weapons.zs:76-90: it
	// is a plain bool rather than a flagdef specifically because +WEAPON.<FLAG>
	// does not resolve from a pk3 in this fork, and this package is its first
	// consumer.
	//
	// CONDITIONAL ON THE RESERVE, not set flat. With rounds left to reload from,
	// an empty magazine must stay in your hand. With the reserve empty too the
	// player is genuinely out of ammunition and vanilla's auto-switch is the
	// right answer and the one they expect -- so the flag goes back off and the
	// engine does what it always did.
	static void KeepEmpty(PlayerPawn pmo, Weapon w)
	{
		if (!w) return;
		let am = AmmoOf(pmo, w);
		w.bKeepWhenEmpty = (am != null) && (Pool(pmo, am) > 0);
	}

	// RESTORE THE FLAG. Separate from KeepEmpty because the off path must not
	// consult a reserve it is in the middle of dumping.
	//
	// `.default` AND NOT A LITERAL false. Nothing in the engine or in any of the
	// five RS packages sets bKeepWhenEmpty -- this is its first consumer -- so
	// false is provably right today and would be silently wrong the day a
	// weapon ships with it set in its own Default block. Both halves of the
	// construct are already proven: rr_feed.zs:528 reads a plain field through
	// `.default` (`w.default.AmmoUse1`), and RS_Hands rs_grabpolicy.zs:335
	// restores a bool the same way round -- `a.bSPECIAL = noWalk ? false :
	// a.default.bSPECIAL;`.
	//
	// SELF-HEALING RATHER THAN EXHAUSTIVE. Only the two weapons currently in
	// hand are reachable from here, so a gun that was stowed while the flag was
	// set keeps it until it comes back out -- at which point this clears it on
	// the first tic. The alternative is walking the whole inventory chain every
	// tic to fix a field nothing reads unless the weapon is held.
	static void RestoreKeep(Weapon w)
	{
		if (!w) return;
		w.bKeepWhenEmpty = w.default.bKeepWhenEmpty;
	}
}
