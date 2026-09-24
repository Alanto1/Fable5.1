--!nonstrict
-- Quests: daily quest templates. Three are picked per day per player (seeded by day and user).
-- `stat` is the counter systems report through QuestService.progress(player, stat, amount).

local Quests = {
	{ id = "win3", text = "Win 3 raids", stat = "RaidWins", target = 3, gems = 10 },
	{ id = "win5", text = "Win 5 raids", stat = "RaidWins", target = 5, gems = 15 },
	{ id = "steal2k", text = "Steal 2,000 coins", stat = "Stolen", target = 2000, gems = 10 },
	{ id = "steal10k", text = "Steal 10,000 coins", stat = "Stolen", target = 10000, gems = 20 },
	{ id = "place3", text = "Place 3 pieces", stat = "Placed", target = 3, gems = 10 },
	{ id = "upgrade2", text = "Upgrade 2 pieces", stat = "Upgraded", target = 2, gems = 10 },
	{ id = "collect2", text = "Collect your vault twice", stat = "Collected", target = 2, gems = 10 },
	{ id = "player1", text = "Raid a player's base", stat = "PlayerRaids", target = 1, gems = 10 },
	{ id = "traps5", text = "Survive 5 traps", stat = "TrapsHit", target = 5, gems = 10 },
	{ id = "extract3", text = "Extract with a full sack", stat = "FullSack", target = 1, gems = 15 },
	{ id = "walls10", text = "Smash 10 walls", stat = "WallsBroken", target = 10, gems = 10 },
	{ id = "clutch", text = "Extract with under 3 seconds left", stat = "Clutch", target = 1, gems = 20 },
}

return Quests
