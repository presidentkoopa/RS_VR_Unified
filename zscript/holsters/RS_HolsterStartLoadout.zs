// Grants RS_HolsterFlashlight at the start of a game, so there's something
// to holster-test without a console `give` every fresh session.
//
// A StaticEventHandler rather than a Player.StartItem on some player
// class -- this mod does not own a player class and should not need one,
// same "no dependency on any specific pack" reasoning as everything else
// here. StaticEventHandler still needs explicit MAPINFO registration to
// actually run (see AddEventHandlers in MAPINFO.txt) -- it is NOT
// auto-registered just by existing, confirmed against GITD_FlashlightHandler
// in GlowInTheDark, which lists itself there despite also being a
// StaticEventHandler.
class RS_HolsterStartLoadout : StaticEventHandler
{
	override void PlayerEntered(PlayerEvent e)
	{
		let pawn = players[e.PlayerNumber].mo;
		if (!pawn) return;

		// FindInventory guards against re-granting a duplicate on every
		// level transition/hub return -- PlayerEntered fires far more often
		// than just "the very first spawn of a new game".
		if (pawn.FindInventory("RS_HolsterFlashlight") == null)
			pawn.GiveInventoryType("RS_HolsterFlashlight");
	}
}
