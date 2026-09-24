--!nonstrict
-- QuestsScreen: today's three quests with progress and claim buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local HudController = require(Controllers.HudController)
local EffectsController = require(Controllers.EffectsController)

local QuestsScreen = {}

local list
local quests = {}

local function render()
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for order, quest in quests do
		local row = Make("Frame", {
			Size = UDim2.new(1, 0, 0, 86),
			BackgroundColor3 = Theme.Colors.PanelLight,
			LayoutOrder = order,
			Parent = list,
			[1] = Components.corner(12),
			[2] = Components.padding(10),
		})
		Components.Text({
			Text = quest.text,
			Font = Theme.Fonts.Display,
			TextSize = 18,
			Size = UDim2.new(0.65, 0, 0, 24),
			Parent = row,
		})
		Components.ProgressBar({
			Size = UDim2.new(0.65, 0, 0, 18),
			Position = UDim2.new(0, 0, 0, 30),
			Color = quest.progress >= quest.target and Theme.Colors.Success or Theme.Colors.Accent,
			Value = quest.progress / quest.target,
			Label = ("%d / %d"):format(quest.progress, quest.target),
			Parent = row,
		})
		Components.Text({
			Text = ("+%d gems"):format(quest.gems),
			TextSize = 13,
			Color = Theme.Colors.Gem,
			Size = UDim2.new(0.65, 0, 0, 16),
			Position = UDim2.new(0, 0, 0, 50),
			Parent = row,
		})
		local done = quest.progress >= quest.target
		local _, api = Components.Button({
			Text = quest.claimed and "CLAIMED" or (done and "CLAIM" or "IN PROGRESS"),
			TextSize = 15,
			Color = quest.claimed and Theme.Colors.Stroke or Theme.Colors.Gem,
			ColorDark = quest.claimed and Theme.Colors.Background or Theme.Colors.GemDark,
			Size = UDim2.new(0, 170, 0, 44),
			Position = UDim2.new(1, 0, 0.5, 0),
			Anchor = Vector2.new(1, 0.5),
			Parent = row,
			OnClick = function()
				Net.Client.fire("ClaimQuest", quest.id)
			end,
		})
		api.setDisabled(quest.claimed or not done)
	end
end

local function build()
	local frame, body =
		HudController.modal({ Name = "Quests", Size = UDim2.new(0, 620, 0, 400), Title = "DAILY QUESTS" })
	Components.Text({
		Text = "New quests every day. Claim gems when the bar is full.",
		TextSize = 13,
		Color = Theme.Colors.TextMuted,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = body,
	})
	list = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -26),
		Position = UDim2.new(0, 0, 0, 26),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = body,
		[1] = Make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	render()
	return frame,
		{
			onOpen = function()
				local fresh = Net.Client.invoke("GetQuests")
				if fresh then
					quests = fresh
					render()
				end
			end,
		}
end

function QuestsScreen.register()
	HudController.registerScreen("Quests", build)
	Net.Client.on("QuestsUpdated", function(data)
		quests = data
		render()
	end)
	Net.Client.on("QuestComplete", function(text, gems)
		HudController.toast(("Quest complete: %s (+%d gems ready)"):format(text, gems), "success", 4)
		EffectsController.sound("Win", 0.5, 1.2)
	end)
end

return QuestsScreen
