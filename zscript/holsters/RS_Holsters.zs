// Body-anchored holsters: calibration + anchor placement + grip-claim
// arbitration. This is the part that actually DRIVES the engine's
// HolsterClaimMain/HolsterClaimOff -- without this handler running, those
// fields stay false, the native grip redirect never fires, and grip keeps its
// normal meaning everywhere (see DoomXR vk_openxrdevice.cpp).
//
// Anchors are computed from HmdPos and HmdYaw ONLY -- never HmdPitch/Roll.
// That is deliberate: pitch/roll come from looking up or down, and a holster
// anchored to full head orientation would swing away from the body every time
// the player looked at it. Yaw is the only rotation a real hip or shoulder
// actually follows.
//
// Calibration is one sample of standing eye height above the floor, not a menu
// flow. Every anchor height is a FRACTION of that number, so a 5'2" and a 6'4"
// player both get anchors on their own body rather than at some fixed offset
// tuned for one height.
//
// NOTE ON SHAPE: the holster table is an indexed accessor rather than an
// Array of structs, because ZScript dynamic arrays only accept integral and
// object types -- Array<SomeStruct> does not compile. Since the table is
// compile-time constant anyway, a switch costs nothing and allocates nothing.
//
// Scope: this owns calibration, anchors, and claims. It does not yet spawn
// holster props -- that is the next piece.

class RS_HolsterManager : EventHandler
{
	const HOLSTER_COUNT = 9;

	// Index 8: the chest ammo pouch (2026-08-25, for RS_Reload -- see its own
	// GetHolster case and updateClaims' GripClaimOff write below). NOT a
	// weapon holster like 0-7: nothing is ever stored here, so contents[8]
	// stays permanently null and the existing empty-slot handling in
	// updateProps already does the right thing (no prop, marker shows the
	// idle ring) with no special-casing needed there.
	const AMMO_POUCH_IDX = 8;

	// The 6 off-hand-anchored forearm/wrist hardpoints that used to occupy
	// indices 8-13 now live in their own mod, RS_HardPoints -- see README.md.
	// Both are designed to load at the same time.
	//
	// THEIR LEFTOVERS WERE REMOVED FROM THIS FILE ON 2026-08-28. Until then
	// this class still carried the whole hand-anchored path -- isHandAnchored,
	// handBasisPose, handAnchorPos, worldToHand, HAND_HOLSTER_START,
	// FOREARM_HOLSTER_END, FOREARM_YAW_CORRECTION -- none of it reachable,
	// because isHandAnchored was `idx >= 9` while HOLSTER_COUNT is 9. It was
	// kept for a while on the theory that dead code is harmless; it was not.
	// A pitch sign-convention bug was found sitting inside that dead path the
	// same day (the engine stores AttackPitch/OffhandPitch negated), which is
	// a bug nobody could ever have observed and everybody would have had to
	// re-derive the day those indices were switched back on. Every branch it
	// guarded resolved to its else, so removal was mechanical.
	//
	// If hand-anchored holsters are ever wanted here again, take them from
	// RS_HardPoints, where that rig actually runs and its math is exercised --
	// not from this file's history.

	// Doom's player scale puts a map unit at roughly one real inch (player
	// radius 16 ~ a person's half shoulder width), so these read as inches.
	//
	//   hsFwd    + is in FRONT of the eye plane, - is behind
	//   hsSide   + is the player's right
	//   hsFrac   height as a fraction of calibrated standing EYE height
	//   hsRadius grab radius, map units
	//
	// Everything is measured from the headset, which sits at your eyes -- the
	// FRONT of your head. That is why almost every hsFwd here is negative:
	// your chest, your back and your hips are all behind your own eyes. An
	// anchor at +fwd would float in front of your face.
	//
	// Heights are fractions of EYE height, not total height. Eye height is
	// about 0.93 of a person's stature, so these do not match the more
	// familiar stature-based proportions: shoulder is ~0.82 of stature but
	// ~0.88 of eye height.
	//
	// Front/back pairs are the tight ones -- a torso is only ~9-10 inches
	// deep, so pectoral and shoulderblade anchors are close enough that
	// oversized radii would overlap. They stay separable in practice because
	// the hand approaches a pectoral from the front and a blade from over the
	// shoulder, never from the same direction.
	// Hips only for now. The chest and shoulderblade anchors are removed
	// rather than commented out -- two working holsters beat six that get in
	// each other's way while the placement is still being tuned.
	//
	// Radius 3.0 = a 6 INCH WIDE catch volume. The marker sphere is drawn at
	// exactly this radius (MODELDEF Scale must match), so what you see is the
	// actual volume, not a decorative shell around it.
	// Orientation is PER HOLSTER, not global: a hip wants a gun hanging
	// barrel-down while a pectoral wants one lying flat across the chest at an
	// angle. One shared set of angles cannot serve both, so pitch/yaw/roll ride
	// in the table alongside position and are captured the same way -- from
	// your hand, in edit mode.
	// FIELD MEANING, all indices: hsFwd/hsSide are offsets from HmdPos along
	// bodyYaw's forward/right, hsFrac is a FRACTION of calibrated eye height
	// (so the rig scales to the player rather than to a fixed inch count),
	// and hsPitch/hsYaw/hsRoll are ABSOLUTE angles.
	//
	// This used to split at idx 9, where a second set of hand-relative
	// meanings took over for the forearm/wrist mounts. Those moved to
	// RS_HardPoints and the dead half was removed on 2026-08-28 -- see the
	// note on the constants at the top of this class.
	static void GetHolster(int idx, out string hsName, out double hsFwd, out double hsSide, out double hsFrac, out double hsRadius,
	                       out double hsPitch, out double hsYaw, out double hsRoll)
	{
		// sensible starting angles; every one of these is meant to be dragged
		hsPitch = 90.0; hsYaw = 0.0; hsRoll = 0.0;

		switch (idx)
		{
			// Hips: barrel straight down, the way a sidearm hangs.
			case 0:
				hsName = "HipLeft";   hsFwd = -2.0; hsSide = -9.0; hsFrac = 0.57; hsRadius = 3.0; break;
			case 1:
				hsName = "HipRight";  hsFwd = -2.0; hsSide =  9.0; hsFrac = 0.57; hsRadius = 3.0; break;

			// Head-side pair. TEMPORARILY PLACED IN FRONT (positive hsFwd) so
			// they are actually visible while being set up -- at their real
			// position beside the ears they sit in peripheral vision, which
			// makes them impossible to aim a hand at or confirm by eye.
			// Drag them back beside the head in edit mode once they work;
			// roughly hsFwd -2, hsSide +/-8 is where they belong.
			case 2:
				hsName = "HeadLeft";  hsFwd = 7.0; hsSide = -10.0; hsFrac = 0.95; hsRadius = 3.0; break;
			case 3:
				hsName = "HeadRight"; hsFwd = 7.0; hsSide =  10.0; hsFrac = 0.95; hsRadius = 3.0; break;

			// Pectorals: pistols and SMGs, lying flat against the chest,
			// angled down and outward rather than hanging vertically. Yaw
			// splits left/right so each points away from the centreline.
			// Barrel down, same as everything else -- no per-holster angle
			// worth the complexity right now. hsPitch/hsYaw/hsRoll default to
			// 90/0/0 at the top of this function already.
			case 4:
				hsName = "PectoralLeft";  hsFwd = -1.0; hsSide = -6.0; hsFrac = 0.78; hsRadius = 3.0; break;
			case 5:
				hsName = "PectoralRight"; hsFwd = -1.0; hsSide =  6.0; hsFrac = 0.78; hsRadius = 3.0; break;

			// Second hip pair -- the "2/4/6/8" tier's last step. Same depth
			// and height as the first hip pair, offset further out along
			// hsSide so the two sit side by side rather than overlapping:
			// radius 3.0 means each is a 6-inch catch volume, so two
			// centres 7 units apart leave a 1-inch gap between them, not a
			// shared boundary. Like the others, a starting guess meant to
			// be dragged into place, not a measured position.
			case 6:
				hsName = "HipLeft2";  hsFwd = -2.0; hsSide = -16.0; hsFrac = 0.57; hsRadius = 3.0; break;
			case 7:
				hsName = "HipRight2"; hsFwd = -2.0; hsSide =  16.0; hsFrac = 0.57; hsRadius = 3.0; break;

			// Chest ammo pouch (AMMO_POUCH_IDX), for RS_Reload -- NOT a
			// weapon holster, see that constant's own comment. Side 0: the
			// only laterally free space left on the torso, since 4/5
			// (PectoralLeft/Right) already span side -9..-3 and +3..+9 at
			// this same 0.78 eye-height. Dropped to frac 0.66 -- 0.12
			// eye-heights lower, ~7.7 inches on a 64" eye height against a
			// radii sum of 6.5 (3.5 here + 3.0 there) -- so the two volumes
			// stay clear rather than merely touching. Sternum-to-navel,
			// where a plate carrier's mag pouches actually sit. Radius 3.5
			// (a 7" catch volume, wider than a holster's 6") because you
			// reach for a mag pouch mid-fight without looking at it, unlike
			// a holster you reach for deliberately.
			default: // AMMO_POUCH_IDX, and a defensive fallback for idx >= HOLSTER_COUNT
				hsName = "AmmoPouch"; hsFwd = -1.0; hsSide = 0.0; hsFrac = 0.66; hsRadius = 3.5; break;
		}
	}

	// Keyed by player number rather than stored on the pawn: pawns are
	// destroyed and replaced on death and hub travel, and the calibration
	// measurement should not have to be retaken every time that happens.
	double eyeHeight[MAXPLAYERS];
	bool   calibrated[MAXPLAYERS];
	int    spawnTries[MAXPLAYERS];

	// Which holster each hand is currently inside, -1 for none. Recorded
	// during the claim pass so the swap acts on the holster the hand was in
	// at the moment of the grip press, rather than re-testing a tic later.
	int nearMain[MAXPLAYERS];
	int nearOff[MAXPLAYERS];

	// Whether THIS mod currently holds EACH hand's GripClaim* for the ammo
	// pouch (GRIPSUBJ_Pouch). Both hands, not just off -- the owner's own
	// framing: a gun is in EVERY hand as the baseline state here (dual
	// wielding, not a one-gun/one-empty-hand game), so reloading either
	// weapon means reaching in with the OTHER hand, and there is no hand
	// that starts out free. Tracked per hand so the clear on exit only ever
	// touches a value this mod itself set -- GripClaim* is shared with other
	// mods (RS_Reload, rs_hands' grab family), each claiming it for their
	// own reasons, and clearing it unconditionally on leaving the pouch
	// radius could stomp a claim that belongs to one of them.
	bool pouchClaimedMain[MAXPLAYERS];
	bool pouchClaimedOff[MAXPLAYERS];

	// ---- the grip arbiter -------------------------------------------------
	//
	// Third copy of this lookup, and it stays a copy. A shared client helper
	// would have to live in some file, and naming that file gives every
	// consumer a COMPILE-TIME dependency on it -- fatal and GLOBAL when it is
	// absent (thingdef.cpp:420-424 refuses every pk3 later in the load order).
	// The arbiter is a Service reachable by string precisely so neither side
	// ever names the other; three small lookups is what that costs.
	private Service arbiter;
	private int     arbWait;

	const RS_ARB_RETRY = 350;    // ~10s at 35Hz; only a miss re-arms it
	const RS_ARB_IDENT = 1;      // the arbiter's frozen IDENTITY, not its PROTOCOL
	// NOT A const -- ZScript has no Name constants (see rs_held.zs).
	// Inlined as a literal at each call site instead.

	private void ArbiterFind()
	{
		if (arbiter) return;
		if (arbWait > 0) { arbWait--; return; }

		ServiceIterator it = ServiceIterator.Find("RS_GripArbiterService");
		Service s;
		while (s = it.Next())
		{
			// ServiceIterator matches on a case-insensitive SUBSTRING, so a hit
			// proves nothing -- ask for something only the arbiter answers.
			if (s.GetInt("grip.hello", "", 0, 0, null, 'None') != RS_ARB_IDENT)
				continue;
			arbiter = s;
			break;
		}

		if (!arbiter) arbWait = RS_ARB_RETRY;
	}

	// The real weapon each hand held before ammo-pouch business took it
	// over, null when nothing is currently suppressed. Watches the CLAIM
	// broadly (GripClaim* != GRIPSUBJ_None), not just whether THIS mod still
	// owns it -- so if a reload sequence takes the claim over from the pouch
	// entry itself (still holding a loose round, still holding a magazine,
	// mid-transfer to the other hand's gun), the real weapon stays a fist
	// through all of that and only comes back once the hand is genuinely
	// free again, whichever mod last let go of the claim.
	Array<Weapon> pouchPreviousMain;
	Array<Weapon> pouchPreviousOff;

	// Holster index awaiting an auto-diagnostic dump, -1 for none. Set by
	// doSwap right after a store; consumed one tic later in WorldTick, AFTER
	// updateClaims (and the updateProps it calls) has actually repositioned
	// the prop for the new contents. Dumping inside doSwap itself would print
	// the PREVIOUS tic's prop position -- correct orientation numbers (those
	// are computed fresh from the weapon class) but a stale/misleading
	// "actual pos vs sphere" line, since that part only updates on
	// WorldTick's own pass, not the instant contents[] changes.
	int pendingDump[MAXPLAYERS];

	// Contents by holster index, flattened to one array because ZScript has
	// no 2D dynamic arrays: index as (player * HOLSTER_COUNT + holster).
	// Null means the holster holds nothing, which reads to the player as
	// holding fists -- the fist is never stored, it is what empty looks like.
	//
	// INSTANCE POINTERS, not class-name strings (was Array<string> until the
	// "can't holster it again" bug: two same-class weapons -- e.g. a matched
	// pair, one per hand -- made the updateProps reconciliation below match
	// by class name, so the OTHER hand's identical-class weapon looked like
	// "the stored one drifted back into a hand" and the table wiped a slot
	// that still legitimately held a different instance. GZDoom nulls out an
	// Actor-typed field automatically when the actor it points to is
	// destroyed, so storing the pointer directly also means "gone from
	// inventory" is just contents[slot] reading null -- no FindInventory
	// lookup needed to detect it either.
	Array<Weapon> contents;

	// Split per-hand, but doSwap below still enforces the per-PLAYER
	// (shared) gate too whenever instant switch is off -- read that
	// function's comment before changing either of these back to one
	// array. Short version of why one array alone was wrong either way:
	// a single per-player value drops a genuinely-simultaneous two-hand
	// press outright (the bug this split fixes), but a naive per-hand
	// split reintroduces an OLDER, already-found bug -- player.PendingWeapon
	// is a SINGLE field shared by both hands, consumed hand-blind by
	// BringUpWeapon, and with instant switch off (~16-tic lower/raise) an
	// off-hand store landing while the main hand's switch is still
	// resolving overwrote it out from under that switch, so it completed
	// into the WRONG hand and the main hand's weapon was never actually
	// put away.
	int lastSwapTicMain[MAXPLAYERS];
	int lastSwapTicOff[MAXPLAYERS];

	// HOW LONG player.PendingWeapon HAS BEEN STUCK, so a genuinely aborted
	// switch can be told apart from an ordinary one still in flight and
	// actively RECOVERED rather than waited out forever.
	//
	// Proven in a real session, not theorised: a third-party weapon's own
	// Deselect state looped on itself and the engine's own recursion guard
	// killed it mid-transition -- "Recursive weapon state loop in
	// 'X.5' -- aborted at depth 65". Refusing to trust the hand while that
	// is true (doSwap's own guard, added first) was correct as far as it
	// went, but it assumed the switch would eventually settle on its own.
	// It does not: PendingWeapon was still stuck six presses and two real
	// interactions later in the session that proved this. Waiting is not a
	// strategy for a switch this broken; recovering is.
	int pendingStuckTics[MAXPLAYERS];

	// One prop per holster per player, flattened like contents. Held as
	// pointers so a destroyed prop (level change, player death) reads null and
	// gets respawned rather than leaving a dangling anchor.
	Array<RS_HolsterProp> props;
	Array<RS_HolsterMarker> markers;

	// ---- live offsets ----
	// The switch in GetHolster is the DEFAULT table; these are what anchorPos
	// actually reads, seeded from it once. Edit mode writes here, so a holster
	// can be dragged to where it belongs on a real body instead of being
	// guessed at from proportion tables. Not per-player: this is a tuning
	// surface for one person wearing the headset, not gameplay state.
	double edFwd[HOLSTER_COUNT];
	double edSide[HOLSTER_COUNT];
	double edFrac[HOLSTER_COUNT];
	// Orientation lives here too, so a hip and a pectoral can hold a weapon at
	// completely different angles. Captured from the hand while dragging: point
	// your hand the way the gun should sit and drop it.
	double edPitch[HOLSTER_COUNT];
	double edYaw[HOLSTER_COUNT];
	double edRoll[HOLSTER_COUNT];
	bool   edInit;

	// Not per-player, same reason edFwd etc. are not: one person wears the
	// headset. Set by saveProfile/loadProfile whenever the name is "seated"
	// or "standing" -- the two names switchProfile() toggles between -- so a
	// switch always flips AWAY from whichever of the two you last touched by
	// any means (a dedicated Save/Load button, not just the toggle itself).
	string activeProfile;

	// PER PLAYER as of 2026-08-26, where all three used to be one global
	// each. The edit TABLE above stays deliberately global -- one person
	// wears the headset, and there is one set of anchors to tune -- but
	// "is this player editing" and "which sphere is this hand dragging"
	// are not tuning values, they are live per-hand state. As single
	// globals, a second player toggling edit mode dropped the first
	// player's sphere mid-drag, and either player's grab overwrote the
	// other's. Mirrored from RS_HardPoints in the same pass.
	//
	// int arrays default to 0, a VALID holster index -- exactly the trap
	// nearMain/nearOff document further up -- so grabbedMain/grabbedOff MUST
	// be seeded to -1 before updateGrabs ever reads them. ensureEdit does
	// that, and updateGrabs now calls ensureEdit first for precisely that
	// reason: previously the zero-default meant the first calibrated tic
	// dragged holster 0 to wherever the main hand happened to be, and only
	// anchorPos' own ensureEdit call (which runs later in the same tic)
	// undid it.
	bool editMode[MAXPLAYERS];
	int  grabbedMain[MAXPLAYERS];  // holster index being dragged, -1 for none
	int  grabbedOff[MAXPLAYERS];

	// ---- body yaw ----
	// Anchors follow THIS, not HmdYaw directly. Your hips do not counter-rotate
	// every time you glance sideways, and neither should a holster: driving
	// them straight off head yaw means a head shake whips them around the body.
	//
	// Two separate defences, because there are two separate problems:
	//
	//  1. NECK RANGE. Within +/- BODY_YAW_DEADZONE of where the body faces,
	//     head rotation moves nothing at all. That is a real person turning
	//     their head without turning their torso.
	//  2. PITCH DEGENERACY. Yaw stops meaning anything useful when you look
	//     near-vertical -- at straight down, a tiny head movement swings yaw
	//     wildly. Past BODY_YAW_MAX_PITCH the body simply stops tracking, which
	//     is the specific fix for "look down and shake, holsters go bananas".
	double bodyYaw[MAXPLAYERS];
	bool   bodyYawInit[MAXPLAYERS];
	// Last seen controller-turn total, to difference against. Tracked rather
	// than read absolutely because only the CHANGE should move the body.
	double lastTurnYaw[MAXPLAYERS];

	const BODY_YAW_DEADZONE  = 50.0;  // degrees of free head turn
	const BODY_YAW_FOLLOW    = 0.15;  // catch-up rate past the deadzone
	const BODY_YAW_MAX_PITCH = 55.0;  // stop tracking beyond this head pitch

	// SLOW_SWAP_COOLDOWN (20, not 12): a default A_Lower needs (WEAPONBOTTOM 128
	// - WEAPONTOP 32) / 6 = 16 tics to finish before BringUpWeapon runs, so at
	// 12 the cooldown expired while ReadyWeapon was STILL the gun being put
	// away. The next store then read that stale weapon as "held" and the
	// dedupe pass wiped the holster it had just gone into -- the gun appeared
	// to hop between holsters and leave the first one empty.
	//
	// FAST_SWAP_COOLDOWN (4) is what actually applies whenever instant switch
	// is on (see swapCooldown() below): the whole reason for the 16-tic wait
	// stops existing once CF_INSTANTWEAPSWITCH makes A_Lower/BringUpWeapon
	// resolve in the SAME tic they are called, not 16 tics later. 4 is pure
	// debounce against one physical press registering as two, not animation
	// settling -- and it is what makes two-hand near-simultaneous store/draw
	// actually work, instead of the second hand eating the first hand's
	// cooldown window for an animation that, with instant switch on, does not
	// even happen.
	const SLOW_SWAP_COOLDOWN = 20;
	const FAST_SWAP_COOLDOWN = 4;
	const CLAIM_HYSTERESIS = 1.4;   // exit radius multiplier; see updateClaims
	const CALIBRATE_MAX_TRIES = 35; // ~1 second, then stop rather than loop forever
	const EYE_MIN = 36.0;           // sanity floor, map units (~3 feet)
	const EYE_MAX = 96.0;           // sanity ceiling (~8 feet)

	override void WorldTick()
	{
		// Once per tic, not once per player: the handle is a property of the
		// loaded pk3 set, not of any player.
		ArbiterFind();

		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			if (!playeringame[i] || players[i].mo == null)
				continue;

			PlayerPawn pawn = players[i].mo;

			if (!calibrated[i])
			{
				bool wasCalibrated = calibrated[i];
				tryCalibrate(i, pawn);
				// int arrays default to 0, a VALID holster index -- not -1.
				// Reset right on the transition into calibrated, once, so the
				// very first WorldTick pass after calibration can't misread a
				// zero-default as "holster 0 has a pending dump" and print an
				// empty auto-dump header before anything has ever been stored.
				// nearMain/nearOff need the exact same reset and, until now,
				// never got one: a grip-bound key pressed before this tic (or
				// any time after ForceRecalibrate, which does not touch these
				// either) could doSwap against holster 0 with updateClaims
				// never having run a single proximity test.
				if (calibrated[i] && !wasCalibrated)
				{
					pendingDump[i] = -1;
					nearMain[i] = -1;
					nearOff[i] = -1;
				}
				continue; // no anchors, no claims, until calibration lands
			}

			// STUCK-SWITCH RECOVERY. See the field comment on
			// pendingStuckTics for why this exists and why "wait" is not
			// enough on its own -- doSwap's own guard already refuses to
			// touch a hand mid-switch, which is correct, but it needs
			// something that actually MOVES the switch forward, since this
			// specific failure mode does not resolve on its own.
			// Only a LIVE player with the fire buttons up can have a switch
			// that is genuinely stuck. CheckWeaponChange waits for
			// A_WeaponReady, so held fire (A_ReFire loops) and a long
			// third-party reload keep PendingWeapon set for as long as they
			// like -- and a corpse keeps it set forever, with BringUpWeapon
			// having no PST_LIVE guard of its own.
			bool switchCanSettle = pawn.player.playerstate == PST_LIVE && pawn.health > 0
				&& !(pawn.player.cmd.buttons & (BT_ATTACK | BT_ALTATTACK | BT_OFFHANDATTACK | BT_OFFHANDALTATTACK));
			if (pawn.player.PendingWeapon != WP_NOCHANGE && switchCanSettle)
			{
				pendingStuckTics[i]++;

				// STUCK_THRESHOLD = 70 tics, ~2 real seconds. Comfortably
				// longer than any legitimate lower/raise cycle -- even the
				// ~16-tic non-instant path this file's own comments cite --
				// so this never fires mid a healthy switch and reliably
				// fires once one has genuinely stopped moving.
				if (pendingStuckTics[i] > 70)
				{
					// BringUpWeapon (player.zs:1958) is the engine's own
					// recovery tool, not something invented here: given a
					// stuck PendingWeapon, it reads that target weapon,
					// clears PendingWeapon to WP_NOCHANGE, and drives the
					// psprite straight to the target's ready state --
					// bypassing whatever broken Deselect/Lower chain the
					// OLD weapon never finished, rather than trying to
					// coax it to completion. Exactly the shape of recovery
					// this needs: it does not fix the third-party weapon's
					// own broken states, it routes around them.
					pawn.BringUpWeapon();
					pendingStuckTics[i] = 0;

					if (verboseDiag())
						Console.Printf("RS_HOLSTER: forced a stuck weapon switch to resolve (BringUpWeapon)");
				}
			}
			else
			{
				pendingStuckTics[i] = 0;
			}

			updateBodyYaw(i, pawn);
			updateGrabs(i, pawn);
			updateClaims(i, pawn); // also repositions props, via updateProps

			// Consume a dump queued by last tic's store, now that this tic's
			// updateClaims has actually moved the prop into place.
			if (pendingDump[i] >= 0)
			{
				Console.Printf("\c[Gold]--- RS_HOLSTER auto (stored) ---");
				dumpOneHolsterProp(i, pawn, pendingDump[i]);
				pendingDump[i] = -1;
			}
		}
	}

	// ------------------------------------------------------------------
	// LIFECYCLE. THERE WAS NONE OF THIS AT ALL until 2026-08-26 -- the only
	// overrides this class had were WorldTick and NetworkProcess -- and the
	// consequences were not cosmetic.
	//
	// This handler is registered through MAPINFO's AddEventHandlers, which
	// makes it a PER-LEVEL handler: a new instance is constructed for every
	// map, so every field here (contents[], the edit table, eyeHeight[],
	// activeProfile) is wiped on any level change. The WEAPONS are not wiped
	// -- they travel with the player. So a holstered weapon crossed the exit
	// line still carrying bHolsterHidden = true, with the only code that ever
	// clears it left behind on the previous map. What that flag does is
	// documented in doSwap below: CheckAmmo refuses to let a bHolsterHidden
	// weapon FIRE, and refuses to let weapnext/weapprev or slot-select reach
	// it. Nothing else anywhere clears it. Every weapon you were carrying in
	// a holster when you took the exit was permanently, silently bricked --
	// still in inventory, un-fireable, unreachable, for the rest of the run.
	//
	// The same absence showed up on death: contents[] and pouchPrevious* kept
	// pointing at the corpse's weapons, and the props kept displaying them.
	// pouchPrevious was the worse of the two -- updatePouchClaim's restore
	// branch fires whenever the hand is unclaimed and prev is non-null, and
	// on the first tic after a respawn a brand new pawn is unclaimed by
	// definition, so it tried to move a dead body's weapon into a living
	// player's hand.
	//
	// SCOPE NOTE for whoever is building the grip arbiter: nothing here
	// changes how pouchPrevious*/GripClaim* WORK. releasePlayer only nulls
	// stale pointers at the two moments the pawn they belong to stops
	// existing. Leave updatePouchClaim itself alone.
	// ------------------------------------------------------------------

	// The pawn is gone or going. Hand every holstered weapon back its flags
	// while the pointers are still good, then forget them.
	override void PlayerDied(PlayerEvent e)
	{
		releasePlayer(e.PlayerNumber, true);
	}

	// A brand new pawn with a brand new inventory. The old contents[] and
	// pouchPrevious* pointers describe weapons that are not this player's any
	// more, and re-measuring eye height is right anyway -- a respawn point can
	// sit at a different floor height than the one calibration was taken at,
	// and every anchor here is placed as a fraction of that measurement.
	override void PlayerRespawned(PlayerEvent e)
	{
		releasePlayer(e.PlayerNumber, true);

		// Destroyed rather than left to be repositioned. ForceRecalibrate
		// below makes WorldTick take its `continue` branch until the new eye
		// height lands (up to CALIBRATE_MAX_TRIES, about a second), and
		// updateProps does not run during that window -- so the existing
		// props and markers would hang in the air at the corpse's last anchor
		// positions for that whole second. updateProps respawns any that read
		// null the first time it does run.
		despawnPlayerActors(e.PlayerNumber);
		ForceRecalibrate(e.PlayerNumber);
	}

	// updateProps only ever runs for players with playeringame[i] set, so a
	// disconnecting player's props and markers simply stop being touched --
	// they do not stop EXISTING. Nine props plus nine markers per player were
	// left parked and visible at whatever world position they last held.
	override void PlayerDisconnected(PlayerEvent e)
	{
		releasePlayer(e.PlayerNumber, true);
		despawnPlayerActors(e.PlayerNumber);
	}

	// Leaving the level: unflag everything BEFORE this handler (and its
	// contents[] table) ceases to exist, which is the only moment the mapping
	// from weapon to "is holstered" still exists at all.
	// The handler is rebuilt per map and int arrays start at 0 -- which is
	// HipLeft, not "no holster". Until calibration lands (up to a second)
	// nothing else writes these, and NetworkProcess is live the whole time.
	override void OnRegister()
	{
		for (int p = 0; p < MAXPLAYERS; ++p)
		{
			nearMain[p]    = -1;
			nearOff[p]     = -1;
			pendingDump[p] = -1;
			grabbedMain[p] = -1;
			grabbedOff[p]  = -1;
		}
	}

	override void WorldUnloaded(WorldEvent e)
	{
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			// THE PAWN TRAVELS, THIS HANDLER DOES NOT. Everything below
			// releasePlayer touches is ours and dies with us; the claim
			// fields live on the pawn and the engine never clears them. A
			// hand resting in the pouch at the exit therefore arrived on the
			// next map still claimed GRIPSUBJ_Pouch with no handler that
			// remembered making the claim -- so it never released, the next
			// pouch entry swapped a fist in, and nothing ever swapped it back
			// out. Stale HolsterClaim* meanwhile kept the engine emitting
			// anchor-grip pulses through the new map's calibration window.
			if (playeringame[i] && players[i].mo)
				releaseTravellingClaims(i, players[i].mo);
			releasePlayer(i, true);
			despawnPlayerActors(i);
		}
	}

	// Drop the pawn-side state this handler owns before the pawn leaves:
	// holster claims, our pouch grip claims (and the arbiter lease behind
	// them), and the weapon the pouch swapped out -- which goes back into
	// the hand now, because pouchPrevious* is about to be forgotten.
	private void releaseTravellingClaims(int i, PlayerPawn pawn)
	{
		pawn.HolsterClaimMain = false;
		pawn.HolsterClaimOff  = false;

		ensurePouchPrevious();
		for (int hand = 0; hand < 2; ++hand)
		{
			bool isMain = (hand == 0);
			bool claimedByUs = isMain ? pouchClaimedMain[i] : pouchClaimedOff[i];
			if (claimedByUs)
			{
				bool ours;
				if (arbiter)
					ours = arbiter.GetInt("grip.mine", "", hand, 0, pawn, 'RS_Holsters') == 1;
				else
					ours = (isMain ? pawn.GripClaimMain : pawn.GripClaimOff) == GRIPSUBJ_Pouch;
				if (ours)
				{
					if (isMain) pawn.GripClaimMain = GRIPSUBJ_None;
					else        pawn.GripClaimOff  = GRIPSUBJ_None;
				}
				if (arbiter)
					arbiter.GetInt("grip.release", "", hand, 0, pawn, 'RS_Holsters');
			}

			Weapon prev = isMain ? pouchPreviousMain[i] : pouchPreviousOff[i];
			if (prev != null)
				moveWeaponInstant(pawn, prev, hand);
		}
	}

	override void WorldLoaded(WorldEvent e)
	{
		// A savegame restores this handler's OWN fields, contents[] included,
		// so the weapons it describes are legitimately still holstered and the
		// sweep below would wrongly un-holster every one of them. Only a
		// genuinely fresh level needs any of this.
		if (e.IsSaveGame)
			return;

		// The backstop for the bricking described above. WorldUnloaded is the
		// primary fix, but it cannot help a weapon stowed by a build (or a
		// session) from before any of this existed, and it never runs at all
		// on the first map of a session. Sweeping inventory here catches both.
		// Safe to run against weapons this mod never holstered: at this point
		// contents[] is empty for every player, so "holstered" is a state
		// nothing on this map claims -- including RS_HardPoints, whose own
		// table was wiped by the very same level change.
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			if (!playeringame[i] || players[i].mo == null)
				continue;
			unstowInventory(players[i].mo);
		}

		// And the tuned profile, which until now had to be reloaded by hand
		// after EVERY map change -- edInit is a per-level field, so ensureEdit
		// reseeded the placeholder table from GetHolster's switch on every
		// level load and threw away whatever the player had dragged and saved.
		// A profile that only survives until the next door is not persistence.
		autoLoadProfile();
	}

	// Give every weapon this player owns its ordinary flags back. Walks
	// inventory rather than contents[], deliberately: the whole failure this
	// exists for is a weapon whose holstering manager no longer exists to be
	// asked. Same walk findFist does.
	private void unstowInventory(PlayerPawn pawn)
	{
		for (Inventory item = pawn.Inv; item != null; item = item.Inv)
		{
			let w = Weapon(item);
			if (w == null)
				continue;
			if (!w.bHolsterHidden)
				continue;
			w.bNoAutoSwitchTo = w.Default.bNoAutoSwitchTo;
			w.bHolsterHidden = false;
		}
	}

	// Empty one player's tables. unflag=false exists for the case where the
	// pointers are known to be stale rather than merely finished with; every
	// current caller passes true, since GZDoom nulls an Actor-typed field
	// automatically once the actor is destroyed, so a stale pointer already
	// reads null here and the flag write never happens.
	private void releasePlayer(int i, bool unflag)
	{
		if (i < 0 || i >= MAXPLAYERS)
			return;

		ensureContents();
		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			int ci = (i * HOLSTER_COUNT) + h;
			let w = contents[ci];
			if (w != null && unflag)
			{
				w.bNoAutoSwitchTo = w.Default.bNoAutoSwitchTo;
				w.bHolsterHidden = false;
			}
			contents[ci] = null;
		}

		// -1, not 0: these are holster indices, and their int zero-default is
		// a VALID index. See WorldTick's own note on the same trap.
		nearMain[i] = -1;
		nearOff[i] = -1;
		pendingDump[i] = -1;

		// The ammo-pouch backup pointers, nulled for the reason given in the
		// block comment above: left set across a death they name a corpse's
		// weapon, and updatePouchClaim's restore branch runs on the first tic
		// after respawn (a fresh pawn has GripClaim* at GRIPSUBJ_None, so
		// "hand is free" is true) and tries to seat it. Only the pointers are
		// touched -- the claim protocol itself is the grip arbiter's, not
		// this pass's.
		ensurePouchPrevious();
		pouchPreviousMain[i] = null;
		pouchPreviousOff[i] = null;

		// The matching "did WE claim it" bookkeeping. Left true across a
		// respawn, updatePouchClaim's exit branch would fire once against the
		// new pawn and clear a GripClaim* value that a completely different
		// system may by then have set -- which is precisely the stomp the
		// pouchClaimed* flags exist to prevent.
		pouchClaimedMain[i] = false;
		pouchClaimedOff[i] = false;
		// Re-seed body yaw from the head on the next calibrated tic. A
		// respawned pawn faces its spawn spot while bodyYaw still held the
		// corpse's facing, and the neck deadzone only ever follows the
		// EXCESS, so the anchors converged to 50 degrees off and stayed.
		bodyYawInit[i] = false;
	}

	// Destroy this player's props and markers. updateProps respawns any that
	// are null the next time it runs for a live player, so this is safe to
	// call on a player who might come back.
	private void despawnPlayerActors(int i)
	{
		if (i < 0 || i >= MAXPLAYERS)
			return;

		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			int pi = (i * HOLSTER_COUNT) + h;
			if (pi < props.Size() && props[pi] != null)
			{
				props[pi].Destroy();
				props[pi] = null;
			}
			if (pi < markers.Size() && markers[pi] != null)
			{
				markers[pi].Destroy();
				markers[pi] = null;
			}
		}
	}

	// Pull a saved profile in on level load, quietly.
	//
	// STANDING FIRST, then seated, and that order is switchProfile's own
	// convention rather than a new decision: activeProfile starts empty every
	// level (it is a per-level field like everything else here), and
	// switchProfile already documents that an empty activeProfile falls to
	// the standing branch. Loading standing therefore leaves the toggle
	// exactly where a player who has not touched it expects it. A seated
	// player presses SWITCH once per map, which is strictly better than the
	// old behaviour of losing the whole tuned table every map.
	//
	// The two-step (test with the native, then go through loadProfile) is
	// there so a player who has never saved a profile does not get a red "no
	// profile on disk" line -- twice -- on every single map change for the
	// rest of the run. level.JSONProfileLoad is idempotent (it clears its
	// buffer and re-parses the same file), so the retry costs one extra read
	// of a file measured in hundreds of bytes and buys the ordinary case a
	// silent no-op. Going through loadProfile rather than reading keys here
	// keeps ONE copy of the per-field GetHolster fallback logic, and lets it
	// set activeProfile the same way every other load does.
	private void autoLoadProfile()
	{
		ensureEdit();
		if (level.JSONProfileLoad("holster_standing"))
		{
			loadProfile("holster_standing");
			return;
		}
		if (level.JSONProfileLoad("holster_seated"))
			loadProfile("holster_seated");
	}

	// One-shot sample of standing eye height. Retried rather than taken
	// immediately because the pawn can still be mid-drop on its first tics,
	// and because HmdPos reads as a zero vector until the VR backend has
	// written a pose at least once.
	private void tryCalibrate(int i, PlayerPawn pawn)
	{
		spawnTries[i]++;
		if (spawnTries[i] > CALIBRATE_MAX_TRIES)
		{
			// NO HEAD POSE, NO HOLSTERS. HmdPos is written only by the OpenXR
			// backend in single player; on a desktop session, the GL/OpenVR
			// backend, or any netgame it stays (0,0,0) forever. Calibrating
			// anyway parked all nine anchors around the map origin and kept
			// nine bright markers and nine props hovering there all level.
			if (pawn.HmdPos.Length() == 0)
			{
				if (verboseDiag())
					Console.Printf("RS_HOLSTER: no head pose after %d tics -- holsters stay off this map", spawnTries[i]);
				return;
			}
			// Never got a plausible reading. Fall back to the pawn's own
			// height so holsters still exist, rather than silently doing
			// nothing forever with no indication why.
			eyeHeight[i] = pawn.Height * 0.9;
			calibrated[i] = true;
			if (verboseDiag())
				Console.Printf("RS_HOLSTER: calibration timed out, using fallback eye height %.1f", eyeHeight[i]);
			return;
		}

		// A zero HmdPos means the VR backend has not written a head pose into
		// the field yet -- distinct from "the player is standing somewhere
		// implausible". Called out separately because it is the failure that
		// looks identical to "nothing is happening" from the outside.
		if (pawn.HmdPos.Length() == 0)
		{
			if (spawnTries[i] == CALIBRATE_MAX_TRIES)
				Console.Printf("\cgRS_HOLSTER: HmdPos is zero -- engine is not writing head pose. Holsters cannot work.");
			return;
		}

		double measured = pawn.HmdPos.Z - pawn.floorz;
		if (measured < EYE_MIN || measured > EYE_MAX)
		{
			if (spawnTries[i] == CALIBRATE_MAX_TRIES)
				Console.Printf("\cgRS_HOLSTER: eye height %.1f outside sane range %.0f-%.0f (HmdPos.Z %.1f, floor %.1f)",
					measured, EYE_MIN, EYE_MAX, pawn.HmdPos.Z, pawn.floorz);
			return;
		}

		eyeHeight[i] = measured;
		calibrated[i] = true;
		if (verboseDiag())
			Console.Printf("RS_HOLSTER: calibrated standing eye height %.1f map units", measured);
	}

	// For a bindable recalibrate command (sat down during the auto sample,
	// playspace floor changed).
	void ForceRecalibrate(int playerNum)
	{
		if (playerNum < 0 || playerNum >= MAXPLAYERS)
			return;
		calibrated[playerNum] = false;
		spawnTries[playerNum] = 0;

		// WorldTick skips updateClaims for the whole resample window, so
		// whatever these held on the last calibrated tic would otherwise
		// stay live: the engine keeps arming F13/F14 off a stale
		// HolsterClaim, and NetworkProcess would doSwap against a holster
		// the hand may have left a second ago.
		nearMain[playerNum]    = -1;
		nearOff[playerNum]     = -1;
		grabbedMain[playerNum] = -1;
		grabbedOff[playerNum]  = -1;
		if (playeringame[playerNum] && players[playerNum].mo)
		{
			players[playerNum].mo.HolsterClaimMain = false;
			players[playerNum].mo.HolsterClaimOff  = false;
		}
	}

	// Seed the live offsets from the default table, once.
	private void ensureEdit()
	{
		if (edInit)
			return;
		edInit = true;
		// -1 for every player, not just the console one: int arrays default
		// to 0, which is holster 0, so an unseeded entry reads as "this hand
		// is dragging HipLeft" the first time updateGrabs looks at it.
		for (int p = 0; p < MAXPLAYERS; ++p)
		{
			grabbedMain[p] = -1;
			grabbedOff[p] = -1;
		}
		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
			GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);
			edFwd[h] = hsFwd;
			edSide[h] = hsSide;
			edFrac[h] = hsFrac;
			edPitch[h] = hsPitch;
			edYaw[h] = hsYaw;
			edRoll[h] = hsRoll;
		}
	}

	// Advance the body's facing toward the head's, the way a torso actually
	// follows a neck. Called once per tic, before anchors are computed.
	private void updateBodyYaw(int i, PlayerPawn pawn)
	{
		if (!bodyYawInit[i])
		{
			bodyYawInit[i] = true;
			bodyYaw[i] = pawn.HmdYaw;
			lastTurnYaw[i] = pawn.VRTurnYaw;
			return;
		}

		// CONTROLLER TURN MOVES THE BODY 1:1, no deadzone, no smoothing.
		//
		// Snap turn and stick turn rotate the whole virtual body -- your hips
		// went with it, because nothing physical happened at all. Feeding that
		// through the neck deadzone was the drift: a 45 degree snap fits inside
		// a 50 degree deadzone, so the body refused to follow, and every snap
		// left the holsters a little further behind where the body actually
		// faced. It never recovered because each snap was individually "within
		// neck range".
		double turnDelta = normalizeDeg(pawn.VRTurnYaw - lastTurnYaw[i]);
		lastTurnYaw[i] = pawn.VRTurnYaw;
		if (turnDelta != 0)
			bodyYaw[i] = normalizeDeg(bodyYaw[i] + turnDelta);

		// Yaw is meaningless near-vertical: looking straight down, a small head
		// movement swings it wildly. Freeze rather than chase the noise.
		if (abs(pawn.HmdPitch) > BODY_YAW_MAX_PITCH)
			return;

		// Shortest signed difference, written out by hand -- deltaangle() is
		// not callable as a free function from a plain Object like this one.
		double d = pawn.HmdYaw - bodyYaw[i];
		while (d >  180.0) { d -= 360.0; }
		while (d < -180.0) { d += 360.0; }

		// Inside the neck's range the body does not move at all. This is what
		// makes a head shake cost nothing.
		if (abs(d) <= BODY_YAW_DEADZONE)
			return;

		// Past it, follow only the EXCESS, and only partway per tic, so the
		// body eases around instead of snapping.
		double excess = (d > 0) ? (d - BODY_YAW_DEADZONE) : (d + BODY_YAW_DEADZONE);
		bodyYaw[i] += excess * BODY_YAW_FOLLOW;

		while (bodyYaw[i] >  360.0) { bodyYaw[i] -= 360.0; }
		while (bodyYaw[i] < -360.0) { bodyYaw[i] += 360.0; }
	}

	// World-space position of one holster anchor for this player.
	private Vector3 anchorPos(int i, PlayerPawn pawn, int idx)
	{
		ensureEdit();

		// bodyYaw, NOT HmdYaw: anchors hang off the torso's facing so they do
		// not whip around when the head turns. ZScript's cos/sin take DEGREES.
		double yaw = bodyYaw[i];
		double fx = cos(yaw), fy = sin(yaw);   // forward vector
		double rx = sin(yaw), ry = -cos(yaw);  // player's right: yaw - 90 degrees

		double floorZ = pawn.HmdPos.Z - eyeHeight[i];

		return (
			pawn.HmdPos.X + (edFwd[idx] * fx) + (edSide[idx] * rx),
			pawn.HmdPos.Y + (edFwd[idx] * fy) + (edSide[idx] * ry),
			floorZ + (eyeHeight[i] * edFrac[idx])
		);
	}

	// The inverse of anchorPos: take a world point (a hand) and express it in
	// the same body-local numbers the table uses. This is what makes edit mode
	// work -- drag a sphere to where it belongs and read the offsets straight
	// back out, rather than deriving them from proportions and hoping.
	private void worldToBody(int i, PlayerPawn pawn, Vector3 world, out double oFwd, out double oSide, out double oFrac)
	{
		// Same frame anchorPos uses -- bodyYaw, not HmdYaw. Mixing the two
		// would make a dragged holster land somewhere other than the hand.
		double yaw = bodyYaw[i];
		double fx = cos(yaw), fy = sin(yaw);
		double rx = sin(yaw), ry = -cos(yaw);

		double dx = world.X - pawn.HmdPos.X;
		double dy = world.Y - pawn.HmdPos.Y;

		oFwd  = (dx * fx) + (dy * fy);
		oSide = (dx * rx) + (dy * ry);

		double floorZ = pawn.HmdPos.Z - eyeHeight[i];
		oFrac = (eyeHeight[i] != 0) ? ((world.Z - floorZ) / eyeHeight[i]) : 0.0;
	}

	// While a holster is grabbed, it simply lives wherever that hand is.
	private void updateGrabs(int i, PlayerPawn pawn)
	{
		// FIRST, before either array is read. grabbedMain/grabbedOff are int
		// arrays, so their zero-default is holster 0 rather than "nothing" --
		// see their declaration. WorldTick calls this BEFORE updateClaims,
		// which is the only other thing that reaches ensureEdit (via
		// anchorPos), so without this the very first calibrated tic dragged
		// HipLeft to wherever the main hand was.
		ensureEdit();

		int gm = grabbedMain[i];
		int go = grabbedOff[i];

		// POSITION ONLY. A holster is placed by holding your hand where the
		// gun goes and letting go. Orientation is the table's (hsPitch 90:
		// barrel straight down along the body) for every anchor -- the earlier
		// build also captured the hand's pitch/yaw/roll at drop time, which
		// left each holster holding its weapon at whatever angle the wrist
		// happened to be at, and that is not a feature anyone asked for.
		if (gm >= 0)
			worldToBody(i, pawn, pawn.AttackPos, edFwd[gm], edSide[gm], edFrac[gm]);
		if (go >= 0)
			worldToBody(i, pawn, pawn.OffhandPos, edFwd[go], edSide[go], edFrac[go]);
	}

	private static double normalizeDeg(double d)
	{
		while (d >  180.0) { d -= 360.0; }
		while (d < -180.0) { d += 360.0; }
		return d;
	}

	// Prints the live table as a ready-to-paste replacement for GetHolster's
	// switch. The whole point of edit mode: tune it on a body, then bake it.
	private void dumpTable()
	{
		Console.Printf("\c[Gold]--- RS_HOLSTER TABLE (paste over GetHolster's switch) ---");
		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
			GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);
			Console.Printf("case %d: hsName = \"%s\"; hsFwd = %.2f; hsSide = %.2f; hsFrac = %.3f; hsRadius = %.1f; hsPitch = %.1f; hsYaw = %.1f; hsRoll = %.1f; break;",
				h, hsName, edFwd[h], edSide[h], edFrac[h], hsRadius, edPitch[h], edYaw[h], edRoll[h]);
		}
	}

	// Real persistence, replacing "read the console dump, hand-paste it into
	// GetHolster's switch, recompile". A profile is a flat JSON document keyed
	// "h<index>_<field>" -- level.JSONProfile* (E:\UZDXREMA
	// src\scripting\vmthunks.cpp) is the ONLY file I/O ZScript has; it does not
	// parse JSON on the script side, so a flat key/double shape is what the
	// native protocol supports, not a design choice made here.
	//
	// name is not sanitized here -- the native refuses anything outside
	// [A-Za-z0-9_-] on its own and returns false, which both callers already
	// report to the console.
	private void saveProfile(string name)
	{
		ensureEdit();
		level.JSONProfileBegin();
		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			string key = String.Format("h%d_", h);
			level.JSONProfileSetDouble(key .. "fwd",   edFwd[h]);
			level.JSONProfileSetDouble(key .. "side",  edSide[h]);
			level.JSONProfileSetDouble(key .. "frac",  edFrac[h]);
			level.JSONProfileSetDouble(key .. "pitch", edPitch[h]);
			level.JSONProfileSetDouble(key .. "yaw",   edYaw[h]);
			level.JSONProfileSetDouble(key .. "roll",  edRoll[h]);
		}
		if (level.JSONProfileSave(name))
		{
			Console.Printf("\c[Gold]RS_HOLSTER: saved profile \"%s\"", name);
			if (name == "holster_seated" || name == "holster_standing")
				activeProfile = name;
		}
		else
			Console.Printf("\cgRS_HOLSTER: could not save profile \"%s\" (bad name, or write failed)", name);
	}

	// Loads into the LIVE edit table, same as dragging every sphere by hand --
	// so it takes effect immediately (updateProps reads edFwd/etc every tic)
	// and a bad or missing profile just leaves the current table untouched
	// rather than zeroing anything out. Returns whether the load actually
	// happened -- switchProfile needs to know, rather than assuming success
	// unconditionally (see its own comment on why that used to get it stuck).
	private bool loadProfile(string name)
	{
		ensureEdit();
		if (!level.JSONProfileLoad(name))
		{
			Console.Printf("\cgRS_HOLSTER: no profile \"%s\" on disk", name);
			return false;
		}
		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			// GetHolster's own defaults are the fallback per field, not 0 --
			// a profile saved before a 7th holster existed (hypothetically)
			// should not zero-pitch a field it never wrote.
			string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
			GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);

			string key = String.Format("h%d_", h);
			edFwd[h]   = level.JSONProfileGetDouble(key .. "fwd",   hsFwd);
			edSide[h]  = level.JSONProfileGetDouble(key .. "side",  hsSide);
			edFrac[h]  = level.JSONProfileGetDouble(key .. "frac",  hsFrac);
			// ORIENTATION IS NOT PER-HOLSTER ANY MORE. Every anchor holds its
			// weapon the same way -- the table's hsPitch/hsYaw/hsRoll, barrel
			// straight down along the body -- and a profile only moves anchors.
			// Older profiles still carry pitch/yaw/roll keys captured from the
			// hand at drop time; they are read past, not applied.
			edPitch[h] = hsPitch;
			edYaw[h]   = hsYaw;
			edRoll[h]  = hsRoll;
		}
		Console.Printf("\c[Gold]RS_HOLSTER: loaded profile \"%s\"", name);
		if (name == "holster_seated" || name == "holster_standing")
			activeProfile = name;
		return true;
	}

	// Flips between the two saved profiles and re-samples eye height for
	// whichever posture that implies. Reloading the offset TABLE alone is not
	// enough: anchorPos multiplies edFrac by eyeHeight[i], and that height is
	// only ever sampled once (tryCalibrate, WorldTick) -- carrying a standing
	// measurement into a freshly-loaded seated table (or vice versa) would
	// place every anchor using the wrong body's proportions on the right
	// table, or the right body's proportions on the wrong one. Neither reads
	// as "positioned for how you are sitting right now."
	private void switchProfile(int playerNum, PlayerPawn pawn)
	{
		// Empty (never touched activeProfile) falls to the "standing" branch,
		// matching GetHolster's own built-in defaults -- a first press that
		// does not visibly move anything, rather than jumping to a table that
		// has never been saved and quietly falling back to those same
		// defaults anyway.
		string target = (activeProfile == "holster_standing") ? "holster_seated" : "holster_standing";

		// loadProfile only advances activeProfile on an actual successful
		// load. Used to claim success and force-recalibrate regardless --
		// on a fresh install (activeProfile still "", nothing ever saved),
		// target computes to "standing" every time, the load fails
		// silently, activeProfile never moves off "", and every future
		// press recomputed the identical "standing" target forever: this
		// bind could never reach "seated" at all until Save/Load were used
		// directly at least once, defeating the point of a one-press
		// switch. Check the real result instead of assuming it.
		if (!loadProfile(target))
		{
			Console.Printf("\cgRS_HOLSTER: no \"%s\" profile saved yet -- use Save current as %s first", target, target.MakeUpper());
			return;
		}
		ForceRecalibrate(playerNum);
		Console.Printf("\c[Gold]RS_HOLSTER: switched to \"%s\" -- hold still a moment for height to resample", target);
	}

	private void updateClaims(int i, PlayerPawn pawn)
	{
		// Hysteresis: a hand already inside a holster keeps it until it leaves
		// a LARGER radius than it took to get in. Without this, a hand resting
		// near the boundary flickers claimed/unclaimed many times a second --
		// which is worse than not claiming at all, because grip's MEANING
		// flips with it, and the player cannot tell what a press will do.
		int prevMain = nearMain[i];
		int prevOff  = nearOff[i];

		bool mainClaimed = false;
		bool offClaimed = false;
		nearMain[i] = -1;
		nearOff[i] = -1;

		// Check the hysteresis-held holster FIRST, with ITS widened radius,
		// before the low-to-high scan below ever runs. The scan latches
		// whichever index passes first in index order -- so without this,
		// a numerically LOWER holster's ordinary (non-widened) radius could
		// steal the claim from a higher-indexed one the hand never actually
		// left, the moment the two overlap (e.g. an arm-rig wrist anchor
		// and a torso hip anchor both being near the hip). The held index's
		// own widened test has to run and win BEFORE any other index gets a
		// chance to, not merely get a bigger number when its own turn comes
		// up in a scan that may never reach it.
		if (prevMain >= 0 && holsterActive(prevMain))
		{
			string hsNameM; double hsFwdM, hsSideM, hsFracM, hsRadiusM, hsPitchM, hsYawM, hsRollM;
			GetHolster(prevMain, hsNameM, hsFwdM, hsSideM, hsFracM, hsRadiusM, hsPitchM, hsYawM, hsRollM);
			Vector3 heldAnchorMain = anchorPos(i, pawn, prevMain);
			if ((pawn.AttackPos - heldAnchorMain).Length() < hsRadiusM * CLAIM_HYSTERESIS)
			{
				mainClaimed = true;
				nearMain[i] = prevMain;
			}
		}
		if (prevOff >= 0 && holsterActive(prevOff))
		{
			string hsNameO; double hsFwdO, hsSideO, hsFracO, hsRadiusO, hsPitchO, hsYawO, hsRollO;
			GetHolster(prevOff, hsNameO, hsFwdO, hsSideO, hsFracO, hsRadiusO, hsPitchO, hsYawO, hsRollO);
			Vector3 heldAnchorOff = anchorPos(i, pawn, prevOff);
			if ((pawn.OffhandPos - heldAnchorOff).Length() < hsRadiusO * CLAIM_HYSTERESIS)
			{
				offClaimed = true;
				nearOff[i] = prevOff;
			}
		}

		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			// An inactive holster (active count dialed below 8) is not
			// visible and must not be claimable either -- a hand should
			// never be able to trigger a store/draw on a holster it cannot
			// see, hysteresis-held or not.
			if (!holsterActive(h))
				continue;

			string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
			GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);

			Vector3 anchor = anchorPos(i, pawn, h);

			// The held index's own widened radius was already tried above,
			// before this scan started -- if it won, !mainClaimed/!offClaimed
			// below skip re-testing anything for that hand at all. Reaching
			// here for a given hand means it does NOT currently hold a
			// claim, so a plain (non-widened) radius is correct for every
			// index this loop actually evaluates.
			double mainR = hsRadius;
			double offR  = hsRadius;

			if (!mainClaimed && (pawn.AttackPos - anchor).Length() < mainR)
			{
				// nearMain still records the pouch (updatePouchClaim keys on
				// it), but HolsterClaim* is NOT raised for it: the engine reads
				// that field as "inside a weapon holster" -- it arms the F13/F14
				// tap, forces GRIPCTX_Holster for the press, and fires a doSwap
				// against the pouch slot on release. Every magazine draw and
				// every RETURNED release used to end with a store/draw attempt.
				if (h != AMMO_POUCH_IDX) mainClaimed = true;
				nearMain[i] = h;
			}

			// The off hand can never claim its OWN hand-anchored gear. For
			// a hand-anchored index, anchor is OffhandPos plus a rotation of
			// that SAME hand's own live basis, so |OffhandPos - anchor| is
			// the constant sqrt(edFwd^2+edSide^2+edFrac^2) every tic, no
			// matter how the player moves -- never a meaningful "did the
			// hand reach it" test. Depending on tuned offsets that constant
			// would land either permanently inside the radius (the off hand
			// stuck claiming its own wrist forever) or permanently outside
			// (dead code) -- excluding the test outright is the only
			// correct fix, not something radius tuning could paper over.
			if (!offClaimed && (pawn.OffhandPos - anchor).Length() < offR)
			{
				if (h != AMMO_POUCH_IDX) offClaimed = true;   // see the main hand above
				nearOff[i] = h;
			}
		}

		// Edge-logged rather than per-tic: this is the signal that the whole
		// chain works, and it should be visible without being a spam source.
		//
		// GATED BEHIND rs_holster_verbose AS OF 2026-08-26. "Edge-logged, not
		// a spam source" was true only relative to a per-tic print: a hand
		// working across nine overlapping anchors crosses these edges
		// constantly, and a shipped build should not narrate that. The HAPTIC
		// is deliberately OUTSIDE the gate -- it is the player-facing
		// feedback, not instrumentation, and turning the console lines off
		// must not also turn off the thing that tells you where a holster is.
		if (mainClaimed != pawn.HolsterClaimMain)
		{
			if (verboseDiag())
				Console.Printf("RS_HOLSTER: main hand %s holster range", mainClaimed ? "ENTERED" : "left");
			// A short, light tap on ENTER only -- a real holster does not buzz
			// your hand when you pull away from it, only when you find it.
			if (mainClaimed) level.VRHaptic(0, 0.35, 25.0);
		}
		if (offClaimed != pawn.HolsterClaimOff)
		{
			if (verboseDiag())
				Console.Printf("RS_HOLSTER: off hand %s holster range", offClaimed ? "ENTERED" : "left");
			if (offClaimed) level.VRHaptic(1, 0.35, 25.0);
		}

		pawn.HolsterClaimMain = mainClaimed;
		pawn.HolsterClaimOff  = offClaimed;

		// Ammo pouch: a SEPARATE claim channel from HolsterClaim* above.
		// GripClaim*/GripSubject* is pose/priority arbitration (read by
		// RS_Reload, rs_hands, and anything else in that family), not the
		// store/draw tap mechanism HolsterClaim* drives -- the pouch never
		// stores anything, so it has no use for a tap at all. BOTH hands --
		// see updatePouchClaim's own comment for why this is not an
		// off-hand-only thing.
		updatePouchClaim(i, pawn, true);
		updatePouchClaim(i, pawn, false);

		updateProps(i, pawn);
	}

	// Ammo pouch claim + the weapon<->fist swap that goes with it, one hand.
	// BOTH hands can do this: the owner's framing is that a gun is in EVERY
	// hand as the baseline state (dual wielding, not one gun and one empty
	// hand), so reloading either weapon means reaching into the pouch with
	// the OTHER hand -- there is no hand that starts out free, so this
	// cannot be hand-specific the way the pouch's original design assumed.
	//
	// Piggybacks on nearMain[i]/nearOff[i], the SAME hysteresis-respecting
	// proximity result every other holster already gets this tic, rather
	// than re-testing distance separately.
	private void updatePouchClaim(int i, PlayerPawn pawn, bool isMain)
	{
		int near = isMain ? nearMain[i] : nearOff[i];
		bool nowInPouch = holsterActive(AMMO_POUCH_IDX) && (near == AMMO_POUCH_IDX);

		bool claimedByUs = isMain ? pouchClaimedMain[i] : pouchClaimedOff[i];
		int curClaim = isMain ? pawn.GripClaimMain : pawn.GripClaimOff;

		int hand = isMain ? 0 : 1;

		// STOW CAUGHT AMMUNITION, and this is what rs_use_ammo_pouch was always
		// waiting for.
		//
		// That switch shipped inert with a note saying the pouch it would route
		// to "died with RS_UnifiedVR" -- it was left in place so the decision
		// was recorded and the menu row was ready for when a pouch came back.
		// This is that pouch. It is the same anchor RR_Reload draws magazines
		// out of, so ammunition now goes back in the way it comes out.
		//
		// THE ARGUMENT FOR IT, in the owner's words: a box you DON'T catch
		// lands at your feet and is picked up by standing there anyway, so
		// catching one can only mean you wanted to keep it. Absorbing it on the
		// catch makes the catch worthless -- it produces the identical outcome
		// as missing. Holding it until you put it away is what makes catching
		// a thing you did rather than a thing that happened.
		//
		// BEFORE the claim block below, deliberately. Stowing is not a grip
		// gesture: the hand is simply carrying something into the pouch volume,
		// so it must not depend on a claim, on a press, or on the swap that the
		// claim triggers. The proximity result it reads (nowInPouch) is the
		// same hysteresis-respecting one every other holster gets this tic.
		let pouchCv = CVar.GetCVar("rs_use_ammo_pouch", pawn.player);
		if (nowInPouch && (pouchCv == null || pouchCv.GetBool()))
		{
			let held = RS_Held.Get();
			// RS_Held keeps ONE pair of hand slots, the console player's. For
			// any other player this would read player 1's hand and stow (and
			// release) whatever it holds into player i's inventory.
			Actor carried = (held && i == consoleplayer) ? held.HeldBy(hand) : null;

			// Ammo only. Everything else a hand can carry into this volume --
			// a barrel, a corpse, a weapon -- has somewhere else to go, and
			// swallowing it here would be a way to delete things by accident.
			if (carried && carried is 'Ammo')
			{
				let inv = Inventory(carried);
				if (inv && !inv.Owner)
				{
					// Released FIRST. CallTryPickup destroys or hides the world
					// copy on success, and a slot still pointing at it would be
					// holding a corpse of an actor for a tic. Release also puts
					// back every flag the hold borrowed, which the pickup path
					// needs -- SPECIAL above all, since it is what makes an
					// item takeable at all.
					//
					// WITHOUT THE PAWN, so this cannot throw. Release only
					// applies a throw velocity when handed a pawn and a
					// PlayerInfo, and your hand is ALWAYS moving as you put
					// something into the pouch -- so a refused stow (ammunition
					// already full) would have flung the box across the room at
					// swing speed. Refused now simply drops it at your feet,
					// where you can pick it up again.
					held.Release(hand);

					bool got = inv.CallTryPickup(pawn);
					if (got)
					{
						level.VRHaptic(hand, 0.45, 30.0);

						// The same confirm the store path uses, so putting
						// ammunition away sounds like putting anything away.
						let sndCv = CVar.GetCVar("rs_holster_sound", pawn.player);
						if (sndCv == null || sndCv.GetBool())
						{
							let styleCv = CVar.GetCVar("rs_holster_sound_style", pawn.player);
							string stowSnd = (styleCv != null && styleCv.GetInt() == 1) ? "rs_holster_fx_ready" : "rs_holster_fx_store";
							pawn.A_StartSound(stowSnd, CHAN_AUTO, CHANF_DEFAULT, 0.7);
						}
					}
					if (verboseDiag())
						Console.Printf("\cy RS_HOLSTER: %s-hand stowed %s -- %s",
							isMain ? "main" : "off", carried.GetClassName(),
							got ? "taken" : "refused");
				}
			}
		}

		if (nowInPouch && !claimedByUs && curClaim == GRIPSUBJ_None)
		{
			if (isMain) { pawn.GripClaimMain = GRIPSUBJ_Pouch; pouchClaimedMain[i] = true; }
			else        { pawn.GripClaimOff  = GRIPSUBJ_Pouch; pouchClaimedOff[i]  = true; }

			if (arbiter)
				arbiter.GetInt("grip.claim", "", hand, GRIPSUBJ_Pouch, pawn, 'RS_Holsters');
		}
		else if (nowInPouch && claimedByUs)
		{
			// RENEWAL. The arbiter's lease has to be refreshed or a hand parked
			// in the pouch for two seconds would read as free.
			if (arbiter)
				arbiter.GetInt("grip.claim", "", hand, GRIPSUBJ_Pouch, pawn, 'RS_Holsters');

			// AND THE ENGINE FIELD IS NOT NECESSARILY STILL RIGHT. Audit
			// finding #11.
			//
			// This branch used to assume it was, because we set it on the entry
			// edge and nothing clears it until the hand leaves. But another
			// consumer can take the claim off us and hand it back to None while
			// the hand is still inside -- which is exactly what a reload does
			// when you let the grip go without leaving the pouch. The entry
			// edge above cannot re-take it (claimedByUs is still true, so this
			// branch runs instead) and the exit branch below cannot clear our
			// flag (the hand has not left), so GripClaim stayed None for as
			// long as the hand stayed put. The engine then falls through to
			// GRIPSUBJ_Holster, and every consumer testing for GRIPSUBJ_Pouch
			// -- the reload's own draw, among others -- refuses that hand until
			// it is taken out and put back.
			//
			// So the invariant is repaired here rather than by asking the other
			// mod not to clear it: while we believe we own the pouch and the
			// hand is in it, the field says Pouch. Only from None, so a claim
			// somebody else legitimately holds is never stolen.
			int live = isMain ? pawn.GripClaimMain : pawn.GripClaimOff;
			if (live == GRIPSUBJ_None)
			{
				if (isMain) pawn.GripClaimMain = GRIPSUBJ_Pouch;
				else        pawn.GripClaimOff  = GRIPSUBJ_Pouch;
			}
		}
		else if (!nowInPouch && claimedByUs)
		{
			// Only clear a claim that is still ours -- another mod may have
			// taken GripClaim* for something else (a mag, a slide) in the
			// meantime, and that claim is not this mod's to erase.
			//
			// Asked of the arbiter as of 2026-08-28 rather than inferred from
			// the value. GRIPSUBJ_Pouch is at least a subject nothing else in
			// this family writes, so the old compare was sounder here than it
			// was in Hands or Reload -- but "sounder" is not "sound", and a
			// fourth consumer picking the same subject would break it silently.
			bool ours;
			if (arbiter)
				ours = arbiter.GetInt("grip.mine", "", hand, 0, pawn, 'RS_Holsters') == 1;
			else
				ours = (isMain ? pawn.GripClaimMain : pawn.GripClaimOff) == GRIPSUBJ_Pouch;

			if (ours)
			{
				if (isMain) pawn.GripClaimMain = GRIPSUBJ_None;
				else        pawn.GripClaimOff  = GRIPSUBJ_None;
			}

			if (arbiter)
				arbiter.GetInt("grip.release", "", hand, 0, pawn, 'RS_Holsters');

			if (isMain) pouchClaimedMain[i] = false;
			else        pouchClaimedOff[i]  = false;
		}

		// The weapon<->fist swap watches the CLAIM broadly (GripClaim* !=
		// None), not just whether THIS mod still owns it -- so if a reload
		// sequence takes the claim over from the pouch entry itself (still
		// holding a round or magazine, mid-transfer to the other hand's
		// gun), the real weapon stays a fist through all of that and only
		// returns once the hand is genuinely free again, whichever mod last
		// let go of the claim.
		ensurePouchPrevious();
		int liveClaim = isMain ? pawn.GripClaimMain : pawn.GripClaimOff;
		Weapon prev = isMain ? pouchPreviousMain[i] : pouchPreviousOff[i];
		bool handClaimed = (liveClaim != GRIPSUBJ_None);
		// `hand` is declared at the top of this function now -- the arbiter
		// calls in the claim/release block above need it too.

		// ENTERING THE SWAP NEEDS THE POUCH. STAYING IN IT DOES NOT.
		//
		// The broad watch above is right about STAYING: once the swap is
		// engaged, any mod's claim should hold it, so a reload that takes the
		// claim over mid-transfer does not hand your gun back early.
		//
		// It was wrong about STARTING. `handClaimed` alone meant ANY non-zero
		// GripClaim from ANY mod swapped your weapon for a fist -- and RS_Hands
		// writes GRIPSUBJ_Magazine for Ammo, Health, Armor, Inventory and
		// ExplosiveBarrel, while RS_Reload returns the same value as its default
		// case. So picking a health pack up off the floor, nowhere near your
		// chest, WITH THE POUCH SWITCHED OFF ENTIRELY, disarmed you.
		//
		// That is the single most-reported symptom in this family, and three
		// separate audits reached it by three different routes -- one through
		// RS_Hands leaking a claim, one through RS_Reload leaking one, one
		// through here. This is the receiving end, and gating entry on the pouch
		// stops the symptom no matter which writer caused it.
		//
		// nowInPouch already folds in holsterActive(AMMO_POUCH_IDX), so a
		// disabled pouch can never start a swap.
		// The pouch itself claimed the hand (or the reload took that claim
		// over), not merely "some claim while inside the volume": RS_Held
		// claims a hand for every object it closes on, and a barrel carried
		// past the chest used to fist the hand until the barrel was let go.
		bool pouchInvolved = claimedByUs || (nowInPouch && liveClaim == GRIPSUBJ_Pouch);

		if (handClaimed && prev == null && pouchInvolved)
		{
			Weapon real = isMain ? pawn.player.ReadyWeapon : pawn.player.OffhandWeapon;
			if (real != null && !RS_HandFist.IsFistClass(real.GetClass()))
			{
				// findFist's own parameter is named "offhand" -- !isMain
				// gives it exactly that.
				let fist = RS_HandFist.FindOrMakeFist(pawn, !isMain);
				if (fist != null)
				{
					if (isMain) pouchPreviousMain[i] = real;
					else        pouchPreviousOff[i]  = real;
					moveWeaponInstant(pawn, fist, hand);
				}
			}
		}
		else if (!handClaimed && prev != null)
		{
			moveWeaponInstant(pawn, prev, hand);
			if (isMain) pouchPreviousMain[i] = null;
			else        pouchPreviousOff[i]  = null;
		}
	}

	private void ensurePouchPrevious()
	{
		while (pouchPreviousMain.Size() < MAXPLAYERS)
			pouchPreviousMain.Push(null);
		while (pouchPreviousOff.Size() < MAXPLAYERS)
			pouchPreviousOff.Push(null);
	}

	// Park a prop at every anchor and keep it showing whatever is stored there.
	// Position is rewritten each tic rather than parented, because the anchors
	// move with the player's head every frame and there is nothing to parent to.
	private void updateProps(int i, PlayerPawn pawn)
	{
		// TWO INDEPENDENT SWITCHES as of 2026-08-26. The markers (wireframe
		// rings showing WHERE a holster is) and the props (the stored weapon's
		// model) are separate actor arrays, and they used to share one cvar
		// under a menu row labelled "Show holster spheres".
		//
		// That row was wrong twice. It did not only hide spheres -- the default
		// marker shape is the bracket reticle -- and it did not hide the markers
		// AT ALL: the early return below only ever touched props[], while every
		// line that positions markers[] sits after it. Switching it off hid your
		// stored weapons and left the rings visible and FROZEN in world space,
		// no longer following you.
		//
		// Now: markers and stored weapons toggle independently, which is the
		// case worth having -- once the anchors are learned by feel the rings
		// are clutter, but the guns parked in them are still worth seeing.
		bool wantProps   = showProps();
		bool wantMarkers = showMarkers();

		if (!wantProps || !wantMarkers)
		{
			// Setting invisible rather than destroying: the player can toggle
			// this mid-session, and respawning six actors on every toggle is
			// worse than leaving six invisible ones parked.
			for (int h = 0; h < HOLSTER_COUNT; ++h)
			{
				int pi = (i * HOLSTER_COUNT) + h;
				if (!wantProps && pi < props.Size() && props[pi] != null)
					props[pi].SetVisible(false);
				if (!wantMarkers && pi < markers.Size() && markers[pi] != null)
					markers[pi].SetVisible(false);
			}

			// Only bail entirely when there is nothing left to draw. With one
			// of the two still on, the loop below must run so that one keeps
			// tracking the player.
			if (!wantProps && !wantMarkers)
				return;
		}

		ensureContents();
		ensureProps();

		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			int pi = (i * HOLSTER_COUNT) + h;

			// Same "invisible, not destroyed" treatment showProps() already
			// uses for the whole system -- dialing the active count down
			// hides a holster without evacuating whatever might be stored in
			// it, so raising the count back up later shows it exactly as it
			// was left. updateClaims already refuses to claim an inactive
			// index; this is what makes it actually disappear too.
			if (!holsterActive(h))
			{
				if (pi < markers.Size() && markers[pi] != null)
					markers[pi].SetVisible(false);
				if (pi < props.Size() && props[pi] != null)
					props[pi].SetVisible(false);
					props[pi].shownClass = null;   // forget the class: ShowWeapon only re-shows on a class CHANGE
				continue;
			}

			Vector3 at = anchorPos(i, pawn, h);

			// Declared here, once, rather than where the weapon prop's own
			// orientation math used to declare it further down -- the marker
			// needs the same basis now too. It used to matter for nothing
			// but the prop, back when the marker was a sphere with no
			// orientation to get right; a bracket reticle is not
			// rotationally symmetric, so it needs pointing the same way.
			//
			// baseAngle/basePitch/baseRoll rather than a single byaw: every
			// holster in this mod is torso-anchored, so the base is body yaw
			// with zero pitch and roll, and edPitch/edRoll are used as
			// ABSOLUTE values on top of it. The three names are kept (rather
			// than folding bodyYaw[i] into the formulas directly) because the
			// orientation math below reads all three, and a future
			// non-zero-pitch anchor would set them here and change nothing
			// downstream.
			double baseAngle = bodyYaw[i];
			double basePitch = 0.0;
			double baseRoll  = 0.0;

			string hsNameM; double hsFwdM, hsSideM, hsFracM, hsRadius, hsPitchM, hsYawM, hsRollM;
			GetHolster(h, hsNameM, hsFwdM, hsSideM, hsFracM, hsRadius, hsPitchM, hsYawM, hsRollM);

			// Computed once, reused for both the color-class choice below and
			// the SetHot() call -- same "is a hand in range right now" test.
			bool hot = (nearMain[i] == h || nearOff[i] == h);

			// --- the ring marker: always present, so an empty holster is
			// still something the player can see and aim a hand at ---
			//
			// Color is a CLASS choice (RS_HolsterMarker.holsterMarkerColorClass,
			// RS_HolsterProp.zs), not a settable field -- an existing marker
			// whose class no longer matches the cvar gets destroyed and
			// respawned so a color change takes effect immediately instead of
			// waiting for something else to force a respawn later. Cold and
			// hot are independent cvars now, so this same respawn path also
			// fires on every hand-enter/leave transition -- fade state is
			// carried across it (GetFadeAlpha/GetFadeVisible/SetFadeState) so
			// that respawn is invisible: without it, a fresh marker always
			// starts faded to nothing and would fade back in on every single
			// hot/cold toggle instead of just switching color instantly.
			class<Actor> wantColorClass = RS_HolsterMarker.holsterMarkerColorClass(hot);
			double carryAlpha = 0.0;
			bool carryVisible = false;
			bool carryState = false;
			if (markers[pi] != null && markers[pi].GetClass() != wantColorClass)
			{
				carryAlpha = markers[pi].GetFadeAlpha();
				carryVisible = markers[pi].GetFadeVisible();
				carryState = true;
				markers[pi].Destroy();
				markers[pi] = null;
			}
			if (markers[pi] == null)
			{
				markers[pi] = RS_HolsterMarker(Actor.Spawn(wantColorClass, at, NO_REPLACE));
				if (markers[pi] != null && carryState)
					markers[pi].SetFadeState(carryAlpha, carryVisible);
			}

			if (markers[pi] != null)
			{
				markers[pi].SetVisible(wantMarkers);
				markers[pi].SetOrigin(at, true);
				markers[pi].SetHot(hot);
				markers[pi].SetRadius(hsRadius);   // the pouch is 3.5, the rest 3.0

				// Same live-tunable orientation the weapon prop uses (edYaw/
				// edPitch/edRoll, not a fresh GetHolster read) -- so dragging
				// a holster in edit mode reorients its marker too, instead of
				// the reticle staying frozen at the un-tuned default.
				markers[pi].angle = baseAngle + edYaw[h];
				markers[pi].pitch = basePitch + edPitch[h];
				markers[pi].roll  = baseRoll  + edRoll[h];

				// Proximity feed for the tighten effect: 1.0 at the anchor,
				// fading to 0 by SENSE_MULT*hsRadius out. Wider than the
				// actual grab radius on purpose -- the point is a reticle
				// that visibly notices a hand APPROACHING, not one that only
				// reacts once the hand is already inside the tiny grab
				// volume (at which point SetHot's binary swap already fired).
				// Plain local, not const -- every const in this codebase is a
				// CLASS-level member (HOLSTER_COUNT, SWAP_COOLDOWN, etc.), never
				// a local declared inside a method body, and there is no way to
				// test-compile before this ships to find out the hard way.
				double senseMult = 4.0;
				double dMain = (pawn.AttackPos - at).Length();
				double dOff  = (pawn.OffhandPos - at).Length();
				// No bare Min()/Clamp() -- neither has any precedent as a
				// builtin anywhere in this engine's own ZScript (only Max()
				// does), and there is no way to test-compile before this
				// ships, so plain comparisons it is.
				double dNear = (dMain < dOff) ? dMain : dOff;
				double senseRange = hsRadius * senseMult;
				double norm = (senseRange > 0.0) ? (dNear / senseRange) : 1.0;
				if (norm < 0.0) norm = 0.0;
				if (norm > 1.0) norm = 1.0;
				markers[pi].SetProximity(1.0 - norm);

				// --- ammo-driven glow, THE POUCH AND NOTHING ELSE ---
				// Gated on the index rather than fed to every marker with a
				// neutral value, because "never fed" is a real state the
				// marker relies on: SetAmmoGlow latches ammoDriven true, and
				// a marker that never latches it keeps the exact alpha it
				// had before this feature existed (RS_HolsterProp.zs Tick).
				// So the eight torso holsters are not merely unchanged in
				// effect -- they never enter the code path at all.
				if (h == AMMO_POUCH_IDX)
					markers[pi].SetAmmoGlow(pouchGlow(i, pawn));
			}

			// --- the stored weapon's model, when there is one ---
			if (props[pi] == null)
			{
				props[pi] = RS_HolsterProp(Actor.Spawn("RS_HolsterProp", at, NO_REPLACE));
				if (props[pi] == null)
					continue;
			}

			let p = props[pi];

			Weapon stored = contents[(i * HOLSTER_COUNT) + h];

			// --- reconcile the slot against reality ---
			// contents[] is only ever written by doSwap, so it drifts: a stored
			// weapon stays in inventory and the engine can re-arm it (ammo
			// pickup -> CheckWeaponSwitch), or it can be dropped, or promoted
			// into a different class by a tier upgrade. Any of those leaves the
			// table describing a holster that does not match the world.
			//
			// GATED ON THE SWITCH HAVING SETTLED, and that gate is the whole
			// trick: for the ~16 tics a weapon spends lowering, ReadyWeapon is
			// STILL the gun being put away. Reconciling during that window would
			// see "the stored weapon is in a hand" on the very tic after every
			// store and erase all six holsters as fast as they were filled.
			// PendingWeapon == WP_NOCHANGE means no switch is in flight.
			// Max of both hands here on purpose -- this gate is about giving
			// ANY recent swap time to settle before trusting ReadyWeapon/
			// OffhandWeapon, not about which specific hand caused it.
			if (stored != null && pawn.player.PendingWeapon == WP_NOCHANGE
			    && level.time - Max(lastSwapTicMain[i], lastSwapTicOff[i]) >= swapCooldown())
			{
				let rw = pawn.player.ReadyWeapon;
				let ow = pawn.player.OffhandWeapon;
				// POINTER equality, not class name -- this used to compare
				// GetClassName() strings, which false-positived the instant
				// the OTHER hand held a weapon of the same CLASS as this
				// holster's contents (a matched pair, one per hand: store
				// one, and the other hand's identical-class weapon looked
				// like "the stored one drifted back"). That wiped the slot
				// and reset the WRONG instance's flags below, permanently
				// orphaning the actually-stored weapon -- bHolsterHidden
				// stuck true on an instance nothing pointed at anymore, gone
				// from every holster's table and unable to fire or be cycled
				// to ever again. contents[] holding the real pointer makes
				// this test exact.
				bool inHand = (rw != null && rw == stored) || (ow != null && ow == stored);

				// contents[] now holds the actual instance, so "still owned"
				// is just this pointer being non-null -- GZDoom nulls an
				// Actor-typed field automatically when the actor it refers to
				// is destroyed (dropped, tier-promoted away), no
				// FindInventory lookup needed to detect it.
				if (inHand)
				{
					// TEMPORARY, 2026-08-26: this is the prime suspect for a
					// store that confirms, then reads empty again on the very
					// next attempt. The gate above (PendingWeapon==WP_NOCHANGE
					// and swapCooldown() elapsed) exists specifically to stop
					// this firing right after a normal doSwap store -- but
					// that gate assumes the weapon's own Deselect/Raise state
					// chain fully resolves ReadyWeapon within swapCooldown()
					// tics (4, with instant switch on). A third-party weapon
					// with a longer transition could still be mid-switch when
					// this fires, which would look EXACTLY like "drifted back
					// on its own" from here. One line, only when a slot is
					// actually being cleared, cannot become spam.
					// PendingWeapon is guaranteed WP_NOCHANGE here already --
					// that is the outer gate this branch sits inside -- so it
					// is not worth re-printing. ticsSinceSwap is the number
					// that actually matters: it is being compared against
					// swapCooldown() (4 tics, instant switch on) by that same
					// gate, and this print exists to check whether 4 is
					// actually enough for THIS weapon's own state chain.
					if (verboseDiag())
					Console.Printf("\cy RS_HOLSTER: updateProps CLEARING slot %d (%s) -- still in %s hand, %d tics after the last swap",
						h, stored.GetClassName(),
						(rw != null && rw == stored) ? "MAIN" : "OFF",
						level.time - Max(lastSwapTicMain[i], lastSwapTicOff[i]));

					// The weapon drifted back into a hand through something
					// other than doSwap (ammo-pickup re-arm via
					// CheckWeaponSwitch, the native VR wheel, a tier
					// promotion) -- give it the same reset doSwap's own draw
					// branch gives a normal draw. Clearing the table alone
					// left the weapon ITSELF permanently flagged: excluded
					// from weapnext/weapprev forever (CheckAmmo gates on
					// bHolsterHidden) and, worse, unable to ever fire again
					// (CheckAmmo gates that too, unconditionally) -- nothing
					// else in this file clears either flag.
					stored.bNoAutoSwitchTo = stored.Default.bNoAutoSwitchTo;
					stored.bHolsterHidden = false;

					contents[(i * HOLSTER_COUNT) + h] = null;
					stored = null;
				}
			}
			// Show first: it reads level.GetModelOrientationHint, which the
			// angle below depends on. Hand-anchored holsters get their own,
			// smaller default scale (RS_HolsterProp.holsterPropScaleArm) --
			// a wrist-mounted flashlight should read as compact gear, not a
			// full holstered sidearm.
			double propScale = RS_HolsterProp.holsterPropScale();

			// Passing null is the existing "this holster is empty" path --
			// ShowWeapon sets pendingClear and fades the model out. Reusing it
			// for "stored weapons are switched off" means the hide is the same
			// well-tested route rather than a second way to make a prop
			// invisible, and it comes back correctly when switched on again.
			Weapon toShow = wantProps ? stored : null;
			p.ShowWeapon(toShow, propScale, RS_HolsterProp.holsterPropVisualRadius());

			// Face the same way the BODY does (not the head), so a holstered
			// gun stays put on the hip when you look around, plus a tunable
			// yaw, MEASURED mirroring, and cancellation of whatever that
			// specific model bakes into its own MODELDEF block.
			//
			// Mirroring (p.mirrored) comes from level.GetModelOrientationHint,
			// not a guess: it is true exactly when that weapon's own Scale has
			// a negative X, which is a per-model authoring choice uncorrelated
			// with which hand it is normally held in. A mirrored mesh points
			// the opposite way for the same actor angle, hence +180.
			//
			// bakedAngleOffset/PitchOffset/RollOffset are MODELDEF fields
			// (e.g. the SMG's PitchOffset 45) that the renderer applies AFTER
			// actor rotation (r_data/models.cpp, step 5 follows step 1) --
			// so they land on top of whatever pitch/angle/roll is set here
			// REGARDLESS of what this code does. Subtracting them cancels
			// that per-weapon quirk out, so every weapon ends up at the same
			// intended final orientation instead of each carrying its own
			// baked-in deviation. Exact for the common case here, where a
			// weapon bakes at most one of the three axes; a weapon baking two
			// or more non-commuting axes at once would need real matrix math
			// to cancel exactly, which none of the current data requires.
			// baseAngle/basePitch/baseRoll are declared once, up with the
			// marker orientation code above.
			double extra = RS_HolsterProp.holsterPropYaw() + edYaw[h];
			if (p.mirrored)
				extra += 180.0;
			double finalAngle = baseAngle + extra - p.bakedAngleOffset;
			double finalPitch = basePitch + edPitch[h] + RS_HolsterProp.holsterPropPitch() - p.bakedPitchOffset;

			p.angle = finalAngle;
			p.pitch = finalPitch;
			p.roll  = baseRoll + edRoll[h] + RS_HolsterProp.holsterPropRoll() - p.bakedRollOffset;

			// Local basis for the MANUAL TRIM sliders only now (below). "Push it
			// forward" should mean forward-relative-to-the-gun, not raw world X,
			// so the trim still rides this rotated frame -- but this basis is no
			// longer used for the automatic correction. It was a hand-derived
			// reconstruction of the engine's own rotation, and it was wrong: two
			// independent derivations (direct and cross-product-verified) each
			// passed their own internal consistency check and still landed the
			// prop exactly 4.55 units off, on opposite sides depending on sign,
			// because neither accounted for RenderModel silently NEGATING pitch
			// before rotating (r_data/models.cpp: "pitch -= angles.Pitch.Degrees()"
			// under MDL_USEACTORPITCH without MDL_BADROTATION). That is not a
			// mistake worth repeating a third time by hand.
			double localFwdX =  cos(finalAngle) * cos(finalPitch);
			double localFwdY =  sin(finalAngle) * cos(finalPitch);
			double localFwdZ = -sin(finalPitch);
			double localUpX  = -cos(finalAngle) * sin(finalPitch);
			double localUpY  = -sin(finalAngle) * sin(finalPitch);
			double localUpZ  = -cos(finalPitch);
			double rightX = sin(finalAngle);
			double rightY = -cos(finalAngle);

			// AUTOMATIC centering: level.GetModelWorldOffset builds the SAME
			// VSMatrix with the SAME rotate() calls RenderModel itself makes
			// (including the pitch negation above) and transforms the model's
			// baked local offset through it directly -- the engine's own
			// transform, replayed, not a reconstruction of it. p.sprite/p.frame
			// are exactly the (sprite,frame) A_ChangeModel bound in ShowWeapon.
			double stretch = (level.info != null) ? level.info.pixelstretch : 1.0;
			bool foundWorld;
			double worldOffX, worldOffY, worldOffZ;
			// p.scale is passed because the renderer multiplies the model's
			// baked offset by it. Omitting it (defaulting to 1,1) subtracted a
			// full-size correction from a prop drawn at 0.18 -- roughly four
			// times too much -- which is why shrinking a weapon threw it out of
			// the sphere instead of settling it in the middle.
			[foundWorld, worldOffX, worldOffY, worldOffZ] =
				level.GetModelWorldOffset(p.boundClass, p.sprite, p.frame, stretch, finalAngle, finalPitch, p.roll,
				                          p.scale.X, p.scale.Y);
			if (!foundWorld) { worldOffX = 0.0; worldOffY = 0.0; worldOffZ = 0.0; }

			// Manual trim, local rotated frame, on top of the automatic
			// correction -- a residual nudge now, not the whole mechanism.
			double nUp   = RS_HolsterProp.holsterPropUp();
			double nFwd  = RS_HolsterProp.holsterPropFwd();
			double nSide = RS_HolsterProp.holsterPropSide();

			// TRIMMED IN THE BODY'S FRAME, NOT THE WEAPON'S.
			//
			// These three used to ride the local basis built above from
			// finalAngle/finalPitch, on the reasoning that "push it forward"
			// should mean forward-relative-to-the-gun. In practice that is
			// wrong, and reported as such 2026-08-29: every torso holster sets
			// hsPitch to 90 (barrel down), which rotates the weapon's frame a
			// quarter turn against the body -- so the up/down slider moved the
			// prop sideways, forward/back moved it up and down, and side moved
			// it forward and back. A clean 3-cycle, and no amount of care with
			// the sliders can undo it because the labels and the maths are
			// describing different frames.
			//
			// bodyYaw is the same frame the holster ANCHOR is placed in (hsFwd
			// and hsSide are already body-relative), so the trim now agrees
			// with the thing it is trimming. Up is world up, forward is where
			// your chest points, side is your right -- regardless of how the
			// weapon inside the holster happens to be posed.
			//
			// The weapon-frame basis above is left alone: it is still what the
			// automatic centring correction is derived in.
			double trimYaw = bodyYaw[i];
			double bFwdX =  cos(trimYaw), bFwdY =  sin(trimYaw);
			double bRgtX =  sin(trimYaw), bRgtY = -cos(trimYaw);

			Vector3 placed = (
				at.X - worldOffX + (nFwd * bFwdX) + (nSide * bRgtX),
				at.Y - worldOffY + (nFwd * bFwdY) + (nSide * bRgtY),
				at.Z - worldOffZ + nUp
			);
			p.SetOrigin(placed, true);
		}
	}

	// Grab the sphere this hand is inside, or drop the one it is holding.
	private void toggleGrab(int i, bool mainHand)
	{
		ensureEdit();

		int held = mainHand ? grabbedMain[i] : grabbedOff[i];
		if (held >= 0)
		{
			string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
			GetHolster(held, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);
			Console.Printf("RS_HOLSTER: dropped %s at fwd %.2f  side %.2f  frac %.3f",
				hsName, edFwd[held], edSide[held], edFrac[held]);
			level.VRHaptic(mainHand ? 0 : 1, 0.6, 15.0);
			if (mainHand) { grabbedMain[i] = -1; } else { grabbedOff[i] = -1; }
			return;
		}

		// Nothing held -- grab whatever this hand is inside. While editing,
		// the claim radius is what decides, same as a real grab, so a sphere
		// you cannot claim is also a sphere you cannot drag: that is the
		// feedback, not a limitation.
		int want = mainHand ? nearMain[i] : nearOff[i];
		if (want < 0)
		{
			Console.Printf("RS_HOLSTER: no sphere in reach for that hand");
			return;
		}

		string hsName2; double f2, s2, fr2, r2, p2, y2, rl2;
		GetHolster(want, hsName2, f2, s2, fr2, r2, p2, y2, rl2);
		Console.Printf("RS_HOLSTER: grabbed %s -- move your hand, press again to drop", hsName2);
		level.VRHaptic(mainHand ? 0 : 1, 0.35, 25.0);
		if (mainHand) { grabbedMain[i] = want; } else { grabbedOff[i] = want; }
	}


	private void ensureProps()
	{
		int want = MAXPLAYERS * HOLSTER_COUNT;
		while (props.Size() < want)
			props.Push(null);
		while (markers.Size() < want)
			markers.Push(null);
	}

	// The STORED WEAPON models parked in occupied holsters.
	private bool showProps() const
	{
		let cv = CVar.GetCVar("rs_holster_props", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : true;
	}

	// The WIREFRAME MARKERS showing where each holster is. Separate actors from
	// the props and, since 2026-08-26, a separate switch -- see updateProps for
	// why they used to share one and what that broke.
	private bool showMarkers() const
	{
		let cv = CVar.GetCVar("rs_holster_markers", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : true;
	}

	// How many of the 8 declared holsters are actually live: 2 (hip), 4
	// (+shoulder), 6 (+pectoral), 8 (+second hip pair) -- matching the
	// GetHolster index order exactly, so "active count N" always means
	// "indices 0..N-1", no separate ordering table needed. Clamped and
	// snapped to the nearest valid step rather than trusted raw, since this
	// cvar can be hand-edited in an ini to any int.
	private int activeCount() const
	{
		let cv = CVar.GetCVar("rs_holster_active_count", players[consoleplayer]);
		int n = (cv != null) ? cv.GetInt() : HOLSTER_COUNT;
		if (n <= 2) return 2;
		if (n <= 4) return 4;
		if (n <= 6) return 6;
		return 8;
	}

	// The ammo pouch (AMMO_POUCH_IDX) is its OWN toggle, not part of the
	// 2/4/6/8 weapon-holster progression above -- activeCount() snaps to the
	// nearest of exactly those four values and never returns 9, so without
	// this branch the pouch would be permanently unreachable (8 < 8 is
	// false) regardless of what rs_holster_active_count is set to. It is a
	// different kind of thing (ammo, not a weapon slot) and toggling it
	// should not ride a cvar named and tiered for the other eight.
	private bool holsterActive(int h) const
	{
		if (h == AMMO_POUCH_IDX)
			return pouchEnabled();
		return h < activeCount();
	}

	private bool pouchEnabled() const
	{
		let cv = CVar.GetCVar("rs_holster_pouch_enabled", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : true;
	}

	// =====================================================================
	// AMMO-DRIVEN POUCH GLOW (2026-08-26). THE POUCH ONLY -- AMMO_POUCH_IDX
	// and nothing else. The eight torso holsters are untouched by every line
	// below, on purpose: the curve is being proven in a headset before the
	// idea is allowed to spread to anything else.
	//
	// What it is for, in order of how much it matters:
	//   1. It TEACHES. Nothing else in this mod tells a new player the pouch
	//      exists; a marker that lights itself the first time you run low is
	//      the only thing that ever points at it unprompted.
	//   2. It answers "am I about to run dry" without a HUD number, which is
	//      the only way to answer it in VR without something pinned to your
	//      face.
	//   3. It stays out of the way when you are stocked, which is what earns
	//      it the right to be loud when you are not.
	// =====================================================================

	private bool pouchGlowEnabled() const
	{
		let cv = CVar.GetCVar("rs_holster_pouch_glow", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : true;
	}

	// Where the curve reaches zero. NOT one of the owner's numbers -- theirs
	// start at 20% -- and it is called out separately for exactly that
	// reason, so a re-tune knows which values are the spec and which one is
	// the joinery.
	//
	// It exists because "invisible when you are full" cannot be read as
	// "zero only at frac == 1.0". MaxAmount for a Doom clip is 200 (400 with
	// a backpack) and almost nobody is ever AT it, so a ramp anchored at 1.0
	// would leave the pouch faintly lit essentially forever -- and a cue
	// that is always slightly on is a cue the player stops seeing. 0.25 sits
	// just above the owner's first data point, which gives the glow a 5%
	// window to fade in over instead of popping on at exactly 20%.
	const POUCH_GLOW_KNEE = 0.25;

	// THE CURVE. One function, deliberately, so it can be re-tuned without
	// hunting for pieces of it.
	//
	// THE OWNER'S THREE DATA POINTS, which are the actual specification:
	//
	//     20% ammo left  ->  20% visible
	//     10% ammo left  ->  50% visible
	//      1% ammo left  ->  90% visible
	//
	// Non-linear ON PURPOSE. Quiet until it matters, then it shouts. Linear
	// would put 10% ammo at 10% brightness -- the moment you most need to be
	// told is the moment it would be whispering.
	//
	// Two more points close the ends, and neither is the owner's:
	//     >= POUCH_GLOW_KNEE (25%) -> 0% visible   (see that const)
	//      0% ammo                 -> 100% visible (dry is the loudest case
	//                                 there is; stopping at the 1%/90% row
	//                                 would make empty look the same as
	//                                 nearly-empty)
	//
	// Straight lines between the five, which is what makes it re-tunable:
	// move a row, and only the two segments touching it change.
	//
	// Takes a NEGATIVE frac to mean "nothing measurable in either hand" and
	// returns 0 for it -- see handAmmoFraction() for why that is not the
	// same as being empty.
	//
	// Not static, even though it is pure arithmetic on a double and reads
	// like it wants to be: it references POUCH_GLOW_KNEE, and a STATIC
	// method reading a class-level const has no precedent anywhere in the
	// five mods or in wadsrc (searched for exactly that pattern). An
	// ordinary private method reading one has precedent all over this class
	// -- activeCount() falls back to HOLSTER_COUNT, holsterActive() compares
	// against AMMO_POUCH_IDX -- so that is the form used.
	private double pouchAmmoCurve(double frac)
	{
		if (frac < 0.0)              return 0.0;   // nothing to measure -> silent
		if (frac >= POUCH_GLOW_KNEE) return 0.0;
		if (frac <= 0.0)             return 1.0;   // bone dry

		if (frac >= 0.20)
		{
			// KNEE..20%: 0.00 -> 0.20, the fade-in.
			// Guarded because the span is the one denominator here that a
			// re-tune can zero out -- drop POUCH_GLOW_KNEE to 0.20 and the
			// fade-in window disappears, which should mean "pop straight to
			// the 20% row", not a divide by zero.
			double span = POUCH_GLOW_KNEE - 0.20;
			if (span <= 0.0) return 0.20;
			return 0.20 * ((POUCH_GLOW_KNEE - frac) / span);
		}
		if (frac >= 0.10)
		{
			// 20%..10%: 0.20 -> 0.50
			return 0.20 + (0.30 * ((0.20 - frac) / 0.10));
		}
		if (frac >= 0.01)
		{
			// 10%..1%: 0.50 -> 0.90
			return 0.50 + (0.40 * ((0.10 - frac) / 0.09));
		}
		// 1%..0%: 0.90 -> 1.00
		return 0.90 + (0.10 * ((0.01 - frac) / 0.01));
	}

	// Fold one hand's weapon into the running worst-case fraction. Returns
	// `worst` unchanged for every hand that has nothing measurable in it, so
	// a skipped hand can never drag the answer down.
	//
	// EVERY ONE OF THESE GUARDS IS A REAL CASE, and getting any of them
	// wrong makes the pouch scream permanently at a player who is in no
	// trouble at all -- which is worse than the feature not existing, since
	// a cue that is always on teaches the player to ignore it:
	//
	//   w == null           an empty hand. Normal: this mod's own pouch
	//                       claim swaps a fist in while a hand is reaching
	//                       into the pouch (see updatePouchClaim), so a null
	//                       or fist hand is the EXPECTED state at the exact
	//                       moment the glow is being looked at.
	//   !w.AmmoType1        a fist. Precedent for testing this field's
	//                       truthiness rather than == null: RS_Reload's
	//                       rr_feed.zs:325, "if (!w.AmmoType1) return
	//                       RR_A_MELEE;" -- the same question, asked the
	//                       same way, one repo over.
	//   w.Ammo1 == null     the ammo item was never attached. Read as
	//                       UNKNOWN, not as zero: the weapon declares an
	//                       ammo type but there is no instance to measure,
	//                       and a guess of "empty" here would be a
	//                       permanent full-brightness pouch. wadsrc does the
	//                       same null-test before every read of this field
	//                       (weapons.zs:1113, "count1 = (Ammo1 != null) ?
	//                       Ammo1.Amount : 0").
	//   MaxAmount <= 0      a weapon whose ammo has no ceiling to be a
	//                       fraction OF -- and the divide-by-zero guard.
	private double mergeAmmoFraction(double worst, Weapon w)
	{
		if (w == null)              return worst;
		if (!w.AmmoType1)           return worst;
		if (w.Ammo1 == null)        return worst;
		if (w.Ammo1.MaxAmount <= 0) return worst;

		// (int * 1.0) rather than a double(...) cast, which is this repo's
		// established idiom for float promotion and carries its own
		// explanation at RS_HolsterProp.zs' popMult.
		double f = (w.Ammo1.Amount * 1.0) / w.Ammo1.MaxAmount;
		if (f < 0.0) f = 0.0;
		// Clamped at the top because MaxAmount is not a hard ceiling: a
		// backpack RAISES it (ammo.zs BackpackMaxAmount), and there are
		// windows where Amount is above the value being divided by.
		if (f > 1.0) f = 1.0;

		if (worst < 0.0) return f;      // first measurable hand
		return (f < worst) ? f : worst; // plain compare, no min() -- matches
		                                // the proximity feed's reasoning in
		                                // updateProps
	}

	// The ammo fraction the glow is driven from, or a NEGATIVE number for
	// "nothing measurable in either hand". Negative rather than 0.0 because
	// those two mean opposite things: 0.0 is "you are dry, panic", and a
	// bare fist or a chainsaw must read as "not low" instead.
	//
	// DUAL WIELD -- WHICH HAND WINS. This engine has ReadyWeapon AND
	// OffhandWeapon and, in this mod's own framing, a gun in EVERY hand is
	// the baseline (see the pouchClaimed* fields: there is no hand that
	// starts out free). So "the gun in your hand" has two answers, and the
	// choice here is the WORST of the two, not the main hand:
	//
	//   - The pouch is ONE cue for a shared resource. If either gun is about
	//     to run dry, that is the fact worth knowing, and it is the fact the
	//     player is about to act on by reaching into this exact pouch.
	//   - Taking the main hand alone would go quiet while the off hand sat
	//     empty, which is the failure the feature exists to prevent.
	//   - Taking the BRIGHTER-of/fuller-of would be worse still: it would
	//     stay dark specifically because one gun is fine, at the moment the
	//     other one is not.
	//   - In the ordinary case the two hands share an ammo pool anyway (two
	//     pistols, one Clip), and worst == best == the single answer the
	//     owner described.
	//
	// Both hands null (dead, or mid-switch with nothing raised) falls
	// straight through to the negative return -- silent, which is right.
	private double handAmmoFraction(PlayerPawn pawn)
	{
		if (pawn == null || pawn.player == null)
			return -1.0;

		double worst = -1.0;
		worst = mergeAmmoFraction(worst, pawn.player.ReadyWeapon);
		worst = mergeAmmoFraction(worst, pawn.player.OffhandWeapon);
		return worst;
	}

	// The glow value handed to the pouch marker every tic. Split out of
	// updateProps so the two overrides that force it fully lit sit next to
	// each other instead of being scattered through the marker loop.
	private double pouchGlow(int i, PlayerPawn pawn)
	{
		// OFF means "look exactly the way this marker looked before the
		// feature existed", and that is FULL brightness, not zero. The
		// marker latches ammoDriven true the first time it is fed
		// (RS_HolsterProp.zs) and there is no un-feeding it mid-session, so
		// handing it 1.0 is what actually makes toggling the cvar back off
		// restore the old look instead of leaving the pouch frozen at
		// whatever the last computed glow happened to be.
		if (!pouchGlowEnabled())
			return 1.0;

		// Edit mode positions a holster by GRABBING ITS MARKER. A pouch
		// faded to nothing is a pouch you cannot grab, so without this the
		// only way to tune the pouch's position would be to shoot yourself
		// down to 10% ammo first.
		if (i >= 0 && i < MAXPLAYERS && editMode[i])
			return 1.0;

		return pouchAmmoCurve(handAmmoFraction(pawn));
	}

	private bool instantSwitchEnabled() const
	{
		let cv = CVar.GetCVar("rs_holster_instant_switch", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : true;
	}

	// Developer instrumentation gate, added 2026-08-26. Until then this mod
	// shipped a permanent instrumentation layer switched ON in the default
	// build: a seven-line orientation dump after EVERY store, plus a console
	// line on every hand-enters/leaves-range transition.
	//
	// GATED, NOT DELETED. Every one of those exists because a specific
	// question was open and is still open -- the same reasoning that kept
	// RS_HardPoints' wrist-pitch dump alive when it got this treatment
	// (rs_hardpoint_wristdump). Turn this on for a tuning session and they
	// all come back at once. See CVARINFO.txt's rs_holster_verbose entry for
	// one such question that lost its own diagnostic tool (RS_HolsterFlashlight,
	// removed 2026-08-28) before it was ever answered.
	//
	// What is deliberately NOT behind it: the range-entry HAPTIC (player
	// feedback, not instrumentation), the one-line store/draw confirmation,
	// every error line, and the MANUAL dump on netevent rs-holster-debug --
	// asking for that one is the whole gesture.
	//
	// NAMED _verbose, NOT _debug: KEYCONF binds an ALIAS called
	// rs_holster_debug, and a cvar sharing that name would collide in the
	// console namespace. Same trap, same resolution, as _wristdump.
	// EVERYTHING THIS PACKAGE PRINTS WHILE PLAYING IS BEHIND THIS.
	// Off, the holsters are silent except for a genuine fault (no head
	// pose, an eye height outside any sane range) and the things you asked
	// for by pressing a key -- the table dump, a profile save or load,
	// edit mode. Calibration used to announce itself on every map; that is
	// a tuning session's want, not a shipped build's.
	private bool verboseDiag() const
	{
		let cv = CVar.GetCVar("rs_holster_verbose", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : false;
	}

	private int swapCooldown() const
	{
		return instantSwitchEnabled() ? FAST_SWAP_COOLDOWN : SLOW_SWAP_COOLDOWN;
	}

	override void NetworkProcess(ConsoleEvent evt)
	{
		if (evt.player < 0) return;
		PlayerPawn pawn = players[evt.player].mo;
		if (!pawn) return;

		if (evt.name == "rs-holster-recalibrate")
		{
			ForceRecalibrate(evt.player);
			return;
		}

		if (evt.name == "rs-holster-debug")
		{
			dumpDebug(evt.player, pawn);
			return;
		}

		if (evt.name == "rs-holster-edit")
		{
			ensureEdit();
			editMode[evt.player] = !editMode[evt.player];
			grabbedMain[evt.player] = -1;
			grabbedOff[evt.player] = -1;
			if (editMode[evt.player])
			{
				Console.Printf("\c[Gold]RS_HOLSTER: EDIT MODE ON");
				Console.Printf("  put a hand in a sphere and press its holster key to GRAB it");
				Console.Printf("  move your hand, press again to DROP it there");
				Console.Printf("  then: netevent rs-holster-table   (prints the numbers)");
			}
			else
			{
				Console.Printf("\c[Gold]RS_HOLSTER: edit mode off");
			}
			return;
		}

		if (evt.name == "rs-holster-table")
		{
			ensureEdit();
			dumpTable();
			return;
		}

		if (evt.name == "rs-holster-reset")
		{
			edInit = false;
			ensureEdit();
			Console.Printf("RS_HOLSTER: offsets reset to the built-in defaults");
			return;
		}

		// Two named profiles, not a generic named-save flow: a hip/pectoral
		// table tuned standing does not fit a seated body (shorter reach,
		// different eye-to-hip fraction), so "which profile" is really "which
		// posture", and posture only has two values worth a dedicated bind.
		if (evt.name == "rs-holster-save-seated")   { saveProfile("holster_seated");   return; }
		if (evt.name == "rs-holster-load-seated")   { loadProfile("holster_seated");   return; }
		if (evt.name == "rs-holster-save-standing") { saveProfile("holster_standing"); return; }
		if (evt.name == "rs-holster-load-standing") { loadProfile("holster_standing"); return; }

		// The switcher: flips to whichever of the two you are not currently
		// on, and re-samples eye height for it. One bind, no menu digging --
		// this is the one meant for mid-session use (you just sat down),
		// where the four buttons above are a setup-time thing.
		if (evt.name == "rs-holster-switch-profile") { switchProfile(evt.player, pawn); return; }

		// One key per hand -- which hand pressed decides which weapon moves,
		// or in edit mode which sphere gets dragged.
		//
		// TWO event names per hand, and the shared one is why this mod can be
		// loaded alongside RS_HardPoints. The engine's grip arbiter redirects
		// a holster-context grip to the synthetic keys F13/F14; a key can only
		// be bound to ONE alias, so two mods each binding F13 to their own
		// private alias means the second one loaded silently wins and the
		// other never hears a grip press again.
		//
		// So both mods bind their own alias name (no KEYCONF collision) and
		// both aliases fire the SAME "rs-vrhp-grab-*" netevent, which every
		// handler receives. doSwap's first line then returns immediately when
		// the hand is not inside one of THIS mod's own anchors.
		//
		// THAT IS NOT ARBITRATION, and this comment used to claim it was
		// ("the hand is in exactly one place, so exactly one mod acts"). It
		// stops being true the moment an anchor here overlaps one of
		// RS_HardPoints' -- a hip holster sits on the body, a wrist mount
		// rides the forearm, and one reach can be inside both. Both handlers
		// get the netevent, both find a claim, and BOTH swap on a single
		// press. What keeps that from happening today is where the anchors
		// happen to sit, not anything in this code. The real fix is the grip
		// arbiter being built separately; DO NOT "tidy" this dispatch in the
		// meantime, it will collide with that work.
		// THE HANDS LANE OWNS A FULL OR REACHING HAND. The engine fires the
		// anchor pulse on any clean tap that STARTED inside a holster without
		// consulting the grab claims, so lowering a carried barrel to the hip
		// and tapping grip to drop it also stored the gun in that hand.
		if (evt.name == "rs-holster-grab-main" || evt.name == "rs-vrhp-grab-main")
		{
			if (editMode[evt.player])                             { toggleGrab(evt.player, true); }
			else if (evt.player == consoleplayer && handsBusy(0)) { return; }
			else                                                  { doSwap(evt.player, pawn, nearMain[evt.player], false); }
		}
		else if (evt.name == "rs-holster-grab-off" || evt.name == "rs-vrhp-grab-off")
		{
			if (editMode[evt.player])                             { toggleGrab(evt.player, false); }
			else if (evt.player == consoleplayer && handsBusy(1)) { return; }
			else                                                  { doSwap(evt.player, pawn, nearOff[evt.player], true); }
		}
	}

	// Is the hands lane holding or reaching for a world object with this
	// hand? RS_Held and RS_GrabHandler track the console player only.
	private bool handsBusy(int hand)
	{
		let held = RS_Held.Get();
		if (held && held.HandIsFull(hand)) return true;
		let grab = RS_GrabHandler.Get();
		return grab && grab.TargetFor(hand) != null;
	}

	// Wraps MoveWeaponToHand with a transient CF_INSTANTWEAPSWITCH, restored
	// immediately after. A dedicated helper rather than inlining this at both
	// call sites in doSwap means there is no early-return path that could
	// leave the flag set -- set/call/restore is one atomic sequence with
	// nothing else inside it to return out of early. (An earlier version of
	// this set the flag before doSwap's validation checks instead of right
	// around the call; those checks have their own early returns, which would
	// have left the flag stuck on for the rest of the session.)
	//
	// CF_INSTANTWEAPSWITCH is a real, complete GZDoom mechanism
	// (constants.zs) that both A_Lower and BringUpWeapon already check
	// (weapons.zs / player.zs) -- setting it makes psp.y jump straight to
	// WEAPONBOTTOM/WEAPONTOP instead of climbing 6 units/tic, so the whole
	// lower-then-raise sequence resolves SYNCHRONOUSLY inside the
	// MoveWeaponToHand call, same tic, rather than over the ~16 tics that
	// made two-hand near-simultaneous store/draw fight over one shared
	// PendingWeapon. Restored right after so ordinary weapon switching
	// (number keys, the wheel) keeps its normal animated feel -- this only
	// ever touches the switch a holster itself just triggered.
	//
	// Checked for side effects before using it: RS_ScoreRevival.zs is the
	// only place in RS_Main that reads player.cheats for anything besides a
	// single unrelated HUD check (CF_CHASECAM in RS_HealthBars.zs), and it
	// only tests the invincibility bits (CF_BUDDHA/CF_BUDDHA2/CF_GODMODE/
	// CF_GODMODE2) -- nothing anywhere treats "cheats nonzero" as a global
	// cheated-run flag that this would trip.
	//
	// exactInstance: true. MoveWeaponToHand's default matches the weapon to
	// the OTHER hand's by CLASS (and sister link) and turns a match into a
	// hand switch instead of a seat. This file deals in INSTANCES -- a
	// matched pair of pistols, one per hand, or a second fist of the class
	// already seated opposite -- and for those the class test was true every
	// time, so the stored gun / fresh fist was never placed and the swap
	// read as "did nothing". Pointer identity is the only test that fits.
	private void moveWeaponInstant(PlayerPawn pawn, Weapon w, int hand)
	{
		if (!instantSwitchEnabled())
		{
			pawn.MoveWeaponToHand(w, hand, true);
			return;
		}
		bool wasSet = (pawn.player.cheats & CF_INSTANTWEAPSWITCH) != 0;
		pawn.player.cheats |= CF_INSTANTWEAPSWITCH;
		pawn.MoveWeaponToHand(w, hand, true);
		if (!wasSet)
			pawn.player.cheats &= ~CF_INSTANTWEAPSWITCH;
	}

	// Swap what the hand is holding with what the holster holds. Because an
	// empty hand always means "fists" and an empty holster always means
	// "nothing stored", both directions are the same operation: read both
	// sides, write both sides. Draw, store, and swap are all this.
	private void doSwap(int i, PlayerPawn pawn, int holsterIdx, bool offhand)
	{
		// TEMPORARY, 2026-08-26: unconditional entry marker. Every refusal
		// below this point now prints its own reason -- this catches the
		// possibility that NONE of them fire and the function still does
		// nothing, which would otherwise be a fourth silent path nobody
		// anticipated. Fires once per physical press, cannot become spam.
		if (verboseDiag())
		Console.Printf("\cy RS_HOLSTER: doSwap ENTER  hand=%s  holsterIdx=%d",
			offhand ? "off" : "main", holsterIdx);

		if (holsterIdx < 0)
			return; // hand was not in a holster; nothing claimed it

		// A HAND ON LOAN TO THE POUCH, OR CLAIMED BY ANOTHER LANE, IS NOT
		// FREE TO STORE OR DRAW. The engine's store/draw pulse fires on the
		// falling edge of any clean tap that started inside an anchor volume,
		// without consulting the grip claims -- so a magazine carry released
		// inside a pectoral holster drew that holster's gun into the fisted
		// hand, and the pouch's restore on the next tic stranded it.
		ensurePouchPrevious();
		Weapon lent  = offhand ? pouchPreviousOff[i] : pouchPreviousMain[i];
		int    claim = offhand ? pawn.GripClaimOff  : pawn.GripClaimMain;
		if (lent != null || claim != GRIPSUBJ_None)
		{
			if (verboseDiag())
				Console.Printf("RS_HOLSTER: %s hand is claimed (%d) or lent to the pouch -- ignoring store/draw",
					offhand ? "off" : "main", claim);
			return;
		}

		// A HAND WITH A SWITCH ALREADY IN FLIGHT IS NOT A TRUSTWORTHY WITNESS.
		//
		// Proven in a real session, not theorised: a third-party rifle's own
		// Deselect state looped on itself, and the engine's own recursion
		// guard killed it --
		//   "Recursive weapon state loop in 'VR_Rifle.5' -- aborted at depth 65"
		// -- mid-transition. CF_INSTANTWEAPSWITCH is supposed to resolve the
		// whole lower/raise cycle synchronously inside ONE MoveWeaponToHand
		// call (see moveWeaponInstant's own comment above), so there should
		// be no window where PendingWeapon reads anything but WP_NOCHANGE by
		// the time control returns here -- but an aborted weapon state chain
		// leaves the switch wherever the engine gave up, permanently, with no
		// later tic that will ever finish it.
		//
		// This mod has no way to fix a third-party weapon's own broken
		// states, but it does not have to trust ReadyWeapon/OffhandWeapon as
		// fresh truth while this is true for THIS hand -- that stale value is
		// exactly what let an already-broken rifle get read as the hand's
		// current weapon by a LATER, unrelated holster action and displace
		// whatever else was legitimately stored. Refuse instead: the holster
		// table (contents[]) stays exactly as it was, nothing gets displaced,
		// and the player at least keeps whatever the OTHER hand can still do.
		if (pawn.player.PendingWeapon != WP_NOCHANGE)
		{
			if (verboseDiag())
				Console.Printf("RS_HOLSTER: %s-hand -- a weapon switch has not settled, refusing rather than trusting a stale hand",
					offhand ? "off" : "main");
			return;
		}

		// Debounce. A held or repeating key must not swap more than once. With
		// instant switch OFF, a swap also cannot settle immediately --
		// PendingWeapon takes ~16 tics to become ReadyWeapon, so a second swap
		// inside that window reads the OLD held weapon and shuffles the same
		// gun back and forth; with it ON (the default), that window is gone
		// and swapCooldown() is pure debounce, short enough that both hands
		// can act within the same reach without one eating the other's.
		// Checked here but NOT charged here -- the write lives at the end, next
		// to the confirm haptic. Charging on entry meant every no-op press
		// (fists into an empty holster, a same-weapon repeat, a stale slot)
		// burned a full cooldown, so recovering from a bad slot needed two
		// presses spaced a cooldown apart with no indication why the first did
		// nothing.
		//
		// Own hand's cooldown always applies (plain debounce against one
		// physical press registering as two). The OTHER hand's cooldown
		// only applies when instant switch is off -- see the field
		// declarations above for why: with it off, a store takes ~16 tics
		// to actually resolve, and PendingWeapon is one field BringUpWeapon
		// consumes hand-blind, so the other hand's own store landing inside
		// that window would clobber a switch that has not settled yet. With
		// it on (the default), THIS call fully resolves PendingWeapon
		// before returning -- nothing is left in flight for the other hand
		// to collide with, so two hands really can swap in the same tic.
		int sameHandTic = offhand ? lastSwapTicOff[i] : lastSwapTicMain[i];
		if (level.time - sameHandTic < swapCooldown())
		{
			// TEMPORARY, 2026-08-26: both cooldown returns below were
			// completely silent -- if the timestamp ever gets stuck ahead of
			// level.time, this blocks EVERY press forever with zero evidence
			// why. Only fires on an actual blocked press, not per tic.
			if (verboseDiag())
			Console.Printf("\cy RS_HOLSTER: %s-hand BLOCKED by own cooldown -- level.time=%d sameHandTic=%d delta=%d need=%d",
				offhand ? "off" : "main", level.time, sameHandTic, level.time - sameHandTic, swapCooldown());
			return;
		}
		if (!instantSwitchEnabled())
		{
			int otherHandTic = offhand ? lastSwapTicMain[i] : lastSwapTicOff[i];
			if (level.time - otherHandTic < swapCooldown())
			{
				if (verboseDiag())
				Console.Printf("\cy RS_HOLSTER: %s-hand BLOCKED by OTHER hand's cooldown -- level.time=%d otherHandTic=%d delta=%d need=%d",
					offhand ? "off" : "main", level.time, otherHandTic, level.time - otherHandTic, swapCooldown());
				return;
			}
		}

		ensureContents();

		int slot = (i * HOLSTER_COUNT) + holsterIdx;

		// TEMPORARY, 2026-08-26: contents[slot] is reading as if the LAST
		// call's commit never happened -- same "held" weapon, same "empty"
		// slot, five presses in a row. Every other per-player array in this
		// class (nearMain, calibrated, lastSwapTicMain) persists correctly
		// between calls, so this checks whether i/slot/array-size themselves
		// are the problem rather than the swap logic.
		string dbgPre = "null";
		if (contents[slot] != null) dbgPre = contents[slot].GetClassName();
		if (verboseDiag())
		Console.Printf("\cy RS_HOLSTER: pre-commit  i=%d  slot=%d  contents.Size()=%d  contents[slot]-BEFORE=%s",
			i, slot, contents.Size(), dbgPre);

		// Evict any fist a previous build managed to store. Without this the
		// bad slots persist in a running session and keep showing a fist at
		// the holster even after the store guard is fixed.
		for (int c = 0; c < HOLSTER_COUNT; ++c)
		{
			int ci = (i * HOLSTER_COUNT) + c;
			if (contents[ci] != null && RS_HandFist.IsFistClass(contents[ci].GetClass()))
				contents[ci] = null;
		}

		Weapon stored = contents[slot];
		Weapon held = offhand ? pawn.player.OffhandWeapon : pawn.player.ReadyWeapon;

		// Never store the fist. It is what an empty holster looks like, not a
		// thing that occupies one -- otherwise "swap fists into an empty
		// holster" would fill it with a weapon the player still has anyway.
		// "is Fist" does NOT work here: VR_Fist derives from RS_Weapon, not
		// from Doom's Fist, so the inheritance test is always false and every
		// fist got stored like a real weapon. That is where the extra fists
		// came from. Match on the name, the same way findFist does.
		string heldName = "";
		if (held != null && !RS_HandFist.IsFistClass(held.GetClass()))
			heldName = held.GetClassName();

		if (stored == null && heldName == "")
		{
			// TEMPORARY, 2026-08-26: this branch is completely silent by
			// design (a real no-op, empty holster + nothing worth storing),
			// but that silence is indistinguishable from a bug from outside.
			// One line, only on the no-op path, so it cannot become spam.
			//
			// held.GetClassName() returns Name, not String -- a ternary needs
			// both branches to share one type, so "NULL" (a String literal)
			// against a bare Name does not compile. Plain if/else into a
			// String local sidesteps the whole question.
			string dbgHeld = "NULL";
			if (held != null) dbgHeld = held.GetClassName();
			string dbgFistNote = "";
			if (held != null && RS_HandFist.IsFistClass(held.GetClass())) dbgFistNote = " (matched as fist)";
			if (verboseDiag())
			Console.Printf("\cy RS_HOLSTER: %s-hand no-op -- held=%s%s  slot(%d) empty",
				offhand ? "off" : "main", dbgHeld, dbgFistNote, holsterIdx);
			return; // fists into an empty holster: nothing to do
		}

		// The slot names the very gun this hand is holding. That is not
		// ALWAYS a stale slot, and conflating the two is the actual bug this
		// comment used to describe as fixed.
		//
		// GENUINE STALE SLOT: the weapon drifted back into a hand through
		// something OTHER than doSwap (ammo-pickup re-arm, the wheel, a tier
		// promotion), completed, and settled. contents[] just hasn't heard
		// about it yet. Safe to resync and re-store.
		//
		// SWITCH STILL IN FLIGHT: THIS mod's own PREVIOUS press already
		// called MoveWeaponToHand for this exact hand and is still mid
		// DropWeapon/BringUpWeapon. ReadyWeapon/OffhandWeapon has not caught
		// up yet, so it reads identically to the genuine case above -- same
		// held, same stored, same pointer equality. The two are
		// indistinguishable from contents[] and held alone.
		//
		// Confusing the second case for the first was a real, reproducible
		// jam: falling through re-called moveWeaponInstant, which calls
		// MoveWeaponToHand a SECOND time on a weapon whose DropWeapon is
		// already running. player.zs:2605-2639 does not guard against being
		// re-entered mid-transition -- it happily reassigns PendingWeapon and
		// calls DropWeapon(hand) again, restarting the lower sequence from
		// wherever the first call's Deselect states had gotten to. Press
		// again before that finishes -- and swapCooldown() is 4 tics,
		// nowhere near enough to guarantee ANY weapon's Deselect chain has
		// settled -- and the restart happens again. A weapon whose own
		// Deselect is slow enough gets kept in a perpetual restart loop by
		// this mod's own retries, which reads as "the switch is permanently
		// stuck" and is not the third-party weapon's fault: this mod caused
		// it by calling DropWeapon on top of an already-running DropWeapon.
		//
		// So: only treat this as a stale slot when NOTHING is already in
		// flight for this hand. PendingWeapon != WP_NOCHANGE means a switch
		// this mod itself started has not settled -- wait for it rather than
		// restarting it. Precedent for exactly this gate is updateProps'
		// own reconciliation a few hundred lines up, which already refuses
		// to trust ReadyWeapon/OffhandWeapon while a switch is in flight, for
		// the identical reason.
		if (stored != null && stored == held)
		{
			if (pawn.player.PendingWeapon != WP_NOCHANGE)
			{
				if (verboseDiag())
					Console.Printf("RS_HOLSTER: %s-hand -- a switch is still resolving, not restarting it",
						offhand ? "off" : "main");
				return;
			}
			contents[slot] = null;
			stored = null;
		}

		// A weapon lives in exactly one holster. Without this, storing the
		// same gun in two places leaves both claiming it, and drawing from
		// one silently empties the other. POINTER equality -- a same-CLASS
		// weapon sitting in a different holster (a matched pair) must not be
		// evicted just because it shares a class name with the one just
		// stored.
		if (heldName != "")
		{
			for (int h = 0; h < HOLSTER_COUNT; ++h)
			{
				int other = (i * HOLSTER_COUNT) + h;
				if (other != slot && contents[other] == held)
					contents[other] = null;
			}
		}

		contents[slot] = (heldName != "") ? held : null;

		string dbgPost = "null";
		if (contents[slot] != null) dbgPost = contents[slot].GetClassName();
		if (verboseDiag())
		Console.Printf("\cy RS_HOLSTER: post-commit  contents[%d]=%s", slot, dbgPost);

		// Bring out whatever was in there. The instance pointer IS the stored
		// weapon -- no FindInventory-by-name lookup needed (that used to be
		// how a same-class matched pair could resolve to the WRONG instance).
		// stored is only non-null here because GZDoom nulls an Actor-typed
		// field automatically when the actor it refers to is destroyed
		// (dropped, tier-promoted away) -- if that had happened, contents[slot]
		// would already read null and the block above would have returned.
		int hand = offhand ? 1 : 0;

		if (stored != null)
		{
			let w = stored;

			// ANY HAND CAN DRAW FROM ANY HOLSTER. A holster is not bound to a
			// hand -- either hand can claim any of the six anchors, and the
			// hip pair sit on opposite sides of the body -- so refusing a
			// draw because the weapon's OWN hand-flag happens to disagree was
			// asking the physical world to match a piece of engine
			// bookkeeping instead of the other way round.
			//
			// bOffhandWeapon is not a fixed "this weapon belongs to this
			// hand" label. It is the engine's own live "which hand did I
			// most recently get seated in" tracker -- player.zs:2629 inside
			// MoveWeaponToHand writes `weap.bOffhandWeapon = hand == 1;`
			// unconditionally, every single time a weapon is placed. So the
			// correct move on a mismatch is not to refuse -- it is to
			// relabel the weapon for the hand that is actually reaching for
			// it, right now, which is exactly what MoveWeaponToHand would do
			// to it anyway the moment it finishes seating. Doing it a line
			// early just means MoveWeaponToHand's own guard --
			//     if (weap.bNoHandSwitch && weap.bOffhandWeapon != (hand==1)) return;
			// -- sees a weapon already labelled for where it is about to go,
			// instead of silently refusing on the way in. Every weapon in
			// this arsenal carries +WEAPON.NOHANDSWITCH, so without this the
			// guard above would still be live and this draw would still
			// silently do nothing.
			if (w.bOffhandWeapon != offhand)
			{
				w.bOffhandWeapon = offhand;
				if (w.SisterWeapon != null)
					w.SisterWeapon.bOffhandWeapon = offhand;
			}

			// Coming back out, so it is an ordinary auto-switch candidate again,
			// and weapnext/weapprev/slot-select can land on it again too.
			w.bNoAutoSwitchTo = w.Default.bNoAutoSwitchTo;
			w.bHolsterHidden = false;

			// MoveWeaponToHand, never a raw OffhandWeapon assignment.
			// Assigning the pointer directly leaves the hand's psprite
			// still running the OLD weapon's states with the new weapon as
			// caller, and the VM aborts the moment one of those state
			// functions type-checks its owner:
			//   "Invalid class VR_Fist in function call to VR_SMG.StateFunction"
			// This routes through PendingWeapon and DropWeapon/BringUpWeapon
			// so the psprite is torn down and rebuilt properly.
			moveWeaponInstant(pawn, w, hand);

			// SAME IMMEDIATE RECOVERY AS THE STORE PATH, and for the same
			// reason: DRAWING a stored weapon calls this exact same
			// MoveWeaponToHand machinery, just with the weapon and the hand
			// it is currently occupying swapped -- so it is exactly as
			// exposed to a broken Select/Ready chain as the store path is to
			// a broken Deselect chain. This mod's own evidence has only
			// caught the store direction breaking so far, but there is no
			// reason to leave the draw direction on the slow 70-tic
			// WorldTick backstop when the fix is one identical check. contents[]
			// is already correct at this point either way -- the slot was
			// cleared above -- so recovering here only ever affects how the
			// weapon lands in the hand, never the holster table.
			if (pawn.player.PendingWeapon != WP_NOCHANGE)
			{
				pawn.BringUpWeapon();
				pendingStuckTics[i] = 0;
				if (verboseDiag())
					Console.Printf("RS_HOLSTER: draw did not settle this tic -- recovered immediately, not waiting");
			}
		}
		else
		{
			// Holster was empty, so the hand comes back to fists. Resolved by
			// search, not by name: this arsenal has VR_Fist, RS_GH_Fist and
			// RS_PS_Fist (plus numbered tiers of each) and the right one
			// depends on the player class. Hardcoding "Fist" found nothing,
			// which is why storing a weapon appeared to do nothing at all --
			// the gun went into the holster but never left the hand.
			let fist = RS_HandFist.FindOrMakeFist(pawn, offhand);
			if (fist == null)
			{
				// No fist this hand can actually accept. Refusing loudly beats
				// the old behaviour, which committed the store and then failed
				// to empty the hand -- leaving the player still holding a gun
				// the table had already filed away.
				contents[slot] = stored;   // roll back; the store did not happen
				Console.Printf("\cgRS_HOLSTER: no %s-hand fist to empty into", offhand ? "off" : "main");

				// TEMPORARY, 2026-08-26: findFist is failing with no known
				// arsenal loaded and no obvious reason why -- dump every
				// Weapon this player actually owns, since findFist only
				// searches THIS list and nothing else. Not gated on
				// rs_holster_verbose: this only fires on an actual failed
				// store, not per tic, so it cannot become spam.
				if (verboseDiag())
				Console.Printf("\cy  inventory dump:");
				int wCount = 0;
				for (Inventory dbgItem = pawn.Inv; dbgItem != null; dbgItem = dbgItem.Inv)
				{
					let dbgW = Weapon(dbgItem);
					if (dbgW == null) continue;
					wCount++;
					string dbgCn = dbgW.GetClassName();
					// noHandSwitch/sister added 2026-08-28, chasing the
					// Brutal Doom/Project Brutality off-hand report -- the
					// original three columns can't tell a single-instance
					// arsenal (this fist is the only one, so it's always
					// "otherHandWeapon" from the off hand's point of view,
					// findFist has nothing to relabel) apart from a
					// two-instance one where the SECOND instance's own
					// NOHANDSWITCH or missing SisterWeapon link is what
					// actually blocks the seat. One repro answers both.
					string dbgSister = "null";
					if (dbgW.SisterWeapon != null)
						dbgSister = dbgW.SisterWeapon.GetClassName();
					if (verboseDiag())
					Console.Printf("\cy    %-24s offhand=%d  isFist=%d  noHandSwitch=%d  sister=%s",
						dbgCn, dbgW.bOffhandWeapon, RS_HandFist.IsFistClass(dbgW.GetClass()), dbgW.bNoHandSwitch, dbgSister);
				}
				if (wCount == 0)
					if (verboseDiag())
					Console.Printf("\cy    (no Weapon-type items in inventory at all)");
				return;
			}
			// TEMPORARY, 2026-08-26: contents[] bookkeeping has been proven
			// correct -- this is the one remaining unverified step. Print
			// what findFist chose and what actually landed in each hand
			// immediately after the call, so a fist that silently fails to
			// seat is visible instead of inferred.
			string dbgRW  = "null";  if (pawn.player.ReadyWeapon  != null) dbgRW  = pawn.player.ReadyWeapon.GetClassName();
			string dbgOW  = "null";  if (pawn.player.OffhandWeapon != null) dbgOW  = pawn.player.OffhandWeapon.GetClassName();
			if (verboseDiag())
			Console.Printf("\cy RS_HOLSTER: about to seat fist=%s (bOffhandWeapon=%d) into hand=%d.  BEFORE: Ready=%s Offhand=%s",
				fist.GetClassName(), fist.bOffhandWeapon, hand, dbgRW, dbgOW);

			moveWeaponInstant(pawn, fist, hand);

			dbgRW = "null";  if (pawn.player.ReadyWeapon  != null) dbgRW  = pawn.player.ReadyWeapon.GetClassName();
			dbgOW = "null";  if (pawn.player.OffhandWeapon != null) dbgOW  = pawn.player.OffhandWeapon.GetClassName();
			if (verboseDiag())
			Console.Printf("\cy RS_HOLSTER: AFTER seating:  Ready=%s Offhand=%s  PendingWeapon==WP_NOCHANGE=%d",
				dbgRW, dbgOW, pawn.player.PendingWeapon == WP_NOCHANGE);

			// IMMEDIATE RECOVERY, NOT A 2-SECOND WAIT. Proven in a real
			// session: this specific failure (a third-party weapon's own
			// Deselect looping and getting killed by the engine's recursion
			// guard) is synchronous -- the abort happens DURING
			// moveWeaponInstant, on this exact tic, not sometime later. The
			// per-tic recovery in WorldTick (pendingStuckTics) exists for a
			// switch that gets stuck through some OTHER path, but for the
			// one this file has actual evidence of, waiting up to 70 tics to
			// notice something that already finished failing THIS tic is
			// pure lost time. Recover right here instead.
			if (pawn.player.PendingWeapon != WP_NOCHANGE)
			{
				pawn.BringUpWeapon();
				pendingStuckTics[i] = 0;
				if (verboseDiag())
					Console.Printf("RS_HOLSTER: seat did not settle this tic -- recovered immediately, not waiting");
			}
		}

		// The gun that just went IN stops being an auto-switch candidate. A
		// holstered weapon is still in inventory, so without this the engine's
		// CheckWeaponSwitch picks it straight back out on the next ammo pickup
		// (the fists it is compared against are +WEAPON.WIMPY_WEAPON, so the
		// test always passes) -- and then the holster and the hand both claim
		// the same gun. Restored on draw, above.
		//
		// bHolsterHidden alongside it, same lifecycle: without this,
		// weapnext/weapprev/slot-select would still happily cycle straight
		// to a weapon that is sitting in a holster, pulling it into the hand
		// through a path that never goes through doSwap at all -- the
		// holster would then show empty (this mod's own reconciliation in
		// updateProps catches the desync) while the gun ends up in-hand
		// unasked for. bHolsterHidden makes CheckAmmo itself refuse to
		// treat a stowed weapon as a valid candidate, which is what actually
		// keeps it out of the cycle in the first place.
		if (held != null && heldName != "")
		{
			held.bNoAutoSwitchTo = true;
			held.bHolsterHidden = true;
		}

		// Charged only now that real work happened -- see the check at the top.
		if (offhand) lastSwapTicOff[i] = level.time;
		else         lastSwapTicMain[i] = level.time;

		// Firmer and shorter than the entry tap -- a confirm, not a notice.
		level.VRHaptic(offhand ? 1 : 0, 0.6, 15.0);

		// Diegetic confirm, fired from the HOLSTER's own position rather than
		// the player -- a sound with a place in the world, not a UI blip
		// glued to your head.
		//
		// NAMES CHANGED 2026-08-26, and the old ones were the bug. This asked
		// for "rs_fx_holster" / "rs_allclear_ready", which are defined in
		// exactly one place on disk: RS_Main's SNDINFO. RS_Main is not part of
		// this family and is not a declared dependency of this pk3 -- this
		// file's own header is explicit that the mod must work with any weapon
		// pack and name none -- and GZDoom resolves an undefined sound to
		// SILENCE rather than to an error. So this cue had simply never played
		// for anybody running these mods without RS_Main, with a cvar, a menu
		// row and a style selector all wired to it and nothing reporting a
		// thing. The audio now ships here under this pk3's own logical and
		// lump names; see SNDINFO.txt.
		let sndCv = CVar.GetCVar("rs_holster_sound", pawn.player);
		if (sndCv == null || sndCv.GetBool())
		{
			let styleCv = CVar.GetCVar("rs_holster_sound_style", pawn.player);
			string sndName = (styleCv != null && styleCv.GetInt() == 1) ? "rs_holster_fx_ready" : "rs_holster_fx_store";

			if (slot < props.Size() && props[slot] != null)
				props[slot].A_StartSound(sndName, CHAN_AUTO, CHANF_DEFAULT, 0.7);
			else
				pawn.A_StartSound(sndName, CHAN_AUTO, CHANF_DEFAULT, 0.7);
		}

		string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
		GetHolster(holsterIdx, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);
		// GetClassName() returns Name, not string -- ?: needs both branches
		// to be the SAME type (an assignment coerces Name->string fine, a
		// ternary does not), so the conversion happens on its own line, not
		// inline in the ternary below. This is exactly what broke the real
		// compile (line 1734/1780 in the actual error log).
		string storedName = "";
		if (stored != null)
			storedName = stored.GetClassName();
		Console.Printf("RS_HOLSTER: %s <-> %s (%s)",
			heldName == "" ? "fists" : heldName,
			stored == null ? "empty" : storedName,
			hsName);

		// Auto-diagnostic: if a real weapon just went INTO this holster (not a
		// fists-only draw with nothing to measure), queue a dump for next tic.
		// This is what makes "record as I play" true -- store a gun and the
		// full orientation/offset breakdown lands in the log on its own, no
		// menu, no netevent, nothing to remember mid-session.
		//
		// GATED BEHIND rs_holster_verbose AS OF 2026-08-26. "Record as I
		// play" is a tuning session's want, not a shipped build's: every
		// single store printed a seven-line orientation breakdown into the
		// player's console. Gated at the SOURCE rather than at WorldTick's
		// consumption point so nothing is queued in the first place -- the
		// manual dump (netevent rs-holster-debug) is untouched and still
		// prints the same numbers on demand.
		if (contents[slot] != null && verboseDiag())
			pendingDump[i] = holsterIdx;
	}

	// Everything needed to tell WHY a holster is not triggering, in one dump.
	// Without this a mislocated anchor is indistinguishable from a dead
	// system: both produce no console output at all.
	private void dumpDebug(int i, PlayerPawn pawn)
	{
		Console.Printf("\c[Gold]--- RS_HOLSTER DEBUG ---");
		Console.Printf("calibrated: %s   eye height: %.1f", calibrated[i] ? "yes" : "NO", eyeHeight[i]);
		Console.Printf("HmdPos  %.1f, %.1f, %.1f   yaw %.1f", pawn.HmdPos.X, pawn.HmdPos.Y, pawn.HmdPos.Z, pawn.HmdYaw);
		Console.Printf("pawn    %.1f, %.1f, %.1f   floor %.1f", pawn.pos.X, pawn.pos.Y, pawn.pos.Z, pawn.floorz);
		Console.Printf("mainhnd %.1f, %.1f, %.1f", pawn.AttackPos.X, pawn.AttackPos.Y, pawn.AttackPos.Z);
		Console.Printf("offhand %.1f, %.1f, %.1f", pawn.OffhandPos.X, pawn.OffhandPos.Y, pawn.OffhandPos.Z);

		if (!calibrated[i])
		{
			Console.Printf("\cgnot calibrated -- no anchors computed yet");
			return;
		}

		ensureContents();

		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
			GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);

			Vector3 anchor = anchorPos(i, pawn, h);
			double dMain = (pawn.AttackPos - anchor).Length();
			double dOff  = (pawn.OffhandPos - anchor).Length();
			Weapon slotHas = contents[(i * HOLSTER_COUNT) + h];
			string slotHasName = "";
			if (slotHas != null)
				slotHasName = slotHas.GetClassName();

			Console.Printf("%-13s at %.1f,%.1f,%.1f  r%.0f  main %.1f%s  off %.1f%s  [%s]",
				hsName, anchor.X, anchor.Y, anchor.Z, hsRadius,
				dMain, dMain < hsRadius ? " IN" : "",
				dOff,  dOff  < hsRadius ? " IN" : "",
				slotHas == null ? "empty" : slotHasName);
		}

		dumpPropOrientation(i, pawn);
	}

	// Everything the two orientation/offset natives measured for each occupied
	// holster's model, plus what actually got applied to the actor and where
	// the mesh ended up relative to the sphere it should be centred in. Built
	// for exactly the "still not centred / still not barrel-down" reports --
	// without this, the only way to tell "the native returned garbage" apart
	// from "the math consuming it is wrong" was to keep guessing at both.
	private void dumpPropOrientation(int i, PlayerPawn pawn)
	{
		Console.Printf("\c[Gold]--- prop orientation ---");

		bool anyStored = false;
		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			if (contents[(i * HOLSTER_COUNT) + h] == null) continue;
			anyStored = true;
			dumpOneHolsterProp(i, pawn, h);
		}

		if (!anyStored)
			Console.Printf("(nothing stored anywhere -- store a weapon first, then run this again)");
	}

	// Everything the two orientation/offset natives measured for ONE occupied
	// holster's model, plus what actually got applied and where the mesh ended
	// up relative to the sphere. Factored out of dumpPropOrientation so the
	// same diagnostic can fire AUTOMATICALLY the instant a store happens (see
	// doSwap), not just on a manual dump -- "record as I play" instead of
	// needing to remember a menu press.
	private void dumpOneHolsterProp(int i, PlayerPawn pawn, int h)
	{
		Weapon stored = contents[(i * HOLSTER_COUNT) + h];
		if (stored == null) return;

		// The instance pointer IS the stored weapon -- no FindInventory-by-name
		// lookup, same reasoning as doSwap. Still owned because GZDoom nulls an
		// Actor-typed field automatically when the actor it refers to is
		// destroyed; if that had happened, stored above would already be null.
		let w = stored;

		State rs = w.FindState("Ready");
		if (rs == null)
		{
			Console.Printf("%-13s [%s] -- no Ready state, cannot resolve model", "?", stored.GetClassName());
			return;
		}

		// GetActorModelClass, not w.GetClass() -- same reasoning as
		// RS_HolsterProp.ShowWeapon: reads what THIS INSTANCE actually
		// resolves against, which can be a donor class from another mod
		// (ModelSwapper) that per-instance model-swapped w. Recomputed here
		// independently rather than read off the prop, matching this
		// function's existing "independent recomputation" role.
		class<Actor> resolvedClass = level.GetActorModelClass(w);

		bool foundOri, mirrored;
		double angOff, pitOff, rolOff;
		[foundOri, mirrored, angOff, pitOff, rolOff] = level.GetModelOrientationHint(resolvedClass, rs.sprite, rs.Frame);

		double stretch = (level.info != null) ? level.info.pixelstretch : 1.0;
		bool foundOff;
		double offX, offY, offZ;
		[foundOff, offX, offY, offZ] = level.GetModelOffsetHint(resolvedClass, rs.sprite, rs.Frame, stretch);

		string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
		GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);

		// Same base as updateProps -- kept as its own copy here rather than
		// factored out, matching this function's existing role as an
		// INDEPENDENT recomputation for diagnostics (see the file header
		// comment on dumpOneHolsterProp): a dump that shared updateProps'
		// arithmetic could not catch updateProps getting it wrong.
		double baseAngle = bodyYaw[i];
		double basePitch = 0.0;
		double baseRoll  = 0.0;
		double extra = RS_HolsterProp.holsterPropYaw() + edYaw[h] + (mirrored ? 180.0 : 0.0);
		double finalAngle = baseAngle + extra - angOff;
		double finalPitch = basePitch + edPitch[h] + RS_HolsterProp.holsterPropPitch() - pitOff;

		double finalRoll = baseRoll + edRoll[h] + RS_HolsterProp.holsterPropRoll() - rolOff;

		// Same fill-vs-fallback split ShowWeapon actually applies -- kept as
		// its own copy for the same independent-recomputation reason as the
		// angle/pitch/roll split above, not factored out into a shared
		// helper. Using the REAL applied scale here (not always the flat
		// fallback) matters: GetModelWorldOffset's own correctness depends
		// on being handed the actor scale that is actually in effect, or
		// this dump's "world offset" stops matching what is really on screen.
		bool foundBounds; double measuredRadius;
		[foundBounds, measuredRadius] = level.GetModelBoundsHint(resolvedClass, rs.sprite, rs.Frame);
		double fallbackScale = RS_HolsterProp.holsterPropScale();
		double visualRadius = RS_HolsterProp.holsterPropVisualRadius();
		double steadyStateScale = (foundBounds && measuredRadius > 0.0)
			? (visualRadius * RS_HolsterProp.holsterPropFill()) / measuredRadius
			: fallbackScale;

		// Prefer the prop's REAL, currently-applied Scale over the formula
		// above when the prop actually exists. The auto-dump-on-store fires
		// one tic after every store, while Tick()'s settle-pop is still
		// mid-ramp (up to POP_OVERSHOOT=1.35x baseScale for POP_TICS=6
		// tics) -- the steady-state formula alone does not know about that
		// overshoot, so it under-reports scale for every automatic dump,
		// the tool's main "record as I play" use case, and the printed
		// world-offset number would not match what is actually on screen
		// that tic even though the math itself is correct.
		int pi = (i * HOLSTER_COUNT) + h;
		double propScale = (pi < props.Size() && props[pi] != null) ? props[pi].scale.X : steadyStateScale;

		bool foundWorld; double worldDX, worldDY, worldDZ;
		[foundWorld, worldDX, worldDY, worldDZ] =
			level.GetModelWorldOffset(resolvedClass, rs.sprite, rs.Frame, stretch, finalAngle, finalPitch, finalRoll,
			                          propScale, propScale);

		Console.Printf("%-13s [%s]", hsName, stored.GetClassName());
		Console.Printf("  orientation hint: found=%d mirrored=%d angOff=%.1f pitOff=%.1f rolOff=%.1f",
			foundOri, mirrored, angOff, pitOff, rolOff);
		Console.Printf("  offset hint:      found=%d  local(fwd,side,up)= %.2f, %.2f, %.2f",
			foundOff, offX, offY, offZ);
		Console.Printf("  bounds hint:      found=%d  radius=%.2f  holster r=%.2f fill=%.2f -> steady-state=%.4f  live=%.4f  (fallback would be %.4f)",
			foundBounds, measuredRadius, hsRadius, RS_HolsterProp.holsterPropFill(), steadyStateScale, propScale, fallbackScale);
		Console.Printf("  world offset:     found=%d  world(x,y,z)= %.2f, %.2f, %.2f  (via GetModelWorldOffset, replays the engine's own rotation)",
			foundWorld, worldDX, worldDY, worldDZ);
		Console.Printf("  applied:          angle=%.1f pitch=%.1f  (base angle %.1f, holster pitch %.1f, trim yaw %.1f pitch %.1f)",
			finalAngle, finalPitch, baseAngle, hsPitch, RS_HolsterProp.holsterPropYaw(), RS_HolsterProp.holsterPropPitch());

		if (!foundOri || !foundOff || !foundWorld)
			Console.Printf("\cg  NATIVE RETURNED NOT-FOUND -- class/sprite/frame lookup failed, model may not have hasmodel set or FSpriteModelFrame is missing for this (sprite,frame)");

		// pi already declared above (same value, (i * HOLSTER_COUNT) + h) for
		// the live-Scale read -- still in scope, nothing between there and
		// here reassigns it.
		if (pi < props.Size() && props[pi] != null)
		{
			Vector3 anchor = anchorPos(i, pawn, h);
			double drift = (props[pi].pos - anchor).Length();
			Console.Printf("  prop actual pos:  %.1f, %.1f, %.1f   sphere at %.1f, %.1f, %.1f   drift %.2f%s",
				props[pi].pos.X, props[pi].pos.Y, props[pi].pos.Z,
				anchor.X, anchor.Y, anchor.Z, drift,
				drift > hsRadius ? "  <-- OUTSIDE the sphere" : "");
		}
	}

	private void ensureContents()
	{
		int want = MAXPLAYERS * HOLSTER_COUNT;
		while (contents.Size() < want)
			contents.Push(null);
	}
}
