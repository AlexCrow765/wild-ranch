--!strict
--[[
	SteerInput
	Pure rule for turning raw device input into one steering value (designer approved 2026-11-20).

	  -1 = full left, +1 = full right, 0 = none.

	- Sources: keyboard (A/D and Left/Right arrows), gamepad D-pad, gamepad left stick, the two
	  on-screen mobile buttons.
	- The same direction from several sources counts once and never exceeds full steering.
	- Opposite directions held at the same time give ZERO steering (no most-recent-input priority).
	- When the player is not riding, steering is always 0, so nothing can carry into a later run.
	- Digital sources steer at full strength; the stick alone steers by how far it is pushed.
]]

export type Sources = {
	Riding: boolean,
	KeyboardLeft: boolean,
	KeyboardRight: boolean,
	DPadLeft: boolean,
	DPadRight: boolean,
	StickX: number, -- -1 .. 1
	TouchLeft: boolean,
	TouchRight: boolean,
}

local SteerInput = {}

function SteerInput.Resolve(sources: Sources, stickDeadzone: number): number
	if not sources.Riding then
		return 0
	end

	local stickX = math.clamp(if sources.StickX == sources.StickX then sources.StickX else 0, -1, 1)
	local stickLeft = stickX < -stickDeadzone
	local stickRight = stickX > stickDeadzone

	local digitalLeft = sources.KeyboardLeft or sources.DPadLeft or sources.TouchLeft
	local digitalRight = sources.KeyboardRight or sources.DPadRight or sources.TouchRight
	local wantsLeft = digitalLeft or stickLeft
	local wantsRight = digitalRight or stickRight

	if wantsLeft and wantsRight then
		return 0 -- opposite directions cancel
	elseif wantsLeft then
		return if digitalLeft then -1 else stickX
	elseif wantsRight then
		return if digitalRight then 1 else stickX
	end
	return 0
end

return SteerInput
