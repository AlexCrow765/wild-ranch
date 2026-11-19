--!strict
--[[
	Rarity
	Star, variant and species rolls (design doc section 2.D).

	- Segment index: 0 = starting area, 1..n = segments. Multipliers 1, 1, 1.25, 1.5, 1.75, 2;
	  capped at 2x (segments past the last configured one stay at the cap).
	- The multiplier is applied to 3-5 star weights only, then the distribution is normalized.
	- Variant is rolled independently and never receives the segment multiplier.

	Every roll takes the Random object to draw from, so the RunPlanner can pass one seeded
	Random and reproduce a whole run.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("RarityConfig"))
local WeightedRandom = require(Shared:WaitForChild("Util"):WaitForChild("WeightedRandom"))

local Rarity = {}

-- Star multiplier for a zone of a biome. 0 = starting area.
function Rarity.SegmentMultiplier(segment: number): number
	if segment <= 0 then
		return RarityConfig.StartingAreaStarMultiplier
	end
	local list = RarityConfig.SegmentStarMultipliers
	local multiplier = list[math.min(segment, #list)]
	return math.min(multiplier, RarityConfig.MaxStarMultiplier)
end

-- Star odds in percent, keyed 0..5, summing to 100, for a given multiplier.
function Rarity.StarOdds(multiplier: number): { [number]: number }
	assert(
		multiplier >= 1 and multiplier <= RarityConfig.MaxStarMultiplier,
		`star multiplier must be between 1 and {RarityConfig.MaxStarMultiplier}`
	)
	local odds = {}
	local total = 0
	for stars = RarityConfig.MinStars, RarityConfig.MaxStars do
		local weight = RarityConfig.StarBaseOdds[stars]
		if stars >= RarityConfig.MinBoostedStars then
			weight *= multiplier
		end
		odds[stars] = weight
		total += weight
	end
	for stars = RarityConfig.MinStars, RarityConfig.MaxStars do
		odds[stars] = odds[stars] / total * 100
	end
	return odds
end

function Rarity.RollStars(rng: Random, multiplier: number): number
	local odds = Rarity.StarOdds(multiplier)
	local entries: { WeightedRandom.Entry<number> } = {}
	for stars = RarityConfig.MinStars, RarityConfig.MaxStars do
		table.insert(entries, { value = stars, weight = odds[stars] })
	end
	return WeightedRandom.Pick(rng, entries)
end

function Rarity.RollVariant(rng: Random): string
	local entries: { WeightedRandom.Entry<string> } = {}
	for _, variant in RarityConfig.VariantOrder do
		table.insert(entries, { value = variant, weight = RarityConfig.VariantOdds[variant] })
	end
	return WeightedRandom.Pick(rng, entries)
end

-- Multiplier on a species' base stats for a variant. Errors while a value is undecided.
function Rarity.VariantStatMultiplier(variant: string): number
	local multiplier = (RarityConfig.VariantStatMultiplier :: any)[variant]
	assert(
		multiplier ~= nil,
		`OPEN QUESTION: no stat multiplier set for variant "{variant}" (Rainbow is 3x or 4x - designer to decide)`
	)
	return multiplier
end

-- Picks a species from {[speciesId] = weight}. Ids are sorted so a seed always gives the same pick.
function Rarity.RollSpecies(rng: Random, weights: { [string]: number }): string
	local ids = {}
	for id in weights do
		table.insert(ids, id)
	end
	table.sort(ids)
	local entries: { WeightedRandom.Entry<string> } = {}
	for _, id in ids do
		table.insert(entries, { value = id, weight = weights[id] })
	end
	return WeightedRandom.Pick(rng, entries)
end

return Rarity
