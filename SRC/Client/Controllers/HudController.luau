--!strict
--[[
	HudController
	Grey-box Phase 3 HUD (plain UI; final styling is Phase 13):
	  - stamina bar
	  - debug readout: state, distance, segment, forward speed
	  - temporary "Ride Plains" button at the ranch (until the Phase 9 level-select screen)
	  - "Return to Ranch" button, shown only in a starting area (design notes 2.B)
	  - centre message (e.g. "Out of stamina")
	  - two large on-screen steering buttons on touch devices while riding
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseLayout = require(Shared:WaitForChild("Rules"):WaitForChild("CourseLayout"))
local CourseConfig = require(Shared:WaitForChild("Config"):WaitForChild("CourseConfig"))

local InputController = require(script.Parent:WaitForChild("InputController"))
local RideController = require(script.Parent:WaitForChild("RideController"))

local HudController = {
	LoadOrder = 20,
}

local player = Players.LocalPlayer

type Ui = {
	Gui: ScreenGui,
	StaminaFrame: Frame,
	StaminaFill: Frame,
	StaminaText: TextLabel,
	Debug: TextLabel,
	Message: TextLabel,
	RideButton: TextButton,
	ReturnButton: TextButton,
	SteerLeft: TextButton,
	SteerRight: TextButton,
}

local ui: Ui

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, text: string): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.TextColor3 = Color3.new(1, 1, 1)
	item.TextStrokeTransparency = 0.5
	item.Font = Enum.Font.GothamBold
	item.TextScaled = true
	item.Text = text
	item.Parent = parent
	return item
end

local function button(parent: Instance, name: string, size: UDim2, position: UDim2, text: string): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.Size = size
	item.Position = position
	item.AnchorPoint = Vector2.new(0.5, 1)
	item.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	item.BackgroundTransparency = 0.2
	item.TextColor3 = Color3.new(1, 1, 1)
	item.Font = Enum.Font.GothamBold
	item.TextScaled = true
	item.Text = text
	item.Visible = false
	item.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = item
	return item
end

local function steerButton(parent: Instance, side: "Left" | "Right", position: UDim2): TextButton
	local item = button(parent, `Steer{side}`, UDim2.fromOffset(150, 150), position, if side == "Left" then "◀" else "▶")
	item.AnchorPoint = Vector2.new(if side == "Left" then 0 else 1, 1)
	item.AutoButtonColor = true
	item.MouseButton1Down:Connect(function()
		InputController.SetTouchSteer(side, true)
	end)
	item.MouseButton1Up:Connect(function()
		InputController.SetTouchSteer(side, false)
	end)
	item.MouseLeave:Connect(function()
		InputController.SetTouchSteer(side, false)
	end)
	return item
end

local function build(): Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "WildRanchHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local staminaFrame = Instance.new("Frame")
	staminaFrame.Name = "Stamina"
	staminaFrame.AnchorPoint = Vector2.new(0.5, 0)
	staminaFrame.Position = UDim2.new(0.5, 0, 0, 12)
	staminaFrame.Size = UDim2.fromOffset(320, 28)
	staminaFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	staminaFrame.BackgroundTransparency = 0.2
	staminaFrame.Visible = false
	staminaFrame.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 200, 90)
	fill.BorderSizePixel = 0
	fill.Parent = staminaFrame

	local staminaText = label(staminaFrame, "Text", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), "")

	local debugLabel = label(gui, "Debug", UDim2.fromOffset(360, 90), UDim2.fromOffset(12, 12), "")
	debugLabel.TextXAlignment = Enum.TextXAlignment.Left
	debugLabel.TextYAlignment = Enum.TextYAlignment.Top
	debugLabel.TextScaled = false
	debugLabel.TextSize = 16

	local message = label(gui, "Message", UDim2.fromOffset(600, 80), UDim2.fromScale(0.5, 0.4), "")
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Visible = false

	local ride = button(gui, "RidePlains", UDim2.fromOffset(240, 60), UDim2.new(0.5, 0, 1, -24), "Ride Plains")
	ride.Activated:Connect(function()
		RideController.RequestTravel("Plains")
	end)

	local returnButton = button(gui, "ReturnToRanch", UDim2.fromOffset(240, 60), UDim2.new(0.5, 0, 1, -24), "Return to Ranch")
	returnButton.Activated:Connect(function()
		RideController.RequestReturnToRanch()
	end)

	return {
		Gui = gui,
		StaminaFrame = staminaFrame,
		StaminaFill = fill,
		StaminaText = staminaText,
		Debug = debugLabel,
		Message = message,
		RideButton = ride,
		ReturnButton = returnButton,
		SteerLeft = steerButton(gui, "Left", UDim2.new(0, 24, 1, -24)),
		SteerRight = steerButton(gui, "Right", UDim2.new(1, -24, 1, -24)),
	}
end

local function updateStamina()
	local payload = RideController.Payload
	local maxStamina = payload.MaxStamina
	if typeof(maxStamina) ~= "number" or maxStamina <= 0 then
		return
	end
	local stamina = math.max(0, RideController.Stats.Stamina or maxStamina)
	ui.StaminaFill.Size = UDim2.fromScale(math.clamp(stamina / maxStamina, 0, 1), 1)
	ui.StaminaText.Text = string.format("Stamina %.1f / %d", stamina, maxStamina)
end

local function onState(payload: { [string]: any })
	local state = payload.State
	local riding = state == "Riding"
	local collapsed = state == "Collapsed"

	ui.RideButton.Visible = state == "Ranch"
	ui.ReturnButton.Visible = state == "StartingArea"
	ui.StaminaFrame.Visible = riding or collapsed
	ui.SteerLeft.Visible = riding and UserInputService.TouchEnabled
	ui.SteerRight.Visible = riding and UserInputService.TouchEnabled

	if riding then
		RideController.Stats = { Stamina = payload.MaxStamina, Progress = 0 }
		updateStamina()
	end

	if collapsed and typeof(payload.Message) == "string" then
		ui.Message.Text = payload.Message
		ui.Message.Visible = true
	else
		ui.Message.Visible = false
	end
end

local function updateDebug()
	local lines = { `State: {RideController.State}` }
	local state = RideController.State
	if state == "Riding" or state == "Collapsed" then
		local progress = RideController.Stats.Progress or 0
		table.insert(lines, string.format("Distance: %.1f studs", progress))
		table.insert(lines, `Segment: {CourseLayout.SegmentAt(progress)} / {CourseConfig.SegmentsPerBiome}`)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local forward = RideController.Payload.Forward
		if root and root:IsA("BasePart") and typeof(forward) == "Vector3" then
			table.insert(lines, string.format("Forward speed: %.1f studs/s", root.AssemblyLinearVelocity:Dot(forward)))
		end
		if typeof(RideController.Payload.ReachDistance) == "number" then
			table.insert(lines, string.format("Expected reach: %.0f studs", RideController.Payload.ReachDistance))
		end
	end
	ui.Debug.Text = table.concat(lines, "\n")
end

function HudController:Start()
	ui = build()
	RideController.StateChanged:Connect(onState)
	RideController.StatsChanged:Connect(updateStamina)
	onState(RideController.Payload.State and RideController.Payload or { State = RideController.State })
	RunService.RenderStepped:Connect(updateDebug)
end

return HudController
