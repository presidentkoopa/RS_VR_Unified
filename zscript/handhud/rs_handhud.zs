// RS_HandHUD -- THE HUD ON YOUR HANDS.
//
// Two plates, one strapped to each hand, drawn the way the hands themselves
// are drawn: a model on a psprite layer that rides the controller at render
// rate (rs_hands.zs LAYER_MAIN/OFF, RR_Ammo's in-hand magazine). No world
// billboard, no per-tic placement, no per-weapon calibration -- the hand is
// the one thing whose pose is exact, and a fixed offset in its frame lands on
// the same spot of the wrist every frame.
//
// Each plate is skinned with a CANVAS TEXTURE (ANIMDEFS RSHUDMAIN / RSHUDOFF)
// painted from ZScript, the mechanism the wheel already uses for its card
// faces. The content is the stock HUD: the big red status-bar digits, the
// small yellow ones, MEDIA0, the armor pickup icon, the key icons and the
// mugshot. Nothing on either plate needs an asset this package does not
// already get for free from the IWAD.
//
// ROLES. The WEAPON plate follows whatever is in that hand -- loaded /
// capacity in big digits, reserve under it. The VITALS plate carries the
// mugshot, health, armor and keys. Weapon on the main wrist, vitals on the
// off forearm by default; rs_handhud_swap flips them for a left-hander.
//
// THE WRIST GATE is what makes this hudless rather than a HUD stuck to your
// hand: a plate is faded out unless that wrist is rolled toward your face,
// the way you check a watch. rs_handhud_always switches the gate off while
// the plates are being placed.
//
// TWO SCOPES, ON PURPOSE. WorldTick (play) owns the layers, the gate and the
// numbers; it cannot touch the status bar. UiTick (ui) owns the painting; it
// can read the numbers play left behind and ask StatusBar for the mugshot.
// The play side changes the world, the ui side only draws -- which is also
// why the ui side never writes anything the play side reads.

class RS_HandHUDPlateMain : Inventory
{
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
		TNT1 A -1;
		Stop;
	}
}
class RS_HandHUDPlateOff : RS_HandHUDPlateMain {}

class RS_HandHUD : EventHandler
{
	// Beside the hand (900000) and the reload's magazine (900010).
	const LAYER_MAIN = 900020;
	const LAYER_OFF  = 1900020;

	// Must match the canvastexture lines in ANIMDEFS.
	const CANVAS_W = 256;
	const CANVAS_H = 128;

	// ---- play state, read by ui -------------------------------------------
	private double mAlpha[2];       // current fade per hand
	private bool   mLayerUp[2];     // the psprite is currently installed

	// The numbers, resolved in play scope because the resolvers are play.
	private int  mWepLoaded;        // -1: no magazine split, show the pool only
	private int  mWepCap;
	private int  mWepPool;          // reserve (or the whole pool)
	private bool mWepDry;
	private bool mWepNone;          // no weapon in the weapon hand
	private int  mHealth;
	private int  mArmor;
	private TextureID mArmorIcon;
	private Array<TextureID> mKeyIcons;
	private int  mSigWep;           // change signatures, so ui repaints only on change
	private int  mSigVit;

	// ---- ui state --------------------------------------------------------
	private ui int mPaintedWep;
	private ui int mPaintedVit;
	private ui int mPaintedMug;

	private clearscope static double cvNum(string name, PlayerInfo p, double fb)
	{
		let c = CVar.GetCVar(name, p);
		return c ? c.GetFloat() : fb;
	}
	private clearscope static bool cvOn(string name, PlayerInfo p, bool fb)
	{
		let c = CVar.GetCVar(name, p);
		return c ? c.GetBool() : fb;
	}

	// Which hand carries the weapon plate. The other carries vitals.
	private clearscope static int weaponHand(PlayerInfo p) { return cvOn("rs_handhud_swap", p, false) ? 1 : 0; }
	clearscope static int LayerFor(int hand) { return (hand == 0) ? LAYER_MAIN : LAYER_OFF; }
	clearscope static Name ClassFor(int hand) { return (hand == 0) ? 'RS_HandHUDPlateMain' : 'RS_HandHUDPlateOff'; }
	clearscope static String CanvasFor(int hand) { return (hand == 0) ? "RSHUDMAIN" : "RSHUDOFF"; }

	// ======================================================================
	// PLAY
	// ======================================================================
	override void WorldTick()
	{
		let p = players[consoleplayer];
		if (!p) return;
		let pmo = p.mo;

		bool on = pmo && pmo.health > 0 && pmo.OverrideAttackPosDir && cvOn("rs_handhud", p, true);
		if (!on)
		{
			Hide(p, 0);
			Hide(p, 1);
			return;
		}

		Resolve(p, pmo);

		double fade = max(1.0, cvNum("rs_handhud_fade", p, 6.0));
		double scale = cvNum("rs_handhud_scale", p, 1.0);
		if (scale <= 0.0) scale = 1.0;

		for (int h = 0; h < 2; h++)
		{
			double target = Gate(p, pmo, h) ? 1.0 : 0.0;
			if (mAlpha[h] < target) mAlpha[h] = min(target, mAlpha[h] + 1.0 / fade);
			else if (mAlpha[h] > target) mAlpha[h] = max(target, mAlpha[h] - 1.0 / fade);

			if (mAlpha[h] <= 0.01) { Hide(p, h); continue; }
			Show(p, pmo, h, scale, mAlpha[h]);
		}
	}

	// THE WRIST GATE. Roll the wrist toward your face and the plate comes up.
	// The engine's roll fields turn opposite to actor roll (rs_held.zs), so
	// the target angles are simply whatever reads right in the headset --
	// tune rs_handhud_roll_main/off rather than reasoning about the sign.
	private bool Gate(PlayerInfo p, PlayerPawn pmo, int hand)
	{
		if (cvOn("rs_handhud_always", p, false)) return true;
		double roll   = (hand == 0) ? pmo.MainHandRoll : pmo.OffhandRoll;
		double target = cvNum(hand == 0 ? "rs_handhud_roll_main" : "rs_handhud_roll_off", p, hand == 0 ? 90.0 : -90.0);
		double tol    = cvNum("rs_handhud_roll_tol", p, 45.0);
		double d = roll - target;
		while (d >  180.0) d -= 360.0;
		while (d < -180.0) d += 360.0;
		return abs(d) <= tol;
	}

	// Same plumbing as RR_Ammo.Show: an inert Inventory item is the layer's
	// caller, MODELDEF puts the plate model on it, the canvas is its skin.
	private void Show(PlayerInfo p, PlayerPawn pmo, int hand, double scale, double alpha)
	{
		Name cls = ClassFor(hand);
		let it = pmo.FindInventory(cls);
		if (!it)
		{
			pmo.GiveInventory(cls, 1);
			it = pmo.FindInventory(cls);
			if (!it) return;
		}
		int layer = LayerFor(hand);
		let psp = p.FindPSprite(layer);
		if (!psp || psp.Caller != it)
		{
			State st = it.FindState("Spawn");
			if (!st) return;
			p.SetPsprite(layer, st, false, it);
			psp = p.FindPSprite(layer);
			if (!psp) return;
		}
		psp.scale = (scale, scale);
		psp.alpha = alpha;
		mLayerUp[hand] = true;
	}

	private void Hide(PlayerInfo p, int hand)
	{
		mAlpha[hand] = 0.0;
		if (!mLayerUp[hand]) return;
		let psp = p.FindPSprite(LayerFor(hand));
		if (psp) psp.SetState(null);
		mLayerUp[hand] = false;
	}

	// The numbers. Play scope, because wr_Stats / RR_Mag / RR_Feed are play.
	private void Resolve(PlayerInfo p, PlayerPawn pmo)
	{
		int wh = weaponHand(p);
		Weapon w = (wh == 0) ? p.ReadyWeapon : p.OffhandWeapon;

		mWepNone   = (w == null) || RS_HandFist.IsFistClass(w.GetClass());
		mWepLoaded = -1;
		mWepCap    = 0;
		mWepPool   = 0;
		mWepDry    = false;

		if (!mWepNone)
		{
			Ammo a1 = w.Ammo1;
			int pool = a1 ? a1.Amount : -1;

			if (a1 && cvOn("rr_magazines", p, false))
			{
				// The reload lane's split: the Ammo item IS the magazine and
				// RR_Reserve holds the pool behind it.
				int f, a;
				[f, a] = RR_Feed.Resolve(w, p);
				mWepLoaded = a1.Amount;
				mWepCap    = RR_Feed.CapOf(a, w, p);
				mWepPool   = RR_Mag.Pool(pmo, a1);
			}
			else
			{
				// A weapon that keeps its own magazine (Ammo2, or a mod field
				// wr_Stats knows about). Otherwise the pool is the whole story.
				int src, loaded, cap;
				[src, loaded, cap] = wr_Stats.Magazine(w);
				if (src != wr_Stats.SRC_UNKNOWN && src != wr_Stats.SRC_MASKED && cap > 0)
				{
					if (loaded < 0)
					{
						// wr_Rig.hasMagazine's test, inlined (it is private): Ammo2 is a
						// magazine only when it is a different pool and not an alt-fire pool.
						bool mag2 = w.Ammo2 != null && w.Ammo1 != w.Ammo2 && !wr_Rig.hasAltFire(w);
						loaded = mag2 ? w.Ammo2.Amount : (a1 ? a1.Amount : 0);
					}
					mWepLoaded = loaded;
					mWepCap    = cap;
					mWepPool   = pool;
				}
				else
				{
					mWepPool = pool;
				}
			}
			mWepDry = (mWepLoaded >= 0) ? (mWepLoaded <= 0) : (pool == 0);
		}

		mHealth = pmo.health;
		let armor = BasicArmor(pmo.FindInventory('BasicArmor'));
		mArmor = (armor && armor.Amount > 0) ? armor.Amount : 0;
		if (mArmor > 0) mArmorIcon = armor.Icon; else mArmorIcon.SetInvalid();

		mKeyIcons.Clear();
		for (Inventory it = pmo.Inv; it != null; it = it.Inv)
		{
			let k = Key(it);
			if (k && k.Icon.IsValid()) mKeyIcons.Push(k.Icon);
		}

		// Change signatures. Cheap to compute, and they are what keeps the
		// painter idle on the tics where nothing moved.
		mSigWep = (mWepNone ? 1 : 0) + (mWepDry ? 2 : 0) + (mWepLoaded + 1) * 4 + mWepCap * 4096 + mWepPool * 1048576;
		mSigVit = mHealth + mArmor * 1024 + mKeyIcons.Size() * 1048576 + (mArmorIcon.IsValid() ? mArmorIcon.GetIndex() * 8 : 0);
	}

	// ======================================================================
	// UI -- the painting
	// ======================================================================
	override void UiTick()
	{
		let p = players[consoleplayer];
		if (!p || !p.mo) return;
		if (!cvOn("rs_handhud", p, true)) return;

		int wh = weaponHand(p);

		// The mugshot animates on its own (pain, grin, dead); it is the one
		// thing that can change with no number moving.
		TextureID mug;
		mug.SetInvalid();
		if (cvOn("rs_handhud_mugshot", p, true) && StatusBar)
			mug = StatusBar.GetMugShot(5);
		int mugSig = mug.IsValid() ? mug.GetIndex() : 0;

		if (mPaintedWep != mSigWep)
		{
			PaintWeapon(CanvasFor(wh));
			mPaintedWep = mSigWep;
		}
		if (mPaintedVit != mSigVit || mPaintedMug != mugSig)
		{
			PaintVitals(CanvasFor(1 - wh), mug);
			mPaintedVit = mSigVit;
			mPaintedMug = mugSig;
		}
	}

	private ui Font bigFont()
	{
		Font f = Font.GetFont("HUDFONT_DOOM");    // the big red status-bar digits
		if (!f) f = Font.GetFont("BIGFONT");
		return f;
	}
	private ui Font smallFont()
	{
		Font f = Font.GetFont("INDEXFONT_DOOM");  // the small yellow ones
		if (!f) f = Font.GetFont("SMALLFONT");
		return f;
	}

	private ui void bed(Canvas c)
	{
		// Dark bed, thin rim -- the Aliens pulse-rifle counter's bezel.
		c.Clear(0, 0, CANVAS_W, CANVAS_H, Color(255, 10, 11, 13));
		c.DrawLineFrame(Color(255, 70, 74, 80), 2, 2, CANVAS_W - 4, CANVAS_H - 4, 2);
	}

	// Weapon plate:
	//     3 / 12        loaded / capacity, big red digits
	//       128         reserve, small yellow digits
	// or, with no magazine split, the pool alone in big digits.
	private ui void PaintWeapon(String canvasName)
	{
		let c = TexMan.GetCanvas(canvasName);
		if (!c) return;
		bed(c);

		Font big = bigFont();
		Font sml = smallFont();
		if (!big || !sml) return;

		if (mWepNone)
		{
			c.DrawText(sml, Font.CR_DARKGRAY, 24, 52, "--", DTA_ScaleX, 3.0, DTA_ScaleY, 3.0);
			return;
		}

		int col = mWepDry ? Font.CR_DARKRED : Font.CR_UNTRANSLATED;
		if (mWepLoaded >= 0)
		{
			String top = String.Format("%d / %d", mWepLoaded, mWepCap);
			double sx = 2.6;
			int tw = int(big.StringWidth(top) * sx);
			c.DrawText(big, col, (CANVAS_W - tw) / 2, 18, top, DTA_ScaleX, sx, DTA_ScaleY, sx);

			String res = String.Format("%d", mWepPool);
			double ss = 2.2;
			int rw = int(sml.StringWidth(res) * ss);
			c.DrawText(sml, Font.CR_UNTRANSLATED, (CANVAS_W - rw) / 2, 84, res, DTA_ScaleX, ss, DTA_ScaleY, ss);
		}
		else
		{
			String top = String.Format("%d", mWepPool);
			double sx = 3.4;
			int tw = int(big.StringWidth(top) * sx);
			c.DrawText(big, col, (CANVAS_W - tw) / 2, 34, top, DTA_ScaleX, sx, DTA_ScaleY, sx);
		}
	}

	// Vitals plate:
	//   [mugshot]  MEDIA0  82
	//              armor   40
	//              keys
	private ui void PaintVitals(String canvasName, TextureID mug)
	{
		let c = TexMan.GetCanvas(canvasName);
		if (!c) return;
		bed(c);

		Font big = bigFont();
		if (!big) return;

		int x0 = 14;
		if (mug.IsValid())
		{
			// The face is 24x29; at 2.6x it fills the left third.
			c.DrawTexture(mug, false, 12, 22, DTA_ScaleX, 2.6, DTA_ScaleY, 2.6);
			x0 = 92;
		}

		TextureID med = TexMan.CheckForTexture("MEDIA0", TexMan.Type_Any, TexMan.TryAny);
		if (med.IsValid()) c.DrawTexture(med, false, x0, 16, DTA_ScaleX, 1.6, DTA_ScaleY, 1.6);
		c.DrawText(big, Font.CR_UNTRANSLATED, x0 + 40, 20, String.Format("%d", mHealth), DTA_ScaleX, 2.2, DTA_ScaleY, 2.2);

		if (mArmor > 0)
		{
			if (mArmorIcon.IsValid()) c.DrawTexture(mArmorIcon, false, x0, 60, DTA_ScaleX, 1.6, DTA_ScaleY, 1.6);
			c.DrawText(big, Font.CR_UNTRANSLATED, x0 + 40, 62, String.Format("%d", mArmor), DTA_ScaleX, 2.2, DTA_ScaleY, 2.2);
		}

		int kx = x0;
		for (int i = 0; i < mKeyIcons.Size() && i < 6; i++)
		{
			c.DrawTexture(mKeyIcons[i], false, kx, 100, DTA_ScaleX, 1.6, DTA_ScaleY, 1.6);
			kx += 24;
		}
	}
}
