--!strict
--[[
	RunSessionService
	Server-authoritative run state for every player.

	States:
	  Ranch        at the placeholder ranch hub (spawn point)
	  StartingArea in a biome's starting area; walking freely; Return to Ranch allowed
	  Riding       crossed the starting line; auto-forward; stamina drains by forward progress
	  Collapsed    stamina reached 0 (or end of course); frozen, message shown, then back to Ranch

	The server:
	  - starts a run when the character crosses the starting line inside the corridor,
	  - accepts forward progress only as fast as the mount could travel (RunProgress),
	    pulling the rider back if they get far ahead of what is allowed,
	  - keeps riders inside the playable corridor,
	  - computes stamina and ends the run at 0.
	The client only steers its own character (RideController).

	State transitions go through Shared/Rules/RunSessionState, which changes state, biome and
	run together and bumps the session Token, so a session can never be Riding without a run
	and stale delayed callbacks are ignored. A respawn or death always returns to Ranch at once.

	Phase 3 uses the temporary test mount (MountConfig.TestMountStamina at the baseline speed).
	Phase 4 adds the run plan (seeded encounters) at run start.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Rules = Shared:WaitForChild("Rules")
local CourseConfig = require(Config:WaitForChild("CourseConfig"))
local MountConfig = require(Config:WaitForChild("MountConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local CourseLayout = require(Rules:WaitForChild("CourseLayout"))
local RunProgress = require(Rules:WaitForChild("RunProgress"))
local RunSessionState = require(Rules:WaitForChild("RunSessionState"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local WorldService = require(script.Parent:WaitForChild("WorldService"))

export type State = RunSessionState.State
type Session = RunSessionState.Session

local DEBUG_MAX_SPEED = 500 -- studs/s; sanity limit for the debug override

local STATS_INTERVAL = 0.1
local MOUNT_NAME = "TestMount"

local RunSessionService = {
	LoadOrder = 30,
}

local sessions: { [Player]: Session } = {}
local runStateRemote: RemoteEvent
local runStatsRemote: UnreliableRemoteEvent

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function statePayload(session: Session): { [string]: any }
	local payload: { [string]: any } = { State = session.State, Biome = session.Biome }
	if session.State == "Riding" and session.Biome then
		local origin = WorldService.GetCourseOrigin(session.Biome) :: CFrame
		local run = session.Run :: RunProgress.Run
		payload.Forward = origin.LookVector
		payload.Right = origin.RightVector
		payload.Origin = origin
		payload.Speed = run.Speed
		payload.SteerSpeed = CourseConfig.SteerSpeed
		payload.MaxStamina = run.MaxStamina
		payload.ReachDistance = RunProgress.ReachDistance(run)
	end
	return payload
end

-- Sends the session's current state to its client (after a RunSessionState transition).
local function notify(player: Player, session: Session, extra: { [string]: any }?)
	local payload = statePayload(session)
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	runStateRemote:FireClient(player, payload)
end

local function removeMountFrom(character: Instance?)
	local mount = character and character:FindFirstChild(MOUNT_NAME)
	if mount then
		mount:Destroy()
	end
end

local function removeMount(player: Player)
	removeMountFrom(player.Character)
end

-- Grey-box test mount: a plain block welded under the rider. No collision, no mass.
local function attachMount(player: Player, root: BasePart)
	removeMount(player)
	local mount = Instance.new("Part")
	mount.Name = MOUNT_NAME
	mount.Size = Vector3.new(4, 3, 7)
	mount.Color = Color3.fromRGB(140, 100, 60)
	mount.Material = Enum.Material.SmoothPlastic
	mount.CanCollide = false
	mount.CanQuery = false
	mount.CanTouch = false
	mount.Massless = true
	mount.CFrame = root.CFrame * CFrame.new(0, -2.5, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = mount
	weld.Parent = mount
	mount.Parent = player.Character
end

local function teleport(root: BasePart, target: CFrame)
	local character = root.Parent
	if character and character:IsA("Model") then
		character:PivotTo(target)
	end
end

local function sendToRanch(player: Player, session: Session)
	local root = getRoot(player)
	removeMount(player)
	if root then
		root.Anchored = false
		teleport(root, WorldService.GetHubSpawn())
	end
	RunSessionState.ToRanch(session)
	notify(player, session)
end

local function startRun(player: Player, session: Session)
	local root = getRoot(player)
	if root == nil then
		return
	end
	-- Phase 3: temporary test mount (removed when Phase 8 mount selection lands).
	local speed = session.DebugSpeed or CourseConfig.BaselineRidingSpeed
	local run = RunProgress.new(MountConfig.TestMountStamina, MountConfig.StaminaPerStud, speed)
	RunSessionState.ToRiding(session, run)
	attachMount(player, root)
	notify(player, session)
	print(`[RunSession] {player.Name} started a {session.Biome} run (reach ≈ {math.floor(RunProgress.ReachDistance(run))} studs)`)
end

local function collapse(player: Player, session: Session, reason: string)
	local run = session.Run :: RunProgress.Run
	local root = getRoot(player)
	if root then
		root.Anchored = true -- frozen while the message shows
	end
	local message = if reason == "OutOfStamina"
		then CourseConfig.CollapseMessage
		else "End of the course (the next biome arrives in a later phase)"
	RunSessionState.ToCollapsed(session)
	notify(player, session, {
		Reason = reason,
		Message = message,
		Seconds = CourseConfig.CollapseMessageSeconds,
		Distance = run.Progress,
	})
	print(
		`[RunSession] {player.Name} run ended ({reason}) at {string.format("%.1f", run.Progress)} studs, segment {CourseLayout.SegmentAt(run.Progress)}, rejected samples: {run.Violations}`
	)

	local token = session.Token
	task.delay(CourseConfig.CollapseMessageSeconds, function()
		if sessions[player] == session and RunSessionState.IsCurrent(session, token) and session.State == "Collapsed" then
			sendToRanch(player, session)
		end
	end)
end

local function updateStartingArea(player: Player, session: Session)
	local root = getRoot(player)
	local origin = session.Biome and WorldService.GetCourseOrigin(session.Biome)
	if root == nil or origin == nil then
		return
	end
	local distance, lateral = CourseLayout.ToCourseSpace(origin, root.Position)
	local maxLateral = CourseLayout.PlayableHalfWidth() + CourseConfig.Validation.LateralToleranceStuds
	if distance >= 0 and math.abs(lateral) <= maxLateral then
		startRun(player, session)
	end
end

local function updateRiding(player: Player, session: Session, dt: number)
	local run = session.Run :: RunProgress.Run
	local root = getRoot(player)
	local origin = WorldService.GetCourseOrigin(session.Biome :: string)
	if root == nil or origin == nil then
		return
	end

	local distance, lateral = CourseLayout.ToCourseSpace(origin, root.Position)
	local accepted = RunProgress.Step(run, distance, dt)

	-- Keep the rider within what the server accepted and inside the playable corridor.
	local playHalf = CourseLayout.PlayableHalfWidth()
	local tooFar = distance > accepted + CourseConfig.Validation.PullBackStuds
	local outside = math.abs(lateral) > playHalf + CourseConfig.Validation.LateralToleranceStuds
	if tooFar or outside then
		local height = (root.Position - origin.Position):Dot(origin.UpVector)
		local fixedDistance = if tooFar then accepted else distance
		local fixedLateral = math.clamp(lateral, -playHalf, playHalf)
		local target = CourseLayout.ToWorld(origin, fixedDistance, fixedLateral, height)
		root.CFrame = root.CFrame + (target - root.Position)
		warn(`[RunSession] Corrected {player.Name} ({if tooFar then "too far ahead" else "outside corridor"})`)
	end

	session.StatsTimer += dt
	if session.StatsTimer >= STATS_INTERVAL then
		session.StatsTimer = 0
		runStatsRemote:FireClient(player, { Stamina = run.Stamina, Progress = run.Progress })
	end

	if RunProgress.IsExhausted(run) then
		runStatsRemote:FireClient(player, { Stamina = 0, Progress = run.Progress })
		collapse(player, session, "OutOfStamina")
	elseif CourseLayout.IsPastEnd(run.Progress) then
		collapse(player, session, "EndOfCourse")
	end
end

local function onTravelRequest(player: Player, biomeId: any)
	local session = sessions[player]
	if session == nil or session.State ~= "Ranch" or typeof(biomeId) ~= "string" then
		return
	end
	local biome = BiomeConfig.Biomes[biomeId]
	-- Only Level 1 is unlocked until biome progression (Phase 9); the course must exist.
	if biome == nil or biome.Level ~= 1 or not WorldService.HasCourse(biomeId) then
		return
	end
	local root = getRoot(player)
	local spawn = WorldService.GetStartingAreaSpawn(biomeId)
	if root == nil or spawn == nil then
		return
	end
	teleport(root, spawn)
	RunSessionState.ToStartingArea(session, biomeId)
	notify(player, session)
end

local function onReturnRequest(player: Player)
	local session = sessions[player]
	-- Design notes 2.B: Return to Ranch only from a starting area, never during a run.
	if session == nil or session.State ~= "StartingArea" then
		if session then
			runStateRemote:FireClient(player, statePayload(session)) -- resync the client's buttons
		end
		return
	end
	sendToRanch(player, session)
end

-- Ends any run immediately (respawn, death): back to Ranch, delayed callbacks invalidated,
-- client told at once. Removes a leftover test mount from the given character if any.
local function resetToRanch(player: Player, session: Session, character: Instance?)
	removeMountFrom(character)
	if session.State ~= "Ranch" or not RunSessionState.IsValid(session) then
		RunSessionState.ToRanch(session)
	end
	notify(player, session)
end

local function onCharacterAdded(player: Player, character: Model)
	local session = sessions[player]
	if session == nil then
		return
	end
	-- Immediately: never leave the session Riding/Collapsed for a character that no longer exists.
	resetToRanch(player, session, character)
	local token = session.Token

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			if sessions[player] == session and player.Character == character and session.State ~= "Ranch" then
				resetToRanch(player, session, character)
			end
		end)
	end

	-- Then: put the new character at the ranch hub once its root part exists (also covers the
	-- very first spawn), unless something else has changed the session in the meantime.
	task.defer(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if
			root
			and root:IsA("BasePart")
			and sessions[player] == session
			and player.Character == character
			and RunSessionState.IsCurrent(session, token)
		then
			teleport(root, WorldService.GetHubSpawn())
		end
	end)
end

-- Current state name, for other services and debug.
function RunSessionService.GetState(player: Player): State?
	local session = sessions[player]
	return if session then session.State else nil
end

function RunSessionService.DebugInfo(): string
	local lines = {}
	for player, session in sessions do
		local line = `{player.Name}: {session.State}`
		if session.Biome then
			line ..= ` in {session.Biome}`
		end
		if session.DebugSpeed then
			line ..= ` [debug speed {session.DebugSpeed} studs/s]`
		end
		local run = session.Run
		if run then
			line ..= string.format(
				", progress %.1f studs (segment %d), stamina %.2f / %d, rejected samples %d",
				run.Progress,
				CourseLayout.SegmentAt(run.Progress),
				run.Stamina,
				run.MaxStamina,
				run.Violations
			)
		end
		table.insert(lines, line)
	end
	return if #lines > 0 then table.concat(lines, "\n") else "no players"
end

-- Studio debug: override a player's riding speed (nil = back to the approved baseline).
-- Applies to the current ride immediately and to later rides. Stamina still drains by
-- distance, so the mount collapses at the same distance, just sooner.
function RunSessionService.DebugSetSpeed(player: Player, speed: number?): (boolean, string?)
	local session = sessions[player]
	if session == nil then
		return false, "no session for player"
	end
	if speed ~= nil and (speed ~= speed or speed <= 0 or speed > DEBUG_MAX_SPEED) then
		return false, `speed must be between 0 and {DEBUG_MAX_SPEED} studs/s`
	end
	session.DebugSpeed = speed
	local run = session.Run
	if session.State == "Riding" and run then
		run.Speed = speed or CourseConfig.BaselineRidingSpeed
		-- The speed cap grows with time from now on; keep it consistent with distance so far.
		run.Elapsed = math.max(run.Elapsed, run.Progress / run.Speed)
		notify(player, session) -- resend the riding payload with the new speed
	end
	return true
end

-- Studio debug: move a riding player to a forward distance (stamina is recalculated).
function RunSessionService.DebugSetProgress(player: Player, distance: number): (boolean, string?)
	local session = sessions[player]
	if session == nil or session.State ~= "Riding" or session.Run == nil then
		return false, "player is not riding"
	end
	local root = getRoot(player)
	local origin = WorldService.GetCourseOrigin(session.Biome :: string)
	if root == nil or origin == nil then
		return false, "no character"
	end
	local clamped = math.clamp(distance, 0, CourseConfig.BiomeLengthStuds - 1)
	RunProgress.SetProgress(session.Run :: RunProgress.Run, clamped)
	local _, lateral = CourseLayout.ToCourseSpace(origin, root.Position)
	root.CFrame = CFrame.lookAt(CourseLayout.ToWorld(origin, clamped, lateral, 3), CourseLayout.ToWorld(origin, clamped + 1, lateral, 3))
	return true
end

function RunSessionService:Init()
	runStateRemote = Remotes.Event("RunState")
	runStatsRemote = Remotes.UnreliableEvent("RunStats")

	Remotes.Event("RequestTravelToBiome").OnServerEvent:Connect(onTravelRequest)
	Remotes.Event("RequestReturnToRanch").OnServerEvent:Connect(onReturnRequest)
	Remotes.Function("GetRunState").OnServerInvoke = function(player: Player)
		local session = sessions[player]
		return if session then statePayload(session) else nil
	end
end

function RunSessionService:Start()
	PlayerService.OnPlayerAdded(function(player: Player)
		local session = RunSessionState.new()
		sessions[player] = session
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end)
	PlayerService.OnPlayerRemoving(function(player: Player)
		sessions[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		for player, session in sessions do
			if player.Parent ~= Players then
				continue
			end
			-- Defensive: a session that breaks its invariant is recovered, never processed.
			local valid, reason = RunSessionState.IsValid(session)
			if not valid then
				warn(`[RunSession] {player.Name} session invalid ({reason}); returning to ranch`)
				resetToRanch(player, session, player.Character)
				continue
			end
			if session.State == "StartingArea" then
				updateStartingArea(player, session)
			elseif session.State == "Riding" then
				updateRiding(player, session, dt)
			end
		end
	end)
end

return RunSessionService
