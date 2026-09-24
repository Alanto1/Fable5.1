--!nonstrict
-- HudController: the always-on layer (currency pills, side menu) and the screen router.
-- Screens register with HudController.registerScreen(name, builder) and are opened by name;
-- only one modal screen is open at a time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Signal = require(Shared.Util.Signal)

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI.Theme)
local Make = require(UI.Make)
local Components = require(UI.Components)
local Toast = require(UI.Toast)

local ClientData = require(script.Parent.ClientData)

local HudController = {
	ScreenOpened = Signal.new(), -- (name)
	ScreenClosed = Signal.new(), -- (name)
}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = nil
local hudLayer = nil
local modalLayer = nil
local sideMenu = nil
local screens = {} -- name -> { build = fn, instance = Frame? }
local current = nil
local setCoins, setGems

local function buildRoot()
	root = Make("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	local scale = Make("UIScale", { Scale = 1, Parent = root })
	local camera = workspace.CurrentCamera
	local function rescale()
		scale.Scale = Theme.scaleFor(camera.ViewportSize)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	hudLayer = Make(
		"Frame",
		{ Name = "HudLayer", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root }
	)
	modalLayer = Make("Frame", {
		Name = "ModalLayer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})

	-- Currency pills, top-left
	local pills = Make("Frame", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.new(0, 320, 0, 40),
		Parent = hudLayer,
		[1] = Make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local _, coinSetter = Components.Pill({
		Name = "Coins",
		Color = Theme.Colors.Coin,
		Text = "0",
		LayoutOrder = 1,
		Parent = pills,
	})
	local _, gemSetter = Components.Pill({
		Name = "Gems",
		Color = Theme.Colors.Gem,
		Text = "0",
		LayoutOrder = 2,
		Parent = pills,
		OnClick = function()
			HudController.open("Shop")
		end,
	})
	setCoins, setGems = coinSetter, gemSetter

	-- Side menu, left edge
	sideMenu = Make("Frame", {
		Name = "SideMenu",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, Theme.Sizes.IconButton, 0, 400),
		Parent = hudLayer,
		[1] = Make("UIListLayout", {
			Padding = UDim.new(0, 18),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
end

function HudController.addMenuButton(props)
	return Components.IconButton({
		Name = props.Name,
		Icon = props.Icon,
		Text = props.Text,
		Color = props.Color,
		ColorDark = props.ColorDark,
		LayoutOrder = props.Order or 0,
		Parent = sideMenu,
		OnClick = function()
			if props.Screen then
				HudController.toggle(props.Screen)
			elseif props.OnClick then
				props.OnClick()
			end
		end,
	})
end

function HudController.hudLayer()
	return hudLayer
end

function HudController.modalLayer()
	return modalLayer
end

function HudController.registerScreen(name: string, build)
	screens[name] = { build = build, instance = nil }
end

function HudController.isOpen(name: string?): boolean
	if name then
		return current == name
	end
	return current ~= nil
end

function HudController.close()
	if not current then
		return
	end
	local entry = screens[current]
	local name = current
	current = nil
	if entry and entry.instance then
		local scale = entry.instance:FindFirstChildOfClass("UIScale")
		if scale then
			local tween = TweenService:Create(scale, Theme.Anim.Fast, { Scale = 0.9 })
			tween:Play()
			tween.Completed:Wait()
		end
		entry.instance.Visible = false
		if entry.onClose then
			entry.onClose()
		end
	end
	modalLayer.Visible = false
	HudController.ScreenClosed:Fire(name)
end

function HudController.open(name: string, ...)
	local entry = screens[name]
	if not entry then
		warn("[Hud] unknown screen " .. name)
		return
	end
	if current and current ~= name then
		HudController.close()
	end
	if not entry.instance then
		local instance, hooks = entry.build(modalLayer, ...)
		entry.instance = instance
		entry.onOpen = hooks and hooks.onOpen
		entry.onClose = hooks and hooks.onClose
		if not instance:FindFirstChildOfClass("UIScale") then
			Make("UIScale", { Scale = 1, Parent = instance })
		end
	end
	current = name
	modalLayer.Visible = true
	entry.instance.Visible = true
	local scale = entry.instance:FindFirstChildOfClass("UIScale")
	scale.Scale = 0.9
	TweenService:Create(scale, Theme.Anim.Pop, { Scale = 1 }):Play()
	if entry.onOpen then
		entry.onOpen(...)
	end
	HudController.ScreenOpened:Fire(name)
end

function HudController.toggle(name: string, ...)
	if current == name then
		HudController.close()
	else
		HudController.open(name, ...)
	end
end

-- Standard modal frame with title and close button. Returns frame, body.
function HudController.modal(props)
	local frame = Components.Panel({
		Name = props.Name or "Modal",
		Size = props.Size or UDim2.new(0, 720, 0, 460),
		Title = props.Title,
		ZIndex = 21,
		Parent = modalLayer,
	})
	frame.Visible = false
	local closeButton = Components.Button({
		Name = "Close",
		Text = "X",
		Color = Theme.Colors.Danger,
		ColorDark = Theme.Colors.DangerDark,
		Size = UDim2.new(0, 44, 0, 44),
		Position = UDim2.new(1, 6, 0, -6),
		Anchor = Vector2.new(1, 0),
		Radius = 22,
		ZIndex = 23,
		Parent = frame,
		OnClick = function()
			HudController.close()
		end,
	})
	closeButton.ZIndex = 23
	local body = Make("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, props.Title and (Theme.Sizes.Title + 8) or 0),
		Size = UDim2.new(1, 0, 1, -(props.Title and (Theme.Sizes.Title + 8) or 0)),
		ZIndex = 22,
		Parent = frame,
	})
	return frame, body
end

function HudController.toast(message: string, kind: string?, duration: number?)
	return Toast.show(message, kind, duration)
end

function HudController.init()
	buildRoot()
	ClientData.Changed:Connect(function(key, value, delta)
		if key == "Coins" then
			setCoins(Format.short(value))
			if delta and delta > 0 and ClientData.IsLoaded then
				Toast.show("+" .. Format.short(delta) .. " coins", "loot", 1.6)
			end
		elseif key == "Gems" then
			setGems(Format.short(value))
		end
	end)
end

return HudController
