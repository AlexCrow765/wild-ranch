--!strict
--[[
	RideController
	Client side of a run: follows the server's run state and drives this player's own
	character while riding.

	While Riding:
	  - default movement controls and jumping are switched off,
	  - the character moves forward at the mount speed sent by the server,
	  - steering (InputController.GetSteer) adds sideways speed (SteerSpeed),
	  - the character keeps facing the riding direction.
	The server decides when a run starts and ends, checks every position, and owns stamina.
	This controller never reports distance or stamina; it only moves the character.

	Signals for the HUD:
	  StateChanged(payload)   server run state (State, Biome, Message, ...)
	  StatsChanged(stats)     { Stamina, Progress } about 10 times per second while riding
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local InputController = require(script.Parent:WaitForChild("InputController"))

local RENDER_BIND_NAME = "WildRanchRide"

local RideController = {
	LoadOrder = 10,
	State = "Ranch",
	Payload = {} :: { [string]: any },
	Stats = { Stamina = 0, Progress = 0 } :: { [string]: number },
	StateChanged = Signal.new(),
	StatsChanged = Signal.new(),
}

local player = Players.LocalPlayer
local riding = false
local savedWalkSpeed: number? = nil

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Roblox's default control module, if this place has one. Never waits for it: some places
-- (including the current test place) have no PlayerModule in PlayerScripts.
local function getControls(): any
	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if playerModule == nil or not playerModule:IsA("ModuleScript") then
		return nil
	end
	local ok, controls = pcall(function()
		return (require(playerModule) :: any):GetControls()
	end)
	return if ok then controls else nil
end

-- Turns default walking/jumping on or off for the ride. Works with or without PlayerModule:
-- the ride loop (bound after the default controls each frame) overrides their movement anyway,
-- jumping is switched off on the Humanoid, and the mobile thumbstick/jump button are hidden.
local function setDefaultControlsEnabled(enabled: boolean)
	local controls = getControls()
	if controls then
		pcall(function()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end
	GuiService.TouchControlsEnabled = enabled
	local humanoid = getHumanoid()
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
		humanoid.AutoRotate = enabled
	end
end

local function stopRiding()
	if not riding then
		return
	end
	riding = false
	RunService:UnbindFromRenderStep(RENDER_BIND_NAME)
	InputController.ClearTouchSteer()
	local humanoid = getHumanoid()
	if humanoid then
		humanoid:Move(Vector3.zero, false)
		if savedWalkSpeed then
			humanoid.WalkSpeed = savedWalkSpeed
		end
	end
	savedWalkSpeed = nil
end

local function startRiding(payload: { [string]: any })
	stopRiding()
	local humanoid = getHumanoid()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return
	end

	local forward: Vector3 = payload.Forward
	local right: Vector3 = payload.Right
	local speed: number = payload.Speed
	local steerSpeed: number = payload.SteerSpeed

	riding = true
	savedWalkSpeed = humanoid.WalkSpeed
	setDefaultControlsEnabled(false)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)

	RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Input.Value + 1, function()
		local currentHumanoid = getHumanoid()
		if currentHumanoid == nil then
			return
		end
		local velocity = forward * speed + right * (InputController.GetSteer() * steerSpeed)
		currentHumanoid.WalkSpeed = velocity.Magnitude
		currentHumanoid:Move(velocity.Unit, false)
	end)
end

local function applyState(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.State) ~= "string" then
		return
	end
	RideController.State = payload.State
	RideController.Payload = payload

	if payload.State == "Riding" then
		startRiding(payload)
	elseif payload.State == "Collapsed" then
		stopRiding() -- the server freezes the character; controls stay off until back at the ranch
	else
		stopRiding()
		setDefaultControlsEnabled(true)
	end
	RideController.StateChanged:Fire(payload)
end

-- Temporary "Ride Plains" button (until the Phase 9 level-select screen).
function RideController.RequestTravel(biomeId: string)
	Remotes.Event("RequestTravelToBiome"):FireServer(biomeId)
end

-- Only accepted by the server while in a starting area.
function RideController.RequestReturnToRanch()
	Remotes.Event("RequestReturnToRanch"):FireServer()
end

function RideController:Start()
	Remotes.Event("RunState").OnClientEvent:Connect(applyState)
	Remotes.UnreliableEvent("RunStats").OnClientEvent:Connect(function(stats: any)
		if typeof(stats) == "table" and typeof(stats.Stamina) == "number" and typeof(stats.Progress) == "number" then
			RideController.Stats = stats
			RideController.StatsChanged:Fire(stats)
		end
	end)

	-- A respawn always ends any ride locally; the server then sends the new state.
	player.CharacterAdded:Connect(function()
		stopRiding()
	end)

	local ok, payload = pcall(function()
		return Remotes.Function("GetRunState"):InvokeServer()
	end)
	if ok and payload then
		applyState(payload)
	end
end

return RideController
