// THE GRIP ARBITER.
//
// Three mods write the engine-native per-hand int GripClaimMain / GripClaimOff,
// and each tests ownership by comparing the VALUE rather than the owner:
//
//   RS_Hands     rs_held.zs          on any world object a hand closes on
//   RS_Reload    rr_sequence.zs      on a magazine carried from the pouch
//   RS_Holsters  RS_Holsters.zs      on the chest ammo pouch
//
// RS_Hands assigns GRIPSUBJ_Magazine to Ammo, Health, Armor, Inventory and
// ExplosiveBarrel. RS_Reload's SubjectFor returns GRIPSUBJ_Magazine as its
// DEFAULT case. So picking up a health pack writes the exact same int a
// magazine reload writes, and each mod's "clear only what is mine" guard will
// happily clear the other's claim believing it to be its own.
//
// Worse, RS_Holsters READS the field and swaps the hand's real weapon for a
// fist on ANY non-None value, ignoring even its own pouch-enable cvar. Pick
// anything up off the floor and you are disarmed.
//
// This is LIVE with any two of the three loaded. It is not a race that merging
// causes -- merging only removes the thing that made it occasional.
//
// ---------------------------------------------------------------------------
// WHY A Service AND NOT AN EventHandler
//
// The fix has to be reachable from three mods that must each still ship and run
// ALONE. A hard reference is not an option: EventHandler.Find("Literal") and
// Service.Find(class<Service>) both resolve their argument at COMPILE time
// (codegen.cpp:12434-12456), and a miss is fatal AND GLOBAL -- thingdef.cpp:
// 420-424 calls I_Error and then refuses to compile every pk3 LATER IN THE
// LOAD ORDER. One missing optional pk3 would take the whole game down.
//
// Service is the one path with no compile-time link in either direction.
// InitServices() (vmnatives.cpp:62-75, called from info.cpp:383) walks
// PClass::AllClasses and instantiates every Service subclass by itself, so this
// class registers with NOBODY naming it -- no MAPINFO entry, no
// AddEventHandlers line, nothing. Consumers find it with
// ServiceIterator.Find(String) (service.zs:154), which takes a plain String and
// whose Next() returns null when absent.
//
// So: load this pk3 and grip is arbitrated. Do not load it and every mod
// behaves exactly as it does today. Neither side names the other.
//
// ---------------------------------------------------------------------------
// THIS IS VERSION 1 AND IT IS DELIBERATELY INERT.
//
// It answers a handshake and NOTHING ELSE. It writes no field, reads no player,
// registers no handler and changes no behaviour. That is the entire point: with
// no test-compile available anywhere in this project, the first thing to prove
// is that a Service subclass in a loose pk3 really does auto-register and
// really is reachable by string -- and the cheapest way to prove it is a
// version that cannot possibly break anything if it is wrong.
//
// Arbitration proper (owner tokens, a priority ladder, lease expiry for a
// writer that dies mid-claim) lands in v2, once v1 has been seen to answer.
// Building it all at once would mean debugging the registration mechanism and
// the arbitration logic through the same silent failure.

class RS_GripArbiterService : Service
{
	// The protocol version this pk3 speaks. A consumer that ever needs to tell
	// an old arbiter from a new one asks for "grip.version"; today they all
	// speak 1. Bumped when the request vocabulary changes in a way a consumer
	// could not survive, never for adding a request.
	const PROTOCOL = 1;

	// An override takes NEITHER the scope keyword NOR the parameter defaults
	// from the virtual it overrides -- both are inherited from Service's own
	// declaration (engine/service.zs:47), and restating either is a compile
	// error ("Attempt to change scope for virtual function", "Default values
	// for parameter of virtual override not allowed"), not a harmless repeat.
	//
	// All six parameters are spelled out because that is the form the shipped
	// precedent uses -- RS_Main/zscript/systems/ui/RS_TierPalette.zs:121 is a
	// working Service in this same engine and this signature is copied from it
	// character for character.
	//
	// GetInt is the ONLY override. GetString, GetName, GetDouble, GetObject and
	// the clearscope *Data variants are left alone: a virtual's scope can never
	// be changed after the fact, so guessing wrong about one costs a build,
	// while adding a new override later costs nothing.
	override int GetInt(String request, string stringArg, int intArg, double doubleArg, Object objectArg, Name nameArg)
	{
		// THE HANDSHAKE, and it exists because ServiceIterator matching is a
		// case-insensitive SUBSTRING test, not equality (service.zs:167-176).
		// Find("RS_GripArbiterService") would also return any service whose
		// class name merely CONTAINS that text. A hit is therefore not proof of
		// identity, so a consumer must ask something only this class answers
		// and check the answer. Anything else returns 0 through Service's own
		// base GetInt and is correctly treated as "not the arbiter".
		if (request == "grip.hello")   return PROTOCOL;
		if (request == "grip.version") return PROTOCOL;

		// EVERY OTHER REQUEST RETURNS -1, NOT 0.
		//
		// Service's API has no way to signal "I do not answer that" -- the base
		// implementations return zero, and zero is a perfectly good answer to
		// plenty of real questions. So the vocabulary reserves -1 for "unknown
		// request" and no request may ever use -1 as a meaningful reply. A
		// consumer that gets -1 knows the arbiter is present but does not speak
		// this request, which is exactly the case a future protocol bump
		// creates, and it can fall back rather than believing a zero.
		return -1;
	}
}
