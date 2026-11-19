--!strict
--[[
	Stamina (design doc section 2.F)
	- Stamina decides how far a mount can travel; it drains by DISTANCE, not time.
	- Gold/Rainbow multiply the species' base stamina.
	- Each mount level above StartingLevel adds a fixed amount (not multiplied by variant).
	- Star rating does not change stamina directly; it only raises the max level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MountConfig = require(Config:WaitForChild("MountConfig"))
local SpeciesConfig = require(Config:WaitForChild("SpeciesConfig"))
local Rarity = require(script.Parent:WaitForChild("Rarity"))

local Stamina = {}

-- The formula itself, with every input supplied.
function Stamina.Max(baseStamina: number, variantMultiplier: number, level: number, staminaPerLevel: number): number
	assert(level >= MountConfig.StartingLevel, `level must be at least {MountConfig.StartingLevel}`)
	return baseStamina * variantMultiplier + (level - MountConfig.StartingLevel) * staminaPerLevel
end

-- Max stamina for a saved animal used as a mount, looking values up from Config.
function Stamina.ForAnimal(animal: { Species: string, Variant: string, Level: number }): number
	local species = SpeciesConfig.Species[animal.Species]
	assert(species ~= nil, `unknown species "{animal.Species}"`)
	assert(species.BaseStamina ~= nil, `OPEN QUESTION: no BaseStamina set for species "{animal.Species}"`)
	local perLevel = (MountConfig :: any).StaminaPerLevel
	assert(perLevel ~= nil, "OPEN QUESTION: MountConfig.StaminaPerLevel is not set")

	return Stamina.Max(species.BaseStamina :: number, Rarity.VariantStatMultiplier(animal.Variant), animal.Level, perLevel)
end

-- Stamina used to travel a distance (studs).
function Stamina.Cost(distance: number, staminaPerStud: number): number
	return math.max(0, distance) * staminaPerStud
end

-- Farthest distance (studs) a given amount of stamina can travel.
function Stamina.MaxDistance(stamina: number, staminaPerStud: number): number
	assert(staminaPerStud > 0, "staminaPerStud must be greater than 0")
	return math.max(0, stamina) / staminaPerStud
end

return Stamina
