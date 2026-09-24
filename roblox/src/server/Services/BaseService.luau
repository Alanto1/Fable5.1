--!nonstrict
-- BaseService: a player's base in the hub. Plots, building, vault accrual, shields, gear,
-- snapshots for the raid pool, and applying raid results that arrive through the inbox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)
local Pieces = require(Shared.Data.Pieces)
local Themes = require(Shared.Data.Themes)
local Net = require(Shared.Net.Net)
local Guard = require(Shared.Net.Guard)
local Signal = require(Shared.Util.Signal)
local BaseLayout = require(Shared.BaseLayout)
local RaidRules = require(Shared.RaidRules)

local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local InboxService = require(script.Parent.InboxService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local MonetizationService = require(script.Parent.MonetizationService)
local PoolService = require(script.Parent.PoolService)
local QuestService = require(script.Parent.QuestService)
local BaseRenderer = require(script.Parent.Parent.Base.BaseRenderer)

local BaseService = {
	BaseChanged = Signal.new(), -- (player)
	LevelUp = Signal.new(), -- (player, newLevel)
}

local TICK = 30
local SNAPSHOT_DEBOUNCE = 8
local MAX_RAID_LOG = 10

local plots: { [number]: Model } = {} -- plot index -> plot model
local plotOwner: { [number]: Player? } = {}
local playerPlot: { [Player]: number } = {}
local handles: { [Player]: any } = {} -- render handles in the hub
local snapshotDirty: { [Player]: number } = {}

------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------

local function profileOf(player: Player)
	local profile = DataService.getProfile(player)
	return profile, profile and profile.Data.Base
end

local function now(): number
	return os.time()
end

local function accrue(base)
	local capacity = BaseLayout.vaultCapacity(base.Layout)
	local income = BaseLayout.incomePerHour(base.Layout)
	base.Vault.Stored, base.Vault.LastTick =
		RaidRules.accrue(base.Vault.Stored, income, base.Vault.LastTick, now(), capacity)
	return capacity, income
end

local function levelFor(base)
	local level = RaidRules.levelFromXp(base.XP)
	return level
end

local function addXp(player: Player, base, amount: number)
	local before = levelFor(base)
	base.XP += math.max(0, math.floor(amount))
	local after = levelFor(base)
	base.Level = after
	if after > before then
		BaseService.LevelUp:Fire(player, after)
		Net.Server.fire(player, "LevelUp", after)
		AnalyticsService.progression(player, "BaseLevel", "Complete", after)
	end
end

local function stateFor(player: Player)
	local profile, base = profileOf(player)
	if not profile then
		return nil
	end
	local capacity, income = accrue(base)
	local level, into, need = RaidRules.levelFromXp(base.XP)
	local raider = profile.Data.Raider
	return {
		Layout = base.Layout,
		Level = level,
		XP = into,
		XPNeeded = need,
		Theme = base.Theme,
		Name = base.Name,
		Stored = base.Vault.Stored,
		Capacity = capacity,
		Income = income,
		ShieldUntil = base.ShieldUntil,
		Pending = base.Pending,
		RaidLog = base.RaidLog,
		PlotIndex = playerPlot[player],
		Rating = BaseLayout.rating(base.Layout),
		Raider = {
			Hammer = raider.Hammer,
			Sack = raider.Sack,
			Boots = raider.Boots,
			Trophies = raider.Trophies,
		},
		ServerTime = now(),
	}
end

local function push(player: Player)
	local state = stateFor(player)
	if state then
		Net.Server.fire(player, "BaseState", state)
	end
end

local function markDirty(player: Player)
	snapshotDirty[player] = os.clock()
end

function BaseService.snapshotFor(player: Player)
	local profile, base = profileOf(player)
	if not profile then
		return nil
	end
	accrue(base)
	return {
		userId = player.UserId,
		name = player.DisplayName,
		baseName = base.Name,
		level = levelFor(base),
		rating = BaseLayout.rating(base.Layout),
		layout = BaseLayout.clone(base.Layout),
		theme = base.Theme,
		stored = base.Vault.Stored,
		shieldUntil = base.ShieldUntil,
		lastRaidedAt = base.LastRaidedAt,
	}
end

local function publishSnapshot(player: Player)
	local snapshot = BaseService.snapshotFor(player)
	if snapshot then
		PoolService.publish(player.UserId, snapshot)
	end
end

------------------------------------------------------------------------------------------------
-- Plots
------------------------------------------------------------------------------------------------

local function findPlots()
	local map = workspace:WaitForChild("Map")
	local folder = map:WaitForChild("Plots")
	for _, plot in folder:GetChildren() do
		local index = plot:GetAttribute("PlotIndex")
		if index ~= nil then
			plots[index] = plot
		end
	end
end

local function assignPlot(player: Player): number?
	for index = 0, 7 do
		if plots[index] and plotOwner[index] == nil then
			plotOwner[index] = player
			playerPlot[player] = index
			return index
		end
	end
	return nil
end

local function releasePlot(player: Player)
	local index = playerPlot[player]
	if index ~= nil then
		plotOwner[index] = nil
		playerPlot[player] = nil
	end
end

function BaseService.plotRoot(player: Player): CFrame?
	local index = playerPlot[player]
	local plot = index ~= nil and plots[index] or nil
	if not plot then
		return nil
	end
	return plot.PrimaryPart.CFrame
end

function BaseService.plotModel(player: Player): Model?
	local index = playerPlot[player]
	return index ~= nil and plots[index] or nil
end

local function renderHub(player: Player)
	local profile, base = profileOf(player)
	local plot = BaseService.plotModel(player)
	if not profile or not plot then
		return
	end
	if handles[player] then
		BaseRenderer.clear(handles[player])
	end
	handles[player] = BaseRenderer.spawn(base.Layout, plot.PrimaryPart.CFrame, base.Theme, plot, "Base")
	-- Recolour the plot ground with the theme too.
	for _, child in plot:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("ThemeKey") then
			child.Color = Themes.color(base.Theme, child:GetAttribute("ThemeKey"))
		end
	end
	local sign = plot:FindFirstChild("Sign")
	if sign then
		sign:SetAttribute("OwnerName", player.DisplayName)
		sign:SetAttribute("OwnerUserId", player.UserId)
	end
end

------------------------------------------------------------------------------------------------
-- Building
------------------------------------------------------------------------------------------------

local function spendCoins(player: Player, amount: number, reason: string, sku: string?): boolean
	if amount <= 0 then
		return true
	end
	return PlayerService.addCurrency(player, "Coins", -amount, reason, sku)
end

local function place(player: Player, id: string, x: number, z: number, r: number)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	local level = levelFor(base)
	local ok, reason = BaseLayout.canPlace(base.Layout, id, x, z, r, level)
	if not ok then
		Net.Server.fire(player, "BuildError", reason)
		return
	end
	local cost = Pieces.cost(id, 1)
	if not spendCoins(player, cost, "Shop", "Piece_" .. id) then
		Net.Server.fire(player, "BuildError", "not enough coins")
		return
	end
	table.insert(base.Layout, { id = id, x = x, z = z, r = r, lvl = 1 })
	addXp(player, base, cost * Balance.XP.PerCoinSpent)
	local handle = handles[player]
	if handle then
		BaseRenderer.setPiece(handle, #base.Layout, base.Layout[#base.Layout])
	end
	if profile.Data.Tutorial.Step < 3 then
		AnalyticsService.onboarding(player, "FirstPiecePlaced")
	end
	AnalyticsService.custom(player, "PiecePlaced", 1, { piece = id })
	QuestService.progress(player, "Placed", 1)
	markDirty(player)
	push(player)
	BaseService.BaseChanged:Fire(player)
end

local function move(player: Player, index: number, x: number, z: number, r: number)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	local piece = base.Layout[index]
	if not piece then
		return
	end
	local ok, reason = BaseLayout.canPlace(base.Layout, piece.id, x, z, r, levelFor(base), index)
	if not ok then
		Net.Server.fire(player, "BuildError", reason)
		return
	end
	piece.x, piece.z, piece.r = x, z, r
	local handle = handles[player]
	if handle then
		BaseRenderer.setPiece(handle, index, piece)
	end
	markDirty(player)
	push(player)
end

local function applyUpgrade(player: Player, base, index: number, toLevel: number)
	local piece = base.Layout[index]
	if not piece then
		return
	end
	piece.lvl = toLevel
	local handle = handles[player]
	if handle then
		BaseRenderer.setPiece(handle, index, piece)
	end
	if piece.id == "Vault" then
		accrue(base)
	end
end

local function upgrade(player: Player, index: number)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	local piece = base.Layout[index]
	if not piece then
		return
	end
	local def = Pieces.get(piece.id)
	if piece.lvl >= def.maxLevel then
		Net.Server.fire(player, "BuildError", "max level")
		return
	end
	for _, pending in base.Pending do
		if pending.index == index then
			Net.Server.fire(player, "BuildError", "already upgrading")
			return
		end
	end
	local toLevel = piece.lvl + 1
	local cost = Pieces.cost(piece.id, toLevel)
	if not spendCoins(player, cost, "Shop", "Upgrade_" .. piece.id) then
		Net.Server.fire(player, "BuildError", "not enough coins")
		return
	end
	addXp(player, base, cost * Balance.XP.PerCoinSpent)
	local seconds = RaidRules.upgradeSeconds(toLevel)
	if seconds > 0 then
		table.insert(base.Pending, { index = index, toLevel = toLevel, readyAt = now() + seconds })
	else
		applyUpgrade(player, base, index, toLevel)
	end
	if profile.Data.Tutorial.Step < 6 then
		AnalyticsService.onboarding(player, "FirstUpgrade")
	end
	AnalyticsService.custom(player, "PieceUpgraded", toLevel, { piece = piece.id })
	QuestService.progress(player, "Upgraded", 1)
	markDirty(player)
	push(player)
end

local function skipUpgrade(player: Player, index: number)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	for i, pending in base.Pending do
		if pending.index == index then
			local gems = RaidRules.skipGems(pending.readyAt - now())
			if gems > 0 and not PlayerService.addCurrency(player, "Gems", -gems, "Shop", "SkipUpgrade") then
				Net.Server.fire(player, "BuildError", "not enough gems")
				return
			end
			table.remove(base.Pending, i)
			applyUpgrade(player, base, pending.index, pending.toLevel)
			markDirty(player)
			push(player)
			return
		end
	end
end

local function sell(player: Player, index: number)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	local piece = base.Layout[index]
	if not piece then
		return
	end
	local def = Pieces.get(piece.id)
	if not def.sellable then
		Net.Server.fire(player, "BuildError", "cannot sell")
		return
	end
	for i, pending in base.Pending do
		if pending.index == index then
			table.remove(base.Pending, i)
		elseif pending.index > index then
			pending.index -= 1
		end
	end
	local refund = Pieces.refund(piece.id, piece.lvl)
	table.remove(base.Layout, index)
	PlayerService.addCurrency(player, "Coins", refund, "Gameplay", "Sell_" .. piece.id)
	local handle = handles[player]
	if handle then
		BaseRenderer.refresh(handle, base.Layout)
	end
	markDirty(player)
	push(player)
end

local function setTheme(player: Player, theme: string)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	local owned = profile.Data.Cosmetics.Owned.Themes
	if not owned[theme] then
		local palette = Themes.get(theme)
		if palette.price > 0 then
			if not PlayerService.addCurrency(player, "Gems", -palette.price, "Shop", "Theme_" .. theme) then
				Net.Server.fire(player, "BuildError", "not enough gems")
				return
			end
		end
		owned[theme] = true
	end
	base.Theme = theme
	renderHub(player)
	markDirty(player)
	push(player)
end

local function collect(player: Player)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	accrue(base)
	local amount = math.floor(base.Vault.Stored)
	if amount <= 0 then
		return
	end
	local bonus = 0
	if MonetizationService.ownsPass(player, "VIP") then
		bonus += math.floor(amount * 0.10)
	end
	if profile.Data.GroupBonus then
		bonus += math.floor(amount * Balance.Group.CoinBonus)
	end
	base.Vault.Stored = 0
	base.Vault.LastTick = now()
	PlayerService.addCurrency(player, "Coins", amount + bonus, "Gameplay", "VaultCollect")
	AnalyticsService.custom(player, "VaultCollected", amount)
	QuestService.progress(player, "Collected", 1)
	markDirty(player)
	push(player)
end

local function upgradeGear(player: Player, kind: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local raider = profile.Data.Raider
	local caps = {
		Hammer = Balance.Gear.Hammer.MaxLevel,
		Sack = Balance.Gear.Sack.MaxLevel,
		Boots = Balance.Gear.Boots.MaxLevel,
	}
	local current = raider[kind]
	if not current or current >= caps[kind] then
		Net.Server.fire(player, "BuildError", "max level")
		return
	end
	local cost = RaidRules.gearCost(current + 1)
	if not spendCoins(player, cost, "Shop", "Gear_" .. kind) then
		Net.Server.fire(player, "BuildError", "not enough coins")
		return
	end
	raider[kind] = current + 1
	AnalyticsService.custom(player, "GearUpgraded", current + 1, { gear = kind })
	push(player)
end

local function rename(player: Player, name: string)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	name = name:sub(1, 24):gsub("[^%w%s!%?%.%-']", "")
	if #name < 2 then
		return
	end
	-- Filter through TextService so the name is safe to show to other players.
	local TextService = game:GetService("TextService")
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	base.Name = ok and filtered or ""
	markDirty(player)
	push(player)
end

------------------------------------------------------------------------------------------------
-- Shields and raid results
------------------------------------------------------------------------------------------------

function BaseService.giveShield(player: Player, seconds: number, source: string)
	local profile, base = profileOf(player)
	if not profile then
		return
	end
	base.ShieldUntil = math.max(base.ShieldUntil, now()) + seconds
	AnalyticsService.custom(player, "ShieldGranted", seconds, { source = source })
	markDirty(player)
	push(player)
end

function BaseService.dropShield(player: Player)
	local profile, base = profileOf(player)
	if profile and base.ShieldUntil > now() then
		base.ShieldUntil = 0
		markDirty(player)
		push(player)
	end
end

function BaseService.isShielded(player: Player): boolean
	local profile, base = profileOf(player)
	return profile ~= nil and base.ShieldUntil > now()
end

-- Applies a raid against an online player (same server) or from the inbox.
function BaseService.applyRaidResult(player: Player, profile, entry)
	local base = profile.Data.Base
	accrue(base)
	local before = base.Vault.Stored
	local lost = math.min(before, entry.amount or 0)
	base.Vault.Stored = before - lost
	base.LastRaidedAt = entry.time or now()
	base.TotalLost += lost
	base.TimesRaided += 1
	local fraction = before > 0 and lost / before or 0
	local shield = RaidRules.shieldSeconds(fraction)
	if shield > 0 then
		base.ShieldUntil = math.max(base.ShieldUntil, now() + shield)
	end
	table.insert(base.RaidLog, {
		name = entry.raiderName,
		userId = entry.raiderId,
		amount = lost,
		success = entry.success,
		time = entry.time or now(),
		revenged = false,
		bandit = false,
	})
	while #base.RaidLog > MAX_RAID_LOG do
		table.remove(base.RaidLog, 1)
	end
	Net.Server.fire(player, "RaidAlert", { name = entry.raiderName, amount = lost, success = entry.success })
	markDirty(player)
	push(player)
end

------------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------------

local function onProfileLoaded(player: Player, profile)
	local base = profile.Data.Base
	if #base.Layout == 0 then
		base.Layout = BaseLayout.starter()
		base.Vault.LastTick = now()
		base.ShieldUntil = now() + Balance.Shield.NewPlayerSeconds
	end
	local ok, err = BaseLayout.validate(base.Layout, math.max(levelFor(base), base.Level))
	if not ok then
		warn(("[Base] invalid saved layout for %s (%s); resetting"):format(player.Name, tostring(err)))
		base.Layout = BaseLayout.starter()
	end
	base.Level = levelFor(base)
	accrue(base)
	pcall(function()
		profile.Data.GroupBonus = Balance.Group.CoinBonus > 0
			and game.CreatorType == Enum.CreatorType.Group
			and player:IsInGroupAsync(game.CreatorId)
	end)
	local index = assignPlot(player)
	if index == nil then
		warn("[Base] no free plot for " .. player.Name)
	end
	renderHub(player)
	push(player)
	task.spawn(publishSnapshot, player)
end

local function onProfileReleased(player: Player)
	if handles[player] then
		BaseRenderer.clear(handles[player])
		handles[player] = nil
	end
	local plot = BaseService.plotModel(player)
	if plot then
		local sign = plot:FindFirstChild("Sign")
		if sign then
			sign:SetAttribute("OwnerName", nil)
			sign:SetAttribute("OwnerUserId", nil)
		end
	end
	releasePlot(player)
	snapshotDirty[player] = nil
end

local function tickLoop()
	while true do
		task.wait(TICK)
		for _, player in Players:GetPlayers() do
			local profile, base = profileOf(player)
			if profile then
				local changed = false
				for i = #base.Pending, 1, -1 do
					local pending = base.Pending[i]
					if pending.readyAt <= now() then
						table.remove(base.Pending, i)
						applyUpgrade(player, base, pending.index, pending.toLevel)
						changed = true
					end
				end
				local capacity = accrue(base)
				if changed then
					markDirty(player)
				end
				Net.Server.fire(player, "VaultTick", base.Vault.Stored, capacity, base.ShieldUntil)
				if changed then
					push(player)
				end
			end
		end
	end
end

local function snapshotLoop()
	while true do
		task.wait(2)
		local clock = os.clock()
		for player, since in snapshotDirty do
			if clock - since >= SNAPSHOT_DEBOUNCE then
				snapshotDirty[player] = nil
				if player.Parent then
					task.spawn(publishSnapshot, player)
				end
			end
		end
	end
end

local function periodicPublish()
	while true do
		task.wait(300)
		for _, player in Players:GetPlayers() do
			if DataService.getProfile(player) then
				task.spawn(publishSnapshot, player)
				task.wait(1)
			end
		end
	end
end

function BaseService.push(player: Player)
	push(player)
end

function BaseService.accrue(player: Player)
	local profile, base = profileOf(player)
	if profile then
		accrue(base)
	end
end

function BaseService.init()
	findPlots()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	DataService.ProfileReleased:Connect(onProfileReleased)
	Players.PlayerRemoving:Connect(function(player)
		if not DataService.getProfile(player) then
			onProfileReleased(player)
		end
	end)

	InboxService.registerHandler("RaidResult", function(player, profile, entry)
		BaseService.applyRaidResult(player, profile, entry)
	end)

	local cell = Guard.integer(0, Balance.Grid.Size - 1)
	local rotation = Guard.integer(0, 3)
	local index = Guard.integer(1, 200)

	Net.Server.on("PlacePiece", { Guard.keyOf(Pieces.ById), cell, cell, rotation }, place, { rate = 8 })
	Net.Server.on("MovePiece", { index, cell, cell, rotation }, move, { rate = 8 })
	Net.Server.on("UpgradePiece", { index }, upgrade, { rate = 5 })
	Net.Server.on("SkipUpgrade", { index }, skipUpgrade, { rate = 3 })
	Net.Server.on("SellPiece", { index }, sell, { rate = 5 })
	Net.Server.on("SetTheme", { Guard.keyOf(Themes.Palettes) }, setTheme, { rate = 2 })
	Net.Server.on("CollectVault", {}, collect, { rate = 2 })
	Net.Server.on("UpgradeGear", { Guard.enum({ "Hammer", "Sack", "Boots" }) }, upgradeGear, { rate = 3 })
	Net.Server.on("RenameBase", { Guard.string(32) }, rename, { rate = 1, burst = 2 })
	Net.Server.on("GoHome", {}, function(player)
		local plot = BaseService.plotModel(player)
		local character = player.Character
		local root = plot and character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local entrance = plot:FindFirstChild("Entrance")
			local target = entrance and entrance.CFrame * CFrame.new(0, 4, 8)
				or plot.PrimaryPart.CFrame * CFrame.new(0, 4, 40)
			character:PivotTo(
				CFrame.lookAt(target.Position, plot.PrimaryPart.Position + Vector3.new(0, 4, 0))
			)
		end
	end, { rate = 1, burst = 2 })

	Net.Server.handle("RequestBaseState", {}, function(player)
		return stateFor(player)
	end, { rate = 1, burst = 3 })

	MonetizationService.registerGrant("Shield24h", function(player)
		BaseService.giveShield(player, Balance.Shield.BuySeconds, "Robux")
		return true
	end)
	MonetizationService.registerGrant("AdShield1h", function(player)
		BaseService.giveShield(player, Balance.Shield.AdSeconds, "Ad")
		return true
	end)

	task.spawn(tickLoop)
	task.spawn(snapshotLoop)
	task.spawn(periodicPublish)
end

return BaseService
