--!strict
-- Income, stamina and mount level caps checked against design doc sections 2.F and 2.H.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = Shared:WaitForChild("Rules")
local Income = require(Rules:WaitForChild("Income"))
local Stamina = require(Rules:WaitForChild("Stamina"))
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
		-- e.g. base 10, Gold (2x), 4 stars (2x), biome 1.5x
		t.near(Income.PerSecond(10, 2, 4, 1.5), 60, EPS)
		t.near(Income.PerSecond(7, 1, 0, 1), 7, EPS)
	end)

	t.test("income for a real animal fails loudly while base income is undecided", function()
		t.errors(function()
			Income.ForAnimal({ Species = "TestCritter", Stars = 2, Variant = "Normal", BiomeCaught = "Plains" })
		end, "OPEN QUESTION")
	end)

	t.test("max stamina = base x variant + fixed bonus per level above 1", function()
		t.eq(Stamina.Max(100, 1, 1, 10), 100, "level 1 has no bonus")
		t.eq(Stamina.Max(100, 1, 5, 10), 140, "4 levels x 10")
		t.eq(Stamina.Max(100, 2, 5, 10), 240, "Gold doubles base only")
		t.errors(function()
			Stamina.Max(100, 1, 0, 10)
		end)
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
