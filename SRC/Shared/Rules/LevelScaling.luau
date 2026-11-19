--!strict
--[[
	LevelScaling
	Shared formula for mount stats that grow with level (designer decision 2026-11-18):

	  Stat = Base x Variant x (1 + GrowthPerLevel x (Level - StartingLevel))

	The bonus is a percentage of the variant-adjusted base, added per level, never compounded.
	Used by Stamina (1% per level) and Speed (0.1% per level).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MountConfig = require(Shared:WaitForChild("Config"):WaitForChild("MountConfig"))
local Validate = require(Shared:WaitForChild("Util"):WaitForChild("Validate"))

local LevelScaling = {}

function LevelScaling.Apply(statName: string, base: number, variantMultiplier: number, level: number, growthPerLevel: number): number
	assert(
		Validate.IsFiniteNumber(base) and base >= 0,
		`base {statName} must be a finite number >= 0, got {tostring(base)}`
	)
	assert(
		Validate.IsFiniteNumber(variantMultiplier) and variantMultiplier > 0,
		`variantMultiplier must be a finite number > 0, got {tostring(variantMultiplier)}`
	)
	assert(
		Validate.IsFiniteNumber(growthPerLevel) and growthPerLevel >= 0,
		`{statName} growth per level must be a finite number >= 0, got {tostring(growthPerLevel)}`
	)
	assert(
		Validate.IsInteger(level) and level >= MountConfig.StartingLevel,
		`level must be a whole number of at least {MountConfig.StartingLevel}, got {tostring(level)}`
	)
	return base * variantMultiplier * (1 + growthPerLevel * (level - MountConfig.StartingLevel))
end

return LevelScaling
