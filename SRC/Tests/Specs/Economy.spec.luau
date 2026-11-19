--!strict
-- Income, speed, stamina, course dimensions and mount level caps, checked against the design
-- notes (2.F, 2.H) and the designer decisions of 2026-11-18 recorded in ARCHITECTURE.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = Shared:WaitForChild("Rules")
local Config = Shared:WaitForChild("Config")
local Income = require(Rules:WaitForChild("Income"))
local Stamina = require(Rules:WaitForChild("Stamina"))
local Speed = require(Rules:WaitForChild("Speed"))
local Rarity = require(Rules:WaitForChild("Rarity"))
local CourseConfig = require(Config:WaitForChild("CourseConfig"))
local MountConfig = require(Config:WaitForChild("MountConfig"))
local Animal = require(Shared:WaitForChild("Types"):WaitForChild("Animal"))

local EPS = 1e-9

return function(t)
	t.test("star income multipliers 1 / 1.25 / 1.5 / 1.75 / 2 / 2.5", function()
		local expected = { [0] = 1, [1] = 1.25, [2] = 1.5, [3] = 1.75, [4] = 2, [5] = 2.5 }
		for stars = 0, 5 do
			t.eq(Income.StarMultiplier(stars), expected[stars], `{stars} stars`)
		end
	end)

	t.test("income formula = base x variant x star x biome", function()
		-- pure formula: base 10, variant multiplier 2, 4 stars (2x), biome 1.5x
		t.near(Income.PerSecond(10, 2, 4, 1.5), 60, EPS)
		t.near(Income.PerSecond(7, 1, 0, 1), 7, EPS)
	end)

	t.test("income for a real animal fails loudly while base income is undecided", function()
		t.errors(function()
			Income.ForAnimal({ Species = "TestCritter", Stars = 2, Variant = "Normal", BiomeCaught = "Plains" })
		end, "OPEN QUESTION")
	end)

	t.test("income uses the new variant multipliers (Gold 1.25x, Rainbow 1.75x)", function()
		-- base 10, 4 stars (2x), biome 1.5x
		t.near(Income.PerSecond(10, Rarity.VariantStatMultiplier("Gold"), 4, 1.5), 37.5, EPS)
		t.near(Income.PerSecond(10, Rarity.VariantStatMultiplier("Rainbow"), 4, 1.5), 52.5, EPS)
	end)

	t.test("max stamina = base x variant x (1 + 1% x (level - 1))", function()
		t.near(Stamina.Max(100, 1, 1), 100, EPS, "level 1 has no bonus")
		t.near(Stamina.Max(100, 1, 5), 104, EPS, "4 levels x 1%")
		t.near(Stamina.Max(100, 1, 11), 110, EPS, "additive, not compounded (compounded would be 110.46)")
		t.near(Stamina.Max(100, 1.25, 5), 130, EPS, "Gold applied before level bonus")
		t.near(Stamina.Max(100, 1.75, 50), 260.75, EPS, "Rainbow at level 50")
	end)

	t.test("speed = base x variant x (1 + 0.1% x (level - 1))", function()
		t.near(Speed.Max(32, 1, 1), 32, EPS, "level 1 has no bonus")
		t.near(Speed.Max(32, 1, 11), 32.32, EPS, "10 levels x 0.1%")
		t.near(Speed.Max(32, 1.25, 1), 40, EPS, "Gold")
		t.near(Speed.Max(32, 1.75, 50), 32 * 1.75 * 1.049, EPS, "Rainbow at level 50")
	end)

	t.test("speed and stamina for a real animal fail loudly while base stats are undecided", function()
		local animal = { Species = "TestCritter", Variant = "Gold", Level = 1 }
		t.errors(function()
			Speed.ForAnimal(animal)
		end, "OPEN QUESTION")
		t.errors(function()
			Stamina.ForAnimal(animal)
		end, "OPEN QUESTION")
	end)

	t.test("course config matches the approved dimensions", function()
		t.eq(CourseConfig.SegmentsPerBiome, 5)
		t.eq(CourseConfig.BaselineRidingSpeed, 32)
		t.eq(CourseConfig.SegmentLengthStuds, CourseConfig.BaselineRidingSpeed * CourseConfig.SegmentTargetSeconds, "576 = 32 x 18")
		t.eq(CourseConfig.BiomeLengthStuds, CourseConfig.SegmentsPerBiome * CourseConfig.SegmentLengthStuds, "2,880 = 5 x 576")
		t.eq(CourseConfig.BiomeLengthStuds / CourseConfig.BaselineRidingSpeed, 90, "about 90 s per biome")
		t.truthy(CourseConfig.CorridorWidthStuds - 2 * CourseConfig.MaxBushWidthStuds >= 74, "playable centre >= 74 studs")
		t.eq(CourseConfig.MinAnimalsPerSegment, 1)
		t.eq(CourseConfig.MaxAnimalsPerSegment, 3)
	end)

	t.test("test mount (100 stamina) reaches ~864 studs, about halfway through Segment 2", function()
		local reach = Stamina.MaxDistance(MountConfig.TestMountStamina, MountConfig.StaminaPerStud)
		t.near(reach, 864, 1e-6, "reach in studs")
		t.near(reach / CourseConfig.SegmentLengthStuds, 1.5, 1e-9, "1.5 segments = mid Segment 2")
		t.near(reach / CourseConfig.BaselineRidingSpeed, 27, 1e-6, "about 27 s at 32 studs/s")
	end)

	t.test("stamina drains by distance and converts back to distance", function()
		t.eq(Stamina.Cost(500, 0.2), 100)
		t.eq(Stamina.MaxDistance(100, 0.2), 500)
		t.eq(Stamina.Cost(-10, 0.2), 0, "negative distance costs nothing")
	end)

	t.test("mount level caps by stars: 5 / 10 / 20 / 30 / 40 / 50", function()
		local expected = { [0] = 5, [1] = 10, [2] = 20, [3] = 30, [4] = 40, [5] = 50 }
		for stars = 0, 5 do
			t.eq(Animal.MaxLevel(stars), expected[stars], `{stars} stars`)
		end
	end)

	t.test("animal records: new animals start at level 1 in inventory; traits validated", function()
		local traits = { Species = "TestCritter", Stars = 3, Variant = "Gold", BiomeCaught = "Plains" }
		t.truthy(Animal.ValidateTraits(traits), "valid traits")
		local owned = Animal.NewOwned(traits :: any)
		t.eq(owned.Level, 1)
		t.eq(owned.Placed, false)
		t.truthy(Animal.ValidateOwned(owned), "valid owned record")
		t.eq((Animal.ValidateTraits({ Species = "TestCritter", Stars = 6, Variant = "Gold", BiomeCaught = "Plains" })), false)
		t.eq((Animal.ValidateTraits({ Species = "TestCritter", Stars = 3, Variant = "Gold", BiomeCaught = "Savannah" })), false)
		t.eq((Animal.ValidateOwned({ Species = "TestCritter", Stars = 0, Variant = "Normal", BiomeCaught = "Plains", Level = 6, Placed = false })), false)
	end)
end
