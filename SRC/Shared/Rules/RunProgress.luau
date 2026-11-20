--!strict
--[[
	RunProgress
	Pure, server-authoritative bookkeeping for one ride.

	- Only FORWARD progress along the course consumes stamina (designer decision 2026-11-18);
	  sideways steering and turning cost nothing. Progress never goes backwards.
	- The observed distance is accepted only up to what the mount could have travelled since
	  the run started (speed x elapsed x tolerance + slack). Measuring from the run start (not
	  from the last sample) tolerates bursty network updates while still blocking speed hacks
	  and teleports. Anything beyond is rejected and counted.
	- Stamina left = max stamina - forward progress x stamina per stud.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseConfig = require(Shared:WaitForChild("Config"):WaitForChild("CourseConfig"))
local Validate = require(Shared:WaitForChild("Util"):WaitForChild("Validate"))
local Stamina = require(script.Parent:WaitForChild("Stamina"))

export type Run = {
	MaxStamina: number,
	StaminaPerStud: number,
	Speed: number, -- forward studs/s of the mount
	Progress: number, -- accepted forward distance from the starting line
	Stamina: number,
	Elapsed: number, -- seconds of riding counted so far
	Violations: number, -- samples where the rider was further than allowed
}

local RunProgress = {}

function RunProgress.new(maxStamina: number, staminaPerStud: number, speed: number): Run
	assert(Validate.IsFiniteNumber(maxStamina) and maxStamina > 0, "maxStamina must be > 0")
	assert(Validate.IsFiniteNumber(speed) and speed > 0, "speed must be > 0")
	Stamina.Cost(0, staminaPerStud) -- validates the rate
	return {
		MaxStamina = maxStamina,
		StaminaPerStud = staminaPerStud,
		Speed = speed,
		Progress = 0,
		Stamina = maxStamina,
		Elapsed = 0,
		Violations = 0,
	}
end

-- Furthest distance the run can accept after a further dt seconds of riding.
function RunProgress.MaxAccepted(run: Run, dt: number): number
	local tolerance = CourseConfig.Validation
	return run.Speed * (run.Elapsed + dt) * tolerance.SpeedTolerance + tolerance.SlackStuds
end

-- Applies one server sample. Returns (accepted progress, rejected: boolean).
function RunProgress.Step(run: Run, observedDistance: number, dt: number): (number, boolean)
	assert(Validate.IsFiniteNumber(observedDistance), "observedDistance must be finite")
	assert(Validate.IsFiniteNumber(dt) and dt >= 0, "dt must be a finite number >= 0")

	local target = observedDistance
	local rejected = false
	local limit = RunProgress.MaxAccepted(run, dt)
	run.Elapsed += dt
	if target > limit then
		target = limit
		rejected = true
		run.Violations += 1
	end
	if target > run.Progress then
		run.Progress = target
	end
	run.Stamina = math.max(0, run.MaxStamina - Stamina.Cost(run.Progress, run.StaminaPerStud))
	return run.Progress, rejected
end

-- Lets the server move a rider directly (debug teleport); bypasses the speed check on purpose.
function RunProgress.SetProgress(run: Run, distance: number)
	assert(Validate.IsFiniteNumber(distance) and distance >= 0, "distance must be a finite number >= 0")
	run.Progress = distance
	-- Count the time the mount would have needed, so the speed cap stays consistent afterwards.
	run.Elapsed = math.max(run.Elapsed, distance / run.Speed)
	run.Stamina = math.max(0, run.MaxStamina - Stamina.Cost(run.Progress, run.StaminaPerStud))
end

function RunProgress.IsExhausted(run: Run): boolean
	return run.Stamina <= 0
end

-- Where stamina runs out, in studs from the starting line.
function RunProgress.ReachDistance(run: Run): number
	return Stamina.MaxDistance(run.MaxStamina, run.StaminaPerStud)
end

return RunProgress
