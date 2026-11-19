--!strict
--[[
	TamingMeter (design doc section 2.G)
	Pure state for the directional QTE. The server runs the real one; the client may run a
	copy only to animate the bar.

	- Starts at 50%. No drain for the first 1.5 s, then drains continuously.
	- Drain/sec = star drain (3 for 0-2 stars, 5 for 3-5) + variant extra (Gold/Rainbow +10).
	- Correct input: +25, then the next prompt appears (mistake allowance resets).
	- Incorrect input: -15, but only one mistake counts per prompt.
	- 100% = tamed. 0% = thrown off. Nothing changes after a result.
	- Prompts are completely random Up/Down/Left/Right, one at a time, with no timer of their own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TamingConfig = require(Shared:WaitForChild("Config"):WaitForChild("TamingConfig"))
local Validate = require(Shared:WaitForChild("Util"):WaitForChild("Validate"))

export type Result = "Tamed" | "Failed"

export type State = {
	Percent: number,
	Elapsed: number,
	DrainPerSecond: number,
	MistakesThisPrompt: number,
	Result: Result?,
}

local TamingMeter = {}

function TamingMeter.DrainPerSecond(stars: number, variant: string): number
	local starDrain = TamingConfig.StarDrainPerSecond[stars]
	local variantDrain = (TamingConfig.VariantExtraDrainPerSecond :: any)[variant]
	assert(starDrain ~= nil, `no taming drain for {stars} stars`)
	assert(variantDrain ~= nil, `no taming drain for variant "{variant}"`)
	return starDrain + variantDrain
end

function TamingMeter.new(stars: number, variant: string): State
	return {
		Percent = TamingConfig.StartPercent,
		Elapsed = 0,
		DrainPerSecond = TamingMeter.DrainPerSecond(stars, variant),
		MistakesThisPrompt = 0,
		Result = nil,
	}
end

local function checkFail(state: State)
	if state.Percent <= TamingConfig.FailPercent then
		state.Percent = TamingConfig.FailPercent
		state.Result = "Failed"
	end
end

-- Moves time forward by dt seconds, draining only the part after the grace period.
function TamingMeter.Advance(state: State, dt: number)
	assert(Validate.IsFiniteNumber(dt), `dt must be a finite number, got {tostring(dt)}`)
	if state.Result ~= nil or dt <= 0 then
		return
	end
	local before = state.Elapsed
	local after = before + dt
	state.Elapsed = after

	local drainSeconds = math.max(0, after - math.max(before, TamingConfig.GracePeriodSeconds))
	if drainSeconds > 0 then
		state.Percent -= state.DrainPerSecond * drainSeconds
		checkFail(state)
	end
end

-- Applies one player input. Returns true if it changed the meter.
function TamingMeter.Input(state: State, correct: boolean): boolean
	if state.Result ~= nil then
		return false
	end

	if correct then
		state.Percent = math.min(TamingConfig.SuccessPercent, state.Percent + TamingConfig.CorrectInputGain)
		state.MistakesThisPrompt = 0 -- next prompt
		if state.Percent >= TamingConfig.SuccessPercent then
			state.Result = "Tamed"
		end
		return true
	end

	if state.MistakesThisPrompt >= TamingConfig.MaxCountedMistakesPerPrompt then
		return false -- repeated mistakes on the same prompt don't count
	end
	state.MistakesThisPrompt += 1
	state.Percent -= TamingConfig.IncorrectInputPenalty
	checkFail(state)
	return true
end

function TamingMeter.RollDirection(rng: Random): string
	local directions = TamingConfig.Directions
	return directions[rng:NextInteger(1, #directions)]
end

return TamingMeter
