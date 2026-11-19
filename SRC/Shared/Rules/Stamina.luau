--!strict
--[[
	Stamina (design doc section 2.F)
	- Stamina decides how far a mount can travel; it drains by DISTANCE, not time.
	- Gold/Rainbow multiply the species' base stamina.
	- Each mount level above StartingLevel adds a fixed amount (not multiplied by variant).
	- Star rating does not change stamina directly; it only raises the max level.

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
function Stamina.Max(baseStamina: number, variantMultiplier: number, level: number, staminaPerLevel: number): number
	checkFinite(baseStamina, "baseStamina")
	assert(baseStamina >= 0, `baseStamina must not be negative, got {baseStamina}`)
	checkFinite(variantMultiplier, "variantMultiplier")
	assert(variantMultiplier > 0, `variantMultiplier must be greater than 0, got {variantMultiplier}`)
	checkFinite(staminaPerLevel, "staminaPerLevel")
	assert(staminaPerLevel >= 0, `staminaPerLevel must not be negative, got {staminaPerLevel}`)
	assert(
		Validate.IsInteger(level) and level >= MountConfig.StartingLevel,
		`level must be a whole number of at least {MountConfig.StartingLevel}, got {tostring(level)}`
	)
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
