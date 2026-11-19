--!strict
-- Star/variant/species rolls checked against design doc section 2.D (+ 3-5 star boost decision).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rules"):WaitForChild("Rarity"))

local EPS = 1e-9
local SIM_ROLLS = 200000

-- Allowed deviation for a simulated percentage: 4 standard deviations.
local function tolerance(percent: number, n: number): number
	local p = percent / 100
	return 4 * math.sqrt(p * (1 - p) / n) * 100
end

return function(t)
	t.test("segment multipliers: start 1, then 1, 1.25, 1.5, 1.75, 2, capped at 2", function()
		local expected = { [0] = 1, [1] = 1, [2] = 1.25, [3] = 1.5, [4] = 1.75, [5] = 2, [6] = 2, [20] = 2 }
		for segment, value in expected do
			t.eq(Rarity.SegmentMultiplier(segment), value, `segment {segment}`)
		end
	end)

	t.test("1x odds equal the locked baseline 50/25/14/8/2.5/0.5", function()
		local odds = Rarity.StarOdds(1)
		local baseline = { [0] = 50, [1] = 25, [2] = 14, [3] = 8, [4] = 2.5, [5] = 0.5 }
		for stars = 0, 5 do
			t.near(odds[stars], baseline[stars], EPS, `{stars} stars`)
		end
	end)

	t.test("2x odds boost 3-5 stars only, then normalize (45.0/22.5/12.6/14.4/4.5/0.9)", function()
		local odds = Rarity.StarOdds(2)
		local total = 50 + 25 + 14 + 16 + 5 + 1 -- 111
		local expected = { [0] = 50, [1] = 25, [2] = 14, [3] = 16, [4] = 5, [5] = 1 }
		for stars = 0, 5 do
			t.near(odds[stars], expected[stars] / total * 100, EPS, `{stars} stars`)
		end
	end)

	t.test("every multiplier's odds sum to 100 and keep 0-2 star ratios", function()
		for segment = 0, 5 do
			local odds = Rarity.StarOdds(Rarity.SegmentMultiplier(segment))
			local sum = 0
			for stars = 0, 5 do
				sum += odds[stars]
			end
			t.near(sum, 100, 1e-6, `sum at segment {segment}`)
			t.near(odds[0] / odds[1], 2, EPS, `0:1 star ratio at segment {segment}`)
			t.near(odds[0] / odds[2], 50 / 14, EPS, `0:2 star ratio at segment {segment}`)
		end
	end)

	t.test("rarer stars get more likely in each later segment", function()
		local previous = Rarity.StarOdds(1)
		for segment = 2, 5 do
			local odds = Rarity.StarOdds(Rarity.SegmentMultiplier(segment))
			t.truthy(odds[5] > previous[5], `5 stars should rise at segment {segment}`)
			t.truthy(odds[0] < previous[0], `0 stars should fall at segment {segment}`)
			previous = odds
		end
	end)

	t.test("multipliers outside 1..2 are rejected", function()
		t.errors(function()
			Rarity.StarOdds(3)
		end, "between 1 and 2")
		t.errors(function()
			Rarity.StarOdds(0.5)
		end, "between 1 and 2")
	end)

	t.test(`simulated star rolls match odds at 1x and 2x ({SIM_ROLLS} rolls each)`, function()
		for _, multiplier in { 1, 2 } do
			local rng = Random.new(12345)
			local counts = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
			for _ = 1, SIM_ROLLS do
				local stars = Rarity.RollStars(rng, multiplier)
				counts[stars] += 1
			end
			local odds = Rarity.StarOdds(multiplier)
			for stars = 0, 5 do
				local percent = counts[stars] / SIM_ROLLS * 100
				t.near(percent, odds[stars], tolerance(odds[stars], SIM_ROLLS), `{multiplier}x, {stars} stars`)
			end
		end
	end)

	t.test(`simulated variant rolls match 97 / 2.5 / 0.5 ({SIM_ROLLS} rolls)`, function()
		local rng = Random.new(777)
		local counts = { Normal = 0, Gold = 0, Rainbow = 0 }
		for _ = 1, SIM_ROLLS do
			local variant = Rarity.RollVariant(rng)
			counts[variant] += 1
		end
		for variant, percent in { Normal = 97, Gold = 2.5, Rainbow = 0.5 } do
			t.near(counts[variant] / SIM_ROLLS * 100, percent, tolerance(percent, SIM_ROLLS), variant)
		end
	end)

	t.test("variant stat multipliers: Normal 1, Gold 1.25, Rainbow 1.75; unknown variant errors", function()
		t.eq(Rarity.VariantStatMultiplier("Normal"), 1)
		t.eq(Rarity.VariantStatMultiplier("Gold"), 1.25)
		t.eq(Rarity.VariantStatMultiplier("Rainbow"), 1.75)
		t.errors(function()
			Rarity.VariantStatMultiplier("Silver")
		end, "Silver")
	end)

	t.test("the same seed reproduces the same rolls", function()
		local function sequence(seed: number): string
			local rng = Random.new(seed)
			local parts = {}
			for i = 1, 200 do
				table.insert(parts, `{Rarity.RollStars(rng, Rarity.SegmentMultiplier(i % 6))}{Rarity.RollVariant(rng)}`)
				table.insert(parts, Rarity.RollSpecies(rng, { Deer = 3, Rabbit = 5, Fox = 1 }))
			end
			return table.concat(parts, ",")
		end
		t.eq(sequence(42), sequence(42), "same seed")
		t.truthy(sequence(42) ~= sequence(43), "different seeds should differ")
	end)

	t.test("species roll respects weights and never picks a zero weight", function()
		local rng = Random.new(99)
		local counts = { A = 0, B = 0, Never = 0 }
		for _ = 1, 30000 do
			local id = Rarity.RollSpecies(rng, { A = 1, B = 3, Never = 0 })
			counts[id] += 1
		end
		t.eq(counts.Never, 0, "zero-weight species")
		t.near(counts.B / 30000, 0.75, 0.02, "B share")
	end)
end
