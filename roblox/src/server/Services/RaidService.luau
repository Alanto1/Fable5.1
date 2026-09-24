--!nonstrict
-- RaidService: matchmaking, arenas, and the whole raid lifecycle.
--
--   RequestRaid -> offer -> AcceptRaid -> countdown -> raid (swings, traps, loot, extraction)
--   -> results -> inbox/notification to the defender -> back to the hub.

local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)
local Pieces = require(Shared.Data.Pieces)
local Net = require(Shared.Net.Net)
local Guard = require(Shared.Net.Guard)
local Signal = require(Shared.Util.Signal)
local BaseLayout = require(Shared.BaseLayout)
local BanditBases = require(Shared.BanditBases)
local RaidRules = require(Shared.RaidRules)

local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local InboxService = require(script.Parent.InboxService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local MonetizationService = require(script.Parent.MonetizationService)
local QuestService = require(script.Parent.QuestService)
local NotificationService = require(script.Parent.NotificationService)
local PoolService = require(script.Parent.PoolService)
local BaseService = require(script.Parent.BaseService)
local BaseRenderer = require(script.Parent.Parent.Base.BaseRenderer)
local Effects = require(script.Parent.Parent.Defense.Effects)
local Traps = require(script.Parent.Parent.Defense.Traps)
local Turrets = require(script.Parent.Parent.Defense.Turrets)
local Guards = require(script.Parent.Parent.Defense.Guards)

local RaidService = {
	RaidFinished = Signal.new(), -- (player, result)
}

local arenas: { [number]: Model } = {}
local arenaBusy: { [number]: any } = {}
local offers: { [Player]: any } = {} -- pending offers per player
local raids: { [Player]: any } = {} -- active raid per player
local swingClock: { [Player]: number } = {}
local dashClock: { [Player]: number } = {}
local reRolls: { [Player]: number } = {}

local now = os.time

-- A player is busy while they are in a raid that has not finished for them yet.
local function busy(player: Player): boolean
	local raid = raids[player]
	if not raid then
		return false
	end
	local r = raid.raiders[player]
	return raid.state ~= "Ended" and not (r and r.done)
end

local function raidIsActive(raid): boolean
	return raid.state == "Active"
end

local function vaultLevelOf(layout): number
	local vault = BaseLayout.findVault(layout)
	return vault and vault.lvl or 1
end

------------------------------------------------------------------------------------------------
-- Matchmaking
------------------------------------------------------------------------------------------------

local function raiderLevel(profile): number
	return RaidRules.levelFromXp(profile.Data.Base.XP)
end

local function liveCandidate(raider: Player, level: number)
	local candidates = {}
	for _, other in Players:GetPlayers() do
		if other ~= raider and not raids[other] then
			local profile = DataService.getProfile(other)
			if profile then
				local base = profile.Data.Base
				local otherLevel = RaidRules.levelFromXp(base.XP)
				local bracketOk = math.abs(RaidRules.bracket(otherLevel) - RaidRules.bracket(level)) <= 1
				local shielded = base.ShieldUntil > now()
				local recent = now() - base.LastRaidedAt < Balance.Matchmaking.RecentRaidCooldown
				if bracketOk and not shielded and not recent then
					table.insert(candidates, other)
				end
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local target = candidates[math.random(1, #candidates)]
	local snapshot = BaseService.snapshotFor(target)
	if not snapshot then
		return nil
	end
	return {
		kind = "Live",
		userId = target.UserId,
		player = target,
		name = target.DisplayName,
		baseName = snapshot.baseName,
		level = snapshot.level,
		rating = snapshot.rating,
		layout = snapshot.layout,
		theme = snapshot.theme,
		stored = snapshot.stored,
	}
end

local function poolCandidate(raider: Player, level: number)
	local bracket = RaidRules.bracket(level)
	local candidates = PoolService.candidates(bracket, raider.UserId)
	if #candidates == 0 and bracket > 0 then
		candidates = PoolService.candidates(bracket - 1, raider.UserId)
	end
	if #candidates == 0 then
		return nil
	end
	-- Try a few random candidates until one is raidable.
	for _ = 1, math.min(4, #candidates) do
		local pick = table.remove(candidates, math.random(1, #candidates))
		local online = Players:GetPlayerByUserId(pick.userId)
		if not online then
			local snapshot = PoolService.loadSnapshot(pick.userId)
			if snapshot and snapshot.layout then
				local shielded = (snapshot.shieldUntil or 0) > now()
				local recent = now() - (snapshot.lastRaidedAt or 0) < Balance.Matchmaking.RecentRaidCooldown
				local valid = BaseLayout.validate(snapshot.layout, snapshot.level or 1)
				if not shielded and not recent and valid then
					return {
						kind = "Pool",
						userId = pick.userId,
						name = snapshot.name or "Player",
						baseName = snapshot.baseName,
						level = snapshot.level or 1,
						rating = snapshot.rating or 0,
						layout = snapshot.layout,
						theme = snapshot.theme or "Classic",
						stored = snapshot.stored or 0,
					}
				end
			end
		end
		if #candidates == 0 then
			break
		end
	end
	return nil
end

local function banditCandidate(profile, level: number)
	local seed = math.random(1, 1000000)
	local recent = RaidRules.recentBanditRaids(profile.Data.Raider.BanditRaidTimes, now())
	local banditLevel = math.max(1, level + math.random(-1, 1))
	return {
		kind = "Bandit",
		userId = 0,
		name = BanditBases.name(banditLevel, seed),
		baseName = "",
		level = banditLevel,
		rating = 0,
		layout = BanditBases.generate(banditLevel, seed),
		theme = ({ "Classic", "Neon", "Ice", "Candy" })[math.random(1, 4)],
		stored = RaidRules.banditLoot(banditLevel, recent) * 4,
		seed = seed,
	}
end

local function makeOffer(player: Player, forceKind: string?)
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	local level = raiderLevel(profile)
	local tutorial = profile.Data.Tutorial.Step < 1
	local candidate = nil
	if tutorial then
		candidate = {
			kind = "Bandit",
			userId = 0,
			name = "Bandit Camp (Tutorial)",
			baseName = "",
			level = 1,
			rating = 0,
			layout = BanditBases.generate(1, 7),
			theme = "Classic",
			stored = 1600,
			seed = 7,
			tutorial = true,
		}
	elseif forceKind == "Bandit" then
		candidate = banditCandidate(profile, level)
	else
		if math.random() < Balance.Raid.LiveTargetChance then
			candidate = liveCandidate(player, level)
		end
		candidate = candidate or poolCandidate(player, level) or banditCandidate(profile, level)
	end
	candidate.rating = candidate.rating > 0 and candidate.rating or BaseLayout.rating(candidate.layout)
	candidate.id = HttpService:GenerateGUID(false)
	candidate.raiderLevel = level
	offers[player] = candidate

	local sackCapacity = RaidRules.sackCapacity(profile.Data.Raider.Sack)
	local exact = MonetizationService.ownsPass(player, "RaidRadar")
	local estimate = RaidRules.stealable(candidate.stored, sackCapacity, 1)
	Net.Server.fire(player, "RaidOffer", {
		id = candidate.id,
		kind = candidate.kind,
		name = candidate.name,
		baseName = candidate.baseName,
		level = candidate.level,
		rating = candidate.rating,
		loot = exact and estimate or math.floor(estimate / 100 + 0.5) * 100,
		lootExact = exact,
		duration = RaidRules.raidDuration(vaultLevelOf(candidate.layout)),
		freeReRolls = math.max(
			0,
			Balance.Raid.FreeReRolls + (exact and Balance.Raid.RadarReRolls or 0) - (reRolls[player] or 0)
		),
		reRollCost = Balance.Raid.ReRollCost,
		tutorial = candidate.tutorial == true,
	})
	return candidate
end

------------------------------------------------------------------------------------------------
-- Arena and raid state
------------------------------------------------------------------------------------------------

local function findArenas()
	local folder = workspace:WaitForChild("Map"):WaitForChild("Arenas")
	for _, arena in folder:GetChildren() do
		local index = arena:GetAttribute("ArenaIndex")
		if index ~= nil then
			arenas[index] = arena
		end
	end
end

local function allocateArena(): (number?, Model?)
	for index = 0, 7 do
		if arenas[index] and not arenaBusy[index] then
			return index, arenas[index]
		end
	end
	return nil, nil
end

local function attachmentPos(model: Model, name: string): Vector3
	for _, descendant in model:GetDescendants() do
		if descendant.Name == name then
			if descendant:IsA("Attachment") then
				return descendant.WorldPosition
			elseif descendant:IsA("BasePart") then
				return descendant.Position
			end
		end
	end
	return model:GetPivot().Position + Vector3.new(0, 5, 40)
end

local function isRaiderIn(raid)
	return function(player: Player)
		return raid.raiders[player] ~= nil and raid.state == "Active"
	end
end

local function sendRaid(raid, name: string, ...)
	for player in raid.raiders do
		Net.Server.fire(player, name, ...)
	end
end

local function sackFill(raid, player: Player): number
	local r = raid.raiders[player]
	return r.capacity > 0 and math.clamp(r.sack / r.capacity, 0, 1) or 1
end

local function spawnPiles(raid, position: Vector3, total: number, spread: number)
	if total <= 0 then
		return
	end
	local count = math.clamp(math.ceil(total / Balance.Raid.PileValue), 1, Balance.Raid.MaxPiles)
	local each = math.ceil(total / count)
	local remaining = total
	for i = 1, count do
		local value = math.min(each, remaining)
		remaining -= value
		local pile = Instance.new("Part")
		pile.Name = "Pile"
		pile.Shape = Enum.PartType.Cylinder
		pile.Size = Vector3.new(0.5, 1.6, 1.6)
		pile.Color = Color3.fromRGB(255, 205, 60)
		pile.Material = Enum.Material.Neon
		pile.CanCollide = true
		pile.CanTouch = false
		pile.CFrame = CFrame.new(position + Vector3.new(0, 3 + i * 0.1, 0))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		local angle = math.random() * math.pi * 2
		local power = spread * (0.4 + math.random() * 0.6)
		pile.AssemblyLinearVelocity =
			Vector3.new(math.cos(angle) * power, 18 + math.random() * 10, math.sin(angle) * power)
		pile:SetAttribute("Value", value)
		pile.Parent = raid.container
		pile:SetNetworkOwner(nil)
		raid.piles[pile] = value
		task.delay(2.5, function()
			if pile.Parent then
				pile.Anchored = true
			end
		end)
		if remaining <= 0 then
			break
		end
	end
	raid.lootOnGround += total
end

local function spillSack(raid, player: Player, fraction: number, at: Vector3)
	local r = raid.raiders[player]
	if not r or r.sack <= 0 then
		return
	end
	local amount = math.floor(r.sack * fraction)
	if amount <= 0 then
		return
	end
	r.sack -= amount
	spawnPiles(raid, at + Vector3.new(0, 2, 0), amount, 10)
	Net.Server.fire(player, "SackUpdated", r.sack, r.capacity, -amount)
end

local function startDefenses(raid)
	local context = {
		container = raid.container,
		isRaider = isRaiderIn(raid),
		onTrigger = function(pieceId: string, player: Player)
			raid.trapsTriggered += 1
			QuestService.progress(player, "TrapsHit", 1)
			local profile = DataService.getProfile(player)
			if profile then
				profile.Data.Index.Traps[pieceId] = true
			end
		end,
		sackSpill = function(player: Player, fraction: number, at: Vector3)
			spillSack(raid, player, fraction, at)
		end,
	}
	local extraGuards = math.max(0, raid.raiderCount - 1) * Balance.Raid.GuardsPerExtraRaider
	for index, entry in raid.base.Pieces do
		local id = entry.piece.id
		local connection = nil
		if Traps.isTrap(id) then
			connection = Traps.attach(entry, context)
		elseif Turrets.isTurret(id) then
			connection = Turrets.attach(entry, context)
		elseif Guards.isGuard(id) then
			connection = Guards.attach(entry, context)
			if extraGuards > 0 then
				extraGuards -= 1
				local extra = Guards.attach(entry, context)
				table.insert(raid.defenses, extra)
			end
		end
		if connection then
			table.insert(raid.defenses, connection)
		end
		local _ = index
	end
end

local function stopDefenses(raid)
	for _, connection in raid.defenses do
		pcall(function()
			connection:Disconnect()
		end)
	end
	raid.defenses = {}
end

local function teleport(player: Player, position: Vector3, lookAt: Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local cf = lookAt and CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
			or CFrame.new(position)
		character:PivotTo(cf)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function hubSpawn(): Vector3
	local plaza = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plaza")
	local spawn = plaza and plaza:FindFirstChild("Spawn")
	return spawn and spawn.Position + Vector3.new(0, 4, 0) or Vector3.new(0, 10, 26)
end

------------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------------

local finishRaider -- forward

local function endRaid(raid)
	if raid.state == "Ended" then
		return
	end
	raid.state = "Ended"
	stopDefenses(raid)
	for player in raid.raiders do
		if not raid.raiders[player].done then
			finishRaider(raid, player, "Timeout")
		end
	end
	task.delay(Balance.Raid.ResultsSeconds, function()
		for player in raid.raiders do
			if raids[player] ~= raid then
				continue -- already in a new raid
			end
			raids[player] = nil
			Effects.clear(player)
			if player.Parent then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if character then
					character:SetAttribute("Raiding", false)
					character:SetAttribute("SackFill", 0)
				end
				if humanoid then
					humanoid.WalkSpeed = Balance.Player.WalkSpeed
					humanoid.Health = humanoid.MaxHealth
				end
				teleport(player, hubSpawn())
				Net.Server.fire(player, "RaidLeft")
			end
		end
		BaseRenderer.clear(raid.base)
		if raid.container.Parent then
			raid.container:Destroy()
		end
		arenaBusy[raid.arenaIndex] = nil
	end)
end

local function checkAllDone(raid)
	for _, r in raid.raiders do
		if not r.done then
			return
		end
	end
	endRaid(raid)
end

finishRaider = function(raid, player: Player, outcome: string)
	local r = raid.raiders[player]
	if not r or r.done then
		return
	end
	r.done = true
	r.outcome = outcome
	local kept = outcome == "Extracted" and r.sack or RaidRules.keepOnFail(r.sack)
	local success = outcome == "Extracted" and r.sack > 0
	local profile = DataService.getProfile(player)
	local clutch = outcome == "Extracted" and (raid.endsAt - now()) <= Balance.Raid.ClutchSeconds

	if profile then
		local raider = profile.Data.Raider
		local multiplier = 1
		if MonetizationService.ownsPass(player, "DoubleLoot") then
			multiplier *= 2
		end
		if profile.Data.Boosts.DoubleLootUntil > now() then
			multiplier *= 2
		end
		local banked = math.floor(kept * multiplier)
		if banked > 0 then
			PlayerService.addCurrency(player, "Coins", banked, "Gameplay", "Raid")
		end
		local bandit = raid.target.kind == "Bandit"
		local delta = RaidRules.trophyDelta(success, raid.target.raiderLevel, raid.target.level, bandit)
		raider.Trophies = math.max(0, raider.Trophies + delta)
		raider.Raids += 1
		if success then
			raider.Wins += 1
		end
		raider.Stolen += banked
		raider.BestRaid = math.max(raider.BestRaid, banked)
		if bandit then
			table.insert(raider.BanditRaidTimes, now())
			while #raider.BanditRaidTimes > 20 do
				table.remove(raider.BanditRaidTimes, 1)
			end
		end
		local base = profile.Data.Base
		base.XP += success and Balance.XP.PerRaidWin or Balance.XP.PerRaidLoss
		base.Level = RaidRules.levelFromXp(base.XP)
		if raid.target.tutorial then
			profile.Data.Tutorial.Step = math.max(profile.Data.Tutorial.Step, 1)
			AnalyticsService.onboarding(
				player,
				outcome == "Extracted" and "TutorialRaidExtracted" or "TutorialRaidStarted"
			)
		elseif profile.Data.Tutorial.Step < 4 then
			profile.Data.Tutorial.Step = 4
			AnalyticsService.onboarding(player, "FirstRealRaid")
		end
		if raid.target.revenge and success then
			for _, entry in base.RaidLog do
				if entry.userId == raid.target.userId then
					entry.revenged = true
				end
			end
			AnalyticsService.onboarding(player, "FirstRevenge")
		end
		AnalyticsService.custom(player, "RaidResult", banked, {
			outcome = outcome,
			target = raid.target.kind,
			success = tostring(success),
			clutch = tostring(clutch),
		})
		AnalyticsService.progression(player, "Raids", success and "Complete" or "Fail", raider.Raids)
		QuestService.progress(player, "RaidWins", success and 1 or 0)
		QuestService.progress(player, "Stolen", banked)
		if not bandit then
			QuestService.progress(player, "PlayerRaids", 1)
		end
		if clutch then
			QuestService.progress(player, "Clutch", 1)
		end
		if outcome == "Extracted" and r.sack >= r.capacity then
			QuestService.progress(player, "FullSack", 1)
		end

		Net.Server.fire(player, "RaidEnded", {
			outcome = outcome,
			success = success,
			sack = r.sack,
			banked = banked,
			multiplier = multiplier,
			trophies = delta,
			trophiesTotal = raider.Trophies,
			timeLeft = math.max(0, raid.endsAt - now()),
			traps = raid.trapsTriggered,
			clutch = clutch,
			target = raid.target.name,
			kind = raid.target.kind,
		})
		BaseService.push(player)
	end

	-- Defender side: apply the loss once per raid (first raider to finish reports the total).
	if not raid.defenderApplied and raid.target.kind ~= "Bandit" then
		raid.defenderApplied = true
		local totalStolen = 0
		for _, other in raid.raiders do
			totalStolen += other.outcome == "Extracted" and other.sack or RaidRules.keepOnFail(other.sack)
		end
		task.delay(0.1, function()
			-- Recompute after everyone finished (they finish within the same tick on timeout).
			totalStolen = 0
			for _, other in raid.raiders do
				if other.done then
					totalStolen += other.outcome == "Extracted" and other.sack or RaidRules.keepOnFail(
						other.sack
					)
				end
			end
			local entry = {
				type = "RaidResult",
				raiderName = raid.leader.DisplayName,
				raiderId = raid.leader.UserId,
				amount = totalStolen,
				success = totalStolen > 0,
				time = now(),
			}
			local defender = Players:GetPlayerByUserId(raid.target.userId)
			local defenderProfile = defender and DataService.getProfile(defender)
			if defender and defenderProfile then
				BaseService.applyRaidResult(defender, defenderProfile, entry)
			else
				InboxService.push(raid.target.userId, entry)
				if totalStolen > 0 then
					task.spawn(NotificationService.send, raid.target.userId, "Raided", {
						raiderName = raid.leader.DisplayName,
						amount = totalStolen,
					}, "revenge:" .. raid.leader.UserId)
				end
			end
			PoolService.markRaided(raid.target.userId, totalStolen)
		end)
	end

	RaidService.RaidFinished:Fire(player, outcome)
	checkAllDone(raid)
end

local function startRaid(leader: Player, target, party: { Player })
	local arenaIndex, arena = allocateArena()
	if not arena then
		Net.Server.fire(leader, "RaidError", "All arenas are busy. Try again in a moment.")
		return
	end
	arenaBusy[arenaIndex] = true

	local container = Instance.new("Folder")
	container.Name = "Raid_" .. arenaIndex
	container.Parent = workspace

	local raidState: string = "Countdown"
	local raid = {
		id = target.id,
		arenaIndex = arenaIndex,
		arena = arena,
		container = container,
		target = target,
		leader = leader,
		raiders = {},
		raiderCount = #party,
		state = raidState,
		defenses = {},
		piles = {},
		lootOnGround = 0,
		trapsTriggered = 0,
		vaultCracked = false,
		defenderApplied = false,
		startedAt = now(),
		endsAt = 0,
	}
	raid.base =
		BaseRenderer.spawn(target.layout, arena.PrimaryPart.CFrame, target.theme, container, "TargetBase")

	local spawnPos = attachmentPos(arena, "RaiderSpawn")
	local vaultEntry = nil
	for _, entry in raid.base.Pieces do
		if entry.piece.id == "Vault" then
			vaultEntry = entry
		end
	end
	local duration = RaidRules.raidDuration(vaultEntry and vaultEntry.piece.lvl or 1)

	for i, player in party do
		local profile = DataService.getProfile(player)
		if profile then
			raids[player] = raid
			raid.raiders[player] = {
				sack = 0,
				capacity = RaidRules.sackCapacity(profile.Data.Raider.Sack),
				hammer = RaidRules.hammerDamage(profile.Data.Raider.Hammer),
				boots = profile.Data.Raider.Boots,
				done = false,
				outcome = nil,
			}
			offers[player] = nil
			BaseService.dropShield(player)
			local character = player.Character or player.CharacterAdded:Wait()
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
			character:SetAttribute("Raiding", true)
			character:SetAttribute("HammerSkin", profile.Data.Cosmetics.Equipped.Hammer)
			character:SetAttribute("SackSkin", profile.Data.Cosmetics.Equipped.Sack)
			teleport(
				player,
				spawnPos + Vector3.new((i - 1) * 4 - (#party - 1) * 2, 0, 0),
				arena.PrimaryPart.Position
			)
			Net.Server.fire(player, "RaidStarted", {
				id = raid.id,
				arenaIndex = arenaIndex,
				target = target.name,
				kind = target.kind,
				level = target.level,
				countdown = Balance.Raid.Countdown,
				duration = duration,
				startsAt = workspace:GetServerTimeNow() + Balance.Raid.Countdown,
				sackCapacity = raid.raiders[player].capacity,
				tutorial = target.tutorial == true,
			})
			if target.tutorial then
				AnalyticsService.onboarding(player, "TutorialRaidStarted")
			end
		end
	end

	task.delay(Balance.Raid.Countdown, function()
		if raid.state ~= "Countdown" then
			return
		end
		raid.state = "Active"
		raid.endsAt = now() + duration
		startDefenses(raid)
		sendRaid(raid, "RaidGo", raid.endsAt)
		-- Timer
		task.delay(duration, function()
			if raidIsActive(raid) then
				endRaid(raid)
			end
		end)
	end)
	return raid
end

------------------------------------------------------------------------------------------------
-- Per-tick raid updates: speed, pickups, extraction
------------------------------------------------------------------------------------------------

local function inExit(arena: Model, position: Vector3): boolean
	local exit = arena:FindFirstChild("Exit")
	if not exit then
		return false
	end
	local local_ = exit.CFrame:PointToObjectSpace(position)
	local half = exit.Size / 2
	return math.abs(local_.X) <= half.X + 1 and math.abs(local_.Z) <= half.Z + 1 and math.abs(local_.Y) <= 6
end

local function raidTick()
	for player, raid in raids do
		local r = raid.raiders[player]
		if r and not r.done and raid.state == "Active" then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				-- Speed
				local sprinting = character:GetAttribute("Sprinting") == true
				local speed = RaidRules.walkSpeed(sackFill(raid, player), r.boots, sprinting)
				humanoid.WalkSpeed = speed * Effects.speedMultiplier(player)
				character:SetAttribute("SackFill", sackFill(raid, player))
				-- Pickups
				local leftovers = {}
				for pile, value in raid.piles do
					if
						pile.Parent
						and (pile.Position - root.Position).Magnitude <= Balance.Raid.PickupRange
					then
						if r.sack >= r.capacity then
							break
						end
						local space = r.capacity - r.sack
						local taken = math.min(value, space)
						r.sack += taken
						raid.piles[pile] = nil
						raid.lootOnGround -= value
						pile:Destroy()
						Net.Server.fire(player, "SackUpdated", r.sack, r.capacity, taken)
						if taken < value then
							table.insert(leftovers, value - taken)
						end
					end
				end
				for _, amount in leftovers do
					-- Leave the remainder as a smaller pile for a teammate.
					spawnPiles(raid, root.Position, amount, 3)
				end
				-- Extraction
				if inExit(raid.arena, root.Position) and (r.sack > 0 or raid.vaultCracked) then
					finishRaider(raid, player, "Extracted")
				end
			elseif humanoid and humanoid.Health <= 0 then
				finishRaider(raid, player, "Died")
			end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Inputs
------------------------------------------------------------------------------------------------

local function onSwing(player: Player, targetPart)
	local raid = raids[player]
	if not raid or raid.state ~= "Active" then
		return
	end
	local r = raid.raiders[player]
	if not r or r.done then
		return
	end
	local clock = os.clock()
	if swingClock[player] and clock - swingClock[player] < Balance.Raid.SwingCooldown * 0.9 then
		return
	end
	swingClock[player] = clock
	if Effects.speedMultiplier(player) == 0 then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	Net.Server.fireExcept(player, "SwingFx", player)
	if typeof(targetPart) ~= "Instance" or not targetPart:IsA("BasePart") then
		return
	end
	if
		(targetPart.Position - root.Position).Magnitude
		> Balance.Raid.SwingRange + targetPart.Size.Magnitude / 2
	then
		return
	end

	-- Guards take damage as humanoids.
	local guardModel = targetPart.Parent
	if guardModel and guardModel:GetAttribute("Guard") and guardModel:IsDescendantOf(raid.container) then
		local humanoid = guardModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(r.hammer)
			Net.Server.fireAll("HitFx", targetPart, humanoid.Health / humanoid.MaxHealth, "Guard")
		end
		return
	end

	local model = BaseRenderer.pieceFromInstance(targetPart)
	if not model or not model:IsDescendantOf(raid.container) then
		return
	end
	local hp = model:GetAttribute("HP") or 0
	local maxHp = model:GetAttribute("MaxHP") or 1
	if hp <= 0 then
		return
	end
	hp -= r.hammer
	model:SetAttribute("HP", math.max(0, hp))
	local pieceId = model:GetAttribute("PieceId")
	Net.Server.fireAll("HitFx", targetPart, math.max(0, hp) / maxHp, pieceId)
	if hp > 0 then
		return
	end

	-- Broken
	local index = model:GetAttribute("PieceIndex")
	local entry = raid.base.Pieces[index]
	local position = model:GetPivot().Position
	local level = model:GetAttribute("Level") or 1
	if pieceId == "Vault" then
		raid.vaultCracked = true
		local total = 0
		for _, other in raid.raiders do
			total += other.capacity
		end
		local loot = RaidRules.stealable(raid.target.stored, total, 1)
		spawnPiles(raid, position + Vector3.new(0, 3, 0), loot, 16)
		Net.Server.fireAll("BreakFx", position, "Vault")
		sendRaid(raid, "VaultCracked", loot)
		-- Keep the vault body as a broken shell: hide the door and wheel.
		for _, child in model:GetChildren() do
			if child.Name == "Door" or child.Name == "Wheel" or child.Name:sub(1, 5) == "Spoke" then
				child.Transparency = 1
				child.CanCollide = false
			end
		end
		local profile = DataService.getProfile(player)
		if profile then
			profile.Data.Index.Walls.Vault = true
		end
	else
		if pieceId == "Mine" then
			local loot = RaidRules.mineLoot(Pieces.stat("Mine", level, "income"))
			spawnPiles(raid, position + Vector3.new(0, 2, 0), loot, 8)
		end
		local profile = DataService.getProfile(player)
		if profile and Pieces.get(pieceId).category == "Wall" then
			profile.Data.Index.Walls[pieceId] = true
			QuestService.progress(player, "WallsBroken", 1)
		end
		Net.Server.fireAll("BreakFx", position, pieceId)
		if entry then
			raid.base.Pieces[index] = nil
		end
		-- Debris: a few chunks that fall and vanish.
		for _ = 1, 4 do
			local chunk = Instance.new("Part")
			chunk.Size = Vector3.new(1, 1, 1) * (0.6 + math.random() * 0.8)
			chunk.Color = targetPart.Color
			chunk.Material = targetPart.Material
			chunk.CFrame = CFrame.new(position + Vector3.new(math.random() * 2 - 1, 2, math.random() * 2 - 1))
			chunk.AssemblyLinearVelocity =
				Vector3.new(math.random() * 20 - 10, 15 + math.random() * 10, math.random() * 20 - 10)
			chunk.CanCollide = false
			chunk.Parent = raid.container
			Debris:AddItem(chunk, 2)
		end
		model:Destroy()
	end
end

local function onDash(player: Player)
	local raid = raids[player]
	if not raid or raid.state ~= "Active" then
		return
	end
	local clock = os.clock()
	if dashClock[player] and clock - dashClock[player] < Balance.Player.DashCooldown then
		return
	end
	if Effects.speedMultiplier(player) == 0 then
		return
	end
	dashClock[player] = clock
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.1 then
		dir = root.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	Effects.push(player, dir * Balance.Player.DashSpeed + Vector3.new(0, 2, 0))
	Net.Server.fireAll("DashFx", player)
end

local function onRequestRaid(player: Player, mode: string?)
	if busy(player) then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	reRolls[player] = 0
	makeOffer(player, mode == "Bandit" and "Bandit" or nil)
end

local function onReRoll(player: Player)
	if busy(player) or not offers[player] then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local free = Balance.Raid.FreeReRolls
		+ (MonetizationService.ownsPass(player, "RaidRadar") and Balance.Raid.RadarReRolls or 0)
	local used = reRolls[player] or 0
	if used >= free then
		if not PlayerService.addCurrency(player, "Coins", -Balance.Raid.ReRollCost, "Gameplay", "ReRoll") then
			Net.Server.fire(player, "RaidError", "Not enough coins to re-roll.")
			return
		end
	end
	reRolls[player] = used + 1
	AnalyticsService.custom(player, "ReRoll", used + 1)
	makeOffer(player)
end

local function onAcceptRaid(player: Player, offerId: string)
	if busy(player) then
		return
	end
	local offer = offers[player]
	if not offer or offer.id ~= offerId then
		Net.Server.fire(player, "RaidError", "That offer expired. Find a new target.")
		return
	end
	-- Party: friends in this server who opted in through the party UI (attribute set by PartyService later).
	local party = { player }
	startRaid(player, offer, party)
end

local function onRevenge(player: Player, targetUserId: number)
	if busy(player) then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local found = nil
	for _, entry in profile.Data.Base.RaidLog do
		if entry.userId == targetUserId and not entry.revenged then
			found = entry
		end
	end
	if not found then
		return
	end
	local online = Players:GetPlayerByUserId(targetUserId)
	local snapshot = online and BaseService.snapshotFor(online) or PoolService.loadSnapshot(targetUserId)
	if
		not snapshot
		or not snapshot.layout
		or not BaseLayout.validate(snapshot.layout, snapshot.level or 1)
	then
		Net.Server.fire(player, "RaidError", "That base is not available right now.")
		return
	end
	local candidate = {
		kind = online and "Live" or "Pool",
		userId = targetUserId,
		player = online,
		name = snapshot.name or found.name,
		baseName = snapshot.baseName,
		level = snapshot.level or 1,
		rating = snapshot.rating or 0,
		layout = snapshot.layout,
		theme = snapshot.theme or "Classic",
		stored = snapshot.stored or 0,
		revenge = true,
		id = HttpService:GenerateGUID(false),
		raiderLevel = raiderLevel(profile),
	}
	offers[player] = candidate
	local sackCapacity = RaidRules.sackCapacity(profile.Data.Raider.Sack)
	Net.Server.fire(player, "RaidOffer", {
		id = candidate.id,
		kind = candidate.kind,
		name = candidate.name,
		baseName = candidate.baseName,
		level = candidate.level,
		rating = candidate.rating,
		loot = RaidRules.stealable(candidate.stored, sackCapacity, 1),
		lootExact = true,
		duration = RaidRules.raidDuration(vaultLevelOf(candidate.layout)),
		freeReRolls = 0,
		reRollCost = Balance.Raid.ReRollCost,
		revenge = true,
	})
end

local function onLeaveRaid(player: Player)
	local raid = raids[player]
	if raid and raid.raiders[player] and not raid.raiders[player].done then
		finishRaider(raid, player, "Left")
	end
end

------------------------------------------------------------------------------------------------

function RaidService.isRaiding(player: Player): boolean
	return busy(player)
end

function RaidService.init()
	findArenas()

	Net.Server.on(
		"RequestRaid",
		{ Guard.optional(Guard.enum({ "Any", "Bandit" })) },
		onRequestRaid,
		{ rate = 2 }
	)
	Net.Server.on("ReRoll", {}, onReRoll, { rate = 2 })
	Net.Server.on("AcceptRaid", { Guard.string(64) }, onAcceptRaid, { rate = 2 })
	Net.Server.on("Revenge", { Guard.integer(1) }, onRevenge, { rate = 1, burst = 2 })
	Net.Server.on("LeaveRaid", {}, onLeaveRaid, { rate = 2 })
	Net.Server.on("Swing", { Guard.optional(Guard.instance("BasePart")) }, onSwing, { rate = 4, burst = 6 })
	Net.Server.on("Dash", {}, onDash, { rate = 1, burst = 2 })
	Net.Server.on("SetSprint", { Guard.boolean() }, function(player, sprinting)
		local character = player.Character
		if character then
			character:SetAttribute("Sprinting", sprinting)
		end
	end, { rate = 6 })

	MonetizationService.registerGrant("AdRaidKey", function(player, profile)
		profile.Data.Boosts.DoubleLootUntil = math.max(profile.Data.Boosts.DoubleLootUntil, now()) + 600
		Net.Server.fire(player, "BoostUpdated", profile.Data.Boosts)
		return true
	end)

	Players.PlayerRemoving:Connect(function(player)
		local raid = raids[player]
		if raid and raid.raiders[player] and not raid.raiders[player].done then
			finishRaider(raid, player, "Left")
		end
		offers[player] = nil
		raids[player] = nil
		swingClock[player] = nil
		dashClock[player] = nil
		reRolls[player] = nil
		Effects.clear(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.MaxHealth = Balance.Player.MaxHealth
				humanoid.Health = Balance.Player.MaxHealth
				humanoid.WalkSpeed = Balance.Player.WalkSpeed
			end
			-- Dying mid-raid ends that raider's run; the results screen handles the rest.
			if humanoid then
				humanoid.Died:Connect(function()
					local raid = raids[player]
					if raid and raid.raiders[player] and not raid.raiders[player].done then
						finishRaider(raid, player, "Died")
					end
				end)
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(0.15)
			local ok, err = pcall(raidTick)
			if not ok then
				warn("[Raid] tick error: " .. tostring(err))
			end
		end
	end)
end

return RaidService
