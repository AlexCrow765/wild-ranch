--!strict
--[[
	Income (design doc section 2.H)
	Income/sec = species base income x variant stat multiplier x star income multiplier
	             x biome income multiplier (biome the animal was caught in)

	Only animals placed in the ranch earn; that check belongs to the ranch/income service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local SpeciesConfig = require(Config:WaitForChild("SpeciesConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local Rarity = require(script.Parent:WaitForChild("Rarity"))

local Income = {}

function Income.StarMultiplier(stars: number): number
	local multiplier = EconomyConfig.StarIncomeMultiplier[stars]
	assert(multiplier ~= nil, `no income multiplier for {stars} stars`)
	return multiplier
end

-- The formula itself, with every input supplied.
function Income.PerSecond(baseIncome: number, variantMultiplier: number, stars: number, biomeMultiplier: number): number
	return baseIncome * variantMultiplier * Income.StarMultiplier(stars) * biomeMultiplier
end

-- Income/sec for a saved animal, looking values up from Config.
function Income.ForAnimal(animal: { Species: string, Stars: number, Variant: string, BiomeCaught: string }): number
	local species = SpeciesConfig.Species[animal.Species]
	assert(species ~= nil, `unknown species "{animal.Species}"`)
	assert(species.BaseIncome ~= nil, `OPEN QUESTION: no BaseIncome set for species "{animal.Species}"`)

	local biome = BiomeConfig.Biomes[animal.BiomeCaught]
	assert(biome ~= nil, `unknown biome "{animal.BiomeCaught}"`)
	assert(biome.IncomeMultiplier ~= nil, `OPEN QUESTION: no IncomeMultiplier set for biome "{animal.BiomeCaught}"`)

	return Income.PerSecond(
		species.BaseIncome :: number,
		Rarity.VariantStatMultiplier(animal.Variant),
		animal.Stars,
		biome.IncomeMultiplier :: number
	)
end

return Income
