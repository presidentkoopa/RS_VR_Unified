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
// ================= THE KNOWN LIMITATION. READ IT BEFORE EDITING. ============
//
// AN EMPTY MAGAZINE MAKES A WEAPON UNSELECTABLE BY THE KEYBOARD-STYLE PATHS,
// AND THIS IS NOT FIXED. It is the price of the whole mechanism and it is
// stated here rather than discovered in a headset.
//
// Capping Ammo1.Amount IS the firing gate -- that is the trick the file opens
// with. But the engine asks the SAME question, Weapon.CheckAmmo, to decide
// whether a weapon is worth switching to, and bKeepWhenEmpty only suppresses
// the auto-switch INSIDE CheckAmmo; it does not change what CheckAmmo returns.
// So with the magazine at zero:
//   * slot keys skip the weapon. PlayerPawn.PickWeapon gates each candidate on
//     CheckAmmo when its `checkammo` argument is true (player.zs:2511, :2527),
//     and the engine passes `!(dmflags2 & DF2_DONTCHECKAMMO)` for it from both
//     call sites (d_net.cpp:2522, g_game.cpp:662) -- so true unless the player
//     has turned that dmflag on.
//   * next/previous weapon skip it. PickNextWeapon and PickPrevWeapon gate on
//     CheckAmmo UNCONDITIONALLY, with no such argument to turn off
//     (player.zs:2769, :2825), and the engine calls them with no parameters at
//     all (d_net.cpp:2527, :2532). The dmflag does not reach them.
//   * BestWeapon and the start-game pick skip it too (player.zs:2126, :2277).
// Fire a shotgun dry, switch away by hand, and slot 3 will not bring it back.
//
// WHAT STILL WORKS, verified rather than hoped, and this is why the practical
// blast radius in the stack this mod actually ships into is small:
//   * PlayerPawn.MoveWeaponToHand (player.zs:2605) does NOT consult CheckAmmo,
//     and it is the retrieval path for RS_Holsters, RS_HardPoints and the VR
//     weapon wheel. In headset, drawing the gun off your body still works.
//   * bKeepWhenEmpty still keeps the dry gun in the hand that is holding it,
//     so reaching this state at all takes a DELIBERATE manual switch away.
//
// NOTHING IS EVER LOST, ONLY STRANDED, and there are three ways back:
//   * bring the weapon into a hand by any holster/hardpoint/wheel route and
//     reload it normally,
//   * set sv_dontcheckammo (Gameplay Options -> "Don't check ammo for weapon
//     switch"). It is the engine's own switch for exactly this question and it
//     restores the SLOT KEYS. It does not restore next/previous weapon, per
//     the second bullet above.
//   * turn rr_magazines off. RR_Reserve.Dump hands every reserved round back
//     to the real Ammo items, so the ammunition is recoverable from the
//     console at any time.
//
// WHY THE OBVIOUS WORKAROUND IS WORSE THAN THE LIMITATION. The tempting fix is
// to hold a floor of one shot in the magazine so CheckAmmo keeps saying yes.
// It fails twice over:
//   1. CheckAmmo cannot be made to mean "selectable but not fireable".
//      PlayerPawn.FireWeapon calls CheckAmmo(PrimaryFire, true) with
//      requireAmmo defaulted FALSE (player.zs:435), the same call shape
//      selection uses. Anything that makes selection succeed makes FIRING
//      succeed -- including bAmmo_Optional, which short-circuits at
//      weapons.zs:1109 on exactly that defaulted parameter. A floored magazine
//      is therefore a free shot, refilled from the reserve by the next tic:
//      the gun fires forever at one round per tic and the reload gesture
//      becomes pointless. Gating firing back off would mean a per-weapon hook
//      on every weapon in every mod, which is the one thing this design exists
//      to avoid.
//   2. The floor cannot even be aimed. There is one Ammo.Amount per ammo
//      CLASS, not per weapon, so a floor held for a stowed chaingun is a floor
//      held for the pistol in your hand. "Only floor it when no held weapon
//      uses it" makes the free shot rarer, not absent, and buys a second
//      upward-filling path -- which is precisely the invariant Trim's ratchet
//      exists to keep down to one.
// The honest fix is engine-side: teach CheckAmmo to consult the reserve, in
// the same fork that already added bKeepWhenEmpty and the bHolsterHidden gate
// (weapons.zs:1084) for this mod's benefit. That is an engine change, it
// cannot be made from a pk3, and it is not attempted here.
// ============================================================================
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
	//
	// THREE ARRAYS AND NOT TWO, AS OF THE PICKUP FIX. `mags` holds what the
	// magazine contained on the PREVIOUS upkeep pass; -1 means "this ammo type
	// has never been through one". Trim needs that number to tell a round that
	// was already loaded from a round that arrived since -- without it, ammo
	// pickups reload the gun for free. The long note on Trim is the argument.
	//
	// -1 AND NOT 0 AS THE SENTINEL, because a magazine of zero is a real and
	// extremely common value here: fired dry, reload owed, reserve waiting. If
	// zero meant "unseeded" then every dry weapon would re-migrate on the next
	// pickup, which is the exact bug this array exists to close.
	Array<Ammo> kinds;
	Array<int>  pool;
	Array<int>  mags;

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

	// PAD THE SIDE ARRAYS UP TO kinds, AND DO IT BEFORE EVERY INDEXED READ.
	//
	// THIS IS A SAVEGAME GUARD AND NOT DEFENSIVE PADDING FOR ITS OWN SAKE. A
	// save written by the build that shipped `kinds`/`pool` and no `mags` has
	// no `mags` field in it at all, so on load the first two come back
	// populated and the third stays at its default, which is EMPTY. Every
	// `mags[i]` in this class would then be an out-of-range index on a save
	// the owner is very likely to still have sitting on disk, and an
	// out-of-range array read is a VM abort, not a zero.
	//
	// Row() below is the only thing that ever pushes, and it pushes all three
	// together, so after one pass the loops do nothing. Precedent for exactly
	// this shape -- pad a dynamic array up to a required length rather than
	// trusting it -- is RS_Holsters.zs:1326, ensurePouchPrevious.
	void Align()
	{
		while (pool.Size() < kinds.Size()) pool.Push(0);
		while (mags.Size() < kinds.Size()) mags.Push(-1);
	}

	// THE ROW FOR THIS AMMO TYPE, or -1. Linear, over a table whose length is
	// the number of ammo classes the player has ever carried -- four, in stock
	// Doom. A map or a hash here would cost more to maintain than the scan
	// costs to run.
	//
	// ROWS ARE NOW CREATED EAGERLY, which they were not before `mags` existed.
	// The old Set() refused to grow the table to record a pool of zero, on the
	// grounds that a zero for a type with no row is already true. That is still
	// true of the POOL and is no longer true of the MAGAZINE: an empty
	// magazine with a reload owed has to be distinguishable from an ammo type
	// this code has never looked at, and the only place that distinction can
	// live is a row.
	int Row(Ammo am, bool create)
	{
		if (!am) return -1;
		Align();

		for (int i = 0; i < kinds.Size(); i++)
		{
			if (kinds[i] == am) return i;
		}
		if (!create) return -1;

		// REUSE A DEAD ROW BEFORE PUSHING A NEW ONE. A row whose kinds[] entry
		// has gone null is an ammo type the engine destroyed under us
		// (ClearInventory, a morph, a hub strip); its count is unreachable and
		// the slot is free. Reusing it is also why nothing in this file ever
		// calls Array.Delete -- no index shifts, so no other row can be moved
		// out from under a caller mid-loop.
		for (int k = 0; k < kinds.Size(); k++)
		{
			if (!kinds[k]) { kinds[k] = am; pool[k] = 0; mags[k] = -1; return k; }
		}

		kinds.Push(am);
		pool.Push(0);
		mags.Push(-1);

		// Array.Size() is uint and this function returns int. That narrowing is
		// fine and is not worth a cast -- the engine's own scripts do exactly
		// this: `int rsize = RestrictedToPlayerClass.Size();`
		// (inventory.zs:637) and `int x = index >= jobs.Size()? jobs.Size()-1 :
		// index;` (engine/screenjob.zs:500). A Push has just happened, so the
		// size is at least one and cannot underflow.
		return kinds.Size() - 1;
	}

	int Get(Ammo am)
	{
		int i = Row(am, false);
		return (i < 0) ? 0 : pool[i];
	}

	void Set(Ammo am, int v)
	{
		if (v < 0) v = 0;
		int i = Row(am, true);
		if (i >= 0) pool[i] = v;
	}

	// WHAT THE MAGAZINE HELD LAST PASS. -1 means no pass has happened for this
	// ammo type yet, which is the signal Trim reads as "seed me" -- the
	// one-time migration of an existing flat pool into magazine + reserve.
	int MagOf(Ammo am)
	{
		int i = Row(am, false);
		return (i < 0) ? -1 : mags[i];
	}

	void SetMag(Ammo am, int v)
	{
		if (v < 0) v = 0;
		int i = Row(am, true);
		if (i >= 0) mags[i] = v;
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
	//
	// THE MAGAZINE RECORD IS UN-SEEDED HERE TOO, and that is what makes the
	// off-then-on round trip land back where the documented migration says it
	// should. Everything has just been poured back into the real Ammo item, so
	// the flat pool is genuinely flat again and the next Trim should treat it
	// exactly like the first-ever pass: full magazine, remainder in reserve.
	// Leaving a stale magazine number here instead would mean a player who
	// toggled off and on after firing dry came back with an empty magazine and
	// no explanation.
	void Dump()
	{
		Align();
		for (int i = 0; i < kinds.Size(); i++)
		{
			let am = kinds[i];
			int n = pool[i];
			pool[i] = 0;
			mags[i] = -1;
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
	// answer "there isn't one" is a valid answer -- every reader. The single
	// caller that passes true is Trim, which runs only with rr_magazines on, so
	// a game that never turns the cvar on still never gets the item at all.
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
	// IT ONLY EVER SPILLS DOWN, AND THE RATCHET THAT GUARANTEES THAT IS `mags`.
	//
	// The obvious way to write this line is `mag = min(am.Amount, cap)`, and it
	// was written that way, and it silently reloaded the gun on every ammo
	// pickup in the game. The engine writes a pickup STRAIGHT INTO Ammo.Amount
	// -- Ammo.HandlePickup, actors/inventory/ammo.zs:80-107 for walking over an
	// ammo item, Weapon.AddAmmo, weapons.zs:894-900 for the ammo that comes
	// with a weapon -- and neither asks anything in this file first. So a dry
	// stock shotgun (Amount 0, reserve 40, cap 8) that walks over a shell box
	// came out of the min() with a FULL EIGHT-SHELL TUBE and no gesture
	// performed. Every weapon, every pickup, and stock Doom is wall to wall
	// ammo pickups.
	//
	// So the magazine is clamped to what it held ON THE PREVIOUS PASS as well
	// as to capacity. Any INCREASE in Amount since the last tic is, by
	// definition, ammunition that arrived from the world, and under magazines
	// that belongs in the reserve -- so it routes to `keep`. Decreases pass
	// through untouched, which is what firing looks like. -1 means no previous
	// pass exists and IS the one-time migration: seed from min(Amount, cap) so
	// switching the cvar on still leaves a loaded magazine and the rest in
	// reserve.
	//
	// FILLING UPWARD HAPPENS IN EXACTLY ONE PLACE AND IT IS Insert, one
	// function below -- which is called only by the completed gesture, from
	// RR_Reload.Seat in rr_sequence.zs. (The two are easy to confuse. Insert is
	// deliberately not named Seat; see its own header.) Insert writes `mags`
	// itself when it moves rounds, because otherwise this ratchet would claw a
	// freshly seated magazine straight back into the reserve on the next tic.
	//
	// ONE HONEST CONSEQUENCE FOR FOREIGN MODS: a weapon that "reloads" itself
	// by assigning Ammo1.Amount directly in a Reload state is indistinguishable
	// from a pickup here, so its write lands in the reserve rather than in the
	// magazine. Such a weapon is already fighting this feature for control of
	// the same number; the ratchet only makes which one wins predictable.
	//
	// THE ONE PLACE THIS DIFFERS FROM VANILLA'S AMMO CEILING, stated plainly
	// because it is a real difference: because Amount is held at or below the
	// magazine size, it is almost always well under MaxAmount, so the engine's
	// pickup test -- `Amount < MaxAmount` in Ammo.HandlePickup
	// (actors/inventory/ammo.zs:85), and the same test again in Weapon.AddAmmo
	// (weapons.zs:894) for weapon-granted ammo -- accepts ammunition the player
	// is not entitled to. The total is therefore clipped to MaxAmount here and
	// the surplus is discarded: the same amount of ammunition vanilla would
	// have refused, so the ceiling is preserved exactly, and the only visible
	// difference is that the pickup disappears instead of staying on the floor.
	// Fixing THAT properly means an Ammo.HandlePickup override, which means
	// replacing every ammo class in every mod, which is the universality this
	// whole design exists to avoid.
	//
	// AND THE CLIP LANDS ON THE RESERVE SIDE OF THE LEDGER, NEVER ON THE
	// MAGAZINE. `mag` is settled before the ceiling is applied to it, so the
	// clip can only ever eat into what was about to be spilled. Losing the
	// rounds in the gun in your hand because you walked over a box of them
	// would be indefensible.
	static void Trim(PlayerPawn pmo, Ammo am, int cap)
	{
		if (!pmo || !am) return;

		cap = Fit(am, cap);
		if (cap <= 0) return;

		// THE BAG IS MADE BEFORE THE MAGAZINE IS EMPTIED, not after. The other
		// order loses rounds outright on the one tic where GiveInventory fails:
		// Amount would already have been written down with nowhere for the
		// spill to have gone. Nothing here is willing to touch Amount without
		// somewhere to put what comes off it, so a missing bag is a clean
		// no-op and the player keeps everything they had.
		//
		// `create` IS TRUE NOW WHERE IT USED TO BE `keep > 0`. The bag is no
		// longer only a container for a surplus -- it is also the only place
		// the previous magazine can be recorded, and that has to be written on
		// the pass where the magazine is still full, so that the pass after a
		// pickup has something to clamp against. Trim runs only with
		// rr_magazines on, so "a game that never turns the cvar on never gets
		// the item" is still exactly true.
		let r = Bag(pmo, true);
		if (!r) return;

		int res  = r.Get(am);
		int last = r.MagOf(am);          // -1 = never seen, i.e. migrate

		int total = am.Amount + res;
		if (am.MaxAmount > 0 && total > am.MaxAmount) total = am.MaxAmount;

		int mag = min(am.Amount, cap);
		if (last >= 0 && mag > last) mag = last;   // the ratchet
		if (mag > total) mag = total;
		if (mag < 0) mag = 0;

		int keep = total - mag;
		if (keep < 0) keep = 0;

		am.Amount = mag;
		r.Set(am, keep);
		r.SetMag(am, mag);
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
	//
	// AND IT RECORDS THE NEW MAGAZINE BEFORE IT RETURNS. Trim clamps the
	// magazine to what `mags` says it held last pass, so a seated round that
	// did not update `mags` would be spilled straight back into the reserve on
	// the very next tic and the reload would appear to do nothing. This write
	// is what makes Insert the one legitimate way to fill upward rather than
	// just the one that tries.
	static int Insert(PlayerPawn pmo, Weapon w, int cap, int per)
	{
		let am = AmmoOf(pmo, w);
		if (!am) return 0;

		cap = Fit(am, cap);
		if (cap <= 0) return 0;

		// No bag means no reserve, which means nothing to move. Not an error --
		// it is what a player looks like before Trim has run for them even once
		// under the cvar. (Trim creates the bag; a player who has simply never
		// SPILLED a round has one, holding zeroes and the magazine record.)
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
		r.SetMag(am, am.Amount);
		return take;
	}

	// KEEP AN EMPTY GUN IN THE HAND THAT IS HOLDING IT.
	//
	// Without this the feature cannot work at all. Weapon.CheckAmmo calls
	// PickNewWeapon the moment Amount drops below AmmoUse1 (weapons.zs:1149-1151)
	// -- so running the magazine dry would swap the gun out of your hand before
	// you could reload it, which is precisely the failure this fork added
	// Weapon.bKeepWhenEmpty to prevent. Read its comment at weapons.zs:77-90: it
	// is a plain bool rather than a flagdef specifically because +WEAPON.<FLAG>
	// does not resolve from a pk3 in this fork, and this package is its first
	// consumer.
	//
	// CONDITIONAL ON THE RESERVE, not set flat. With rounds left to reload from,
	// an empty magazine must stay in your hand. With the reserve empty too the
	// player is genuinely out of ammunition and vanilla's auto-switch is the
	// right answer and the one they expect -- so the flag goes back to the
	// weapon's own default and the engine does what it always did.
	//
	// OR-ED WITH THE DEFAULT, NEVER ASSIGNED FLAT. This function can only ever
	// ADD the behaviour, never take it away. The unconditional assignment that
	// used to be here would CLEAR the flag on a weapon whose own class defaults
	// have it set, the instant that weapon's reserve ran out -- silently
	// overruling the weapon author on a field this package does not own -- and
	// it directly contradicted RestoreKeep below, which goes to the trouble of
	// restoring w.default.bKeepWhenEmpty precisely because a literal false is
	// not provably right.
	//
	// TODAY THIS CHANGES NOTHING OBSERVABLE, and that is the honest statement.
	// bKeepWhenEmpty is a plain bool, not a flagdef, so it cannot be set from a
	// Default block at all -- w.default.bKeepWhenEmpty is false for every class
	// that currently exists, and nothing in the engine or in the five RS
	// packages sets it. The OR is here so that the day this fork promotes the
	// field to a real property or flagdef, the two halves of this file already
	// agree about who owns it.
	//
	// WHAT THIS FLAG DOES NOT DO -- READ THIS BEFORE TRUSTING IT.
	//
	// bKeepWhenEmpty suppresses the AUTO-SWITCH inside Weapon.CheckAmmo
	// (weapons.zs:1099 and :1149, both `if (autoSwitch && !bKeepWhenEmpty)`)
	// and NOTHING ELSE. It does not make an empty weapon SELECTABLE, because
	// selection does not consult the flag -- it consults CheckAmmo's RETURN
	// VALUE, which is still false:
	//   * PlayerPawn.PickWeapon gates every candidate on
	//     CheckAmmo(EitherFire, false) when its `checkammo` argument is true
	//     (player.zs:2511, :2527). That argument has NO default in this fork;
	//     the engine supplies !(dmflags2 & DF2_DONTCHECKAMMO) at both call
	//     sites, so the slot keys skip an empty weapon unless sv_dontcheckammo
	//     is set,
	//   * PlayerPawn.PickNextWeapon / PickPrevWeapon gate on CheckAmmo
	//     UNCONDITIONALLY, with no such argument to turn off (player.zs:2769,
	//     :2825) -- so next-weapon and previous-weapon skip it regardless,
	//   * PlayerPawn.BestWeapon (player.zs:2126) and the start-game pick
	//     (player.zs:2277) skip it too.
	// So a weapon fired dry and then switched away from MANUALLY becomes
	// unreachable by every keyboard-style selection path, and with it the
	// reserve behind it -- Insert only runs for a weapon that is in a hand.
	//
	// THIS IS A KNOWN, UNFIXED LIMITATION AND IT IS NOT FIXED HERE. See the
	// header of this file for the full argument, the three escape hatches that
	// keep it from ever losing ammunition, and why the obvious one-shot-floor
	// workaround is worse than the limitation.
	static void KeepEmpty(PlayerPawn pmo, Weapon w)
	{
		if (!w) return;
		let am = AmmoOf(pmo, w);
		w.bKeepWhenEmpty = w.default.bKeepWhenEmpty || ((am != null) && (Pool(pmo, am) > 0));
	}

	// RESTORE THE FLAG. Separate from KeepEmpty because the off path must not
	// consult a reserve it is in the middle of dumping.
	//
	// `.default` AND NOT A LITERAL false. Nothing in the engine or in any of the
	// five RS packages sets bKeepWhenEmpty -- this is its first consumer -- so a
	// literal false is provably right today and would be silently wrong the day
	// a weapon ships with the field set in its own class defaults, which is
	// exactly what will happen if this fork ever promotes the plain bool to a
	// real property or flagdef. KeepEmpty above ORs with the same value for the
	// same reason; the two must not disagree. Both halves of the
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
