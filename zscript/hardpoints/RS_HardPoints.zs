// ARM-ANCHORED HARDPOINTS: anchor placement + grip-claim arbitration.
// Six mount points, THREE AROUND EACH WRIST -- one bank per arm -- each
// holding one item the OPPOSITE hand can reach over and grab.
//
// RE-LAID OUT 2026-08-26 on the owner's re-spec. This rig used to be six
// mounts on ONE arm: three along the forearm (indices 0-2) plus three around
// the wrist (3-5). It is now three around the MAIN wrist (0-2) and three
// around the OFF wrist (3-5). The COUNT is deliberately unchanged at six --
// dual-arm arrives without adding anything new to learn -- and the FOREARM
// tier is deferred, not cancelled; see the DEFERRED block on the constants
// below for everything that was learned about it, so it does not have to be
// re-derived when it comes back.
//
// TWO VERBS, and keeping them apart is the whole point of the split (owner,
// 2026-08-26): HOLSTERS DRAW, WRISTS FIRE. A torso holster (RS_Holsters,
// separate repo) puts a gun in your hand. A wrist mount fires its weapon IN
// PLACE, palm-out, without ever drawing it -- see updateGestureArm/
// fireGesture. Do not add drawing behaviour to a wrist mount; the two systems
// stop competing precisely because they are different verbs.
//
// This is the part that actually DRIVES the engine's HardpointClaimMain/
// HardpointClaimOff -- without this handler running, those fields stay false,
// the native grip redirect never fires, and grip keeps its normal meaning
// everywhere (see DoomXR vk_openxrdevice.cpp).
//
// ORIGIN AND BASIS BOTH COME FROM THE LIVE POSE OF THE ARM THAT WEARS THE
// MOUNT -- AttackPos/Angle/Pitch/Roll for the main bank (0-2), OffhandPos/
// Angle/Pitch/Roll for the off bank (3-5) -- unconditionally. It does not
// matter which hand is holding a weapon, or whether either hand is holding one
// at all. This is each arm's own hardpoint rig, not something that tracks a
// weapon.
//
// A HAND CANNOT CLAIM ITS OWN GEAR, and that is not a tuning choice: an anchor
// here is a FIXED offset from its own arm's live pose, so the distance from
// that hand to it is a constant every tic no matter how the player moves. It
// would be a permanent self-claim or permanent dead code, never a proximity
// test. THE OTHER HAND reaches over and uses the rig -- the main hand works
// the off bank and the off hand works the main bank; see the guard in
// updateClaims.
//
// THAT CROSS-REACH IS WHY nearOff STOPPED BEING DEAD. Before the re-layout
// every index was off-arm-anchored, so the off hand was excluded from all six
// and nearOff was pinned to -1 forever -- a complete dead path kept only
// because the fork's other half (RS_Holsters) still used it. With a main-arm
// bank to reach for, the off hand has real work again and every nearOff/
// grabbedOff branch below is live. Do not "tidy" any of them away.
//
// SPLIT OUT OF RS_Holsters, which owns the 8 torso holsters (hip, head,
// pectoral) and shares this same manager design. The two load together: see
// NetworkProcess's rs-vrhp-grab-* handling for how one grip press reaches both
// mods without either needing to know the other exists.
//
// NOTE ON SHAPE: the hardpoint table is an indexed accessor rather than an
// Array of structs, because ZScript dynamic arrays only accept integral and
// object types -- Array<SomeStruct> does not compile. Since the table is
// compile-time constant anyway, a switch costs nothing and allocates nothing.
//
// KNOWN v1 GAP: the basis is built from the wearing arm's yaw+pitch only, not
// roll. A stored item's own orientation tracks live roll correctly; the ANCHOR
// POSITION does not swing around the arm when that arm rolls. Left unfixed
// deliberately rather than guessed at blind -- this file's rotation math has
// been hand-derived wrongly twice before. The fix, if it reads wrong in
// headset: rotate handAnchorPos/worldToHand's right/up vectors around forward
// by the same roll handBasisPose already returns. The re-layout did not touch
// this either way; it is the same gap on both arms now instead of on one.
//
// Names like GetHolster/holsterActive/HOLSTER_COUNT are inherited from that
// shared origin and left alone: they are private to this pk3, referenced
// nowhere outside it, and renaming every one of them in a codebase with no way
// to test-compile buys nothing but risk.

class RS_HardPointManager : EventHandler
{
	const HOLSTER_COUNT = 6;

	// EVERY index here is arm-anchored -- anchored to the live pose of the arm
	// that WEARS it (AttackPos/Angle/Pitch/Roll for the main bank,
	// OffhandPos/Angle/Pitch/Roll for the off bank) rather than to the head or
	// a torso, because that is what a thing strapped to your own arm actually
	// has to track.
	//
	//   0,1,2  MainWristBelow / MainWristKnuckle / MainWristJoint
	//   3,4,5  OffWristBelow  / OffWristKnuckle  / OffWristJoint
	//
	// TWO BANKS OF THREE, CLONED, not one bank with a hand argument threaded
	// through every function. That was a deliberate call and the reasoning
	// still holds: the one-bank pattern is proven, every consumer already
	// takes a plain index, and a parameterised version would touch far more
	// call sites for equivalent risk in a codebase with no test-compile. The
	// clone costs one extra predicate (isMainArmAnchor) and three extra table
	// rows; the parameterised version costs a signature change in anchorPos,
	// worldToHand, handBasisPose, updateGrabs, updateClaims, updateProps,
	// doSwap, fireGesture and every dump.
	//
	// The OFF bank kept indices 3-5 on purpose. Everything already hardcoded
	// to those numbers -- the three gesture-fire netevents and their KEYCONF
	// aliases, which the owner assigned per-button on 2026-08-25 -- keeps
	// exactly its current meaning, and the new bank takes the indices whose
	// old meaning (the forearm row) is going away anyway.
	//
	// HAND_HOLSTER_START is 0 rather than being deleted, and isHandAnchored()
	// still exists and still always returns true: this file was split out of
	// RS_Holsters, where indices 0-7 were torso-anchored and 8-13 were these,
	// and isHandAnchored(idx) was the predicate every consumer branched on.
	// Keeping the predicate (rather than tearing out its every call site by
	// hand, in a codebase with no way to test-compile) means the split is a
	// change to ONE constant instead of edits scattered through anchor
	// placement, orientation, edit-mode dragging and claim arbitration.
	// The torso branches those calls guard are now unreachable, deliberately.
	const HAND_HOLSTER_START = 0;

	// Where the OFF arm's bank starts, and how wide a bank is. These two
	// replace FOREARM_HOLSTER_END, which used to be 3 as well but meant
	// something completely different ("index of the first WRIST mount on the
	// one and only arm"). Deleted rather than repurposed: a constant whose
	// value stays the same while its meaning inverts is exactly the sort of
	// thing that survives a refactor and then quietly reads backwards.
	const OFF_WRIST_START = 3;
	const WRIST_PER_ARM   = 3;

	// ------------------------------------------------------------------
	// DEFERRED: THE FOREARM TIER.
	//
	// Indices 0-2 used to be Forearm1/2/3 -- three mounts spaced back along
	// the off forearm toward the elbow. The owner deferred that tier on
	// 2026-08-26 (it was going to hold UTILITY items -- flares, shields,
	// usable inventory -- not weapons, and its content model is not built:
	// see CLAUDE.md on contents[] being Array<Weapon> and a CustomInventory
	// flare having no Ready state for the prop to bind a model from). Its
	// menu rows are gone so they stop cluttering a menu they cannot serve.
	//
	// EVERYTHING LEARNED ABOUT IT IS PRESERVED HERE rather than deleted with
	// the code, because all of it was paid for in headset time:
	//
	//  * DEFAULT TABLE, hand-tuned starting values, in the same units the
	//    live table uses (hsFwd/hsSide/hsFrac in inches, hsRadius map units):
	//        Forearm1  fwd  -4.0  side 0.0  frac 0.0  radius 2.0
	//        Forearm2  fwd  -9.0  side 0.0  frac 0.0  radius 2.0
	//        Forearm3  fwd -14.0  side 0.0  frac 0.0  radius 2.0
	//    hsFwd negative means "back" along the arm's own aim vector; hsFrac
	//    0.0 means "right on the aim line", since there is no IK to say where
	//    the forearm's actual surface is. Radius 2.0 (a 4" catch volume) with
	//    5-unit spacing leaves a 1" gap between neighbours.
	//
	//  * FOREARM_YAW_CORRECTION = 90.0 DEGREES, determined empirically in
	//    headset (a red reference line drawn across a screenshot showing
	//    where the row should trail vs. where it actually rendered). The
	//    negative hsFwd already means "the reverse of forward" -- pointing
	//    back along the arm, per the owner's own framing: "if I were holding
	//    that SMG backwards, pointing 180, it would be pointing along my
	//    forearm." So the 90 is NOT that 180 -- it corrects a separate
	//    mismatch between the raw hand angle and where the held weapon
	//    visually appears to point, which this mod has no way to introspect
	//    (that gap is owned by the engine's own VR weapon rendering, not by
	//    RS_HardPointProp's model binding, which only corrects HOLSTERED
	//    props via level.GetModelOrientationHint -- there is no equivalent
	//    hint for a weapon actively held in a hand). If it ever overshoots or
	//    undershoots, the fix is changing that one number, not re-deriving
	//    the geometry.
	//
	//  * FOREARM PITCH WAS FORCED TO 0, not read live, and that is a
	//    confirmed headset finding, not a simplification. Tilting the hand's
	//    gun down swung Forearm1-3 the WRONG way (up, mirrored) instead of
	//    leaving them roughly put, because a pure 180-degree reversal of a
	//    downward-tilted vector points backward-and-UP -- mathematically
	//    correct for "the exact reverse of wherever the controller points
	//    this instant", physically wrong for "my forearm", which does not
	//    flip upside down just because I flex my wrist. With no elbow
	//    tracking there is no real forearm direction to use, so the stand-in
	//    was: forearm mounts follow the arm's YAW only and ignore wrist
	//    PITCH entirely, for both position and the stored item's own
	//    orientation. A forearm-mounted item should sit level and stay level.
	//
	//  * REJECTED APPROACH, kept so it does not get re-tried: an earlier
	//    version had Forearm1-3 track the MAIN hand's aim instead of the arm
	//    they sit on, on the theory that the wearing hand's own orientation
	//    would be unreliably canted by gripping a foregrip. In headset
	//    testing this changed nothing visible and the premise was rejected
	//    outright -- "it doesn't matter what hand i have a gun in, just put
	//    three hardpoints on the offhand behind the controller position."
	//    It is the arm's own rig, full stop, not a weapon-aim-tracking
	//    accessory rail.
	//
	// The WRIST mounts never wanted any of that: they sit at the hand, not
	// back along a limb the tracker cannot see, so they read live pitch and
	// take no yaw correction -- which is why handBasisPose is now a plain
	// per-arm pose read with no special case in it at all.
	// ------------------------------------------------------------------

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
	// hsFwd/hsSide/hsFrac are raw map-unit (inch) offsets, always from the
	// WEARING hand's own position (AttackPos for the main bank, OffhandPos
	// for the off bank) and along that same hand's own live forward/right/up
	// axes -- see handBasisPose/handAnchorPos/handOrigin -- and
	// hsPitch/hsYaw/hsRoll are TRIMS added on top of that basis, not absolute
	// angles (see updateProps' baseAngle/basePitch/baseRoll).
	//
	// Doom's player scale puts a map unit at roughly one real inch (player
	// radius 16 ~ a person's half shoulder width), so these read as inches.
	static void GetHolster(int idx, out string hsName, out double hsFwd, out double hsSide, out double hsFrac, out double hsRadius,
	                       out double hsPitch, out double hsYaw, out double hsRoll)
	{
		// All trims, so all zero -- these are offsets ON TOP of the hand's
		// own live pose, and a nonzero default here would silently cant
		// every hardpoint off the arm it is supposed to be strapped to.
		hsPitch = 0.0; hsYaw = 0.0; hsRoll = 0.0;

		// TWO BANKS OF THREE WRIST MOUNTS, one per arm. Identical shape,
		// identical numbers except for the hsSide mirror -- see below.
		//
		// hsFrac here is local "up" inches (negative = below), not a
		// fraction of anything. (The fraction-of-eye-height reading only
		// ever applied to the torso branch of anchorPos, which is
		// unreachable in this fork.)
		//
		// Owner's own reference pose: hand outstretched holding a pistol,
		// pistol at the top of the hand. Below/Knuckle/Joint aren't
		// symmetric -- Knuckle sits slightly FORWARD (toward the fingers,
		// +hsFwd) and Joint sits slightly BACK (toward the actual wrist
		// joint, -hsFwd), not just mirrored left/right at the same depth.
		//
		// Left/right sign is HAND-LOCAL (edSide rides the rx/ry basis in
		// handAnchorPos, built from that hand's own yaw), so which physical
		// side each name lands on depends on that hand's own resting yaw.
		// The main bank's hsSide is the NEGATIVE of the off bank's for
		// exactly that reason: with both hands pointing the same way, the
		// two banks' local right vectors point the same way in world space
		// too, so identical hsSide would stack both banks on the same side
		// of the body rather than mirroring them onto each arm's outer
		// side the way a real pair of wrist rigs sits. That mirror is a
		// STARTING GUESS about which side is "outer", not a measurement --
		// same status as every other number in this table. Edit mode is
		// what settles it; these just need to be in the right
		// neighbourhood so there is something to grab and drag.
		switch (idx)
		{
			// ---- MAIN arm (anchored to AttackPos and the main hand's own
			// live angle/pitch/roll; reached by the OFF hand) ----
			case 0:
				hsName = "MainWristBelow";   hsFwd =  0.0; hsSide =  0.0; hsFrac = -3.0; hsRadius = 2.0; break;
			case 1:
				hsName = "MainWristKnuckle"; hsFwd =  2.5; hsSide =  3.0; hsFrac =  0.0; hsRadius = 2.0; break;
			case 2:
				hsName = "MainWristJoint";   hsFwd = -2.5; hsSide = -3.0; hsFrac =  0.0; hsRadius = 2.0; break;

			// ---- OFF arm (anchored to OffhandPos and the off hand's own
			// live angle/pitch/roll; reached by the MAIN hand). These three
			// keep the exact numbers the single-arm rig shipped with, and
			// the exact indices the gesture-fire netevents are hardcoded to
			// -- nothing about the off bank changed in the re-layout. ----
			case 3:
				hsName = "OffWristBelow";    hsFwd =  0.0; hsSide =  0.0; hsFrac = -3.0; hsRadius = 2.0; break;
			case 4:
				hsName = "OffWristKnuckle";  hsFwd =  2.5; hsSide = -3.0; hsFrac =  0.0; hsRadius = 2.0; break;
			default: // case 5, and a defensive fallback for idx >= HOLSTER_COUNT
				hsName = "OffWristJoint";    hsFwd = -2.5; hsSide =  3.0; hsFrac =  0.0; hsRadius = 2.0; break;
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

	// One prop per holster per player, flattened like contents. Held as
	// pointers so a destroyed prop (level change, player death) reads null and
	// gets respawned rather than leaving a dangling anchor.
	Array<RS_HardPointProp> props;
	Array<RS_HardPointMarker> markers;

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

	// PER PLAYER as of 2026-08-26, where all three used to be one global
	// each. The edit TABLE above stays deliberately global -- one person
	// wears the headset, and there is one set of anchors to tune -- but
	// "is this player editing" and "which sphere is this hand dragging"
	// are not tuning values, they are live per-hand state. As single
	// globals, a second player toggling edit mode dropped the first
	// player's sphere mid-drag, and either player's grab overwrote the
	// other's.
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

	// GESTURE-CAST arming: palm-out/open-palm pose (the wrist rolled away
	// from a normal weapon grip). Roll only -- see updateGestureArm for why
	// yaw/pitch/position play no part. Latched per player so the rising edge
	// can get its own confirm haptic, the same "short tap on ENTER only"
	// pattern updateClaims already uses for holster-range haptics.
	//
	// ONE PER ARM as of the 2026-08-26 re-layout, where there used to be one
	// (off hand only). Each arm arms ITSELF for ITS OWN three mounts: the arm
	// that wears a mount is the arm that rolls palm-out to fire it. That is
	// the reverse of the STORE/DRAW direction, where a hand can only ever
	// reach the OTHER arm's bank -- and it is not a contradiction, it is the
	// two verbs: HOLSTERS DRAW, WRISTS FIRE. You reach across to load a
	// mount; you roll your own wrist to shoot it.
	bool gestureArmed[MAXPLAYERS];      // OFF arm, mounts 3-5
	bool gestureArmedMain[MAXPLAYERS];  // MAIN arm, mounts 0-2

	// What the off hand held BEFORE the first gesture-fire of this armed
	// stretch, null when nothing is currently gesture-seated. Captured once
	// on the first fire after arming, not on every fire -- so firing HP1
	// then HP2 then HP3 in the same armed stretch always restores the ONE
	// real weapon you started with, not whatever the previous hardpoint
	// press left seated. Restored (and cleared) the instant gestureArmed
	// drops, in updateGestureArm -- see there.
	Array<Weapon> gesturePreviousOff;

	// The FORWARD pointer, and deliberately a separate field from
	// gesturePreviousOff above rather than derived from it: whichever
	// hardpoint weapon fireGesture currently has seated in the off hand,
	// null when none. Two jobs, both of which need an exact instance and
	// neither of which gesturePreviousOff can answer:
	//
	//  1. updateProps' reconciliation pass sees a contents[] weapon sitting
	//     in a hand and concludes it "drifted back" -- which is true for an
	//     ammo-pickup re-arm and false for a gesture-fire. Firing a mount
	//     therefore EMPTIED it on the very next tic, clearing the mount's
	//     own stow flags with it. That check now skips this one instance.
	//  2. The stow flags (bNoAutoSwitchTo/bHolsterHidden) have to come OFF
	//     for the weapon to fire at all (CheckAmmo gates firing on
	//     bHolsterHidden) and go back ON when it returns to the mount --
	//     which needs to know exactly which instance is out.
	//
	// NOT folded into gesturePreviousOff: that array is the backup/restore
	// stack for the player's REAL off-hand weapon and is owned by the grip
	// arbiter work in progress. This is a different fact about a different
	// weapon, so it gets its own storage rather than overloading that one.
	Array<Weapon> gestureSeatedOff;

	// The MAIN arm's pair of the two arrays above, added with the 2026-08-26
	// re-layout so the main bank (mounts 0-2) can fire in place the same way
	// the off bank always could. Every word of the two comments above applies
	// unchanged, with ReadyWeapon substituted for OffhandWeapon and PSP_WEAPON
	// for PSP_OFFHANDWEAPON.
	//
	// SEPARATE ARRAYS, NOT one array indexed by hand: a hand index would have
	// to be threaded through ensureGesture*, releasePlayer, updateProps'
	// reconciliation exemption and both edges of updateGestureArm, and the
	// flattened-array trap this file already documents twice (an int
	// zero-default reading as a VALID index) is exactly what that invites.
	// Two named arrays cannot be indexed with the wrong hand by accident.
	Array<Weapon> gesturePreviousMain;
	Array<Weapon> gestureSeatedMain;

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

	// GESTURE-CAST arming needs the same treatment CLAIM_HYSTERESIS gives
	// proximity, and for the same reason: a wrist held near the threshold
	// crosses it many times a second, and every crossing is a haptic tap
	// plus (on the falling edge) a real weapon swap back into the off hand.
	// Proximity chatter is merely confusing; arming chatter yanks the gun
	// out of your hand and puts it back several times a second. Enter at
	// the tolerance, leave only past tolerance * this.
	const GESTURE_ROLL_HYSTERESIS = 1.35;

	const CALIBRATE_MAX_TRIES = 35; // ~1 second, then stop rather than loop forever
	const EYE_MIN = 36.0;           // sanity floor, map units (~3 feet)
	const EYE_MAX = 96.0;           // sanity ceiling (~8 feet)

	override void WorldTick()
	{
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

			updateBodyYaw(i, pawn);
			updateGrabs(i, pawn);
			// BEFORE updateClaims -- updateClaims' own HardpointClaim* writes
			// OR the armed flags in (see there), so both arm checks have to
			// have already run this tic.
			updateGestureArm(i, pawn);
			updateGestureArmMain(i, pawn);
			updateClaims(i, pawn); // also repositions props, via updateProps

			// Throttled live dump of each arm's raw pitch plus the resulting
			// wrist anchor positions, gated on that arm's bank actually being
			// on. Built for one question: do the three mounts move the way a
			// real tilt of the hand should, or backward?
			// (GlowInTheDark's GITD_Flashlight hit OffhandPitch being
			// stored negated at the engine level and documented it against
			// real engine source -- see that file's ResolveMount.) Printed
			// raw rather than pre-judged: hsFwd/hsSide/hsFrac differ across
			// all three wrist slots, so one prediction does not obviously
			// hold the same way for all three -- read the numbers against
			// the actual tilt rather than trusting a guess about the sign.
			// GATED BEHIND rs_hardpoint_wristdump AS OF 2026-08-26. This block
			// was previously reached whenever the wrist tier was active, so a
			// shipped build printed two lines every 10 tics -- roughly 7 lines
			// a second -- into the player's console. The diagnostic is kept
			// because the hypothesis it tests is still open; it just no longer
			// runs by default.
			//
			// PER ARM as of the re-layout, and printing BOTH is the point: the
			// open question (handBasisPose reading pitch RAW while every other
			// consumer in the family negates it) now has two independent
			// witnesses on two controllers, so a sign error shows up as both
			// banks being wrong the same way rather than as one ambiguous set
			// of numbers.
			let cWristDump = CVar.GetCVar("rs_hardpoint_wristdump", pawn.player);
			bool wantDump = (cWristDump != null) && cWristDump.GetBool();
			if (wantDump && (level.time % 10) == 0)
			{
				if (wristTierLive(true))
				{
					Vector3 mBelowP = anchorPos(i, pawn, 0);
					Vector3 mKnuckP = anchorPos(i, pawn, 1);
					Vector3 mJointP = anchorPos(i, pawn, 2);
					// MainHandRoll, not AttackRoll -- and this line matters more
					// than the others, because it is the INSTRUMENT the roll
					// target is tuned with. AttackRoll is zeroed by the playsim
					// every tic (p_user.cpp:134, inside P_PlayerThink, which
					// p_tick.cpp:501 runs three lines before WorldTick at :504),
					// so this dump printed a constant 0.0 no matter how the
					// wrist was actually turned -- and any target value dialled
					// in from it would have been wrong.
					Console.Printf("RS_HARDPOINT wrist-pitch MAIN: raw AttackPitch=%.1f MainHandRoll=%.1f AttackAngle=%.1f  gesture-armed=%d (target=%.1f tol=%.1f)",
						pawn.AttackPitch, pawn.MainHandRoll, pawn.AttackAngle,
						gestureArmedMain[i], gestureRollTarget(), gestureRollTolerance());
					Console.Printf("  Below  %.1f,%.1f,%.1f   Knuckle %.1f,%.1f,%.1f   Joint %.1f,%.1f,%.1f",
						mBelowP.X, mBelowP.Y, mBelowP.Z, mKnuckP.X, mKnuckP.Y, mKnuckP.Z, mJointP.X, mJointP.Y, mJointP.Z);
				}
				if (wristTierLive(false))
				{
					Vector3 belowP = anchorPos(i, pawn, 3);
					Vector3 knuckP = anchorPos(i, pawn, 4);
					Vector3 jointP = anchorPos(i, pawn, 5);
					Console.Printf("RS_HARDPOINT wrist-pitch OFF: raw OffhandPitch=%.1f OffhandRoll=%.1f OffhandAngle=%.1f  gesture-armed=%d (target=%.1f tol=%.1f)",
						pawn.OffhandPitch, pawn.OffhandRoll, pawn.OffhandAngle,
						gestureArmed[i], gestureRollTarget(), gestureRollTolerance());
					Console.Printf("  Below  %.1f,%.1f,%.1f   Knuckle %.1f,%.1f,%.1f   Joint %.1f,%.1f,%.1f",
						belowP.X, belowP.Y, belowP.Z, knuckP.X, knuckP.Y, knuckP.Z, jointP.X, jointP.Y, jointP.Z);
				}
			}

			// Consume a dump queued by last tic's store, now that this tic's
			// updateClaims has actually moved the prop into place.
			if (pendingDump[i] >= 0)
			{
				Console.Printf("\c[Gold]--- RS_HARDPOINT auto (stored) ---");
				dumpOneHolsterProp(i, pawn, pendingDump[i]);
				pendingDump[i] = -1;
			}
		}
	}

	// ------------------------------------------------------------------
	// LIFECYCLE. There was none of this at all until 2026-08-26 -- the only
	// overrides in this class were WorldTick and NetworkProcess -- and the
	// consequences were not cosmetic.
	//
	// This handler is registered through MAPINFO's AddEventHandlers, which
	// makes it a PER-LEVEL handler: a new instance is constructed for every
	// map, so every field here (contents[], the edit table, eyeHeight[]) is
	// wiped on any level change. The WEAPONS are not wiped -- they travel
	// with the player. So a stowed weapon crossed the exit line carrying
	// bHolsterHidden = true with the only code that ever clears it left
	// behind on the previous map. This file's own doSwap comment spells out
	// what that flag does: CheckAmmo refuses to let a bHolsterHidden weapon
	// FIRE, and refuses to let weapnext/weapprev cycle to it. Nothing else
	// clears it. The weapon was permanently, silently bricked -- in
	// inventory, un-fireable, unreachable, for the rest of the run.
	//
	// Same shape on death: contents[] and the props kept pointing at the
	// corpse's weapons.
	// ------------------------------------------------------------------

	// The pawn is gone or going. Hand every stowed weapon back its flags
	// while the pointers are still good, then forget them.
	override void PlayerDied(PlayerEvent e)
	{
		releasePlayer(e.PlayerNumber, true);
	}

	// A brand new pawn with a brand new inventory. The old contents[]
	// pointers describe weapons that are not this player's any more, and
	// re-measuring eye height is right anyway -- the respawn may well be at
	// a different floor height than the calibration was taken at.
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
	// they do not stop EXISTING. Six props plus six markers per player were
	// left parked and visible at whatever world position they last held.
	override void PlayerDisconnected(PlayerEvent e)
	{
		releasePlayer(e.PlayerNumber, true);
		despawnPlayerActors(e.PlayerNumber);
	}

	// Leaving the level: unflag everything BEFORE this handler (and its
	// contents[] table) ceases to exist, which is the only moment the
	// mapping from weapon to "is stowed" still exists at all.
	override void WorldUnloaded(WorldEvent e)
	{
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			releasePlayer(i, true);
			despawnPlayerActors(i);
		}
	}

	override void WorldLoaded(WorldEvent e)
	{
		// A savegame restores this handler's OWN fields, contents[] included,
		// so the weapons it describes are legitimately still stowed and the
		// sweep below would wrongly un-stow every one of them. Only a
		// genuinely fresh level needs any of this.
		if (e.IsSaveGame)
			return;

		// The backstop for the bricking described above. WorldUnloaded is the
		// primary fix, but it cannot help a weapon that was stowed by a build
		// (or a session) where none of this existed, and it never runs at all
		// on the first map of a session. Sweeping inventory here catches both.
		// Safe to run against weapons this mod never stowed: at this point
		// contents[] is empty for every player, so "stowed" is a state nothing
		// on this map claims -- including RS_Holsters, whose own table was
		// wiped by the same level change.
		for (int i = 0; i < MAXPLAYERS; ++i)
		{
			if (!playeringame[i] || players[i].mo == null)
				continue;
			unstowInventory(players[i].mo);
		}

		// And the tuned layout, which until now had to be loaded by hand
		// after EVERY map change -- edInit is a per-level field, so
		// ensureEdit reseeded the placeholder table from GetHolster's switch
		// on every single level load and threw away whatever the player had
		// dragged and saved. Saving a layout that only survives until the
		// next door is not persistence.
		autoLoadLayout();
	}

	// Give every weapon this player owns its ordinary flags back. Walks
	// inventory rather than contents[], deliberately: the whole failure this
	// exists for is a weapon whose stowing manager no longer exists to be
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

	// Empty one player's table. unflag=false exists for the case where the
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

		// Gesture-cast state dies with the pawn too. An armed flag staying
		// true across a death would keep that hand's HardpointClaim pinned on
		// the new pawn from its first tic, and the seated pointer would still
		// name a weapon on a body that no longer exists.
		//
		// BOTH ARMS, as of the 2026-08-26 re-layout. Missing the main-arm
		// pair here would be the same bug this block exists to prevent, just
		// on the other controller -- and it would be invisible, because the
		// off-arm half would still look correct.
		gestureArmed[i] = false;
		gestureArmedMain[i] = false;
		ensureGestureSeatedOff();
		ensureGestureSeatedMain();
		gestureSeatedOff[i] = null;
		gestureSeatedMain[i] = null;

		// And the backup pointers. Clearing the armed flags above means the
		// falling edge in updateGestureArm/updateGestureArmMain can never fire
		// for this player again (it needs a wasArmed -> !nowArmed transition,
		// and wasArmed is now false), so anything left here would sit stale
		// forever: the next armed stretch's FIRST fire would see a non-null
		// capture, skip capturing the live weapon, and then "restore" a dead
		// body's weapon into a living player's hand on disarm.
		//
		// SCOPE NOTE for whoever is building the grip arbiter: this nulls a
		// stale pointer at the one moment the pawn it belongs to stops
		// existing. It does not change how the capture/restore protocol
		// works. Leave updateGestureArm's own restore branch alone.
		ensureGesturePreviousOff();
		ensureGesturePreviousMain();
		gesturePreviousOff[i] = null;
		gesturePreviousMain[i] = null;
	}

	// Destroy this player's six props and six markers. updateProps respawns
	// any that are null the next time it runs for a live player, so this is
	// safe to call on a player who might come back.
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

	// Pull the saved layout in on level load, quietly.
	//
	// The two-step (test with the native, then go through loadProfile) is
	// there so a player who has never saved a layout does not get a red
	// "no layout on disk" line on every single map change for the rest of
	// the run. level.JSONProfileLoad is idempotent -- it clears its buffer
	// and re-parses the same file -- so calling it twice costs one extra
	// read of a file measured in hundreds of bytes, and buys the ordinary
	// case a silent no-op. Going through loadProfile rather than reading the
	// keys here keeps ONE copy of the per-field GetHolster fallback logic.
	private void autoLoadLayout()
	{
		ensureEdit();
		if (level.JSONProfileLoad("hardpoint_layout"))
			loadProfile("hardpoint_layout");
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
			// Never got a plausible reading. Fall back to the pawn's own
			// height so holsters still exist, rather than silently doing
			// nothing forever with no indication why.
			eyeHeight[i] = pawn.Height * 0.9;
			calibrated[i] = true;
			Console.Printf("RS_HARDPOINT: calibration timed out, using fallback eye height %.1f", eyeHeight[i]);
			return;
		}

		// A zero HmdPos means the VR backend has not written a head pose into
		// the field yet -- distinct from "the player is standing somewhere
		// implausible". Called out separately because it is the failure that
		// looks identical to "nothing is happening" from the outside.
		if (pawn.HmdPos.Length() == 0)
		{
			if (spawnTries[i] == CALIBRATE_MAX_TRIES)
				Console.Printf("\cgRS_HARDPOINT: HmdPos is zero -- engine is not writing head pose. Holsters cannot work.");
			return;
		}

		double measured = pawn.HmdPos.Z - pawn.floorz;
		if (measured < EYE_MIN || measured > EYE_MAX)
		{
			if (spawnTries[i] == CALIBRATE_MAX_TRIES)
				Console.Printf("\cgRS_HARDPOINT: eye height %.1f outside sane range %.0f-%.0f (HmdPos.Z %.1f, floor %.1f)",
					measured, EYE_MIN, EYE_MAX, pawn.HmdPos.Z, pawn.floorz);
			return;
		}

		eyeHeight[i] = measured;
		calibrated[i] = true;
		Console.Printf("RS_HARDPOINT: calibrated standing eye height %.1f map units", measured);
	}

	// For a bindable recalibrate command (sat down during the auto sample,
	// playspace floor changed).
	void ForceRecalibrate(int playerNum)
	{
		if (playerNum < 0 || playerNum >= MAXPLAYERS)
			return;
		calibrated[playerNum] = false;
		spawnTries[playerNum] = 0;
	}

	// Seed the live offsets from the default table, once.
	private void ensureEdit()
	{
		if (edInit)
			return;
		edInit = true;
		// -1 for every player, not just the console one: int arrays default
		// to 0, which is holster 0, so an unseeded entry reads as "this hand
		// is dragging MainWristBelow" the first time updateGrabs looks at it.
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

		// Wrist hardpoints track the WEARING hand's own live pose, not the
		// torso -- a completely different basis, so it is its own function
		// rather than a few more branches folded into this one.
		if (isHandAnchored(idx))
			return handAnchorPos(pawn, idx);

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

	// Is this anchor mounted on the MAIN arm? The one predicate the whole
	// two-bank clone turns on -- position, basis, origin, which hand may
	// claim it, which hand arms it, and which half of the saved layout it
	// belongs to all branch here and nowhere else.
	//
	// const, because holsterActive() is const and calls it. A const method may
	// only call const methods (the 4.15.1 SafeConst rule this repo's methods
	// were checked against); the holsterActive -> armMode pair this replaced
	// was already that exact shape, and holsterActive -> wristCount still is.
	private bool isMainArmAnchor(int idx) const
	{
		return idx < OFF_WRIST_START;
	}

	// Which hand's live position an anchor hangs off. Split out rather than
	// written inline at its two call sites (handAnchorPos and its inverse
	// worldToHand) so "which arm wears this mount" is answered in exactly one
	// place -- the same reasoning handBasisPose was factored out under, one
	// function below, and the same reason the two of them must always agree:
	// a mount positioned from one hand and oriented from the other would look
	// almost right and drift wrong.
	//
	// This exact function already exists in the family and is the shape
	// copied here: RS_Reload/zscript/rr_point.zs:71-73,
	//     static Vector3 HandPos(PlayerPawn pmo, int hand)
	//     { return (hand == 0) ? pmo.AttackPos : pmo.OffhandPos; }
	// -- so both halves of what looked risky (a method returning a Vector3
	// FIELD rather than a constructed vector, and a ternary whose arms are
	// Vector3) are proven, not assumed. Kept as its own predicate-driven
	// version rather than a call into RS_Reload because this pk3 does not
	// depend on that one and must not start.
	private Vector3 handOrigin(PlayerPawn pawn, int idx)
	{
		return isMainArmAnchor(idx) ? pawn.AttackPos : pawn.OffhandPos;
	}

	// The live angle/pitch/roll an arm-anchored holster's basis is built
	// from: the WEARING hand's own live pose, unconditionally, for both
	// position (handAnchorPos/worldToHand, which only read ang/pit -- position
	// deliberately ignores roll, see handAnchorPos' own comment) and
	// orientation (updateProps/dumpOneHolsterProp/updateGrabs, which need
	// all three). A single small function rather than reading
	// pawn.AttackAngle/Pitch/Roll or pawn.OffhandAngle/Pitch/Roll inline at
	// every call site so there is one place to touch if that ever needs to
	// change again.
	//
	// NO SPECIAL CASE LEFT IN IT as of the 2026-08-26 re-layout. This used to
	// branch on `idx < FOREARM_HOLSTER_END` to add FOREARM_YAW_CORRECTION and
	// force pitch to 0 for the forearm row. Every mount is a WRIST mount now,
	// and a wrist mount sits at the hand rather than back along a limb the
	// tracker cannot see -- so it reads live pitch and takes no yaw
	// correction, which is what the wrist trio always did. The forearm
	// findings (the 90 degrees, and WHY pitch had to be forced flat) are
	// preserved verbatim in the DEFERRED block on the constants at the top of
	// this class; they were expensive to get and this tier is coming back.
	private void handBasisPose(PlayerPawn pawn, int idx, out double ang, out double pit, out double rol)
	{
		if (isMainArmAnchor(idx))
		{
			ang = pawn.AttackAngle;
			// NEGATED. AttackPitch/OffhandPitch are stored negated by the
			// engine -- every correct consumer in this family flips it back
			// on read; RS_Reload's rr_point.zs:Pit() is the precedent,
			// `return -((hand == 0) ? pmo.AttackPitch : pmo.OffhandPitch);`.
			// This read it raw, so a wrist mount pitched the opposite way
			// from an actual tilt of the wrist -- tilt the gun up and the
			// mount swung down. Level wrist reads 0 either way, which is
			// why this survived: it looks correct until you actually tip
			// your hand.
			pit = -pawn.AttackPitch;
			// MainHandRoll, not AttackRoll. The playsim zeroes AttackRoll every
			// tic (p_user.cpp:134) and does it in P_PlayerThink, which
			// p_tick.cpp:501 runs three lines before WorldTick at :504 -- so
			// script always reads a hard zero from it. The engine documents
			// exactly this at actor.zs:378-383: it "left script believing the
			// wrist was level while the held model rolled with it."
			rol = pawn.MainHandRoll;
		}
		else
		{
			ang = pawn.OffhandAngle;
			pit = -pawn.OffhandPitch;
			rol = pawn.OffhandRoll;
		}
	}

	// World-space position of one ARM-anchored holster (every index in this
	// fork): the hand-relative counterpart to anchorPos, above. ORIGIN is the
	// wearing hand's own position via handOrigin -- these are physically ON
	// that arm -- and the forward/right/up BASIS comes from handBasisPose,
	// the same hand's own live angle/pitch. Same local-basis shape already
	// proven in updateProps' trim-slider math (localFwdX/localUpX/rightX
	// there) and in RS_Main's RS_GrenadeThrower.Throw (positive pitch looks
	// DOWN in this engine, hence the negated Z on forward/up), just
	// re-sourced here.
	// Deliberately yaw+pitch only, NOT roll -- rolling the wearing hand will
	// visibly rotate whatever is mounted here (updateProps carries roll into
	// orientation) but will not swing the ANCHOR POSITION around the arm.
	// Known v1 gap, not an oversight: this is the #1 thing to look at in
	// headset before guessing at a roll-aware basis blind (see the plan/
	// CLAUDE.md notes on this file's two previous wrong hand-derived
	// rotation attempts).
	private Vector3 handAnchorPos(PlayerPawn pawn, int idx)
	{
		double ang, pit, unusedRoll;
		handBasisPose(pawn, idx, ang, pit, unusedRoll);

		double fx =  cos(ang) * cos(pit);
		double fy =  sin(ang) * cos(pit);
		double fz = -sin(pit);
		double rx = sin(ang);
		double ry = -cos(ang);   // right is yaw-only, matches anchorPos' rx/ry
		// up = right x forward (verified by direct cross-product expansion
		// at pit=0, where forward/right/up must reduce to the familiar
		// facing/right/world-up trio) -- NOT the -cos/-sin signs the prop
		// trim sliders in updateProps use, which get away with being
		// inverted because they are a symmetric bidirectional knob nobody
		// would notice the polarity of. hsFrac has a HARD physical meaning
		// here (WristBelow's -3.0 means "below", full stop), so the sign
		// has to be actually correct, not just self-consistent.
		double upx = cos(ang) * sin(pit);
		double upy = sin(ang) * sin(pit);
		double upz = cos(pit);

		// ORIGIN is the WEARING hand's own position -- AttackPos for the main
		// bank, OffhandPos for the off bank. Read through handOrigin rather
		// than pawn.OffhandPos directly, which is what this line used to say
		// back when every mount rode one arm.
		Vector3 org = handOrigin(pawn, idx);

		return (
			org.X + (edFwd[idx] * fx) + (edSide[idx] * rx) + (edFrac[idx] * upx),
			org.Y + (edFwd[idx] * fy) + (edSide[idx] * ry) + (edFrac[idx] * upy),
			org.Z + (edFwd[idx] * fz)                      + (edFrac[idx] * upz)
		);
	}

	// The inverse of handAnchorPos, mirroring how worldToBody inverts
	// anchorPos -- what makes edit mode able to drag a wrist sphere and read
	// hand-local offsets straight back out. oUp takes the third out-param
	// name (not oFrac) because it is a raw inch offset here, never a fraction
	// of anything. Takes idx not just to index the ed* arrays --
	// handBasisPose and handOrigin both need it too, to know which arm this
	// mount rides.
	private void worldToHand(PlayerPawn pawn, int idx, Vector3 world, out double oFwd, out double oSide, out double oUp)
	{
		double ang, pit, unusedRoll;
		handBasisPose(pawn, idx, ang, pit, unusedRoll);

		double fx = cos(ang) * cos(pit),  fy = sin(ang) * cos(pit),  fz = -sin(pit);
		double rx = sin(ang), ry = -cos(ang);
		// up = right x forward -- see handAnchorPos' own comment on this
		// exact formula for why it is NOT the same sign as updateProps'
		// prop-trim basis.
		double upx = cos(ang) * sin(pit), upy = sin(ang) * sin(pit), upz = cos(pit);

		// Same per-arm origin handAnchorPos uses. Mixing the two would put a
		// dragged sphere somewhere other than the hand that dropped it -- the
		// hand-anchored twin of the bodyYaw-vs-HmdYaw warning on worldToBody.
		Vector3 org = handOrigin(pawn, idx);

		double dx = world.X - org.X;
		double dy = world.Y - org.Y;
		double dz = world.Z - org.Z;

		oFwd  = (dx * fx)  + (dy * fy)  + (dz * fz);
		oSide = (dx * rx)  + (dy * ry);
		oUp   = (dx * upx) + (dy * upy) + (dz * upz);
	}

	// While a holster is grabbed, it simply lives wherever that hand is.
	private void updateGrabs(int i, PlayerPawn pawn)
	{
		// FIRST, before either array is read. grabbedMain/grabbedOff are int
		// arrays, so their zero-default is holster 0 rather than "nothing" --
		// see their declaration. WorldTick calls this BEFORE updateClaims,
		// which is the only other thing that reaches ensureEdit (via
		// anchorPos), so without this the very first calibrated tic dragged
		// holster 0 to wherever the main hand was.
		ensureEdit();

		int gm = grabbedMain[i];
		int go = grabbedOff[i];

		// Position AND orientation follow the hand, so a holster is placed the
		// way you would actually place one: hold your hand where the gun goes,
		// angled how the gun should sit, and let go.
		// BOTH BRANCHES ARE LIVE as of the 2026-08-26 re-layout, where the
		// off-hand one was structurally unreachable. updateClaims lets a hand
		// claim only the OTHER arm's bank, so:
		//   grabbedMain can only ever hold an OFF-arm index  (3-5)
		//   grabbedOff  can only ever hold a  MAIN-arm index (0-2)
		// -- which is precisely what makes each drag meaningful: the dragging
		// hand and the basis hand are always different hands, so the captured
		// orientation delta says something.
		if (gm >= 0)
		{
			if (isHandAnchored(gm))
			{
				// Position always updates -- this is what lets you drag a
				// wrist sphere to a new spot on the other arm either way.
				worldToHand(pawn, gm, pawn.AttackPos, edFwd[gm], edSide[gm], edFrac[gm]);

				// Orientation trim is captured RELATIVE to the WEARING hand's
				// own basis pose (handBasisPose), same idea as edYaw being
				// relative to bodyYaw for the torso case below -- the
				// dragging hand (main) and the basis hand (off, since gm is
				// always an off-arm index here) are always different hands,
				// so this delta is always meaningful.
				double bAng, bPit, bRol;
				handBasisPose(pawn, gm, bAng, bPit, bRol);
				edYaw[gm]   = normalizeDeg(pawn.AttackAngle - bAng);
				// NEGATED, to match handBasisPose's own fix -- bPit now comes
				// back true-signed (handBasisPose negates AttackPitch itself),
				// so the raw field on this side has to match or the
				// subtraction mixes two different sign conventions and gets a
				// delta that is wrong in a NEW way, not just inverted.
				edPitch[gm] = normalizeDeg(-pawn.AttackPitch - bPit);
				// MainHandRoll -- AttackRoll is a playsim-zeroed constant in
				// script (see handBasisPose), so this captured -bRol rather
				// than the wrist angle the mount was actually dragged to.
				edRoll[gm]  = normalizeDeg(pawn.MainHandRoll - bRol);
			}
			else
			{
				worldToBody(i, pawn, pawn.AttackPos, edFwd[gm], edSide[gm], edFrac[gm]);
				// NEGATED, same reason as handBasisPose and the branch above --
				// this stores the wrist's TRUE pitch at capture time as a fixed
				// trim; storing the raw (negated-at-source) field here would
				// have applied that trim backwards every time it was consumed.
				edPitch[gm] = -pawn.AttackPitch;
				// MainHandRoll, same reason as the branch above -- AttackRoll
				// reads zero in script, so this stored 0 for every main-arm
				// mount no matter how the wrist was held while placing it.
				edRoll[gm]  = pawn.MainHandRoll;
				// yaw relative to the BODY, not the world, or the stored angle
				// would only be right while facing the direction you set it in
				edYaw[gm] = normalizeDeg(pawn.AttackAngle - bodyYaw[i]);
			}
		}
		if (go >= 0)
		{
			// THIS BRANCH USED TO NOT EXIST, and the comment that stood here
			// explained why: with every mount on the off arm, updateClaims
			// never let the off hand claim any of them, so grabbedOff could
			// never be a hand-anchored index and worldToHand -- whose origin
			// was hardcoded to pawn.OffhandPos -- had no meaningful answer
			// for "drag a wrist sphere with the hand it is mounted on".
			//
			// Both halves of that changed together. There is now a MAIN-arm
			// bank for the off hand to reach, and handOrigin makes
			// worldToHand's origin the wearing hand's, so dragging a main-arm
			// sphere with the off hand is exactly the mirror of the branch
			// above and is measured against the main hand's own pose. Adding
			// it back was the point of the re-layout, not an incidental tidy.
			if (isHandAnchored(go))
			{
				worldToHand(pawn, go, pawn.OffhandPos, edFwd[go], edSide[go], edFrac[go]);

				double bAngO, bPitO, bRolO;
				handBasisPose(pawn, go, bAngO, bPitO, bRolO);
				edYaw[go]   = normalizeDeg(pawn.OffhandAngle - bAngO);
				// NEGATED -- same reason as the main-hand branch above.
				edPitch[go] = normalizeDeg(-pawn.OffhandPitch - bPitO);
				edRoll[go]  = normalizeDeg(pawn.OffhandRoll  - bRolO);
			}
			else
			{
				worldToBody(i, pawn, pawn.OffhandPos, edFwd[go], edSide[go], edFrac[go]);
				// NEGATED, same reason as the main-hand branch above.
				edPitch[go] = -pawn.OffhandPitch;
				edRoll[go]  = pawn.OffhandRoll;
				edYaw[go] = normalizeDeg(pawn.OffhandAngle - bodyYaw[i]);
			}
		}
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
		Console.Printf("\c[Gold]--- RS_HARDPOINT TABLE (paste over GetHolster's switch) ---");
		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
			GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);
			Console.Printf("case %d: hsName = \"%s\"; hsFwd = %.2f; hsSide = %.2f; hsFrac = %.3f; hsRadius = %.1f; hsPitch = %.1f; hsYaw = %.1f; hsRoll = %.1f; break;",
				h, hsName, edFwd[h], edSide[h], edFrac[h], hsRadius, edPitch[h], edYaw[h], edRoll[h]);
		}
	}

	// ONE KEY PREFIX PER MOUNT, ARM-TAGGED: "m0_".."m2_" for the main arm's
	// three wrist mounts, "o0_".."o2_" for the off arm's.
	//
	// EACH ARM NEEDS ITS OWN SAVED LAYOUT -- the mounts sit relative to
	// whichever controller wears them, so one shared table cannot serve both.
	// The two banks are already separate indices in the ed* arrays, so what
	// this function really buys is that the KEY can never be ambiguous about
	// which arm it describes, and specifically that the OLD flat schema
	// ("h0_".."h5_", one bank of six where 0-2 meant the FOREARM row) cannot
	// be silently mistaken for the new one.
	//
	// That last part is not hypothetical. loadProfile falls back PER FIELD to
	// GetHolster's defaults rather than erroring, so a stale "h0_fwd = -4.0"
	// from the forearm era would have loaded straight into MainWristBelow and
	// parked it four inches back up the arm, with nothing printed to say why.
	// Under the new prefixes an old profile simply has no matching keys, every
	// field falls back to the new default, and the layout reads as "never
	// tuned" -- which is the honest description of it.
	//
	// String.Format("%d") with a plain int, matching the schema this replaced.
	private string profileKey(int h)
	{
		if (isMainArmAnchor(h))
			return String.Format("m%d_", h);
		return String.Format("o%d_", h - OFF_WRIST_START);
	}

	// Real persistence, replacing "read the console dump, hand-paste it into
	// GetHolster's switch, recompile". A profile is a flat JSON document keyed
	// "<arm><slot>_<field>" (see profileKey) -- level.JSONProfile* (E:\UZDXREMA
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
			string key = profileKey(h);
			level.JSONProfileSetDouble(key .. "fwd",   edFwd[h]);
			level.JSONProfileSetDouble(key .. "side",  edSide[h]);
			level.JSONProfileSetDouble(key .. "frac",  edFrac[h]);
			level.JSONProfileSetDouble(key .. "pitch", edPitch[h]);
			level.JSONProfileSetDouble(key .. "yaw",   edYaw[h]);
			level.JSONProfileSetDouble(key .. "roll",  edRoll[h]);
		}
		if (level.JSONProfileSave(name))
		{
			Console.Printf("\c[Gold]RS_HARDPOINT: saved layout \"%s\"", name);
		}
		else
			Console.Printf("\cgRS_HARDPOINT: could not save layout \"%s\" (bad name, or write failed)", name);
	}

	// Loads into the LIVE edit table, same as dragging every sphere by hand --
	// so it takes effect immediately (updateProps reads edFwd/etc every tic)
	// and a bad or missing layout just leaves the current table untouched
	// rather than zeroing anything out.
	private bool loadProfile(string name)
	{
		ensureEdit();
		if (!level.JSONProfileLoad(name))
		{
			Console.Printf("\cgRS_HARDPOINT: no layout \"%s\" on disk", name);
			return false;
		}
		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			// GetHolster's own defaults are the fallback per field, not 0 --
			// a profile saved before a 7th holster existed (hypothetically)
			// should not zero-pitch a field it never wrote. That same
			// per-field fallback is why the key schema had to change with the
			// re-layout rather than being reused: it never errors, so a stale
			// key that still MATCHES would be loaded in silence. See
			// profileKey.
			string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
			GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);

			string key = profileKey(h);
			edFwd[h]   = level.JSONProfileGetDouble(key .. "fwd",   hsFwd);
			edSide[h]  = level.JSONProfileGetDouble(key .. "side",  hsSide);
			edFrac[h]  = level.JSONProfileGetDouble(key .. "frac",  hsFrac);
			edPitch[h] = level.JSONProfileGetDouble(key .. "pitch", hsPitch);
			edYaw[h]   = level.JSONProfileGetDouble(key .. "yaw",   hsYaw);
			edRoll[h]  = level.JSONProfileGetDouble(key .. "roll",  hsRoll);
		}
		Console.Printf("\c[Gold]RS_HARDPOINT: loaded layout \"%s\"", name);
		return true;
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
		//
		// THE SELF-CLAIM EXCLUSION RIDES THESE TWO TESTS TOO, and it has to:
		// the widened re-test is the one place a claim can be kept without
		// the scan below ever looking at it, so a hand excluded from an index
		// down there but not up here would hold that index forever. Before
		// the re-layout that read `!isHandAnchored(prevOff)` -- always false,
		// because every index was off-arm gear. Now it is per bank: a hand may
		// keep only what it could have claimed in the first place, which is
		// the OTHER arm's bank.
		if (prevMain >= 0 && holsterActive(prevMain) && !isMainArmAnchor(prevMain))
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
		if (prevOff >= 0 && holsterActive(prevOff) && isMainArmAnchor(prevOff))
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
			// An inactive mount (its arm's bank switched off, or its count
			// dialed below this slot) is not visible and must not be
			// claimable either -- a hand should never be able to trigger a
			// store/draw on a mount it cannot see, hysteresis-held or not.
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

			// A HAND CAN NEVER CLAIM ITS OWN ARM'S GEAR, and that is a
			// structural fact rather than a tuning choice. For any index,
			// anchor is that arm's own hand position plus a rotation of that
			// SAME hand's own live basis, so |that hand - anchor| is the
			// constant sqrt(edFwd^2+edSide^2+edFrac^2) every tic, no matter
			// how the player moves -- never a meaningful "did the hand reach
			// it" test. Depending on tuned offsets that constant would land
			// either permanently inside the radius (the hand stuck claiming
			// its own wrist forever) or permanently outside (dead code) --
			// excluding the test outright is the only correct fix, not
			// something radius tuning could paper over.
			//
			// So each bank is reachable by exactly ONE hand: the other one.
			// This used to exclude only the off hand, because every index was
			// off-arm gear; the exclusion is now symmetric, which is what
			// gives nearOff real work for the first time.
			bool wornOnMain = isMainArmAnchor(h);

			if (!wornOnMain && !mainClaimed && (pawn.AttackPos - anchor).Length() < mainR)
			{
				mainClaimed = true;
				nearMain[i] = h;
			}

			if (wornOnMain && !offClaimed && (pawn.OffhandPos - anchor).Length() < offR)
			{
				offClaimed = true;
				nearOff[i] = h;
			}
		}

		// GESTURE-CAST folds in here too: while armed, that hand reads to the
		// engine's grip arbiter exactly like a real proximity claim would
		// (GRIPCTX_Hardpoint -> GRIPSUBJ_Holster -> rs_hands' POSE_REACH,
		// same pipeline hardpointHere already drives for a physical reach --
		// see that mod's rs_hands.zs, "case GRIPSUBJ_Holster: return
		// POSE_REACH"). No new engine work needed; both claim fields already
		// exist and each is written by exactly one system.
		//
		// BOTH HANDS NOW, where this was off-hand only. Note the deliberate
		// asymmetry with the loop above: a hand REACHES for the other arm's
		// bank (proximity) but ARMS its own (gesture). Both facts land on the
		// same claim field because both mean the same thing to the arbiter --
		// "this hand is doing hardpoint work, do not give grip its normal
		// meaning" -- and rs_hands wants POSE_REACH either way.
		bool mainClaimedFinal = mainClaimed || gestureArmedMain[i];
		bool offClaimedFinal  = offClaimed  || gestureArmed[i];

		// Edge-logged rather than per-tic: this is the signal that the whole
		// chain works, and it should be visible without being a spam source.
		//
		// GATED BEHIND rs_hardpoint_verbose AS OF 2026-08-26. "Edge-logged,
		// not a spam source" was true only relative to a per-tic print: a
		// hand working across a rig of six overlapping anchors crosses these
		// edges constantly, and a shipped build should not narrate that. The
		// HAPTIC is deliberately OUTSIDE the gate -- it is the player-facing
		// feedback, not instrumentation, and turning the console lines off
		// must not also turn off the thing that tells you where the mount is.
		// mainClaimedFinal, not mainClaimed -- the edge test has to watch the
		// SAME value that gets written to the field two blocks down, or the
		// two disagree on every gesture-armed tic and the edge fires forever.
		// The off-hand half below already had this right; the main half only
		// looked right because nothing ever ORed anything into it.
		if (mainClaimedFinal != pawn.HardpointClaimMain)
		{
			if (verboseDiag())
				Console.Printf("RS_HARDPOINT: main hand %s hardpoint range", mainClaimedFinal ? "ENTERED" : "left");
			// A short, light tap on ENTER only -- a real holster does not buzz
			// your hand when you pull away from it, only when you find it.
			if (mainClaimedFinal) level.VRHaptic(0, 0.35, 25.0);
		}
		if (offClaimedFinal != pawn.HardpointClaimOff)
		{
			if (verboseDiag())
				Console.Printf("RS_HARDPOINT: off hand %s hardpoint range", offClaimedFinal ? "ENTERED" : "left");
			if (offClaimedFinal) level.VRHaptic(1, 0.35, 25.0);
		}

		// HardpointClaim, NOT HolsterClaim, and the change is not cosmetic.
		//
		// Both this mod and RS_Holsters wrote HolsterClaim* unconditionally
		// every tic. Whichever handler ran second won: a hand genuinely inside a
		// weapon holster had its claim erased by this mod reporting "not at a
		// hardpoint", and the reverse happened just as often. One boolean cannot
		// carry two independent facts, and nothing anywhere logged the loss.
		//
		// Each system now owns its own field. Write yours every frame; never
		// write anyone else's. The engine arbitrates between them in one place,
		// in priority order -- holster, then hardpoint, then a grab, then the
		// grip modifier, then stabilize.
		pawn.HardpointClaimMain = mainClaimedFinal;
		pawn.HardpointClaimOff  = offClaimedFinal;

		updateProps(i, pawn);
	}

	// Park a prop at every anchor and keep it showing whatever is stored there.
	// Position is rewritten each tic rather than parented, because the anchors
	// move with the player's head every frame and there is nothing to parent to.
	private void updateProps(int i, PlayerPawn pawn)
	{
		// TWO INDEPENDENT SWITCHES as of 2026-08-26, matching the same split in
		// RS_Holsters. The markers (wireframe rings showing WHERE a mount is)
		// and the props (the stored item's model) are separate actor arrays and
		// used to share one cvar.
		//
		// The menu row was labelled "Show hardpoint markers" and did the exact
		// opposite: the early return below only ever touched props[], while
		// every line that positions markers[] sits after it. Switching it off
		// hid your stored items and left the rings visible and FROZEN in world
		// space, no longer tracking your arm.
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
			// tracking the arm.
			if (!wantProps && !wantMarkers)
				return;
		}

		ensureContents();
		ensureProps();

		for (int h = 0; h < HOLSTER_COUNT; ++h)
		{
			int pi = (i * HOLSTER_COUNT) + h;

			// Same "invisible, not destroyed" treatment showProps() already
			// uses for the whole system -- dialing an arm's count down
			// hides a mount without evacuating whatever might be stored in
			// it, so raising the count back up later shows it exactly as it
			// was left. updateClaims already refuses to claim an inactive
			// index; this is what makes it actually disappear too.
			if (!holsterActive(h))
			{
				if (pi < markers.Size() && markers[pi] != null)
					markers[pi].SetVisible(false);
				if (pi < props.Size() && props[pi] != null)
					props[pi].SetVisible(false);
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
			// baseAngle/basePitch/baseRoll, not a single byaw: torso
			// holsters (h < HAND_HOLSTER_START) keep the exact old
			// behaviour -- body yaw only, edPitch/edRoll used as ABSOLUTE
			// values -- while hand-anchored holsters (8-13) take their base
			// from handBasisPose (the off hand's own live pose), with
			// edPitch/edRoll added as TRIMS on top. For the torso branch
			// basePitch/baseRoll are 0.0, which makes every formula below
			// reduce to exactly what it was before this split --
			// behavior-preserving for 0-7.
			double baseAngle, basePitch, baseRoll;
			if (isHandAnchored(h))
			{
				handBasisPose(pawn, h, baseAngle, basePitch, baseRoll);
			}
			else
			{
				baseAngle = bodyYaw[i];
				basePitch = 0.0;
				baseRoll  = 0.0;
			}

			string hsNameM; double hsFwdM, hsSideM, hsFracM, hsRadius, hsPitchM, hsYawM, hsRollM;
			GetHolster(h, hsNameM, hsFwdM, hsSideM, hsFracM, hsRadius, hsPitchM, hsYawM, hsRollM);

			// Computed once, reused for both the color-class choice below and
			// the SetHot() call -- same "is a hand in range right now" test.
			bool hot = (nearMain[i] == h || nearOff[i] == h);

			// --- the ring marker: always present, so an empty holster is
			// still something the player can see and aim a hand at ---
			//
			// Color is a CLASS choice (RS_HardPointMarker.holsterMarkerColorClass,
			// RS_HardPointProp.zs), not a settable field -- an existing marker
			// whose class no longer matches the cvar gets destroyed and
			// respawned so a color change takes effect immediately instead of
			// waiting for something else to force a respawn later. Cold and
			// hot are independent cvars now, so this same respawn path also
			// fires on every hand-enter/leave transition -- fade state is
			// carried across it (GetFadeAlpha/GetFadeVisible/SetFadeState) so
			// that respawn is invisible: without it, a fresh marker always
			// starts faded to nothing and would fade back in on every single
			// hot/cold toggle instead of just switching color instantly.
			class<Actor> wantColorClass = RS_HardPointMarker.holsterMarkerColorClass(hot);
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
				markers[pi] = RS_HardPointMarker(Actor.Spawn(wantColorClass, at, NO_REPLACE));
				if (markers[pi] != null && carryState)
					markers[pi].SetFadeState(carryAlpha, carryVisible);
			}

			if (markers[pi] != null)
			{
				markers[pi].SetVisible(wantMarkers);
				markers[pi].SetOrigin(at, true);
				markers[pi].SetHot(hot);

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
				//
				// WITH GESTURE-CAST ON, every marker gets a DIFFERENT feed:
				// the "not-yet-armed" visual. Firing a mount is not a reach
				// -- the arm that WEARS it rolls into the palm-out pose -- so
				// for that job hand DISTANCE has no meaning; ROLL distance
				// from the arming target does. Same shape (1.0 at the target,
				// fading out, wider than the hard armed cutoff so it visibly
				// notices the wrist approaching the pose, not just arriving).
				//
				// The roll it watches is the WEARING arm's own, per bank --
				// MainHandRoll for 0-2, OffhandRoll for 3-5 -- matching
				// updateGestureArm/updateGestureArmMain exactly. Reading one
				// hand's roll for all six would light up the other arm's
				// reticles for a pose that arms nothing.
				//
				// ...but only while gesture-cast is actually switched on.
				// With it off (the default) there is no arming pose to
				// approach, so a roll feed would just make the reticles pulse
				// at whatever angle the wrist happens to be at, for no reason
				// -- and it would hide the one feed that IS still meaningful
				// with gesture-cast off: the OTHER hand reaching over to
				// store/draw, an ordinary distance test.
				double proxValue;
				bool wornOnMainM = isMainArmAnchor(h);
				if (gestureEnabled())
				{
					// MainHandRoll for the main arm, NOT AttackRoll. The comment
					// above says this matches updateGestureArmMain -- and it
					// does now, because that function was corrected to
					// MainHandRoll in the same pass. AttackRoll is zeroed by
					// the playsim before WorldTick runs, so this fed the
					// reticle pulse a constant and the main-arm markers never
					// reacted to the arming pose at all.
					double armRoll = wornOnMainM ? pawn.MainHandRoll : pawn.OffhandRoll;
					double rollSenseMult = 3.0;
					double rollDelta = abs(normalizeDeg(armRoll - gestureRollTarget()));
					double rollSenseRange = gestureRollTolerance() * rollSenseMult;
					double rollNorm = (rollSenseRange > 0.0) ? (rollDelta / rollSenseRange) : 1.0;
					if (rollNorm < 0.0) rollNorm = 0.0;
					if (rollNorm > 1.0) rollNorm = 1.0;
					proxValue = 1.0 - rollNorm;
				}
				else
				{
					// ONE hand's distance, not the nearer of the two. This
					// used to take min(dMain, dOff) because either hand could
					// in principle be the one approaching; after the
					// re-layout exactly one hand can ever claim a given mount
					// (see updateClaims' self-claim exclusion), and the
					// WEARING hand's distance to its own mount is a constant.
					// Feeding that constant in through a min() would peg
					// every reticle's proximity at a fixed non-zero value
					// forever and the tighten effect would stop meaning
					// anything at all.
					double senseMult = 4.0;
					double dReach;
					if (wornOnMainM)
						dReach = (pawn.OffhandPos - at).Length();
					else
						dReach = (pawn.AttackPos - at).Length();
					double senseRange = hsRadius * senseMult;
					double norm = (senseRange > 0.0) ? (dReach / senseRange) : 1.0;
					if (norm < 0.0) norm = 0.0;
					if (norm > 1.0) norm = 1.0;
					proxValue = 1.0 - norm;
				}
				markers[pi].SetProximity(proxValue);
			}

			// --- the stored weapon's model, when there is one ---
			if (props[pi] == null)
			{
				props[pi] = RS_HardPointProp(Actor.Spawn("RS_HardPointProp", at, NO_REPLACE));
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
			//
			// GESTURE-CAST IS THE ONE LEGITIMATE "in a hand AND still on its
			// mount" state, and this pass used to have no idea. fireGesture
			// seats the mount's own weapon into the off hand deliberately and
			// leaves it there for the whole armed stretch, and it does NOT
			// charge lastSwapTic* -- so the very next tic this test read "the
			// stored weapon is in a hand", concluded it had drifted back, and
			// emptied the mount that had just fired, clearing its stow flags
			// on the way out. Firing a hardpoint therefore consumed it.
			// gestureSeatedOff[i] is the exact instance fireGesture put there
			// (see that field), so this exempts that one weapon and nothing
			// else -- an ammo-pickup re-arm of a DIFFERENT mount is still
			// reconciled normally, in the same tic.
			//
			// BOTH ARMS' seated pointers are checked. Exempting only the off
			// arm's would leave the main bank with exactly the bug this test
			// exists to fix -- firing a main-arm mount would empty it on the
			// next tic and strip its stow flags -- and it would look like a
			// gesture-cast bug rather than a reconciliation one.
			ensureGestureSeatedOff();
			ensureGestureSeatedMain();
			bool gestureHeld = (stored != null
			    && (stored == gestureSeatedOff[i] || stored == gestureSeatedMain[i]));

			if (stored != null && !gestureHeld && pawn.player.PendingWeapon == WP_NOCHANGE
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
			// smaller default scale (RS_HardPointProp.holsterPropScaleArm) --
			// a wrist-mounted flashlight should read as compact gear, not a
			// full holstered sidearm.
			double propScale = isHandAnchored(h) ? RS_HardPointProp.holsterPropScaleArm() : RS_HardPointProp.holsterPropScale();

			// Passing null is the existing "this mount is empty" path --
			// ShowWeapon sets pendingClear and fades the model out. Reusing it
			// for "stored items are switched off" means the hide takes the same
			// well-tested route rather than a second way to make a prop
			// invisible, and it comes back correctly when switched on again.
			Weapon toShow = wantProps ? stored : null;
			p.ShowWeapon(toShow, propScale, hsRadius);

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
			double extra = RS_HardPointProp.holsterPropYaw() + edYaw[h];
			if (p.mirrored)
				extra += 180.0;
			double finalAngle = baseAngle + extra - p.bakedAngleOffset;
			double finalPitch = basePitch + edPitch[h] + RS_HardPointProp.holsterPropPitch() - p.bakedPitchOffset;

			p.angle = finalAngle;
			p.pitch = finalPitch;
			p.roll  = baseRoll + edRoll[h] + RS_HardPointProp.holsterPropRoll() - p.bakedRollOffset;

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
				level.GetModelWorldOffset(p.shownClass, p.sprite, p.frame, stretch, finalAngle, finalPitch, p.roll,
				                          p.scale.X, p.scale.Y);
			if (!foundWorld) { worldOffX = 0.0; worldOffY = 0.0; worldOffZ = 0.0; }

			// Manual trim, local rotated frame, on top of the automatic
			// correction -- a residual nudge now, not the whole mechanism.
			double nUp   = RS_HardPointProp.holsterPropUp();
			double nFwd  = RS_HardPointProp.holsterPropFwd();
			double nSide = RS_HardPointProp.holsterPropSide();

			Vector3 placed = (
				at.X - worldOffX + (nFwd * localFwdX) + (nUp * localUpX) + (nSide * rightX),
				at.Y - worldOffY + (nFwd * localFwdY) + (nUp * localUpY) + (nSide * rightY),
				at.Z - worldOffZ + (nFwd * localFwdZ) + (nUp * localUpZ)
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
			Console.Printf("RS_HARDPOINT: dropped %s at fwd %.2f  side %.2f  frac %.3f",
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
			Console.Printf("RS_HARDPOINT: no sphere in reach for that hand");
			return;
		}

		string hsName2; double f2, s2, fr2, r2, p2, y2, rl2;
		GetHolster(want, hsName2, f2, s2, fr2, r2, p2, y2, rl2);
		Console.Printf("RS_HARDPOINT: grabbed %s -- move your hand, press again to drop", hsName2);
		level.VRHaptic(mainHand ? 0 : 1, 0.35, 25.0);
		if (mainHand) { grabbedMain[i] = want; } else { grabbedOff[i] = want; }
	}

	// Whatever this player's melee weapon actually is. Walks inventory rather
	// than naming a class, so it survives new player classes and new fist
	// variants without edits here.
	// Must return a fist that ALREADY belongs to the hand being filled.
	// MoveWeaponToHand's first guard is:
	//     if (weap.bNoHandSwitch && weap.bOffhandWeapon != (hand == 1)) return;
	// and every fist here carries +WEAPON.NOHANDSWITCH -- so handing it the
	// main-hand fist for the off hand makes it bail SILENTLY. That was the
	// "offhand never lets go of the gun" bug: the store happened, the hand
	// was never emptied, and nothing reported a failure.
	// One definition of "is this a fist", used by both the store guard and the
	// fist lookup. Name-based on purpose -- see the note at the store guard.
	static bool isFistClass(string cn)
	{
		return cn.IndexOf("Fist") >= 0;
	}

	private Weapon findFist(PlayerPawn pawn, bool offhand) const
	{
		for (Inventory item = pawn.Inv; item != null; item = item.Inv)
		{
			let w = Weapon(item);
			if (w == null)
				continue;
			// GetClassName() is a Name; IndexOf is a String method, so it has
			// to land in a string first.
			string cn = w.GetClassName();
			if (cn.IndexOf("Fist") < 0)
				continue;

			if (w.bOffhandWeapon == offhand)
				return w;      // the one that belongs in this hand
		}

		// No fallback to "any fist". A wrong-hand fist can NEVER be seated --
		// MoveWeaponToHand's first guard rejects it silently because every fist
		// carries +WEAPON.NOHANDSWITCH -- so handing one back only produced a
		// store that emptied nothing while the table recorded it as done. That
		// is the "offhand never lets go of the gun" bug, reintroduced by the
		// very fallback that was meant to be defensive. Null is the honest
		// answer, and the caller rolls the store back.
		return null;
	}

	private void ensureProps()
	{
		int want = MAXPLAYERS * HOLSTER_COUNT;
		while (props.Size() < want)
			props.Push(null);
		while (markers.Size() < want)
			markers.Push(null);
	}

	// The STORED ITEM models parked in occupied hardpoints.
	private bool showProps() const
	{
		let cv = CVar.GetCVar("rs_hardpoint_props", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : true;
	}

	// The WIREFRAME MARKERS showing where each mount is. Separate actors from
	// the props and, since 2026-08-26, a separate switch -- see updateProps for
	// why they used to share one and what that broke.
	private bool showMarkers() const
	{
		let cv = CVar.GetCVar("rs_hardpoint_markers", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : true;
	}

	// Always true -- every index in this mod is arm-anchored. Kept as a
	// predicate rather than deleted; see the HAND_HOLSTER_START comment at
	// the top of this class for why.
	private bool isHandAnchored(int idx) const
	{
		return idx >= HAND_HOLSTER_START;
	}

	// How many of one arm's three wrist mounts are live: 0-3.
	//
	// REPLACES armMode(), which was a single four-valued MODE across one
	// six-mount bank (0 off / 1 forearm only / 2 wrist only / 3 both). That
	// shape existed because the wrist trio sat at indices 3-5 and "first N
	// active" could never express "the top half only". With two banks of
	// three, each bank IS a low-to-high run, so a plain count works and the
	// mode disappears -- which is what let the menu become the four controls
	// the owner asked for (on/off and 1/2/3, per hand) instead of one
	// combined dropdown.
	//
	// TWO CVARS PER ARM, not one 0-3 count, because that is the menu shape
	// the owner specified: an on/off you can flick without losing your
	// chosen count, and a count you can change without switching the arm on.
	// Folding them into one value would make "off" and "one mount" adjacent
	// positions on the same slider, which is exactly the fiddly thing the
	// split avoids.
	//
	// Clamped rather than trusted raw -- these cvars can be hand-edited in
	// an ini to any int.
	//
	// The cvar NAME is chosen with a ternary and passed as a string, which
	// CVar.GetCVar takes as a Name (doombase.zs:155). Precedent for exactly
	// this -- a string local holding a chosen cvar name, handed straight to
	// GetCVar -- is RS_HardPointProp.zs:121-122.
	private int wristCount(bool mainArm) const
	{
		string enableName = mainArm ? "rs_hardpoint_wrist_main"       : "rs_hardpoint_wrist_off";
		let en = CVar.GetCVar(enableName, players[consoleplayer]);
		// Fallback TRUE, matching the declared default: an unrecognised cvar
		// name (an old ini, a partial install) must not silently switch the
		// whole mod off, which is the entire visible surface of this pk3.
		if (en != null && !en.GetBool())
			return 0;

		string countName = mainArm ? "rs_hardpoint_wrist_main_count" : "rs_hardpoint_wrist_off_count";
		let cv = CVar.GetCVar(countName, players[consoleplayer]);
		int n = (cv != null) ? cv.GetInt() : WRIST_PER_ARM;
		if (n <= 0) return 0;
		if (n >= WRIST_PER_ARM) return WRIST_PER_ARM;
		return n;
	}

	// Does this arm have any live mounts at all? The gesture-cast tier gate
	// and the wrist debug dump both want this and neither wants the number.
	private bool wristTierLive(bool mainArm) const
	{
		return wristCount(mainArm) > 0;
	}

	private bool holsterActive(int h) const
	{
		bool mainArm = isMainArmAnchor(h);
		// Slot within its own bank: 0,1,2 either way. The count then means
		// the obvious thing -- 1 lights the first mount, 2 the first two.
		int slot = mainArm ? h : (h - OFF_WRIST_START);
		return slot < wristCount(mainArm);
	}

	private bool instantSwitchEnabled() const
	{
		let cv = CVar.GetCVar("rs_hardpoint_instant_switch", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : true;
	}

	// GESTURE-CAST master switch, DEFAULTING OFF, and the default is the
	// whole point of this existing.
	//
	// Arming is a pure roll test against gestureRollTarget(), which defaults
	// to 0.0 with a 30-degree tolerance -- and a hand hanging at rest reads
	// an OffhandRoll near 0. So before this cvar existed, merely loading the
	// pk3 left every player permanently gesture-armed: HardpointClaimOff
	// pinned true forever (updateClaims ORs gestureArmed in), rs_hands stuck
	// in POSE_REACH, and the three gesture netevents live from the first
	// tic. A feature whose own KEYCONF entry calls its binds PLACEHOLDER
	// must not be on by default.
	//
	// Read with a false fallback, not true: an unrecognised cvar name (an
	// old ini, a partial install) has to resolve to "off", or the fallback
	// reintroduces exactly the on-by-default state this is here to remove.
	private bool gestureEnabled() const
	{
		let cv = CVar.GetCVar("rs_hardpoint_gesture_enable", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : false;
	}

	// Developer instrumentation gate. Same idea as rs_hardpoint_wristdump
	// (and named _verbose rather than _debug for the same reason: KEYCONF
	// already binds an ALIAS called rs_hardpoint_debug, and a cvar sharing
	// that name would collide in the console namespace).
	//
	// Covers the two things that print on their own during ordinary play --
	// the hand-entered/left range edge lines, and the automatic multi-line
	// prop-orientation dump fired one tic after every store. Both are real
	// diagnostics worth keeping; neither belongs in a shipped build's
	// console by default. The MANUAL dump (netevent rs-hardpoint-debug) is
	// deliberately NOT gated -- asking for it is the whole gesture.
	private bool verboseDiag() const
	{
		let cv = CVar.GetCVar("rs_hardpoint_verbose", players[consoleplayer]);
		return (cv != null) ? cv.GetBool() : false;
	}

	// GESTURE-CAST arming target/tolerance, degrees. Live-tunable rather than
	// baked -- same reasoning as every other angle in this file: the right
	// number is found by rolling the wrist in headset and reading raw
	// OffhandRoll off the debug dump below, not by reasoning about it on
	// paper. This codebase's rotation math has been hand-derived wrong twice
	// before (see the wrist-pitch lead); this is the same shape of problem.
	private double gestureRollTarget() const
	{
		let cv = CVar.GetCVar("rs_hardpoint_gesture_roll_target", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 0.0;
	}

	private double gestureRollTolerance() const
	{
		let cv = CVar.GetCVar("rs_hardpoint_gesture_roll_tolerance", players[consoleplayer]);
		return (cv != null) ? cv.GetFloat() : 30.0;
	}

	// Palm-out/open-palm arming check for GESTURE-CAST, OFF ARM. Its main-arm
	// twin is updateGestureArmMain, immediately below; read this one first,
	// it carries the reasoning for both.
	//
	// AN ARM ARMS ITS OWN MOUNTS. This used to be "off hand only", back when
	// there was only one bank and it rode the off arm. The re-layout did not
	// change the rule, only how many arms it applies to: the arm wearing the
	// three mounts is the arm that rolls palm-out to fire them. (That is the
	// mirror image of store/draw, where a hand can only reach the OTHER arm's
	// bank -- the two verbs, HOLSTERS DRAW / WRISTS FIRE, deliberately do not
	// share a hand assignment.)
	//
	// Roll alone, no position/extension test: there is no elbow tracking to
	// check "is the arm actually outstretched" against (the same gap the
	// deferred forearm anchors worked around), and no precondition on
	// anything else the player is doing -- the owner was explicit that an
	// earlier "shoot first, then arm" framing was just an example, not a
	// requirement. Haptic fires on the rising edge only, mirroring
	// updateClaims' own "short tap on ENTER only" pattern.
	//
	// THREE HARD GATES run before the roll test, added 2026-08-26. The roll
	// test alone was reached unconditionally, and with the target defaulting
	// to 0.0 (+/- 30) a hand hanging at rest passes it -- so the shipped
	// state was "permanently armed, from the first tic, for everyone":
	//
	//  1. gestureEnabled() -- the master switch, defaulting OFF. See there.
	//  2. THIS ARM'S BANK has to actually be live. Gesture-cast fires the
	//     three mounts on this arm and nothing else; with the bank switched
	//     off (or its count at 0) those mounts are invisible and unclaimable
	//     (holsterActive), so arming for them would pin HardpointClaimOff
	//     true for a bank that is not even on screen. Per arm now, where it
	//     used to be one shared armMode() test -- switching the main bank
	//     off must not disarm the off arm, and vice versa.
	//  3. NOT IN EDIT MODE. Placement and live fire must not coexist: edit
	//     mode reassigns the grab keys to sphere-dragging, and an armed
	//     off hand simultaneously holding HardpointClaimOff true means the
	//     hand you are trying to place spheres with is also mid-gesture.
	//
	// Failing any gate forces nowArmed false rather than returning early --
	// that keeps the falling-edge restore below on the ONE path it needs to
	// be on, so switching the cvar off (or entering edit mode) while armed
	// puts the player's real weapon back in their hand instead of leaving a
	// hardpoint weapon seated forever.
	private void updateGestureArm(int i, PlayerPawn pawn)
	{
		bool wasArmed = gestureArmed[i];

		bool allowed = gestureEnabled() && wristTierLive(false) && !editMode[i];

		bool nowArmed = false;
		if (allowed)
		{
			double delta = abs(normalizeDeg(pawn.OffhandRoll - gestureRollTarget()));
			// Hysteresis, exactly as CLAIM_HYSTERESIS does for proximity:
			// enter at the tolerance, leave only past the widened one.
			// Without it a wrist parked on the boundary re-crosses it many
			// times a second, and every falling edge is a real weapon swap
			// back into the off hand plus a haptic tap -- the gun visibly
			// flickering in and out of the player's hand, not merely a noisy
			// console line.
			double tol = gestureRollTolerance();
			double useTol = wasArmed ? (tol * GESTURE_ROLL_HYSTERESIS) : tol;
			nowArmed = (delta <= useTol);
		}

		gestureArmed[i] = nowArmed;
		if (nowArmed && !wasArmed)
			level.VRHaptic(1, 0.35, 25.0);

		// Falling edge: the hand rolled back out of the arming pose.
		// Whatever gesture-fire last seated in the off hand (if anything --
		// most armed stretches fire nothing at all) swaps back out HERE, on
		// the tic arming actually ends, not on a same-tic pulse inside
		// fireGesture -- see gesturePreviousOff's own field comment for why
		// that matters (a same-tic swap-back risks tearing the Fire state's
		// psprite down before its action functions ever actually run).
		if (!nowArmed && wasArmed)
		{
			ensureGesturePreviousOff();
			ensureGestureSeatedOff();
			Weapon restore = gesturePreviousOff[i];
			if (restore != null)
			{
				moveWeaponInstant(pawn, restore, 1);
				gesturePreviousOff[i] = null;

				// The hardpoint weapon is genuinely back in its mount now --
				// the hand let go of it on this exact branch -- so put the
				// stow flags back on. fireGesture had to strip them for it
				// to fire at all (CheckAmmo refuses to let a bHolsterHidden
				// weapon fire, see doSwap's own note), and leaving them
				// stripped would let weapnext/weapprev cycle straight into a
				// weapon that is sitting on a mount, which is the exact
				// desync bHolsterHidden exists to prevent.
				//
				// INSIDE the restore != null branch on purpose. When there
				// was no real weapon to restore (an off hand that started
				// out empty), nothing moves and the hardpoint weapon simply
				// STAYS in the hand -- at which point flagging it hidden
				// would make the weapon the player is now visibly holding
				// unable to fire. Leaving it unflagged instead means
				// updateProps' reconciliation sees it in-hand next tic and
				// clears the mount, i.e. it degrades into an ordinary draw,
				// which is the honest reading of what just happened.
				Weapon seated = gestureSeatedOff[i];
				if (seated != null)
				{
					seated.bNoAutoSwitchTo = true;
					seated.bHolsterHidden = true;
				}
			}
			gestureSeatedOff[i] = null;
		}
	}

	// The MAIN arm's twin of updateGestureArm above. Every comment there
	// applies here with the main hand substituted: MainHandRoll for
	// OffhandRoll, haptic channel 0 for 1, hand 0 for hand 1 in the restore,
	// ReadyWeapon for OffhandWeapon (fireGestureMain captures it), and
	// wristTierLive(true) for the bank gate.
	//
	// A CLONE, NOT A PARAMETERISED VERSION, for the reason spelled out on the
	// constants at the top of this class: the one-bank pattern is proven, and
	// threading a hand argument through the arm/fire/restore trio would put
	// an index nobody can see wrong in the middle of a weapon swap. Two
	// functions that each read plainly beat one that has to be traced.
	private void updateGestureArmMain(int i, PlayerPawn pawn)
	{
		bool wasArmed = gestureArmedMain[i];

		bool allowed = gestureEnabled() && wristTierLive(true) && !editMode[i];

		bool nowArmed = false;
		if (allowed)
		{
			// MainHandRoll, NOT AttackRoll -- and this one is not a style
			// preference, it is the difference between working and being
			// permanently armed from the first tic.
			//
			// AttackRoll is dead in script. The playsim zeroes it outright
			// every tic (p_user.cpp:134, inside UpdateCanonicalMainHandPose,
			// which P_PlayerThink calls at :1781), and p_tick.cpp runs
			// P_PlayerThink for every player BEFORE WorldTick() -- so by the
			// time this handler looks, the field is always 0. The VR backends
			// only rewrite it at render time (vk_openxrdevice.cpp:4396), long
			// after we have read it. Reading it here made `delta` the
			// constant abs(normalizeDeg(0.0 - target)): with the shipped
			// default target of 0.0 that is 0, inside any tolerance, so the
			// main arm armed on EVERY tic that the gate allowed. That ORs
			// into mainClaimedFinal in updateClaims and pins
			// HardpointClaimMain true forever -- rs_hands stuck in
			// POSE_REACH, the main grip redirected permanently. It is the
			// exact failure the gestureEnabled() comment above records
			// fixing for the OFF hand, and no cvar value escapes it: a
			// nonzero target makes arming impossible, a zero target makes
			// disarming impossible.
			//
			// MainHandRoll is the same wrist angle kept somewhere the playsim
			// will not clear it (actor.zs:384 -- "Use this for anything
			// welded to the weapon"). The family is unanimous on the pairing:
			// rr_point.zs:69, rs_grab.zs:217 and :304, rs_distance.zs:25 all
			// read MainHandRoll for hand 0 and OffhandRoll for hand 1.
			double delta = abs(normalizeDeg(pawn.MainHandRoll - gestureRollTarget()));
			// Same hysteresis, same reason -- see updateGestureArm.
			double tol = gestureRollTolerance();
			double useTol = wasArmed ? (tol * GESTURE_ROLL_HYSTERESIS) : tol;
			nowArmed = (delta <= useTol);
		}

		gestureArmedMain[i] = nowArmed;
		if (nowArmed && !wasArmed)
			level.VRHaptic(0, 0.35, 25.0);

		if (!nowArmed && wasArmed)
		{
			ensureGesturePreviousMain();
			ensureGestureSeatedMain();
			Weapon restore = gesturePreviousMain[i];
			if (restore != null)
			{
				moveWeaponInstant(pawn, restore, 0);
				gesturePreviousMain[i] = null;

				// Stow flags back on, and INSIDE this branch on purpose --
				// see updateGestureArm for the full argument. Short version:
				// with no real weapon to restore, the hardpoint weapon stays
				// in the hand, and flagging a weapon the player is visibly
				// holding would make it unable to fire.
				Weapon seated = gestureSeatedMain[i];
				if (seated != null)
				{
					seated.bNoAutoSwitchTo = true;
					seated.bHolsterHidden = true;
				}
			}
			gestureSeatedMain[i] = null;
		}
	}

	private void ensureGestureSeatedOff()
	{
		while (gestureSeatedOff.Size() < MAXPLAYERS)
			gestureSeatedOff.Push(null);
	}

	private void ensureGesturePreviousOff()
	{
		while (gesturePreviousOff.Size() < MAXPLAYERS)
			gesturePreviousOff.Push(null);
	}

	private void ensureGestureSeatedMain()
	{
		while (gestureSeatedMain.Size() < MAXPLAYERS)
			gestureSeatedMain.Push(null);
	}

	private void ensureGesturePreviousMain()
	{
		while (gesturePreviousMain.Size() < MAXPLAYERS)
			gesturePreviousMain.Push(null);
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

		if (evt.name == "rs-hardpoint-recalibrate")
		{
			ForceRecalibrate(evt.player);
			return;
		}

		if (evt.name == "rs-hardpoint-debug")
		{
			dumpDebug(evt.player, pawn);
			return;
		}

		if (evt.name == "rs-hardpoint-edit")
		{
			ensureEdit();
			editMode[evt.player] = !editMode[evt.player];
			grabbedMain[evt.player] = -1;
			grabbedOff[evt.player] = -1;
			if (editMode[evt.player])
			{
				Console.Printf("\c[Gold]RS_HARDPOINT: EDIT MODE ON");
				Console.Printf("  put a hand in a sphere and press its holster key to GRAB it");
				Console.Printf("  move your hand, press again to DROP it there");
				Console.Printf("  then: netevent rs-hardpoint-table   (prints the numbers)");
			}
			else
			{
				Console.Printf("\c[Gold]RS_HARDPOINT: edit mode off");
			}
			return;
		}

		if (evt.name == "rs-hardpoint-table")
		{
			ensureEdit();
			dumpTable();
			return;
		}

		if (evt.name == "rs-hardpoint-reset")
		{
			edInit = false;
			ensureEdit();
			Console.Printf("RS_HARDPOINT: offsets reset to the built-in defaults");
			return;
		}

		// ONE saved layout, not the seated/standing pair RS_Holsters has.
		// That pair exists there because a hip or pectoral anchor is placed
		// relative to a BODY, and a table tuned standing does not fit a
		// seated one -- shorter reach, different eye-to-hip fraction. These
		// mounts are bolted to a tracked controller: the arm is in the same
		// place relative to itself no matter what the rest of you is doing,
		// so posture is not a variable here and two slots would be two names
		// for the same numbers.
		if (evt.name == "rs-hardpoint-save-layout") { saveProfile("hardpoint_layout"); return; }
		if (evt.name == "rs-hardpoint-load-layout") { loadProfile("hardpoint_layout"); return; }

		// One key per hand -- which hand pressed decides which weapon moves,
		// or in edit mode which sphere gets dragged.
		//
		// TWO event names per hand, and the shared one is why this mod can be
		// loaded alongside RS_Holsters. The engine's grip arbiter redirects a
		// holster-context grip to the synthetic keys F13/F14; a key can only
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
		// RS_Holsters' -- a wrist mount rides the forearm, a hip holster sits
		// on the body, and one reach can be inside both. Both handlers get the
		// netevent, both find a claim, and BOTH swap on a single press. What
		// keeps that from happening today is where the anchors happen to sit,
		// not anything in this code. The real fix is the grip arbiter being
		// built separately; DO NOT "tidy" this dispatch in the meantime, it
		// will collide with that work.
		if (evt.name == "rs-hardpoint-grab-main" || evt.name == "rs-vrhp-grab-main")
		{
			if (editMode[evt.player]) { toggleGrab(evt.player, true); }
			else                      { doSwap(evt.player, pawn, nearMain[evt.player], false); }
		}
		else if (evt.name == "rs-hardpoint-grab-off" || evt.name == "rs-vrhp-grab-off")
		{
			if (editMode[evt.player]) { toggleGrab(evt.player, false); }
			else                      { doSwap(evt.player, pawn, nearOff[evt.player], true); }
		}

		// GESTURE-CAST fire, one netevent per button per arm, each hardcoded
		// to the ONE wrist index the owner assigned it (2026-08-25):
		// grip -> Below, pad/X -> Knuckle, trigger -> Joint.
		//
		// SIX NETEVENTS, not three with a hand argument, and the OFF trio
		// kept its exact original names and indices (3/4/5) so every existing
		// KEYCONF alias and every bind a player already made still means what
		// it meant. Still not a hand-parameterized dispatch like
		// grab-main/grab-off above: those two share a netevent with
		// RS_Holsters and must, these do not exist anywhere else, and a
		// mis-parameterised gesture-fire seats a weapon in the wrong hand
		// rather than merely doing nothing.
		//
		// PLACEHOLDER BINDS: nothing in KEYCONF binds these to the real
		// grip/trigger/pad keys yet, because doing that safely needs the
		// engine-side context gating (in progress, owner's own lane) that
		// stops a gesture-fire from ALSO firing whatever that hand's own
		// weapon does on the same physical button. Bind these to throwaway
		// test keys for now; once the gated keys exist, rebind onto those.
		else if (evt.name == "rs-hardpoint-gesture-grip")         { fireGesture(evt.player, pawn, 3); }
		else if (evt.name == "rs-hardpoint-gesture-padx")         { fireGesture(evt.player, pawn, 4); }
		else if (evt.name == "rs-hardpoint-gesture-trigger")      { fireGesture(evt.player, pawn, 5); }
		else if (evt.name == "rs-hardpoint-gesture-main-grip")    { fireGestureMain(evt.player, pawn, 0); }
		else if (evt.name == "rs-hardpoint-gesture-main-padx")    { fireGestureMain(evt.player, pawn, 1); }
		else if (evt.name == "rs-hardpoint-gesture-main-trigger") { fireGestureMain(evt.player, pawn, 2); }
	}

	// GESTURE-CAST fire, one hardpoint, OFF arm (mounts 3-5). fireGestureMain
	// is its twin for the main arm, immediately after it; this is the copy
	// that carries the reasoning.
	//
	// Confirmed design (owner, 2026-08-25):
	// palm-out hides that hand's PSprite weapon model and holds rs_hands in
	// REACH pose (the "sorcerer" read), and MULTIPLE hardpoints can fire
	// within the same press -- HP1/2/3 are independent, not mutually
	// exclusive.
	//
	// THIS IS THE "WRISTS FIRE" HALF OF THE 2026-08-26 DESIGN RULE. A wrist
	// mount fires its weapon IN PLACE, palm-out, and never draws it -- the
	// weapon is seated invisibly and swapped straight back out. Drawing is
	// the TORSO HOLSTERS' verb (RS_Holsters). Do not add a draw path here;
	// the two systems stop competing precisely because they are different
	// verbs.
	//
	// Hardpoints are weapon-agnostic, same as every torso holster --
	// whatever is seated here is an ORDINARY Weapon from whatever pack is
	// loaded, not a bespoke "ability" class. So "fire" means: run THAT
	// WEAPON'S OWN real Fire state, the same one that runs when it is
	// normally held and fired.
	//
	// SEATED FOR THE WHOLE ARMED STRETCH, hidden the whole time -- NOT a
	// same-tic swap-fire-swap-back pulse. That was tried first and
	// rejected: swapping the original weapon back before even one tic has
	// passed risks tearing the Fire state's psprite down (TickPSprites,
	// player.zs ~601, destroys any PSP_OFFHANDWEAPON psprite whose Caller
	// is not the CURRENT OffhandWeapon, every tic) before its action
	// functions ever actually ran. So instead:
	//   1. First fire since arming: remember the real off-hand weapon in
	//      gesturePreviousOff[i] (see that field's own comment for why only
	//      the FIRST fire captures it).
	//   2. moveWeaponInstant swaps the requested hardpoint's weapon into
	//      the off hand -- already-proven machinery (the exact call doSwap
	//      uses for store/draw), synchronous via CF_INSTANTWEAPSWITCH.
	//   3. player.SetPsprite jumps the off-hand psprite straight to that
	//      weapon's own "Fire" state -- same call the engine's own
	//      TickPSprites uses to seat a weapon into its Ready state
	//      (player.zs ~1985), just targeting Fire instead.
	//   4. That new psprite's NoDraw is set true (player.zs PSprite class --
	//      "Hide this layer without touching the weapon behind it. The
	//      weapon keeps its states, damage and slot; only the drawing
	//      stops.") -- exactly the tool for "no hardpoint weapon model
	//      drawn": the Fire state's action functions still run in full,
	//      nothing about the attack itself is suppressed, only the render.
	// It stays seated, hidden, running its own states normally, right up
	// until updateGestureArm's falling edge swaps the real weapon back --
	// see that function. gestureArmed keeping HardpointClaimOff forced true
	// the whole time (updateClaims) is what holds rs_hands in POSE_REACH.
	//
	// MULTI-FIRE: firing a second or third hardpoint before disarming just
	// re-seats a DIFFERENT weapon into the same slot, interrupting whatever
	// the previous one was doing mid-state -- ordinary weapon-switch
	// behaviour, not a special case. gesturePreviousOff only remembers the
	// ONE real weapon from before any of this started, so whichever
	// hardpoint fired last, disarming always restores the right thing.
	//
	// KNOWN GAP: jumping straight to Fire bypasses whatever ammo-check the
	// weapon normally does on the button-driven path (player.zs ~515,
	// gated on WeaponState flags this call never sets). Whether that
	// matters depends on where a given weapon puts its own ammo check --
	// something to confirm in headset per weapon, not something to guess
	// at blind here.
	//
	// Silent no-op when not armed, when the hardpoint is hidden
	// (holsterActive), or when nothing is seated there -- none of those
	// are errors, and two of three buttons doing nothing is the NORMAL
	// case whenever fewer than three hardpoints are occupied.
	private void fireGesture(int i, PlayerPawn pawn, int holsterIdx)
	{
		// The master switch and the edit-mode lockout are re-checked HERE,
		// not just in updateGestureArm, and that is not belt-and-braces
		// paranoia: a netevent is delivered the moment it arrives, which can
		// be between two WorldTicks. Toggling the cvar off, or entering edit
		// mode, and pressing a gesture key in the same gap would otherwise
		// reach this on a gestureArmed[] value that had not been recomputed
		// yet -- placement and live fire coexisting, which is the exact
		// combination edit mode has to exclude.
		if (!gestureEnabled() || editMode[i])
			return;

		if (!gestureArmed[i])
			return;

		// Same rule updateClaims/updateProps already enforce for every other
		// consumer of a holster index: a hand should never be able to
		// trigger anything on a holster it cannot see. Dialing the off
		// bank's count down (rs_hardpoint_wrist_off_count), or switching the
		// bank off entirely, hides a hardpoint
		// WITHOUT evacuating whatever is stored in it (updateProps' own
		// comment), so contents[] can stay non-null on an index that is
		// currently invisible -- without this check, gesture-fire could
		// trigger a hidden hardpoint the player cannot even see the marker
		// for.
		if (!holsterActive(holsterIdx))
			return;

		ensureContents();
		int slot = (i * HOLSTER_COUNT) + holsterIdx;
		Weapon w = contents[slot];
		if (w == null)
			return;

		// THE WRONG-HAND GUARD, the same one doSwap has carried for a long
		// time and this path was written without. It is not cosmetic:
		//
		//     if (weap.bNoHandSwitch && weap.bOffhandWeapon != (hand == 1)) return;
		//
		// is MoveWeaponToHand's own first line, and it returns VOID and
		// SILENTLY. Every weapon in this arsenal carries +WEAPON.NOHANDSWITCH,
		// so seating a MAIN-hand weapon into the off hand does nothing at all
		// -- and the SetPsprite two lines below would then jump the off hand's
		// psprite to a Fire state belonging to a weapon that is not the off
		// hand's weapon. That is the abort doSwap documents ~700 lines from
		// here: the psprite runs the foreign weapon's state functions with the
		// WRONG caller, and the VM kills the game the moment one of them
		// type-checks its owner ("Invalid class VR_Fist in function call to
		// VR_SMG.StateFunction"). Nothing stored a main-hand weapon on a
		// wrist mount deliberately -- but doSwap lets either hand fill any
		// mount, so it is reachable.
		//
		// This is the OFF-hand path, so the comparison is against a constant
		// true rather than doSwap's `offhand` parameter. fireGestureMain
		// carries the mirror of this test, inverted -- if you change one,
		// change both, and check the polarity against MoveWeaponToHand's own
		// line rather than against the other copy.
		//
		// -------------------------------------------------------------
		// OPEN DESIGN COLLISION, surfaced (not caused) by the 2026-08-26
		// re-layout, and NOT fixed here because fixing it is an owner call:
		//
		//   * A mount is FILLED by the OPPOSITE hand (updateClaims' self-claim
		//     exclusion -- a hand cannot reach its own arm). doSwap stores
		//     whatever THAT hand was holding, so an off-arm mount ends up
		//     holding a MAIN-hand weapon.
		//   * A mount is FIRED by the hand that WEARS it, because the arming
		//     pose is that wrist rolling palm-out.
		//   * Every weapon in this arsenal carries +WEAPON.NOHANDSWITCH, so
		//     an instance is permanently bound to one hand and this guard
		//     refuses it.
		//
		// Net: with a NOHANDSWITCH arsenal, the weapon a reach naturally puts
		// on a mount is the one this guard will not fire. That was already
		// true before the re-layout (nearOff was pinned to -1, so the main
		// hand filled all six off-arm mounts) -- it has simply never been hit,
		// because gesture-cast defaults OFF and its binds are placeholders.
		//
		// DO NOT "fix" it by deleting this guard. It is what stops the VM
		// abort described above. The real fix is one of two owner decisions:
		// let a hand arm the bank it can REACH rather than the one it wears,
		// or give mounts their own hand-agnostic copy of the weapon. Both are
		// design changes, not repairs.
		// -------------------------------------------------------------
		if (w.bNoHandSwitch && !w.bOffhandWeapon)
		{
			Console.Printf("\cgRS_HARDPOINT: %s is a MAIN-hand weapon on an OFF-arm mount -- cannot gesture-fire (see fireGesture's hand-binding note)", w.GetClassName());
			return;
		}

		State fireState = w.FindState('Fire');
		if (fireState == null)
		{
			// A seated item with no Fire state at all -- nothing to run.
			// Loud rather than silent: an empty slot is normal, a real
			// weapon missing a Fire state is a content problem worth
			// seeing in the console.
			Console.Printf("\cgRS_HARDPOINT: %s has no Fire state, cannot gesture-fire", w.GetClassName());
			return;
		}

		ensureGesturePreviousOff();
		ensureGestureSeatedOff();

		// Capture the real off-hand weapon ONLY on the first fire of this
		// armed stretch -- see gesturePreviousOff's field comment. A second
		// or third hardpoint fired before disarming must not overwrite this
		// with whatever the FIRST hardpoint's weapon left seated.
		if (gesturePreviousOff[i] == null)
			gesturePreviousOff[i] = pawn.player.OffhandWeapon;

		// MULTI-FIRE housekeeping: HP1 then HP2 in one armed stretch leaves
		// HP1's weapon back on its own mount with its stow flags stripped
		// (they were stripped below so it could fire). Nothing else ever put
		// them back -- updateGestureArm's falling edge only knows about the
		// LAST weapon seated -- so that mount's weapon stayed permanently
		// cyclable by weapnext/weapprev while visibly parked on the arm.
		Weapon prevSeated = gestureSeatedOff[i];
		if (prevSeated != null && prevSeated != w)
		{
			prevSeated.bNoAutoSwitchTo = true;
			prevSeated.bHolsterHidden = true;
		}
		gestureSeatedOff[i] = w;

		// A stowed weapon carries bHolsterHidden/bNoAutoSwitchTo (doSwap sets
		// both on store), and this file already documents what the first one
		// means: CheckAmmo gates FIRING on it, unconditionally. So without
		// this, gesture-fire seated the weapon, jumped it to Fire, and the
		// attack was refused -- the whole feature was inert for anything
		// actually stored on a mount, which is every case it exists for.
		// Restored by updateGestureArm's falling edge when it goes back.
		w.bNoAutoSwitchTo = w.Default.bNoAutoSwitchTo;
		w.bHolsterHidden = false;

		moveWeaponInstant(pawn, w, 1);
		pawn.player.SetPsprite(PSP_OFFHANDWEAPON, fireState);

		// No hardpoint weapon model drawn. Stays hidden for as long as it
		// stays seated -- there is no swap-back here; updateGestureArm's
		// falling edge is what eventually restores gesturePreviousOff[i].
		let psp = pawn.player.GetPSprite(PSP_OFFHANDWEAPON);
		if (psp != null)
			psp.NoDraw = true;

		level.VRHaptic(1, 0.5, 20.0);
	}

	// GESTURE-CAST fire, MAIN arm -- the twin of fireGesture above, for
	// mounts 0-2. Read that one first: every design note on it (why the
	// weapon stays seated for the whole armed stretch instead of pulsing,
	// why the psprite is hidden with NoDraw rather than not created, what
	// multi-fire does, and the known ammo-check gap from jumping straight to
	// Fire) applies here unchanged.
	//
	// THE SUBSTITUTIONS, all of them:
	//   gestureArmedMain / gesturePreviousMain / gestureSeatedMain
	//   ReadyWeapon instead of OffhandWeapon  (player.zs -- the main hand's)
	//   hand 0 instead of hand 1 in moveWeaponInstant
	//   PSP_WEAPON instead of PSP_OFFHANDWEAPON  (precedent: chicken.zs:119
	//     for GetPSprite, weaponphoenix.zs:133 for SetPsprite)
	//   haptic channel 0 instead of 1
	//   the wrong-hand guard inverted -- see below.
	//
	// Hiding PSP_WEAPON hides the player's PRIMARY weapon model for as long
	// as the main hand stays armed, which is the intended read: palm-out
	// means the held weapon goes invisible and the hand drops to the reach
	// pose while the mounts do the shooting. It is not a side effect.
	private void fireGestureMain(int i, PlayerPawn pawn, int holsterIdx)
	{
		// Re-checked here rather than trusted from the last WorldTick, for
		// the exact reason fireGesture spells out: a netevent can arrive
		// between two tics, after the cvar was switched off or edit mode was
		// entered but before updateGestureArmMain has recomputed anything.
		if (!gestureEnabled() || editMode[i])
			return;

		if (!gestureArmedMain[i])
			return;

		// A hand must never be able to trigger anything on a mount it cannot
		// see. Dialing the main bank's count down hides a mount WITHOUT
		// evacuating what is stored in it (updateProps' own comment), so
		// contents[] can stay non-null on an index that is currently
		// invisible.
		if (!holsterActive(holsterIdx))
			return;

		ensureContents();
		int slot = (i * HOLSTER_COUNT) + holsterIdx;
		Weapon w = contents[slot];
		if (w == null)
			return;

		// THE WRONG-HAND GUARD, inverted from fireGesture's. MoveWeaponToHand's
		// own first line is
		//     if (weap.bNoHandSwitch && weap.bOffhandWeapon != (hand == 1)) return;
		// (player.zs:2612) and it returns VOID and SILENTLY. With hand == 0
		// that reduces to "refuse an OFF-hand weapon", where fireGesture's
		// hand == 1 reduces to "refuse a MAIN-hand weapon" -- so the test
		// here is bOffhandWeapon true, not false. Get this backwards and the
		// SetPsprite below jumps the MAIN psprite to a Fire state belonging
		// to a weapon that is not the main hand's weapon, and the VM kills
		// the game the moment one of those state functions type-checks its
		// owner ("Invalid class VR_Fist in function call to
		// VR_SMG.StateFunction").
		//
		// The same OPEN DESIGN COLLISION fireGesture documents at length
		// applies here mirrored: a main-arm mount is filled by the OFF hand,
		// so it naturally ends up holding an off-hand weapon, which is
		// exactly what this guard refuses. Read that note before touching
		// either copy.
		if (w.bNoHandSwitch && w.bOffhandWeapon)
		{
			Console.Printf("\cgRS_HARDPOINT: %s is an OFF-hand weapon on a MAIN-arm mount -- cannot gesture-fire (see fireGesture's hand-binding note)", w.GetClassName());
			return;
		}

		State fireState = w.FindState('Fire');
		if (fireState == null)
		{
			Console.Printf("\cgRS_HARDPOINT: %s has no Fire state, cannot gesture-fire", w.GetClassName());
			return;
		}

		ensureGesturePreviousMain();
		ensureGestureSeatedMain();

		// FIRST fire of this armed stretch only -- see gesturePreviousOff's
		// field comment for why a second or third fire must not overwrite it.
		if (gesturePreviousMain[i] == null)
			gesturePreviousMain[i] = pawn.player.ReadyWeapon;

		// MULTI-FIRE housekeeping, same as fireGesture: the previously seated
		// mount weapon is back on its own mount with its stow flags stripped,
		// and nothing else would ever put them back.
		Weapon prevSeated = gestureSeatedMain[i];
		if (prevSeated != null && prevSeated != w)
		{
			prevSeated.bNoAutoSwitchTo = true;
			prevSeated.bHolsterHidden = true;
		}
		gestureSeatedMain[i] = w;

		// CheckAmmo gates FIRING on bHolsterHidden, unconditionally -- so a
		// stowed weapon cannot fire until these come off. Restored by
		// updateGestureArmMain's falling edge when it goes back.
		w.bNoAutoSwitchTo = w.Default.bNoAutoSwitchTo;
		w.bHolsterHidden = false;

		moveWeaponInstant(pawn, w, 0);
		pawn.player.SetPsprite(PSP_WEAPON, fireState);

		// No hardpoint weapon model drawn. Stays hidden for as long as it
		// stays seated -- there is no swap-back here; updateGestureArmMain's
		// falling edge is what eventually restores gesturePreviousMain[i].
		let psp = pawn.player.GetPSprite(PSP_WEAPON);
		if (psp != null)
			psp.NoDraw = true;

		level.VRHaptic(0, 0.5, 20.0);
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
	private void moveWeaponInstant(PlayerPawn pawn, Weapon w, int hand)
	{
		if (!instantSwitchEnabled())
		{
			pawn.MoveWeaponToHand(w, hand);
			return;
		}
		bool wasSet = (pawn.player.cheats & CF_INSTANTWEAPSWITCH) != 0;
		pawn.player.cheats |= CF_INSTANTWEAPSWITCH;
		pawn.MoveWeaponToHand(w, hand);
		if (!wasSet)
			pawn.player.cheats &= ~CF_INSTANTWEAPSWITCH;
	}

	// Swap what the hand is holding with what the holster holds. Because an
	// empty hand always means "fists" and an empty holster always means
	// "nothing stored", both directions are the same operation: read both
	// sides, write both sides. Draw, store, and swap are all this.
	private void doSwap(int i, PlayerPawn pawn, int holsterIdx, bool offhand)
	{
		if (holsterIdx < 0)
			return; // hand was not in a holster; nothing claimed it

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
			return;
		if (!instantSwitchEnabled())
		{
			int otherHandTic = offhand ? lastSwapTicMain[i] : lastSwapTicOff[i];
			if (level.time - otherHandTic < swapCooldown())
				return;
		}

		ensureContents();

		int slot = (i * HOLSTER_COUNT) + holsterIdx;

		// Evict any fist a previous build managed to store. Without this the
		// bad slots persist in a running session and keep showing a fist at
		// the holster even after the store guard is fixed.
		for (int c = 0; c < HOLSTER_COUNT; ++c)
		{
			int ci = (i * HOLSTER_COUNT) + c;
			if (contents[ci] != null && isFistClass(contents[ci].GetClassName()))
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
		if (held != null && !isFistClass(held.GetClassName()))
			heldName = held.GetClassName();

		if (stored == null && heldName == "")
			return; // fists into an empty holster: nothing to do

		// The slot names the very gun this hand is holding. That is not a
		// legitimate no-op -- it is a STALE SLOT. A stored weapon never leaves
		// inventory, so CheckWeaponSwitch re-arms it on the next ammo pickup
		// while the table still claims the holster holds it.
		//
		// Used to clear the slot and RETURN here -- that fixed the permanent
		// jam (a stale slot could never be drawn from OR stored into again)
		// but traded it for a quieter one: the press that discovered the
		// stale slot did nothing visible at all (no haptic, no sound, no
		// console line), identical to a no-op press, so it read as "I have
		// to holster something else first to unstick it" even though the
		// table was already fixed by that first press. Resync stored to null
		// and fall through into the ordinary store logic below instead, so
		// the SAME press that finds the desync is the press that actually
		// completes the store, with the normal confirmation. POINTER
		// equality now (was class-name equality) -- see the field comment on
		// contents for why that mattered.
		if (stored != null && stored == held)
		{
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

			// MoveWeaponToHand is VOID and bails SILENTLY on a hand mismatch:
			//     if (weap.bNoHandSwitch && weap.bOffhandWeapon != (hand == 1)) return;
			// Every weapon in this arsenal carries +WEAPON.NOHANDSWITCH, and
			// nothing binds a holster to a hand -- either hand can claim any of
			// the six anchors, and the hip pair sit on opposite sides of the
			// body. Without this check the store above was already committed, so
			// reaching across with the wrong hand ATE the slot and delivered
			// nothing: the weapon ended up in no holster and in no hand, and the
			// console cheerfully printed a swap that never happened.
			if (w.bNoHandSwitch && w.bOffhandWeapon != offhand)
			{
				contents[slot] = stored;   // roll back the commit above
				Console.Printf("\cgRS_HARDPOINT: %s belongs to the %s hand", stored.GetClassName(), offhand ? "main" : "off");
				return;
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
		}
		else
		{
			// Holster was empty, so the hand comes back to fists. Resolved by
			// search, not by name: this arsenal has VR_Fist, RS_GH_Fist and
			// RS_PS_Fist (plus numbered tiers of each) and the right one
			// depends on the player class. Hardcoding "Fist" found nothing,
			// which is why storing a weapon appeared to do nothing at all --
			// the gun went into the holster but never left the hand.
			let fist = findFist(pawn, offhand);
			if (fist == null)
			{
				// No fist this hand can actually accept. Refusing loudly beats
				// the old behaviour, which committed the store and then failed
				// to empty the hand -- leaving the player still holding a gun
				// the table had already filed away.
				contents[slot] = stored;   // roll back; the store did not happen
				Console.Printf("\cgRS_HARDPOINT: no %s-hand fist to empty into", offhand ? "off" : "main");
				return;
			}
			moveWeaponInstant(pawn, fist, hand);
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
		// this family and is not a declared dependency of this pk3, and GZDoom
		// resolves an undefined sound to SILENCE rather than to an error -- so
		// this cue had simply never played for anybody running these mods
		// without RS_Main, with a cvar, a menu row and a style selector all
		// wired up to it. The audio now ships here under this pk3's own
		// logical and lump names; see SNDINFO.txt.
		let sndCv = CVar.GetCVar("rs_hardpoint_sound", pawn.player);
		if (sndCv == null || sndCv.GetBool())
		{
			let styleCv = CVar.GetCVar("rs_hardpoint_sound_style", pawn.player);
			string sndName = (styleCv != null && styleCv.GetInt() == 1) ? "rs_hardpoint_fx_ready" : "rs_hardpoint_fx_store";

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
		// compile (line 2015/2061 in the actual error log).
		string storedName = "";
		if (stored != null)
			storedName = stored.GetClassName();
		Console.Printf("RS_HARDPOINT: %s <-> %s (%s)",
			heldName == "" ? "fists" : heldName,
			stored == null ? "empty" : storedName,
			hsName);

		// Auto-diagnostic: if a real weapon just went INTO this holster (not a
		// fists-only draw with nothing to measure), queue a dump for next tic.
		// This is what makes "record as I play" true -- store a gun and the
		// full orientation/offset breakdown lands in the log on its own, no
		// menu, no netevent, nothing to remember mid-session.
		//
		// GATED BEHIND rs_hardpoint_verbose AS OF 2026-08-26. "Record as I
		// play" is a tuning session's want, not a shipped build's: every
		// single store printed a seven-line orientation breakdown into the
		// player's console. Gated at the SOURCE rather than at WorldTick's
		// consumption point so nothing is queued in the first place -- the
		// manual dump (netevent rs-hardpoint-debug) is untouched and still
		// prints the same numbers on demand.
		if (contents[slot] != null && verboseDiag())
			pendingDump[i] = holsterIdx;
	}

	// Everything needed to tell WHY a holster is not triggering, in one dump.
	// Without this a mislocated anchor is indistinguishable from a dead
	// system: both produce no console output at all.
	private void dumpDebug(int i, PlayerPawn pawn)
	{
		Console.Printf("\c[Gold]--- RS_HARDPOINT DEBUG ---");
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

		bool foundOri, mirrored;
		double angOff, pitOff, rolOff;
		[foundOri, mirrored, angOff, pitOff, rolOff] = level.GetModelOrientationHint(w.GetClass(), rs.sprite, rs.Frame);

		double stretch = (level.info != null) ? level.info.pixelstretch : 1.0;
		bool foundOff;
		double offX, offY, offZ;
		[foundOff, offX, offY, offZ] = level.GetModelOffsetHint(w.GetClass(), rs.sprite, rs.Frame, stretch);

		string hsName; double hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll;
		GetHolster(h, hsName, hsFwd, hsSide, hsFrac, hsRadius, hsPitch, hsYaw, hsRoll);

		// Same baseAngle/basePitch/baseRoll split as updateProps -- kept as
		// its own copy here rather than factored out, matching this
		// function's existing role as an independent recomputation for
		// diagnostics (see the file header comment on dumpOneHolsterProp).
		// Without this branch the auto-dump-on-store would print body-yaw
		// numbers for a wrist/forearm item, which is exactly the kind of
		// misleading "actual vs sphere" report this function exists to
		// prevent.
		double baseAngle, basePitch, baseRoll;
		if (isHandAnchored(h))
		{
			handBasisPose(pawn, h, baseAngle, basePitch, baseRoll);
		}
		else
		{
			baseAngle = bodyYaw[i];
			basePitch = 0.0;
			baseRoll  = 0.0;
		}
		double extra = RS_HardPointProp.holsterPropYaw() + edYaw[h] + (mirrored ? 180.0 : 0.0);
		double finalAngle = baseAngle + extra - angOff;
		double finalPitch = basePitch + edPitch[h] + RS_HardPointProp.holsterPropPitch() - pitOff;

		double finalRoll = baseRoll + edRoll[h] + RS_HardPointProp.holsterPropRoll() - rolOff;

		// Same fill-vs-fallback split ShowWeapon actually applies -- kept as
		// its own copy for the same independent-recomputation reason as the
		// angle/pitch/roll split above, not factored out into a shared
		// helper. Using the REAL applied scale here (not always the flat
		// fallback) matters: GetModelWorldOffset's own correctness depends
		// on being handed the actor scale that is actually in effect, or
		// this dump's "world offset" stops matching what is really on screen.
		bool foundBounds; double measuredRadius;
		[foundBounds, measuredRadius] = level.GetModelBoundsHint(w.GetClass(), rs.sprite, rs.Frame);
		double fallbackScale = isHandAnchored(h) ? RS_HardPointProp.holsterPropScaleArm() : RS_HardPointProp.holsterPropScale();
		double steadyStateScale = (foundBounds && measuredRadius > 0.0)
			? (hsRadius * RS_HardPointProp.holsterPropFill()) / measuredRadius
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
			level.GetModelWorldOffset(w.GetClass(), rs.sprite, rs.Frame, stretch, finalAngle, finalPitch, finalRoll,
			                          propScale, propScale);

		Console.Printf("%-13s [%s]", hsName, stored.GetClassName());
		Console.Printf("  orientation hint: found=%d mirrored=%d angOff=%.1f pitOff=%.1f rolOff=%.1f",
			foundOri, mirrored, angOff, pitOff, rolOff);
		Console.Printf("  offset hint:      found=%d  local(fwd,side,up)= %.2f, %.2f, %.2f",
			foundOff, offX, offY, offZ);
		Console.Printf("  bounds hint:      found=%d  radius=%.2f  holster r=%.2f fill=%.2f -> steady-state=%.4f  live=%.4f  (fallback would be %.4f)",
			foundBounds, measuredRadius, hsRadius, RS_HardPointProp.holsterPropFill(), steadyStateScale, propScale, fallbackScale);
		Console.Printf("  world offset:     found=%d  world(x,y,z)= %.2f, %.2f, %.2f  (via GetModelWorldOffset, replays the engine's own rotation)",
			foundWorld, worldDX, worldDY, worldDZ);
		Console.Printf("  applied:          angle=%.1f pitch=%.1f  (base angle %.1f, holster pitch %.1f, trim yaw %.1f pitch %.1f)",
			finalAngle, finalPitch, baseAngle, hsPitch, RS_HardPointProp.holsterPropYaw(), RS_HardPointProp.holsterPropPitch());

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
