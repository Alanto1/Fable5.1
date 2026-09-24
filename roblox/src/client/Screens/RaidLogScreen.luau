--!nonstrict
-- RaidLogScreen: who raided you, what they took, and a Revenge button per raider.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local HudController = require(Controllers.HudController)
local HubController = require(Controllers.HubController)

local RaidLogScreen = {}

local list, emptyLabel

local function render()
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local state = HubController.baseState()
	local log = state and state.RaidLog or {}
	emptyLabel.Visible = #log == 0
	for i = #log, 1, -1 do
		local entry = log[i]
		local row = Make("Frame", {
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundColor3 = Theme.Colors.PanelLight,
			LayoutOrder = #log - i,
			Parent = list,
			[1] = Components.corner(12),
			[2] = Components.padding(10),
		})
		local took = entry.amount > 0 and ("took %s coins"):format(Format.short(entry.amount))
			or "got nothing"
		Components.Text({
			Text = ("%s %s"):format(entry.name or "Someone", took),
			Font = Theme.Fonts.Display,
			TextSize = 17,
			Color = entry.amount > 0 and Theme.Colors.Danger or Theme.Colors.Success,
			Size = UDim2.new(0.65, 0, 0, 22),
			Parent = row,
		})
		Components.Text({
			Text = Format.duration(math.max(0, os.time() - (entry.time or os.time()))) .. " ago",
			TextSize = 12,
			Color = Theme.Colors.TextMuted,
			Size = UDim2.new(0.65, 0, 0, 16),
			Position = UDim2.new(0, 0, 0, 24),
			Parent = row,
		})
		if entry.userId and entry.userId > 0 then
			local _, api = Components.Button({
				Text = entry.revenged and "DONE" or "REVENGE",
				TextSize = 15,
				Color = entry.revenged and Theme.Colors.Stroke or Theme.Colors.Danger,
				ColorDark = entry.revenged and Theme.Colors.Background or Theme.Colors.DangerDark,
				Size = UDim2.new(0, 150, 0, 40),
				Position = UDim2.new(1, 0, 0.5, 0),
				Anchor = Vector2.new(1, 0.5),
				Parent = row,
				OnClick = function()
					Net.Client.fire("Revenge", entry.userId)
				end,
			})
			api.setDisabled(entry.revenged == true)
		end
	end
end

local function build()
	local frame, body = HudController.modal({
		Name = "RaidLog",
		Size = UDim2.new(0, 600, 0, 420),
		Title = "RAIDS ON YOUR BASE",
	})
	emptyLabel = Components.Text({
		Text = "Nobody has raided you yet. Build defenses before they do.",
		TextSize = 15,
		Color = Theme.Colors.TextMuted,
		Align = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.new(0, 0, 0.4, 0),
		Parent = body,
	})
	list = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = body,
		[1] = Make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	render()
	return frame, { onOpen = render }
end

function RaidLogScreen.register()
	HudController.registerScreen("RaidLog", build)
	HubController.BaseChanged:Connect(function()
		if HudController.isOpen("RaidLog") then
			render()
		end
	end)
end

return RaidLogScreen
