--!strict
-- Riding controls: steering rules (designer approved 2026-11-20) and riding config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SteerInput = require(Shared:WaitForChild("Rules"):WaitForChild("SteerInput"))
local Config = Shared:WaitForChild("Config")
local CourseConfig = require(Config:WaitForChild("CourseConfig"))
local MountConfig = require(Config:WaitForChild("MountConfig"))

local DEADZONE = CourseConfig.SteerStickDeadzone

local function sources(overrides: { [string]: any }): SteerInput.Sources
	local s: { [string]: any } = {
		Riding = true,
		KeyboardLeft = false,
		KeyboardRight = false,
		DPadLeft = false,
		DPadRight = false,
		StickX = 0,
		TouchLeft = false,
		TouchRight = false,
	}
	for key, value in overrides do
		s[key] = value
	end
	return s :: any
end

local function steer(overrides: { [string]: any }): number
	return SteerInput.Resolve(sources(overrides), DEADZONE)
end

return function(t)
	t.test("each source steers on its own: keyboard, D-pad and touch at full strength", function()
		t.eq(steer({ KeyboardLeft = true }), -1)
		t.eq(steer({ KeyboardRight = true }), 1)
		t.eq(steer({ DPadLeft = true }), -1)
		t.eq(steer({ DPadRight = true }), 1)
		t.eq(steer({ TouchLeft = true }), -1)
		t.eq(steer({ TouchRight = true }), 1)
		t.eq(steer({}), 0, "nothing held")
	end)

	t.test("the stick steers by how far it is pushed, ignoring the deadzone", function()
		t.near(steer({ StickX = 0.6 }), 0.6, 1e-9)
		t.near(steer({ StickX = -0.75 }), -0.75, 1e-9)
		t.eq(steer({ StickX = DEADZONE * 0.5 }), 0, "inside the deadzone")
		t.eq(steer({ StickX = -DEADZONE }), 0, "exactly at the deadzone")
		t.eq(steer({ StickX = 3 }), 1, "clamped")
		t.eq(steer({ StickX = 0 / 0 }), 0, "NaN ignored")
	end)

	t.test("the same direction from several devices counts once and never exceeds full", function()
		t.eq(steer({ KeyboardRight = true, DPadRight = true, TouchRight = true }), 1)
		t.eq(steer({ KeyboardLeft = true, StickX = -0.4 }), -1, "digital + stick same way = full")
		t.eq(steer({ TouchLeft = true, StickX = -1 }), -1)
	end)

	t.test("opposite directions held at once give zero steering", function()
		t.eq(steer({ KeyboardLeft = true, KeyboardRight = true }), 0, "A + D")
		t.eq(steer({ TouchLeft = true, TouchRight = true }), 0, "both mobile buttons")
		t.eq(steer({ DPadLeft = true, KeyboardRight = true }), 0, "D-pad left + D key")
		t.eq(steer({ KeyboardLeft = true, StickX = 0.8 }), 0, "A + stick right")
		t.eq(steer({ TouchRight = true, StickX = -0.5 }), 0, "touch right + stick left")
	end)

	t.test("no steering at all when not riding, whatever is held", function()
		t.eq(steer({ Riding = false, KeyboardLeft = true }), 0)
		t.eq(steer({ Riding = false, TouchRight = true }), 0)
		t.eq(steer({ Riding = false, StickX = -1 }), 0)
	end)

	t.test("riding config: placeholder mount name and a configurable Ride animation id", function()
		t.eq(MountConfig.TestMountName, "Test Mount")
		local id = (MountConfig :: any).RideAnimationId
		t.truthy(id == nil or (typeof(id) == "number" and id > 0 and id % 1 == 0), "nil until a Ride animation is published")
	end)
end
