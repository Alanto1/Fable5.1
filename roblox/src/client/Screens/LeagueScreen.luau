--!nonstrict
-- LeagueScreen: your league, the next one, and the global boards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local RaidRules = require(Shared.RaidRules)
local Net = require(Shared.Net.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local HudController = require(Controllers.HudController)

local LeagueScreen = {}

local header, boards

local function fillBoard(list, entries, valueFormatter)
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for rank, entry in entries or {} do
		if rank > 25 then
			break
		end
		local row = Make("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = rank % 2 == 0 and Theme.Colors.PanelLight or Theme.Colors.Panel,
			LayoutOrder = rank,
			Parent = list,
			[1] = Components.corner(6),
		})
		Components.Text({
			Text = ("#%d"):format(rank),
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			Size = UDim2.new(0, 40, 1, 0),
			Position = UDim2.new(0, 6, 0, 0),
			Parent = row,
		})
		Components.Text({
			Text = entry.name or "Player",
			TextSize = 13,
			Size = UDim2.new(0.55, 0, 1, 0),
			Position = UDim2.new(0, 46, 0, 0),
			Parent = row,
		})
		Components.Text({
			Text = valueFormatter(entry.value),
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			Align = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.35, -8, 1, 0),
			Position = UDim2.new(0.65, 0, 0, 0),
			Parent = row,
		})
	end
end

local function refresh()
	local data = Net.Client.invoke("GetLeaderboards")
	if not data then
		return
	end
	local me = data.Me or { Trophies = 0, Stolen = 0, Raids = 0, Wins = 0, Best = 0 }
	local league = RaidRules.leagueFor(me.Trophies)
	local nextLeague = RaidRules.nextLeague(me.Trophies)
	header.Text = ("%s LEAGUE  •  %d trophies%s\n%d raids, %d wins, best haul %s, total stolen %s"):format(
		league.name:upper(),
		me.Trophies,
		nextLeague and ("  •  %d to %s"):format(nextLeague.min - me.Trophies, nextLeague.name)
			or "  •  top league",
		me.Raids,
		me.Wins,
		Format.short(me.Best),
		Format.short(me.Stolen)
	)
	fillBoard(boards.Trophies, data.Trophies, function(v)
		return tostring(v)
	end)
	fillBoard(boards.Stolen, data.Stolen, function(v)
		return Format.short(v)
	end)
end

local function build()
	local frame, body =
		HudController.modal({ Name = "League", Size = UDim2.new(0, 720, 0, 480), Title = "LEAGUE" })
	header = Components.Text({
		Text = "",
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 44),
		VAlign = Enum.TextYAlignment.Top,
		Parent = body,
	})
	boards = {}
	for i, key in { "Trophies", "Stolen" } do
		local column = Make("Frame", {
			Name = key,
			BackgroundTransparency = 1,
			Size = UDim2.new(0.5, -6, 1, -56),
			Position = UDim2.new((i - 1) * 0.5, (i - 1) * 6, 0, 52),
			Parent = body,
		})
		Components.Text({
			Text = key == "Trophies" and "TOP TROPHIES" or "TOP THIEVES",
			Font = Theme.Fonts.Display,
			TextSize = 16,
			Size = UDim2.new(1, 0, 0, 22),
			Parent = column,
		})
		boards[key] = Make("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -26),
			Position = UDim2.new(0, 0, 0, 26),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			Parent = column,
			[1] = Make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
	end
	return frame, {
		onOpen = function()
			task.spawn(refresh)
		end,
	}
end

function LeagueScreen.register()
	HudController.registerScreen("League", build)
	Net.Client.on("LeagueReward", function(leagueName, gems)
		HudController.toast(("Weekly %s league reward: +%d gems"):format(leagueName, gems), "success", 4)
	end)
end

return LeagueScreen
