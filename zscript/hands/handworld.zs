// The hands as WORLD ACTORS, riding the controllers through MDL_FOLLOWMAINHAND
// and MDL_FOLLOWOFFHAND.
//
// The psprite hands work, and they work because RenderHUDModel reads the
// controller transform itself, every frame. But a psprite hand is drawn relative
// to your eye: it can never be grabbed, never collide, never hold a world object
// by an arbitrary point. Everything the plan is aiming at needs the hand to be a
// thing in the world, on the same footing as the gun.
//
// This is the same wire the M9 world actor uses, pointed at the other two poses.
//
// THREE THINGS THAT LOOK LIKE TRACKING FAILURE AND ARE NOT:
//   - a TNT1 sprite is never drawn, model or not -- it is an instruction to skip
//     the actor entirely, checked before any model is considered.
//   - the actor is CULLED on its true world position while being DRAWN at your
//     hand, so it must be kept near the player or it silently vanishes.
//   - world-path scale is vr_vunits_per_meter (34 units/metre). The HUD path
//     works out to 173.44. A model scaled for one is wildly wrong on the other,
//     and that is the entire "100x" class of bug in one sentence.

class RS_HandWorldBase : Actor
{
    Default
    {
        +NOGRAVITY;
        +NOBLOCKMAP;
        +NOINTERACTION;
        // MUST be present, and its absence is a hard crash rather than a warning.
        // The MODELDEF block for these ends in BaseFrame, which registers into
        // BaseSpriteModelFrames -- and that registry is what a DECOUPLEDANIMATIONS
        // actor's model lookup reads. BaseFrame without the flag is a mismatched
        // pair: the model is registered somewhere nothing consults, and the lookup
        // walks a path that was never set up. It took the game down on map load
        // with nothing in the log at all.
        +DECOUPLEDANIMATIONS;
        Radius 1;
        Height 1;
        RenderStyle "Normal";
    }


    // ---- POSES -------------------------------------------------------------
    //
    // HOW A POSE ACTUALLY REACHES THE BONES, because this is the part every
    // previous attempt got wrong.
    //
    // The hand rig carries ONE clip, "ArmatureAction", 1298 frames. The poses
    // are FRAMES of it: 0-10 are the baked hand shapes and 1289-1297 are the
    // manipulation set. There is no separate animation to play and nothing to
    // start -- holding a grip is one frame re-asserted.
    //
    // The decoupled animation path resolves a frame through MODELDEF's sprite
    // letter table, which caps at MAX_SPRITE_FRAMES. No sprite letter can name
    // frame 1293. That is the whole reason the manipulation set has been
    // authored and unreachable this entire time -- not a rigging problem, an
    // addressing one.
    //
    // ModelFrame / ModelFrameNext / ModelFrameLerp address a frame by NUMBER
    // and bypass that table. They existed only on DPSprite, which is why the
    // psprite hands could be posed and world-actor hands never could; they are
    // now on AActor too (actor.h, RS fork).
    //
    // The lerp blends BONE MATRICES, not sprite frames -- the fingers travel
    // from one shape to the other, so a grip closes rather than appearing
    // closed. Setting both frames equal with a lerp of 0 is an explicit
    // instruction NOT to blend, and that reads as the hand teleporting.

    const POSE_OPEN     = 0;   // rest
    const POSE_POINT    = 1;   // 3-4-5 closed, index and thumb out
    const POSE_TRIGGER  = 2;   // index curled alone
    const POSE_FIST     = 3;
    const POSE_PINCH    = 4;   // thumb meets index -- magazines, shells, slide
    const POSE_THUMBOUT = 5;   // fist, thumb clear -- magazine release
    const POSE_GRIPFIRE = 6;   // on a gun, trigger pulled
    const POSE_GRIP_TU  = 7;   // on a gun, thumb lifted
    const POSE_READY_TD = 8;   // index resting ON the trigger, thumb wrapped
    const POSE_READY_TU = 9;   // index on the trigger, thumb lifted
    const POSE_FIRE_TU  = 10;  // firing, thumb lifted
    const POSE_MAX      = 10;

    const HOLD_BASE     = 1289;
    const POSE_HOLD_ROUND    = HOLD_BASE + 0;   // one cartridge, fingertips
    const POSE_HOLD_SHELL    = HOLD_BASE + 1;
    const POSE_INSERT        = HOLD_BASE + 2;   // thumb driving it home
    const POSE_HOLD_SLIDE    = HOLD_BASE + 3;   // pinched on the serrations
    const POSE_HOLD_MAG      = HOLD_BASE + 4;
    const POSE_HOLD_FOREGRIP = HOLD_BASE + 5;
    const POSE_HOLD_FOREND   = HOLD_BASE + 6;   // a fat cylinder -- a barrel
    const POSE_REACH         = HOLD_BASE + 7;   // splayed, about to take hold
    const POSE_SUPPORT       = HOLD_BASE + 8;   // wrapped round the firing hand

    // Capacitive pads. Where the fingers REST, which buttons cannot report: a
    // thumb lying on the stick and a thumb lifted clear are the same button
    // state, and so are a finger indexed along the frame and one on the trigger.
    const TOUCH_THUMB = 1;
    const TOUCH_INDEX = 2;

    // Blend state.
    private int    poseFrom, poseTo;
    private double poseT;

    // What the thing being HELD wants this hand to look like, -1 for nothing.
    // Written by whatever took hold of something -- a gun's grab handler knows
    // it was caught by the barrel and this is how it says so. Deliberately not
    // a set of weapon-specific flags: any future weapon says what shape it
    // needs and needs no support here.
    int poseHold;

    void SetPose(int frame)
    {
        if (frame == poseTo) return;
        // Interrupting a blend keeps the ORIGINAL start rather than snapping to
        // the abandoned target first.
        if (poseT >= 1.0) poseFrom = poseTo;
        poseTo = frame;
        poseT  = 0;
    }

    int GetPose() const { return poseTo; }

    // Called by the holder every tic it wants a shape; -1 hands control back to
    // the controllers.
    void HoldPose(int frame) { poseHold = frame; }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        poseFrom = POSE_OPEN;
        poseTo   = POSE_OPEN;
        poseT    = 1.0;
        poseHold = -1;
    }

    override void Tick()
    {
        Super.Tick();

        // Position is for CULLING only -- the renderer takes the draw transform
        // straight from the controller. moving=false so no interpolation is
        // retained: this transform is authored elsewhere and smearing it between
        // tics is exactly the drift the world path exists to avoid.
        let p = players[consoleplayer].mo;
        if (p)
            SetOrigin(p.Pos, false);

        // Advance the blend and publish it. Written every tic rather than only
        // on change: these are renderer-owned fields with no serialisation, and
        // a value written once and never refreshed is exactly the kind of thing
        // that survives until the first save/load and then quietly stops.
        double speed = 4.0;
        let c = CVar.GetCVar("rs_handworld_blend", players[consoleplayer]);
        if (c && c.GetFloat() > 0) speed = c.GetFloat();

        if (poseT < 1.0)
        {
            poseT += 1.0 / speed;
            if (poseT >= 1.0) { poseT = 1.0; poseFrom = poseTo; }
        }

        ModelFrame     = poseFrom;
        ModelFrameNext = poseTo;
        ModelFrameLerp = poseT;
    }

    States
    {
    Spawn:
        PIST A -1;   // any REAL sprite; TNT1 would skip the actor entirely
        Stop;
    }
}

class RS_HandWorldMain : RS_HandWorldBase { }
class RS_HandWorldOff  : RS_HandWorldBase { }

// Spawns them and keeps exactly one of each alive.
class RS_HandWorldHandler : EventHandler
{
    static bool Flag(String name, PlayerInfo p, bool fallback)
    {
        let c = CVar.GetCVar(name, p);
        return c ? c.GetBool() : fallback;
    }

    override void WorldLoaded(WorldEvent e)
    {
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!playeringame[i] || players[i].mo == null) continue;
            let p = players[i];
            let pmo = p.mo;

            bool want = Flag("rs_handworld", p, true);

            for (int k = 0; k < 2; k++)
            {
                String cls = (k == 0) ? "RS_HandWorldMain" : "RS_HandWorldOff";
                bool found = false;
                ThinkerIterator it = ThinkerIterator.Create(cls);
                Actor a;
                while (a = Actor(it.Next()))
                {
                    if (!want) { a.Destroy(); }
                    else found = true;
                }
                if (want && !found)
                    Actor.Spawn(cls, pmo.Pos);
            }

            Console.Printf("[HANDWORLD] world hands %s", want ? "ON" : "off");
        }
    }

    // Find a hand, so anything holding something can ask for a shape.
    static RS_HandWorldBase Get(int hand)
    {
        String cls = (hand == 0) ? "RS_HandWorldMain" : "RS_HandWorldOff";
        ThinkerIterator it = ThinkerIterator.Create(cls);
        Actor a = Actor(it.Next());
        return RS_HandWorldBase(a);
    }

    // What an EMPTY hand does. A hand holding something has its shape decided by
    // the thing it is holding, which is the only party that knows whether it was
    // caught by the grip or the barrel.
    static int PoseForEmpty(bool grip, bool trigger, int touch)
    {
        bool thumbDown = (touch & RS_HandWorldBase.TOUCH_THUMB) != 0;

        if (grip && trigger) return RS_HandWorldBase.POSE_FIST;
        // Empty-hand grip: three fingers closed, index out. Where the thumb goes
        // is the player's, read off the pad rather than assumed -- rest it on the
        // controller and it tucks in, lift it and it stands up.
        if (grip)    return thumbDown ? RS_HandWorldBase.POSE_POINT
                                      : RS_HandWorldBase.POSE_GRIP_TU;
        if (trigger) return RS_HandWorldBase.POSE_TRIGGER;
        return RS_HandWorldBase.POSE_OPEN;
    }

    override void WorldTick()
    {
        let p = players[consoleplayer];
        if (!p || !p.mo) return;
        let pmo = p.mo;

        // A forced pose beats everything, and it is HELD rather than latched --
        // leaving the menu on a pose parks the hand there for as long as it takes
        // to look at it. There is no console in play; this is how a pose gets
        // inspected at all.
        int forced = -1;
        let cf = CVar.GetCVar("rs_handworld_forcepose", p);
        if (cf && cf.GetInt() >= 0)
        {
            // The menu numbers the poses 0..19 continuously, because a dropdown
            // that jumps from 10 to 1289 would be absurd. The manipulation set
            // really does live past the source animation, so anything above
            // POSE_MAX is mapped across to where it actually is.
            int v = cf.GetInt();
            forced = (v <= RS_HandWorldBase.POSE_MAX)
                ? v
                : min(RS_HandWorldBase.HOLD_BASE + (v - RS_HandWorldBase.POSE_MAX - 1),
                      RS_HandWorldBase.HOLD_BASE + 8);
        }

        for (int h = 0; h < 2; h++)
        {
            let hd = Get(h);
            if (!hd) continue;

            bool grip = (h == 0) ? (pmo.GripContextMain != 0) : (pmo.GripContextOff != 0);
            bool trig = (h == 0) ? ((p.cmd.buttons & BT_ATTACK) != 0)
                                 : ((p.cmd.buttons & BT_OFFHANDATTACK) != 0);
            int touch = (h == 0) ? pmo.FingerTouchMain : pmo.FingerTouchOff;

            int want;
            if (forced >= 0)         want = forced;
            else if (hd.poseHold >= 0) want = hd.poseHold;
            else                     want = PoseForEmpty(grip, trig, touch);

            int before = hd.GetPose();
            hd.SetPose(want);

            let cd = CVar.GetCVar("rs_handworld_debug", p);
            if (cd && cd.GetBool() && before != want)
                Console.Printf("[HANDPOSE] %s -> frame %d  (grip=%d trigger=%d touch=%d hold=%d)",
                    (h == 0) ? "MAIN" : "OFF ", want, grip, trig, touch, hd.poseHold);
        }
    }
}
