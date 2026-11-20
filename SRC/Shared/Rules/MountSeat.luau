--!strict
--[[
	MountSeat
	Pure maths for sitting a rider on a mount model (test horse now, real mounts in Phase 8).

	The rider's physics never change shape: the character keeps walking on its Humanoid. While
	riding we only (a) weld the mount so its "Seat" attachment sits where the rider's seated thighs
	are, and (b) raise the Humanoid's HipHeight so the mount's hooves reach the ground.

	Terms
	  seatDrop     how far below the root-part centre the seated thighs rest (MountConfig, tuned)
	  seatHeight   the Seat attachment's height above the bottom of the mount model (its hooves)
	  rootHalf     half the height of the rider's HumanoidRootPart
]]

local MountSeat = {}

-- Where the mount's Seat must be, in the world: under the rider's root, facing the same way.
function MountSeat.SeatTarget(rootCFrame: CFrame, seatDrop: number): CFrame
	return rootCFrame * CFrame.new(0, -seatDrop, 0)
end

-- New pivot for the mount model so that its Seat attachment (currently at seatWorld) lands
-- exactly on target, keeping the mount's shape: the whole model is moved and rotated together.
function MountSeat.AlignedPivot(modelPivot: CFrame, seatWorld: CFrame, target: CFrame): CFrame
	return target * seatWorld:Inverse() * modelPivot
end

-- HipHeight that puts the mount's hooves on the ground: the rider's root centre must sit at
-- seatHeight + seatDrop above the ground, and (R15) HipHeight is measured to the root's bottom.
function MountSeat.RiderHipHeight(seatHeight: number, seatDrop: number, rootHalf: number): number
	return math.max(0, seatHeight + seatDrop - rootHalf)
end

return MountSeat
