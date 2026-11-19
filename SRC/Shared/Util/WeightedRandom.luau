--!strict
--[[
	WeightedRandom
	Picks one entry by weight using a given Random object.

	Entries are an ARRAY, never a dictionary: dictionary iteration order is not
	guaranteed, and a seeded run must make the same picks in the same order every time.
]]

local Validate = require(script.Parent:WaitForChild("Validate"))

export type Entry<T> = { value: T, weight: number }

local WeightedRandom = {}

function WeightedRandom.Pick<T>(rng: Random, entries: { Entry<T> }): T
	local total = 0
	for index, entry in entries do
		assert(
			Validate.IsFiniteNumber(entry.weight) and entry.weight >= 0,
			`invalid weight {tostring(entry.weight)} at entry {index}: weights must be finite numbers >= 0`
		)
		total += entry.weight
	end
	assert(total > 0, "weights must add up to more than 0")

	local roll = rng:NextNumber() * total -- [0, total)
	for _, entry in entries do
		if roll < entry.weight then
			return entry.value
		end
		roll -= entry.weight
	end

	-- Floating-point rounding can leave a tiny remainder: fall back to the last non-zero entry.
	for index = #entries, 1, -1 do
		if entries[index].weight > 0 then
			return entries[index].value
		end
	end
	error("unreachable")
end

return WeightedRandom
