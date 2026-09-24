--!strict
-- Server-to-client events, created up front so clients can subscribe before the first fire.
-- Client-to-server remotes are created by the service that handles them during init.

return {
	-- framework
	"ProfileSnapshot",
	"CurrencyChanged",
	"PassesUpdated",
	"ProductGranted",
	"BoostUpdated",
	-- base
	"BaseState",
	"VaultTick",
	"LevelUp",
	"BuildError",
	"RaidAlert",
	-- raid
	"RaidError",
	"RaidOffer",
	"RaidStarted",
	"RaidGo",
	"SackUpdated",
	"VaultCracked",
	"RaidEnded",
	"RaidLeft",
	"ApplyImpulse",
	-- effects
	"HitFx",
	"BreakFx",
	"TrapFx",
	"TurretFx",
	"GuardFx",
	"SwingFx",
	"DashFx",
	-- live ops
	"QuestsUpdated",
	"QuestComplete",
	"CodeResult",
	"CosmeticsUpdated",
	"LeagueReward",
} :: { string }
