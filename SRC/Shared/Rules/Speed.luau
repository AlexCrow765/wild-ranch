--!strict
--[[
	Speed
	Mount riding speed in studs per second (designer decision 2026-11-18).
	- Speed = Base Speed x Variant x (1 + 0.1% x (Level - 1))   (see LevelScaling)
	- Each species has its own base speed; stars do not change speed.
	- Speed is a small secondary leveling benefit; stamina is the main one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MountConfig = require(Config:WaitForChild("MountConfig"))
local SpeciesConfig = require(Config:WaitForChild("SpeciesConfig"))
local Rarity = require(script.Parent:WaitForChild("Rarity"))
local LevelScaling = require(script.Parent:WaitForChild("LevelScaling"))

local Speed = {}

-- The formula itself, with every input supplied.
function Speed.Max(baseSpeed: number, variantMultiplier: number, level: number): number
	return LevelScaling.Apply("baseSpeed", baseSpeed, variantMultiplier, level, MountConfig.SpeedGrowthPerLevel)
end

-- Riding speed for a saved animal used as a mount, looking values up from Config.
function Speed.ForAnimal(animal: { Species: string, Variant: string, Level: number }): number
	local species = SpeciesConfig.Species[animal.Species]
	assert(species ~= nil, `unknown species "{animal.Species}"`)
	assert(species.BaseSpeed ~= nil, `OPEN QUESTION: no BaseSpeed set for species "{animal.Species}"`)
	return Speed.Max(species.BaseSpeed :: number, Rarity.VariantStatMultiplier(animal.Variant), animal.Level)
end

return Speed
