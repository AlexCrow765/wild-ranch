--!strict
-- Run session state machine: respawn/death during a run, stale callbacks, invariants.
-- (Regression for review finding: a respawn must never leave a session Riding with no run.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = Shared:WaitForChild("Rules")
local Config = Shared:WaitForChild("Config")
local RunSessionState = require(Rules:WaitForChild("RunSessionState"))
local RunProgress = require(Rules:WaitForChild("RunProgress"))
local MountConfig = require(Config:WaitForChild("MountConfig"))
local CourseConfig = require(Config:WaitForChild("CourseConfig"))

local function newRun()
	return RunProgress.new(MountConfig.TestMountStamina, MountConfig.StaminaPerStud, CourseConfig.BaselineRidingSpeed)
end

local function ridingSession()
	local session = RunSessionState.new()
	RunSessionState.ToStartingArea(session, "Plains")
	RunSessionState.ToRiding(session, newRun())
	return session
end

return function(t)
	t.test("a new session is a valid Ranch session", function()
		local session = RunSessionState.new()
		t.eq(session.State, "Ranch")
		t.truthy(RunSessionState.IsValid(session))
	end)

	t.test("normal flow: Ranch -> StartingArea -> Riding -> Collapsed -> Ranch stays valid", function()
		local session = RunSessionState.new()
		RunSessionState.ToStartingArea(session, "Plains")
		t.truthy(RunSessionState.IsValid(session), "starting area")
		RunSessionState.ToRiding(session, newRun())
		t.truthy(RunSessionState.IsValid(session), "riding")
		RunSessionState.ToCollapsed(session)
		t.truthy(RunSessionState.IsValid(session), "collapsed")
		RunSessionState.ToRanch(session)
		t.truthy(RunSessionState.IsValid(session), "back at ranch")
		t.eq(session.Biome, nil)
		t.eq(session.Run, nil)
	end)

	t.test("respawn during an active run returns straight to Ranch with no run left behind", function()
		local session = ridingSession()
		RunSessionState.ToRanch(session) -- what onCharacterAdded / Humanoid.Died do
		t.eq(session.State, "Ranch")
		t.eq(session.Run, nil, "run cleared")
		t.eq(session.Biome, nil, "biome cleared")
		t.truthy(RunSessionState.IsValid(session))
	end)

	t.test("respawn invalidates delayed callbacks captured before it (Token)", function()
		local session = ridingSession()
		RunSessionState.ToCollapsed(session)
		local token = session.Token -- captured by the 3 s collapse timer
		RunSessionState.ToRanch(session) -- respawn before the timer fires
		t.eq(RunSessionState.IsCurrent(session, token), false, "stale timer must be ignored")
		RunSessionState.ToStartingArea(session, "Plains")
		RunSessionState.ToRiding(session, newRun())
		t.eq(RunSessionState.IsCurrent(session, token), false, "still stale after a new run starts")
	end)

	t.test("every transition increments the token", function()
		local session = RunSessionState.new()
		local last = session.Token
		local function step(fn: () -> ())
			fn()
			t.truthy(session.Token > last, "token increased")
			last = session.Token
		end
		step(function()
			RunSessionState.ToStartingArea(session, "Plains")
		end)
		step(function()
			RunSessionState.ToRiding(session, newRun())
		end)
		step(function()
			RunSessionState.ToCollapsed(session)
		end)
		step(function()
			RunSessionState.ToRanch(session)
		end)
	end)

	t.test("a session can never become Riding without a run", function()
		local session = RunSessionState.new()
		RunSessionState.ToStartingArea(session, "Plains")
		t.errors(function()
			RunSessionState.ToRiding(session, nil)
		end, "run is required")
		t.eq(session.State, "StartingArea", "unchanged after the rejected transition")
	end)

	t.test("illegal transitions are rejected", function()
		local session = RunSessionState.new()
		t.errors(function()
			RunSessionState.ToRiding(session, newRun())
		end, "cannot start a run from Ranch")
		t.errors(function()
			RunSessionState.ToCollapsed(session)
		end, "cannot collapse from Ranch")
		local riding = ridingSession()
		t.errors(function()
			RunSessionState.ToStartingArea(riding, "Plains")
		end, "cannot travel from Riding")
	end)

	t.test("IsValid detects a corrupted Riding session with a nil run (Heartbeat guard)", function()
		local session = ridingSession()
		session.Run = nil -- simulate the old bug
		local ok, reason = RunSessionState.IsValid(session)
		t.eq(ok, false)
		t.truthy(reason and string.find(reason, "Riding", 1, true), "reason mentions Riding")
		RunSessionState.ToRanch(session) -- the recovery path
		t.truthy(RunSessionState.IsValid(session))
	end)

	t.test("the debug speed override survives transitions", function()
		local session = ridingSession()
		session.DebugSpeed = 120
		RunSessionState.ToRanch(session)
		t.eq(session.DebugSpeed, 120)
	end)
end
