--!strict
--[[
	Animal
	The one data shape for an individual animal across its whole life:
	spawning -> taming -> inventory -> ranch -> mount.

	AnimalTraits  - rolled at the starting line, never re-rolled.
	OwnedAnimal   - saved record once captured. Stored in PlayerData.Animals under a
	                server-generated unique id (the id is the key, not a field).

	Derived values (income/sec, stamina, max level) are NOT stored; they are computed
	from these fields + Config, so tuning Config updates every animal consistently.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local SpeciesConfig = require(Config:WaitForChild("SpeciesConfig"))
local MountConfig = require(Config:WaitForChild("MountConfig"))

export type Variant = "Normal" | "Gold" | "Rainbow"

export type AnimalTraits = {
	Species: string,
	Stars: number, -- integer 0-5
	Variant: Variant,
	BiomeCaught: string, -- biome id; its income multiplier is looked up from BiomeConfig
}

export type OwnedAnimal = {
	Species: string,
	Stars: number,
	Variant: Variant,
	BiomeCaught: string,
	Level: number, -- mount level, StartingLevel..MaxLevelByStars[Stars]
	Placed: boolean, -- true = physically in the ranch (earning); false = in inventory
}

local Animal = {}

local function isInteger(value: any): boolean
	return typeof(value) == "number" and value == value and value % 1 == 0
end

-- Checks a set of traits against Config. Returns (true) or (false, reason).
function Animal.ValidateTraits(traits: any): (boolean, string?)
	if typeof(traits) ~= "table" then
		return false, "traits must be a table"
	end

	local species = SpeciesConfig.Species[traits.Species]
	if species == nil then
		return false, `unknown species "{tostring(traits.Species)}"`
	end

	if not isInteger(traits.Stars) or traits.Stars < RarityConfig.MinStars or traits.Stars > RarityConfig.MaxStars then
		return false, `invalid star rating "{tostring(traits.Stars)}"`
	end

	if typeof(traits.Variant) ~= "string" or RarityConfig.VariantOdds[traits.Variant] == nil then
		return false, `invalid variant "{tostring(traits.Variant)}"`
	end

	if typeof(traits.BiomeCaught) ~= "string" or BiomeConfig.Biomes[traits.BiomeCaught] == nil then
		return false, `unknown biome "{tostring(traits.BiomeCaught)}"`
	end

	-- Species are exclusive to the biome they are introduced in.
	if species.Biome ~= traits.BiomeCaught then
		return false, `{species.Id} belongs to {species.Biome}, not {traits.BiomeCaught}`
	end

	return true
end

function Animal.MaxLevel(stars: number): number
	local maxLevel = MountConfig.MaxLevelByStars[stars]
	assert(maxLevel ~= nil, `no max level configured for {stars} stars`)
	return maxLevel
end

-- Checks a saved record. Returns (true) or (false, reason).
function Animal.ValidateOwned(animal: any): (boolean, string?)
	local ok, reason = Animal.ValidateTraits(animal)
	if not ok then
		return false, reason
	end
	if not isInteger(animal.Level) or animal.Level < MountConfig.StartingLevel or animal.Level > Animal.MaxLevel(animal.Stars) then
		return false, `invalid level "{tostring(animal.Level)}"`
	end
	if typeof(animal.Placed) ~= "boolean" then
		return false, "Placed must be a boolean"
	end
	return true
end

-- Builds the saved record for a newly captured animal. Traits must already be valid.
function Animal.NewOwned(traits: AnimalTraits): OwnedAnimal
	return {
		Species = traits.Species,
		Stars = traits.Stars,
		Variant = traits.Variant,
		BiomeCaught = traits.BiomeCaught,
		Level = MountConfig.StartingLevel,
		Placed = false,
	}
end

return Animal
