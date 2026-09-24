--!nonstrict
-- Toast: short stacked messages at the top of the screen (rewards, warnings, raid alerts).
--   Toast.show("Vault full!", "warn")   kinds: info | success | warn | danger | loot

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Make = require(script.Parent.Make)
local Components = require(script.Parent.Components)

local Toast = {}

local KIND_COLORS = {
	info = Theme.Colors.Accent,
	success = Theme.Colors.Success,
	warn = Theme.Colors.Primary,
	danger = Theme.Colors.Danger,
	loot = Theme.Colors.Coin,
}

local container = nil

local function getContainer()
	if container then
		return container
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Make("ScreenGui", {
		Name = "Toasts",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	container = Make("Frame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 420, 0, 300),
		Position = UDim2.new(0.5, 0, 0, 56),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
		[1] = Make("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
	return container
end

local order = 0

function Toast.show(message: string, kind: string?, duration: number?)
	local parent = getContainer()
	order += 1
	local color = KIND_COLORS[kind or "info"] or Theme.Colors.Accent
	local frame = Make("Frame", {
		Name = "Toast",
		BackgroundColor3 = Theme.Colors.Panel,
		Size = UDim2.new(0, 0, 0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = parent,
		[1] = Components.corner(22),
		[2] = Components.stroke(color, 3),
		[3] = Make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		[4] = Make("UIScale", { Scale = 0.6 }),
	})
	Components.Text({
		Text = message,
		Size = UDim2.new(0, 0, 1, 0),
		AutoSize = Enum.AutomaticSize.X,
		Font = Theme.Fonts.Display,
		TextSize = Theme.Sizes.Text,
		Color = Theme.Colors.Text,
		Wrap = false,
		Parent = frame,
	})
	local scale = frame:FindFirstChildOfClass("UIScale")
	TweenService:Create(scale, Theme.Anim.Pop, { Scale = 1 }):Play()
	task.delay(duration or 2.6, function()
		local out = TweenService:Create(scale, Theme.Anim.Fast, { Scale = 0.6 })
		out:Play()
		out.Completed:Wait()
		frame:Destroy()
	end)
	return frame
end

return Toast
