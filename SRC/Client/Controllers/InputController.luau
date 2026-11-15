--!strict
--[[
	InputController
	Tracks which kind of device the player is currently using so UI can show the
	right prompts (keys on PC, on-screen arrows on mobile, D-pad on console).

	Later phases add action mapping here (steering, QTE directions:
	WASD on PC, on-screen arrows on mobile, D-pad on Xbox/PlayStation).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

export type Scheme = "KeyboardMouse" | "Gamepad" | "Touch"

local InputController = {
	LoadOrder = 1,
	Scheme = "KeyboardMouse" :: Scheme,
	SchemeChanged = Signal.new(),
}

local function schemeFor(inputType: Enum.UserInputType): Scheme?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:match("^Gamepad") then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "KeyboardMouse"
	end
	return nil -- ignore anything else (e.g. accelerometer)
end

local function setScheme(scheme: Scheme)
	if InputController.Scheme ~= scheme then
		InputController.Scheme = scheme
		InputController.SchemeChanged:Fire(scheme)
		print(`[InputController] Input scheme: {scheme}`)
	end
end

function InputController:Init()
	-- Best initial guess before any input arrives.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self.Scheme = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		self.Scheme = "Gamepad"
	end
	local fromLast = schemeFor(UserInputService:GetLastInputType())
	if fromLast then
		self.Scheme = fromLast
	end
end

function InputController:Start()
	print(`[InputController] Input scheme: {self.Scheme}`)
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local scheme = schemeFor(inputType)
		if scheme then
			setScheme(scheme)
		end
	end)
end

return InputController
