--!nonstrict
-- RaidRules: pure formulas shared by server and client (for previews). No state.

local Balance = require(script.Parent.Data.Balance)

local RaidRules = {}

function RaidRules.hammerDamage(level: number): number
	local g = Balance.Gear.Hammer
	return math.floor(g.BaseDamage * g.Growth ^ (level - 1))
end

function RaidRules.sackCapacity(level: number): number
	local g = Balance.Gear.Sack
	return math.floor(g.BaseCapacity * g.Growth ^ (level - 1))
end

function RaidRules.gearCost(level: number): number
	-- cost to upgrade *to* `level`
	return math.floor(Balance.Gear.BaseCost * Balance.Gear.CostGrowth ^ (level - 2))
end

-- Fraction of the sack slow removed by boots.
function RaidRules.bootsRelief(level: number): number
	local g = Balance.Gear.Boots
	return math.min(0.9, g.BaseRelief + g.ReliefPerLevel * (level - 1))
end

-- Walk speed for a raider given sack fill (0..1) and boots level.
function RaidRules.walkSpeed(fill: number, bootsLevel: number, sprinting: boolean): number
	local base = sprinting and Balance.Player.SprintSpeed or Balance.Player.WalkSpeed
	local slow = Balance.Gear.Sack.SlowAtFull
		* math.clamp(fill, 0, 1)
		* (1 - RaidRules.bootsRelief(bootsLevel))
	return base * (1 - slow)
end

function RaidRules.xpForLevel(level: number): number
	-- XP needed to go from `level` to `level + 1`
	return math.floor(Balance.XP.Base * level ^ Balance.XP.Exponent)
end

function RaidRules.levelFromXp(xp: number): (number, number, number)
	-- returns level, xp into level, xp needed for next
	local level = 1
	local remaining = xp
	while level < Balance.XP.MaxLevel do
		local need = RaidRules.xpForLevel(level)
		if remaining < need then
			break
		end
		remaining -= need
		level += 1
	end
	return level, remaining, RaidRules.xpForLevel(level)
end

function RaidRules.upgradeSeconds(toLevel: number): number
	local u = Balance.Upgrade
	if toLevel <= u.InstantThroughLevel then
		return 0
	end
	return math.floor(u.BaseSeconds * u.SecondsGrowth ^ (toLevel - u.InstantThroughLevel - 1))
end

function RaidRules.skipGems(secondsLeft: number): number
	if secondsLeft <= 0 then
		return 0
	end
	return math.max(1, math.ceil(secondsLeft / Balance.Upgrade.SkipGemsPerSeconds))
end

function RaidRules.raidDuration(vaultLevel: number): number
	local r = Balance.Raid
	local extra = math.max(0, vaultLevel - r.VaultLevelForExtra) * r.ExtraSecondsPerVaultLevel
	return r.Duration + extra
end

-- Coins that leave the vault when it is cracked.
function RaidRules.stealable(stored: number, sackCapacity: number, raiders: number): number
	local fromVault = math.floor(stored * Balance.Vault.StealFraction)
	return math.max(0, math.min(fromVault, sackCapacity * math.max(1, raiders)))
end

function RaidRules.mineLoot(mineIncomePerHour: number): number
	return math.floor(mineIncomePerHour * Balance.Mine.SmashFraction)
end

function RaidRules.keepOnFail(sack: number): number
	return math.floor(sack * Balance.Raid.KeepOnFail)
end

function RaidRules.trophyDelta(
	win: boolean,
	raiderLevel: number,
	defenderLevel: number,
	bandit: boolean
): number
	local t = Balance.Trophies
	local delta
	if win then
		delta = math.clamp(t.WinBase - t.LevelDiffScale * (raiderLevel - defenderLevel), t.WinMin, t.WinMax)
	else
		delta = -t.Loss
	end
	if bandit then
		delta = math.floor(delta * t.BanditScale)
	end
	return delta
end

function RaidRules.shieldSeconds(lostFraction: number): number
	local s = Balance.Shield
	if lostFraction >= s.AfterWipeFraction then
		return s.AfterWipeSeconds
	elseif lostFraction >= s.AfterLossFraction then
		return s.AfterLossSeconds
	end
	return 0
end

-- Number of bandit raids inside the decay window.
function RaidRules.recentBanditRaids(times: { number }, now: number): number
	local count = 0
	for _, t in times do
		if now - t < Balance.Bandit.DecayWindow then
			count += 1
		end
	end
	return count
end

function RaidRules.banditLoot(level: number, recentRaids: number): number
	local b = Balance.Bandit
	local factor = math.max(0, 1 - b.DecayPerRaid * math.min(b.DecayMaxRaids, recentRaids))
	return math.floor(b.LootPerLevel * level * factor + 1e-6)
end

function RaidRules.leagueFor(trophies: number)
	local current = Balance.Leagues[1]
	for _, league in Balance.Leagues do
		if trophies >= league.min then
			current = league
		end
	end
	return current
end

function RaidRules.nextLeague(trophies: number)
	for _, league in Balance.Leagues do
		if trophies < league.min then
			return league
		end
	end
	return nil
end

function RaidRules.bracket(baseLevel: number): number
	return baseLevel // Balance.Matchmaking.LevelsPerBracket
end

function RaidRules.attackRating(hammer: number, sack: number, boots: number): number
	return hammer * 3 + sack * 2 + boots
end

-- Vault accrual: coins produced since `lastTick`, capped by capacity and the offline cap.
function RaidRules.accrue(
	stored: number,
	incomePerHour: number,
	lastTick: number,
	now: number,
	capacity: number
): (number, number)
	if lastTick <= 0 then
		return stored, now
	end
	local elapsed = math.max(0, now - lastTick)
	elapsed = math.min(elapsed, Balance.Mine.MaxOfflineHours * 3600)
	local gained = math.floor(incomePerHour * elapsed / 3600)
	local newStored = math.min(capacity, stored + gained)
	-- Keep fractional progress by only advancing the tick for whole coins produced.
	local usedSeconds = incomePerHour > 0 and (gained * 3600 / incomePerHour) or elapsed
	local newTick = lastTick + math.floor(usedSeconds)
	if newStored >= capacity then
		newTick = now
	end
	if now - newTick > 3600 then
		newTick = now
	end
	return newStored, newTick
end

return RaidRules
