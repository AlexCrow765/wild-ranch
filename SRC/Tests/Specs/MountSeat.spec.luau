--!strict
-- Test-horse mount placement: Seat alignment and rider lift (MountSeat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MountSeat = require(Shared:WaitForChild("Rules"):WaitForChild("MountSeat"))
local MountConfig = require(Shared:WaitForChild("Config"):WaitForChild("MountConfig"))

local EPS = 1e-3 -- CFrames are 32-bit floats

return function(t)
	t.test("seat target sits seatDrop below the root, facing the same way", function()
		local root = CFrame.new(10, 8, -40) * CFrame.Angles(0, math.rad(30), 0)
		local target = MountSeat.SeatTarget(root, 2)
		t.near((target.Position - (root.Position - root.UpVector * 2)).Magnitude, 0, EPS)
		t.near(target.LookVector:Dot(root.LookVector), 1, EPS)
	end)

	t.test("aligned pivot puts the model's Seat exactly on the target", function()
		-- A model whose pivot is at its feet and whose Seat is 5.95 up and 0.3 back, facing -Z.
		local modelPivot = CFrame.new(100, 0, 100) * CFrame.Angles(0, math.rad(70), 0)
		local seatLocal = CFrame.new(0, 5.95, 0.3)
		local seatWorld = modelPivot * seatLocal
		local target = CFrame.new(-20, 12, 5) * CFrame.Angles(0, math.rad(-45), 0)
		local newPivot = MountSeat.AlignedPivot(modelPivot, seatWorld, target)
		local newSeat = newPivot * seatLocal -- the Seat moves rigidly with the model
		t.near((newSeat.Position - target.Position).Magnitude, 0, EPS, "seat position")
		t.near(newSeat.LookVector:Dot(target.LookVector), 1, EPS, "seat faces the riding direction")
		t.near(newSeat.UpVector:Dot(target.UpVector), 1, EPS, "seat upright")
	end)

	t.test("rider hip height puts the hooves on the ground", function()
		-- Seat 5.95 above the hooves, thighs 2 below the root centre, root half-height 1.
		local hipHeight = MountSeat.RiderHipHeight(5.95, 2, 1)
		t.near(hipHeight, 6.95, 1e-9)
		-- Root centre = hipHeight + rootHalf above the ground; seat = root - seatDrop = 5.95.
		t.near(hipHeight + 1 - 2, 5.95, 1e-9)
		t.eq(MountSeat.RiderHipHeight(0.5, 0, 1), 0, "never negative")
	end)

	t.test("test mount config names the horse model and its Seat attachment", function()
		t.eq(MountConfig.TestMountFolder, "Mounts")
		t.eq(MountConfig.TestMountModel, "TestHorse")
		t.eq(MountConfig.SeatAttachment, "Seat")
		t.eq(MountConfig.MountInstanceName, "TestMount")
		t.truthy(MountConfig.TestMountSeatDrop > 0)
	end)
end
