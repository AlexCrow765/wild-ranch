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
	  - a riding pose plays (see below) and steering input is enabled.
	The server decides when a run starts and ends, checks every position, and owns stamina.
	This controller never reports distance or stamina; it only moves the character.

	Riding pose (designer approved 2026-11-20): if MountConfig.RideAnimationId is set, that
	published animation plays; otherwise the built-in "sit" animation from the character's default
	Animate script is used as a temporary pose. It only animates the character - physics, hip
	height, movement and the server's validation are untouched, so nothing needs repositioning
	afterwards. Whenever riding stops (collapse, return home, capture/failed taming via the
	same state change, respawn, death) the pose track is stopped and destroyed and the normal
	animations take over again. If the character has no Animator or no sit animation, the ride
	continues without a pose and a warning explains why.

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
local MountConfig = require(Shared:WaitForChild("Config"):WaitForChild("MountConfig"))

local InputController = require(script.Parent:WaitForChild("InputController"))

local RENDER_BIND_NAME = "WildRanchRide"
local POSE_FADE_SECONDS = 0.15 -- visual blend in/out of the riding pose

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
local poseTrack: AnimationTrack? = nil
local configuredRideAnimation: Animation? = nil
local poseWarned = false
local savedHipHeight: number? = nil
local liftedHumanoid: Humanoid? = nil
local MOUNT_WAIT_SECONDS = 3 -- how long to wait for the server's mount to replicate

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

local function warnPose(reason: string)
	if not poseWarned then
		poseWarned = true
		warn(`[RideController] Riding without a pose: {reason}`)
	end
end

-- The animation to use while riding: the published Ride animation if configured, otherwise the
-- built-in sit animation from the character's default Animate script (temporary).
local function getRideAnimation(character: Model): Animation?
	local id = MountConfig.RideAnimationId
	if id then
		if configuredRideAnimation == nil then
			local animation = Instance.new("Animation")
			animation.Name = "WildRanchRide"
			animation.AnimationId = `rbxassetid://{id}`
			configuredRideAnimation = animation
		end
		return configuredRideAnimation
	end
	local animate = character:FindFirstChild("Animate")
	local sit = animate and animate:FindFirstChild("sit")
	local sitAnimation = sit and sit:FindFirstChildWhichIsA("Animation")
	return sitAnimation
end

local function stopPose()
	local track = poseTrack
	poseTrack = nil
	if track then
		track:Stop(POSE_FADE_SECONDS)
		task.delay(POSE_FADE_SECONDS + 0.05, function()
			track:Destroy()
		end)
	end
end

local function startPose(humanoid: Humanoid, character: Model)
	stopPose()
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		warnPose("the character's Humanoid has no Animator")
		return
	end
	local animation = getRideAnimation(character)
	if animation == nil then
		warnPose("no Ride animation is configured and the character has no default Animate.sit animation")
		return
	end
	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or result == nil then
		warnPose(`the riding animation could not be loaded ({tostring(result)})`)
		return
	end
	local track = result :: AnimationTrack
	track.Priority = Enum.AnimationPriority.Action -- above the walk/run animation
	track.Looped = true
	track:Play(POSE_FADE_SECONDS)
	poseTrack = track
end

-- Lift the rider so the mount's hooves reach the ground (the server computes RiderHipHeight from
-- the mount model; the grey-box block has none, so there is no lift). Restored by dropLift().
local function liftForMount(humanoid: Humanoid, character: Model)
	task.spawn(function()
		local mount = character:WaitForChild(MountConfig.MountInstanceName, MOUNT_WAIT_SECONDS)
		local hipHeight = mount and mount:GetAttribute("RiderHipHeight")
		if not riding or player.Character ~= character or typeof(hipHeight) ~= "number" then
			return
		end
		if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
			warn("[RideController] Rider lift needs an R15 character; the mount may sit below the ground")
			return
		end
		if savedHipHeight == nil then
			savedHipHeight = humanoid.HipHeight
			liftedHumanoid = humanoid
		end
		humanoid.HipHeight = hipHeight
	end)
end

local function dropLift()
	local humanoid, original = liftedHumanoid, savedHipHeight
	liftedHumanoid, savedHipHeight = nil, nil
	if humanoid and original and humanoid.Parent then
		humanoid.HipHeight = original
	end
end

local function stopRiding()
	-- Input, pose and lift are always cleared, even if a ride never fully started.
	InputController.SetRidingActive(false)
	stopPose()
	dropLift()
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
	InputController.SetRidingActive(true)
	startPose(humanoid, character :: Model)
	liftForMount(humanoid, character :: Model)

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

	-- Death or respawn always ends any ride locally (pose, input, movement); the server then sends
	-- the new state.
	local function watchCharacter(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				if player.Character == character then
					stopRiding()
				end
			end)
		end
	end
	player.CharacterAdded:Connect(function(character)
		stopRiding()
		watchCharacter(character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	local ok, payload = pcall(function()
		return Remotes.Function("GetRunState"):InvokeServer()
	end)
	if ok and payload then
		applyState(payload)
	end
end

return RideController
