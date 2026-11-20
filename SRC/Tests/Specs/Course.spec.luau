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
