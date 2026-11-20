--!strict
--[[
	RunProgress
	Pure, server-authoritative bookkeeping for one ride.

	- Only FORWARD progress along the course consumes stamina (designer decision 2026-11-18);
	  sideways steering and turning cost nothing. Progress never goes backwards.
	- The observed distance is accepted only up to where a perfect rider could be, plus a small
	  fixed lead: speed x (elapsed + LeadAllowanceSeconds). Measuring from the run start (not
	  from the last sample) tolerates bursty network updates, because late positions only ever
	  put a legitimate rider behind that line. A rider can therefore never get more than the
	  allowance ahead of a legitimate rider: constant speed hacks are rejected within seconds and
	  "saving up" headroom by going slow gains nothing. Anything beyond is rejected and counted.
	- Phase 6 note: Elapsed must stop counting while the rider is stopped for taming.
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
	-- Measurement only (does not affect what is accepted): how far the observed position ran
	-- ahead of a perfect rider (Speed x Elapsed). Used to choose a fixed lead allowance.
	MaxLeadStuds: number,
	MaxLeadSeconds: number, -- MaxLeadStuds / Speed at the time, so it is independent of speed
	DebugMoved: boolean, -- true if a debug teleport/speed change touched this run (exclude from data)
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
		MaxLeadStuds = 0,
		MaxLeadSeconds = 0,
		DebugMoved = false,
	}
end

-- How far an observed distance is ahead of a perfect rider at the current elapsed time.
function RunProgress.Lead(run: Run, observedDistance: number): number
	return observedDistance - run.Speed * run.Elapsed
end

-- Furthest distance the run can accept after a further dt seconds of riding.
function RunProgress.MaxAccepted(run: Run, dt: number): number
	local tolerance = CourseConfig.Validation
	return run.Speed * (run.Elapsed + dt + tolerance.LeadAllowanceSeconds)
end

-- Applies one server sample. Returns (accepted progress, rejected: boolean).
function RunProgress.Step(run: Run, observedDistance: number, dt: number): (number, boolean)
	assert(Validate.IsFiniteNumber(observedDistance), "observedDistance must be finite")
	assert(Validate.IsFiniteNumber(dt) and dt >= 0, "dt must be a finite number >= 0")

	local target = observedDistance
	local rejected = false
	local limit = RunProgress.MaxAccepted(run, dt)
	run.Elapsed += dt

	-- Measurement only: record the largest lead over a perfect rider.
	local lead = RunProgress.Lead(run, observedDistance)
	if lead > run.MaxLeadStuds then
		run.MaxLeadStuds = lead
		run.MaxLeadSeconds = lead / run.Speed
	end

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
	run.DebugMoved = true
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
