--!strict
-- Invalid inputs must fail loudly; finished tames must not change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = Shared:WaitForChild("Rules")
local Util = Shared:WaitForChild("Util")
local WeightedRandom = require(Util:WaitForChild("WeightedRandom"))
local Validate = require(Util:WaitForChild("Validate"))
local Stamina = require(Rules:WaitForChild("Stamina"))
local Speed = require(Rules:WaitForChild("Speed"))
local LevelScaling = require(Rules:WaitForChild("LevelScaling"))
local Income = require(Rules:WaitForChild("Income"))
local TamingMeter = require(Rules:WaitForChild("TamingMeter"))
local Animal = require(Shared:WaitForChild("Types"):WaitForChild("Animal"))

local NAN = 0 / 0
local INF = math.huge

return function(t)
	t.test("Validate.IsFiniteNumber rejects NaN, infinity and non-numbers", function()
		t.truthy(Validate.IsFiniteNumber(0))
		t.truthy(Validate.IsFiniteNumber(-3.5))
		t.eq(Validate.IsFiniteNumber(NAN), false, "NaN")
		t.eq(Validate.IsFiniteNumber(INF), false, "+inf")
		t.eq(Validate.IsFiniteNumber(-INF), false, "-inf")
		t.eq(Validate.IsFiniteNumber("5"), false, "string")
		t.eq(Validate.IsFiniteNumber(nil), false, "nil")
		t.eq(Validate.IsInteger(2.5), false, "2.5 is not an integer")
	end)

	t.test("weighted pick rejects NaN, infinite, negative and non-number weights", function()
		local rng = Random.new(1)
		for _, bad in { NAN, INF, -INF, -1, "3" :: any } do
			t.errors(function()
				WeightedRandom.Pick(rng, { { value = "a", weight = 1 }, { value = "b", weight = bad } })
			end, "invalid weight")
		end
	end)

	t.test("weighted pick rejects finite weights whose total overflows to infinity", function()
		local rng = Random.new(1)
		local big = 1e308
		t.truthy(Validate.IsFiniteNumber(big), "each weight is finite on its own")
		t.errors(function()
			WeightedRandom.Pick(rng, { { value = "a", weight = big }, { value = "b", weight = big } })
		end, "not finite")
	end)

	t.test("weighted pick rejects all-zero weights and an empty list", function()
		local rng = Random.new(1)
		t.errors(function()
			WeightedRandom.Pick(rng, { { value = "a", weight = 0 }, { value = "b", weight = 0 } })
		end, "more than 0")
		t.errors(function()
			WeightedRandom.Pick(rng, {})
		end, "more than 0")
	end)

	t.test("stamina rejects zero, negative, NaN and infinite consumption rates", function()
		for _, bad in { 0, -0.5, NAN, INF } do
			t.errors(function()
				Stamina.Cost(100, bad)
			end, "staminaPerStud")
			t.errors(function()
				Stamina.MaxDistance(100, bad)
			end, "staminaPerStud")
		end
	end)

	t.test("stamina rejects NaN/infinite distances and stamina amounts", function()
		t.errors(function()
			Stamina.Cost(NAN, 0.2)
		end, "distance")
		t.errors(function()
			Stamina.MaxDistance(INF, 0.2)
		end, "stamina")
	end)

	t.test("max stamina and speed reject invalid base, multiplier and level", function()
		t.errors(function()
			Stamina.Max(-1, 1, 1)
		end, "baseStamina")
		t.errors(function()
			Stamina.Max(NAN, 1, 1)
		end, "baseStamina")
		t.errors(function()
			Stamina.Max(100, 0, 1)
		end, "variantMultiplier")
		t.errors(function()
			Stamina.Max(100, 1, 2.5)
		end, "level")
		t.errors(function()
			Stamina.Max(100, 1, 0)
		end, "level")
		t.errors(function()
			Speed.Max(-32, 1, 1)
		end, "baseSpeed")
		t.errors(function()
			Speed.Max(32, INF, 1)
		end, "variantMultiplier")
		t.errors(function()
			Speed.Max(32, 1, NAN)
		end, "level")
	end)

	t.test("level growth rejects invalid growth rates", function()
		for _, bad in { -0.01, NAN, INF } do
			t.errors(function()
				LevelScaling.Apply("baseStamina", 100, 1, 2, bad)
			end, "growth per level")
		end
	end)

	t.test("invalid star ratings are rejected everywhere", function()
		for _, bad in { -1, 6, 2.5, NAN } do
			t.errors(function()
				Income.StarMultiplier(bad)
			end)
			t.errors(function()
				TamingMeter.new(bad, "Normal")
			end)
			t.errors(function()
				Animal.MaxLevel(bad)
			end)
			t.eq(
				(Animal.ValidateTraits({ Species = "TestCritter", Stars = bad, Variant = "Normal", BiomeCaught = "Plains" })),
				false,
				`ValidateTraits with {tostring(bad)} stars`
			)
		end
	end)

	t.test("unknown variants are rejected by the taming meter", function()
		t.errors(function()
			TamingMeter.new(2, "Silver")
		end, "variant")
	end)

	t.test("after a successful tame, inputs and time change nothing", function()
		local state = TamingMeter.new(0, "Normal")
		TamingMeter.Input(state, true)
		TamingMeter.Input(state, true)
		t.eq(state.Result, "Tamed")
		t.eq(TamingMeter.Input(state, true), false, "correct input after success")
		t.eq(TamingMeter.Input(state, false), false, "wrong input after success")
		TamingMeter.Advance(state, 30)
		t.eq(state.Percent, 100, "no drain after success")
		t.eq(state.Result, "Tamed")
	end)

	t.test("after a failed tame, inputs and time change nothing", function()
		local state = TamingMeter.new(5, "Rainbow")
		TamingMeter.Advance(state, 60)
		t.eq(state.Result, "Failed")
		t.eq(TamingMeter.Input(state, false), false, "wrong input after failure")
		t.eq(TamingMeter.Input(state, true), false, "correct input after failure")
		TamingMeter.Advance(state, 5)
		t.eq(state.Percent, 0)
		t.eq(state.Result, "Failed")
	end)

	t.test("the taming clock rejects NaN and infinite time steps", function()
		local state = TamingMeter.new(1, "Normal")
		t.errors(function()
			TamingMeter.Advance(state, NAN)
		end, "dt")
		t.errors(function()
			TamingMeter.Advance(state, INF)
		end, "dt")
		t.eq(state.Percent, 50, "meter unchanged by rejected steps")
	end)
end
