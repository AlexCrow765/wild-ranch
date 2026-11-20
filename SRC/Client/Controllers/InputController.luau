--!strict
--[[
	InputController
	Tracks which kind of device the player is currently using so UI can show the
	right prompts (keys on PC, on-screen arrows on mobile, D-pad on console).

	Steering (designer approved): GetSteer() returns -1 (left) .. +1 (right) from
	  PC:      A/D and Left/Right arrows
	  Gamepad: left stick X and D-pad left/right
	  Mobile:  two on-screen buttons (HudController calls SetTouchSteer)
	The rules for combining sources live in Shared/Rules/SteerInput (tested): the same direction
	counts once, opposite directions cancel to 0, and steering is 0 whenever not riding
	(RideController calls SetRidingActive).

	Phase 6 adds the QTE directions here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local CourseConfig = require(Shared:WaitForChild("Config"):WaitForChild("CourseConfig"))
local SteerInput = require(Shared:WaitForChild("Rules"):WaitForChild("SteerInput"))

local LEFT_KEYS = { Enum.KeyCode.A, Enum.KeyCode.Left }
local RIGHT_KEYS = { Enum.KeyCode.D, Enum.KeyCode.Right }

local thumbstickX = 0
local touchLeft = false
local touchRight = false
local ridingActive = false

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

local function anyKeyDown(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

-- Steering input: -1 = full left, +1 = full right, 0 = none.
function InputController.GetSteer(): number
	-- Keyboard is ignored while the player is typing (e.g. in chat).
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	return SteerInput.Resolve({
		Riding = ridingActive,
		KeyboardLeft = not typing and anyKeyDown(LEFT_KEYS),
		KeyboardRight = not typing and anyKeyDown(RIGHT_KEYS),
		DPadLeft = UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.DPadLeft),
		DPadRight = UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.DPadRight),
		StickX = thumbstickX,
		TouchLeft = touchLeft,
		TouchRight = touchRight,
	}, CourseConfig.SteerStickDeadzone)
end

-- RideController turns steering on for the duration of a ride; turning it off also drops any
-- held on-screen buttons so nothing can carry into the next run.
function InputController.SetRidingActive(active: boolean)
	ridingActive = active
	if not active then
		touchLeft = false
		touchRight = false
	end
end

function InputController.IsRidingActive(): boolean
	return ridingActive
end

-- Called by the on-screen steering buttons.
function InputController.SetTouchSteer(side: "Left" | "Right", pressed: boolean)
	if side == "Left" then
		touchLeft = pressed
	else
		touchRight = pressed
	end
end

function InputController.ClearTouchSteer()
	touchLeft = false
	touchRight = false
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

	-- Track the left stick (InputChanged gives its current position).
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick1 then
			thumbstickX = input.Position.X
		end
	end)
	UserInputService.GamepadDisconnected:Connect(function(gamepad)
		if gamepad == Enum.UserInputType.Gamepad1 then
			thumbstickX = 0
		end
	end)
end

return InputController
