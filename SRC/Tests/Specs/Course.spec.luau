--!strict
-- Phase 3: course geometry and server-side run progress (forward progress only drains stamina).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = Shared:WaitForChild("Rules")
local Config = Shared:WaitForChild("Config")
local CourseLayout = require(Rules:WaitForChild("CourseLayout"))
local RunProgress = require(Rules:WaitForChild("RunProgress"))
local CourseConfig = require(Config:WaitForChild("CourseConfig"))
local MountConfig = require(Config:WaitForChild("MountConfig"))

local EPS = 1e-6
-- Roblox stores CFrame/Vector3 components as 32-bit floats (~7 significant digits),
-- so world-space round trips are only exact to about 1e-5 studs at these distances.
local WORLD_EPS = 1e-3

local function newTestRun()
	return RunProgress.new(MountConfig.TestMountStamina, MountConfig.StaminaPerStud, CourseConfig.BaselineRidingSpeed)
end

-- Rides forward at exactly the mount speed, sampling like the server Heartbeat.
local function rideTo(run: RunProgress.Run, distance: number, dt: number)
	local position = run.Progress
	while position < distance do
		position = math.min(distance, position + run.Speed * dt)
		RunProgress.Step(run, position, dt)
	end
end

return function(t)
	t.test("approved Phase 3 values are in config", function()
		t.eq(CourseConfig.SteerSpeed, 16, "steer speed (provisional)")
		t.eq(CourseConfig.CollapseMessage, "Out of stamina")
		t.eq(CourseConfig.CollapseMessageSeconds, 3)
		t.eq(CourseConfig.StartingFloorSize, Vector3.new(250, 1, 100), "starting floor 250 x 1 x 100")
	end)

	t.test("segment boundaries every 576 studs up to 2,880", function()
		for segment = 1, 5 do
			t.eq(CourseLayout.SegmentStart(segment), (segment - 1) * 576, `start of segment {segment}`)
			t.eq(CourseLayout.SegmentEnd(segment), segment * 576, `end of segment {segment}`)
		end
		t.eq(CourseLayout.SegmentEnd(5), CourseConfig.BiomeLengthStuds)
		t.errors(function()
			CourseLayout.SegmentStart(6)
		end)
	end)

	t.test("distance maps to the right zone", function()
		t.eq(CourseLayout.SegmentAt(-10), 0, "starting area")
		t.eq(CourseLayout.SegmentAt(0), 1)
		t.eq(CourseLayout.SegmentAt(575.9), 1)
		t.eq(CourseLayout.SegmentAt(576), 2)
		t.eq(CourseLayout.SegmentAt(864), 2, "test mount reach is in segment 2")
		t.eq(CourseLayout.SegmentAt(2879), 5)
		t.eq(CourseLayout.SegmentAt(5000), 5, "past the end counts as the last segment")
		t.truthy(CourseLayout.IsPastEnd(2880))
		t.eq(CourseLayout.IsPastEnd(2879.9), false)
	end)

	t.test("playable centre is 74 studs (37 each side of the centre line)", function()
		t.eq(CourseLayout.PlayableHalfWidth(), 37)
		t.eq(CourseLayout.CorridorHalfWidth(), 50)
	end)

	t.test("course space round-trips for a rotated, offset course", function()
		local origin = CFrame.new(10, 5, -30) * CFrame.Angles(0, math.rad(37), 0)
		local world = CourseLayout.ToWorld(origin, 123.5, -20, 3)
		local distance, lateral = CourseLayout.ToCourseSpace(origin, world)
		t.near(distance, 123.5, WORLD_EPS, "distance")
		t.near(lateral, -20, WORLD_EPS, "lateral")
	end)

	t.test("course origin is the centre of the floor's front edge, on top", function()
		local floorCFrame = CFrame.new(0, 0.5, 0)
		local origin = CourseLayout.OriginFromFloor(floorCFrame, Vector3.new(250, 1, 100))
		t.near((origin.Position - Vector3.new(0, 1, -50)).Magnitude, 0, WORLD_EPS, "position")
		t.near(origin.LookVector:Dot(Vector3.new(0, 0, -1)), 1, WORLD_EPS, "faces the floor's LookVector")
	end)

	t.test("standing still or moving sideways does not drain stamina", function()
		local run = newTestRun()
		for _ = 1, 100 do
			RunProgress.Step(run, 0, 1 / 60) -- no forward movement (sideways is not part of distance)
		end
		t.eq(run.Stamina, MountConfig.TestMountStamina)
		t.eq(run.Progress, 0)
	end)

	t.test("progress never goes backwards", function()
		local run = newTestRun()
		rideTo(run, 100, 1 / 60)
		local before = run.Stamina
		RunProgress.Step(run, 40, 1 / 60)
		t.near(run.Progress, 100, EPS)
		t.eq(run.Stamina, before, "moving back does not refund stamina")
	end)

	t.test("stamina drains by forward distance: half at 432 studs, empty at ~864", function()
		local run = newTestRun()
		rideTo(run, 432, 1 / 60)
		t.near(run.Stamina, 50, 1e-6, "half stamina at 432 studs")
		t.eq(RunProgress.IsExhausted(run), false)
		rideTo(run, 864, 1 / 60)
		t.near(run.Stamina, 0, 1e-6)
		t.truthy(RunProgress.IsExhausted(run), "exhausted at 864 studs")
		t.near(RunProgress.ReachDistance(run), 864, 1e-6)
	end)

	t.test("a normal ride at mount speed is never rejected", function()
		local run = newTestRun()
		rideTo(run, 800, 1 / 60)
		t.eq(run.Violations, 0)
	end)

	t.test("bursty network updates at legal speed are accepted (no false rejections)", function()
		local run = newTestRun()
		rideTo(run, 100, 1 / 60)
		-- No position update for half a second, then the rider's real position arrives at once.
		for _ = 1, 30 do
			RunProgress.Step(run, run.Progress, 1 / 60)
		end
		local _, rejected = RunProgress.Step(run, 100 + 32 * 0.5, 1 / 60)
		t.eq(rejected, false, "a 16-stud catch-up after a 0.5 s gap is legal")
		t.eq(run.Violations, 0)
	end)

	t.test("moving faster than the mount allows is rejected and capped", function()
		local run = newTestRun()
		rideTo(run, 100, 1 / 60)
		local limit = RunProgress.MaxAccepted(run, 0.1)
		local accepted, rejected = RunProgress.Step(run, 500, 0.1) -- teleport attempt
		t.truthy(rejected, "rejected")
		t.near(accepted, limit, EPS, "capped at the allowed distance")
		t.eq(run.Violations, 1)
		t.truthy(run.Stamina > 0, "stamina reflects only the accepted distance")
	end)

	-- ===== Speed validation: speed x (elapsed + LeadAllowanceSeconds) (designer approved) =====

	-- Rides for `seconds` at `factor` x the mount speed, sampling at 60 Hz.
	-- Returns the run and the time of the first rejected sample (or nil).
	local function rideAtFactor(speed: number, factor: number, seconds: number): (RunProgress.Run, number?)
		local run = RunProgress.new(MountConfig.TestMountStamina, MountConfig.StaminaPerStud, speed)
		local dt = 1 / 60
		local firstRejection: number? = nil
		local position = 0
		local time = 0
		while time < seconds - 1e-9 do
			time += dt
			position += speed * factor * dt
			local _, rejected = RunProgress.Step(run, position, dt)
			if rejected and firstRejection == nil then
				firstRejection = time
			end
		end
		return run, firstRejection
	end

	local function allowanceStuds(speed: number): number
		return speed * CourseConfig.Validation.LeadAllowanceSeconds
	end

	t.test("validation config: 0.25 s lead allowance, old multiplier and slack removed, pull-back unchanged", function()
		local validation = CourseConfig.Validation :: any
		t.eq(validation.LeadAllowanceSeconds, 0.25)
		t.eq(validation.SpeedTolerance, nil, "SpeedTolerance removed")
		t.eq(validation.SlackStuds, nil, "SlackStuds removed")
		t.eq(validation.PullBackStuds, 20, "pull-back threshold unchanged")
	end)

	t.test("accepted limit = speed x (elapsed + 0.25 s)", function()
		local run = newTestRun()
		t.near(RunProgress.MaxAccepted(run, 0), 32 * 0.25, 1e-9, "8 studs at the start")
		rideTo(run, 320, 1 / 60) -- 10 s of perfect riding
		t.near(RunProgress.MaxAccepted(run, 0), 32 * (run.Elapsed + 0.25), 1e-9)
	end)

	t.test("legitimate riders pass at the normal and the boosted test speed", function()
		for _, speed in { CourseConfig.BaselineRidingSpeed, 120 } do
			local run, firstRejection = rideAtFactor(speed, 1, 864 / speed)
			t.eq(firstRejection, nil, `no rejection at {speed} studs/s`)
			t.eq(run.Violations, 0)
			t.truthy(run.Progress >= 863, `reached ~864 studs at {speed} studs/s (got {run.Progress})`)
		end
	end)

	t.test("bursty network movement passes: a 2 s freeze then catching up to the true position", function()
		local run = newTestRun()
		rideTo(run, 200, 1 / 60)
		local truePosition = run.Progress
		for _ = 1, 120 do -- no position updates for 2 s while the rider keeps going
			truePosition += run.Speed / 60
			RunProgress.Step(run, run.Progress, 1 / 60)
		end
		local _, rejected = RunProgress.Step(run, truePosition, 1 / 60)
		t.eq(rejected, false, "64-stud catch-up after a 2 s gap is legal")
		t.eq(run.Violations, 0)
	end)

	t.test("bursty network movement passes: positions arriving 0-300 ms late in random bursts", function()
		local run = newTestRun()
		local rng = Random.new(2026)
		local dt = 1 / 60
		local time = 0
		local reported = 0
		for _ = 1, 60 * 20 do -- 20 s
			time += dt
			if rng:NextNumber() < 0.3 then -- an update arrives on ~30% of frames
				local delay = rng:NextNumber() * 0.3
				reported = math.max(reported, run.Speed * math.max(0, time - delay))
			end
			RunProgress.Step(run, reported, dt)
		end
		t.eq(run.Violations, 0, "late, bursty positions never exceed the limit")
	end)

	t.test("a constant 25% speed exploit is rejected within ~1 s and held to the allowance", function()
		local run, firstRejection = rideAtFactor(32, 1.25, 10)
		t.truthy(firstRejection ~= nil and (firstRejection :: number) <= 1.05, `first rejection at {tostring(firstRejection)} s`)
		t.truthy(run.Violations > 0)
		t.truthy(run.Progress <= 32 * run.Elapsed + allowanceStuds(32) + 1e-6, "accepted never beyond a legit rider + 8 studs")
	end)

	t.test("a constant 10% speed exploit is rejected within ~2.5 s and held to the allowance", function()
		local run, firstRejection = rideAtFactor(32, 1.10, 10)
		t.truthy(firstRejection ~= nil and (firstRejection :: number) <= 2.55, `first rejection at {tostring(firstRejection)} s`)
		t.truthy(run.Violations > 0)
		t.truthy(run.Progress <= 32 * run.Elapsed + allowanceStuds(32) + 1e-6, "accepted never beyond a legit rider + 8 studs")
	end)

	t.test("saving up headroom (riding slow) then jumping forward cannot bypass validation", function()
		local run = newTestRun()
		local dt = 1 / 60
		local position = 0
		for _ = 1, 60 * 30 do -- 30 s at half speed: 480 studs "saved up" versus a legit rider
			position += 16 * dt
			RunProgress.Step(run, position, dt)
		end
		local legitPosition = 32 * run.Elapsed
		local accepted, rejected = RunProgress.Step(run, legitPosition + 400, dt) -- teleport attempt
		t.truthy(rejected, "the jump is rejected")
		t.truthy(accepted <= 32 * run.Elapsed + allowanceStuds(32) + 1e-6, "capped at a legit rider + 8 studs")
	end)

	t.test("lead measurement: a perfect rider has ~0 lead", function()
		local run = newTestRun()
		rideTo(run, 500, 1 / 60)
		t.near(run.MaxLeadStuds, 0, 1e-6, "studs")
		t.near(run.MaxLeadSeconds, 0, 1e-6, "seconds")
		t.eq(run.DebugMoved, false)
	end)

	t.test("lead measurement records the largest lead ahead of speed x time, in studs and seconds", function()
		local run = newTestRun()
		rideTo(run, 100, 1 / 60)
		local expected = run.Speed * (run.Elapsed + 0.1)
		RunProgress.Step(run, expected + 4, 0.1) -- 4 studs ahead of a perfect rider
		t.near(run.MaxLeadStuds, 4, 1e-6, "studs")
		t.near(run.MaxLeadSeconds, 4 / run.Speed, 1e-9, "seconds = studs / speed")
		RunProgress.Step(run, run.Speed * (run.Elapsed + 0.1) + 1, 0.1) -- smaller lead later
		t.near(run.MaxLeadStuds, 4, 1e-6, "keeps the maximum")
	end)

	t.test("lead measurement does not change what the server accepts", function()
		local measured = newTestRun()
		local reference = newTestRun()
		for i = 1, 300 do
			local observed = i * 0.6 -- slightly faster than 32 studs/s at 60 Hz
			RunProgress.Step(measured, observed, 1 / 60)
			RunProgress.Step(reference, observed, 1 / 60)
		end
		t.eq(measured.Progress, reference.Progress)
		t.eq(measured.Violations, reference.Violations)
		t.truthy(measured.MaxLeadStuds > 0, "the faster-than-allowed-speed lead is recorded")
	end)

	t.test("debug teleports mark the run so its lead data is excluded", function()
		local run = newTestRun()
		RunProgress.SetProgress(run, 400)
		t.truthy(run.DebugMoved)
	end)

	t.test("debug SetProgress moves directly and recalculates stamina", function()
		local run = newTestRun()
		RunProgress.SetProgress(run, 864)
		t.truthy(RunProgress.IsExhausted(run))
		t.errors(function()
			RunProgress.SetProgress(run, -1)
		end)
	end)

	t.test("invalid run inputs are rejected", function()
		t.errors(function()
			RunProgress.new(0, MountConfig.StaminaPerStud, 32)
		end, "maxStamina")
		t.errors(function()
			RunProgress.new(100, 0, 32)
		end, "staminaPerStud")
		t.errors(function()
			RunProgress.new(100, MountConfig.StaminaPerStud, 0)
		end, "speed")
		local run = newTestRun()
		t.errors(function()
			RunProgress.Step(run, 0 / 0, 0.1)
		end, "observedDistance")
		t.errors(function()
			RunProgress.Step(run, 10, -1)
		end, "dt")
	end)
end
