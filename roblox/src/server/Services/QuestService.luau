--!nonstrict
-- QuestService: three daily quests per player, progress counters, gem rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Data.Balance)
local Quests = require(Shared.Data.Quests)
local Net = require(Shared.Net.Net)
local Guard = require(Shared.Net.Guard)

local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local QuestService = {}

local byId = {}
for _, quest in Quests do
	byId[quest.id] = quest
end

local function today(): number
	return os.time() // 86400
end

-- Deterministic pick of N quests for (day, user).
local function pickFor(userId: number, day: number)
	local rng = Random.new(day * 1000003 + userId)
	local pool = table.clone(Quests)
	local picked = {}
	for _ = 1, Balance.Quests.PerDay do
		if #pool == 0 then
			break
		end
		local index = rng:NextInteger(1, #pool)
		local chosen = table.remove(pool, index)
		if chosen then
			table.insert(picked, chosen.id)
		end
	end
	return picked
end

local function ensureToday(profile)
	local quests = profile.Data.Quests
	local day = today()
	if quests.Day ~= day then
		quests.Day = day
		quests.Active = pickFor(profile.UserId, day)
		quests.Progress = {}
		quests.Claimed = {}
	elseif not quests.Active then
		quests.Active = pickFor(profile.UserId, day)
	end
end

local function view(profile)
	ensureToday(profile)
	local quests = profile.Data.Quests
	local out = {}
	for _, id in quests.Active do
		local quest = byId[id]
		if quest then
			table.insert(out, {
				id = id,
				text = quest.text,
				target = quest.target,
				progress = math.min(quest.target, quests.Progress[id] or 0),
				gems = quest.gems,
				claimed = quests.Claimed[id] == true,
			})
		end
	end
	return out
end

local function push(player: Player, profile)
	Net.Server.fire(player, "QuestsUpdated", view(profile))
end

function QuestService.progress(player: Player, stat: string, amount: number)
	local profile = DataService.getProfile(player)
	if not profile or amount <= 0 then
		return
	end
	ensureToday(profile)
	local quests = profile.Data.Quests
	local changed = false
	for _, id in quests.Active do
		local quest = byId[id]
		if quest and quest.stat == stat and not quests.Claimed[id] then
			local before = quests.Progress[id] or 0
			if before < quest.target then
				quests.Progress[id] = math.min(quest.target, before + amount)
				changed = true
				if quests.Progress[id] >= quest.target then
					Net.Server.fire(player, "QuestComplete", quest.text, quest.gems)
				end
			end
		end
	end
	if changed then
		push(player, profile)
	end
end

local function claim(player: Player, id: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensureToday(profile)
	local quests = profile.Data.Quests
	local quest = byId[id]
	if not quest or not table.find(quests.Active, id) or quests.Claimed[id] then
		return
	end
	if (quests.Progress[id] or 0) < quest.target then
		return
	end
	quests.Claimed[id] = true
	PlayerService.addCurrency(player, "Gems", quest.gems, "TimedReward", "Quest_" .. id)
	AnalyticsService.custom(player, "QuestClaimed", quest.gems, { quest = id })
	push(player, profile)
end

function QuestService.init()
	DataService.ProfileLoaded:Connect(function(player, profile)
		ensureToday(profile)
		push(player, profile)
	end)
	Net.Server.on("ClaimQuest", { Guard.keyOf(byId) }, claim, { rate = 3 })
	Net.Server.handle("GetQuests", {}, function(player)
		local profile = DataService.getProfile(player)
		return profile and view(profile) or {}
	end, { rate = 1, burst = 3 })
	-- Roll over at midnight for players who stay online.
	task.spawn(function()
		while true do
			task.wait(60)
			for player, profile in DataService.getAllProfiles() do
				if profile.Data.Quests.Day ~= today() then
					ensureToday(profile)
					push(player, profile)
				end
			end
		end
	end)
end

return QuestService
