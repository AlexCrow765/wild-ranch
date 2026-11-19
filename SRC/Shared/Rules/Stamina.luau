--!strict
--[[
	Stamina
	- Stamina decides how far a mount can travel; it drains by DISTANCE, not time.
	- Max stamina = Base Stamina x Variant x (1 + 1% x (Level - 1))   (see LevelScaling)
	- Stars do not change stamina; they only raise the max level.

	Every input is validated so a bad config value (0, negative, NaN, infinity) fails with a
	clear message instead of silently producing an endless or zero-length run.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MountConfig = require(Config:WaitForChild("MountConfig"))
local SpeciesConfig = require(Config:WaitForChild("SpeciesConfig"))
local Validate = require(Shared:WaitForChild("Util"):WaitForChild("Validate"))
local Rarity = require(script.Parent:WaitForChild("Rarity"))
local LevelScaling = require(script.Parent:WaitForChild("LevelScaling"))

local Stamina = {}

local function checkRate(staminaPerStud: any)
	assert(
		Validate.IsFiniteNumber(staminaPerStud) and staminaPerStud > 0,
		`staminaPerStud must be a finite number greater than 0, got {tostring(staminaPerStud)}`
	)
end

local function checkFinite(value: any, name: string)
	assert(Validate.IsFiniteNumber(value), `{name} must be a finite number, got {tostring(value)}`)
end

-- The formula itself, with every input supplied.
function Stamina.Max(baseStamina: number, variantMultiplier: number, level: number): number
	return LevelScaling.Apply("baseStamina", baseStamina, variantMultiplier, level, MountConfig.StaminaGrowthPerLevel)
end

-- Max stamina for a saved animal used as a mount, looking values up from Config.
function Stamina.ForAnimal(animal: { Species: string, Variant: string, Level: number }): number
	local species = SpeciesConfig.Species[animal.Species]
	assert(species ~= nil, `unknown species "{animal.Species}"`)
	assert(species.BaseStamina ~= nil, `OPEN QUESTION: no BaseStamina set for species "{animal.Species}"`)
	return Stamina.Max(species.BaseStamina :: number, Rarity.VariantStatMultiplier(animal.Variant), animal.Level)
end

-- Stamina used to travel a distance (studs). Negative distance costs nothing.
function Stamina.Cost(distance: number, staminaPerStud: number): number
	checkRate(staminaPerStud)
	checkFinite(distance, "distance")
	return math.max(0, distance) * staminaPerStud
end

-- Farthest distance (studs) a given amount of stamina can travel. Negative stamina travels 0.
function Stamina.MaxDistance(stamina: number, staminaPerStud: number): number
	checkRate(staminaPerStud)
	checkFinite(stamina, "stamina")
	return math.max(0, stamina) / staminaPerStud
end

return Stamina
