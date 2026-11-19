--!strict
-- Taming meter checked against design doc section 2.G.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TamingMeter = require(Shared:WaitForChild("Rules"):WaitForChild("TamingMeter"))

local EPS = 1e-9

return function(t)
	t.test("drain rates: 0-2 stars 3/s, 3-5 stars 5/s, Gold/Rainbow +10 stacking", function()
		for stars = 0, 2 do
			t.eq(TamingMeter.DrainPerSecond(stars, "Normal"), 3, `{stars} stars normal`)
		end
		for stars = 3, 5 do
			t.eq(TamingMeter.DrainPerSecond(stars, "Normal"), 5, `{stars} stars normal`)
		end
		t.eq(TamingMeter.DrainPerSecond(0, "Gold"), 13, "0-star Gold")
		t.eq(TamingMeter.DrainPerSecond(5, "Gold"), 15, "5-star Gold")
		t.eq(TamingMeter.DrainPerSecond(5, "Rainbow"), 15, "5-star Rainbow")
	end)

	t.test("starts at 50% and does not drain during the 1.5 s grace period", function()
		local state = TamingMeter.new(5, "Rainbow")
		t.eq(state.Percent, 50)
		TamingMeter.Advance(state, 1.5)
		t.near(state.Percent, 50, EPS)
	end)

	t.test("drains continuously after grace, including a step that crosses it", function()
		local state = TamingMeter.new(0, "Normal") -- 3/s
		TamingMeter.Advance(state, 1.0)
		TamingMeter.Advance(state, 1.0) -- 0.5 s of this step is after grace
		t.near(state.Percent, 50 - 1.5, EPS)
		TamingMeter.Advance(state, 2.0)
		t.near(state.Percent, 50 - 1.5 - 6, EPS)
	end)

	t.test("correct input +25; reaching 100% tames and caps at 100", function()
		local state = TamingMeter.new(1, "Normal")
		t.truthy(TamingMeter.Input(state, true))
		t.eq(state.Percent, 75)
		t.eq(state.Result, nil)
		TamingMeter.Input(state, true)
		t.eq(state.Percent, 100)
		t.eq(state.Result, "Tamed")
	end)

	t.test("only one mistake counts per prompt; it resets after a correct input", function()
		local state = TamingMeter.new(1, "Normal")
		t.truthy(TamingMeter.Input(state, false), "first mistake counts")
		t.eq(state.Percent, 35)
		t.eq(TamingMeter.Input(state, false), false, "second mistake on same prompt ignored")
		t.eq(state.Percent, 35)
		TamingMeter.Input(state, true) -- next prompt
		t.eq(state.Percent, 60)
		t.truthy(TamingMeter.Input(state, false), "mistake on the new prompt counts")
		t.eq(state.Percent, 45)
	end)

	t.test("reaching 0% throws the player off; nothing changes after a result", function()
		local state = TamingMeter.new(5, "Gold") -- 15/s
		TamingMeter.Advance(state, 1.5 + 50 / 15 + 0.01)
		t.eq(state.Percent, 0)
		t.eq(state.Result, "Failed")
		t.eq(TamingMeter.Input(state, true), false)
		t.eq(state.Percent, 0)
	end)

	t.test("a mistake that drops the meter to 0 fails the tame", function()
		local state = TamingMeter.new(0, "Normal")
		TamingMeter.Advance(state, 1.5 + 35 / 3) -- down to 15%
		t.near(state.Percent, 15, 1e-6)
		TamingMeter.Input(state, false)
		t.eq(state.Result, "Failed")
	end)

	t.test("prompts are only Up/Down/Left/Right and all four appear", function()
		local rng = Random.new(5)
		local seen = {}
		for _ = 1, 400 do
			local direction = TamingMeter.RollDirection(rng)
			t.truthy(
				direction == "Up" or direction == "Down" or direction == "Left" or direction == "Right",
				`unexpected direction {direction}`
			)
			seen[direction] = true
		end
		t.truthy(seen.Up and seen.Down and seen.Left and seen.Right, "all four directions should appear")
	end)
end
