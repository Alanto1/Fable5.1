--!nonstrict
-- InputController: knows which device the player is on and exposes a single action layer so
-- gameplay code never checks UserInputService directly.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Util.Signal)

local InputController = {
	Device = "Keyboard", -- "Touch" | "Gamepad" | "Keyboard"
	DeviceChanged = Signal.new(),
}

local function classify(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
	then
		return "Keyboard"
	end
	return nil
end

local function setDevice(device: string)
	if device ~= InputController.Device then
		InputController.Device = device
		InputController.DeviceChanged:Fire(device)
	end
end

function InputController.isTouch(): boolean
	return InputController.Device == "Touch"
end

function InputController.isGamepad(): boolean
	return InputController.Device == "Gamepad"
end

function InputController.isConsole(): boolean
	return GuiService:IsTenFootInterface()
end

function InputController.init()
	if
		GuiService:IsTenFootInterface()
		or (UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled)
	then
		InputController.Device = "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		InputController.Device = "Touch"
	else
		InputController.Device = "Keyboard"
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local device = classify(inputType)
		if device then
			setDevice(device)
		end
	end)
end

return InputController
